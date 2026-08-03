# bench-obs: bench observability guest — Prometheus, Grafana,
# postgres_exporter, and the Incus per-guest metrics scrape (tieto
# goldmill/wiki/reviews/bench/phase0-summary.md, phase 1 step 3).
#
# Secrets (all out-of-repo, root-only on the guest):
#   /root/bench-secrets.env  — DATA_SOURCE_NAME for postgres_exporter,
#     PGHOST/PGPORT/PGUSER/PGPASSWORD (same credentials, libpq form, for the
#     per-table size poller), and HATCHET_API_TOKEN (the worker JWT, which
#     doubles as a REST bearer) + HATCHET_TENANT_ID for the queue poller.
#   /var/lib/prometheus-incus/incus-metrics.{crt,key} — client cert trusted
#     by the host's Incus metrics endpoint (10.135.155.1:8444,
#     --type=metrics). Deliberately outside /root: prometheus runs as its
#     own user and must traverse the containing directory, which /root's
#     0700 forbids even with a bind mount of the files themselves.
{ pkgs, ... }:

{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-obs";

  services.prometheus = {
    enable = true;
    # Full check stats the incus client cert inside the build sandbox where
    # it cannot exist.
    checkConfig = "syntax-only";
    globalConfig.scrape_interval = "15s";
    retentionTime = "30d";
    scrapeConfigs = [
      {
        job_name = "node";
        # `role` splits the Incus host from the guests running on it, so a
        # dashboard can sum guests without double-counting the substrate.
        # Targets are MagicDNS names rather than localhost so every series
        # carries the instance label the panels select on.
        static_configs = [
          {
            targets = [ "dogmatix:9100" ];
            labels.role = "host";
          }
          {
            targets = [
              "bench-obs:9100"
              "bench-absurd:9100"
              "bench-temporal:9100"
            ];
            labels.role = "guest";
          }
        ];
      }
      {
        job_name = "temporal";
        static_configs = [{ targets = [ "bench-temporal:9091" ]; }];
      }
      {
        job_name = "hatchet";
        static_configs = [{ targets = [ "dogmatix:9090" ]; }];
      }
      {
        job_name = "postgres";
        static_configs = [{ targets = [ "localhost:9187" ]; }];
      }
      {
        # Per-guest cgroup RAM/CPU — the primary per-engine bench figures.
        job_name = "incus";
        scheme = "https";
        tls_config = {
          cert_file = "/var/lib/prometheus-incus/incus-metrics.crt";
          key_file = "/var/lib/prometheus-incus/incus-metrics.key";
          insecure_skip_verify = true; # host cert is Incus-generated
        };
        static_configs = [{ targets = [ "10.135.155.1:8444" ]; }];
        metrics_path = "/1.0/metrics";
      }
    ];
  };
  # Prometheus runs sandboxed (ProtectSystem=strict); grant it the cert dir.
  systemd.services.prometheus.serviceConfig.BindReadOnlyPaths = [
    "/var/lib/prometheus-incus"
  ];

  # Hatchet exposes no queue-depth gauge: every hatchet_* Prometheus series is
  # an unlabelled tenant-global counter with no queue or worker-class label.
  # Depth per queue — the wake-on-LAN signal — exists only over REST, so this
  # poller reads it and publishes gauges through the node-exporter textfile
  # collector, the same route bench-absurd uses for its own queue depth. It
  # runs here rather than on bench-hatchet because that guest is an OCI
  # container with no room for a NixOS unit.
  #
  # HATCHET_QUEUES zero-fills: the API omits any queue with no pending work,
  # and an absent series looks identical to a broken poller on a dashboard.
  # hatchet_poller_up separates the two. The list has to be maintained by
  # hand — no endpoint enumerates declared queues, only backlogged ones.
  systemd.services.hatchet-queue-metrics = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/root/bench-secrets.env";
      # Well inside the timer interval: a run still in flight when the next
      # one is due leaves the gauges stale without saying so.
      TimeoutStartSec = "20s";
    };
    environment = {
      HATCHET_API_URL = "http://dogmatix:8888";
      OUT = "/var/lib/node-exporter-textfile/hatchet.prom";
      HATCHET_QUEUES = "bench-noop bench-gpu bench-hitl bench-cron bench-burst";
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
    environmentFile = "/root/bench-secrets.env"; # DATA_SOURCE_NAME=...
    extraFlags = [
      # Server start time, for an uptime panel.
      "--collector.postmaster"
      # Postgres 17 moved the checkpoint counters out of pg_stat_bgwriter into
      # pg_stat_checkpointer, which is a separate collector here.
      "--collector.stat_checkpointer"
    ];
  };

  # Per-table sizes per engine database — see the script's header for why the
  # exporter cannot supply them.
  systemd.services.pg-table-metrics = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/root/bench-secrets.env"; # PGHOST/PGUSER/PGPASSWORD
      TimeoutStartSec = "60s";
    };
    environment = {
      PSQL = "${pkgs.postgresql}/bin/psql";
      PG_DATABASES = "temporal temporal_visibility hatchet bench";
    };
    script = "exec ${pkgs.bash}/bin/bash ${./pg-table-metrics.sh}";
  };
  systemd.timers.pg-table-metrics = {
    wantedBy = [ "timers.target" ];
    # Sizes move on the scale of minutes at most; a 5 min sample keeps the
    # per-table series cheap.
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
    # Generated on first start (preStart below); never in repo or store.
    settings.security.secret_key = "$__file{/var/lib/grafana/secret-key}";
    provision = {
      enable = true;
      datasources.settings.datasources = [{
        name = "bench-prometheus";
        type = "prometheus";
        url = "http://localhost:9090";
        isDefault = true;
      }];
    };
  };
  systemd.services.grafana.preStart = ''
    if [ ! -f /var/lib/grafana/secret-key ]; then
      umask 077
      head -c 32 /dev/urandom | base64 | tr -d '\n' > /var/lib/grafana/secret-key
    fi
  '';
}
