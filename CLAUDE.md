# AI Agent Configuration Guide

This document provides AI agents with context and guidelines for working with the tapppi/nix-config repository.

## External File Loading

CRITICAL: When you encounter a file reference (e.g., `@flakes/nvim/AGENTS.md`), use your Read tool to load it on a
need-to-know basis. They're relevant to the SPECIFIC task at hand.

Instructions:

- Do NOT preemptively load all references - use lazy loading based on actual need
- When loading another `AGENTS.md` file, treat content as mandatory instructions that override defaults set in this file
- Follow references recursively when needed

## Project Overview

This is a declarative system configuration repository built with Nix Flakes. The repository provides reproducible
development environments and system configurations across systems (macOS with nix-darwin, nixOS, eventually homelab).

The project is primarily authored by tapppi to manage his system configurations, it is not meant to provide anything
generic.

The repository structure is based on [dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config)

## Project Status

- **macOS Configuration**: In progress of being migrated from
  [tapppi/macos-setup](https://github.com/tapppi/macos-setup)
  - `asterix` (the Apple Silicon Mac) has a working configuration in
    `hosts/darwin-minimal/`. It is deliberately narrow while the migration
    proceeds: the nix-rosetta-builder Linux builder, neovim (built from
    `flakes/nvim`), neovide wrapped to launch that exact neovim, `herdr` and
    its config, the `session-sync` launchd agent, Hammerspoon (application and
    configuration, see `modules/darwin/hammerspoon/README.md`), and the
    Determinate Nix accommodations. Everything but Hammerspoon has been
    activated on the machine; Hammerspoon arrives with SYSMI-63 and its first
    activation is what proves the packaged bundle launches. Everything else on
    that machine is still owned by `macos-setup` — check there before assuming
    something is managed here.
  - **home-manager is wired into this host** as of SYSMI-63, in
    `hosts/darwin-minimal/default.nix`. It is scoped hard: `useUserPackages`
    keeps `home.profileDirectory` at `/etc/profiles/per-user` rather than
    materialising `~/.nix-profile`, and the darwin/xdg files home-manager would
    otherwise place are suppressed. The host owns `stateVersion`,
    `users.users.tapani` and the `useGlobalPkgs`/`useUserPackages`/
    `backupFileExtension` settings; modules under `modules/darwin/` contribute
    `home.file` entries and nothing else. A module that sets any of the
    host-wide options will collide with the next one that does.

    `home.stateVersion` tracks the **newest supported** release and converges
    with the NixOS hosts — `dogmatix`, `automatix` and the LXC guest base are
    all on 26.11, so darwin is too. The starter modules are still on 25.05;
    importing one without reconciling that will fail evaluation.
  - `hosts/darwin/` and `modules/darwin/` are the full-featured upstream
    starter, kept as the worked reference for the macos-setup migration. They
    have never been activated and are deliberately not instantiated in
    `flake.nix`, so no buildable configuration exists for them. Per ADR-002 the
    per-architecture starter placeholders are to be dropped entirely once
    `systems` becomes a module library.
- **NixOS Configuration**: Placeholder/untested
  - Not being actively worked on, but shared functionality kept in sync as "best effort" to reduce eventual work
- **Neovim Configuration**: Fully functional, more information in @flakes/nvim/AGENTS.md

## Architecture

### Directory Structure

```text
.
├── apps/           # Nix commands for bootstrapping and building per architecture
│   ├── aarch64-darwin/
│   ├── aarch64-linux/
│   ├── x86_64-darwin/
│   └── x86_64-linux/
├── flakes/         # Standalone flake configurations
│   └── nvim/       # Neovim configuration (with its own detailed AGENTS.md file, see "Neovim Configuration" section)
├── hosts/          # Host-specific configurations
│   ├── darwin/
│   └── nixos/
├── modules/        # System configuration modules
│   ├── darwin/     # macOS-specific modules
│   ├── nixos/      # NixOS-specific modules
│   └── shared/     # Cross-platform modules
└── overlays/       # Nixpkgs overlays and patches
```

### Flake Inputs

See `flake.nix` for complete list. The most important ones are:

- **nixpkgs**: nixos-unstable channel
- **home-manager**: User environment management
- **nix-darwin**: macOS system configuration
- **nix-homebrew**: Homebrew integration for macOS

### Supported Systems

- `aarch64-darwin` (Apple Silicon macOS)
- `x86_64-darwin` (Intel macOS)
- `aarch64-linux` (ARM Linux)
- `x86_64-linux` (x86_64 Linux)

### Overlays

The overlays in `overlays/` apply patches on top of every build, allowing for workarounds like using a different
version or a fork of a package. See the `@overlays/README.md` for more information when there is need for a workaround.
See `overlays/10-feather-font.nix` for an example of an overlay.

## Code Style and Formatting

### EditorConfig Settings

All files in this project follow the standard style in `.editorconfig`:

```ini
end_of_line = lf
insert_final_newline = true
charset = utf-8
indent_size = 2
indent_style = space
trim_trailing_whitespace = true
max_line_length = 120
```

### Specific File Type Conventions

- **Nix**: Formatted with nixfmt, follows editorconfig rules
- **Lua**: Formatted with StyLua which is configured to match editorconfig
- **Shell scripts**: Follow bash best practices, 2-space indentation. Bootstrap code must be
  portable; everything else can assume GNU. Scripts that bring a machine up (`scripts/`, the
  `apps/`, anything run before a config is activated) may execute against a stock BSD macOS
  userland, so they must work under both — chiefly `sed -i.bak … && rm -f …bak` rather than
  `sed -i ''` (BSD-only) or bare `sed -i` (GNU-only); same care for `readlink -f`, `date`, `stat`,
  `sort`, `grep -P` and `find -printf`. Anything running on an already-configured macOS host or on
  NixOS has GNU first on PATH and can rely on it
- **Markdown**: Formatted with markdownlint-cli2, follows editorconfig rules

### Nix Style Guidelines

- Use `with pkgs;` sparingly; prefer explicit `pkgs.package` references for clarity
- Use descriptive variable names
- Add comments for non-obvious configuration decisions
- Group related packages logically
- Prefer `lib.mkOption` for reusable options

## Common Tasks

### Making file changes

When making file changes, do NOT create backup files, we use git for that purpose.

### Building Configurations

`darwinConfigurations` are keyed by **hostname** (`asterix`), not by
architecture. The apps in `apps/<system>/` resolve the hostname themselves via
`scutil --get LocalHostName`, overridable with `DARWIN_HOST`.

```bash
# Check the flake configuration. Since SYSMI-63 this is not a no-op: it parses
# the Hammerspoon Lua with the same Lua 5.4 the app embeds and holds it to
# stylua.toml. That Lua is symlinked out of the store, so no build can catch a
# syntax error in it — this check is the only thing that does.
nix flake check

# macOS (darwin) — asterix
nix run .#build         # build only, activates nothing
nix run .#build-switch  # build and activate (prompts for sudo)
nix run .#rollback      # list generations, pick one, activate it

# NixOS hosts — push-based, run from asterix, keyed by hostname
nix run nixpkgs#nixos-rebuild -- switch --flake .#<host> --target-host root@<host>
```

**The `nix run nixpkgs#` prefix is not optional on asterix.** `nixos-rebuild`
ships with NixOS, not with nix-on-macOS, so the bare command is `command not
found` on the very machine these deploys are run from.

No `--build-host` is needed: asterix is `aarch64-darwin` and the NixOS hosts are
`x86_64-linux`, so the daemon farms the build out to the Linux builder below.
Evaluation stays local, which darwin handles fine. If that builder is ever
unavailable, `--build-host root@<host>` builds on the target instead — correct
but slower, and a poor idea on a small guest.

**`nix run .#build-switch` is the single user-facing entrypoint for activating
macOS configuration.** Everything beneath it — `nix build` of
`darwinConfigurations.<host>.system`, then `darwin-rebuild switch --flake
.#<host>` as root — is implementation detail. When the user asks how to
activate, or how to apply a change just made, give them that one command, and
name only that command: telling them to run `darwin-rebuild` directly bypasses
the wrapper's host resolution and its sudo handling.

**There is no `nix run .#` path for NixOS hosts, and `apps/<linux>/build-switch`
must not be used.** It is the upstream starter's: it resolves the target from
`uname -m` and switches to `nixosConfigurations.<arch>`, the untested
placeholder, rather than to a hostname-keyed host like `dogmatix`. That
placeholder's `keys` list is empty, so activating it would leave a host with no
authorized SSH keys. It is currently non-executable, which is the only reason
that has not happened. Real NixOS deploys are push-based (HLB-9) via remote
`nixos-rebuild` as above; new hosts are onboarded with `nixos-anywhere` per
ADR-001.

`darwinConfigurations` contains hostname-keyed entries only. The upstream
starter's per-architecture placeholder is no longer instantiated — see
"Project Status" for where that tree now lives.

**Never activate without the user explicitly asking.** `nix run .#build-switch`,
`darwin-rebuild switch`, and `nixos-rebuild` change live system state and are the
user's call, not an agent's. Building is not activating: `nix run .#build`,
`nix build`, `nix eval` and `nix flake check` are all safe and are the way to
verify a change before proposing it.

### The Linux builder (asterix)

Builds targeting `x86_64-linux` or `aarch64-linux` — every NixOS deploy, the
installer ISOs — are farmed out to the nix-rosetta-builder VM configured in
`hosts/darwin-minimal/default.nix`. Only the build crosses; evaluation is local.

**Nothing needs to be done to start it.** It boots when a Linux build reaches
for it and stops when idle, so a Linux build just works — a little slower
against a cold VM. `macos-setup` has a `builder {status|up|down}` helper for
pre-warming or reclaiming the RAM early; the normal path never calls it.

A build that fails with `Cannot build … platform mismatch` caught the VM mid
re-create, which a nixpkgs bump or a change to the builder's own settings
triggers. Re-run it.

### System Configuration vs. Imperative Package Install

`build-switch` activates a whole new system generation built from this repo.
That is the reproducible, in-git path and is what should be used for anything
meant to persist.

`nix profile install` is the imperative alternative: it adds a single package
to `~/.nix-profile` with no record in this flake, so it silently would not exist
on a rebuilt machine. Reach for it — or preferably `nix shell nixpkgs#<pkg>`,
which is ephemeral and leaves nothing behind — only for genuine throwaways.
Anything else belongs in a module here.

`~/.nix-profile` does not currently exist on asterix: nothing is installed
imperatively, and it should stay that way.

### Development Shell

```bash
nix develop
```

## Module System

### Darwin Modules (`modules/darwin/`)

Active on `asterix` — these are imported by `hosts/darwin-minimal/`:

- **session-sync.nix**: launchd agent mirroring `~/.claude/` to the homelab archive
- **herdr.nix**: the agent multiplexer, plus its generated config
- **hammerspoon/**: the Hammerspoon application and its configuration. Read its
  `README.md` before touching it — the config path, the module name the stub
  requires and the restart-vs-reload branch each prevent a specific failure

Unused upstream starter — imported only by the never-activated `hosts/darwin/`:

- **casks.nix**: Homebrew cask applications
- **dock/**: macOS Dock configuration
- **files.nix**: System file management
- **home-manager.nix**: User-level darwin configuration
- **packages.nix**: System-level packages

### NixOS Modules (`modules/nixos/`)

- **disk-config.nix**: Disko (declarative disk-partitioning) disk layout
- **files.nix**: System files
- **home-manager.nix**: User-level nixos configuration
- **packages.nix**: System packages
- **config/**: Configuration files (polybar, rofi, etc.)

### Shared Modules (`modules/shared/`)

- **default.nix**: Common configuration
- **files.nix**: Cross-platform file management
- **home-manager.nix**: Shared home-manager config
- **packages.nix**: Common packages, such as cli utils, terminal/dev tools, fonts
- **programs.nix**: Shared program configurations
- **nvim/**: Neovim module integration

## Guidelines for AI Agents

### Agent worktrees

**Agent sessions that change this repo work in a git worktree, not in the main
checkout.**

The main checkout is the user's: it is where `nix run .#build-switch` runs,
where diffs get reviewed, and where activation happens. `build-switch` builds
*whatever is in the working tree*, committed or not, so an agent's in-flight
edits there can land in a live system generation nobody chose to activate —
and with more than one session in the repo at once, their commits land mixed
into each other's in-progress work.

```bash
# Create and enter. The EnterWorktree tool does the same thing and puts it in
# the same place; `.claude/worktrees/` is gitignored.
git worktree add .claude/worktrees/<topic> -b agent/<topic>

# Work, build and test there. Commit scoped by path, and verify each commit
# with `git show --stat HEAD`.
```

**Default: stop there and leave the branch for the user to review and merge**
— this repo carries config for real machines, and review-before-merge plays
the role a PR would. The one authorized exception is work explicitly set up
as unattended background work that includes a deploy: the deploy tooling
reads from main, not a branch, so in that case only, merge the worktree
branch into main, deploy (`nix run .#build-switch` on darwin,
`nixos-rebuild switch --flake .#<host> --target-host root@<host>` for a NixOS
host — see "Building Configurations"), then resume in the worktree — the same
one or a fresh one — to keep going. This is a statement of current policy,
not a claim it is pleasant for fast iteration; the ergonomics of that
exception are an open question tracked in tieto's ikeh follow-ups, not
settled here.

Either way, land with a rebase rather than a `--no-ff` merge commit — nothing
here races an external auto-committer for main the way tieto's obsidian-git
does, so linear history costs nothing:

```bash
# Reviewed case (the default): the worktree's own commits are already the
# reviewable units, so keep them — just linearize.
git -C .claude/worktrees/<topic> rebase main
git merge --ff-only agent/<topic>

# Background-work exception: nobody reviewed the individual commits, so
# squash to one first. That keeps history linear while still leaving a
# single commit as the revert point — the property a --no-ff merge commit
# would otherwise buy.
git -C .claude/worktrees/<topic> reset --soft main
git -C .claude/worktrees/<topic> commit
git merge --ff-only agent/<topic>

git worktree remove .claude/worktrees/<topic> && git branch -d agent/<topic>
```

A subagent that needs its own workspace branches a nested worktree off the
worktree already in use, not off main — reserve this for work big enough that
the existing parallel-work conventions, without a nested worktree, stop being
enough.

A worktree is a full checkout with its own index, so `nix build`,
`nix flake check`, `nix eval` and the VM tests all work inside one exactly as
they do in the main checkout — flake evaluation follows the working directory,
not the git root. Two things do not move with it:

- **Activation is the main checkout's.** `nix run .#build-switch` from a
  worktree would activate an unmerged branch. Build and check in the worktree;
  merge first, then let the user activate.
- **Remote deploys likewise** — `nixos-rebuild --target-host` pushes a closure
  built from the working tree to a real machine, so it is subject to the same
  rule, on top of the "never activate without being asked" one below.

Worktrees live under `.claude/` by convention because that is where the harness
creates them. A sibling directory outside the repo works equally well.

Small single-file edits made while an operator is watching do not need a
worktree. Anything long-running, anything backgrounded, and anything that will
accumulate uncommitted state does.

### When Making Changes

1. **Understand the scope**: Determine if a change affects darwin, nixos, or shared modules
2. **Check existing patterns**: Review similar configurations in the codebase
3. **Test incrementally**: Use `nix run .#build` before `build-switch`.
   - NOTE: This is currently not enforced as no working macOS setup exists yet
   - Once initial configuration is stable, always test builds before switching
4. **Respect EditorConfig**: Maintain consistent formatting (2 spaces, LF, UTF-8)
5. **Add comments**: Only explain non-obvious configuration decisions, let the code explain the specifics

### When Adding Packages

The repository uses a two-tier approach for package management:

**packages.nix files** (`modules/{darwin,nixos,shared}/packages.nix`):

- Contain lists of packages (CLI tools, terminal apps, development tools, fonts, etc.)
- Return a simple array of packages
- **Shared packages.nix** is dual-loaded on Darwin:
  - System-level via `hosts/darwin/default.nix` → `environment.systemPackages`
  - User-level via home-manager → `home.packages`
- **Platform-specific packages.nix** (darwin/nixos) are loaded **only** into home-manager
- Platform-specific files import and extend the shared list

**home-manager.nix files** (`modules/{darwin,nixos,shared}/home-manager.nix`):

- Configure program settings and services (zsh, git, polybar, dunst, etc.)
- Manage dotfiles and user files
- Import packages.nix via `home.packages = pkgs.callPackage ./packages.nix {}`
- Handle user-specific configuration (username, directories, stateVersion)

**Guidelines for adding new items:**

- **CLI tools, fonts, and simple packages**: Add to appropriate `packages.nix`
  - Cross-platform tools → `modules/shared/packages.nix`
  - macOS-specific tools → `modules/darwin/packages.nix`
  - Linux-specific tools → `modules/nixos/packages.nix`

- **GUI applications on macOS**: Use Homebrew casks in `modules/darwin/casks.nix`

- **Programs requiring configuration**: Add to appropriate `home-manager.nix` or `programs.nix`
  - Configure via `programs.<name>` attributes
  - Set up services via `services.<name>` attributes

- **System-level NixOS packages** (rare): Add directly to `hosts/nixos/default.nix` → `environment.systemPackages`
  - Only for system services/daemons that must run outside user context
  - Most packages should go in home-manager instead

**Examples:**

- Adding `ripgrep` → `modules/shared/packages.nix` (simple CLI tool)
- Adding `dockutil` → `modules/darwin/packages.nix` (macOS-specific utility)
- Configuring `zsh` → `modules/shared/programs.nix` (needs configuration)
- Adding Slack → `modules/darwin/casks.nix` (macOS GUI app)

### When Troubleshooting

1. Check flake.lock for dependency versions
2. Review module README files for documentation
3. Verify system compatibility (darwin vs nixos)
4. Test with `nix flake check` before building
5. Use `nix run .#build` to test without switching

### Common Pitfalls

- Don't mix `with pkgs;` and explicit `pkgs.` references inconsistently
- Ensure new modules are imported in `default.nix`
- Remember home-manager and system configs are separate
- macOS-specific features require darwin modules, not nixos
- Test on target architecture (aarch64 vs x86_64)
- Ensure home-manager input version matches nixpkgs channel (both unstable)
  - Check `flake.lock` if home-manager evaluation fails
  - Errors for mismatched versions are expected when the version number of home-manager and nixpkgs on unstable diverge

## Neovim Configuration

See `@flakes/nvim/AGENTS.md` for detailed guidelines that take priority when working with Neovim configuration.
Key points:

- Standalone flake in `flakes/nvim/`
- Integrated via `modules/shared/nvim/`
