# Hammerspoon

Hammerspoon holds this Mac's window hotkeys, its per-app keyboard-layout forcing, and the link router that picks a
browser *profile* for an opened URL.

## Status

Hammerspoon, its configuration, the link router, the picker and the hotkeys are all delivered from here. Activation
claims the `http`/`https` handler, so a clicked link reaches the router.

Activation calls out before each change it makes, because macOS raises a confirmation dialog on every real change. It
is not reliably silent when everything already holds: the handler probe runs through `hs.ipc`, which the reload just
before it tears down and rebuilds, and a failed probe reads as an empty handler — so a run can announce a claim it does
not need and then wait out a prompt that never comes.

**The claim is gated on a Hammerspoon that answers with *this* config**, never on the process merely existing. An
instance that outlived its `killall` still answers `pgrep` while running the old config, and claiming `http` for one
that never registered `hs.urlevent.httpCallback` drops every clicked link on the machine with no fallback — strictly
worse than not claiming at all.

**The claim goes through `duti`, not `hs.urlevent.setDefaultHandler`** — the latter reports success and leaves the
handler unchanged on macOS 26.6.2.

Hammerspoon's `Info.plist` declares `html htm shtml jhtml`, `txt text`, `url`, `xhtml xht xhtm`, `spoon` and `*` as
document types, all Viewer, and `hammerspoon`, `http`, `https` and `mailto` as URL schemes. Only `http`/`https` are
claimed; `mailto` is left alone deliberately, since `hs.urlevent.httpCallback` does not serve it and taking it would
drop every `mailto:` link with no fallback.

Extensions are the wrong unit for the document types — UTIs are, and they collapse. `html htm shtml` are one
`public.html`, which is why taking `http` transfers all three together; `xhtml xht xhtm` are one `public.xhtml`;
`jhtml` is a *dynamic* UTI. `spoon` was always Hammerspoon's, and `*` claims nothing that resolves — `pdf`, `png`,
`md` and `json` all still land elsewhere. That leaves three groups and three treatments:

- **Left with Hammerspoon** — `html`, `htm`, `shtml`. On macOS the web types **are** the default-browser identity, so
  moving one asks to change the browser back and accepting that would undo the claim. They need no undoing anyway: a
  web file opened into Hammerspoon arrives as a `file://` URL and reaches the picker.
- **Claimed outright** — the `public.xhtml` family, via `.xhtml`. Wanted for the same reason as `html`, but macOS
  never transfers it: it sat with Chrome. One claim moves `xhtml`, `xht` and `xhtm` together. It is a new default
  rather than a hand-back, so it raises its own confirmation dialog the first time, and the claim is asynchronous —
  `duti` returns before the dialog is answered.
  `jhtml` is **not** claimed. Its dynamic UTI is one `duti` rejects outright (`error -50`), so listing it would
  re-attempt an impossible claim on every activation. A rejection returns immediately rather than waiting the claim
  out — that distinction is why the claim helper checks `duti`'s exit status before it starts polling.
- **Put back** — `txt`, `text`, `url`. A `.url` is a shortcut file rather than web content — the picker hands the
  browser the file instead of following the link inside it — and `txt`/`text` are not web content at all.

The restore runs on every activation that is not a dry run — including ones where Hammerspoon is not running, or is
running some other config. It reads and writes LaunchServices through `duti` and needs no live instance, and the
runs where a type is most likely still stranded are exactly the ones where the claim is skipped. It restores from a
snapshot taken at the start of the same run, so each claim is waited out before it runs; a prompt answered after
activation has finished is still not repaired, since the next run sees the type already Hammerspoon's and has nothing
to put it back to.

**Known defects, deliberately left.** The input source is set synchronously right after `win:focus()`, so the async
`windowFocused` handler never records the previous layout; the layout is also set immediately after
`launchOrFocusByBundleID`, changing the keyboard under the app still holding focus; the 0.05s retry timer in
`setInputSource` is unreferenced, so it is both collectable and un-cancellable; `win:setFrame()` runs before
`app:unhide()` in `bindToggle`, with unverified effect on a hidden window; and `CustomUserPreferences` is write-only,
so removing this module leaves `MJConfigFile` pointing at a file home-manager has deleted. All tracked in SYSMI-63.

