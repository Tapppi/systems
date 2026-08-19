# Flow: PR with user review

**The default.** Use this unless the task put you in another flow.

You work in a worktree, land nothing yourself, and hand the user a PR that is
worth reading.

## Guardrails for this flow

| Rule | Exception |
|---|---|
| Don't commit to `main` | None here — that is the [direct-on-main](flow-direct-main.md) flow |
| Don't merge your own branch | None here. Merging is the user's, always |
| Don't push work you have not locally reviewed | None. Push complete, reviewed turns |
| Don't squash after pushing | Before pushing, squashing your own local review cycles is expected |

## Steps

### 1. Worktree

```bash
git worktree add .claude/worktrees/<topic> -b agent/<topic>
```

Branches from local `HEAD` (`.claude/settings.json` sets
`worktree.baseRef: head`), which is what you want when the work builds on a
feature branch rather than on `main`.

### 2. Work, committing freely

The worktree's index is yours alone, so staging is unrestricted. Commit as
often as is useful — these are working commits and nobody else sees them yet.
Run `git show --stat HEAD` after each and confirm the file list is what you
meant to change.

### 3. Verify, review your own work, then clean the history

Build before you review — `nix flake check`, and `nix build` the hosts you
touched. Building never activates anything, so it is always safe. Then review
the whole change yourself and fix what you find. Then
reshape the working commits into the history you want reviewed — squash the
review-cycle churn, reorder, split by logical change. This is unpushed work,
so it is yours to rewrite.

**What survives into the commit messages is standing state, not the story of
getting there.** A commit message says what the change is and why it is right;
it does not narrate that you tried it three ways first. The exception is a
question the work raised and did not settle — that is worth carrying, because
someone has to decide it.

### 4. Push and open the PR

```bash
git push -u origin agent/<topic>
gh pr create --fill
```

`--fill` takes the commit messages. Replace them when the PR needs to say
something the commits do not — see below.

### 5. Write the PR so it is worth reading

**The description carries intention and the high-level standing state**: what
this changes, why, and what the reader should end up believing. Not a
changelog of your commits — they are right there.

**Comments carry what has no home in the code or the description.** Use them,
including inline comments on specific lines, for:

- **New traps solved and gotchas avoided.** Only if genuinely new — do not
  restate a convention you simply followed correctly. This is the fuel for
  future tooling and instructions, and it is exactly what gets lost when local
  review cycles are squashed away, so if you squashed something interesting,
  say what it was.
- **Decisions that do not warrant a code comment**, have no natural place in
  the code, or are important enough that an existing code comment deserves
  pointing at.
- **Fixes you made during your own local review**, where knowing you already
  considered something saves the reviewer raising it.

### 6. Stop

The user reviews. They may merge, or ask for changes — including asking for a
cleaner history, in which case rewriting your own pushed branch is now
requested and therefore fine.

### 7. Clean up locally, after the merge

```bash
git worktree remove .claude/worktrees/<topic>
git branch -d agent/<topic>
```

The remote branch is the forge's to delete on merge — do not delete it by
hand, and do not assume it is gone.

## Why the squash-on-merge is safe

Squash-merging keeps `main` linear while the per-commit history stays
reachable at `refs/pull/<N>/head` — permanently, and independent of branch
deletion (`git fetch origin refs/pull/<N>/head`). That is the one place a
squash discards nothing, because the forge holds the pre-squash commits.

This is why the flow is worth its ceremony: it is the only landing that gives
both a linear `main` and a recoverable record of how the change was built.

## Catching up with `main`

Rebase the worktree onto `main` — see [traps.md](traps.md#syncing-with-main)
for when a merge is the better call.

## Deploying while the PR is open

Deploys do not wait for the merge and are not part of this flow — a NixOS host
deploys from the branch. See [deploys.md](deploys.md), and run the preflight
check every time.
