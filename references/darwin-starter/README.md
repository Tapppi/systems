# Darwin starter references

These uninstantiated examples are inputs to M2's workstation design and implementation. Retain them until
that design is finalized, then retire this reference subtree. They are not exported modules or buildable
flake configurations. The live interface is [darwinModules.workstation](../../modules/darwin/README.md).

The starter originates from [dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config).

| Reference | Purpose |
| --- | --- |
| [casks.nix](casks.nix) | Sample Homebrew application selection |
| [dock/default.nix](dock/default.nix) | Per-user Dock activation with URI comparison |
| [files.nix](files.nix) | Home Manager file examples |
| [home-manager.nix](home-manager.nix) | Sample account, Homebrew, Home Manager and Dock composition |
| [packages.nix](packages.nix) | Home Manager package list extending the shared list |

The sample account is `demo` and its Home Manager state version is `25.05`. The composition imports
`modules/shared/` reference files by explicit relative path. Importing it into a real workstation would also
introduce its identity, package, Homebrew and Home Manager policies: reconcile those with the consuming host
before adapting individual ideas. Preserve the active workstation's narrow ownership and separate main/fresh pins.
