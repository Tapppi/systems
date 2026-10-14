# Match USB Ethernet drivers instead of blanket DHCP: the internal apple-bce
# bridge is not a LAN NIC, and its transmit/watchdog path has caused T2 lockups.
# Driver matches also tolerate replacement dongles without a host-specific MAC.
# See README.md; Tailscale still requires a working physical network path.
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
