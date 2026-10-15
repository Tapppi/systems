# Evaluation/build example. Filesystem labels are assumptions, not installation actions.
{ ... }:
{
  imports = [ ./intel-n150-hardware.nix ];
  networking.hostName = "nixos-intel-n150";
  networking.hostId = "01234567";
  boot.zfs.extraPools = [ "examplepool" ];
  boot.kernelParams = [ "zfs.zfs_arc_max=4294967296" ];
  users.users.demo = { isNormalUser = true; extraGroups = [ "wheel" "incus-admin" ]; };
}
