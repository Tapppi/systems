# Agent guide — systems

Read [README](README.md) for interfaces and documentation, then the relevant module guide.
[Development](docs/development.md), [conventions](docs/conventions.md) and
[deployment ownership](docs/deploys.md) are the canonical instructions for all contributors.
Load references as needed; read [flakes/nvim/AGENTS.md](flakes/nvim/AGENTS.md) before editor changes
and [Hammerspoon](modules/darwin/hammerspoon/README.md) before changing its configuration.

- Work in a worktree under `.claude/worktrees/` on an `agent/<topic>` branch based on local HEAD.
  Never edit the main checkout: a consumer may activate its current files, and out-of-store Lua can be live.
  A helper needing isolation branches from the current worktree, not the main checkout.
- Load `ikeh-git:git-workflows` before commits, pushes, merges, PRs or deployment; default to PR with user review.
  Preserve other sessions' changes and stage/commit only owned paths explicitly.
- Follow the development checks before publication. Build checks and guest activation tests are distinct evidence.
- Real-host activation requires explicit authorization; Darwin activation and rollback on the real workstation
  are owner steps. Activation inside an isolated test VM is authorized; follow the guest boundary in
  [deployment ownership](docs/deploys.md). Never bypass a guard that cannot distinguish that guest.
- No package/runtime/Brew ownership change or Nix-distribution transition is implicit in a module edit.
  Never change live builder configuration or cache trust merely to make a test pass.

## Enforcement

[`.claude/settings.json`](.claude/settings.json), [`.codex/config.toml`](.codex/config.toml),
[`opencode.json`](opencode.json) and [`.pi/settings.json`](.pi/settings.json) enable the git/worktree plugin
for their respective harnesses. The git skill owns the full guard rules and each harness's supported behavior.
The worktree guard forbids whole-tree staging in the main checkout and rebasing main. The repository opts in
for `agent/` branches pushed to origin from a linked worktree; from the main checkout the push guard gives
no verdict and the session's own rules decide. Push only when the selected flow calls for it.
Keep `main` and `master` out of branch names: the ask floor matches those words in push text.
Configured plugin enablement does not install the plugin; these rules apply even when a harness lacks its hooks.

[deploy-guard.sh](.claude/hooks/deploy-guard.sh) conservatively scans command text, including commands inside
SSH or shell wrappers. It denies Darwin activation, rollback and closure activation scripts and legacy starter
activation paths, and asks about NixOS switch/boot/test. It cannot recognize isolated guests. Pure read-only
calls have a narrow exemption; unparseable activation calls ask. A commit message naming an activation command
can also trigger it: pass message text through a file with `git commit -F`.
Run [deploy-guard-test.sh](.claude/hooks/deploy-guard-test.sh) after changing the guard.
