#!/usr/bin/env bash
# Refuse to deploy when the target already runs a closure this branch does not
# contain.
#
# Deploys run from a worktree branch rather than from main, so nothing else
# stops two branches from overwriting each other on the same host, or stops a
# stale branch from silently reverting a host below main. This compares the
# revision the target actually booted against the branch about to deploy.
#
#   ancestor of HEAD    -> deploy
#   ancestor of main    -> the target is ahead via main; rebase and retry
#   anything else       -> another branch owns this host
#   unknown             -> provenance unverifiable; refuse
#
# Depends on system.configurationRevision being set (flake.nix does this). A
# host installed before that landed reports nothing and is refused until its
# first deploy from a revision-carrying config.
set -euo pipefail

host=${1:-}
if [ -z "$host" ]; then
	echo "usage: ${0##*/} <host> [--user <ssh-user>]" >&2
	exit 64
fi
ssh_user=root
[ "${2:-}" = "--user" ] && ssh_user=${3:?--user needs a value}

say() { printf '%s\n' "$*" >&2; }
block() {
	say ""
	say "BLOCKED: $*"
	exit 1
}

# The branch we would deploy. Fails loudly outside a repo.
head_rev=$(git rev-parse HEAD)
branch=$(git rev-parse --abbrev-ref HEAD)

if ! git diff --quiet HEAD 2>/dev/null; then
	say "note: working tree is dirty — nix will deploy the dirty state, and the"
	say "      target will record '<rev>-dirty', which nobody can reconstruct."
fi

say "preflight: ${host} <- ${branch} (${head_rev:0:12})"

target_raw=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "${ssh_user}@${host}" \
	'nixos-version --json 2>/dev/null || true' </dev/null) ||
	block "cannot reach ${ssh_user}@${host} over SSH."

target_rev=$(printf '%s' "$target_raw" | jq -r '.configurationRevision // empty' 2>/dev/null || true)

if [ -z "$target_rev" ]; then
	# Chicken-and-egg: a host installed before system.configurationRevision was
	# set reports nothing, and cannot report anything until it is deployed once
	# from a config that sets it. The override exists for exactly that first
	# deploy, and is deliberately noisy rather than a flag.
	[ "${PREFLIGHT_ASSUME_UNKNOWN:-}" = "1" ] || block \
		"${host} reports no configurationRevision, so what it runs cannot be
         identified. Either it predates that option being set, or it was
         installed by nixos-anywhere and has not been deployed since.

         Confirm by hand that nothing running on it is worth keeping, then:

             PREFLIGHT_ASSUME_UNKNOWN=1 scripts/deploy-preflight.sh ${host}"

	say "OVERRIDE: ${host} has no identifiable revision and"
	say "          PREFLIGHT_ASSUME_UNKNOWN=1 was set. Proceeding blind — this"
	say "          deploy may overwrite work from another branch."
	exit 0
fi

# A dirty deploy records '<rev>-dirty'; the base commit is still the best
# available provenance, so test ancestry against that and warn.
case "$target_rev" in
*-dirty)
	say "warning: ${host} runs a DIRTY closure (${target_rev}). Its exact tree"
	say "         is not reconstructable; testing against its base commit."
	target_rev=${target_rev%-dirty}
	;;
esac

git cat-file -e "${target_rev}^{commit}" 2>/dev/null || block \
	"${host} runs ${target_rev:0:12}, which is not a commit in this repo.
         It was deployed from a branch that was never pushed. Fetch it, or
         find whoever deployed it, before overwriting their host."

if git merge-base --is-ancestor "$target_rev" HEAD; then
	if [ "$target_rev" = "$head_rev" ]; then
		say "OK: ${host} already runs exactly ${head_rev:0:12}. Deploy is a no-op."
	else
		say "OK: ${host} runs ${target_rev:0:12}, an ancestor of this branch."
	fi
	exit 0
fi

# Target is not in our history. Distinguish "ahead via main" from "someone
# else's branch", because only the first is ours to fix.
main_ref=main
git rev-parse --verify --quiet "$main_ref" >/dev/null || main_ref=origin/main

if git rev-parse --verify --quiet "$main_ref" >/dev/null &&
	git merge-base --is-ancestor "$target_rev" "$main_ref"; then
	block "${host} runs ${target_rev:0:12}, which is on ${main_ref} but not on
         ${branch}. Deploying would revert it. Rebase and retry:

             git rebase ${main_ref}
             scripts/deploy-preflight.sh ${host}"
fi

block "${host} runs ${target_rev:0:12}, which is on neither ${branch} nor
         ${main_ref} — another worktree deployed it. Deploying would silently
         overwrite that work. Resolve with its owner; do not force past this.

             git log --oneline -3 ${target_rev}
             git branch -a --contains ${target_rev}"
