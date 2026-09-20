---
name: git-workflows
description: Git, forge and deploy conventions for changing this repo — branching, worktrees, commits, PRs, review, landing and activating configuration on real hosts. Load before starting any change that will produce commits, and before any push, merge, PR or deploy.
---

# Agent git workflows

How work gets from an idea into `main`, and from a branch onto a machine.
Four landing flows, differing only in who reviews and how it lands, plus a
deploy path that is **independent of all of them**.

Pick a landing flow **before** you start committing — switching later means
rewriting history.

## Never, in any flow

These have no exceptions. Everything conditional lives in the flow files.

1. **Never `git add -A` / `git add .` / `git add --all` outside a worktree.**
   Other sessions routinely leave work staged in the main checkout, so this
   stages theirs into your commit. Inside a worktree the index is yours alone
   and staging is unrestricted.
2. **Never rebase `main` onto a branch.** Branch-onto-`main` is the normal
   catch-up; the reverse rewrites shared history and is never correct.
3. **Never rewrite history someone else may have read.** Before a push, your
   history is yours to clean up freely. After a push, the line is whether the
   branch has been *looked at*: tidying your own `agent/` branch that carries
   no review and no comments is fine and is pre-approved by the push guard;
   rewriting once a review or comment exists needs the user to ask. Never
   force-push `main`, and never a plain `--force` — the mandatory form is
   `--force-with-lease --force-if-includes`
   ([why](references/flow-pr-review.md#rewriting-a-pushed-branch)).
   `.claude/hooks/git-push-guard.sh` enforces this, so a prompt here is the
   rule speaking, not an obstacle to route around.
4. **Never commit files you did not change.** Check `git show --stat HEAD`
   after every commit.
5. **Never activate macOS configuration.** `nix run .#build-switch` and
   `darwin-rebuild switch` need interactive sudo this session does not have,
   and activating is the user's call regardless. Build, then hand over.
6. **Never deploy without preflight.** See below.

## Pick a landing flow

| Situation | Flow |
|---|---|
| Any non-trivial change — **the default** | [PR with user review](references/flow-pr-review.md) |
| The task explicitly pre-approved autonomous delivery | [Autonomous PR](references/flow-pr-autonomous.md) |
| The user explicitly asked to merge locally, no PR | [Local merge](references/flow-local-merge.md) |
| A small edit, operator watching, and you asked first | [Direct on main](references/flow-direct-main.md) |

If nothing was said, you are in the default flow.

## Deploying is not landing

**A NixOS host deploys straight from the worktree branch.** Nix evaluates the
flake from the working directory, so there is nothing to merge first, and no
landing flow gates a deploy.

| Target | Command | Agent may run it? |
|---|---|---|
| NixOS host | `nixos-rebuild switch --flake .#<host> --target-host root@<host>` | Yes, after preflight — SSHes as root, no local sudo |
| asterix (darwin) | `nix run .#build-switch` | **No.** Interactive sudo; build and hand over |

Read [deploys.md](references/deploys.md) before the first one. It covers the
preflight check that stops two branches fighting over a host, the untracked-file
trap that silently omits new modules, and what to do when preflight refuses.

## Also read

- [deploys.md](references/deploys.md) — preflight, the deploy flow, host ownership
- [traps.md](references/traps.md) — untracked files, inspecting merges,
  upstream/push refs, syncing with `main`
