# Host-level metrics. The Incus metrics endpoint covers the guests' cgroups
# but says nothing about the substrate they share — host CPU pressure, ZFS
# ARC and pool capacity, the physical NICs, eMMC wear headroom. node_exporter
# supplies those, and bench-obs scrapes it at dogmatix:9100.
#
# Bound to all interfaces rather than a fixed address: both paths the
# scraper can arrive on (tailscale0 and incusbr0) are trusted interfaces and
# neither has a stable address at unit start. Port 9100 is only reachable
# through those two, never from the LAN — the firewall opens no hole for it.
{ config, ... }:

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
    ];
  };
  systemd.tmpfiles.rules = [ "d /var/lib/node-exporter-textfile 0755 root root -" ];

  # ZFS pool capacity and health are not in the kernel stats node_exporter
  # reads, so `zpool list` is sampled into the textfile collector instead.
  systemd.services.zpool-metrics = {
    serviceConfig.Type = "oneshot";
    # boot.zfs.package, not pkgs.zfs: the userland has to be the same build as
    # the loaded kernel module.
    script = ''
      set -eu
      OUT=/var/lib/node-exporter-textfile/zpool.prom
      TMP="$OUT.tmp"
      : > "$TMP"
      ${config.boot.zfs.package}/bin/zpool list -Hp -o name,size,alloc,free,fragmentation,capacity,health \
      | while IFS=$'\t' read -r name size alloc free frag cap health; do
        echo "zpool_size_bytes{pool=\"$name\"} $size" >> "$TMP"
        echo "zpool_allocated_bytes{pool=\"$name\"} $alloc" >> "$TMP"
        echo "zpool_free_bytes{pool=\"$name\"} $free" >> "$TMP"
        echo "zpool_fragmentation_ratio{pool=\"$name\"} $frag" >> "$TMP"
        echo "zpool_capacity_ratio{pool=\"$name\"} $cap" >> "$TMP"
        if [ "$health" = "ONLINE" ]; then h=1; else h=0; fi
        echo "zpool_health_online{pool=\"$name\"} $h" >> "$TMP"
      done
      mv "$TMP" "$OUT"
    '';
  };
  systemd.timers.zpool-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "60s";
    };
  };
}
