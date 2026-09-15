# Hammerspoon

Hammerspoon holds this Mac's window hotkeys, its per-app keyboard-layout forcing, and the link router that picks a
browser *profile* for an opened URL. The app, its configuration, the router, the picker and the hotkeys are all
delivered from here.

Claims asserted sharply below were checked against Chromium and Hammerspoon source at the installed versions, this
machine's TCC database, the pinned nix-darwin revision, or the live machine. Where a claim is hedged, the hedge is the
finding.

## Activation and the default browser

Activation claims `http`/`https` for Hammerspoon so a clicked link reaches the router, and announces each change first,
because macOS raises a confirmation dialog for every real one. It is not reliably silent when nothing needs changing:
the handler probe runs through `hs.ipc`, which the reload just before it rebuilds, and a failed probe reads as an empty
handler.

- **The claim is gated on a Hammerspoon answering with *this* config**, never on the process existing. An instance that
  outlived its `killall` answers `pgrep` while running the old config, and claiming `http` for one with no
  `hs.urlevent.httpCallback` drops every clicked link on the machine.
- **The claim goes through `duti`.** `hs.urlevent.setDefaultHandler` reports success and changes nothing on macOS
  26.6.2.
- **`mailto` is not claimed**: `httpCallback` does not serve it, so taking it would drop every `mailto:` link.

Hammerspoon's `Info.plist` also declares document types, and they move by UTI, not by extension:

- **Left with Hammerspoon** — `html htm shtml` (one `public.html`). The web types *are* the default-browser identity:
  moving one offers to change the browser back. A web file opened into Hammerspoon reaches the picker as `file://`.
- **Claimed** — `xhtml xht xhtm` (one `public.xhtml`), which macOS does not transfer with `http`. The claim raises its
  own dialog the first time and `duti` returns before it is answered. `jhtml` is a dynamic UTI `duti` rejects
  (`error -50`) immediately, which is why the helper checks the exit status before polling.
- **Put back** — `txt text url`. A `.url` is a shortcut file, not web content.

The restore runs on every non-dry-run activation, with or without a live Hammerspoon, from a snapshot taken at the start
of the same run. A dialog answered after activation exits still strands its type: the next run sees Hammerspoon as the
owner and has nothing to restore. That residual is deferred to SYSMI-19, where asserting the full intended associations
removes it.

## Why the app is packaged here

Hammerspoon is not in nixpkgs, so it is packaged from its GitHub release. Nix-installing a GUI app does not break TCC
here, for narrow reasons:

- The Accessibility grant is keyed by **bundle identifier**. Its `csreq` pins `anchor apple generic`, the bundle id and
  Team ID `VQCYSNZB89` — no path, no cdhash — so a store-built bundle satisfies it and upgrades do not re-prompt.
- `system.activationScripts.applications` **rsyncs** bundles into `/Applications/Nix Apps`, so the bundle is a real
  directory at a stable path. That rsync draws from `environment.systemPackages` only; a `home.packages` app would not
  be placed at all on this host.
- **Nothing wraps the executable.** A nix wrapper script in `Contents/MacOS/` hands TCC a store binary — Neovide on this
  machine is exactly that. Hammerspoon's release bundle is copied whole.

Two build settings keep the upstream Developer ID signature valid:

- **`dontFixup = true`** — load-bearing. `Contents/Resources/timeout3` is a sealed shebang script; `patchShebangs`
  would rewrite it and `codesign --verify` would fail with *a sealed resource is missing or invalid*.
- **`stdenvNoCC`** — defence in depth: no strip tooling, no C toolchain in the closure.

Never `codesign -s -` this bundle.

## Where the config lives

`~/.config/hammerspoon`, for XDG convergence and nothing more. It is not beyond `macos-setup`'s reach: `bootstrap.sh`
rsyncs `dotfiles/config/` into `~/.config/` with `--force`, so **no `dotfiles/config/hammerspoon/` may ever exist**.

