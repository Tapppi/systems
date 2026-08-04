# CLAUDE.md

`AGENTS.md` in this directory is the canonical agent guide for this repo — read
it and follow it. This file exists so Claude Code picks the guidance up
automatically; keep the two in sync when either changes.

The few things worth having up front, before that file is read:

## Activating configuration on asterix

`darwinConfigurations` are keyed by **hostname** (`asterix`), not architecture.
There is one user-facing entrypoint:

```sh
nix run .#build-switch   # build and activate (prompts for sudo)
nix run .#build          # build only, activates nothing
```

What happens beneath it — `nix build` of `darwinConfigurations.<host>.system`,
then `darwin-rebuild switch --flake .#<host>` as root — is implementation
detail. When asked how to activate, or how to apply a change just made, give
that one command.

**Not recommended, do not use:** `darwinConfigurations.aarch64-darwin` (the
per-architecture attribute) is the upstream starter's untested placeholder and
enables `nix-homebrew` with `autoMigrate`, which would take over the Homebrew
install that `tapppi/macos-setup` still manages. Likewise prefer this repo over
`nix profile install`, which is imperative and leaves no record in the flake.

Both points are documented in `AGENTS.md` so they need not be re-explained in
conversation — state the correct command and move on rather than reiterating
why the alternatives are wrong each time.

## Do not activate without approval

Never run `nix run .#build-switch`, `darwin-rebuild switch`, or any other
activation without the user explicitly asking for it. Building
(`nix run .#build`, `nix build`, `nix eval`) is fine and is the way to verify a
change.

## Migration status

asterix is mid-migration from `tapppi/macos-setup`. `hosts/darwin-minimal/` is
deliberately small: the nix-rosetta-builder Linux builder, neovim (from
`flakes/nvim`), neovide wrapped to launch that exact neovim, and the
Determinate Nix accommodations. Everything else on the machine is still owned
by `macos-setup`, so check there before assuming something is managed here.
