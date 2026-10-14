# Whole-disk Linux layout: recreates the ESP and removes macOS/recovery partitions.
# Keep ESP first, type EF00, mounted at /boot to match apple-t2/base.nix.
# Its 2 GiB size pairs with configurationLimit = 10; resizing either needs review.
# Keep disk swap below zram's priority 5. Virtual tests replace device paths and
# cannot establish the target's by-id identity or Apple firmware boot discovery.
# Generic rationale and test-size limits: ../modules/nixos/apple-t2/README.md.
{ ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/EXAMPLE-REPLACE-BEFORE-INSTALL";
    content = {
      type = "gpt";
      # Explicit priorities keep attribute renames from reordering partitions.
      partitions = {
        ESP = {
          priority = 1;
          name = "ESP";
          size = "2G";
          # disko defaults ordinary filesystems to 8300, not an EFI system partition.
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        swap = {
          priority = 2;
          size = "8G";
          content = {
            type = "swap";
            # Avoid per-page discard latency while the overflow tier is under pressure.
            discardPolicy = "once";
          };
        };

        root = {
          priority = 3;
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            # Compress store churn; keep container data independently snapshot-able.
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@home" = {
                mountpoint = "/home";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@containers" = {
                mountpoint = "/var/lib/containers";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };
  };
}
