# Shared configuration

[default.nix](default.nix) supplies nixpkgs policy and imports the repository's overlays.
The N150, combined T2 and Incus guest profiles import it explicitly. The Darwin workstation manages its
package set independently; directory placement does not make a file part of every platform's configuration.
See the [overlay constraints](../../overlays/README.md) before changing package scope.

The inactive [shared desktop references](../../references/shared-desktop/README.md) supply Home Manager
settings for the [NixOS desktop](../../references/nixos-desktop/README.md) and
[Darwin starter](../../references/darwin-starter/README.md) references. For active editor work, start with the
[Neovim flake](../../flakes/nvim/README.md); for package ownership, follow the
[repository conventions](../../docs/conventions.md#module-and-package-changes).
