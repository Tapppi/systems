#!/usr/bin/env bash
# Install NixOS to dogmatix's internal eMMC from the minimal installer live
# environment. Run as root (sudo -i) on the n150 mini-PC itself.
#
# Encodes the eMMC install runbook from SYSMI-58: partition, format, mount,
# nixos-install. Does NOT reboot at the end — that is a deliberate manual
# step so the installer USB is not pulled before the operator has confirmed
# the install actually succeeded.
#
# Usage: install-dogmatix-emmc.sh [--target <disk>] [--flake <path>] [--yes] [--force-size]
#   --target <disk>   block device to install to (default: /dev/mmcblk0)
#   --flake <path>    path to the systems flake (default: /root/systems)
#   --yes             skip the interactive confirmation prompt
#   --force-size      skip the 50-70 GB target-size sanity check

set -euo pipefail

TARGET=/dev/mmcblk0
FLAKE=/root/systems
ASSUME_YES=0
FORCE_SIZE=0

usage() {
  cat <<'EOF'
Usage: install-dogmatix-emmc.sh [--target <disk>] [--flake <path>] [--yes] [--force-size]

  --target <disk>   block device to install to (default: /dev/mmcblk0)
  --flake <path>    path to the systems flake (default: /root/systems)
  --yes             skip the interactive confirmation prompt
  --force-size      skip the 50-70 GB target-size sanity check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      if [[ $# -lt 2 ]]; then
        echo "!! --target requires a value" >&2
        usage >&2
        exit 1
      fi
      TARGET="$2"
      shift 2
      ;;
    --flake)
      if [[ $# -lt 2 ]]; then
        echo "!! --flake requires a value" >&2
        usage >&2
        exit 1
      fi
      FLAKE="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --force-size)
      FORCE_SIZE=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "!! unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "!! must be run as root (sudo -i)" >&2
  exit 1
fi

# The eMMC root partition gets mounted at /mnt in step 3/5, which would
# shadow (or on unmount, orphan) a flake staged anywhere under /mnt — and
# the existence check below runs before partitioning, so it would pass and
# nixos-install would then fail against an empty /mnt. Refuse it outright.
case "$FLAKE" in
  /mnt | /mnt/*)
    echo "!! --flake must not be under /mnt: $FLAKE" >&2
    echo "   /mnt is where the eMMC root partition gets mounted in step 3/5," >&2
    echo "   which would shadow the flake before nixos-install can read it." >&2
    echo "   Stage the repo elsewhere first, e.g. /root/systems or /tmp/systems." >&2
    exit 1
    ;;
esac

echo "==> safety checks"

# Refuse the M.2 outright, regardless of what --target says. This is the
# 128 GB Intel M.2 in dogmatix, never the intended install target.
if [[ "$TARGET" == "/dev/nvme0n1" ]]; then
  echo "!! refusing to touch /dev/nvme0n1 — that is the M.2, not the eMMC" >&2
  exit 1
fi

if [[ ! -e "$TARGET" ]]; then
  echo "!! target does not exist: $TARGET" >&2
  exit 1
fi
if [[ ! -b "$TARGET" ]]; then
  echo "!! target is not a block device: $TARGET" >&2
  exit 1
fi

# Resolve a mount SOURCE (as reported by findmnt) down to the whole-disk
# device backing it, so it can be compared against $TARGET. Handles three
# shapes: a loop device (ISO squashfs — resolve to its backing file, then to
# the disk holding that file), a plain partition (resolve via PKNAME), and a
# mount served directly off a whole disk (already the answer). --nodeps is
# load-bearing: without it, lsblk on a whole-disk argument walks its
# partitions too and prints one row per partition instead of one row total.
resolve_disk_for_source() {
  local source="$1" backing type pk
  if [[ "$source" =~ ^/dev/loop ]]; then
    backing="$(losetup -nO BACK-FILE "$source" 2>/dev/null || true)"
    if [[ -n "$backing" ]]; then
      source="$(df --output=source "$backing" 2>/dev/null | tail -n1)"
    fi
  fi
  [[ -z "$source" ]] && return 1
  type="$(lsblk -ndo TYPE --nodeps "$source" 2>/dev/null || true)"
  if [[ "$type" == "disk" ]]; then
    echo "$source"
    return 0
  fi
  pk="$(lsblk -ndo PKNAME --nodeps "$source" 2>/dev/null || true)"
  if [[ -n "$pk" ]]; then
    echo "/dev/$pk"
  else
    echo "$source"
  fi
}

# Refuse to touch whatever disk backs the running live system, whether that
# is the installer ISO's own mount or the read-only nix store squashfs.
for probe in /iso /nix/.ro-store; do
  live_source="$(findmnt -no SOURCE --target "$probe" 2>/dev/null | head -n1 || true)"
  [[ -z "$live_source" ]] && continue
  live_disk="$(resolve_disk_for_source "$live_source" || true)"
  [[ -z "$live_disk" ]] && continue
  if [[ "$live_disk" == "$TARGET" ]]; then
    echo "!! target $TARGET backs the running live system (via $probe, source $live_source) — refusing" >&2
    exit 1
  fi
done

if [[ "$FORCE_SIZE" -ne 1 ]]; then
  size_bytes="$(blockdev --getsize64 "$TARGET")"
  size_gb=$((size_bytes / 1000 / 1000 / 1000))
  if [[ "$size_gb" -lt 50 || "$size_gb" -gt 70 ]]; then
    echo "!! target $TARGET is ${size_gb} GB, expected 50-70 GB for the eMMC" >&2
    echo "   pass --force-size to override" >&2
    exit 1
  fi
fi

if [[ ! -d "$FLAKE" ]]; then
  echo "!! flake path does not exist: $FLAKE" >&2
  echo "   rsync or clone the systems repo there first, e.g.:" >&2
  echo "     mkdir -p '$FLAKE' && rsync -a asterix:project/github/tapppi/systems/ '$FLAKE/'" >&2
  exit 1
fi

# mmcblk devices need a "p" before the partition number (mmcblk0p1), sdX
# devices do not (sda1). Work out the suffix once and reuse it.
if [[ "$TARGET" =~ [0-9]$ ]]; then
  PART_SUFFIX=p
else
  PART_SUFFIX=""
fi
PART1="${TARGET}${PART_SUFFIX}1"
PART2="${TARGET}${PART_SUFFIX}2"

echo "==> plan"
lsblk
echo
echo "    target:     $TARGET"
echo "    partitions: $PART1 (ESP), $PART2 (root)"
echo "    flake:      ${FLAKE}#dogmatix"

if [[ "$ASSUME_YES" -ne 1 ]]; then
  echo
  read -r -p "Type the target device ($TARGET) to confirm and proceed: " confirm
  if [[ "$confirm" != "$TARGET" ]]; then
    echo "!! confirmation did not match — aborting" >&2
    exit 1
  fi
fi

echo "==> pre-flight: clearing existing mounts on $TARGET and /mnt"
if findmnt /mnt >/dev/null 2>&1; then
  echo "    /mnt is already mounted — unmounting"
  umount -R /mnt
fi
mapfile -t target_mounts < <(lsblk -nrpo MOUNTPOINT "$TARGET" 2>/dev/null | grep -v '^$' || true)
for mp in "${target_mounts[@]}"; do
  echo "    unmounting $mp (mounted from $TARGET)"
  umount -R "$mp"
done

echo "==> 1/5 partitioning $TARGET (GPT: 1 GiB ESP + rest root)"
parted -s "$TARGET" -- mklabel gpt
parted -s "$TARGET" -- mkpart ESP fat32 1MiB 1025MiB
parted -s "$TARGET" -- set 1 esp on
parted -s "$TARGET" -- mkpart primary 1025MiB 100%
partprobe "$TARGET" || true
udevadm settle

echo "==> 2/5 formatting"
mkfs.fat -F32 -n NIXOS_BOOT "$PART1"
udevadm settle
mkfs.ext4 -F -L NIXOS_ROOT "$PART2"
udevadm settle

echo "==> 3/5 mounting"
mount "$PART2" /mnt
mkdir -p /mnt/boot
mount "$PART1" /mnt/boot

# NixOS mounts by label at boot, so verify the labels are unambiguous on
# this machine — another attached disk (e.g. a root-on-USB stick built for
# the same host, per SYSMI-58/59) could carry the same NIXOS_ROOT/
# NIXOS_BOOT labels. The partitions above were mounted by device path, not
# by label, so this install is unaffected either way — but the ambiguity
# must be surfaced, since it will confuse the installed system at boot.
root_by_label="$(readlink -f /dev/disk/by-label/NIXOS_ROOT 2>/dev/null || true)"
if [[ -n "$root_by_label" && "$root_by_label" != "$(readlink -f "$PART2")" ]]; then
  echo "!! WARNING: /dev/disk/by-label/NIXOS_ROOT resolves to $root_by_label," >&2
  echo "   not $PART2 — another attached disk has a conflicting NIXOS_ROOT" >&2
  echo "   label. Remove or relabel $root_by_label before rebooting." >&2
fi
boot_by_label="$(readlink -f /dev/disk/by-label/NIXOS_BOOT 2>/dev/null || true)"
if [[ -n "$boot_by_label" && "$boot_by_label" != "$(readlink -f "$PART1")" ]]; then
  echo "!! WARNING: /dev/disk/by-label/NIXOS_BOOT resolves to $boot_by_label," >&2
  echo "   not $PART1 — another attached disk has a conflicting NIXOS_BOOT" >&2
  echo "   label. Remove or relabel $boot_by_label before rebooting." >&2
fi

echo "==> 4/5 nixos-install --flake ${FLAKE}#dogmatix"
nixos-install --flake "${FLAKE}#dogmatix" --no-root-passwd

echo "==> 5/5 done"
echo "DONE — do not forget the installer USB; system is ready to boot from eMMC"
echo "This script deliberately does NOT reboot. Verify the install, then"
echo "reboot and remove the USB yourself."
