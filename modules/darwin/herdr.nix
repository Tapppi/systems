# herdr — the agent multiplexer this Mac's coding-agent sessions live in.
#
# Delivered from `nixpkgs-fresh` rather than the flake's main nixpkgs. herdr cuts
# a stable release every one to two weeks, while the main pin is deliberately
# slow-moving: bumping it rebuilds nvim and the Rosetta builder's guest image.
# Refresh herdr, and only herdr, with
#
#   nix flake update nixpkgs-fresh && nix run .#build-switch
#
# The binary sits in the read-only store, so herdr's own `herdr update` and
# `herdr channel set` cannot replace it. The flake update above is the upgrade
# path; the config below turns off the background check that would otherwise
# advertise versions this host has no way to install.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  inherit (config.local.workstation) user home;

  pkgsFresh = inputs.nixpkgs-fresh.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  herdr = builtins.head (
    import ../../packages/harnesses.nix {
      inherit pkgsFresh;
      names = [ "herdr" ];
    }
  );
  herdr-win = import ../../packages/herdr-win.nix { inherit pkgs herdr; };
  settings = lib.recursiveUpdate (import ../shared/herdr/settings.nix) {
    # System delivery is visible while unfocused; tmux does not forward Herdr's OSC notifications.
    ui.toast.delivery = "system";
  };
  herdrConfig = (pkgs.formats.toml { }).generate "herdr-config.toml" settings;

in
{
  environment.systemPackages = [
    herdr
    herdr-win
  ];

  # Link the default config path while keeping sibling runtime state writable.
  # Activation runs as
  # root — nix-darwin removed the per-user activation scripts — hence the
  # explicit ownership on the directory and on the symlink itself.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    install -d -o ${user} -g staff ${home}/.config/herdr
    ln -sfn ${herdrConfig} ${home}/.config/herdr/config.toml
    chown -h ${user}:staff ${home}/.config/herdr/config.toml
  '';
}
