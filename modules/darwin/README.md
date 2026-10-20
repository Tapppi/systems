# Darwin modules

`darwinModules.workstation` is the reusable Darwin workstation module. It provides the Linux builder, Neovim and
Neovide, coding-agent tools, session archival, Hammerspoon and the Determinate Nix accommodations. Use the flake's
`lib.mkDarwin` helper to supply the pinned Home Manager and nix-rosetta-builder dependency modules.

The consuming host supplies `local.workstation.user`, `local.workstation.home`, its native `networking` names,
`home-manager.users.<user>.home.stateVersion`, and `local.hammerspoon.luaDir`. User names accept lowercase account
characters; home and Lua directory paths must be absolute and contain only letters, digits, `_`, `.`, `/` and `-`.
This keeps the existing activation script interpolation safe. The public browser target is Safari; hosts configure
personal targets through `local.browsers.targets`. Set `local.sessionSync.archiveHost` to the archive's SSH host or
alias; its default is the inert example `archive.example.invalid`.

## Workstation modules

- `workstation.nix`: shared system packages, Home Manager wiring, builder and Determinate Nix settings.
- `session-sync.nix`: launchd agent mirroring `~/.claude/` to a write-only archive.
- `herdr.nix`: the agent multiplexer, shared settings/wrapper and Darwin notification/link policy.
  [Portable Herdr](../../docs/portable-user.md) exposes the common behavior through Home Manager.
- `codex.nix`: Codex from nixpkgs-fresh, with defaults in `/etc/codex/config.toml`.
- `agent-reaper/`: launchd agent reaping idle companion brokers and orphaned MCP servers.
- `opencode.nix`, `devenv.nix`, `pi-coding-agent.nix`: packages from nixpkgs-fresh.
- [Hammerspoon](hammerspoon/README.md): the application, configuration, link routing and hotkeys.

The workstation owns `useGlobalPkgs`, `useUserPackages`, `backupFileExtension` and the configured user's home.
The [Home Manager file settings](../home-manager/workstation-files.nix) are also exported as
`homeManagerModules.workstationFiles`. They suppress automatically generated font, cache, state, application and
manual files. The consuming host owns `home.stateVersion`. Child modules contribute only their own files and services.

`useUserPackages` keeps Home Manager's profile under `/etc/profiles/per-user` rather than managing
`~/.nix-profile`. Child modules must not redefine the configured user, state version, shared Home Manager
settings or backup policy. The workstation sets `nix.enable = false` for Determinate Nix and writes daemon
settings through `nix.custom.conf`; changing Nix distribution or ownership requires its own reviewed design.

## Design references

The [Darwin starter references](../../references/darwin-starter/README.md) contain uninstantiated workstation
composition examples for design comparison. They are separate from the exported modules and have no buildable
flake configuration.
