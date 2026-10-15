# DHCP server networking with key-only SSH, mDNS and an authenticated Tailscale overlay.
# Tailscale enrollment is a separate operator action; its state persists under /var/lib/tailscale.
{ config, ... }:

{
  networking = {
    useDHCP = true;

    nftables.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ config.services.tailscale.port ];
      trustedInterfaces = [ "tailscale0" ];
      checkReversePath = "loose"; # required for Tailscale's exit-node handling
    };
  };

  services.tailscale.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };
}
