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

## A stale index makes per-path git commands lie

Two commands take a pathspec and look like they scope to it. Neither does when
something else is already staged, and **both succeed silently** — the exit code
tells you nothing.

### `git checkout -- <path>` restores from the index, not from `HEAD`

If the file is staged, this restores the *staged* version — precisely the thing
you were trying to throw away. The file looks reverted and is not.

```bash
git add file.ext          # the bad version is now IN the index
git checkout -- file.ext  # restores the bad version. Exit 0, no output.
```

Use an explicit source:

```bash
git checkout HEAD -- <path>
git restore --source=HEAD --staged --worktree <path>   # modern equivalent
```

### `git commit` commits the whole index, not the paths you just added

```bash
git add -A                # earlier, for some unrelated reason
git add path/to/one.ext   # "just this one"
git commit -m "..."       # commits everything staged
```

The tell is the *next* commit reporting "nothing to commit" — so a run that
splits work into several commits catches it, and a single mixed commit at the
end of a session does not.

Scope it, or clear the index first:

```bash
git commit -- <paths>     # pathspec-limited; ignores the rest of the index
git reset                 # unstage everything, then stage per commit
```

### The rule

**Clear or scope the index before any per-path operation, and verify the
result rather than the exit code.** `git diff HEAD -- <path>` after a revert,
`git show --stat HEAD` after a commit. Both commands report success either way.

**This repo manufactures the stale index itself.** Nix cannot see untracked
files and hard-errors on them, so `git add` is *required* to make a new module
visible to `nix build` — [deploys.md](deploys.md#untracked-files-are-invisible-to-nix)
tells you to do exactly that. Following that instruction is what leaves the
index dirty, so these two traps are a direct consequence of the build workflow
rather than a generic git curiosity. Stage what nix needs, then clear or scope
before committing or reverting.