Hammerspoon relocates through the `MJConfigFile` user default. It names a **file** (`…/init.lua`), is read **once** at
launch (so a change needs a restart, not `hs.reload()`), makes `hs.configdir` its dirname with no trailing slash, and is
undocumented.

```text
~/.config/hammerspoon/          real directory, three independent entries
├── init.lua                    -> /nix/store/…   generated stub, never hand-edited
├── lua/                        -> <repo>/modules/darwin/hammerspoon/lua   out-of-store, live-editable
├── generated/targets.lua       -> /nix/store/…   from local.browsers.targets
└── Spoons/                     created by Hammerspoon at every launch; unmanaged
```

- **The parent must be a real directory.** Hammerspoon's launch-time `mkdir` of `Spoons/` resolves symlinks, so a
  symlinked parent would create `Spoons/` inside the git tree.
- **Nothing named `Spoons` may be anything but a directory.** Hammerspoon `abort()`s at launch otherwise, and only at
  launch — a bad entry lies dormant through every `hs.reload()`.
- **Only `lua/` is out of store**, because it is edited live. That is the exception, not the pattern for dotfiles.

Hammerspoon's `package.path` template `configdir/?.lua` already resolves `require("lua.router")`. The stub also
prepends `configdir/lua/?.lua` and `configdir/lua/?/init.lua` so modules require each other by bare name.

## `~/.hammerspoon` must stay gone

Holding Cmd+Opt at launch, or any prefs reset, removes `MJConfigFile`, and Hammerspoon then silently loads
`~/.hammerspoon/init.lua`. That directory and its `dotfiles` source are both gone, so the fallback fails visibly.
Recreating either — including through a `setup.sh` run — restores the silent failure.

## The init.lua stub

Generated, checked with `pkgs.lua5_4`'s `luac -p` (`pkgs.lua` is 5.2; Hammerspoon embeds 5.4.7), and executed by the
test suite. Before loading anything that can fail it:

1. registers `hs.urlevent.httpCallback`;
2. `require("hs.ipc")`, so `hs -c` can reach the instance — activation calls the package's `hs` by store path;
3. notifies loudly if `hs.configdir` differs from what nix configured;
4. prepends `lua/` to `package.path`;
5. starts the reload watcher, held in a global, since `hs.pathwatcher` keeps no registry.

Only then is the hand-written config loaded, inside a `pcall`.

**The callback comes first because a missing one drops links.** With no `httpCallback`, Hammerspoon logs and discards
the event; once it is the default handler every clicked link goes nowhere, with no loop and no fallback. The callback
itself wraps dispatch in `pcall` and falls back to `hs.urlevent.openURLWithBundle` with **Safari hard-coded** — the one
bundle every Mac has. A router failure therefore lands a link in Safari's last-used profile: recoverable, where a
dropped link is not.

**The final `require` must be the dotted `lua.init`.** A bare `require("init")` resolves through `<configdir>/?.lua`
back to the stub itself, and because Hammerspoon loads `init.lua` with `loadfile`, Lua's loop guard never arms: it
recurses until the C stack overflows, and the `pcall` reports success — no hotkeys, no error.

## Hotkeys

Every hyper hotkey — the apps in `lua/init.lua` and one per browser target — goes through `whu.toggle`. What differs is
passed in: which windows the hotkey owns and how it opens one. A press:

- **puts away** a focused window that is the hotkey's own: hides the app, or minimizes just that window when another of
  the app's standard windows is showing (another browser profile's). A full-screen window always hides. An app hotkey
  also hides its app when the app is frontmost with a dialog, panel or Finder's desktop focused;
- **raises** otherwise: unhides, unminimizes, applies the layout, focuses;
- **goes to a full-screen window's Space** when the hotkey has no window on this one (see below);
- **launches** when there is nothing, and positions the new window after 1.5s with a held timer that the next press
  cancels. `watchCreate` hotkeys (Ghostty) position every new window through a filter matched by bundle id —
  `nameForBundleID` is not `app:name()` for Chrome or Brave.

