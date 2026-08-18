---
name: worktrees
description: Isolating, committing, landing and deploying agent work in this repo. Load before creating a worktree or branch, before committing on one, before any merge, push or PR, and before any deploy.
---

# Agent worktrees, landing and deploys

Agent sessions that change this repo work in a **git worktree**, not in the
main checkout.

The main checkout is where activation happens. `nix run .#build-switch` builds
*whatever is in the working tree*, committed or not — so in-flight agent edits
there can land in a live system generation nobody chose to activate. With more
than one session in the repo, their commits also mix into each other's
in-progress work.

## Guardrails

| Never | Instead |
|---|---|
| Commit to `main` | Commit to `agent/<topic>` in a worktree |
| `git add -A`, `git add .`, bare `git commit` | `git commit -- <explicit paths>` |
| Merge your own branch | Push, open a PR, stop |
| Squash a branch that exists only locally | `--no-ff`, so per-commit history survives |
| `nix run .#build-switch` | Never, as an agent — it needs interactive sudo. Build only |
| `nix run .#build-switch` for a NixOS host | It is the starter's placeholder, see below |
| Deploy without running `scripts/deploy-preflight.sh` | Preflight, then deploy |
| Activate from the main checkout on the agent's behalf | Leave activation to the user |

## Flow

1. **Create:**

   ```bash
   git worktree add .claude/worktrees/<topic> -b agent/<topic>
   ```

2. **Work and commit,** scoped by path. After each commit run
   `git show --stat HEAD` and confirm the file list is exactly yours.

3. **Verify — building is always safe, activating never is:**

   ```bash
   nix flake check
   nix build .#darwinConfigurations.asterix.system
   nix build .#nixosConfigurations.<host>.config.system.build.toplevel
   ```

4. **Land.** Push and open a PR:

   ```bash
   git push -u origin agent/<topic>
   gh pr create --fill
   ```

5. **Stop.** The user merges, squashing. Merge your own PR only when the task
   explicitly pre-approved it.

6. **Clean up once merged:**

   ```bash
   git worktree remove .claude/worktrees/<topic>
   git branch -d agent/<topic>
   ```

### Nix reads the worktree, but only tracked files

Flake evaluation follows the working directory, so everything above works in a
worktree exactly as in the main checkout, uncommitted changes included (nix
warns "Git tree is dirty" and proceeds).

**A new file nix cannot see is the most common worktree failure.** Untracked
files are a hard error, not a silent skip:

```
error: Path 'modules/nixos/<host>/new.nix' in the repository … is not tracked by Git.
```

`git add` it. This bites every time a module is split into a new file.

### Why PR-then-squash

Squash-merging on the forge keeps `main` linear while the per-commit history
stays reachable at `refs/pull/<N>/head` — permanently, and independent of
branch deletion (`git fetch origin refs/pull/<N>/head`). That is the one place
a squash is safe: it discards nothing, because the forge holds the pre-squash
commits.

A branch that never became a PR has no such backup, so squashing it destroys
the per-commit record of unattended work. Land those with `--no-ff`: the merge
commit keeps the individual commits *and* gives one revert point
(`git revert -m 1 <merge>`, `git diff <merge>^1..<merge>`).

## Deploying

**Deploys are decoupled from merging.** A NixOS host deploys straight from the
worktree branch — there is no need to merge to `main` first.

| Target | Command | Agent may run it? |
|---|---|---|
| NixOS host | `nixos-rebuild switch --flake .#<host> --target-host root@<host>` | Yes, after preflight — SSHes as root, no local sudo |
| asterix (darwin) | `nix run .#build-switch` | **No.** Interactive sudo; prepare and hand over |

There is no `nix run .#` path for NixOS hosts. `apps/<linux>/build-switch` is
the upstream starter's placeholder: it resolves the target from `uname -m` and
switches to `nixosConfigurations.<arch>`, whose `keys` list is empty —
activating it would leave a host with no authorized SSH keys. It is
non-executable, which is the only reason that has not happened.

### Preflight, every time

Two worktrees can deploy to the same host and silently overwrite each other,
and a branch deploy can silently revert a host to something older than `main`.
Before every deploy:

```bash
scripts/deploy-preflight.sh <host>
```

It reads the target's `system.configurationRevision` and compares it to the
deploying branch:

| Target revision | Verdict |
|---|---|
| Ancestor of `HEAD` | **OK** — deploy |
| Ancestor of `main` only | **Rebase** the worktree onto `main`, then retry |
| Anything else | **Blocked** — another worktree owns this host; resolve with its owner |
| Unknown or absent | **Blocked** — provenance unverifiable |

This guard serialises hosts by rejection rather than giving them a defined
source of truth. The convergence-branch design that would replace it is an open
item on HLB-9 in the vault.

## When a worktree is not needed

Small single-file edits with an operator watching. Anything long-running,
backgrounded, or accumulating uncommitted state needs one.

A subagent needing its own workspace branches a nested worktree off the
worktree already in use — reserve that for work too big for the normal
parallel-work conventions.
