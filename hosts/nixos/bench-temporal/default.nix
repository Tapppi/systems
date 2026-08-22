# bench-temporal: Temporal bench guest (tieto goldmill/wiki/reviews/bench/
# phase0-hosting-temporal.md). Single-process server via the nixpkgs
# services.temporal module, UI, schema oneshot, default namespace.
#
# numHistoryShards=64 is PERMANENT from the first boot against a given
# database — never change it; a mismatch refuses to start and there is no
# re-shard.
#
# The DB password never enters the repo or the nix store: the generated
# config carries an @SQL_PASSWORD@ placeholder, and preStart renders the
# real file into the state dir from /root/bench-secrets.env
# (SQL_PASSWORD=...), which also feeds the schema/namespace oneshots.
{ pkgs, lib, ... }:

let
  pg = "10.135.155.1"; # bench-pg via host proxy on the static bridge IP
  # (incusbr0) — engine<->DB must not depend on tailscale being up
  schemaRoot = "${pkgs.temporal}/share/schema/postgresql/v12";
  sqlStore = db: extra: {
    sql = {
      pluginName = "postgres12";
      databaseName = db;
      connectAddr = "${pg}:5432";
      connectProtocol = "tcp";
      user = "temporal";
      password = "@SQL_PASSWORD@";
    } // extra;
  };
  uiRoot = pkgs.writeTextDir "config/production.yaml" ''
    temporalGrpcAddress: 127.0.0.1:7233
    host: 0.0.0.0
    port: 8080
    enableUi: true
  '';

  # Which cache profile the dynamic config below renders. It has to match
  # `limits.memory` on the Incus side, and the two are set in different places,
  # so changing one without the other is the failure mode to watch for.
  #   roomy — caps of 1 GiB and up, including this guest's deployed 1536 MiB
  #   tight — the 512 MiB cap
  cacheProfile = "roomy";

  # Go's heap ceiling, and the GC aggressiveness that goes with it. Both track
  # `limits.memory` on the Incus side and are set here rather than there:
  # `incus config set … environment.GOMEMLIMIT=…` reaches the container's PID 1
  # and stops, because a service inherits systemd's *manager* environment and
  # not the environment systemd itself was exec'd with. The variable is then
  # present in /proc/1/environ and absent from the server process, which reads
  # exactly like a setting that did not help.
  #
  # Go 1.25 made GOMAXPROCS container-aware and there is still no memory
  # equivalent (golang/go#75164), so without this a capped guest gets no
  # backpressure at all. It is a backstop and not the fix: below a program's
  # true live-heap floor Go caps collection at ~50 % of CPU and lets memory
  # exceed the limit anyway. The cache bounds below are the fix.
  #
  # The cost of setting it here is one rebuild per RAM step. The headroom
  # fraction widens as the cap shrinks, because the fixed non-heap resident set
  # is a larger share of a smaller cap:
  #   2 GiB   -> 1800MiB, GOGC default
  #   1536 MiB -> 1350MiB, GOGC default   (this guest's deployed cap)
  #   1 GiB   ->  880MiB, GOGC default
  #   512 MiB ->  410MiB, GOGC 50         (with cacheProfile = "tight")
  #
  # A value above `limits.memory` is worse than no value at all: it reads like
  # backpressure and provides none, because the cgroup kills the process before
  # Go ever reaches its own ceiling. This must be moved with the cap.
  goMemLimit = "1350MiB";
  goGC = null;

  profiles = {
    roomy = {
      historyCacheEntries = 1024;
      historyCacheTTL = "10m";
      eventsCacheBytes = 33554432; # 32 MiB
      eventsCacheTTL = "5m";
      schedulerWorkers = 32;
      memoryTimerWorkers = 8;
      pendingTasksMax = 1000;
      pendingTasksCritical = 800;
      mutableStateError = 2097152; # 2 MiB
      mutableStateWarn = 524288; # 512 KiB
    };
    tight = {
      historyCacheEntries = 256;
      historyCacheTTL = "5m";
      eventsCacheBytes = 8388608; # 8 MiB
      eventsCacheTTL = "2m";
      schedulerWorkers = 12;
      memoryTimerWorkers = 4;
      pendingTasksMax = 250;
      pendingTasksCritical = 200;
      mutableStateError = 1048576; # 1 MiB
      mutableStateWarn = 262144; # 256 KiB
    };
  };
  c = profiles.${cacheProfile};
