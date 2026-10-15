# Reusable Incus system-container base. The composition supplies hostname and root SSH access.
# Guest lifecycle/enrollment is operator-managed. Activation keeps /sbin/init on the current system profile.
{ config, ... }:

{
  imports = [ ../shared ];

  boot.isContainer = true;

  system.activationScripts.lxcGuestInit = ''
    ln -sfn /nix/var/nix/profiles/system/init /sbin/init
  '';

  systemd.services.console-getty.enable = false;

  services.resolved.enable = true;
  networking.useHostResolvConf = false;

  services.prometheus.exporters.node = {
    enable = true;
    enabledCollectors = [ "systemd" "textfile" ];
    extraFlags = [
      "--collector.textfile.directory=/var/lib/node-exporter-textfile"
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
      trustedInterfaces = [ "tailscale0" ];
    };
  };

  services.tailscale.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "26.11";
}