**One open question in code that shipped.** The focus filter's constructor has two candidates that fail in opposite
directions: `hs.window.filter.new(nil)` copies the default filter, which never fires for `ignoreInDefaultFilter` apps
or non-standard window roles, so focusing one can leave the keyboard stuck in the forced US layout; `new(true)` drops
the default entirely, including its `visible=true` rule, so Spotlight and Notification Center begin firing
`windowFocused` and restore Finnish mid-session. `new(nil)` ships. Neither symptom has been observed, which is what
makes it a question rather than a bug.

**A modal does capture plain letters while another application is frontmost** — measured, with Brave frontmost and
Hammerspoon not. Worth recording because the obvious instrument lies: `hs.eventtap.keyStroke` reaches event taps but
bypasses Carbon hotkey dispatch, so a posted key proves nothing. Post at `kCGHIDEventTap` instead. That the modal also
*swallows* the key is standard `RegisterEventHotKey` behaviour and was not separately measured.

Every non-obvious claim below was verified against primary sources — Chromium and Hammerspoon source at the exact
installed versions, this machine's TCC database, and the pinned nix-darwin revision. Where something is asserted
sharply, it is because it was checked; where it is hedged, the hedge is the finding.

## Why the app is packaged here rather than left to Homebrew

Hammerspoon is not in nixpkgs, so it is packaged from its GitHub release. When Homebrew installation migrates to
`systems`, the packaging and installation mechanism should be re-evaluated.

The usual objection is that nix-installing a macOS GUI app breaks TCC, and Hammerspoon is useless without
Accessibility. It does not apply to this package, for reasons narrower than "nix is fine now":

- The Accessibility grant is keyed by **bundle identifier**, not path — `client_type=0`, and the `access` table has no
  path column. Its `csreq` blob pins `anchor apple generic`, the bundle id and Team ID `VQCYSNZB89`, with no path and
  no cdhash, so a store-built bundle satisfies it and a version bump does not re-prompt.
- `system.activationScripts.applications` **rsyncs** bundles into `/Applications/Nix Apps` rather than symlinking the
  folder into the store, so the installed bundle is a real directory at a stable path.

**The bundle must come from `environment.systemPackages`, not `home.packages`.** That rsync draws from system packages
only. home-manager's own darwin app placement would not help: `copyApps` is disabled on this host and `linkApps`
defaults off at this `stateVersion`, so a `home.packages` app would be placed by neither mechanism and simply would
not appear. Config through home-manager, bundle through `environment.systemPackages`.

**The packaging is what makes this TCC-safe, not the activation mechanism.** `--copy-unsafe-links` dereferences the
store symlink for the *bundle*, but a nix wrapper script inside `Contents/MacOS/` is copied with its store paths
intact and `exec`s a store binary, which is what TCC then evaluates. Neovide on this machine is exactly that — a real
rsynced directory whose executable is a 240-byte script running an ad-hoc-signed store binary, with the bundle
reporting "not signed at all". Hammerspoon is safe because the release bundle is copied whole and nothing wraps it.

Two build settings preserve the upstream Developer ID signature:

- **`dontFixup = true`** — load-bearing. `Contents/Resources/timeout3` is the bundle's only shebang script and it is
  sealed: `CodeResources` covers it under `^Resources/` with no `omit` and no `optional`. `patchShebangs` would repoint
  it at a store bash and invalidate that seal, after which `codesign --verify` fails with *a sealed resource is missing
  or invalid*. Note what this does and does not break: resource hashes live in `CodeResources`, and the CodeDirectory
  seals that plist, so the signature and the designated requirement survive — it is verification that fails.
- **`stdenvNoCC`** — defence in depth. nixpkgs' `strip.sh` defaults `stripDebugList` to include `Applications`, but
  `_doStrip` is reached only through `fixupPhase`, which `dontFixup` already skips. This adds an independent guard (no
  bintools wrapper, so `$STRIP` is unset) and keeps a C toolchain out of the closure.

