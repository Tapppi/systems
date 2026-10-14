# Repository conventions

## Ownership and documentation

Public modules define reusable behavior and options. Consumer flakes supply actual identities, access grants,
storage bindings, topology and service placement. Keep examples synthetic and evaluable without private inputs.
General usage belongs in README or `docs/`; module-specific constraints belong beside the module. AGENTS.md
links those sources and adds only agent workflow rules. Explain unusual composition and compatibility constraints
where they are needed for safe edits. Put real hardware and instance rationale in the private consumer, retaining
enough composing commentary in both the public example and private host to explain their shared requirements.

## Style

Follow [EditorConfig](../.editorconfig): UTF-8, LF, final newline, two-space indentation and a 120-column limit.
Python uses four spaces. Use nixfmt for Nix, StyLua with [stylua.toml](../stylua.toml) for Lua, and
markdownlint-cli2 for Markdown. Do not create backup copies of edited files; Git preserves their history.

Prefer explicit `pkgs.<package>` references and use `with pkgs;` sparingly and consistently. Use descriptive
names, group related packages, and declare reusable options with `lib.mkOption` and appropriate types.
Comments explain non-obvious constraints rather than restating the expression.

Bootstrap and activation wrappers can run against stock macOS BSD tools. Support both BSD and GNU userlands:
for an in-place sed edit use `sed -i.bak` and remove the temporary backup after success. Review assumptions
around `readlink -f`, `date`, `stat`, `sort`, `grep -P` and `find -printf`.
Only code whose target configuration guarantees GNU tools first on PATH may rely on GNU-specific behavior.

## Module and package changes

Trace the import graph before editing: an existing file is not necessarily part of an exported profile.
Wire a new module into the intended composition and, when it is public API, the appropriate flake export;
exercise it through a synthetic example. Keep Darwin, NixOS and Home Manager option namespaces separate.

Persistent packages belong in the module or consumer that owns their purpose. Generic capabilities belong in
public modules; personal application selection belongs in a consumer. Configure programs and services through
their module options. Package-list files are functions returning lists, not modules. A `home.packages` list
does not install system services; `environment.systemPackages` does not configure a Home Manager program.
The active [Darwin workstation](../modules/darwin/README.md) has deliberately narrow Home Manager ownership;
its child modules must not redefine composition-wide identity, state version or shared wiring.

Keep the main nixpkgs and fresh-tool pins separate, with consumers following the corresponding input tracks.
Follow the Home Manager input's nixpkgs pin to avoid a second incompatible package set. Read the relevant
state-version option before changing it; a dependency refresh alone does not justify a state-version change.
The [overlay guide](../overlays/README.md) describes where overlays apply and the kernel-cache exception.

Use `nix shell nixpkgs#<package>` for temporary tools. `nix profile install` creates imperative state outside
the flake and is not the persistence mechanism for a managed machine. A module edit does not authorize moving
packages, runtimes, Homebrew or application configuration between existing owners.

Never commit credentials or bake them into derivations. A private consumer's source and generated configuration
can enter its closure, so publish to a public cache only outputs evaluated from the public flake.
