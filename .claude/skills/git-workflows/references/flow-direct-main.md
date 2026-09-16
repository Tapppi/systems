# Flow: direct on main

For a small, contained edit with an operator watching — a typo, a comment
fix, a version bump.

Allowed when **either**:

- the user asked for it directly, or
- you can see the change is genuinely small and self-contained, and you said
  so and asked before doing it.

The second is not a licence to decide for yourself that something is small.
Ask, and take a no.

## Guardrails for this flow

| Rule | Exception |
|---|---|
| Commit immediately, in the same turn | None — see below |
| **`git commit -- <explicit paths>`**, never `git add -A` / `.` | None. The main checkout's index is shared; this is a global never |
| Don't activate afterwards | None. Building is fine; activating is the user's |
| One small change, then stop | If it grows, stop and move to a worktree |

## Why immediately

The main checkout is where the user runs `nix run .#build-switch`, and that
builds *whatever is in the working tree*, committed or not. An edit left
sitting there can reach a live system generation nobody chose to activate.
Other sessions also work in this checkout and will sweep an uncommitted file
into their own commit.

```bash
git commit -- path/to/file.nix
git show --stat HEAD
```

## When it stops being this flow

The moment the change turns out to touch several files, need iteration, or run
long enough that you are not sure the operator is still watching — stop, and
start again in a worktree under the [default flow](flow-pr-review.md). Work
already committed on `main` stays; just do the rest properly.

Anything backgrounded or autonomous is never this flow, regardless of size.
