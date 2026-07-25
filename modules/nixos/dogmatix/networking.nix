# Hostname, DHCP, firewall, and the Tailscale overlay.
{ config, ... }:

{
  networking = {
    hostName = "dogmatix";
    # Both 2.5GbE NICs take DHCP. Interface names are not known until first
    # boot; the global flag covers whatever they turn out to be. Revisit with
    # explicit per-interface config (and static addressing) when this box takes
    # on routing duties.
    useDHCP = true;

    # Incus wants nftables; the firewall below is built on top of it.
    nftables.enable = true;

    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      # Lets the Tailscale daemon pick its ephemeral port without a hole in the
      # firewall for every possible one.
      allowedUDPPorts = [ config.services.tailscale.port ];
      # Traffic arriving over the overlay is already authenticated by Tailscale.
      trustedInterfaces = [ "tailscale0" ];
      checkReversePath = "loose"; # required for Tailscale's exit-node handling
    };
  };

  # NOTE: this only installs and starts the daemon. The node is NOT on the
  # tailnet until you log in once, by hand, on the machine:
  #
  #   sudo tailscale up --ssh
  #
  # The resulting node key persists in /var/lib/tailscale across rebuilds.
  services.tailscale.enable = true;

  # mDNS so a headless, DHCP-addressed box is reachable as `dogmatix.local`
  # without hunting for its lease on the router. Resolves the "how do I find
  # the IP to ssh in" gap on first boot.
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
