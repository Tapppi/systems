# Incus — the point of this host. LXC system containers, OCI application
# containers, and microVMs all run under it.
{ ... }:

{
  virtualisation.incus = {
    enable = true;
    # Keep the socket/daemon on the LTS channel; `package = pkgs.incus` would
    # track the feature channel instead.
  };

  # Incus' default bridge. Guests NAT out through it and need DHCP/DNS from the
  # host's dnsmasq, which means the bridge has to be trusted by the firewall.
  networking.firewall.trustedInterfaces = [ "incusbr0" ];

  # Guests are unprivileged and share the host kernel's inotify budget; the
  # default ceiling is easily exhausted by a handful of containers.
  boot.kernel.sysctl = {
    "fs.inotify.max_user_instances" = 1024;
    "fs.inotify.max_user_watches" = 1048576;
    "kernel.keys.maxkeys" = 2000;
  };

  users.users.tapani.extraGroups = [ "incus-admin" ];

  # NOTE: run `incus admin init` once after the first boot to create the
  # default storage pool and profile. Nothing here does that for you.
}
