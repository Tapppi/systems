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
#   --flake <path>    path to the systems flake (default: /mnt/tmp/systems)
#   --yes             skip the interactive confirmation prompt
#   --force-size      skip the 50-70 GB target-size sanity check

set -euo pipefail

TARGET=/dev/mmcblk0
FLAKE=/mnt/tmp/systems
ASSUME_YES=0
FORCE_SIZE=0

usage() {
  cat <<'EOF'
Usage: install-dogmatix-emmc.sh [--target <disk>] [--flake <path>] [--yes] [--force-size]

  --target <disk>   block device to install to (default: /dev/mmcblk0)
  --flake <path>    path to the systems flake (default: /mnt/tmp/systems)
  --yes             skip the interactive confirmation prompt
  --force-size      skip the 50-70 GB target-size sanity check
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --flake)
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

# Refuse to touch whatever disk backs the running live system, whether that
# is the installer ISO's own mount or the read-only nix store squashfs.
for probe in /iso /nix/.ro-store; do
  live_disk="$(findmnt -no SOURCE --target "$probe" 2>/dev/null || true)"
  [[ -z "$live_disk" ]] && continue
  live_disk="$(lsblk -no PKNAME "$live_disk" 2>/dev/null || true)"
  [[ -z "$live_disk" ]] && continue
  if [[ "/dev/$live_disk" == "$TARGET" ]]; then
    echo "!! target $TARGET backs the running live system (via $probe) — refusing" >&2
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
  echo "     rsync -a asterix:project/github/tapppi/systems $FLAKE" >&2
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

echo "==> 1/5 partitioning $TARGET (GPT: 1 GiB ESP + rest root)"
parted "$TARGET" -- mklabel gpt
parted "$TARGET" -- mkpart ESP fat32 1MiB 1025MiB
parted "$TARGET" -- set 1 esp on
parted "$TARGET" -- mkpart primary 1025MiB 100%

echo "==> 2/5 formatting"
mkfs.fat -F32 -n NIXOS_BOOT "$PART1"
mkfs.ext4 -F -L NIXOS_ROOT "$PART2"

echo "==> 3/5 mounting"
mount /dev/disk/by-label/NIXOS_ROOT /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/NIXOS_BOOT /mnt/boot

echo "==> 4/5 nixos-install --flake ${FLAKE}#dogmatix"
nixos-install --flake "${FLAKE}#dogmatix" --no-root-passwd

echo "==> 5/5 done"
echo "DONE — do not forget the installer USB; system is ready to boot from eMMC"
echo "This script deliberately does NOT reboot. Verify the install, then"
echo "reboot and remove the USB yourself."