**A hotkey never switches the keyboard layout at press time.** It records the layout it wants, and the `windowFocused`
handler applies it when that app's window takes focus. Set at press, the layout changed under the app still being typed
in and landed before the handler, which then recorded the forced layout as the one to return to.

The filter drops events for windows it does not yet consider visible, so a held check looks every second for a request
still pending once its app has focus, until the request expires after 10s; the policy is safe to run twice for one
focus. Apps in `forceUSApps` get US and the previous layout is restored on leaving them. The retry that works around
macOS dropping the first switch is held and replaced, never left armed.

**The focus filter is `hs.window.filter.new(nil)`**, a copy of the default: `visible = true` plus 30 named rejects,
including Spotlight and Notification Center, which is what keeps them from restoring the layout mid-session. None of
the hotkey apps is on that list. `new(true)` would have no rules at all.

**Full-screen windows are invisible from every other Space.** `app:allWindows()` omits them and `hs.window.get(id)`
returns nil, while `hs.spaces.windowsForSpace` still lists the id (measured). Two consequences are handled:

- pressed from inside a full-screen app, `focusedWindow()` still sees the window, so it counts as the hotkey's own;
- pressed from elsewhere, when a `fullscreen` Space other than the visible one exists, the window server's full list
  (read through JXA, ~90ms) gives each document window's owner pid — layer 0, not transparent, at least 200×200, since
  a Space's list also carries tooltips and ordered-out leftovers. The app is unhidden and its Space gone to with
  `hs.spaces.gotoSpace`, which drives Mission Control and blocks while it does; presses within 1.5s of it do nothing,
  and a failed `gotoSpace` launches instead. A browser profile sharing its process with another profile never does
  this, because the pid cannot say which profile the window is; it launches.

Ordinary Spaces are not a problem: `allWindows()` returns windows on an unfocused Space on this macOS (measured).

## Browser profiles

**Hammerspoon owns routing, the picker and the hotkeys** — it is needed for the hotkeys anyway, and a separate router
would split one target list across two processes. **Finicky is deferred**, together with URL rewriting, source-app rules,
unshortening and domain matching: all need client-identifying data that belongs in the private `kone` repo, not here.

`local.browsers.targets` — `{ key, label, bundle, profileDir }` — generates both the picker rows and the hotkeys. It
stores the on-disk profile **directory**; display names are read from the browser's `Local State` at runtime, which is
what keeps client names out of this public repo.

**Launching is `open -n -a <browser> --args --profile-directory=<dir> <url>`**, argv via `hs.task`. `-n` is mandatory:
`--args` only applies to a new instance, and without it a running browser receives neither the profile nor the URL.
Chromium's process singleton forwards the whole argv to the running instance, which is what makes this work. A target
with no `profileDir` gets no `-n` and no `--args` — `open` would hand the URL over as argv, which only Chromium reads —
unless it is a Chromium target opening a private window, which needs `--incognito` passed that way.

### Finding a profile's windows

`hs.window` reads the **accessible** title, which Chromium ends with `GetAvatarNameForProfile()` — for a signed-in
profile `<GAIA given name> (<local name>)`. The local name is `info_cache`'s `enterprise_label` when a policy set one,
otherwise `name`. A window is matched on its tail against `<gaia> (<local>)`, `<gaia>` and `<local>`, longest match
across all profiles, with a non-alphanumeric boundary — never a substring, since `" - "` occurs in page titles and the
separator is localized.

**A miss means "not identified", and an unidentified window is not claimed** — provided the profile list was readable:

- `Local State` paths are known for Chrome, Brave, Edge and Vivaldi. For any other bundle every window is claimed, and a
  `profileDir` on such a bundle fails the build; the assertion reads the list out of `browsers.lua`.
- A browser that knows **one** profile appends no name at all, so all its windows are that profile's.
- A browser that knows several names every window, so a bare title is **unknown**. That covers automation copies of
  Chrome (`chrome-devtools-mcp`, own `--user-data-dir`, same bundle id) — which is also why lookup iterates
  `applicationsForBundleID` rather than `application.get`.
