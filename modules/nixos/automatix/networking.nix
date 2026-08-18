# Networking. Deliberately different from dogmatix's, for one reason: this
# machine has no built-in ethernet, and the NIC it does have must not be
# confused with the fake one the T2 provides.
#
# The T2 exposes an internal USB-ish "bridge" network interface (MAC
# ac:de:48:00:11:22) that is never connected to anything. A DHCP client that
# retries on it can hard-lock the kernel: a TX stall fires the netdev watchdog
# in softirq context, and apple-bce's URB-cancel path sleeps there — verified
# on another headless T2 NixOS host, recovered only by a power cycle.
#
# dogmatix's blanket `networking.useDHCP = true` would do exactly that here, so
# this host runs systemd-networkd with explicit matches instead. An interface
# with no matching .network file is left completely alone, which makes the T2
# bridge a non-event rather than something to remember to exclude.
{ config, ... }:

{
  networking = {
    hostName = "automatix";

    # systemd-networkd, default-deny: only what is matched below is configured.
    useDHCP = false;
    useNetworkd = true;

    nftables.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ config.services.tailscale.port ];
      trustedInterfaces = [ "tailscale0" ];
      # Tailscale's own guidance for a node that may see asymmetric routing.
      checkReversePath = "loose";
    };
  };

  systemd.network = {
    enable = true;

    # The USB gigabit adapter that is this machine's only real NIC — a Realtek
    # RTL8153 (0bda:8153), MAC 00:e0:4c:68:51:b8, driven by mainline r8152.
    #
    # Matched on driver rather than MAC so that replacing the dongle with
    # another Realtek adapter does not strand a headless machine, while still
    # excluding the T2 bridge by construction: apple-bce is a different driver
    # and can never match this. The other names cover the usual USB-NIC
    # chipsets, so a spare from the drawer also works.
    networks."10-usb-lan" = {
      matchConfig.Driver = "r8152 cdc_ether cdc_ncm ax88179_178a asix";
      networkConfig = {
        DHCP = "yes";
        # Nothing here should ever become the LAN's DNS or hand out routes.
        IPv6AcceptRA = true;
      };
      # A headless host with one NIC should keep trying rather than give up.
      linkConfig.RequiredForOnline = "routable";
    };
  };

  # Joined once by hand, as this fleet's other hosts are:
  #   sudo tailscale up --ssh
  # The node key is persisted under /var/lib/tailscale and survives rebuilds.
  #
  # This matters more here than elsewhere. Tailscale is the second way in when
  # the USB adapter's LAN side is the thing that broke, and on a machine with
  # no console it is the difference between a fix and a car journey.
  services.tailscale.enable = true;

  # mDNS, so the box answers to automatix.local before it is on the tailnet —
  # which is exactly the window during and just after an install.
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
