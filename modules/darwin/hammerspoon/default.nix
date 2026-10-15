# Hammerspoon: the application, and the configuration it runs.
#
# Several choices here fail in ways the code cannot show; ./README.md explains
# each.
{ config, pkgs, lib, ... }:

let
  inherit (config.local.workstation) user home;
  cfgDir = "${home}/.config/hammerspoon";

  hammerspoon = pkgs.callPackage ./package.nix { };

  # Read here, where `config` is still the darwin config — inside
  # home-manager.users.<name> it is shadowed by home-manager's own.
  luaDir = config.local.hammerspoon.luaDir;
  browsers = config.local.browsers.targets;

  # The bundles whose profile list lua/browsers.lua can read, taken from the
  # module itself so the two cannot drift. Read here rather than restated,
  # because the paths that make a bundle supported have to live next to the
  # code that reads them, and a second copy in this option would be the thing
  # the assertion below is meant to prevent.
  #
  # This reads the module's own browsers.lua, not the one the machine loads:
  # luaDir is an out-of-store symlink and can be pointed at a worktree, so a
  # target added there is checked against that tree's table while Hammerspoon
  # runs the main checkout's. The assertion catches a target the *evaluated*
  # tree cannot support, which is the common case; it cannot see that skew.
  supportedBundles =
    let
      lines = lib.splitString "\n" (builtins.readFile ./lua/browsers.lua);
      openIdx = lib.lists.findFirstIndex (l: builtins.match "M\\.localState = [{]" l != null) null lines;
      rest = lib.lists.sublist (openIdx + 1) (builtins.length lines) lines;
      # builtins.match anchors on the whole line, so the body ends at the
      # table's own closing brace in column 0 and a nested table value cannot
      # truncate the list. Each key is matched on its own line, so a
      # commented-out entry cannot join it.
      closeIdx = lib.lists.findFirstIndex (l: builtins.match "[}].*" l != null) null rest;
      body =
        if closeIdx == null then
          throw (
            "hammerspoon: M.localState in lua/browsers.lua has no closing brace in column 0; "
            + "the supported-bundle list cannot be delimited"
          )
        else
          lib.lists.sublist 0 closeIdx rest;
      keys = builtins.filter (m: m != null) (
        map (l: builtins.match "[[:space:]]*[[]\"([^\"]+)\"[]][[:space:]]*=.*" l) body
      );
    in
    if openIdx == null then
      throw "hammerspoon: no M.localState table in lua/browsers.lua; the supported-bundle assertion cannot be derived"
    else
      map builtins.head keys;

  # profileDir is what makes an unreadable bundle harmful: without one the
  # target wants every window of the app anyway, which is what it gets.
  unsupported = lib.unique (
    map (t: t.bundle) (lib.filter (t: t.profileDir != null && !(lib.elem t.bundle supportedBundles)) browsers)
  );

  # The same collision from the other direction, and on a bundle the Lua reads
  # perfectly well: a target with no profileDir claims every window of its
  # bundle, so pairing one with a profiled target on that bundle means the
  # unprofiled one swallows the profiled one's windows.
  overlapping = lib.unique (
    map (t: t.bundle) (
      lib.filter (
        t: t.profileDir == null && lib.any (o: o.bundle == t.bundle && o.profileDir != null) browsers
      ) browsers
    )
  );

  # The bundle is rsynced to a stable path by nix-darwin's applications
  # activation; the store path is not a usable launch target.
  appPath = "/Applications/Nix Apps/Hammerspoon.app";

  bundleId = "org.hammerspoon.Hammerspoon";

  # Web types Hammerspoon declares that macOS does not transfer along with http.
  # Wanted for the same reason html is left alone: they reach the picker as
  # file:// URLs, so the router still chooses the browser.
  # One extension, three types: xhtml, xht and xhtm are all public.xhtml, so
  # this claim moves the family. jhtml is deliberately absent — it resolves to a
  # dynamic UTI that duti rejects outright (error -50), so claiming it would
  # re-attempt an impossible change on every activation.
  claimableExt = "xhtml";

  # What Hammerspoon claims but cannot route. html, htm and shtml are excluded:
  # they are the default-browser identity on macOS, so moving one away asks to
  # change the browser back. A .url is a shortcut file rather than web content —
  # the picker hands the browser the file instead of following the link inside it.
  # One extension per UTI: .txt and .text are both public.plain-text, so
  # listing both would issue the same restore twice and log it as two repairs.
  restorableExts = "txt url";

  # lua5_4 to match the interpreter the app embeds; pkgs.lua is still 5.2.
  checkedLua = name: text:
    pkgs.runCommand name
      {
        inherit text;
        passAsFile = [ "text" ];
        nativeBuildInputs = [ pkgs.lua5_4 ];
      } ''
      cp "$textPath" candidate.lua
      luac -p candidate.lua
      cp candidate.lua "$out"
    '';

  luaStr = import ./lua-str.nix;

  # One source of truth, so the picker rows and the hotkeys cannot drift.
  # Assembled line by line because this file is read when the picker misbehaves,
  # and its indentation should not depend on how nix strips a here-doc.
  targetsLua =
    let
      field = name: value: "    ${name} = ${luaStr value},";
      entry =
        t:
        lib.concatStringsSep "\n" (
          [
            "  {"
            (field "key" t.key)
            (field "label" t.label)
            (field "bundle" t.bundle)
          ]
          ++ lib.optional (t.profileDir != null) (field "profileDir" t.profileDir)
          ++ [ "  }," ]
        );
    in
    checkedLua "hammerspoon-targets.lua" (
      lib.concatStringsSep "\n" (
        [
          "-- Managed by systems/modules/darwin/hammerspoon, generated from"
          "-- local.browsers.targets. Edits here are replaced on the next build-switch."
          "return {"
        ]
        ++ map entry browsers
        ++ [
          "}"
          ""
        ]
      )
    );

  # Generated, and kept deliberately small: everything that can fail is loaded
  # through pcall from here, so a syntax error in a hand-edited module cannot
  # stop the parts that must always run.
  initLua = checkedLua "hammerspoon-init.lua" (import ./stub.nix { inherit cfgDir; });
