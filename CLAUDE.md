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
  - `asterix` (the Apple Silicon Mac) has a working, activated configuration in
    `hosts/darwin-minimal/`. It is deliberately narrow while the migration
    proceeds: the nix-rosetta-builder Linux builder, neovim (built from
    `flakes/nvim`), neovide wrapped to launch that exact neovim, and the
    Determinate Nix accommodations. Everything else on that machine is still
    owned by `macos-setup` — check there before assuming something is managed here.
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

```
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
- **Shell scripts**: Follow bash best practices, 2-space indentation
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
# Check the flake configuration
nix flake check

# macOS (darwin) — asterix
nix run .#build         # build only, activates nothing
nix run .#build-switch  # build and activate (prompts for sudo)
nix run .#rollback      # list generations, pick one, activate it

# NixOS
nix run .#build-switch
nix run .#apply
```

**`nix run .#build-switch` is the single user-facing entrypoint for activating
macOS configuration.** Everything beneath it — `nix build` of
`darwinConfigurations.<host>.system`, then `darwin-rebuild switch --flake
.#<host>` as root — is implementation detail. When the user asks how to
activate, or how to apply a change just made, give them that one command.

`darwinConfigurations` contains hostname-keyed entries only. The upstream
starter's per-architecture placeholder is no longer instantiated — see
"Project Status" for where that tree now lives.

**Never activate without the user explicitly asking.** `nix run .#build-switch`,
`darwin-rebuild switch`, and `nixos-rebuild` change live system state and are the
user's call, not an agent's. Building is not activating: `nix run .#build`,
`nix build`, `nix eval` and `nix flake check` are all safe and are the way to
verify a change before proposing it.

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

