# systems

Public NixOS, nix-darwin and Home Manager modules, with buildable hardware examples.
Actual machine identities, storage bindings, access grants and service placement belong in a composing flake.
This repository evaluates without private inputs.

## Interfaces

`nixosModules` exports the Intel N150 and headless Apple T2 server profiles, independent T2 hardware and
headless policy, an Incus guest base, generic/T2 installers, and speech, archive and benchmark services.
`darwinModules` exports the workstation and its individual tools. `homeManagerModules.workstationFiles`
provides the narrow Darwin file policy; the composition owns Home Manager state version and identity.

`lib.mkNixos { modules = [ ... ]; }` and `lib.mkDarwin { modules = [ ... ]; }` use this flake's pins and
supply its `inputs` to modules. Both accept `system` and `specialArgs`; a consumer can pass
`specialArgs.inputs = systems.inputs // inputs` to add its composing flake's inputs. The Darwin helper
loads Home Manager and nix-rosetta-builder. Modules can also be imported with the upstream constructors.

The main `nixpkgs` pin serves the operating systems, editor and Linux builder. `nixpkgs-fresh` is updated
separately for fast-moving tools with `nix flake update nixpkgs-fresh`. Keep each consumer's corresponding
input following the same track. The standalone editor is documented in [flakes/nvim](flakes/nvim/README.md).

## Examples and checks

```sh
nix flake check
nix build .#nixosConfigurations.nixos-intel-n150.config.system.build.toplevel
nix build .#nixosConfigurations.nixos-on-t2.config.system.build.toplevel
nix build .#darwinConfigurations.apple-silicon-host.system
```

These examples use synthetic identities and disk assumptions. They are build/evaluation examples, not
installation commands. The T2 disk path deliberately names no real device; replace it only in a reviewed
composition. The Darwin example's Hammerspoon Lua path must point at a real checkout before activation.
Linux outputs require a compatible Linux builder. Firmware/image derivations may require the builder
to advertise the `kvm` system feature; QEMU can fall back to slower software emulation when KVM
acceleration is unavailable.

For remote-build diagnosis, capture the full live log with `-L`. Add `--keep-failed` while
investigating to retain the failed build workspace on the builder:

```sh
nix build -L --keep-failed --no-link \
  .#nixosConfigurations.nixos-on-t2.config.system.build.toplevel \
  > nixos-on-t2-build.log 2>&1
```

Keep that captured log: a later `nix log` request over `ssh-ng` may not retrieve the complete
remote build log.

Each service module declares its configurable instance values under `services.systems-<name>`.
Authorized public keys and fleet topology are supplied by the consumer. Installer modules expose
`config.system.build.isoImage`; the consumer supplies authorized keys, hostname, hostId and image labels.
The N150 profile supports the standard NixOS image builders through `config.system.build.images`.

Public cache publication must select only outputs evaluated from this public flake. Do not publish
closures evaluated from a private fleet flake: private source and generated configuration can enter the
store even when plaintext credentials are kept at runtime paths.

## Local development

From the composing checkout, use the local library while keeping its release lock unchanged:

```sh
nix build .#nixosConfigurations.example.config.system.build.toplevel \
  --override-input systems path:../systems --no-write-lock-file
```

Use the actual worktree path when checkouts are nested. Publish a reviewed immutable library revision
before updating the consumer's lock. A local path override is a development input, not a release.
See [development and troubleshooting](docs/development.md), [repository conventions](docs/conventions.md),
[deployment ownership](docs/deploys.md), [Darwin modules](modules/darwin/README.md) and
[overlay constraints](overlays/README.md).
