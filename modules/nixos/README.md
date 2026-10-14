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

The root-level `home-manager.nix`, `packages.nix`, `files.nix`, `disk-config.nix` and `config/` contain
uninstantiated desktop references. They are not imported by the exported server profiles or examples.
There is no root `modules/nixos/default.nix`; follow the flake's explicit exports to find a live composition.

[home-manager.nix](home-manager.nix) composes the shared desktop programs, packages and generated files.
[packages.nix](packages.nix) returns a list, [files.nix](files.nix) returns Home Manager file definitions,
and [disk-config.nix](disk-config.nix) is a disko layout with a placeholder device.
These files need their own adaptation and verification before use; current server build evidence does not
validate a desktop configuration. See [shared configuration](../shared/README.md) for their common inputs.
