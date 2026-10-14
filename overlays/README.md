# Overlays

The shared NixOS module loads each `.nix` file in this directory. Overlays can
apply patches, select different package sources, or provide version-gated fixes.
See [10-feather-font.nix](10-feather-font.nix) for a package override.

[20-rsync.nix](20-rsync.nix) is a reusable example of substituting a fixed
package while preserving upstream kernel cache identities. It supplies rsync
3.5.1 for pins with an older version; pins at 3.5.1 or newer use their upstream
package. The example remains in place when that version condition becomes
inactive.

The Darwin workstation, its Rosetta guest, and the installer module opt in
explicitly because they do not import the shared module. Runtime rsync/rrsync,
Darwin application activation, and image construction use the fixed package.
The Darwin workstation also substitutes it into nix-darwin's separate
uninstaller configuration while the version override is needed.

On Linux, the kernel's native build dependency keeps the upstream rsync.
Changing even a build-time copy tool changes the kernel derivation and loses
matching kernel and module substitutes without changing kernel source or
configuration. The `linuxPackagesFor` wrapper scopes this exception for
explicit kernel package sets, including T2. The default `linuxPackages` alias
also goes through that wrapper, covering the generic host, installer and ARM
builder kernel. Other rsync consumers retain the version-gated fix.
