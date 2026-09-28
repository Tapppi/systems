# Overlays

Files in this directory run automatically as part of each build. Some common ways I've used overlays in the past:

* Applying patches
* Downloading different versions of files (locking to a version or trying a fork)
* Workarounds and stuff I need to run temporarily

See `10-feather-font.nix` for an example.

`20-rsync.nix` temporarily supplies rsync 3.5.1 until nixpkgs catches up.
The shared NixOS module loads it automatically. The minimal Darwin host,
its Rosetta guest, and the installer module opt in explicitly because they
do not import that shared module. Remove those imports with the overlay.
