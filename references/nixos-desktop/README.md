# NixOS desktop references

These uninstantiated desktop sources are design inputs outside the exported server profiles and examples.
They do not form a supported desktop configuration; server build evidence does not validate them.

| Path | Purpose |
| --- | --- |
| [home-manager.nix](home-manager.nix) | Home Manager desktop settings, Polybar and shared desktop imports. |
| [packages.nix](packages.nix) | Package-list function extending the shared desktop list. |
| [files.nix](files.nix) | Generated bspwm, sxhkd and rofi files and scripts. |
| [disk-config.nix](disk-config.nix) | Disko layout with a placeholder device. |
| [config/](config/) | Polybar, rofi and wallpaper assets. |

The [shared desktop references](../shared-desktop/README.md) supply shell, editor and package settings.
Relative Nix imports preserve that composition. Before use, supply appropriate identities and disk bindings,
check package and option compatibility, and verify the desktop as a whole. The generated-file reference
uses evaluation-time `HOME` and contains a machine-specific rofi source-directory string; these need
adaptation to the consuming configuration. Some generated scripts also depend on external commands or
files. The sources are retained for design inspection, not installation or activation.
