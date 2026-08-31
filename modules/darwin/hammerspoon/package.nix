# Hammerspoon, unpacked from the upstream release zip.
#
# Not in nixpkgs, so this is a local package rather than an overlay. The
# version is pinned by hand: releases are rare (1.0.0 in 2024-08, 1.1.0 in
# 2025-12, 1.1.1 in 2026-02), so this needs touching once or twice a year.
#
#   nix store prefetch-file --name Hammerspoon-<ver>.zip \
#     https://github.com/Hammerspoon/hammerspoon/releases/download/<ver>/Hammerspoon-<ver>.zip
#
# Everything here exists to land the notarized bundle in the store BYTE FOR
# BYTE. Accessibility is granted against the bundle's designated requirement,
# and Hammerspoon is inert without it — see ./README.md for why that survives
# both the move off Homebrew and later version bumps.
{ lib, stdenvNoCC, fetchurl, unzip }:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hammerspoon";
  version = "1.1.1";

  src = fetchurl {
    url = "https://github.com/Hammerspoon/hammerspoon/releases/download/"
      + "${finalAttrs.version}/Hammerspoon-${finalAttrs.version}.zip";
    hash = "sha256-EbsckPr1Qn83x71P5+q5d0rkPh1csCDFswiNrDKEnvo=";
  };

  nativeBuildInputs = [ unzip ];

  # The zip holds Hammerspoon.app at its root, so there is no directory for
  # the unpack phase to descend into.
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/Applications" "$out/bin" "$out/share/man/man1"

    # cp -R, not `cp -RL`: the bundle contains 11 relative framework symlinks
    # (Foo.framework/Versions/Current) that the code seal covers as symlinks.
    cp -R Hammerspoon.app "$out/Applications/"

    app="$out/Applications/Hammerspoon.app"

    # The CLI is a separately signed Mach-O linking only /System and /usr/lib,
    # with no LC_RPATH and no @executable_path, so it needs no wrapper. It must
    # be exported here because the Homebrew cask's /opt/homebrew/bin/hs is a
    # symlink into the cask's bundle and dangles once that goes — and Homebrew
    # precedes Nix on PATH, so it would shadow this one even while broken.
    ln -s "$app/Contents/Frameworks/hs/hs" "$out/bin/hs"
    ln -s "$app/Contents/Resources/man/hs.man" "$out/share/man/man1/hs.1"

    runHook postInstall
  '';

  # MANDATORY. Contents/Resources/timeout3 is the bundle's only shebang script
  # and it is sealed in CodeResources under ^Resources/ with no omit and no
  # optional. patchShebangs would repoint it at a store bash and invalidate
  # that seal, after which `codesign --verify` fails with "a sealed resource is
  # missing or invalid". This also skips fixupPhase entirely, which is what
  # keeps strip away from the bundle.
  dontFixup = true;

  meta = {
    description = "Staggeringly powerful macOS desktop automation with Lua";
    homepage = "https://www.hammerspoon.org/";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.platforms.darwin;
    mainProgram = "hs";
  };
})
