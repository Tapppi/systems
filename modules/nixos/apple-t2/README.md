# Apple T2 composition

The `apple-t2` export combines hardware support with a closed-lid server policy.
`apple-t2-hardware` and `headless-t2` expose those parts separately. The
[example](../../../examples/nixos-on-t2.nix) supplies a synthetic host and
[disk layout](../../../examples/t2-disko.nix); `flake.nix` supplies its module imports.

## Kernel and installation

The nixos-hardware module owns `boot.kernelPackages` and loads `apple-bce` for
internal input devices. Do not override it with a stock or LTS kernel in the
composition. The [local patch adaptations](kernel-patches.nix) preserve the stable
kernel's USB reset-resume and nested-report protections while applying the T2
input patches. The replacement trackpad patch stays in its upstream position;
the USB nested-report repair follows the complete upstream patch list. Host and
[T2 installer](../installer/t2.nix) must use the same adaptations.

The installer preserves a working internal keyboard as a recovery path if SSH
fails. A generic nixos-anywhere kexec image can lose that support by replacing
the running kernel. Boot the T2 image and use nixos-anywhere's no-kexec path;
the generic installer remains useful for machines that do not need this kernel.
The T2 image disables the generic image's ZFS support so ZFS's out-of-tree kernel
compatibility does not become an installer dependency. It is not a ZFS rescue image.

Cache substitution depends on exact inputs, including the local patches. Merely
configuring `cache.soopy.moe` does not ensure a kernel is cached. Build missing
outputs on a Linux builder before installation rather than relying on the live
ISO's limited writable store.

## Disk, EFI and memory

The example is a **whole-disk Linux installation**, including a recreated ESP.
It removes macOS and its recovery partitions; it is not a dual-boot layout.
Confirm the target's Linux by-id path before using it. The
[T2 preinstall guide](https://wiki.t2linux.org/guides/preinstall/) describes firmware
boot permissions and the different partition-preserving installation path.

Keep the ESP first through explicit disko priorities, give it GPT type `EF00`,
and mount it at `/boot` to agree with [base.nix](base.nix). A normal disko
filesystem defaults to Linux type `8300`, which does not identify an ESP.
The 2 GiB ESP and ten-generation bootloader limit must be sized together because
each generation copies a kernel and initrd there. Actual sizes vary; ten
generations are not a guarantee that every future kernel/initrd set will fit.

`canTouchEfiVariables = false` avoids relying on T2 EFI-variable writes. The
pinned NixOS systemd-boot installer passes `--variables=no` on installation
and `touchVariables = false` on update. It still installs the removable fallback
`EFI/BOOT/BOOTX64.EFI`; firmware discovery must work without a saved NVRAM entry.
Recreating the ESP therefore needs a physical Startup Manager boot check:
a successful OVMF test does not prove Apple firmware will discover it.

zram's default priority 5 must remain above disk swap. High swappiness favors
compressed RAM reclaim; disk swap absorbs overflow from larger builds. Raising
disk swap priority or removing zram changes that tradeoff. Btrfs compression
reduces store space/write volume; separate subvolumes let container data have
its own snapshot policy without making snapshots a backup requirement.

The pinned disko `installTest` substitutes `/dev/vd*` for real device paths and
allocates 4 GiB test disks. The example's 2 GiB ESP plus 8 GiB swap cannot fit.
Use a dedicated test composition with smaller partitions (512 MiB each leaves
room for root), or a test harness with larger disks. That tests layout mechanics,
not production sizing, disk identity, or physical T2 boot behavior.

## Firmware and graphics

[t2.nix](t2.nix) builds Broadcom Wi-Fi/Bluetooth firmware from an Apple recovery
image inside a Linux VM. This does not depend on keeping macOS on the target.
Ventura is the working recovery input for the pinned extractor: Sonoma's metadata
triggers its `assert not props` failure and prevents the system closure building.
Recheck extraction and device-specific firmware coverage when changing that pin.
The installer imports the kernel capability, not this firmware-enabled host policy;
plan its network access around supported wired hardware.

On models with both Intel and AMD graphics, `enableIGPU` configures apple-gmux to
expose Intel graphics. That and the headless module's media drivers work together
for QSV/VAAPI; installing userspace drivers alone is insufficient.

## Headless access and restart

[networking.nix](networking.nix) matches USB Ethernet driver names rather than
MAC addresses, so a replacement supported dongle works without editing identity.
Blanket DHCP would also touch the internal apple-bce bridge; its transmit/watchdog
path has caused lockups on T2 systems. Keep unmatched interfaces unconfigured.
Tailscale supplies another access route over a working network, not a substitute
for the physical adapter. Firmware availability alone does not configure Wi-Fi.

[headless.nix](headless.nix) disables powertop auto-tuning because USB autosuspend
can remove that network path. All logind lid variants ignore closure, while
disabled sleep targets also block explicit suspend requests. `video=eDP-1:d`
disables the internal display connector; Touch Bar behavior is separate.

Some T2 firmware powers off instead of restarting on reset. The interactive
`reboot` alias refuses that operation, but cannot guard other reset callers.
Panic-on-lockup/oops settings help only for detectable failures and can still
lead to poweroff; they are not a hardware watchdog.

NixOS `prepare-kexec` loads `/nix/var/nix/profiles/system`, unless a kernel is
already loaded for kexec. Before an authorized restart, check that profile and
any preloaded image: a boot-menu selection alone does not select the kexec target.
Physical recovery remains necessary when the kernel or sole network path fails.
