# Hammerspoon, unpacked from the upstream release zip.
#
# Not in nixpkgs, so the version is pinned by hand; releases are roughly
# annual.
#
#   nix store prefetch-file --name Hammerspoon-<ver>.zip \
#     https://github.com/Hammerspoon/hammerspoon/releases/download/<ver>/Hammerspoon-<ver>.zip
#
# The bundle must land in the store byte for byte: Accessibility is granted
# against its designated requirement, and Hammerspoon is inert without it.
# See ./README.md.
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

    # cp -R, not `cp -RL`: the seal covers the bundle's internal framework
    # symlinks as symlinks.
    cp -R Hammerspoon.app "$out/Applications/"

    app="$out/Applications/Hammerspoon.app"

    # Standalone Mach-O with no rpath, so a symlink suffices. Exported here
    # because the cask's /opt/homebrew/bin/hs dangles once the cask goes.
    ln -s "$app/Contents/Frameworks/hs/hs" "$out/bin/hs"
    ln -s "$app/Contents/Resources/man/hs.man" "$out/share/man/man1/hs.1"

    runHook postInstall
  '';

  # MANDATORY: patchShebangs would rewrite the bundle's one sealed shebang
  # script and break signature verification. Also skips fixupPhase, which is
  # what keeps strip away from the bundle.
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
