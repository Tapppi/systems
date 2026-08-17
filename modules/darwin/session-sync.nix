# Mirrors this Mac's AI coding-agent session transcripts to the homelab
# archive guest (arkisto), which is the permanent record.
#
# Claude Code writes JSONL transcripts under ~/.claude/projects/<mangled-cwd>/
# and prunes them after cleanupPeriodDays. The archive outlives that window, so
# the local retention setting stops being the thing that decides what survives.
#
# The whole ~/.claude tree is sent, not just projects/: history.jsonl is never
# pruned and is the only record of sessions whose transcripts are gone, and
# tool-results/ and subagents/ hold content spilled out of the transcripts that
# a session needs to be read — or resumed — in full.
#
# The remote end is a forced-command rrsync in write-only mode (see
# hosts/nixos/arkisto), so this key can add to the archive and can neither read
# it back nor get a shell. Paths below are relative to the rrsync root.
{ config, pkgs, lib, ... }:

let
  user = "tapani";
  home = "/Users/${user}";

  archiveHost = "arkisto";
  syncKey = "${home}/.ssh/id_archive_sync";

  # ~/.ssh/config sets IdentityAgent on Host *, pointing every connection at
  # the 1Password agent, which needs an interactive desktop approval that a
  # launchd job cannot answer. IdentitiesOnly + an explicit -i keeps this job
  # on its own on-disk key, and keeps that key out of interactive ssh.
  sshCommand = lib.concatStringsSep " " [
    "${pkgs.openssh}/bin/ssh"
    "-i ${syncKey}"
    "-o IdentitiesOnly=yes"
    "-o BatchMode=yes"
    "-o ConnectTimeout=15"
  ];

  syncScript = pkgs.writeShellScript "claude-session-sync" ''
    set -uo pipefail

    log="${home}/Library/Logs/claude-session-sync.log"
    exec >>"$log" 2>&1
    echo "=== $(date -Iseconds) start ==="

    # A launchd job denied access to the source by TCC still exits 0 having
    # transferred nothing, which is indistinguishable from a no-op run at the
    # destination. Counting the source first turns that silent failure into a
    # loud one. ~/.claude sits at the home root rather than under
    # Documents/Desktop/Downloads, so it is outside TCC's protected paths —
    # this guard is here for the day that stops being true.
    local_count=$(${pkgs.findutils}/bin/find "${home}/.claude/projects" \
      -name '*.jsonl' 2>/dev/null | ${pkgs.coreutils}/bin/wc -l)
    if [ "$local_count" -eq 0 ]; then
      echo "ERROR: no local transcripts readable - TCC denial or wrong path"
      exit 1
    fi

    # No --delete: the archive is append-only and deliberately keeps sessions
    # the Mac has already pruned. .credentials.json holds live OAuth tokens and
    # must never leave the machine.
    ${pkgs.rsync}/bin/rsync -az --partial --timeout=120 \
      -e "${sshCommand}" \
      --exclude '.credentials.json' \
      --exclude 'shell-snapshots/' \
      "${home}/.claude/" \
      "sync@${archiveHost}:agent-sessions/${config.networking.hostName}/claude/"
    rc=$?

    # rrsync holds an exclusive flock on the archive root for the duration of a
    # write and dies rather than waits, so a run that overlaps another Mac's
    # fails outright. Idempotent and additive, so the next run subsumes it —
    # worth logging, not worth alerting on.
    if [ $rc -ne 0 ]; then
      echo "ERROR: rsync exited $rc (lock contention if another Mac is syncing)"
      exit $rc
    fi

    echo "=== $(date -Iseconds) ok ($local_count local transcripts) ==="
  '';
in
{
  launchd.user.agents.claude-session-sync = {
    command = "${syncScript}";
    serviceConfig = {
      # Half-hourly. StartInterval counts from load and does not fire while the
      # Mac is asleep; launchd runs a single deferred pass on wake rather than
      # replaying every missed interval, which is the behaviour wanted here
      # since each run is a full reconciliation.
      StartInterval = 1800;
      RunAtLoad = true;
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardErrorPath = "${home}/Library/Logs/claude-session-sync.err";
    };
  };
}
