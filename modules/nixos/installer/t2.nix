# T2 installer capability with the patched hardware kernel.
# ZFS is disabled because the T2 kernel is not a supported ZFS build target.
{ inputs, lib, ... }:

{
  imports = [
    ./default.nix
    ../apple-t2/kernel-patches.nix
    inputs.nixos-hardware.nixosModules.apple-t2
  ];


  nix.settings = {
    extra-substituters = [ "https://cache.soopy.moe" ];
    extra-trusted-public-keys = [
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };

  boot.supportedFilesystems.zfs = lib.mkForce false;

}
