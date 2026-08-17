# Shared base for NixOS LXC system containers under Incus on dogmatix.
#
# Guest *contents* are declarative via this flake; guest *lifecycle* is
# imperative Incus until HLB-9/kone land:
#   incus launch images:nixos/unstable <name> -p default -p <guest-profile>
# The guest profile carries the /dev/net/tun device Tailscale needs; what else
# it carries differs per guest family (see the modules that import this).
# Deploy/update by pushing this repo into the guest and running
#   nixos-rebuild switch --flake /root/systems#<name>
# (or nixos-rebuild --target-host over the tailnet once the guest is joined).
# Keep these modules plain — no option abstractions.
{ config, ... }:

let
  keys = [
    # "Asterix Identity" — the single fleet key, held in 1Password. See
    # modules/nixos/dogmatix/users.nix for retrieval notes and decoys to
    # avoid.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmxkJJ/WnwVmYdvylfvp4D+qOAcNMQ/gzFLGkPXVVJ5"
  ];
in
{
  imports = [ ../shared ];

  # NixOS-in-LXC: systemd container mode, no kernel or bootloader managed
  # inside the guest.
  boot.isContainer = true;

  # The images:nixos LXC image ships /sbin/init as a static symlink into the
  # image's original store path, so a plain nixos-rebuild switch would boot
  # back into the image generation on restart. Keep init pointed at the
  # system profile instead (idempotent; runs on every activation).
  system.activationScripts.lxcGuestInit = ''
    ln -sfn /nix/var/nix/profiles/system/init /sbin/init
  '';

  # No console TTY is attached under Incus; the unit just flaps and turns
  # every switch-to-configuration into exit 4. Access is incus exec + SSH.
  systemd.services.console-getty.enable = false;

  # MagicDNS (bare guest names) needs a resolv manager for tailscaled to
  # program. isContainer defaults to the host's resolv.conf, which resolved
  # rejects — the guest manages its own.
  services.resolved.enable = true;
  networking.useHostResolvConf = false;

  # Every guest exports node metrics; bench-obs scrapes them over the
  # tailnet. The textfile collector lets guests publish custom gauges (e.g.
  # absurd queue depth) from timers.
  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" "textfile" ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/node-exporter-textfile"
      # A service that crashes and is restarted is `active` again well before
      # the next 15 s scrape, so unit state alone cannot distinguish running
      # from running *again*. This counter is the only signal that does.
      "--collector.systemd.enable-restarts-metrics"
    ];
  };
  systemd.tmpfiles.rules = [ "d /var/lib/node-exporter-textfile 0755 root root -" ];

  networking = {
    useDHCP = true; # eth0 from incusbr0 (NAT)
    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ config.services.tailscale.port ];
      # Traffic over the overlay is already authenticated by Tailscale.
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  # Each guest is its own tailnet node, giving per-service names and ACL
  # granularity. Daemon only — the join is a one-time `tailscale up` by hand
  # whose flags differ per guest, so each guest documents its own. The node
  # key persists in /var/lib/tailscale across rebuilds.
  services.tailscale.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };
  users.users.root.openssh.authorizedKeys.keys = keys;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.11";
}
