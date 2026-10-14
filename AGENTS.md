# Agent guide — systems

This is the public Nix module library. Read [README](README.md) for exported interfaces and examples.
Real host compositions, fleet identities, topology, disk identifiers and access grants belong in the private
consumer. Keep public modules usable with synthetic inputs and no private repository dependency.

## Working and verification

- Work in a worktree under `.claude/worktrees/` on an `agent/<topic>` branch, based on local HEAD.
- Load `ikeh-git:git-workflows` before committing, publishing or opening a PR; default to PR with user review.
- Other sessions may own changes: stage and commit only your files with explicit paths. Never change the main checkout.
- New files must be staged before Git-flake evaluation can see them.
- Required checks are `nix flake check` and `nix build` for every affected example, host and image. Build never activates.
- Never activate Darwin, run a system closure's activate script, or deploy a host without explicit authorization.
- Keep main and fresh-tool pins separate. No package/runtime/Brew migration or Nix-distribution transition is implicit in a module edit.
- Use nixfmt for Nix, StyLua for Lua and the repository EditorConfig. Preserve portable BSD/GNU behavior in bootstrap scripts.
- Do not add credentials, personal instance bindings or private closure publication to this repository.

The on-demand nix-rosetta-builder configured by the Darwin workstation supports aarch64-linux and
x86_64-linux builds. It starts automatically when needed; a transient platform mismatch during VM recreation
can be retried. Linux outputs require a compatible Linux builder. Firmware/image derivations may require
the builder to advertise the `kvm` system feature; QEMU can fall back to slower software emulation when
KVM acceleration is unavailable. Never change live builder configuration merely to make a test pass.
Capture failed exit codes rather than piping them away.

The Darwin workstation preserves Determinate Nix accommodations and the narrow Home Manager ownership.
The composition owns user identity and stateVersion; child modules may add files without redefining the
host-wide Home Manager settings. Read [Hammerspoon](modules/darwin/hammerspoon/README.md) before editing it:
its Lua is loaded out of the store, so the Lua flake check is essential and main-checkout Lua edits affect a
running app. Do not edit that live checkout during development.

Read [flakes/nvim/AGENTS.md](flakes/nvim/AGENTS.md) before editor changes. `.claude/hooks/deploy-guard.sh`
retains the activation guard; run its fixture test when changing the guard. Existing publication and worktree
hooks remain binding whether or not a harness invokes them.
