# PLACEHOLDER hardware configuration for dogmatix.
#
# !!! THIS FILE IS NOT REAL HARDWARE DETECTION OUTPUT !!!
#
# The filesystem entries below use *labels*, not the real device UUIDs, because
# the machine has never been booted with this config and no UUIDs are known.
# Replace this whole file with the output of:
#
#   nixos-generate-config --root /mnt --show-hardware-config
#
# run from the NixOS installer after partitioning, then commit the result.
#
# If you instead keep this file as-is, you MUST label the partitions to match
# during installation:
#
#   mkfs.fat -F32 -n NIXOS_BOOT /dev/<esp>
#   mkfs.ext4 -L NIXOS_ROOT /dev/<root>
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

  # PLACEHOLDER — replace with real by-uuid paths from nixos-generate-config.
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_ROOT";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXOS_BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # The 128GB boot drive is small; a swapfile is likely wanted once the real
  # layout is known. Left empty deliberately.
  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
