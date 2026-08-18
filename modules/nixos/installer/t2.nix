# konehuone-installer-t2 — the installer image, for Apple T2 Macs.
#
# Same image as ./default.nix plus the patched t2linux kernel. It exists as a
# second artifact rather than as the only one because the T2 kernel comes from
# a third-party binary cache, and every other host in the fleet should be
# installable without depending on that.
#
# Why a T2 Mac needs its own installer at all, given a stock NixOS ISO does
# boot on one and can see the internal NVMe (the mainline `nvme` driver has
# handled Apple's controller since Linux 5.4): the internal keyboard is dead
# without `apple-bce`. On a machine that is going to be driven entirely over
# SSH that would not matter — except that it removes the only fallback if the
# network does not come up, and this machine's sole NIC is a USB dongle.
#
# It is also what makes the no-kexec path worth having. nixos-anywhere's
# generic kexec image carries a stock kernel; kexec'ing into it on a T2 would
# hand the installer a machine with no console. Booting this instead means the
# running kernel is, by construction, one that already works on the hardware.
{ inputs, lib, ... }:

{
  imports = [
    ./default.nix
    inputs.nixos-hardware.nixosModules.apple-t2
  ];

  networking.hostName = lib.mkForce "konehuone-installer-t2";

  # Without this the patched kernel is compiled from source, which is hours,
  # and on an installer image would be hours spent rebuilding a kernel into a
  # tmpfs-backed store that will run out of space first.
  nix.settings = {
    extra-substituters = [ "https://cache.soopy.moe" ];
    extra-trusted-public-keys = [
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };

  # ZFS is dropped here, unlike the generic image. The base image carries it so
  # it can double as the DR restore stick, but ZFS tracks a moving target of
  # supported kernel versions and the t2linux kernel is not one it is tested
  # against — a version bump that breaks the module would take the installer
  # with it. No T2 host in this fleet uses ZFS: automatix is btrfs.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # mkOverride 40 rather than mkForce: the base module already uses mkForce
  # (priority 50) to beat the upstream iso-image defaults, and two mkForces on
  # one option is a conflict rather than an override. 40 wins over 50.
  image.baseName = lib.mkOverride 40 "konehuone-installer-t2";
  isoImage.volumeID = lib.mkOverride 40 "KONEHUONE_T2";
}
