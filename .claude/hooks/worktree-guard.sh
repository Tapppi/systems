#!/usr/bin/env bash
# PreToolUse guard for this repo's git and deploy workflows.
#
# Enforces only the rules in the `git-workflows` skill's "Never, in any flow"
# list — the ones with no exceptions. Everything conditional is left to the
# flow files, because a guard that has to guess which flow you are in produces
# false positives, and a guard with false positives gets disabled.
#
# stdin: PreToolUse JSON payload. stdout: a permission decision, or nothing.
set -uo pipefail

payload=$(cat)

emit_context() {
	# Deliberately not jq: this path has to work when jq is what is missing.
	local text=${1//\\/\\\\}
	text=${text//\"/\\\"}
	text=${text//$'\n'/\\n}
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$text"
	exit 0
}

if ! command -v jq >/dev/null 2>&1; then
	emit_context "ENVIRONMENT WARNING: jq is not installed, so this repo's git-workflows guard cannot parse tool input and is running unenforced for this call. The rules still apply — read the 'git-workflows' skill and follow them manually, and be especially careful with deploys, which are normally gated here. Tell the user their environment is misconfigured and jq should be installed (brew install jq); do not silently continue as if the guard were active."
fi

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

FLOW_RULES="Read the 'git-workflows' skill before your first commit. It has four landing flows — PR with user review (the default), autonomous PR, local merge, direct on main — and you pick one before committing, because switching later means rewriting history. Each states its own guardrails and exceptions, so do not reason from the global never-list alone. Deploying is separate from landing: a NixOS host deploys straight from this worktree, always behind scripts/deploy-preflight.sh — see deploys.md."

# A linked worktree has its own gitdir; the main checkout's gitdir and common
# dir are the same path. Detecting it this way rather than by matching
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
	inform "$FLOW_RULES"
	;;
Bash) ;;
*)
	exit 0
	;;
esac

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# Whole-tree staging outside a worktree: the vault index is shared with
# obsidian-git and other sessions. Inside a worktree it is the agent's alone.
if printf '%s' "$cmd" | grep -Eq '\bgit +add +(-A|--all|\.)( |$)' && ! in_worktree; then
	deny "You are in the main checkout, where other sessions routinely leave work staged — whole-tree staging would sweep their work into your commit. Either work in a worktree, where this is unrestricted, or stage explicit paths and commit with 'git commit -- <paths>'. See the 'git-workflows' skill."
fi

# Rebasing main onto anything rewrites shared history. Checked by where HEAD
# actually is rather than by what the command names, because 'git rebase
# agent/foo' while on main is the dangerous case and mentions main nowhere.
if printf '%s' "$cmd" | grep -Eq '\bgit +rebase\b' &&
	! printf '%s' "$cmd" | grep -Eq -- '--(continue|abort|skip|edit-todo|show-current-patch)\b' &&
	[ "$(git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)" = "main" ]; then
	deny "HEAD is on main, so this rebases MAIN onto something else — that rewrites shared history and is forbidden in every flow. Branch-onto-main is the direction you want: check out the branch and run 'git rebase main' there. See the 'git-workflows' skill."
fi

# The same mistake spelled as a compound command, where HEAD is still elsewhere
# when the hook runs and the check above cannot see it.
if printf '%s' "$cmd" | grep -Eq '\b(git +checkout|git +switch) +main\b' &&
	printf '%s' "$cmd" | grep -Eq '\bgit +rebase\b'; then
	deny "This checks out main and then rebases, which rebases MAIN onto another branch — forbidden in every flow. To catch a branch up, run 'git rebase main' from the branch instead. See the 'git-workflows' skill."
fi

# Local darwin activation. Needs interactive sudo no agent has, and activating
# is the user's call regardless.
if printf '%s' "$cmd" | grep -Eq '(nix +run +[^ ]*#build-switch|\bdarwin-rebuild +(switch|activate)\b)'; then
	deny "Activating macOS configuration is the user's call and needs interactive sudo this session does not have. Build instead — 'nix build .#darwinConfigurations.asterix.system' or 'nix run .#build' — then ask the user to run 'nix run .#build-switch' themselves. See the 'git-workflows' skill."
fi

# The starter's placeholder linux app: targets nixosConfigurations.<arch>,
# whose keys list is empty, so activating it strands a host with no SSH access.
if printf '%s' "$cmd" | grep -Eq 'nix +run +[^ ]*#(build-switch|apply)\b' &&
	printf '%s' "$cmd" | grep -Eq '\b(x86_64|aarch64)-linux\b'; then
	deny "apps/<linux>/build-switch is the upstream starter's untested placeholder — it switches to nixosConfigurations.<arch>, whose 'keys' list is empty, so activating it would leave the host with no authorized SSH keys. Deploy NixOS hosts with 'nixos-rebuild switch --flake .#<host> --target-host root@<host>' after running scripts/deploy-preflight.sh. See 'git-workflows' → deploys.md."
fi

# Remote deploys are allowed from a branch, but only behind the preflight check.
if printf '%s' "$cmd" | grep -Eq '\bnixos-rebuild\b' &&
	printf '%s' "$cmd" | grep -Eq '\b(switch|boot|test)\b'; then
	inform "Deploy guardrail: run 'scripts/deploy-preflight.sh <host>' first unless you already did for this host on this revision. It reads the target's system.configurationRevision and refuses when the host runs a closure this branch does not contain — ancestor of HEAD is fine, ancestor of main only means rebase and retry, anything else means another branch owns that host and you must resolve with its owner rather than deploying past it. Also confirm any NEW file is 'git add'ed: nix cannot see untracked files and fails hard on them. See 'git-workflows' → deploys.md."
fi

if printf '%s' "$cmd" | grep -Eq '\bgit +worktree +add\b'; then
	inform "$FLOW_RULES"
fi

exit 0
