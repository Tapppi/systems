# Darwin modules

Two sets live here, and the distinction matters more than the layout.

## Active on `asterix`

Imported by `hosts/darwin-minimal/`. Changing these changes a real machine.

```text
.
├── session-sync.nix   # launchd agent mirroring ~/.claude/ to the homelab archive
├── herdr.nix          # the agent multiplexer, and its generated config
└── hammerspoon/       # the Hammerspoon app and its config — read its README first
```

They contribute host-level configuration — `environment.systemPackages`, activation scripts, launchd agents — and, in
`hammerspoon/`'s case, `home.file` entries. None of them sets host-wide home-manager settings: `stateVersion`,
`users.users` and the `useGlobalPkgs`/`useUserPackages`/`backupFileExtension` options belong to
`hosts/darwin-minimal/default.nix`, because a second module setting any of them would collide on a non-mergeable
option.

## Unused upstream starter

Imported only by `hosts/darwin/`, which is never instantiated in `flake.nix` and has no buildable configuration. Kept
as the worked reference for the `macos-setup` migration; per ADR-002 it goes away once `systems` becomes a module
library.

```text
.
├── casks.nix          # List of homebrew casks
├── dock/              # macOS dock configuration
├── files.nix          # Non-Nix, static configuration files
├── home-manager.nix   # Defines user programs, the homebrew block, and the dock entries
└── packages.nix       # List of packages to install for macOS
```

Note these still pin `home.stateVersion = "25.05"`; importing one onto `asterix` without reconciling that against the
host's value will fail evaluation.
