# bench-load: the Phase 6 soak guest (tieto goldmill/wiki/reviews/bench/
# phase6-soak.md). It carries every process that *produces* or *consumes*
# bench work for the multi-day soak — the engine workers and the three load
# drivers — and no engine of its own.
#
# It exists as a separate guest rather than as units on the engine guests for
# two reasons. The soak measures per-guest RSS growth per engine from the
# Incus cgroup metrics, so a worker or a driver charged to bench-temporal
# would be indistinguishable from Temporal's own growth — the figure the whole
# phase turns on. And the drivers are the one component here that is *meant*
# to be restarted and retuned mid-soak; keeping them off the engine guests
# means doing that never touches an engine.
#
# Python payload and secrets are **not** in this repo or the nix store. The
# bench client packages (benchlib, agentlib, compose) live in the tieto vault
# and are pushed to /var/lib/bench-soak/code alongside .pgsecrets and
# .hatchet-token, exactly as the engine guests receive their
# /root/bench-secrets.env. `soak-venv.service` builds the venv from the
# pushed requirements file on first boot and whenever that file changes.
#
#   tar -C <vault>/goldmill/wiki/reviews/bench -cz \
#       benchlib agentlib compose soak-requirements.txt .pgsecrets .hatchet-token \
#     | ssh dogmatix 'incus exec bench-load -- tar -C /var/lib/bench-soak/code -xz'
#   ssh dogmatix 'incus exec bench-load -- chown -R soak:soak /var/lib/bench-soak/code'
{ pkgs, lib, ... }:

let
  code = "/var/lib/bench-soak/code";
  venv = "/var/lib/bench-soak/venv";
  py = "${venv}/bin/python";

  # 3.13, not the default: the pinned wheel set in soak-requirements.txt is
  # the one the earlier phases measured, and it is a cp313 set.
  python = pkgs.python313;

  # PyPI wheels are manylinux binaries that expect a filesystem hierarchy
  # NixOS does not have. grpcio (Hatchet, Temporal) and psycopg-binary are the
  # ones that bite: they dlopen libstdc++ and libz at import time and fail with
  # "cannot open shared object file" that names no package. Every unit that
  # runs the venv needs this, including the one that only imports to check.
  wheelLibs = lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib pkgs.zlib pkgs.openssl ];

  # Everything here runs the same payload as the same user out of the same
  # directory; only the command differs. Shared so that a change to the
  # sandboxing or the restart policy cannot apply to eleven units and miss
  # the twelfth.
  # `restart` is "always" for everything that must survive the soak and "no"
  # for the load drivers, which run a bounded ramp and are done when it ends —
  # an always-restarted driver would start the next run on its own.
  soakUnit = { description, exec, extraEnv ? { }, after ? [ ], autostart ? true
             , restart ? "always" }: {
    inherit description;
    wantedBy = lib.optional autostart "multi-user.target";
    after = [ "network-online.target" "soak-venv.service" ] ++ after;
    wants = [ "network-online.target" ];
    requires = [ "soak-venv.service" ];
    environment = {
      PYTHONPATH = code;
      PYTHONUNBUFFERED = "1";
      HOME = "/var/lib/bench-soak";
      LD_LIBRARY_PATH = wheelLibs;
      # No collector is reachable from this guest. The compose adapters still
      # build their spans and still propagate context across the engine
      # boundary; they simply do not try to ship them, which over days is the
      # difference between clean journals and a retry storm per graph run.
      OTEL_TRACES_EXPORTER = "none";
    } // extraEnv;
    serviceConfig = {
      User = "soak";
      Group = "soak";
      WorkingDirectory = code;
      ExecStart = exec;
      Restart = restart;
      # Long enough that a genuinely broken unit does not spin against the
      # engines, short enough that a transient DB blip costs seconds.
      RestartSec = 15;
    };
    # A worker that crashloops must keep trying for the whole soak: the
    # default five-in-ten budget would retire it permanently during a host
    # reboot and leave a queue silently unserved — the failure mode the bench
    # has already paid for twice. StartLimit* live in [Unit], not [Service].
    unitConfig.StartLimitIntervalSec = 0;
  };
