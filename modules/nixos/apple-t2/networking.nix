# T2 networkd policy matches only real USB Ethernet drivers.
# Never run blanket DHCP on the internal apple-bce bridge: its TX watchdog path can lock the kernel.
# mDNS supplies discovery before operator-managed Tailscale enrollment.
{ config, ... }:

{
  networking = {

    useDHCP = false;
    useNetworkd = true;

    nftables.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ config.services.tailscale.port ];
      trustedInterfaces = [ "tailscale0" ];
      checkReversePath = "loose";
    };
  };

  systemd.network = {
    enable = true;

    networks."10-usb-lan" = {
      matchConfig.Driver = "r8152 cdc_ether cdc_ncm ax88179_178a asix";
      networkConfig = {
        DHCP = "yes";
        IPv6AcceptRA = true;
      };
      linkConfig.RequiredForOnline = "routable";
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
