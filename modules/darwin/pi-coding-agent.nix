# pi — delivered from nixpkgs-fresh so coding-agent releases can move
# independently of the main pin, which rebuilds nvim and the Rosetta builder.
# Upgrade with:
#
#   nix flake update nixpkgs-fresh && nix run .#build-switch
#
# The binary lives in the read-only store and cannot self-update. The nixpkgs
# wrapper already sets PI_SKIP_VERSION_CHECK=1 and PI_TELEMETRY=0.
{ pkgs, inputs, ... }:

{
  environment.systemPackages = import ../../packages/harnesses.nix {
    pkgsFresh = inputs.nixpkgs-fresh.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    names = [ "pi-coding-agent" ];
  };
}
