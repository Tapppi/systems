# ZFS support and maintenance. Supply networking.hostId, boot.zfs.extraPools and the ARC limit in the composition.
{ ... }:

{
  boot.supportedFilesystems = [ "zfs" ];




  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly";
    };
    trim.enable = true;
  };
}
