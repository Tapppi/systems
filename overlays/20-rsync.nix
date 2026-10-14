# rsync 3.5.1 fixes the 3.5.0 path-handling regressions, including rrsync's
# restricted-root handling. Pins at 3.5.1 or newer use their upstream package.
# Keep this version-gated substitution as a reusable cache-preserving example.
final: prev: {
  rsync =
    if prev.lib.versionOlder prev.rsync.version "3.5.1" then
      prev.rsync.overrideAttrs (old: {
        version = "3.5.1";
        src = final.fetchurl {
          url = "https://download.samba.org/pub/rsync/src/rsync-3.5.1.tar.gz";
          hash = "sha256-xV+cncEPuL7Dl7OZoP3e1TzJotjjCJG7DWNyTSXDe+8=";
        };
        # 3.5.1 enables internationalised daemon hostnames by default.
        buildInputs = old.buildInputs ++ [ final.libidn2 ];
        # The new test writes a shell fixture after patchShebangs has run.
        preBuild = (old.preBuild or "") + ''
          substituteInPlace testsuite/rsync-ssl-type-option_test.py \
            --replace-fail '#!/usr/bin/env bash' '#!${final.stdenv.shell}'
        '';
      })
    else
      prev.rsync;
} // prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
  # Keep fixed rsync for system scripts and image construction. The kernel's
  # build-time copy tool uses upstream rsync to preserve kernel/module caches.
  linuxPackagesFor = kernel: prev.linuxPackagesFor (
    kernel.overrideAttrs (attrs: {
      nativeBuildInputs = map
        (dependency: if dependency == final.rsync then prev.rsync else dependency)
        attrs.nativeBuildInputs;
    })
  );
  linuxPackages = final.linuxPackagesFor prev.linuxPackages.kernel;
}
