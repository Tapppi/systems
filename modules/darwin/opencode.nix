# OpenCode — held on 1.x from the nixpkgs-opencode input until the move to
# 2.x (issue #35), because 2.x does not run V1 plugins. After the migration it
# comes from nixpkgs-fresh again, like the other coding agents, and upgrades
# with:
#
#   nix flake update nixpkgs-fresh && nix run .#build-switch
#
# The binary lives in the read-only store and cannot self-update; the nixpkgs
# wrapper already sets OPENCODE_DISABLE_AUTOUPDATE=true.
# Config stays in ~/.config/opencode/, managed by the dotfiles repo's additive
# rsync, which preserves runtime state. This module adds no competing writer.
{ pkgs, inputs, ... }:

let
  opencode = inputs.nixpkgs-opencode.legacyPackages.${pkgs.stdenv.hostPlatform.system}.opencode;
in
{
  environment.systemPackages = [ opencode ];
}
