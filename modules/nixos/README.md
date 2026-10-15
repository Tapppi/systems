# NixOS modules

The [root flake](../../flake.nix) exports the supported compositions through `nixosModules`.
Consumers supply actual machine identities, storage bindings, access grants and service placement.
Use `lib.mkNixos` for the library's pinned inputs, or supply the dependencies when importing modules directly.
Build and evaluation commands are in the [repository README](../../README.md#examples-and-checks).

## Exported capabilities

| Path | Exports and purpose |
| --- | --- |
| [intel-n150/](intel-n150/default.nix) | `intel-n150`: Intel N150 server profile, ZFS, Incus, networking and host observability. |
| [apple-t2/](apple-t2/README.md) | `apple-t2`: combined hardware and headless server policy; `apple-t2-hardware` and `headless-t2` expose the parts separately. |
| [lxc-guest.nix](lxc-guest.nix) | `lxc-guest`: Incus system-container base with SSH, Tailscale and node exporter. |
| [installer/default.nix](installer/default.nix) | `installer`: generic installer ISO module. |
| [installer/t2.nix](installer/t2.nix) | `installer-t2`: installer with the T2 kernel adaptations. |
| [services/](services/) | `speech`, `archive`, `bench-absurd`, `bench-load`, `bench-obs` and `bench-temporal`: configurable service modules. |

The [N150 example](../../examples/nixos-intel-n150.nix) and
[T2 example](../../examples/nixos-on-t2.nix) supply synthetic compositions. The T2
[disk example](../../examples/t2-disko.nix) and [composition guide](apple-t2/README.md) retain the
kernel, disk and network constraints needed when adapting a host. The service modules import
[lxc-guest.nix](lxc-guest.nix) for their common container policy.

## Desktop reference files

The [NixOS desktop references](../../references/nixos-desktop/README.md) contain Home Manager,
package, generated-file and disk-layout examples outside the exported server profiles.
They require adaptation and verification before use; server build evidence does not validate a desktop.
There is no root `modules/nixos/default.nix`; follow the flake's explicit exports to find a live composition.
