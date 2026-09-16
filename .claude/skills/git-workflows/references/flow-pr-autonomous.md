# Flow: autonomous PR

**Only when the task explicitly pre-approved autonomous delivery.** A task
being long, backgrounded, or unsupervised does not put you here. If you are
unsure, you are in the [default flow](flow-pr-review.md).

Everything from the [PR flow](flow-pr-review.md) applies — worktree, local
review, clean history, a PR worth reading. This flow adds the review that the
user would otherwise have done, and lets you land it.

## Guardrails for this flow

| Rule | Exception |
|---|---|
| Don't merge your own branch | **This flow is the exception** — but only after an independent review passes |
| Don't merge on your own judgement of your own work | None. The reviewer must be a separate agent with clean context |
| Squash on merge | Unless the history is genuinely worth keeping — see below |

## The independent review is the point

The user is not reading this before it lands, so something else has to. Once
the PR is up, dispatch a **subagent or separate agent with clean context** —
one that has not been reasoning about this change — to review the PR and
**submit its review on the PR itself**, not back to you in conversation. The
review has to be an artifact on the PR, because that is what the user reads
afterwards to see what happened without you.

Merge on consensus. If the reviewer raises something real, fix it and have it
re-reviewed; do not merge over an unresolved objection and do not talk the
reviewer round. A reviewer that disagrees after a fix is a signal to stop and
leave it for the user.

## Landing it

```bash
gh pr merge --squash --delete-branch
```

**Squash is the default here.** Nobody reviewed the individual commits with an
eye to keeping them, so collapsing them into one reviewable, revertable unit is
right — and the pre-squash history survives at `refs/pull/<N>/head` regardless.

**The escape hatch:** if the branch genuinely carries a large, well-organised
history whose commits are each meaningful — a migration done in deliberate
stages, say — keep it (`gh pr merge --merge`). Say why in a PR comment. This
is the only place in agent work where that judgement is yours; everywhere else
the user makes it.

## Leave the record on the PR

The PR is the only account of work nobody watched. Beyond the usual
description and comments from the default flow, make sure it carries:

- **A log of what was actually done**, including anything you decided along
  the way that the task did not specify.
- **The review artifact** from the independent reviewer.
- **Anything that went wrong and how it was resolved** — a failed approach
  abandoned midway is exactly the kind of thing that is invisible in a squashed
  commit and valuable later.

Then clean up locally as in the default flow.