- Private and Guest windows end `(Incognito)`, `(Private)` or `(Guest)` instead, so in a browser that knows several
  profiles they belong to none: with only a private window open, the profile's hotkey opens an ordinary one. A browser
  that knows one profile (Brave, today) claims its private windows too, so its hotkey toggles them.

Only `isStandard()` windows count: Chromium's companion status-bar windows have no readable id (1.1.1 reports 0, which
never matches) and never minimize.

## The picker

**`hs.hotkey.modal`, not `hs.chooser`.** A chooser is a query field, so it cannot commit on one keypress, and it takes
focus away from the application the link was clicked in. A modal binds real hotkeys while that app keeps focus.

The cost is that an entered modal swallows its keys machine-wide, so every path out exits it, a countdown guarantees an
exit, and the alert always outlives the countdown so the keyboard is never held with nothing on screen.

- **Links clicked while it is up join a queue**; one choice opens them all.
- **Each link restarts the 15s countdown**, and a 60s ceiling armed once per picker bounds how long a stream of links
  can hold the keyboard.
- **Running out of time routes to the first target** rather than dropping the links.
- **Shift with a key opens them in a private window** of that profile (`--incognito`), bound only for the Chromium
  family. A policy that disables Incognito makes Chromium open an ordinary window.

A modal does capture plain letters while another app is frontmost — measured by posting at `kCGHIDEventTap`.
`hs.eventtap.keyStroke` bypasses Carbon hotkey dispatch, so a test built on it proves nothing.

## Testing

`nix flake check` is the only thing that runs this Lua: it is symlinked out of the store, so no build loads it. The
check parses every file with Lua 5.4, holds it to `stylua.toml`, and runs it against a recording stub `hs`.

- **The generated stub is executed, not just parsed.** It lives in `stub.nix` so the check can build it with test
  values; `tests/fixtures/hs/` supplies the `hs.ipc` it requires.
- **Its `cfgDir` is substituted with a path inside the build directory.** The flake builds unsandboxed, and the stub
  prepends `<cfgDir>/lua` ahead of everything, so a fixed `/tmp` path would let any local process shadow the modules.

Real key capture, the window server, Spaces and LaunchServices can only be exercised on the machine. Probe the live
instance **serially** — `hs -a -t <s> -c …`, stdin from `/dev/null`, never `-C` — since concurrent probes have crashed
it.

## `hs.ipc` is a privilege surface

`require("hs.ipc")` opens an unauthenticated Mach port, so any process running as this user — coding agents included —
can run Lua inside Hammerspoon with its Accessibility grant. Accepted: activation needs it to reload the config, and
anything running as this user can drive the GUI by other means.

## Reloading and `luaDir`

The watcher points at `<cfgdir>/lua`, never `<cfgdir>`: `hs.pathwatcher` resolves symlinks first, so only the former
follows into the repo.

Activation does nothing under `--dry-run`, read from the parent's argv. `darwin-rebuild` still runs the activation
script for a dry run, and `DRY_RUN` cannot be set because `activate` runs under `env -i`.

Otherwise it restarts when `hs.configdir` does not match the configured path and reloads when it does. **A failed probe
counts as a mismatch**: on the first switch the running instance never loaded `hs.ipc`, so the probe cannot answer on
exactly the run that must restart. That one verdict gates the reload and the handler claim. The restart re-asserts
`MJConfigFile` after the kill, since a terminating app can flush a stale cached value back.

**`luaDir` defaults to the main checkout, so git operations there are deploys.** Any `*.lua` write reloads the running
config — a `checkout`, `stash` or rebase included — and checking out a tree without the module leaves the hotkeys gone
until a manual reload. Worktree edits do not reload. Activating an unmerged branch needs `local.hammerspoon.luaDir`
overridden; activation checks the directory exists and otherwise leaves the running instance alone, since nix cannot
see a missing out-of-store target.
