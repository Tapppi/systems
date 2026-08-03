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
{ pkgs, lib, ... }:

let
  # Bound here so the alert rules can be generated from the same list the
  # scrape config is built from, rather than restating it. `node` carries
  # several instances, so it is the one job the rules count instead of
  # testing for absence.
  nodeTargets = {
    host = [ "dogmatix:9100" ];
    guest = [ "bench-obs:9100" "bench-absurd:9100" "bench-temporal:9100" ];
  };
  otherJobs = [ "temporal" "hatchet" "postgres" "prometheus" "grafana" "incus" ];

  alertRules = import ./alert-rules.nix {
    inherit lib;
    jobs = [ "node" ] ++ otherJobs;
    nodeTargetCount = lib.length (nodeTargets.host ++ nodeTargets.guest);
    # The same directory Grafana provisions from, so the rule is a genuine
    # repo-versus-runtime check rather than a number someone typed once.
    dashboardCount = lib.length (lib.attrNames (builtins.readDir ./dashboards));
  };
in
{
  imports = [ ../../../modules/nixos/bench/guest-base.nix ];

  networking.hostName = "bench-obs";

  services.prometheus = {
    enable = true;

    # No Alertmanager, deliberately: the rules exist for the `ALERTS` series
    # the rule manager generates on its own, which the Health row of
    # /d/bench-overview renders as a table. See alert-rules.nix.
    rules = [
      (builtins.toJSON { groups = lib.attrValues alertRules; })
    ];
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
        # The monitoring stack was the only part of the bench with no
        # liveness signal of its own. The self-scrape carries config-reload
        # success, rule-evaluation failures and TSDB health: a config that
        # passes the syntax-only check below and then fails at runtime — an
        # unreadable cert file being the case that already happened here —
        # otherwise leaves no trace but a journal line.
        job_name = "prometheus";
        static_configs = [{ targets = [ "localhost:9090" ]; }];
      }
      {
        # Grafana serves /metrics unauthenticated, so liveness costs none of
        # the service account the dashboard API would need.
        # absent(grafana_build_info) is the only signal that Grafana is
        # crashlooping: a restart cycle faster than the scrape interval never
        # reads as a failed unit.
        #
        # Kept to the two families anything here reads. Grafana's full surface
        # is ~3600 series — mostly k8s-style apiserver histograms — which is
        # about a tenth of this Prometheus's whole ingest and ~16 MB of its
        # RSS, spent on a box whose 1 GiB cap is itself a bench measurement.
        job_name = "grafana";
        static_configs = [{ targets = [ "localhost:3000" ]; }];
        metric_relabel_configs = [{
          source_labels = [ "__name__" ];
          regex = "grafana_build_info|grafana_stat_totals_.*";
          action = "keep";
        }];
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
      POLLER_FOOTER = "${../../../modules/nixos/bench/poller-footer.sh}";
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
        # Fixed so provisioned dashboards can name the datasource without a
        # per-deploy lookup; they select it through a `ds` dashboard variable
        # defaulting to this name. Grafana cannot re-point an *existing*
        # datasource at a new uid — changing this value needs a
        # deleteDatasources entry alongside it, or Grafana refuses to start.
        uid = "bench-prometheus";
        type = "prometheus";
        url = "http://localhost:9090";
        isDefault = true;
      }];
      # Dashboards are repo artifacts, not click-built state: Grafana loads
      # the JSON from the store and refuses UI edits, so a redeploy always
      # restores exactly what is committed here.
      dashboards.settings.providers = [{
        name = "bench";
        type = "file";
        folder = "Bench";
        allowUiUpdates = false;
        options = {
          path = ./dashboards;
          foldersFromFilesStructure = false;
        };
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
