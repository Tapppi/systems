# bench-obs: bench observability guest — Prometheus, Grafana,
# postgres_exporter, and the Incus per-guest metrics scrape (tieto
# goldmill/wiki/reviews/bench/phase0-summary.md, phase 1 step 3).
#
# Secrets (all out-of-repo, root-only on the guest):
#   /root/bench-secrets.env  — DATA_SOURCE_NAME for postgres_exporter
#   /var/lib/prometheus-incus/incus-metrics.{crt,key} — client cert trusted
#     by the host's Incus metrics endpoint (10.135.155.1:8444,
#     --type=metrics). Deliberately outside /root: prometheus runs as its
#     own user and must traverse the containing directory, which /root's
#     0700 forbids even with a bind mount of the files themselves.
{ ... }:

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
        static_configs = [{
          targets = [
            "localhost:9100"
            "bench-absurd:9100"
            "bench-temporal:9100"
          ];
        }];
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

  services.prometheus.exporters.postgres = {
    enable = true;
    environmentFile = "/root/bench-secrets.env"; # DATA_SOURCE_NAME=...
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
