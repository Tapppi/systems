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
- `herdr.nix`: the agent multiplexer and its generated config.
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

## Desktop preferences

`darwinModules.desktopDefaults` is an opt-in native nix-darwin preset. Import it beside `workstation`,
as the public Darwin example does. It shows hidden files, extensions, paths, status and mounted volumes
in Finder; uses list view and current-folder search; enables immediate spring loading; and configures
an automatically hiding Dock with reduced animations, stable Spaces order and visible process indicators.
The exact settings are in [desktop-defaults.nix](desktop-defaults.nix).

Every value uses `mkDefault`: set individual `system.defaults.finder`, `NSGlobalDomain` or `dock` options
in the consumer to override it. Set a value to `null` to leave that preference unmanaged. A consumer
chooses its own Finder start folder with `system.defaults.finder.NewWindowTarget` and, for `Other`,
`NewWindowTargetPath`. The standalone preset requires the native `system.primaryUser`; `workstation`
already supplies it. The preset installs no packages and declares no account or Home Manager settings.

nix-darwin writes these preferences as the primary user during activation and restarts that user's Dock.
Finder may need a relaunch or logout for all settings to appear. The
[desktop check](tests/desktop-defaults.nix) inspects generated commands, plist types and values without
executing preference writes; it also checks an absent import and native consumer overrides.

Preference writes persist outside the Nix generation. Removing an import or setting a key to `null`
does not restore or delete its old value. Before an owner activates this preset on an existing machine,
capture the prior values and absence of the touched keys and retire each competing writer. Recovery
must restore those captured values (or delete keys previously absent); changing generations alone is
insufficient. Building the example does not validate live preferences or graphical behavior.

## Design references

The [Darwin starter references](../../references/darwin-starter/README.md) contain uninstantiated workstation
composition examples for design comparison. They are separate from the exported modules and have no buildable
flake configuration.
