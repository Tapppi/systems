# Hardware configuration for dogmatix.
#
# Hand-written, not generated. The kernel module lists are for Alder Lake-N and
# the filesystem entries use partition labels rather than real UUIDs. Replace
# with `nixos-generate-config --show-hardware-config` output taken on the
# machine after the first install, keeping the label-based fileSystems only if
# the install partitions are labelled NIXOS_ROOT / NIXOS_BOOT to match.
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
    # eMMC: sdhci_pci is the host controller, mmc_block the block driver.
    # Both are required in initrd to mount root on /dev/mmcblk0p2, which is
    # the primary install target — without mmc_block boot drops to an initrd
    # emergency shell.
    "sdhci_pci"
    "mmc_block"
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
