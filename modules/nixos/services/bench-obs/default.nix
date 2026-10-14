# Benchmark monitoring mechanisms with caller-supplied targets and policy.
# Client certificates and database credentials are runtime files. Prometheus
# uses syntax-only checking because certificates are absent from the store.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.services.systems-bench-obs;
  nodeTargets = cfg.nodeTargets;
  otherJobs = [
    "temporal"
    "hatchet"
    "postgres"
    "prometheus"
    "grafana"
    "incus"
  ];

  soakEngines = cfg.soakEngines;

  alertRules = import cfg.alertRules {
    inherit lib soakEngines;
    jobs = [ "node" ] ++ otherJobs;
    nodeTargetCount = lib.length (nodeTargets.host ++ nodeTargets.guest);
    dashboardCount = lib.length (lib.attrNames (builtins.readDir cfg.dashboards));
  };
in
{
  imports = [ ../../lxc-guest.nix ];

  options.services.systems-bench-obs = {
    nodeTargets = lib.mkOption {
      type = lib.types.submodule {
        options = {
          host = lib.mkOption { type = lib.types.listOf lib.types.str; };
          guest = lib.mkOption { type = lib.types.listOf lib.types.str; };
        };
      };
      description = "Node scrape targets grouped by role.";
    };
    temporalTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "temporalTargets used by scrape and alert configuration.";
    };
    hatchetTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "hatchetTargets used by scrape and alert configuration.";
    };
    incusTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "incusTargets used by scrape and alert configuration.";
    };
    soakEngines = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "soakEngines used by scrape and alert configuration.";
    };
    hatchetApiUrl = lib.mkOption {
      type = lib.types.str;
      description = "Hatchet REST endpoint.";
    };
    hatchetQueues = lib.mkOption {
      type = lib.types.str;
      description = "Space-separated Hatchet queue names.";
    };
    postgresDatabases = lib.mkOption {
      type = lib.types.str;
      description = "Space-separated databases for table metrics.";
    };
    alertRules = lib.mkOption {
      type = lib.types.path;
      description = "Private alertRules source path.";
    };
    dashboards = lib.mkOption {
      type = lib.types.path;
      description = "Private dashboards source path.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/root/bench-secrets.env";
      description = "Runtime database and Hatchet credentials.";
    };
  };

  config = {

    networking.firewall.allowedTCPPorts = [ 9090 ];

    services.prometheus = {
      enable = true;

      rules = [
        (builtins.toJSON { groups = lib.attrValues alertRules; })
      ];
      checkConfig = "syntax-only";
      globalConfig.scrape_interval = "15s";
      retentionTime = "180d";
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = nodeTargets.host;
              labels.role = "host";
            }
            {
              targets = nodeTargets.guest;
              labels.role = "guest";
            }
          ];
        }
        {
          job_name = "temporal";
          static_configs = [ { targets = cfg.temporalTargets; } ];
        }
        {
          job_name = "hatchet";
          static_configs = [ { targets = cfg.hatchetTargets; } ];
        }
        {
          job_name = "postgres";
          static_configs = [ { targets = [ "localhost:9187" ]; } ];
        }
        {
          job_name = "prometheus";
          static_configs = [ { targets = [ "localhost:9090" ]; } ];
        }
        {
          job_name = "grafana";
          static_configs = [ { targets = [ "localhost:3000" ]; } ];
          metric_relabel_configs = [
            {
              source_labels = [ "__name__" ];
              regex = "grafana_build_info|grafana_stat_totals_.*";
              action = "keep";
            }
          ];
        }
        {
          job_name = "incus";
          scheme = "https";
          tls_config = {
            cert_file = "/var/lib/prometheus-incus/incus-metrics.crt";
            key_file = "/var/lib/prometheus-incus/incus-metrics.key";
            insecure_skip_verify = true; # host cert is Incus-generated
          };
          static_configs = [ { targets = cfg.incusTargets; } ];
          metrics_path = "/1.0/metrics";
        }
      ];
    };
    systemd.services.prometheus.serviceConfig.BindReadOnlyPaths = [
      "/var/lib/prometheus-incus"
    ];

    systemd.services.hatchet-queue-metrics = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.environmentFile;
        TimeoutStartSec = "20s";
      };
      environment = {
        HATCHET_API_URL = cfg.hatchetApiUrl;
        OUT = "/var/lib/node-exporter-textfile/hatchet.prom";
        HATCHET_QUEUES = cfg.hatchetQueues;
      };
      script = "exec ${pkgs.python3}/bin/python3 ${./hatchet-queue-metrics.py}";
    };
    systemd.timers.hatchet-queue-metrics = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "30s";
      };
    };

    services.prometheus.exporters.postgres = {
      enable = true;
      environmentFile = cfg.environmentFile; # DATA_SOURCE_NAME=...
      extraFlags = [
        "--collector.postmaster"
        "--collector.stat_checkpointer"
      ];
    };

    systemd.services.pg-table-metrics = {
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.environmentFile; # PGHOST/PGUSER/PGPASSWORD
        TimeoutStartSec = "60s";
      };
      environment = {
        PSQL = "${pkgs.postgresql}/bin/psql";
        POLLER_FOOTER = "${../../bench/poller-footer.sh}";
        PG_DATABASES = cfg.postgresDatabases;
      };
      script = "exec ${pkgs.bash}/bin/bash ${./pg-table-metrics.sh}";
    };
    systemd.timers.pg-table-metrics = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "5min";
      };
    };

    services.grafana = {
      enable = true;
      settings.server = {
        http_addr = "0.0.0.0"; # tailnet-only via firewall trust
        http_port = 3000;
      };
      settings.security.secret_key = "$__file{/var/lib/grafana/secret-key}";
      provision = {
        enable = true;
        datasources.settings.datasources = [
          {
            name = "bench-prometheus";
            uid = "bench-prometheus";
            type = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
          }
        ];
        dashboards.settings.providers = [
          {
            name = "bench";
            type = "file";
            folder = "Bench";
            allowUiUpdates = false;
            options = {
              path = cfg.dashboards;
              foldersFromFilesStructure = false;
            };
          }
        ];
      };
    };
    systemd.services.grafana.preStart = ''
      if [ ! -f /var/lib/grafana/secret-key ]; then
        umask 077
        head -c 32 /dev/urandom | base64 | tr -d '\n' > /var/lib/grafana/secret-key
      fi
    '';
  };
}
