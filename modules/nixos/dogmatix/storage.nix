# NVMe workload storage: single-disk ZFS pool `vmpool` for Incus guests.
#
# Disk roles on this box: the eMMC is the boot/system disk (with the raw-efi
# USB stick as resident backup boot), the 512 GB Intel 660p NVMe is
# non-replicated local workload storage per the primary-worker storage class
# (<3 disks -> no replication; recovery is reinstall-from-config +
# restore-from-NAS, so pool loss is acceptable-loss for anything not
# NAS-synced).
#
# The pool itself is created imperatively once (whole-disk):
#   zpool create -o ashift=12 -O compression=zstd -O atime=off \
#     -O xattr=sa -O acltype=posixacl -o autotrim=on vmpool /dev/nvme0n1
#   zfs create vmpool/incus
#   incus storage create vmpool zfs source=vmpool/incus
# This module makes the host import and mount it at boot.
{ ... }:

{
  boot.supportedFilesystems = [ "zfs" ];

  # ZFS requires a stable host id; derived once from the hostname, identical
  # across boot media so both the eMMC system and the backup USB stick can
  # import the pool.
  networking.hostId = "8f8113a5";

  # The pool holds no filesystems the boot needs; import it explicitly.
  boot.zfs.extraPools = [ "vmpool" ];

  # Cap the ARC at 4 GiB: 12 GB total RAM must leave room for Incus guests.
  boot.kernelParams = [ "zfs.zfs_arc_max=4294967296" ];

  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "monthly";
    };
    trim.enable = true;
  };
}
