# Shared configuration

[default.nix](default.nix) supplies nixpkgs policy and imports the repository's overlays.
The N150, combined T2 and Incus guest profiles import it explicitly. The Darwin workstation manages its
package set independently; directory placement does not make a file part of every platform's configuration.
See the [overlay constraints](../../overlays/README.md) before changing package scope.

## Files and consumers

| Path | Purpose and composition |
| --- | --- |
| [default.nix](default.nix) | NixOS profile nixpkgs settings and overlay loading. |
| [home-manager.nix](home-manager.nix) | Imports `inputs.nvim.homeModule`; used by the desktop Home Manager references. |
| [programs.nix](programs.nix) | Returns Home Manager program settings for Zsh, Git, Alacritty, SSH and tmux with synthetic identity defaults. |
| [packages.nix](packages.nix) | Function returning a package list for the desktop references; not a system or Home Manager module. |
| [files.nix](files.nix) | Returns an empty file attribute set, with a commented Emacs initialization example. |
| [config/p10k.zsh](config/p10k.zsh) | Powerlevel10k configuration loaded by `programs.nix`. |
| [nvim/default.nix](nvim/default.nix) | Standalone nixCats template source; the active editor input comes from `flakes/nvim`. |

The [NixOS desktop references](../nixos/README.md#desktop-reference-files) and
[Darwin starter references](../../references/darwin-starter/README.md) consume the shared desktop settings.
They are outside the exported workstation/server compositions. For active editor work, start with the
[Neovim flake](../../flakes/nvim/README.md); for package ownership, follow the
[repository conventions](../../docs/conventions.md#module-and-package-changes).
