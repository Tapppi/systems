# Shared base for bench-* NixOS LXC guests under Incus on dogmatix
# (workflow-engine bench; see tieto goldmill/wiki/reviews/bench/).
#
# Guest *contents* are declarative via this flake; guest *lifecycle* is
# imperative Incus until HLB-9/kone land:
#   incus launch images:nixos/unstable <name> -p default -p bench-guest
# The bench-guest Incus profile carries the /dev/net/tun device Tailscale
# needs. Deploy/update by pushing this repo into the guest and running
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
  imports = [ ../../shared ];

  # NixOS-in-LXC: systemd container mode, no kernel or bootloader managed
  # inside the guest.
  boot.isContainer = true;

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

  # Each guest is its own tailnet node (bench-<name>), giving per-service
  # names and ACL granularity. Daemon only — join once by hand:
  #   incus exec <name> -- tailscale up --ssh
  # The node key persists in /var/lib/tailscale across rebuilds.
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
