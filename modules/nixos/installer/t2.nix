# T2 installer: retain apple-bce console input while installing over SSH.
# A generic kexec image can replace this working kernel with one lacking that
# input support. Use the no-kexec installer path; see ../apple-t2/README.md.
# Keep this image separate so generic installers do not inherit the T2 kernel/cache.
{ inputs, lib, ... }:

{
  imports = [
    ./default.nix
    ../apple-t2/kernel-patches.nix
    inputs.nixos-hardware.nixosModules.apple-t2
  ];


  # Match the installed host's kernel adaptations. A cache hit still requires
  # identical derivation inputs; build missing outputs before booting the ISO.
  nix.settings = {
    extra-substituters = [ "https://cache.soopy.moe" ];
    extra-trusted-public-keys = [
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };

  # The generic rescue image enables ZFS. Disable it here so an out-of-tree
  # ZFS/kernel compatibility constraint cannot break the T2 installer build.
  # This image consequently cannot serve as a ZFS recovery environment.
  boot.supportedFilesystems.zfs = lib.mkForce false;

}
