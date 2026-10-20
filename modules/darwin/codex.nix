# Codex — delivered from nixpkgs-fresh so coding-agent releases can move
# independently of the main pin, which rebuilds nvim and the Rosetta builder.
# Upgrade with:
#
#   nix flake update nixpkgs-fresh && nix run .#build-switch
#
# The binary lives in the read-only store and cannot self-update.
# /etc/codex/config.toml is the system defaults layer and ~/.codex/config.toml
# the user layer above it: a key set in the user file wins. Codex owns the user
# file and this module never writes to it. Codex writes model, effort and
# features there only when they are changed in the TUI, so the user file
# carries those choices and everything the app keeps for itself: project trust,
# TUI state, hook hashes, marketplaces, plugins, node_repl trust, the desktop
# block, and the MCP server table with its credentials, which stays out of the
# world-readable store.
# This file holds only owner intent: model, effort, provider, window,
# auto-compact, approvals, sandbox mode, web search, feature flags and the
# subagent cap. When an update retires or replaces the default model, update
# `model` here to its successor.
#
# The package puts three binaries on PATH: codex, codex-code-mode-host and a
# generically named logs_client. Nothing else provides the last one today.
{ pkgs, inputs, ... }:

{
  environment.systemPackages = import ../../packages/harnesses.nix {
    pkgsFresh = inputs.nixpkgs-fresh.legacyPackages.${pkgs.stdenv.hostPlatform.system};
    names = [ "codex" ];
  };

  environment.etc."codex/config.toml".text = ''
    # Managed by systems/modules/darwin/codex.nix. User settings override these defaults.
    model = "gpt-6.1-sol"
    model_reasoning_effort = "medium"
    model_provider = "openai"
    model_context_window = 700000
    model_auto_compact_token_limit = 400000
    approvals_reviewer = "auto_review"
    sandbox_mode = "workspace-write"
    web_search = "indexed"

    # The binary comes from the nix store and cannot rewrite itself, so a
    # startup check can only advertise an update it cannot apply.
    check_for_update_on_startup = false

    [features]
    hooks = true
    js_repl = false
    # Run every model on multi-agent V2. Without it the model catalog picks
    # V1 for older models, whose agents follow different limits.
    multi_agent_v2 = true

    # Subagent threads one session may run at once, the root excluded. Codex
    # has no nesting-depth limit for the models in use, so this cap on the
    # whole agent tree is the one that bounds how wide delegation fans out.
    [agents]
    max_concurrent_threads_per_session = 8
  '';
}
