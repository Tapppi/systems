# Development and verification

## Find the implementation

The [root flake](../flake.nix) declares public module exports, constructor helpers and synthetic examples.
`modules/nixos/` contains hardware profiles, installer and service modules; `modules/darwin/` contains the
workstation and individual tools; `modules/home-manager/` contains the narrow file policy.
`modules/shared/` contains shared configuration and editor integration; consumers must import what they need.
The standalone [Neovim flake](../flakes/nvim/README.md) owns the editor.
[Darwin starter references](../references/darwin-starter/README.md) are design inputs outside the live modules.

Development shells and checks cover `aarch64-darwin`, `aarch64-linux` and `x86_64-linux`.
The Darwin example targets Apple Silicon; there is no `x86_64-darwin` output. See README for example names.

## Common tasks

Enter the repository's shell with `nix develop`. It supplies Bash and Git; it is not a full formatter bundle.
Use the established tooling and [conventions](conventions.md) for the files being edited.
Inspect the appropriate module and a similar composition before changing it.

Stage new files by explicit path before Git-flake evaluation; Nix excludes untracked files. Run `nix flake check`
and build every affected example, consumer host and image using the commands in [README](../README.md).
An evaluation checks module composition; a build additionally realizes its output. Neither proves boot,
activation, physical disk identity, hardware support or rollback. Report which checks actually ran.

The Hammerspoon check parses Lua with Lua 5.4, checks StyLua formatting and exercises generated stubs against
a simulated `hs` API. It is essential: the application loads Lua through an out-of-store link, so building
the system does not load or test that Lua. A real consumer's live checkout must not be edited for development.

For co-development, override the systems input from the consumer with `--override-input systems path:<worktree>`
and `--no-write-lock-file`. README has the full example. Publish the reviewed immutable public commit before
updating a release consumer pin. Activations follow [deployment ownership](deploys.md).

## Troubleshooting

Check `flake.lock`, the relevant module guide and target architecture first. Home Manager release warnings
can occur when unstable inputs advertise different releases; inspect their actual pins before changing them.
Do not treat a warning as proof that evaluation or a build succeeded.

Linux outputs require a compatible Linux builder; evaluation can remain on macOS. Firmware/image derivations
may require the `kvm` system feature; QEMU can fall back to slower emulation when acceleration is unavailable.
The workstation's nix-rosetta-builder starts on demand for `aarch64-linux` and `x86_64-linux` builds and stops
when idle. A transient platform mismatch during VM recreation can be retried. Diagnose persistent failures
without changing live builder settings just to satisfy a check. Private builder operations belong to the consumer.

Capture `nix build -L --keep-failed --no-link <output>` into a log and check the command's exit code before
reading the log. README contains a complete command. Piping a build into `tail` can hide failure behind the
last pipeline stage's successful exit. Remote `ssh-ng` logs may be incomplete when retrieved later with `nix log`.

An untrusted client's `--extra-substituters` can be ignored even when `nix config show` displays the setting.
Cache trust belongs in the daemon's managed configuration, with the corresponding trusted keys. For the
Determinate workstation that configuration is `nix.custom.conf`; standard NixOS uses `nix.settings`.
Do not change trust or a live daemon configuration as an incidental build workaround.
