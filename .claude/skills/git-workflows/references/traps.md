# Traps and tips

Things that cost real time, independent of which flow you are in.

## Building is safe, activating is not

Always available, in any flow, from any worktree:

```bash
nix flake check
nix eval .#nixosConfigurations.<host>.config.<option>
nix build .#darwinConfigurations.asterix.system
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
```

None of these change a running system. Verify with them before proposing
anything.

**`nix build … | tail` reports the pipe's exit status, not nix's.** A failed
build reads as success. Redirect and capture explicitly:

```bash
nix build … >/tmp/build.out 2>&1; echo "EXIT=$?"
```

## Nix reads the worktree, but only tracked files

Flake evaluation follows the working directory, so everything works in a
worktree exactly as in the main checkout, uncommitted modifications included.

**New files are the exception and they fail hard**, not silently — see
[deploys.md](deploys.md#untracked-files-are-invisible-to-nix). `git add` any
file you just created before building.

## There is no `nix run .#` path for NixOS hosts

`apps/<linux>/build-switch` is the upstream starter's placeholder: it resolves
the target from `uname -m` and switches to `nixosConfigurations.<arch>`, whose
`keys` list is empty — activating it would leave a host with no authorized SSH
keys. It is non-executable, which is the only reason that has not happened.

Deploy with `nixos-rebuild --target-host`; onboard new hosts with
`nixos-anywhere` per ADR-001.

## Substituters are silently ignored when you are not trusted

`--extra-substituters` on the command line is accepted and then ignored by the
daemon unless your user is in `trusted-users`. `nix config show` reports the
cache as active either way, so the only symptom is an unexplained multi-hour
build where a download was expected. Put caches in the configuration
(`nix.settings.extra-substituters`, or `nix.custom.conf` on the Determinate
Mac), not on the command line.

## Syncing with `main`

**Rebase the worktree onto `main`.** That is the default way to pick up
changes made elsewhere while your branch was in progress.

```bash
git rebase main
```

**Merge `main` into the branch instead when the rebase turns ugly** — a long
branch can make a rebase demand the same conflict be resolved once per
replayed commit, against intermediate trees that never coherently existed.
When that costs you confidence in the resolutions, `git merge main` resolves
once and is the better call. Judgement, not a rule.

**Rebasing `main` onto a branch is forbidden** and is never the answer.

## Inspecting a merge commit

`git show <merge>` is unhelpful — on a merge it prints a combined diff that is
often empty. Use:

```bash
git diff <merge>^1..<merge>   # everything the merge brought in
git log --first-parent        # one line per landed unit
git revert -m 1 <merge>       # undo the whole unit
```

## Upstream and push refs

A branch made with `git worktree add -b` has **no upstream**, so a bare `git
push` errors until you set one — hence `git push -u origin agent/<topic>`.

`push.default` is `simple` (git's default), which refuses to push when the
upstream's name differs from the local branch's. So even a branch that somehow
ended up tracking `origin/main` cannot push to `main` by accident. Set a
mismatched upstream correctly rather than working around it:

```bash
git branch --set-upstream-to=origin/<branch>
```

## PR history survives, but only on the forge

`refs/pull/<N>/head` keeps the pre-squash commits permanently, unaffected by
branch deletion — but that lives on GitHub, not in the repo. A clone does not
carry it. If this repo ever moves to a self-hosted forge, re-verify that
`refs/pull/*` survives branch deletion there before relying on any
squash-merge.