in
{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-load";

  # This guest is deliberately **not** on the tailnet, and reaches everything
  # over incusbr0 by static address instead.
  #
  # Phase 5 established that a Temporal worker's liveness is tied to the
  # tailnet resolver — the SDK re-resolves its target on every retry, so a
  # MagicDNS hiccup is a dead worker, not a slow one. A soak that runs for
  # days on workers with that dependency measures Tailscale as much as it
  # measures the engines. The engine↔Postgres path already avoids it for the
  # same reason; this guest extends that to the worker↔engine path, which it
  # can because it never roams.
  #
  # The names below are the ones benchlib and compose already use, so nothing
  # in the Python payload knows the difference. The addresses are pinned on
  # the Incus side (`incus config device override <guest> eth0
  # ipv4.address=…`), which is what makes them safe to hard-code.
  services.tailscale.enable = lib.mkForce false;
  networking.hosts = {
    "10.135.155.1" = [ "dogmatix" ];    # host proxies: pg 5432, hatchet 7077/8888
    "10.135.155.228" = [ "bench-temporal" ];
    "10.135.155.224" = [ "bench-obs" ];
    "10.135.155.246" = [ "bench-absurd" ];
  };
  # node-exporter, scraped by bench-obs over the bridge. The bridge is a
  # NAT-only network private to dogmatix; nothing off the host can reach it.
  networking.firewall.allowedTCPPorts = [ 9100 ];

  users.groups.soak = { };
  users.users.soak = {
    isSystemUser = true;
    group = "soak";
    home = "/var/lib/bench-soak";
  };

  # 0750: the payload directory holds .pgsecrets and .hatchet-token.
  #
  # The `z` line adjusts the textfile-collector directory guest-base creates
  # root-owned, so the drivers can publish their liveness there. It has to be
  # `z` and not a second `d`: two `d` lines for one path are a duplicate
  # tmpfiles entry whose winner depends on module merge order.
  systemd.tmpfiles.rules = [
    "d /var/lib/bench-soak 0750 soak soak -"
    "d ${code} 0750 soak soak -"
    "z /var/lib/node-exporter-textfile 0775 root soak -"
  ];

  environment.systemPackages = [ pkgs.postgresql pkgs.jq ]; # psql for debug

  # The venv is rebuilt when the pushed requirements file changes and is a
  # no-op otherwise, so a redeploy costs nothing and a dependency bump is a
  # file push plus a restart. It is not a nix derivation because none of these
  # packages are in nixpkgs at the pinned versions the earlier phases measured
  # — the same bench-scoped impurity bench-absurd's worker venv already makes.
  systemd.services.soak-venv = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ python pkgs.gcc pkgs.coreutils ];
    environment.LD_LIBRARY_PATH = wheelLibs;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "soak";
      Group = "soak";
      TimeoutStartSec = "30min"; # first build pulls ~400 MB of wheels
    };
    script = ''
      req=${code}/soak-requirements.txt
      if [ ! -f "$req" ]; then
        echo "no payload at ${code}: push benchlib/agentlib/compose first" >&2
        exit 1
      fi
      want=$(sha256sum "$req" | cut -d' ' -f1)
      have=$(cat ${venv}/.requirements-sha 2>/dev/null || true)
      if [ "$want" != "$have" ] || [ ! -x ${py} ]; then
        rm -rf ${venv}
        ${python}/bin/python3 -m venv ${venv}
        ${venv}/bin/pip install --quiet --upgrade pip
        ${venv}/bin/pip install --quiet -r "$req"
        echo "$want" > ${venv}/.requirements-sha
      fi
      ${py} -c 'import temporalio, hatchet_sdk, absurd_sdk, langgraph'
    '';
  };

  # ---- engine workers ----------------------------------------------------
  # These are also what makes the B4 parked jobs executable when they fall due
  # (2026-08-08 09:16 UTC): the Temporal park is `BenchDelayed` on
  # `bench-default` and the Hatchet park is a scheduled `bench-noop`, both
  # registered by the benchlib worker modules below. The Absurd park is
  # `bench-noop` on `default`, served by bench-absurd's own guest worker.
  systemd.services.soak-worker-temporal-default = soakUnit {
    description = "Temporal bench worker (bench-default)";
    exec = "${py} -m benchlib.temporal_bench worker bench-default";
  };
  systemd.services.soak-worker-temporal-gpu = soakUnit {
    description = "Temporal bench worker (bench-gpu)";
    exec = "${py} -m benchlib.temporal_bench worker bench-gpu";
  };

  # One Hatchet worker advertises class=gpu and one does not. Hatchet routes
  # by workflow registration plus label affinity, so both register the whole
  # benchlib workflow set and only the labelled one can be given `bench-gpu`.
  # `+cron` is deliberately absent: the */5 schedule would add a second,
  # uncontrolled load source to a measured soak.
  systemd.services.soak-worker-hatchet-cpu = soakUnit {
    description = "Hatchet bench worker (default class)";
    exec = "${py} -m benchlib.hatchet_bench worker soak-hatchet-cpu";
  };
  systemd.services.soak-worker-hatchet-gpu = soakUnit {
    description = "Hatchet bench worker (class=gpu)";
    exec = "${py} -m benchlib.hatchet_bench worker soak-hatchet-gpu class=gpu";
  };

  # No Absurd benchlib worker here on purpose. Absurd's claim model pushes an
  # unknown task name back onto the queue instead of leaving it, so two task
  # registries on one queue cost a random multiple of a minute per task. The
  # `default` and `gpu` registries live on bench-absurd and stay there; this
  # guest only adds registries on queues nothing else polls.

  # ---- composition workers ----------------------------------------------
  # The graph share of the load. Each engine gets its flow worker and its
  # `gpu`-class worker, matching the Phase 4 placement.
  systemd.services.soak-compose-temporal = soakUnit {
    description = "Compose worker — Temporal (compose-temporal)";
    exec = "${py} -m compose.temporal_compose worker";
  };
  systemd.services.soak-compose-temporal-gpu = soakUnit {
    description = "Compose worker — Temporal gpu (compose-temporal-gpu)";
    exec = "${py} -m compose.temporal_compose gpuworker";
  };
  systemd.services.soak-compose-hatchet = soakUnit {
    description = "Compose worker — Hatchet";
    exec = "${py} -m compose.hatchet_compose worker --slots 4 --durable-slots 4";
  };
  systemd.services.soak-compose-hatchet-gpu = soakUnit {
    description = "Compose worker — Hatchet gpu";
    exec = "${py} -m compose.hatchet_compose gpuworker --slots 4 --durable-slots 4";
  };
  # `ikeh_gpu`, not `gpu`: bench-absurd's worker owns the `gpu` queue with a
  # different task registry, and sharing it is the cross-registry pushback
  # above. The queue is created in the bench database the same way the rest of
  # the Absurd schema is (absurd.create_queue), not from here.
  systemd.services.soak-compose-absurd = soakUnit {
    description = "Compose worker — Absurd (ikeh)";
    exec = "${py} -m compose.absurd_compose worker";
    extraEnv.COMPOSE_ABSURD_GPU_QUEUE = "ikeh_gpu";
  };
  systemd.services.soak-compose-absurd-gpu = soakUnit {
    description = "Compose worker — Absurd gpu (ikeh_gpu)";
    exec = "${py} -m compose.absurd_compose gpuworker";
    extraEnv.COMPOSE_ABSURD_GPU_QUEUE = "ikeh_gpu";
  };

  # ---- load drivers ------------------------------------------------------
  # One per engine. The profile is the driver's default (documented in
  # phase6-soak.md); overriding it here would put the same numbers in two
  # places and let them drift.
  #
  # PYTHONWARNINGS is set on the drivers and not on the workers. Hatchet's
  # `run_no_wait()` warns on every call, which at the trickle rate is tens of
  # thousands of journal lines over the window with a real error somewhere in
  # among them. A worker's warnings are rare enough to be worth reading.
  #
  # Drivers do not autostart: load generation is an operator decision, and a
  # driver that comes up with the guest restarts load on any reboot — during
  # an idle-measurement window that silently ruins the measurement. Start by
  # hand: `systemctl start soak-driver-{temporal,hatchet,absurd}`.
  systemd.services.soak-driver-temporal = soakUnit {
    description = "Soak load driver — Temporal";
    exec = "${py} -m benchlib.soak temporal";
    after = [ "soak-worker-temporal-default.service" ];
    autostart = false;
    extraEnv = {
      COMPOSE_ABSURD_GPU_QUEUE = "ikeh_gpu";
      PYTHONWARNINGS = "ignore::DeprecationWarning";
    };
  };
  systemd.services.soak-driver-hatchet = soakUnit {
    description = "Soak load driver — Hatchet";
    exec = "${py} -m benchlib.soak hatchet";
    autostart = false;
    after = [ "soak-worker-hatchet-cpu.service" ];
    extraEnv = {
      COMPOSE_ABSURD_GPU_QUEUE = "ikeh_gpu";
      PYTHONWARNINGS = "ignore::DeprecationWarning";
    };
  };
  systemd.services.soak-driver-absurd = soakUnit {
    description = "Soak load driver — Absurd";
    exec = "${py} -m benchlib.soak absurd";
    autostart = false;
    extraEnv = {
      COMPOSE_ABSURD_GPU_QUEUE = "ikeh_gpu";
      PYTHONWARNINGS = "ignore::DeprecationWarning";
    };
  };

  # ---- L4 saturation test ------------------------------------------------
  # The load-test workers and drivers (tieto goldmill/wiki/reviews/bench/
  # load-test-plan.md). All three engines' load workers run here, on queues
  # nothing else polls, because worker placement that differs per engine makes
  # a ceiling a measure of worker hosting.
  #
  # Nothing here autostarts. Saturation is an operator decision and a driver
  # that comes up with its guest restarts a ceiling search on any reboot.
  # Start a run by hand, one engine at a time:
  #
  #   systemctl start load-worker-hatchet
  #   systemctl start load-driver-hatchet          # the full ramp
  #   # or a single fixed-rate step, which takes arguments:
  #   systemd-run --uid=soak --gid=soak --working-directory=/var/lib/bench-soak/code \
  #     -E PYTHONPATH=/var/lib/bench-soak/code -E LD_LIBRARY_PATH=… \
  #     /var/lib/bench-soak/venv/bin/python -m benchlib.load step hatchet 2 60
  systemd.services.load-worker-temporal = soakUnit {
    description = "Temporal load worker (load-temporal)";
    exec = "${py} -m benchlib.temporal_bench worker load-temporal";
    autostart = false;
  };
  systemd.services.load-worker-hatchet = soakUnit {
    description = "Hatchet load worker (load-noop only)";
    exec = "${py} -m benchlib.hatchet_bench loadworker load-hatchet 32";
    autostart = false;
    extraEnv.PYTHONWARNINGS = "ignore::DeprecationWarning";
  };
  # The one Absurd worker this guest carries. It is safe here and the soak
  # workers are not, because `load` is a queue bench-absurd's registries never
  # poll — see the note above about cross-registry pushback.
  systemd.services.load-worker-absurd = soakUnit {
    description = "Absurd load worker (queue load, load-noop only)";
    exec = "${py} -m benchlib.load_worker worker load";
    autostart = false;
  };

  # One driver per engine, running the full ramp with the plan's defaults. The
  # profile lives in the driver, not here, so the numbers exist in one place.
  systemd.services.load-driver-temporal = soakUnit {
    description = "L4 load driver — Temporal (ramp)";
    exec = "${py} -m benchlib.load ramp temporal";
    after = [ "load-worker-temporal.service" ];
    autostart = false;
    restart = "no";
    extraEnv.PYTHONWARNINGS = "ignore::DeprecationWarning";
  };
  systemd.services.load-driver-hatchet = soakUnit {
    description = "L4 load driver — Hatchet (ramp)";
    exec = "${py} -m benchlib.load ramp hatchet";
    after = [ "load-worker-hatchet.service" ];
    autostart = false;
    restart = "no";
    extraEnv.PYTHONWARNINGS = "ignore::DeprecationWarning";
  };
  systemd.services.load-driver-absurd = soakUnit {
    description = "L4 load driver — Absurd (ramp)";
    exec = "${py} -m benchlib.load ramp absurd";
    after = [ "load-worker-absurd.service" ];
    autostart = false;
    restart = "no";
  };
}
