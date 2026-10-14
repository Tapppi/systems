# Node, ZFS pool and Incus trust metrics.
# The firewall exposes these only through trusted interfaces. Poller failures preserve explicit error signals.
{ config, pkgs, ... }:

{
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9100;
    enabledCollectors = [
      "systemd" # unit states: incus, tailscaled, zfs services
      "zfs" # ARC hit rate and sizing against the 4 GiB arc_max cap
      "processes" # host-wide process/thread counts
      "textfile" # host-side gauges published from timers
    ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/node-exporter-textfile"
      "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run|var/lib/incus/storage-pools)($|/)"
      "--collector.systemd.enable-restarts-metrics"
    ];
  };
  systemd.tmpfiles.rules = [ "d /var/lib/node-exporter-textfile 0755 root root -" ];

  systemd.services.zpool-metrics = {
    serviceConfig.Type = "oneshot";
    path = [ config.boot.zfs.package pkgs.jq pkgs.coreutils ];
    script = ''
      set -u
      . ${../bench/poller-footer.sh}
      PREFIX=zpool
      OUT=/var/lib/node-exporter-textfile/zpool.prom
      TMP="$OUT.tmp"
      trap 'rm -f "$TMP"' EXIT
      ok=1
      : > "$TMP"

      list=$(zpool list -Hp -o name,size,alloc,free,fragmentation,capacity,health) || ok=0
      while IFS=$'\t' read -r name size alloc free frag cap health; do
        [ -n "$name" ] || continue
        echo "zpool_size_bytes{pool=\"$name\"} $size"
        echo "zpool_allocated_bytes{pool=\"$name\"} $alloc"
        echo "zpool_free_bytes{pool=\"$name\"} $free"
        echo "zpool_fragmentation_ratio{pool=\"$name\"} $frag"
        echo "zpool_capacity_ratio{pool=\"$name\"} $cap"
        if [ "$health" = "ONLINE" ]; then h=1; else h=0; fi
        echo "zpool_health_online{pool=\"$name\"} $h"
      done <<< "$list" >> "$TMP"

      st=$(zpool status -j --json-int) || ok=0
      printf '%s' "''${st:-}" | jq -r '
        .pools // {} | to_entries[] | .key as $p | .value as $x
        | "zpool_read_errors_total{pool=\"\($p)\"} \($x.vdevs[$p].read_errors)",
          "zpool_write_errors_total{pool=\"\($p)\"} \($x.vdevs[$p].write_errors)",
          "zpool_checksum_errors_total{pool=\"\($p)\"} \($x.vdevs[$p].checksum_errors)",
          "zpool_scan_errors{pool=\"\($p)\"} \($x.scan_stats.errors // 0)",
          "zpool_scrub_end_timestamp_seconds{pool=\"\($p)\"} \($x.scan_stats.end_time // 0)"
      ' >> "$TMP" || ok=0

      poller_footer
    '';
  };
  systemd.timers.zpool-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "60s";
    };
  };

  systemd.services.incus-trust-metrics = {
    serviceConfig.Type = "oneshot";
    path = [ config.virtualisation.incus.package pkgs.coreutils ];
    script = ''
      set -u
      . ${../bench/poller-footer.sh}
      PREFIX=incus_trust
      OUT=/var/lib/node-exporter-textfile/incus-trust.prom
      TMP="$OUT.tmp"
      trap 'rm -f "$TMP"' EXIT
      ok=1
      {
        echo '# HELP incus_trust_cert_expiry_timestamp_seconds Unix time a trust certificate expires.'
        echo '# TYPE incus_trust_cert_expiry_timestamp_seconds gauge'
      } > "$TMP"

      trust=$(incus config trust list --format csv) || ok=0
      while IFS=, read -r cname ctype _desc _fp cexp; do
        [ -n "''${cexp:-}" ] || continue
        epoch=$(LC_ALL=C date -d "$cexp" +%s 2>/dev/null) || continue
        echo "incus_trust_cert_expiry_timestamp_seconds{name=\"$cname\",type=\"$ctype\"} $epoch"
      done <<< "''${trust:-}" >> "$TMP"

      poller_footer
    '';
  };
  systemd.timers.incus-trust-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "24h";
      Persistent = true;
    };
  };
}