Never `codesign -s -` this bundle.

## Why the config lives in `~/.config/hammerspoon`

XDG convergence — that is the whole of the reason, and it is sufficient.

It does **not** put the config beyond `macos-setup`'s reach: `bootstrap.sh` rsyncs `dotfiles/config/` into
`~/.config/` with `--force`. `~/.config/hammerspoon` survives only because no `dotfiles/config/hammerspoon/` source
exists. Treat that as a standing constraint — creating one would let `--force` replace the nix-managed entries
silently.

Hammerspoon relocates via the `MJConfigFile` user default, which is the only supported mechanism — symlinking
`~/.hammerspoon` is the shape with the open, undiagnosed bug (upstream #3706) and does not vacate the dotfile slot
anyway.

Four properties of that default govern the layout:

- **It names a file, not a directory.** The value must end in `/init.lua`. Pointing it at the directory moves
  `hs.configdir` up to `~/.config`.
- **It is read once**, in `applicationDidFinishLaunching:`. A changed value needs a restart; `hs.reload()` uses the
  cached C global and will not see it.
- **`hs.configdir` is the dirname, with no trailing slash.** Every concatenation needs an explicit `/`. The published
  docs are wrong about this.
- **It is undocumented, and a prefs-domain reset wipes it.** See "`~/.hammerspoon` must stay gone".

## Layout

```text
~/.config/hammerspoon/          real directory, three independent entries
├── init.lua                    -> /nix/store/…   generated stub, never hand-edited
├── lua/                        -> <repo>/modules/darwin/hammerspoon/lua   out-of-store, live-editable
├── generated/targets.lua       -> /nix/store/…   from local.browsers.targets
└── Spoons/                     created by Hammerspoon at every launch; unmanaged, harmless
```

**The parent must be a real directory, not one store symlink.** Two reasons, and only the second is fatal: the three
entries have three independent targets that a single `source =` cannot express, and Hammerspoon's launch-time Spoons
`mkdir` uses the *symlink-resolved* path — so if the parent were itself the out-of-store symlink, Hammerspoon would
create `Spoons/` inside the git working tree.

**Nothing named `Spoons` may be anything but a directory.** At launch, and only at launch, Hammerspoon probes that path
with `fileExistsAtPath:isDirectory:` (which follows symlinks) and `abort()`s if it exists and is not a directory. A
symlink *to* a directory passes. A dangling symlink escapes the check but silently defeats the `mkdir` that follows,
since the error is discarded. `hs.reload()` repeats none of this, so a bad entry introduced by activation lies dormant
until the next start rather than failing where it was created.

Only `lua/` is out of store, and only because it is edited live. That is a deliberate exception, not the pattern to
copy: for most dotfiles, store-managed content *is* the point of the migration, and reaching for `mkOutOfStoreSymlink`
by default would hollow it out.

### On `package.path`

`setup.lua` builds `package.path` from nine unconditional entries: the three `configdir` templates (`?.lua`,
`?/init.lua`, `Spoons/?.spoon/init.lua`), the interpreter's existing path, two for the bundle's own `extensions`, and
three under `~/.local/share/hammerspoon/site` — a genuine user-owned module root added upstream in 2022 for this exact
problem. We do not use it: it sits outside the repo, so nothing in git would describe its contents.

`configdir/?.lua` is a *template*, and Lua rewrites dots in a module name to `/`, so **`lua/` already works with no
change**: `require("lua.router")` resolves to `configdir/lua/router.lua`. What `lua/` is not is a path *root* — a bare
`require("router")` will not find it. The stub prepends both `configdir/lua/?.lua` and `configdir/lua/?/init.lua`, so
the modules can require each other by bare name and a module can be a directory; that is readability, not a
precondition.

## The init.lua stub

Generated, and syntax-checked at build time with **`pkgs.lua5_4`'s `luac -p`** — not `pkgs.lua`, which is still
5.2.4 in the pinned nixpkgs, while Hammerspoon embeds Lua 5.4.7. A 5.2 gate would reject valid 5.3+ syntax (`//`,
bitwise operators, `<const>`) and accept 5.2-isms Hammerspoon rejects, which matters because this gate is the only
thing standing between a generated file and the dead-end failure described below. It does five things before loading
anything that can fail:

1. Registers `hs.urlevent.httpCallback`.
2. `require("hs.ipc")`, without which `hs -c` cannot reach the running instance. Loading it only opens the port — it
   does not supply the client, which the package exports as `hs` in `$out/bin`. Activation calls that store path
   directly rather than resolving `hs` on `PATH`, which is what makes it independent of what else is installed.
3. Asserts `hs.configdir` matches what nix configured, loudly. Hammerspoon shipped a symlink-resolution regression in
   0.9.79 that broke sibling `require()`, reverted in 0.9.81, with no regression test guarding it since.
4. Prepends `configdir/lua/?.lua` and `configdir/lua/?/init.lua` to `package.path`, so modules can require each other
   by bare name.
5. Starts the config-reload watcher, held in a global — `hs.pathwatcher` keeps no internal registry, so a watcher
   referenced only by a local is collected and hot reload stops silently.

Only the hand-edited config is then loaded, and only that load is wrapped in `pcall`. Steps 1-5 are deliberately
outside it: they are the parts that must survive a broken module, so anything that could throw belongs after them,
not before.

**The final `require` must use the dotted `lua.init`.** A bare `require("init")` resolves through Hammerspoon's own
`<configdir>/?.lua` template back to *the stub itself* whenever `lua/init.lua` is missing — and because Hammerspoon
loads `init.lua` with `loadfile` rather than `require`, `package.loaded` never arms Lua's loop guard. It re-enters
until the C stack overflows, and the enclosing `pcall` then reports that as success: no hotkeys, no error, and one
live path watcher per level. `lua.init` maps to `lua/init.lua` and cannot collide with the stub. This is reachable
through the `luaDir` override below, so it is not hypothetical.

**Why the callback is registered first.** With no `httpCallback`, Hammerspoon does not forward the URL anywhere — it
logs `no http callback has been set` and **drops the event**. A syntax error is worse: nothing in `init.lua` runs, so
`hs.urlevent` is never required and the drop happens a layer earlier still, in the ObjC handler. Either way, once
Hammerspoon is the default handler, every clicked link on the machine silently goes nowhere. It is a dead end rather
than a loop — no spin, but no fallback to recover through either. Keeping the stub generated and `luac -p`-gated stops
a broken file reaching the machine; keeping the hand-edited modules behind a `pcall` means a typo while iterating
degrades to "links open in the fallback browser, console shows the error".

That degradation is a **requirement on the stub, not an emergent property of the `pcall` at load time**. The load-time
`pcall` cannot help a callback that dispatches into a module which failed to load — the error would simply be raised
per click and the link dropped anyway. So the registered callback must itself wrap its dispatch in `pcall` and carry a
hard-coded `hs.urlevent.openURLWithBundle` fallback that depends on nothing outside the stub.

## Profile targeting

Two decisions settle why this lives here rather than in a dedicated router.

**Hammerspoon owns routing, the picker and the hotkeys.** It is required for the hotkeys regardless, so putting the
router elsewhere would split one feature across two processes, two config languages and two permission surfaces, with
the target list defined twice and free to drift.

**Finicky is deferred as a unit with the rules that would justify it.** Its one irreplaceable feature is short-link
unshortening — no Hammerspoon API returns a post-redirect URL — but that only pays off once domain rules exist to
match against, and those rules are the client-specific part. Adopting it before then buys no routing decisions while
adding a daemon whose broken-config behaviour is to route every link to hardcoded Safari.

Four things wait for the private `kone` repo together: URL rewriting, source-application rules, unshortening, and any
domain matching. Each needs client-identifying data that must not enter a public repo — the same reason the target
list stores on-disk profile *directories* rather than display names.

`local.browsers.targets` is the single source of truth: `{ key, label, bundle, profileDir }`, generating both the picker
rows and the hyper hotkeys so the two cannot drift.

It stores the on-disk **directory** (`Profile 1`), never the display name. Display names are read from the browser's
`Local State` at runtime. This is what keeps a client's company name out of a public repo.

Launching is `open -n -a <browser> --args --profile-directory=<dir> <url>`, via `hs.task`'s argv form so no shell
quoting is involved. **Always pass `-n`.** `--args` maps to `NSWorkspace.OpenConfiguration.arguments`, documented as
"only applies when a new application instance is created", and `-n` is what sets `createsNewApplicationInstance`.
Without it LaunchServices reuses the running process, argv is fixed at exec time, and both the switches and the URL are
dropped — nothing opens at all. It only matters when the browser is already running, which makes the failure look
intermittent rather than absolute.

### Finding an existing profile window

Chromium leaves the macOS NSWindow title as the plain page title — that is what the Window menu shows — but overrides
the **accessible** title in `BrowserView::GetAccessibleWindowTitleForChannelAndProfile`, appending the browser name and
then the profile's display name. `hs.window` is AX-backed, so `win:title()` sees the longer form.

That trailing name is `profiles::GetAvatarNameForProfile()` → `ProfileAttributesEntry::GetName()`, **not** the
`Local State` `name` field this config reads. For a signed-in profile it is `<GAIA given name> (<Local State name>)`, so
the title ends in `)` and a plain suffix test against the Local State name matches nothing — verified against this
machine's live Chrome windows, where it was false for all three profiles. Match the tail against all **three** forms
— `<name>`, `<gaia>` and `<gaia> (<name>)`, since a signed-in profile still carrying Chrome's default local name shows
the GAIA name alone. Never a bare suffix and never an unanchored substring: `" - "` also occurs inside the page
title, and the separator is localized (en dash in de/fr/fi, `$1 ($2)` in ru, `$1: $2` in pt-BR).

**A tail miss means "not identified", and an unidentified window is not claimed — as long as the profile list could be
read at all.** That qualifier is load-bearing. Profile names are read from `Local State`, and this config only knows
where to find that file for Chrome, Brave, Edge and Vivaldi; for any other bundle it cannot tell one profile's windows
from another's, so it claims all of them and says so once on the console. Two targets sharing such a bundle would fight
over one window. Adding a browser means adding its `Local State` path in `browsers.lua`; a target that names a
`profileDir` on a bundle missing from that table fails the build, and the assertion reads the table out of
`browsers.lua` rather than restating it. A target with no `profileDir` is left alone — it asks for every window of its
bundle, which is what an unreadable list gives it anyway.

Where the list *is* readable, not claiming is the safe direction — claiming the wrong window would put a client's links
in front of the wrong profile — but it is not free: a window whose tail matches nothing makes the hotkey launch a new
one. A policy-set enterprise label (`EnterpriseCustomLabel`) replaces the local name in the title, so it is read from
the same `info_cache` entry's `enterprise_label` and used in place of `name` when non-empty — Chrome's own
`GetLocalProfileName` rule. The avatar button's generic "Work"/"School" badge is not stored there and never reaches the
title, so it needs nothing. No profile on this machine carries a label, so this rests on Chromium source rather than a
live window.

Two conditions gate the profile name appearing at all: the profile manager must know more than one profile
(`GetNumberOfProfiles() > 1` — Brave has one today, so its windows carry none) and the profile must not be
off-the-record, since Incognito and Guest take earlier branches appending `(Incognito)`/`(Guest)`.

**"No profile name" therefore cannot simply mean "the default profile".** An automation copy of Chrome — the
`chrome-devtools-mcp` one that runs on this machine — reports the same bundle id from the same bundle path, but runs
under its own `--user-data-dir`, so its windows carry no profile suffix either. Three such Chrome processes were
running when this was measured. The rule that works is to read the *configured* browser's `Local State`: a browser
that knows more than one profile appends a name to every eligible window, so a bare title there is **unknown**, while
a browser that knows only one appends nothing and every window is its. That is also why window lookup iterates
`hs.application.applicationsForBundleID` rather than `hs.application.get`, which returns only one of the processes.

## The picker

`hs.hotkey.modal`, not `hs.chooser`, for two independent reasons. A chooser cannot commit on a single keypress — it is
a query field, so a choice costs typing plus Return. And it **takes** focus: `chooser.lua` installs a default global
callback that stores `window.frontmostWindow()` on `willOpen` and calls `:focus()` on it again at `didClose`, which is
machinery that only exists because opening one steals focus in the first place.

Taking focus is the disqualifying half. A link is clicked from inside some other application, and pulling focus out of
it to ask a question is exactly what this is meant to avoid. A modal binds real hotkeys instead, so the choice is made
while the clicking application still holds focus.

The danger is the mirror of the usefulness. While the modal is entered it swallows its keys from every application, so
a modal left entered would make those letters untypeable machine-wide. Every path out of `picker.lua` exits it, and a
timer guarantees an exit even if none of them run — the timer is armed *before* the modal is entered, so it cannot
outlive it.

Two behaviours are choices rather than consequences, and either could reasonably be the other:

- **A second link while the picker is up joins a queue**, and one choice then opens all of them. Clicking several
  links in a burst is what this serves. The alternative silently drops every link but one.
- **Each queued link restarts the countdown**, so the newest link gets a full `picker.timeout` to be answered rather
  than the remainder of the first one's. That has no fixed point on its own — links arriving faster than the countdown
  would hold the keyboard for as long as they kept coming — so a second timer, `picker.maxHold`, is armed once per
  picker and never restarted. Whichever runs out first ends it.
- **Running out of time routes to the first target rather than dropping the link**, and both timers do the same thing.
  A dropped link is invisible and leaves the user with nothing; reorder `local.browsers.targets` to change which
  target that is.

### Two limits worth knowing before debugging one of them

**Window lookup only sees the current Mission Control Space.** `app:allWindows()` is documented as returning only
windows in the current Space, and this config does not use `hs.window.filter`, which is the documented way around it.
So a browser window that is fullscreen or on another Space is invisible to the hotkey: it finds nothing, launches, and
you get a duplicate window on the current Space. It is self-correcting — the next press finds that new window — and it
does not affect link routing, which always goes through `open`.

**The stub's crash fallback is hard-coded Safari, and cannot carry a profile.** Not because it could not name a
configured target — the previous value was the first target's bundle, interpolated at eval time and just as independent
of anything loaded at runtime. It is hard-coded because Safari is the one bundle guaranteed to be present on any Mac,
so the fallback holds even on a machine whose configured browsers are not installed. The cost is real and accepted: a
router failure puts the link in Safari rather than your primary browser, and `openURLWithBundle` takes a bundle id and
nothing else, so it lands in whichever Safari profile was last used. A link in the wrong browser is recoverable; a link
that goes nowhere is not.

## Testing

`nix flake check` is the whole verification surface for the Lua, because the hand-written config is symlinked out of
the store and no build ever loads it. The check parses every Lua file with the same Lua 5.4 the app embeds, holds it to
`stylua.toml`, and then *runs* it against a stub `hs` that records what the modules did.

Two things about that are easy to break and are recorded nowhere else:

- **The generated `init.lua` is executed too, not just parsed.** It lives in `stub.nix` precisely so the check can
  build it with test values and `dofile` it — it is the one file whose failure loses every clicked link on the machine.
  `tests/fixtures/hs/` resolves the `require("hs.ipc")` it performs for its side effect.
- **Its `cfgDir` must resolve inside the build directory.** The stub prepends `<cfgDir>/lua` to `package.path` ahead of
  everything else, and this flake builds unsandboxed, so a fixed `/tmp` name would let any local process shadow the
  modules under test. The check substitutes a placeholder with `$PWD/cfg` for that reason.

Anything involving real key capture, a real window server or real LaunchServices has to be tested on the machine.

## `~/.hammerspoon` must stay gone

`MJConfigFile` is an undocumented `NSUserDefaults` key. Holding Cmd+Opt at launch removes every key in the domain, and a
prefs reset does the same. When it is missing Hammerspoon silently falls back to the compiled-in
`~/.hammerspoon/init.lua` — with no error.

That directory and its source in `dotfiles` are both removed, so the fallback now fails visibly instead of loading a
stale config. Recreating either would restore the failure mode rather than a safety net: a `setup.sh` run rsyncs
`dotfiles/home/` into `~`, so a file there lands on the exact path a lost `MJConfigFile` silently reaches for.

## `hs.ipc` is a privilege surface

The stub calls `require("hs.ipc")` so activation can reload the config with `hs -c`. That opens a name-based Mach port
with no authentication beyond the user session, and it was **not open before this module existed** — before it, the
CLI had never worked on this Mac.

The consequence is worth stating plainly: any process running as this user can then execute arbitrary Lua inside
Hammerspoon and inherit its Accessibility grant — synthesising keystrokes into any application, reading window
contents, running shell commands. This workspace runs coding agents as that same user. The TCC and code-signing
argument above is about what may *install* Hammerspoon; this is about what may *drive* it, and they are unrelated.

It is accepted because the alternative — activation that cannot reload the config it just replaced — is worse, and
because anything already running as this user can drive the GUI by other means. It is documented because it is a real
capability change the packaging discussion would otherwise hide.

## Reloading

The reload watcher must point at `<cfgdir>/lua`, never at `<cfgdir>`. `hs.pathwatcher` resolves symlinks before
creating the FSEvents stream, so watching `lua/` follows into the repo and fires on edits there; watching the parent
sees only a symlink entry and never fires.

Activation does nothing at all under a dry run, and the intent has to be recovered from the parent's argv.
`darwin-rebuild` routes `--dry-run` into build flags only and runs the activation script regardless, so without an
explicit check a documented preview command would really restart Hammerspoon and raise the handler dialog.

home-manager's own guard also tests `$DRY_RUN`, and copying that half here would be cargo: nix-darwin's `activate`
begins `#!/usr/bin/env -i …/bash`, so no environment is inherited and the variable can never be set. home-manager
tests it because its *user* script is invoked as `env DRY_RUN=1 <script>`, which is a different process.

Otherwise it restarts when `hs.configdir` does not yet match the configured path, and only reloads when it does. The
restart branch is what makes the first switch work, since the preference is read once at launch.

**A failed probe must count as a mismatch.** The comparison runs `hs -c`, which needs `hs.ipc` loaded in the *running*
instance — and on the first activation that instance is still the old config, which never loaded it. So the probe
cannot answer on precisely the run that must restart. Treat any failure, empty output or non-zero exit as "does not
match" and restart; reading it as an error, or as a match, leaves the Mac running the stale config while activation
reports success.

That same comparison is the one verdict everything downstream is gated on — whether to reload, and whether to claim the
handler. The restart also re-asserts `MJConfigFile` between the kill and the relaunch: it is written in the
`userDefaults` phase into the prefs of an app that is still running, and a termination flush can put the cached value
back.

Edits made inside an agent worktree do not hot-reload — `local.hammerspoon.luaDir` defaults to the main checkout, and
that is correct: the running config should follow the reviewed tree, not a branch.

**Ordinary git operations in the watched tree are deploys.** The watcher fires on any `*.lua` write under `luaDir`, so
a `git checkout`, `git stash` or rebase in the main checkout moves the running config to whatever that branch holds,
half a second later. Checking out anything older than the module leaves the symlink dangling and the hotkeys gone,
announced only by a notification — and recovery is not automatic, because the bare `lua` path has no `.lua` suffix and
so does not pass the watcher's own filter. This is the cost of live editing from a real checkout, and the main argument
for pointing `luaDir` at something that is not a branch-switching tree.

The other consequence is that **activating an unmerged branch needs that option overridden**, because the symlink would
otherwise point at a directory that only exists on the branch. Nix cannot catch this: the path is a plain string with
no store context, so a missing target builds cleanly and fails only at runtime. Activation therefore checks the
directory itself and, when it is absent, says so and leaves the running Hammerspoon alone — restarting into a config
with no `lua/` would trade a working instance for one with no hotkeys.
