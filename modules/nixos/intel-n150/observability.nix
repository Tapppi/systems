# Listen on all addresses so scrapes tolerate overlay/bridge address changes.
# With networking.nix and incus.nix, only tailscale0/incusbr0 are trusted and
# no LAN rule opens 9100 (exporter.openFirewall defaults false). Consumers
# changing that firewall composition must preserve the intended scrape boundary.
{ config, pkgs, ... }:

{
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 9100;
    enabledCollectors = [
      "systemd" # unit states: incus, tailscaled, zfs services
      "zfs" # ARC counters; the composition owns any memory cap
      "processes" # host-wide process/thread counts
      "textfile" # host-side gauges published from timers
    ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/node-exporter-textfile"
      # Guest dataset mounts would add host filesystem series for Incus storage.
      # Pool-level capacity is sampled below instead of treating each as a disk.
      "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run|var/lib/incus/storage-pools)($|/)"
      # NRestarts exposes automatic restarts even when the service is active
      # again before the next scrape; unit state alone misses that failure.
      "--collector.systemd.enable-restarts-metrics"
    ];
  };
  systemd.tmpfiles.rules = [ "d /var/lib/node-exporter-textfile 0755 root root -" ];

  # Supplement the exporter's kernel ZFS stats with CLI capacity, vdev errors
  # and scrub times. Capture command status before parsing; the shared footer
  # atomically publishes failure/last-success signals even on a failed poll.
  # Consumers must use those signals before trusting partial or absent gauges.
  systemd.services.zpool-metrics = {
    serviceConfig.Type = "oneshot";
    # Follow the host's selected ZFS userspace, whose version NixOS checks
    # against the kernel module, rather than an unrelated pkgs.zfs default.
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

  # Expose trust-certificate expiry before authenticated metrics scrapes fail.
  # Keep this daily poll independent of the minute-scale ZFS poll: an Incus
  # failure must not invalidate pool metrics, nor a ZFS failure certificate data.
  # The pinned CLI defaults to CSV columns n,t,d,f,e; the parser below depends
  # on that order and expects simple comma-free fields. Recheck on Incus updates.
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
