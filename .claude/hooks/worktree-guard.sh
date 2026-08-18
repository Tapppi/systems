#!/usr/bin/env bash
# PreToolUse guard for this repo's worktree and deploy conventions.
#
# Blocks the moves that change live system state or that silently corrupt
# another session's work, and injects the landing rules when a worktree is
# created. Rules needing judgement stay in the `worktrees` skill; only
# unambiguous ones are enforced here, because a guard with false positives
# gets disabled.
#
# stdin: PreToolUse JSON payload. stdout: a permission decision, or nothing.
set -uo pipefail

payload=$(cat)

# No jq means no reliable parse. Allow rather than block the session on it.
command -v jq >/dev/null 2>&1 || exit 0

tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)

deny() {
	jq -nc --arg r "$1" '{
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			permissionDecision: "deny",
			permissionDecisionReason: $r
		}
	}'
	exit 0
}

inform() {
	jq -nc --arg c "$1" '{
		hookSpecificOutput: {
			hookEventName: "PreToolUse",
			additionalContext: $c
		}
	}'
	exit 0
}

LANDING_RULES="Worktree conventions (see the 'worktrees' skill for the full flow): commit to agent/<topic>, never to main; verify each commit with 'git show --stat HEAD'; land by pushing and opening a PR with 'gh pr create --fill', then stop and let the user merge. Deploys run from the worktree — no merge needed — but always behind scripts/deploy-preflight.sh. New files must be 'git add'ed or nix cannot see them."

# A linked worktree has its own gitdir; the main checkout's gitdir and common
# dir are the same path. Detecting it this way rather than by looking for
# '.claude/worktrees/' in the path keeps the guard correct for worktrees put
# somewhere else.
in_worktree() {
	local gitdir commondir
	[ -n "$cwd" ] || return 1
	gitdir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null) || return 1
	commondir=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null) || return 1
	[ "$gitdir" != "$commondir" ]
}

case "$tool" in
EnterWorktree)
	inform "$LANDING_RULES"
	;;
Bash) ;;
*)
	exit 0
	;;
esac

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# Whole-tree staging. The index is shared with other agent sessions, which
# routinely leave unrelated work staged.
if printf '%s' "$cmd" | grep -Eq '\bgit +add +(-A|--all|\.)( |$)' && ! in_worktree; then
	deny "You are in the main checkout, where other sessions routinely leave unrelated work staged — whole-tree staging would sweep it into your commit. Either work in a worktree (git worktree add .claude/worktrees/<topic> -b agent/<topic>), where this is unrestricted, or stage explicit paths and commit with 'git commit -- <paths>'. See the 'worktrees' skill."
fi

# Local darwin activation. Needs interactive sudo, which no agent has, and
# activating is the user's call regardless.
if printf '%s' "$cmd" | grep -Eq '(nix +run +[^ ]*#build-switch|\bdarwin-rebuild +(switch|activate)\b)'; then
	deny "Activating macOS configuration is the user's call and needs interactive sudo, which this session does not have. Build instead — 'nix build .#darwinConfigurations.asterix.system' or 'nix run .#build' — then ask the user to run 'nix run .#build-switch' themselves. See the 'worktrees' skill."
fi

# The starter's placeholder linux app: targets nixosConfigurations.<arch>,
# whose keys list is empty, so activating it strands a host with no SSH access.
if printf '%s' "$cmd" | grep -Eq 'nix +run +[^ ]*#(build-switch|apply)\b' &&
	printf '%s' "$cmd" | grep -Eq '\b(x86_64|aarch64)-linux\b'; then
	deny "apps/<linux>/build-switch is the upstream starter's untested placeholder — it switches to nixosConfigurations.<arch>, whose 'keys' list is empty, so activating it would leave the host with no authorized SSH keys. Deploy NixOS hosts with 'nixos-rebuild switch --flake .#<host> --target-host root@<host>' after running scripts/deploy-preflight.sh. See the 'worktrees' skill."
fi

# Remote deploys are allowed, but only behind the preflight check.
if printf '%s' "$cmd" | grep -Eq '\bnixos-rebuild\b' &&
	printf '%s' "$cmd" | grep -Eq '\b(switch|boot|test)\b'; then
	inform "Deploy guardrail: run 'scripts/deploy-preflight.sh <host>' first unless you already did for this host on this revision. It reads the target's system.configurationRevision and refuses when the host runs a closure this branch does not contain — ancestor of HEAD is fine, ancestor of main only means rebase and retry, anything else means another worktree owns that host. Deploying past it silently overwrites their work."
fi

if printf '%s' "$cmd" | grep -Eq '\bgit +worktree +add\b'; then
	inform "$LANDING_RULES"
fi

exit 0