in
{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-temporal";

  # The frontend, reachable over incusbr0 as well as the tailnet: bench-load
  # runs the soak's workers off the tailnet on purpose (see that guest's
  # comment on the resolver dependency). The bridge is NAT-only and private to
  # dogmatix, so this exposes nothing the host does not already expose.
  networking.firewall.allowedTCPPorts = [ 7233 ];

  services.temporal = {
    enable = true;
    settings = {
      log = { stdout = true; level = "info"; };
      persistence = {
        numHistoryShards = 64;
        defaultStore = "default";
        visibilityStore = "visibility";
        datastores = {
          default = sqlStore "temporal" {
            maxConns = 10; maxIdleConns = 5; maxConnLifetime = "1h";
          };
          visibility = sqlStore "temporal_visibility" {
            maxConns = 5; maxIdleConns = 2; maxConnLifetime = "1h";
          };
        };
      };
      global = {
        membership.broadcastAddress = "100.116.6.114"; # guest tailnet IP
        metrics.prometheus = {
          framework = "prometheus";
          listenAddress = "0.0.0.0:9091";
        };
      };
      services = {
        frontend.rpc = { grpcPort = 7233; membershipPort = 6933; bindOnIP = "0.0.0.0"; httpPort = 7243; };
        history.rpc = { grpcPort = 7234; membershipPort = 6934; bindOnIP = "0.0.0.0"; };
        matching.rpc = { grpcPort = 7235; membershipPort = 6935; bindOnIP = "0.0.0.0"; };
        worker.rpc = { grpcPort = 7239; membershipPort = 6939; bindOnIP = "0.0.0.0"; };
      };
      clusterMetadata = {
        enableGlobalNamespace = false;
        failoverVersionIncrement = 10;
        masterClusterName = "active";
        currentClusterName = "active";
        clusterInformation.active = {
          enabled = true;
          initialFailoverVersion = 1;
          rpcName = "frontend";
          rpcAddress = "127.0.0.1:7233";
        };
      };
      dcRedirectionPolicy.policy = "noop";
      dynamicConfigClient = {
        filepath = "/etc/temporal/dynamicconfig.yaml";
        # The server refuses to start below 5 s. Only the scheduler pools and
        # the queue budgets below are re-read on a poll; everything cache-shaped
        # is read once at process start, so an edit to those needs a restart.
        pollInterval = "60s";
      };
      publicClient.hostPort = "127.0.0.1:7233";
    };
  };

  # Dynamic config. Temporal's defaults size every cache for a machine far
  # larger than a memory-capped guest: the mutable-state cache holds 128000
  # entries with an 8 MiB per-entry ceiling, the events cache is per shard and
  # so exists 64 times over, every cache is TTL-based with no proactive
  # eviction, and the scheduler pools spawn 1600 goroutines before any work
  # arrives. Nothing warns about this and there is no memory equivalent of
  # Go 1.25's container-aware GOMAXPROCS, so a capped process gets no
  # backpressure of its own either — GOMEMLIMIT is set beside the cap, on the
  # Incus side, because its value tracks the cap. Deliberately NOT set as a
  # unit `environment.GOMEMLIMIT` here: a unit-level Environment= would win
  # over the manager environment and pin every cap to one value.
  #
  # Two hazards this file is shaped around:
  #   - history.cacheSizeBasedLimit must stay false. With size-based limiting
  #     on, the cache release path iterates an unlocked map and Go raises
  #     "concurrent map iteration and map write", which recover() cannot catch
  #     (temporalio/temporal#10548). Entry-count mode is the only safe mode.
  #   - An unregistered key is silently ignored with a single log line, so a
  #     typo reads exactly like a setting that did not help. Every key here is
  #     checked against v1.31.2's common/dynamicconfig/constants.go, and
  #     `journalctl -u temporal | grep -i "unregistered\|unknown key"` after a
  #     deploy is the only signal that they were accepted.
  #
  # Byte-denominated limits are budgeted as if several times larger than they
  # read: the accounting uses protobuf wire size, not unmarshalled heap size
  # (temporalio/temporal#10523).
  environment.etc."temporal/dynamicconfig.yaml".text = ''
    # Mutable-state cache — process-global, not per shard.
    history.cacheSizeBasedLimit:
      - value: false
        constraints: {}
    history.hostLevelCacheMaxSize:
      - value: ${toString c.historyCacheEntries}
        constraints: {}
    history.cacheTTL:
      - value: "${c.historyCacheTTL}"
        constraints: {}
    history.cacheBackgroundEvict:
      - value: { Enabled: true, LoopInterval: "30s", MaxEntryPerCall: 1024 }
        constraints: {}

    # Events cache — per shard by default, so 64 independent caches. One
    # host-level cache instead, which stops the cost scaling with shard count.
    history.enableHostLevelEventsCache:
      - value: true
        constraints: {}
    history.eventsHostLevelCacheMaxSizeBytes:
      - value: ${toString c.eventsCacheBytes}
        constraints: {}
    history.eventsCacheTTL:
      - value: "${c.eventsCacheTTL}"
        constraints: {}

    # Cross-cluster blob cache. This is a single-cluster deployment, so it
    # holds nothing useful.
    history.xdcCacheMaxSizeBytes:
      - value: 1048576
        constraints: {}

    # Host-level scheduler pools, independent of shard count and re-read on
    # the poll interval.
    history.transferProcessorSchedulerWorkerCount:
      - value: ${toString c.schedulerWorkers}
        constraints: {}
    history.timerProcessorSchedulerWorkerCount:
      - value: ${toString c.schedulerWorkers}
        constraints: {}
    history.visibilityProcessorSchedulerWorkerCount:
      - value: ${toString c.schedulerWorkers}
        constraints: {}
    history.memoryTimerProcessorSchedulerWorkerCount:
      - value: ${toString c.memoryTimerWorkers}
        constraints: {}

    # In-memory task budget, per shard per queue category — so x64 x4. The
    # critical count has to stay below the max count.
    history.queuePendingTasksMaxCount:
      - value: ${toString c.pendingTasksMax}
        constraints: {}
    history.queuePendingTaskCriticalCount:
      - value: ${toString c.pendingTasksCritical}
        constraints: {}

    # Matching. Each partition is a separately loaded manager with its own
    # backlog buffer, and four of them buy nothing at bench scale.
    # matching.maxTaskQueueIdleTime stays at its 5 m default because it must
    # exceed matching.getUserDataLongPollTimeout, which is 4 m 50 s.
    matching.numTaskqueueReadPartitions:
      - value: 1
        constraints: {}
    matching.numTaskqueueWritePartitions:
      - value: 1
        constraints: {}
    matching.getTasksBatchSize:
      - value: 100
        constraints: {}

    # Per-entry ceilings — the only thing bounding what one cached workflow
    # can cost.
    limit.mutableStateSize.error:
      - value: ${toString c.mutableStateError}
        constraints: {}
    limit.mutableStateSize.warn:
      - value: ${toString c.mutableStateWarn}
        constraints: {}

    # Background scanners a single-node bench does not need.
    worker.historyScannerEnabled:
      - value: false
        constraints: {}
    worker.taskQueueScannerEnabled:
      - value: false
        constraints: {}
  '';

  # Render the real config (password substituted) into the state dir and
  # point the server at it. EnvironmentFile is read by the manager as root,
  # so DynamicUser still gets the variables.
  systemd.services.temporal = {
    path = [ pkgs.gnused pkgs.coreutils ];
    environment = { GOMEMLIMIT = goMemLimit; } // lib.optionalAttrs (goGC != null) {
      GOGC = toString goGC;
    };
    serviceConfig = {
      EnvironmentFile = "/root/bench-secrets.env";
      # --allow-no-auth is deliberate and load-bearing. The bench runs no
      # authorizer — it is tailnet-only and single-tenant — and the server
      # logs a forward-compatibility warning at every start saying future
      # versions will refuse to boot without the flag. Passing it turns a
      # warning nobody reads into a decision the config states.
      ExecStart = lib.mkForce "${pkgs.temporal}/bin/temporal-server --root / --config /var/lib/temporal/config/ -e temporal-server --allow-no-auth start";
    };
    preStart = ''
      mkdir -p /var/lib/temporal/config
      # The dynamic config the server reads is /etc/temporal/dynamicconfig.yaml.
      # A second file of that name in the state dir would be the one an operator
      # finds by looking, so the state dir does not carry one.
      rm -f /var/lib/temporal/dynamicconfig.yaml
      sed "s|@SQL_PASSWORD@|$SQL_PASSWORD|g" \
        /etc/temporal/temporal-server.yaml > /var/lib/temporal/config/temporal-server.yaml
      chmod 600 /var/lib/temporal/config/temporal-server.yaml
    '';
    after = [ "temporal-schema.service" ];
    requires = [ "temporal-schema.service" ];
  };

  # Schema before server, every activation; update-schema is idempotent.
  # setup-schema errors on an initialized DB — tolerated on purpose.
  systemd.services.temporal-schema = {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.temporal ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      EnvironmentFile = "/root/bench-secrets.env";
    };
    # network-online.target inside an LXC guest fires before the host bridge
    # can actually carry traffic, so without this wait the unit fails on an
    # unreachable bench-pg after a host reboot and takes temporal.service
    # (which Requires= it) down with it for good. Type=oneshot cannot use
    # Restart=, so the retry has to live in the script.
    script = ''
      export SQL_PLUGIN=postgres12 SQL_HOST=${pg} SQL_PORT=5432 SQL_USER=temporal
      export SQL_PASSWORD="$SQL_PASSWORD"
      for i in $(seq 1 60); do
        if ${pkgs.netcat}/bin/nc -z ${pg} 5432; then break; fi
        echo "waiting for postgres at ${pg}:5432 ($i/60)"
        sleep 2
      done
      temporal-sql-tool --database temporal setup-schema -v 0.0 || true
      temporal-sql-tool --database temporal update-schema \
        -d ${schemaRoot}/temporal/versioned
      temporal-sql-tool --database temporal_visibility setup-schema -v 0.0 || true
      temporal-sql-tool --database temporal_visibility update-schema \
        -d ${schemaRoot}/visibility/versioned
    '';
  };

  # Default namespace with bench retention; waits for the frontend.
  systemd.services.temporal-namespace = {
    wantedBy = [ "multi-user.target" ];
    after = [ "temporal.service" ];
    requires = [ "temporal.service" ];
    path = [ pkgs.temporal-cli ];
    environment.HOME = "/tmp"; # CLI insists on a config dir
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      for i in $(seq 1 30); do
        temporal operator cluster health --address 127.0.0.1:7233 && break
        sleep 2
      done
      temporal operator namespace describe --address 127.0.0.1:7233 -n default \
        || temporal operator namespace create --address 127.0.0.1:7233 \
             --retention 72h -n default
    '';
  };

  # Task-queue backlog into the node-exporter textfile collector. The script's
  # own header explains why the native gauge cannot serve this purpose. The
  # HTTP API it calls is the frontend's, on loopback, so this adds no exposure.
  systemd.services.temporal-queue-metrics = {
    after = [ "temporal.service" ];
    serviceConfig = {
      Type = "oneshot";
      # Three loopback HTTP calls per queue; the ceiling keeps a stuck run
      # from overlapping the next timer tick and leaving the gauges silently
      # stale, so it stays below the 30 s interval whatever the queue count.
      TimeoutStartSec = "25s";
    };
    environment = {
      CURL = "${pkgs.curl}/bin/curl";
      JQ = "${pkgs.jq}/bin/jq";
      POLLER_FOOTER = "${../../../modules/nixos/bench/poller-footer.sh}";
      # Hand-kept: nothing enumerates declared task queues, and a queue absent
      # from this list has no backlog series at all — which on a dashboard is
      # indistinguishable from an engine that never queued anything.
      #
      # Names are per-engine and do not carry across: the sleep workload's
      # Temporal task queue is `load-temporal-sleep`, while `load-sleep` is
      # Absurd's queue and Hatchet's task name. A name that no Temporal queue
      # answers to polls clean and publishes nothing.
      TEMPORAL_QUEUES = "bench-default bench-gpu compose-temporal compose-temporal-gpu"
        + " load-temporal load-temporal-sleep";
    };
    script = "exec ${pkgs.bash}/bin/bash ${./temporal-queue-metrics.sh}";
  };
  systemd.timers.temporal-queue-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitActiveSec = "30s";
    };
  };

  systemd.services.temporal-ui = {
    wantedBy = [ "multi-user.target" ];
    after = [ "temporal.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.temporal-ui-server}/bin/temporal-ui-server --root ${uiRoot} --env production start";
      DynamicUser = true;
      Restart = "on-failure";
      # The UI exits when the frontend is not up yet, and it is only ordered
      # After= the server, not Requires=. At the default 100 ms RestartSec it
      # burns systemd's five-starts-in-ten-seconds budget in under a second
      # after a host reboot and then stays dead permanently — the same shape
      # as the reboot-ordering failure that once took the server itself out.
      RestartSec = 10;
    };
    unitConfig.StartLimitIntervalSec = 0;
  };
}
