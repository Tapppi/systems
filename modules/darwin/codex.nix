# Codex — delivered from nixpkgs-fresh so coding-agent releases can move
# independently of the main pin, which rebuilds nvim and the Rosetta builder.
# Upgrade with:
#
#   nix flake update nixpkgs-fresh && nix run .#build-switch
#
# The binary lives in the read-only store and cannot self-update.
# /etc/codex/config.toml is the system defaults layer, below ~/.codex/config.toml.
# Codex keeps owning that user file, including its state and TUI overrides;
# this module never writes to it. Existing user keys keep winning, so on a
# machine that already has a user file the owner deletes the overlapping keys
# once — model, model_reasoning_effort, model_provider, model_context_window,
# model_auto_compact_token_limit, approvals_reviewer and the [features] flags —
# to adopt these defaults; Codex rewrites model/effort/features only when they
# are changed in the TUI, which is the behaviour wanted.
# Only owner intent goes here: model, effort, provider, window, auto-compact,
# approvals and feature flags. Everything the app writes for itself — project
# trust, TUI state, hook hashes, marketplaces, plugins, node_repl trust, the
# desktop block, and the MCP server table with its credentials — stays in the
# user file and out of the world-readable store.
#
# The package puts three binaries on PATH: codex, codex-code-mode-host and a
# generically named logs_client. Nothing else provides the last one today.
{ pkgs, inputs, ... }:

let
  codex = inputs.nixpkgs-fresh.legacyPackages.${pkgs.stdenv.hostPlatform.system}.codex;
in
{
  environment.systemPackages = [ codex ];

  environment.etc."codex/config.toml".text = ''
    # Managed by systems/modules/darwin/codex.nix. User settings override these defaults.
    model = "gpt-6-astra"
    model_reasoning_effort = "medium"
    model_provider = "openai"
    model_context_window = 1000000
    model_auto_compact_token_limit = 700000
    approvals_reviewer = "auto_review"

    # The binary comes from the nix store and cannot rewrite itself, so a
    # startup check can only advertise an update it cannot apply.
    check_for_update_on_startup = false

    [features]
    hooks = true
    js_repl = false
  '';
}
