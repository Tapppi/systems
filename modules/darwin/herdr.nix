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
{ config, pkgs, lib, inputs, ... }:

let
  user = "tapani";
  home = "/Users/${user}";

  herdr = inputs.nixpkgs-fresh.legacyPackages.${pkgs.stdenv.hostPlatform.system}.herdr;

  # One herdr session per tmux session, so each tmuxinator project keeps its own
  # set of agents and reattaches to them.
  herdr-win = pkgs.writeShellApplication {
    name = "herdr-win";
    runtimeInputs = [ herdr ];
    text = ''
      # herdr-win              attach this tmux session's herdr session locally
      # herdr-win tmopro18     attach it on tmopro18, over SSH
      #
      # --session both creates and attaches, so there is nothing to provision
      # before the first run. --remote keeps the client local and only the
      # server remote, which is what preserves clipboard and image paste.
      host="''${1:-}"

      if [ -n "''${TMUX:-}" ]; then
        session="$(tmux display-message -p '#S')"
      else
        session="''${HERDR_SESSION:-default}"
      fi

      # Detaching with prefix+q returns here rather than letting the window's
      # command exit, which would close the tmux window and take any other pane
      # in it along.
      while true; do
        if [ -n "$host" ]; then
          herdr --remote "$host" --session "$session" || true
        else
          herdr --session "$session" || true
        fi

        printf '\n[herdr-win] detached from %s%s\n' "''${host:+$host:}" "$session"
        printf 'press q to close this window, any other key to reattach: '
        read -r -n 1 key || key=q
        printf '\n'
        if [ "$key" = q ]; then
          break
        fi
      done
    '';
  };

  herdrConfig = pkgs.writeText "herdr-config.toml" ''
    # Managed by systems/modules/darwin/herdr.nix. Edits here are replaced on the
    # next build-switch.

    onboarding = false

    [update]
    # The binary comes from the nix store and cannot rewrite itself, so a
    # background check can only ever report an update that `herdr update` will
    # fail to apply.
    version_check = false

    # Deliberately left on: this fetches agent-detection manifests, not binaries.
    # Claude Code, Codex and Cursor report session identity to herdr and nothing
    # else, so their working/blocked/idle state is read from these manifests —
    # a stale set is exactly what makes the agents sidebar wrong for those three.
    manifest_check = true

    [ui]
    # A distinct static shape per agent state rather than one dot recoloured, so
    # the sidebar stays readable without relying on hue. Needs herdr 0.8.2; the
    # nixos-unstable channel is still on 0.8.0, where this key parses as unknown
    # and is ignored, so it takes effect on the flake update that crosses 0.8.2.
    status_indicators = "symbols"

    # Name the detected agent in split pane borders when the pane has no manual
    # name, so a split is identifiable without focusing it.
    show_agent_labels_on_pane_borders = true

    [ui.toast]
    # Route notifications to the macOS notification centre instead of drawing
    # them inside herdr, which is the only delivery that is visible when herdr
    # is not the focused window.
    delivery = "system"
  '';
in
{
  environment.systemPackages = [ herdr herdr-win ];

  # herdr reads one fixed path and takes no config-path flag or environment
  # override, so the store copy has to be linked into place. Activation runs as
  # root — nix-darwin removed the per-user activation scripts — hence the
  # explicit ownership on the directory and on the symlink itself.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    install -d -o ${user} -g staff ${home}/.config/herdr
    ln -sfn ${herdrConfig} ${home}/.config/herdr/config.toml
    chown -h ${user}:staff ${home}/.config/herdr/config.toml
  '';
}
