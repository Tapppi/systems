# Flow: local merge, no PR

**Only when the user explicitly asked to merge locally.** Not a fallback for
"the forge is inconvenient right now" — if you cannot open a PR, say so and
stop rather than switching flows on your own.

The trade this makes: no PR means no `refs/pull/<N>/head`, so **there is no
backup of the pre-merge commits anywhere**. That single fact drives every rule
below.

## Guardrails for this flow

| Rule | Exception |
|---|---|
| **Never squash the branch into `main`** | None. Without a PR the pre-squash commits exist nowhere else |
| Merge with `--no-ff` | None — a fast-forward loses the unit boundary |
| Don't merge until the user asked | The ask is what put you in this flow |

## Steps

Work exactly as in the [default flow](flow-pr-review.md) — worktree, free
commits, local self-review, then clean the history before landing. Cleaning
unpushed history is still fine and still expected; what is forbidden is
collapsing the whole branch as it lands.

```bash
git merge --no-ff agent/<topic>
git worktree remove .claude/worktrees/<topic>
git branch -d agent/<topic>
```

## Why `--no-ff` and not squash

A `--no-ff` merge keeps both properties you would otherwise have to choose
between: the individual commits stay in history as distinguishable ancestors,
**and** the merge commit is a single unit you can inspect or revert whole.

```bash
git diff <merge>^1..<merge>   # everything the merge brought in
git revert -m 1 <merge>       # undo the whole unit
git log --first-parent        # one line per landed unit
```

A squash here would give you the single unit while destroying the commits —
with no forge holding a copy. That is the asymmetry: squashing is safe behind
a PR precisely because the PR keeps what the squash throws away.
