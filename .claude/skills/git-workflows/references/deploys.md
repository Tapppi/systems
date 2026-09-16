# Deploying

Deploying is **independent of landing**. A NixOS host deploys from whatever
branch you are on; nothing has to reach `main` first. That is deliberate — it
is what lets bring-up and iteration happen on a branch — and it is exactly why
the preflight check below exists.

## Guardrails

| Rule | Exception |
|---|---|
| Preflight before every deploy | None |
| Don't deploy past a preflight refusal | Only `PREFLIGHT_ASSUME_UNKNOWN=1`, below, and only for the stated case |
| Don't activate darwin config | None — build and hand to the user |
| Don't deploy a host another branch owns | None. Resolve with its owner first |

## Preflight

```bash
scripts/deploy-preflight.sh <host>
```

Two branches can deploy to the same host and silently overwrite each other,
and a stale branch can silently revert a host below `main`. Preflight reads the
target's `system.configurationRevision` over SSH and compares it to the
deploying branch:

| Target revision | Verdict |
|---|---|
| Ancestor of `HEAD` | **OK** — deploy |
| Ancestor of `main` only | **Rebase** onto `main`, then retry |
| Anything else | **Blocked** — another branch owns this host |
| Unknown or absent | **Blocked** — provenance unverifiable |

**"Another branch owns this host" is not a lock to break.** It means someone
else's work is running there. Find out whose before doing anything:

```bash
git log --oneline -3 <rev>
git branch -a --contains <rev>
```

### The one override

A host installed before `system.configurationRevision` was set reports
nothing, and cannot report anything until it is deployed once from a config
that sets it. That first deploy is the only thing the override is for:

```bash
PREFLIGHT_ASSUME_UNKNOWN=1 scripts/deploy-preflight.sh <host>
```

Confirm by hand that nothing running on the host matters first. It proceeds
blind — that is the whole point, and why it is an environment variable rather
than a flag.

## Deploying

```bash
nixos-rebuild switch --flake .#<host> --target-host root@<host>
```

Build first if you want the failure separated from the activation:

```bash
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
```

### Untracked files are invisible to nix

Flake evaluation reads the git tree, so a **new** file that is not staged is a
hard error, not a silent skip:

```
error: Path 'modules/nixos/<host>/new.nix' in the repository … is not tracked by Git.
```

`git add` it. This bites every time a module is split into a new file, and it
is the most common worktree deploy failure.

Uncommitted *modifications* to tracked files do apply — nix warns "Git tree is
dirty" and proceeds. A dirty deploy stamps the host with `<rev>-dirty`, which
nobody can reconstruct later; preflight warns about this. Prefer committing
first.

## Why this is a guard and not a design

Preflight serialises hosts by rejection: it stops collisions but never says
what a host is *supposed* to be running. A dedicated deploy branch that all
deploys are driven from, and that in-flight branches merge into, would replace
rejection with convergence — and it has to live on the remote to be worth
anything, which opens the question of deploying centrally from forge CI. That
design is an open item on HLB-9 in the vault.
