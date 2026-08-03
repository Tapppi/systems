# Host-level metrics. The Incus metrics endpoint covers the guests' cgroups
# but says nothing about the substrate they share — host CPU pressure, ZFS
# ARC and pool capacity, the physical NICs, eMMC wear headroom. node_exporter
# supplies those, and bench-obs scrapes it at dogmatix:9100.
#
# Bound to all interfaces rather than a fixed address: both paths the
# scraper can arrive on (tailscale0 and incusbr0) are trusted interfaces and
# neither has a stable address at unit start. Port 9100 is only reachable
# through those two, never from the LAN — the firewall opens no hole for it.
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
      # One filesystem series per guest dataset otherwise: Incus mounts each
      # container's ZFS dataset under storage-pools/, and they all report the
      # same pool free space.
      "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|run|var/lib/incus/storage-pools)($|/)"
      # A daemon that crashes and is restarted by systemd is `active` again
      # long before the next 15 s scrape, so unit state alone cannot see it.
      # This counter is the only signal that distinguishes a service which is
      # running from one which is merely running *again*.
      "--collector.systemd.enable-restarts-metrics"
    ];
  };
  systemd.tmpfiles.rules = [ "d /var/lib/node-exporter-textfile 0755 root root -" ];

  # ZFS pool capacity, health and error counters are not in the kernel stats
  # node_exporter reads, so they are sampled into the textfile collector.
  systemd.services.zpool-metrics = {
    serviceConfig.Type = "oneshot";
    # boot.zfs.package, not pkgs.zfs: the userland has to be the same build as
    # the loaded kernel module.
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

      # Captured before writing, and never piped straight into the loop: a
      # failing zpool would otherwise hide behind the pipeline's exit status
      # and publish an empty file, which a dashboard reads as "no pools" —
      # indistinguishable from a healthy pool that is simply not there.
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

      # vmpool is a single non-replicated disk by design, so a checksum error
      # is unrecoverable data loss rather than something a resilver repairs.
      # `zpool status -j` reports every pool in one document, with the counters
      # and scrub timestamps as integers — which is also what avoids parsing a
      # locale-formatted date out of the human output.
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

  # The Incus metrics scrape authenticates with a client certificate, and an
  # expired trust entry kills it silently: a scrape pool that cannot be built
  # emits no `up` series at all, so the failure reads as absence rather than
  # as a target being down. Publishing the expiry makes that cliff visible
  # years ahead of it.
  #
  # Its own unit rather than a block inside zpool-metrics, for two reasons: an
  # `incus` CLI failure must not mark the ZFS gauges untrustworthy, and the
  # alert threshold is thirty days — sampling that once a minute would spend a
  # Go CLI startup 1440 times a day to re-read a date that moves once a decade.
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
