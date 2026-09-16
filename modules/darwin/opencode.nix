# OpenCode — delivered from nixpkgs-fresh so coding-agent releases can move
# independently of the main pin, which rebuilds nvim and the Rosetta builder.
# Upgrade with:
#
#   nix flake update nixpkgs-fresh && nix run .#build-switch
#
# The binary lives in the read-only store and cannot self-update; the nixpkgs
# wrapper already sets OPENCODE_DISABLE_AUTOUPDATE=true.
# Config stays in ~/.config/opencode/, managed by the dotfiles repo's additive
# rsync, which preserves runtime state. This module adds no competing writer.
{ pkgs, inputs, ... }:

let
  opencode = inputs.nixpkgs-fresh.legacyPackages.${pkgs.stdenv.hostPlatform.system}.opencode;
in
{
  environment.systemPackages = [ opencode ];
}
