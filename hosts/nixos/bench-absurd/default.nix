# bench-absurd: Absurd bench guest (tieto goldmill/wiki/reviews/bench/
# phase0-hosting-absurd.md). No server exists — this guest runs the worker
# processes, the Habitat read-only dashboard, and the DIY glue (cleanup
# timer + queue-depth metrics into the node-exporter textfile collector).
#
# Schema 0.4.0 and the default/gpu queues are installed in bench-pg's
# `bench` database via absurdctl (see the phase-0 note). SDK and schema
# versions move in lockstep — pin 0.4.0 on both sides.
#
# Secret (out-of-repo, root-only): /root/bench-secrets.env with
# ABSURD_DATABASE_URL=postgresql://absurd:...@dogmatix:5432/bench
{ pkgs, ... }:

let
  habitat = pkgs.stdenv.mkDerivation {
    pname = "habitat";
    version = "0.4.0";
    src = pkgs.fetchurl {
      url = "https://github.com/earendil-works/absurd/releases/download/0.4.0/habitat-linux-x86_64";
      sha256 = "0lag797pckcv6f3cy2dd1kqp37ib0g3irwz0y7b5l720jcz3az7c";
    };
    dontUnpack = true;
    # Release binary is built against glibc paths NixOS does not have.
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    installPhase = ''
      install -Dm755 $src $out/bin/habitat
    '';
  };

  workerPy = pkgs.writeText "bench-worker.py" ''
    """Minimal bench worker: no-op + sleep tasks, keeps lease sweeps alive."""
    import os
    import sys
    import time

    from absurd_sdk import Absurd

    queue = sys.argv[1] if len(sys.argv) > 1 else "default"
    app = Absurd(os.environ["ABSURD_DATABASE_URL"])

    @app.register_task(name="bench-noop", queue=queue)
    def bench_noop(params, ctx):
        return {"ok": True, "queue": queue, "params": params}

    @app.register_task(name="bench-sleep", queue=queue)
    def bench_sleep(params, ctx):
        step = ctx.run_step

        @step("sleep")
        def s():
            time.sleep(float(params.get("seconds", 1)))
            return {"slept": params.get("seconds", 1)}

        return s

    app.start_worker()
  '';

  workerService = queue: {
    description = "Absurd bench worker (${queue} queue)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.python3 ];
    serviceConfig = {
      EnvironmentFile = "/root/bench-secrets.env";
      DynamicUser = true;
      StateDirectory = "absurd-worker-${queue}";
      Restart = "always";
      RestartSec = 5;
    };
    # absurd-sdk is not in nixpkgs; a per-service venv (pinned version)
    # is the pragmatic bench-scoped impurity. Revisit if Absurd wins.
    preStart = ''
      VENV="$STATE_DIRECTORY/venv"
      if [ ! -x "$VENV/bin/python" ]; then
        ${pkgs.python3}/bin/python3 -m venv "$VENV"
        "$VENV/bin/pip" install --quiet 'absurd-sdk==0.4.0'
      fi
    '';
    script = ''
      exec "$STATE_DIRECTORY/venv/bin/python" ${workerPy} ${queue}
    '';
  };

  queueMetrics = pkgs.writeShellScript "absurd-queue-metrics" ''
    set -eu
    OUT=/var/lib/node-exporter-textfile/absurd.prom
    TMP="$OUT.tmp"
    : > "$TMP"
    for q in default gpu; do
      ${pkgs.postgresql}/bin/psql "$ABSURD_DATABASE_URL" -Atc "
        select
          coalesce(count(*) filter (where r.state in ('pending','sleeping')
            and r.available_at <= now()), 0),
          coalesce(extract(epoch from now() - min(r.available_at)
            filter (where r.state in ('pending','sleeping')
              and r.available_at <= now())), 0)
        from absurd.r_$q r
        join absurd.t_$q t using (task_id)
        where t.state in ('pending','sleeping','running')
      " | while IFS='|' read -r depth oldest; do
        echo "absurd_queue_depth{queue=\"$q\"} $depth" >> "$TMP"
        echo "absurd_queue_oldest_pending_seconds{queue=\"$q\"} $oldest" >> "$TMP"
      done
    done
    mv "$TMP" "$OUT"
  '';
in
{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-absurd";

  environment.systemPackages = [ pkgs.postgresql ]; # psql for glue/debug

  systemd.services.absurd-worker-default = workerService "default";
  systemd.services.absurd-worker-gpu = workerService "gpu";

  # Read-only dashboard; no auth exists — tailnet-only via firewall trust.
  # The env file carries HABITAT_DB_URL alongside ABSURD_DATABASE_URL
  # (same DSN, Habitat's expected variable name).
  systemd.services.habitat = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      EnvironmentFile = "/root/bench-secrets.env";
      ExecStart = "${habitat}/bin/habitat run -listen :7890";
      DynamicUser = true;
      Restart = "on-failure";
    };
  };

  # Queue depth + oldest-pending into the textfile collector — this is the
  # wake-on-LAN signal (event-waiting tasks with future timeouts excluded
  # by the available_at filter).
  systemd.services.absurd-queue-metrics = {
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/root/bench-secrets.env";
    };
    script = "exec ${queueMetrics}";
  };
  systemd.timers.absurd-queue-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "1min"; OnUnitActiveSec = "30s"; };
  };

  # Terminal-state cleanup per queue policy.
  systemd.services.absurd-cleanup = {
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/root/bench-secrets.env";
    };
    script = ''
      ${pkgs.postgresql}/bin/psql "$ABSURD_DATABASE_URL" \
        -c "select * from absurd.cleanup_all_queues()"
    '';
  };
  systemd.timers.absurd-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "hourly"; Persistent = true; };
  };
}
