# Single-node Temporal benchmark service with bounded caches and queue metrics.
# numHistoryShards is fixed for the lifetime of its database. The password is
# substituted into the runtime state directory and never enters the Nix store.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.systems-bench-temporal;
  pg = cfg.postgresHost; # bench-pg via host proxy on the static bridge IP
  schemaRoot = "${pkgs.temporal}/share/schema/postgresql/v12";
  sqlStore = db: extra: {
    sql = {
      pluginName = "postgres12";
      databaseName = db;
      connectAddr = "${pg}:5432";
      connectProtocol = "tcp";
      user = "temporal";
      password = "@SQL_PASSWORD@";
    }
    // extra;
  };
  uiRoot = pkgs.writeTextDir "config/production.yaml" ''
    temporalGrpcAddress: 127.0.0.1:7233
    host: 0.0.0.0
    port: 8080
    enableUi: true
  '';

  cacheProfile = cfg.cacheProfile;

  goMemLimit = cfg.goMemLimit;
  goGC = cfg.goGC;

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
  imports = [ ../../lxc-guest.nix ];

  options.services.systems-bench-temporal = {
    postgresHost = lib.mkOption {
      type = lib.types.str;
      description = "PostgreSQL host reachable independently of overlay DNS.";
    };
    cacheProfile = lib.mkOption {
      type = lib.types.enum [
        "roomy"
        "tight"
      ];
      description = "Cache profile matching the guest memory limit.";
    };
    goMemLimit = lib.mkOption {
      type = lib.types.str;
      description = "Go heap budget matching the guest memory limit.";
    };
    goGC = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Optional Go garbage collector target.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/root/bench-secrets.env";
      description = "Runtime environment file containing SQL_PASSWORD.";
    };
    queues = lib.mkOption {
      type = lib.types.str;
      description = "Space-separated task queues to poll.";
    };
  };

  config = {

    networking.firewall.allowedTCPPorts = [ 7233 ];

    services.temporal = {
      enable = true;
      settings = {
        log = {
          stdout = true;
          level = "info";
        };
        persistence = {
          numHistoryShards = 64;
          defaultStore = "default";
          visibilityStore = "visibility";
          datastores = {
            default = sqlStore "temporal" {
              maxConns = 10;
              maxIdleConns = 5;
              maxConnLifetime = "1h";
            };
            visibility = sqlStore "temporal_visibility" {
              maxConns = 5;
              maxIdleConns = 2;
              maxConnLifetime = "1h";
            };
          };
        };
        global = {
          metrics.prometheus = {
            framework = "prometheus";
            listenAddress = "0.0.0.0:9091";
          };
        };
        services = {
          frontend.rpc = {
            grpcPort = 7233;
            membershipPort = 6933;
            bindOnIP = "0.0.0.0";
            httpPort = 7243;
          };
          history.rpc = {
            grpcPort = 7234;
            membershipPort = 6934;
            bindOnIP = "0.0.0.0";
          };
          matching.rpc = {
            grpcPort = 7235;
            membershipPort = 6935;
            bindOnIP = "0.0.0.0";
          };
          worker.rpc = {
            grpcPort = 7239;
            membershipPort = 6939;
            bindOnIP = "0.0.0.0";
          };
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
          pollInterval = "60s";
        };
        publicClient.hostPort = "127.0.0.1:7233";
      };
    };

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

    systemd.services.temporal = {
      path = [
        pkgs.gnused
        pkgs.coreutils
      ];
      environment = {
        GOMEMLIMIT = goMemLimit;
      }
      // lib.optionalAttrs (goGC != null) {
        GOGC = toString goGC;
      };
      serviceConfig = {
        EnvironmentFile = cfg.environmentFile;
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

    systemd.services.temporal-schema = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.temporal ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = cfg.environmentFile;
      };
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

    systemd.services.temporal-namespace = {
      wantedBy = [ "multi-user.target" ];
      after = [ "temporal.service" ];
      requires = [ "temporal.service" ];
      path = [ pkgs.temporal-cli ];
      environment.HOME = "/tmp"; # CLI insists on a config dir
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
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

    systemd.services.temporal-queue-metrics = {
      after = [ "temporal.service" ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "25s";
      };
      environment = {
        CURL = "${pkgs.curl}/bin/curl";
        JQ = "${pkgs.jq}/bin/jq";
        POLLER_FOOTER = "${../../bench/poller-footer.sh}";
        TEMPORAL_QUEUES = cfg.queues;
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
        RestartSec = 10;
      };
      unitConfig.StartLimitIntervalSec = 0;
    };
  };
}
