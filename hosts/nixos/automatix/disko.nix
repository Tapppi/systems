# Declarative disk layout for automatix's internal SSD.
#
# The first host in this repo to use disko. dogmatix partitions imperatively
# through a hand-written script because it predates the decision; nixos-anywhere
# requires disko, and ADR-001 makes nixos-anywhere the onboarding path.
#
# On a T2 Mac the internal storage presents as an ordinary NVMe device — the T2
# sits in front of it but the mainline `nvme` driver drives it, via quirks
# upstream since Linux 5.4 — so this is a whole-disk GPT wipe like any other
# machine. No Apple partition is preserved: macOS is not being kept, and the
# T2's own firmware lives on the T2, not in this disk's namespace, so nothing
# written here can reach it.
#
# ⚠️ VERIFY THE DEVICE PATH FROM THE BOOTED INSTALLER BEFORE THE FIRST RUN:
#
#   udevadm info -q symlink -n /dev/nvme0n1 | tr ' ' '\n' | grep by-id
#   lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE
#
# The string below was predicted from macOS's reported model and serial
# (`APPLE SSD AP0512M`, `C0283720041JP7G1A`), not read from Linux. udev builds
# it as `nvme-<model>_<serial>_<nsid>`, replacing interior whitespace with
# underscores and stripping the kernel's trailing field padding — hence
# `APPLE_SSD_AP0512M`. The `_1` namespace suffix is deliberate: systemd's own
# rules call the unsuffixed form obsolete and warn it "might get overridden on
# adding a new nvme controller".
#
# This is the one error `nixos-anywhere --vm-test` cannot catch — disko's test
# harness rewrites every device to /dev/vdX, so a wrong path passes the VM test
# and then wipes nothing, or the wrong thing, on the real machine.
#
# by-id rather than /dev/nvme0n1 because the failure mode that matters is
# "wiped the wrong disk", and a name derived from the disk's own serial is the
# one that guards against it. Note `device` is only used for the create step —
# every downstream reference is by partlabel — so a wrong value fails loudly at
# partition time rather than leaving a fragile installed system.
#
# ⚠️ THE ESP IS RECREATED, NOT REUSED, AND THAT IS THE RISK IN THIS FILE.
# Every t2linux distro guide says to keep Apple's own 300 MB ESP and mount it
# at /boot, on the grounds that a boot picker known to find that partition is
# worth more than a tidy layout. Nobody documents deleting and recreating it.
#
# It is recreated anyway, for two reasons. Apple's ESP is 314.6 MB, and
# systemd-boot copies every generation's kernel and initrd into it — at roughly
# 100 MB each that is barely two generations, on the host that rebuilds most.
# And a working headless T2 NixOS server (syntheit/nix, hosts/vista) does
# exactly this whole-disk wipe with a disko-created 2 GiB ESP, which makes it
# demonstrated rather than merely plausible.
#
# If the machine does not appear in the Startup Manager after install, this is
# the first thing to suspect; the fallback is to shrink the layout and reuse a
# 300 MB first partition instead.
{ ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-APPLE_SSD_AP0512M_C0283720041JP7G1A_1";
    content = {
      type = "gpt";
      # Priorities are pinned rather than left to default. disko creates
      # partitions in priority order and falls back to alphabetical attribute
      # order on ties, so without these a rename could silently reorder the
      # disk.
      partitions = {
        ESP = {
          priority = 1;
          name = "ESP";
          # 2 GiB against dogmatix's 1 GiB. systemd-boot copies every
          # generation's kernel and initrd here, and this host rebuilds far
          # more often than dogmatix does — it is the builder. At roughly
          # 100 MB a generation, 2 GiB is comfortable for the
          # configurationLimit set in base.nix.
          size = "2G";
          # Explicit, and load-bearing: disko's default partition type is 8300.
          # An ESP without the EF00 type GUID is not discoverable as an ESP,
          # and on a Linux-only T2 Mac that surfaces only after macOS is gone,
          # with no second OS to repair it from.
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        # The overflow tier under zram, which base.nix enables and which is
        # what actually keeps this machine responsive. dogmatix runs swapless
        # because it is a thin container substrate where swap would only mask
        # overcommit; here a linker that briefly wants more than 16 GB is a
        # normal Tuesday, and the alternative to swap is a failed build.
        swap = {
          priority = 2;
          size = "8G";
          content = {
            type = "swap";
            # TRIM the whole area once at swapon, rather than on every freed
            # page — per-page discard adds latency exactly when the machine is
            # already under memory pressure.
            discardPolicy = "once";
          };
        };

        root = {
          priority = 3;
          size = "100%";
          content = {
            type = "btrfs";
            # The disk has carried macOS since 2018; without this, mkfs
            # refuses on finding the existing APFS signature.
            extraArgs = [ "-f" ];
            # btrfs rather than dogmatix's ext4, bought for two runtime
            # properties rather than for backups — the DR model is still
            # reinstall-from-config plus restore-from-NAS, so nothing here
            # depends on send/receive.
            #
            # zstd on /nix is the big one: the Nix store compresses well, and
            # this host is the builder that churns it. Subvolumes also give
            # container storage somewhere sane to live, and leave the door
            # open to snapshots without a reinstall.
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
              # Container images and volumes. Its own subvolume so it can be
              # snapshotted, or excluded from snapshots, independently of the
              # root filesystem.
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
