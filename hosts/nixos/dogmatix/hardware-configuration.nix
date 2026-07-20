# Hardware configuration for dogmatix.
#
# Filesystems and partitioning are declared in modules/nixos/dogmatix/disko.nix,
# not here — disko generates the fileSystems entries.
#
# The kernel module lists below are hand-written for Alder Lake-N and have not
# been checked against real detection output. Compare against
# `nixos-generate-config --show-hardware-config` on the machine once it boots.
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Alder Lake-N (N150) mini-PC: NVMe/M.2 boot, USB storage attached.
  # Verify against real detection output before trusting this list.
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "ahci"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sdhci_pci" # integrated eMMC
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  # mkDefault so the image builders (config.system.build.images.*) can override
  # these with their own generated layout. These values apply to a normal
  # install, where the partitions must carry the matching labels:
  #   mkfs.fat -F32 -n NIXOS_BOOT /dev/<esp>
  #   mkfs.ext4 -L NIXOS_ROOT /dev/<root>
  fileSystems."/" = {
    device = lib.mkDefault "/dev/disk/by-label/NIXOS_ROOT";
    fsType = lib.mkDefault "ext4";
  };

  fileSystems."/boot" = {
    device = lib.mkDefault "/dev/disk/by-label/NIXOS_BOOT";
    fsType = lib.mkDefault "vfat";
    options = lib.mkDefault [ "fmask=0077" "dmask=0077" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
