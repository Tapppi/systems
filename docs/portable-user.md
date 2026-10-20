# Portable user packages and Herdr

The plain helpers take caller-owned package sets. They fetch no inputs and require neither Home Manager nor devenv.

```nix
systems.lib.userPackages { inherit pkgs; }
systems.lib.harnessPackages { inherit pkgsFresh; names = [ "claude-code" "pi-coding-agent" ]; }
systems.lib.mkHerdrWin { inherit pkgs; herdr = pkgsFresh.herdr; }
```

`userPackages` selects ripgrep, fd, fzf, jq, Go yq (`yq-go`), uv and Node 24 LTS (`nodejs_24`) from `pkgs`.
It does not install a global Python interpreter. `harnessPackages` selects exactly the requested names from
`pkgsFresh`: `claude-code`, `codex`, `pi-coding-agent`, `opencode`, `herdr`, `devenv`. Unknown names fail with
an error. An empty list selects nothing; Claude-only consumers do not receive Codex or Pi.
The consumer decides where these packages belong and resolves existing executable ownership before enabling them.

## Home Manager composition

Declare and lock `systems`, `nixpkgs`, `nixpkgs-fresh` and `home-manager` in the consuming flake.
Home Manager should follow the consumer's base `nixpkgs`. These inputs may follow the corresponding systems
inputs, or use their own explicit pins. Pass the selected fresh set through `extraSpecialArgs`:

```nix
home-manager.lib.homeManagerConfiguration {
  pkgs = nixpkgs.legacyPackages.${system};
  extraSpecialArgs.pkgsFresh = import nixpkgs-fresh {
    inherit system;
    config.allowUnfreePredicate = p: nixpkgs.lib.getName p == "claude-code";
  };
  modules = [
    systems.homeManagerModules.portableUser
    systems.homeManagerModules.herdr
    {
      home.username = "example";
      home.homeDirectory = "/home/example"; # /Users/example on Darwin
      home.stateVersion = "26.05"; # retain the consumer's existing value
      programs.systems-portable-user = {
        base.enable = true;
        harnesses = [ "claude-code" "pi-coding-agent" ];
      };
      programs.systems-herdr.enable = true;
    }
  ];
}
```

The base is disabled and harness selection empty by default. Herdr is separately disabled by default.
Importing the disabled modules does not require `pkgsFresh`. The consumer owns identity, state version,
activation and existing-file collision/backup policy. Claude Code is unfree; only consumers selecting it need
the explicit allowance above. The helpers do not change nixpkgs policy.

The Herdr adapter installs `pkgsFresh.herdr` and `herdr-win`, and manages only
`xdg.configFile."herdr/config.toml"`. Its directory remains writable for manifests and other runtime state;
cache and state directories remain tool-owned. `programs.systems-herdr.package` overrides the package and
`programs.systems-herdr.settings` recursively extends common settings. The common settings disable onboarding
and binary update checks, retain manifest updates, and enable symbolic agent status and pane labels.
Herdr must be at least 0.8.2 for symbolic status support.

Home Manager supplies no platform notification policy. Consumers may set
`programs.systems-herdr.settings.ui.toast.delivery` explicitly. The Darwin workstation adapter selects
`"system"` notifications and retains its root/staff activation link. Do not enable both adapters for the same
user's config file. Herdr respects `XDG_CONFIG_HOME`; `HERDR_CONFIG_PATH` can explicitly override config loading.

`herdr-win` uses the current tmux session name, or `HERDR_SESSION` with a `default` fallback outside tmux.
It accepts one optional SSH target and keeps the client local. tmux must be on PATH when `TMUX` is set.
After detach, `q` or EOF closes the wrapper; another key reattaches. Use matching client/server Herdr versions
on both endpoints. Package selection alone does not prove an SSH connection or interactive terminal session.

## Updates and writable state

Update only the fast-tool input with `nix flake update nixpkgs-fresh`, review the lock diff, then build and
activate through the consumer's procedure. Following consumers update the reviewed systems release input;
an independently pinned consumer updates its own fast-tool input. Keep base and project locks unchanged.
Node's explicit major is updated separately through package data. This API does not implement a release-age policy.

Store binaries update through their Nix input. The pinned Claude package disables its binary updater while
allowing tool-owned plugin updates; OpenCode disables its binary updater; Pi supplies version-check defaults.
Herdr common settings disable binary version checks and leave manifest refresh enabled. Codex's system defaults
remain in its Darwin module. Selecting a package alone does not transfer other harness configuration or setup.
Keep authentication, plugins, extensions and runtime state in supported writable tool-owned locations.

## Independent consumer test

The [fixture](../tests/fixtures/portable-consumer/flake.nix) declares independent base/fresh/HM inputs and exercises
Claude-plus-Pi and Claude-only compositions on Apple Silicon Darwin and both Linux architectures. From this checkout:

```sh
python3 tests/fixtures/portable-consumer/run.py --systems . \
  --output /tmp/portable-consumer-check --build-system aarch64-darwin
```

Choose a new external output directory and keep the candidate checkout unchanged while this runs. The runner
bootstraps its own lock from the candidate's pinned input revisions, evaluates all three platforms, optionally
builds specified platforms, and verifies missing fresh-input rejection and no-write lock integrity. It retains
commands, exit codes, elapsed time, logs and lock hashes in that directory. Linux builds need a compatible builder.
The template's systems URL is a bootstrap source; the runner overrides it with the candidate. Its disposable lock
is development evidence, not a published release pin. A release consumer pins a reviewed immutable systems revision.
The fixture establishes plain Nix/HM composition; it does not establish a remote-directory devenv import contract.

The public `portable-user` check also verifies provenance, opt-in selection, TOML semantics, writable sibling state
and wrapper arguments. A disposable headless-server probe verifies local client/server version and protocol
compatibility using private Unix sockets and an empty environment; that probe disables manifest networking.
It does not exercise SSH or interactive TUI attachment. Evaluating an activation derivation does not activate a home or prove guest boot/rollback.