in
{
  options.local.hammerspoon.luaDir = lib.mkOption {
    type = lib.types.strMatching "/[A-Za-z0-9_./-]+";
    description = ''
      Absolute path to the live, hand-edited Lua directory, symlinked out of
      the store so edits apply without a rebuild.

      Set this in the host composition to the intended live checkout, using
      shell-safe path characters. The reload watcher fires on any *.lua write
      there, so ordinary git operations in that tree are live deploys.

      It is a plain string with no store context, so nix cannot verify it: a
      wrong or missing path builds cleanly and fails only at runtime, which is
      why activation checks it.

      Override it to a worktree path to activate an in-progress branch, and
      revert that before merging.
    '';
  };

  options.local.browsers.targets = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          key = lib.mkOption {
            type = lib.types.strMatching "[a-z0-9]";
            description = "Picker key and hyper hotkey. One character, so a choice is one keypress.";
          };
          label = lib.mkOption {
            type = lib.types.str;
            description = ''
              Row text in the picker. Deliberately generic: this repo is public, so a
              client's name must not appear here. Real display names are read from the
              browser's Local State at runtime instead.
            '';
          };
          bundle = lib.mkOption {
            type = lib.types.str;
            description = "Bundle id of the browser to launch.";
          };
          profileDir = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              On-disk profile directory — "Profile 1", never the display name. null for a
              browser launched without --profile-directory at all.
            '';
          };
        };
      }
    );
    default = [
      {
        key = "b";
        label = "Safari";
        bundle = "com.apple.Safari";
      }
    ];
    description = ''
      Browser profiles an opened link can be routed to, in picker order.

      Generates both the picker and the hyper hotkeys. Keys must not collide with
      each other or with the app hotkeys bound in lua/init.lua.
    '';
  };

  options.local.browsers.claimDefaultHandler = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Make Hammerspoon the system handler for http and https, so clicked links
      reach the router.

      Hammerspoon's Info.plist declares html/htm/shtml/jhtml, txt/text, url,
      xhtml/xht/xhtm, spoon and `*` as document types, all Viewer. Those group
      by UTI, not by extension: html/htm/shtml are one public.html, which taking
      http transfers as a unit and which are left alone; xhtml/xht/xhtm are one
      public.xhtml, never transferred, so one claim takes all three; txt, text
      and url are put back. `spoon` is already Hammerspoon's and `*` resolves
      nothing. jhtml is a dynamic UTI duti cannot set, so it is left alone.

      It also declares a mailto URL scheme, which is deliberately not claimed:
      httpCallback does not serve it, so taking it would drop every mailto link.
    '';
  };

  options.local.browsers.claimWebDocumentTypes = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Also claim the public.xhtml family (xhtml, xht, xhtm), so those render in
      Hammerspoon like html does and reach the picker as file:// URLs.

      Separate from claimDefaultHandler because it is a different claim with a
      different prompt. There is no record of a declined one, so leaving it on
      after declining re-raises the dialog on every activation; turn it off
      rather than living with that.
    '';
  };

  config = {
    # A duplicate key is silent at runtime: the second hs.hotkey.bind wins and the
    # first target becomes unreachable, with the picker still offering both rows.
    assertions = [
      {
        assertion = lib.length (lib.unique (map (t: t.key) browsers)) == lib.length browsers;
        message = "local.browsers.targets: duplicate key. Each key binds one hotkey and one picker row.";
      }
      # Degrades silently otherwise: with no profile list every window of the
      # bundle matches every target naming it, so two of them fight over one.
      {
        assertion = overlapping == [ ];
        message =
          "local.browsers.targets: ${lib.concatStringsSep ", " overlapping} has both a target with no "
          + "profileDir and one with a profileDir. The first claims every window of the bundle, "
          + "including the second's, so give every target on a bundle a profileDir.";
      }
      {
        assertion = unsupported == [ ];
        message =
          "local.browsers.targets: profileDir is set on ${lib.concatStringsSep ", " unsupported}, "
          + "whose profile list lua/browsers.lua cannot read. It knows "
          + "${lib.concatStringsSep ", " supportedBundles}; add this browser's Local State path to "
          + "M.localState there, or drop profileDir to accept every window of the bundle.";
      }
    ];

    # systemPackages, not home.packages: only that is rsynced into
    # /Applications/Nix Apps, which the TCC grant depends on.
    environment.systemPackages = [ hammerspoon ];

    # Written in the userDefaults phase, before the files below are placed.
    # Hammerspoon reads it once at launch, hence the restart branch below.
    # Write-only: removing this module leaves the key behind.
    system.defaults.CustomUserPreferences."org.hammerspoon.Hammerspoon" = {
      MJConfigFile = "${cfgDir}/init.lua";

      # Sparkle cannot replace a read-only store bundle, so a check can only
      # advertise a version this host cannot install.
      SUEnableAutomaticChecks = false;
      SUAutomaticallyUpdate = false;
    };

    home-manager.users.${user} = { config, ... }: {
      home.file.".config/hammerspoon/init.lua".source = initLua;
      home.file.".config/hammerspoon/generated/targets.lua".source = targetsLua;

      # Out of store so edits apply without a rebuild. A deliberate exception:
      # store-managed content is the point everywhere else.
      home.file.".config/hammerspoon/lua".source =
        config.lib.file.mkOutOfStoreSymlink luaDir;
    };

    system.activationScripts.postActivation.text = lib.mkAfter (
      ''
        echo "configuring Hammerspoon" >&2

        # darwin-rebuild routes --dry-run into build flags only and runs the
        # activation script regardless, so the intent is recoverable only from
        # the parent's argv — activate's shebang is `env -i`, so no variable
        # survives into it however the rebuild was invoked.
        #
        # home-manager derives the same reading a few lines earlier. Publishing
        # one DRY_RUN for both was considered and rejected: it would make this
        # guard depend on another module having run, and a guard that silently
        # stops firing restarts Hammerspoon and raises dialogs in the middle of
        # a preview. Duplicating one `ps` call is the cheaper failure.
        hsParentArgs="$(/bin/ps -p "$PPID" -ww -o args= 2>/dev/null || true)"

        # A claim made against an instance running some other config would send
        # every clicked link on the machine nowhere: that instance has no http
        # callback registered, and the stub's fallback lives inside the config
        # it never loaded.
        hsRunningOurConfig=""
        hsDryRun=""

        if [[ "$hsParentArgs" == *" --dry-run"* ]]; then
          hsDryRun=1
          echo "  hammerspoon: --dry-run; leaving the running instance alone." >&2
        else
          hsUid="$(/usr/bin/id -u ${user})"
          asUser() {
            /bin/launchctl asuser "$hsUid" /usr/bin/sudo -u ${user} --set-home "$@"
          }

          # -a makes `hs` exit rather than raise a Launch/Cancel alert that
          # nothing under launchctl can answer. It is absent from `hs -h` but
          # documented in hs.man. A failed probe must read as empty, since an
          # instance predating hs.ipc cannot answer at all and that counts as a
          # mismatch.
          # LaunchServices is the source of truth and answers instantly. The
          # reload above tears down hs.ipc, so asking Hammerspoon instead would
          # read as "no handler" for as long as it takes to come back — and
          # every retry would pay the hs timeout.
          hsHttpHandler() {
            /usr/bin/plutil -convert json -o - \
              "${home}/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist" 2>/dev/null \
              | ${pkgs.jq}/bin/jq -r \
                'first((.LSHandlers // [])[] | select(.LSHandlerURLScheme == "http") | .LSHandlerRoleAll) // ""' \
              2>/dev/null || true
          }

          hsEval() {
            asUser ${hammerspoon}/bin/hs -a -t "$1" -c "$2" </dev/null 2>/dev/null | /usr/bin/tail -1 || true
          }

          if [ ! -d ${lib.escapeShellArg luaDir} ]; then
            # nix cannot verify an out-of-store path, and restarting into a
            # missing config would leave the machine with no hotkeys.
            echo "  hammerspoon: luaDir is missing; leaving the running instance alone." >&2
            echo "  hammerspoon:   ${luaDir}" >&2
            echo "  hammerspoon: set local.hammerspoon.luaDir when activating from a worktree." >&2
          elif ! /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1; then
            # The login item starts this bundle at login, so a missing process
            # means it was quit, not that it was never configured.
            echo "  hammerspoon: not running; start ${appPath} to pick up the new config." >&2
          elif [ "$(hsEval 5 'print(hs.configdir)')" = '${cfgDir}' ]; then
            hsEval 5 'hs.reload()' >/dev/null
            hsRunningOurConfig=1
          else
            # Shutdown handlers can outlast a fixed sleep, and `open -a` on a
            # live instance only activates it.
            /usr/bin/killall Hammerspoon >/dev/null 2>&1 || true

            for _ in 1 2 3 4 5 6 7 8 9 10; do
              /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1 || break
              /bin/sleep 0.5
            done

            if /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1; then
              echo "  hammerspoon: old instance still running after 5s; not relaunching." >&2
              echo "  hammerspoon: quit it and reopen ${appPath}." >&2
            else
              # MJConfigFile was written in the userDefaults phase into the
              # prefs of an app that was still running, so its termination
              # flush can put a stale cached value back — and a missing key
              # falls back to the deliberately absent ~/.hammerspoon/init.lua.
              asUser /usr/bin/defaults write '${bundleId}' MJConfigFile '${cfgDir}/init.lua' || true

              asUser /usr/bin/open -a '${appPath}' >/dev/null 2>&1 || true

              hsNow=""
              for _ in 1 2 3 4 5 6 7 8 9 10; do
                /bin/sleep 1
                # The one place that genuinely runs with no instance, so the
                # process check is made here rather than inherited.
                /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1 || continue
                hsNow="$(hsEval 5 'print(hs.configdir)')"
                if [ "$hsNow" = '${cfgDir}' ]; then
                  hsRunningOurConfig=1
                  break
                fi
              done

              if [ -z "$hsRunningOurConfig" ]; then
                echo "  hammerspoon: relaunched but configdir reports \"$hsNow\"." >&2
              fi
            fi
          fi
        fi
      ''
      + lib.optionalString config.local.browsers.claimDefaultHandler ''

        # duti reads and writes LaunchServices directly, so all of this works
        # whether or not Hammerspoon is running. Only the claim needs a live
        # instance; the restore must not, or the runs where a type is most
        # likely stranded are exactly the ones that skip repairing it.
        if [ -z "$hsDryRun" ]; then
          # duti, because hs.urlevent.setDefaultHandler fails silently on macOS
          # 26.6.2 — it reports success and leaves the handler unchanged.
          handlerFor() {
            asUser ${pkgs.duti}/bin/duti -x "$1" 2>/dev/null | /usr/bin/tail -1 || true
          }
          setHandler() {
            asUser ${pkgs.duti}/bin/duti -s "$1" "$2" all >/dev/null 2>&1 || true
          }

          # The plist stores the bundle id lowercased; duti reports it cased.
          hsIsOurs() {
            [ "$(printf '%s' "$1" | /usr/bin/tr '[:upper:]' '[:lower:]')" = \
              "$(printf '%s' '${bundleId}' | /usr/bin/tr '[:upper:]' '[:lower:]')" ]
          }

          # duti returns before macOS has raised its confirmation, so every
          # claim is waited out: a restore that lands while a prompt is still
          # open is undone the moment the prompt is answered.
          awaitHandler() {
            for _ in $(/usr/bin/seq 1 30); do
              [ "$(handlerFor "$1")" = '${bundleId}' ] && return 0
              /bin/sleep 1
            done
            return 1
          }

          # A duti that refuses outright is not a prompt nobody answered, and
          # only the second is worth waiting out.
          claimExt() {
            if ! asUser ${pkgs.duti}/bin/duti -s '${bundleId}' ".$1" all >/dev/null 2>&1; then
              echo "  hammerspoon: .$1 cannot be claimed; duti rejected it." >&2
              return 1
            fi
            if awaitHandler "$1"; then
              return 0
            fi
            echo "  hammerspoon: .$1 is unchanged; the prompt was declined or ignored." >&2
            return 1
          }

          # Snapshot first: answering any of the prompts below transfers every
          # document type Hammerspoon declares, not just the one being claimed.
          declare -A hsPrevHandler
          for hsExt in ${restorableExts}; do
            hsPrevHandler["$hsExt"]="$(handlerFor "$hsExt")"
          done

          hsClaimed=""
          hsCurrent="$(hsHttpHandler)"

          if [ -z "$hsRunningOurConfig" ]; then
            if ! hsIsOurs "$hsCurrent"; then
              echo "  hammerspoon: not running this config; leaving the http handler alone." >&2
            fi
          else
            if ! hsIsOurs "$hsCurrent"; then
              echo "  hammerspoon: claiming the http handler (macOS will ask you to confirm)" >&2

              # https follows http, and duti returns -54 for it either way.
              asUser ${pkgs.duti}/bin/duti -s '${bundleId}' http >/dev/null 2>&1 || true

              for _ in $(/usr/bin/seq 1 30); do
                hsCurrent="$(hsHttpHandler)"
                hsIsOurs "$hsCurrent" && break
                /bin/sleep 1
              done

              if hsIsOurs "$hsCurrent"; then
                hsClaimed=1
              else
                echo "  hammerspoon: http handler unchanged; the prompt was declined or ignored." >&2
              fi
            fi

            # Only once http is ours: stacking another prompt on top of a
            # declined one is worse than leaving the type where it is.
            if ${lib.boolToString config.local.browsers.claimWebDocumentTypes} && hsIsOurs "$hsCurrent" \
              && [ "$(handlerFor '${claimableExt}')" != '${bundleId}' ]; then
              echo "  hammerspoon: claiming .${claimableExt} (macOS will ask you to confirm)" >&2
              # Only a claim that landed can have transferred anything, so only
              # that one makes the restore below wait.
              claimExt '${claimableExt}' && hsClaimed=1
            fi
          fi

          # LaunchServices lags the dialog being answered.
          [ -z "$hsClaimed" ] || /bin/sleep 2

          for hsExt in ${restorableExts}; do
            hsPrev="''${hsPrevHandler["$hsExt"]}"
            [ -n "$hsPrev" ] || continue
            [ "$(handlerFor "$hsExt")" = '${bundleId}' ] || continue

            # The snapshot is this run's only memory, so a type taken on an
            # earlier run reads as having always been Hammerspoon's and there is
            # nothing to put it back to. Say so rather than skipping in silence;
            # the durable fix is for this module to assert the intended
            # associations instead of guessing them, which is SYSMI-19.
            if [ "$hsPrev" = '${bundleId}' ]; then
              echo "  hammerspoon: .$hsExt is Hammerspoon's and this run does not know what it was." >&2
              echo "  hammerspoon:   reassign it with: duti -s <bundle-id> .$hsExt all" >&2
              continue
            fi

            setHandler "$hsPrev" ".$hsExt"
            # Reported after the fact and only when it took: a restore that
            # duti refused would otherwise be announced as done.
            if [ "$(handlerFor "$hsExt")" = '${bundleId}' ]; then
              echo "  hammerspoon: .$hsExt could not be returned to $hsPrev." >&2
            else
              echo "  hammerspoon: returned .$hsExt to $hsPrev" >&2
            fi
          done
        fi
      ''
    );
  };
}
