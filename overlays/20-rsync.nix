# rsync 3.5.1 fixes the 3.5.0 path-handling regressions, including rrsync's
# restricted-root handling. Remove once the main nixpkgs pin includes it.
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
}
