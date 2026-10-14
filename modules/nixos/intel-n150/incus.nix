# Incus server and kernel budgets for unprivileged guests.
# Initialize storage/profiles separately with incus admin init; grant incus-admin membership in the composition.
{ ... }:

{
  virtualisation.incus = {
    enable = true;
  };

  networking.firewall.trustedInterfaces = [ "incusbr0" ];

  boot.kernel.sysctl = {
    "fs.inotify.max_user_instances" = 1024;
    "fs.inotify.max_user_watches" = 1048576;
    "kernel.keys.maxkeys" = 2000;
  };


}
