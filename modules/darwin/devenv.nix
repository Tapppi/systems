# devenv (devenv.sh) — delivered from nixpkgs-fresh so it can move independently
# of the main pin, which rebuilds nvim and the Rosetta builder's guest image.
# Upgrade with:
#
#   nix flake update nixpkgs-fresh && nix run .#build-switch
#
# nixpkgs-fresh is plain nixos-unstable, so the package substitutes from
# cache.nixos.org and no extra binary cache needs trusting.
{ pkgs, inputs, ... }:

let
  devenv = inputs.nixpkgs-fresh.legacyPackages.${pkgs.stdenv.hostPlatform.system}.devenv;
in
{
  environment.systemPackages = [ devenv ];
}
