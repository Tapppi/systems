# tapppi/nix-config

My system configuration for macOS and nixOS built with Nix.
The goal is to have a single reproducible configuration source for my working
environments.

Nix is a powerful package manager for Linux and Unix systems that ensures
reproducible, declarative, and reliable software management.

## Status

Currently configuring the macOS configuration based on
[my old macos-setup repo](https://github.com/tapppi/macos-setup).
The nixOS config is wholly untested and simply there as a placeholder.

## Usage

`darwinConfigurations` are keyed by **hostname**, and the apps in `apps/`
resolve the right one automatically:

```sh
nix run .#build         # build only, activates nothing
nix run .#build-switch  # build and activate (prompts for sudo)
nix run .#rollback      # list generations, pick one, activate it
```

`build-switch` is *the* entrypoint. What it does underneath — `nix build`
followed by `darwin-rebuild switch --flake .#<hostname>`, with activation as
root — is an implementation detail. Set `DARWIN_HOST` to target a machine other
than the one you are sitting at.

Note this is system configuration, not package installation: it replaces
`/run/current-system` with a whole new generation built from this repo. That is
different from `nix profile install`, which imperatively adds a single package
to `~/.nix-profile` and is not tracked here. Use the flake for anything that
should be reproducible; `nix profile install` (or better, `nix shell nixpkgs#x`)
only for throwaway one-offs.

### asterix

The Apple Silicon Mac, mid-migration from `macos-setup`. `hosts/darwin-minimal/`
is deliberately small while that migration is in progress — it manages the
nix-rosetta-builder Linux builder, neovim (built from `flakes/nvim`), neovide
wrapped to launch that exact neovim, and the Determinate Nix accommodations.
Everything else on that machine is still owned by `macos-setup`.

Because Determinate Nix owns the daemon, `nix.enable = false` and most `nix.*`
options are inert; `/etc/nix/machines`, GC and the custom nix.conf are
reinstated explicitly in `hosts/darwin-minimal/default.nix`.

`hosts/darwin/` and `modules/darwin/` are the full-featured upstream starter,
kept as the worked reference for the macos-setup migration. They are not
instantiated in `flake.nix`, so there is no buildable configuration for them.

## Layout

```
.
├── apps         # Nix commands used to bootstrap and build configuration
├── hosts        # Host-specific configuration
├── modules      # macOS and nix-darwin, NixOS, and shared configuration and modules
├── overlays     # Drop an overlay file in this dir, and it runs. So far, mainly patches.
├── templates    # Starter versions of this configuration
```

## Configuration references

This is a listing of the location's of the most important configurations,
referencing the template used where applicable.

- Template for the overall nix config is from the awesome
  [dustinlyons config](https://github.com/dustinlyons/nixos-config/tree/main).
- [neovim module](./modules/nvim) is built with [nixCats](https://nixcats.org/)
  and the configs are inspired by:
  - [nixCats templates](https://nixcats.org/nixCats_templates.html), especially
    the amazing [example template](https://github.com/BirdeeHub/nixCats-nvim/tree/main/templates/example)
    which was used as a base for the lze, paq+mason fallback etc.
  - [ThePrimeagen's config](https://github.com/ThePrimeagen/init.lua) and the 0
    to LSP video for inspiration of what are basic necessities
  - Too many different dotfiles repos and plugin docs to list here, the
    community is vast and incredible..

## Future ideas

- Remote terminal config, i.e. a simpler configuration with minimal
  dependencies, installable on a remote system. Provide most important terminal 
  configurations and programs without system configuration.
