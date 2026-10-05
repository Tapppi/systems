# Reaps processes that coding-agent sessions leave running.
#
# The Claude Code codex plugin starts a detached `codex app-server` broker per
# workspace and stops it only from its SessionEnd hook, which looks up the
# broker for the session's own cwd. Brokers started for another directory — a
# worktree driven from an orchestrating session — or outliving a session that
# ended without the hook are never stopped, and each holds one set of MCP
# servers per Codex thread it ever ran. Fifteen such brokers had grown to
# ~38 GB, some six days old, before this existed.
#
# Brokers are reaped after 30 idle minutes. Killing one is safe: the plugin
# starts a fresh broker on its next call, and Codex threads are persisted on
# disk, so resume still works. See reaper.sh for what counts as idle.
#
# Run `agent-reaper --dry-run` to see what a pass would do.
{ pkgs, ... }:

let
  home = "/Users/tapani";

  agent-reaper = pkgs.writeShellApplication {
    name = "agent-reaper";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      pkgs.jq
    ];
    text = builtins.readFile ./reaper.sh;
  };
in
{
  environment.systemPackages = [ agent-reaper ];

  launchd.user.agents.agent-reaper = {
    command = "${agent-reaper}/bin/agent-reaper";
    serviceConfig = {
      # A 30-minute idle threshold checked every 5 minutes reaps within 35.
      StartInterval = 300;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = "${home}/Library/Logs/agent-reaper.log";
      StandardErrorPath = "${home}/Library/Logs/agent-reaper.log";
    };
  };
}
