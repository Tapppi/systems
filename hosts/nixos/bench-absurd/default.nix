# bench-absurd: Absurd bench guest (tieto goldmill/wiki/reviews/bench/
# phase0-hosting-absurd.md). No server exists — this guest runs the worker
# processes, the Habitat read-only dashboard, and the DIY glue (cleanup
# timer + queue-depth metrics into the node-exporter textfile collector).
#
# Schema 0.4.0 and the default/gpu queues are installed in bench-pg's
# `bench` database via absurdctl (see the phase-0 note). SDK and schema
# versions move in lockstep — pin 0.4.0 on both sides.
#
# Secrets (out-of-repo, root-only): /root/bench-secrets.env carries
# ABSURD_DATABASE_URL=postgresql://absurd:...@dogmatix:5432/bench for the SDK
# and Habitat, plus the same credentials as libpq's own PGHOST/PGPORT/PGUSER/
# PGPASSWORD/PGDATABASE for the psql timers. psql takes them from the
# environment rather than a DSN argument because argv is world-readable and
# the DynamicUser workers on this guest could read it.
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
    """Minimal bench worker: no-op, sleep and HITL tasks; keeps lease sweeps
    alive.

    Everything runnable on the `default` and `gpu` queues is registered here,
    in one registry per queue. That is a constraint, not a convenience: a
    worker claims task names it has no handler for and pushes them back with a
    delay of a minute or more instead of leaving them for a worker that does,
    so a second process registering different names on the same queue costs a
    random multiple of that delay per task."""
    import os
    import sys
    import time

    from absurd_sdk import Absurd

    queue = sys.argv[1] if len(sys.argv) > 1 else "default"
    # queue_name on the client is what the worker polls. register_task(queue=)
    # only tags where spawn() puts a task — it does not affect claiming, so a
    # worker built without queue_name silently polls "default" no matter what
    # its tasks are registered against.
    app = Absurd(os.environ["ABSURD_DATABASE_URL"], queue_name=queue)

    @app.register_task(name="bench-noop", queue=queue)
    def bench_noop(params, ctx):
        return {"ok": True, "queue": queue, "params": params}

    @app.register_task(name="bench-hitl-scoped", queue=queue)
    def bench_hitl_scoped(params, ctx):
        # The approval event name carries the job id. Absurd events are
        # permanent, so a fixed name is satisfied instantly and for all time by
        # the first emission ever made, and an approval for one job would
        # release every job parked after it.
        return {"ok": True,
                "approval": ctx.await_event("bench:approval:" + params["job"])}

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
    set -u
    . ${../../../modules/nixos/bench/poller-footer.sh}
    PSQL="${pkgs.postgresql}/bin/psql -Atq -v ON_ERROR_STOP=1"
    PREFIX=absurd
    OUT=/var/lib/node-exporter-textfile/absurd.prom
    TMP="$OUT.tmp"
    trap 'rm -f "$TMP"' EXIT
    ok=1
    {
      echo '# HELP absurd_queue_depth Runs claimable now, per queue.'
      echo '# TYPE absurd_queue_depth gauge'
      echo '# HELP absurd_queue_oldest_pending_seconds Age of the oldest claimable run.'
      echo '# TYPE absurd_queue_oldest_pending_seconds gauge'
      echo '# HELP absurd_run_oldest_running_seconds Age of the longest-running run.'
      echo '# TYPE absurd_run_oldest_running_seconds gauge'
      echo '# HELP absurd_run_expired_leases Running runs past their claim expiry.'
      echo '# TYPE absurd_run_expired_leases gauge'
      echo '# HELP absurd_tasks Tasks per queue and state.'
      echo '# TYPE absurd_tasks gauge'
    } > "$TMP"

    # Queues come from absurd.queues rather than a hand-kept list. A queue
    # that exists but is not enumerated has no depth series, and an absent
    # series is indistinguishable from an idle one — the same class of hole
    # as a worker polling a queue nobody watches.
    queues=$($PSQL -c "select queue_name from absurd.queues order by 1") || ok=0

    # All queues in one statement rather than one round trip each: psql spawn
    # plus TCP connect plus SCRAM costs an order of magnitude more than the
    # queries do, and this runs every 30 s against the shared database. The
    # SQL formats the exposition lines itself, which is why there is no
    # parsing here at all — the alternative was a key-tagged union and a case
    # dispatch whose positional fields meant different things per branch.
    #
    # `depth` is the wake-on-LAN signal: event-waiting runs with a future
    # available_at are deliberately excluded, so a legitimately parked task
    # reads as 0. Task states are zero-filled from a fixed list, so `failed`
    # is a series that exists and reads 0 rather than one that springs into
    # existence on the first failure.
    ctes= ; body=
    for q in $queues; do
      ctes="''${ctes:+$ctes,}
        pend_$q as (
          select r.available_at
          from absurd.r_$q r join absurd.t_$q t using (task_id)
          where t.state in ('pending','sleeping','running')
            and r.state in ('pending','sleeping')
            and r.available_at <= now()),
        runs_$q as (
          select r.started_at, r.claim_expires_at
          from absurd.r_$q r where r.state = 'running')"
      body="''${body:+$body union all}
        select format('absurd_queue_depth{queue=\"%s\"} %s', '$q',
          (select count(*) from pend_$q))
        union all select format('absurd_queue_oldest_pending_seconds{queue=\"%s\"} %s', '$q',
          (select coalesce(extract(epoch from now() - min(available_at)), 0)::numeric(20,3)
             from pend_$q))
        union all select format('absurd_run_oldest_running_seconds{queue=\"%s\"} %s', '$q',
          (select coalesce(extract(epoch from now() - min(started_at)), 0)::numeric(20,3)
             from runs_$q))
        union all select format('absurd_run_expired_leases{queue=\"%s\"} %s', '$q',
          (select count(*) from runs_$q where claim_expires_at < now()))
        union all select format('absurd_tasks{queue=\"%s\",state=\"%s\"} %s', '$q',
          s.state, coalesce(c.n, 0))
          from (values ('pending'),('sleeping'),('running'),
                       ('completed'),('failed'),('cancelled')) as s(state)
          left join (select state, count(*) n from absurd.t_$q group by state) c
            on c.state = s.state"
    done

    # Captured before writing: piping psql straight into the file would hide a
    # failed query behind the pipeline's exit status and publish a truncated
    # file, which reads as "nothing waiting".
    if [ -n "$body" ]; then
      rows=$($PSQL -c "with $ctes $body") && printf '%s\n' "$rows" >> "$TMP" || ok=0
    fi

    poller_footer
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
    wants = [ "network-online.target" ];
    serviceConfig = {
      EnvironmentFile = "/root/bench-secrets.env";
      ExecStart = "${habitat}/bin/habitat run -listen :7890";
      DynamicUser = true;
      Restart = "on-failure";
      RestartSec = 10;
    };
    # Habitat exits when it cannot reach the database, and the default
    # start-limit gives up permanently after five fast failures — so a
    # transient unreachable bridge during boot leaves the UI dead until
    # someone notices. Retry forever instead. StartLimit* live in [Unit].
    unitConfig.StartLimitIntervalSec = 0;
  };

  # Queue depth + oldest-pending into the textfile collector — this is the
  # wake-on-LAN signal (event-waiting tasks with future timeouts excluded
  # by the available_at filter).
  systemd.services.absurd-queue-metrics = {
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/root/bench-secrets.env";
      TimeoutStartSec = "20s";
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
      ${pkgs.postgresql}/bin/psql \
        -c "select * from absurd.cleanup_all_queues()"
    '';
  };
  systemd.timers.absurd-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "hourly"; Persistent = true; };
  };
}
