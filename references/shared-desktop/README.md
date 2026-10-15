# Shared desktop references

These inactive sources support the [NixOS desktop](../nixos-desktop/README.md) and
[Darwin starter](../darwin-starter/README.md) references. They are outside the exported workstation and
server compositions. The active NixOS package policy is [modules/shared/default.nix](../../modules/shared/default.nix).

| Path | Purpose and composition |
| --- | --- |
| [home-manager.nix](home-manager.nix) | Imports the consumer-supplied `inputs.nvim.homeModule`. |
| [programs.nix](programs.nix) | Home Manager Zsh, Git, Alacritty, SSH and tmux settings with synthetic identity defaults. |
| [packages.nix](packages.nix) | Package-list function, not a system or Home Manager module. |
| [files.nix](files.nix) | Empty file attributes with a commented Emacs example whose source file is not supplied. |
| [config/p10k.zsh](config/p10k.zsh) | Powerlevel10k configuration loaded by `programs.nix`. |
| [nvim/default.nix](nvim/default.nix) | Uninstantiated standalone nixCats template, with its own input and Lua-source assumptions. |

Neither desktop reference imports the standalone nixCats template. The active editor input comes from
[flakes/nvim](../../flakes/nvim/README.md). These references need consumer-specific adaptation and
verification, including package and Home Manager option compatibility, before use.
