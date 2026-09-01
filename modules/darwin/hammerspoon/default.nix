# Hammerspoon: the application, and the configuration it runs.
#
# Read ./README.md before changing anything here. Most of what follows looks
# arbitrary and is not — the config path, the module name the stub requires,
# the restart-vs-reload branch, the Lua version of the syntax gate and the
# choice of environment.systemPackages over home.packages each exist to
# prevent a specific, observed failure.
{ config, pkgs, lib, ... }:

let
  user = "tapani";
  home = "/Users/${user}";
  cfgDir = "${home}/.config/hammerspoon";

  hammerspoon = pkgs.callPackage ./package.nix { };

  # Read here, where `config` is still the darwin config — inside
  # home-manager.users.<name> it is shadowed by home-manager's own.
  luaDir = config.local.hammerspoon.luaDir;

  # The bundle is rsynced to a stable path by nix-darwin's applications
  # activation; the store path is not a usable launch target.
  appPath = "/Applications/Nix Apps/Hammerspoon.app";

  # pkgs.lua is still 5.2.4 in this pin, while Hammerspoon embeds 5.4.7. A 5.2
  # gate would reject valid 5.3+ syntax and wave through 5.2-isms the app
  # rejects — and this gate is the only thing between a generated file and
  # every link on this Mac silently going nowhere.
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

  # Generated, and kept deliberately small: everything that can fail is loaded
  # through pcall from here, so a syntax error in a hand-edited module cannot
  # stop the parts that must always run.
  initLua = checkedLua "hammerspoon-init.lua" ''
    -- Managed by systems/modules/darwin/hammerspoon. Edits here are replaced
    -- on the next build-switch; hand-edited config lives in lua/.

    -- `hs -c` needs this loaded in the *running* instance. Nothing loaded it
    -- before this module existed, so the hs CLI has never worked on this Mac.
    --
    -- This opens a name-based Mach port with no authentication beyond the user
    -- session: any process running as this user can then drive Hammerspoon,
    -- and so inherit its Accessibility grant. That is a real new capability on
    -- a machine that runs coding agents as this same user — see the "hs.ipc is
    -- a privilege surface" section of README.md.
    require("hs.ipc")

    -- Guards a regression class rather than a specific bug: 0.9.79 shipped a
    -- symlink-resolution change that broke sibling require(), reverted in
    -- 0.9.81, with no test since.
    local expected = "${cfgDir}"
    if hs.configdir ~= expected then
      -- print() as well as notify(): a bundle launched from a new path has no
      -- notification authorization until the user grants it, so notify alone
      -- would leave this "loud" guard silent in exactly the situation that
      -- introduces the drift.
      print("hammerspoon: configdir is " .. tostring(hs.configdir) .. ", expected " .. expected)
      hs.notify.new({
        title = "Hammerspoon config dir drift",
        informativeText = "configdir=" .. tostring(hs.configdir) .. " expected=" .. expected,
      }):send()
    end

    -- Lets the modules under lua/ require each other by bare name. Note this
    -- does NOT make a bare require("init") safe — see the dotted require at
    -- the bottom of this file.
    package.path = hs.configdir .. "/lua/?.lua;" .. hs.configdir .. "/lua/?/init.lua;" .. package.path

    -- Global on purpose. hs.pathwatcher keeps no internal registry, unlike
    -- hs.hotkey and hs.window.filter, so a watcher held only by a local in
    -- this chunk is collected once the chunk returns and hot reload stops at
    -- an arbitrary later GC, silently.
    --
    -- Filtered and debounced: one editor write emits several events (Neovim
    -- alone writes 4913, a swapfile and the target), and reloading on the
    -- first can read a half-flushed file and report a failure that is not
    -- real. A git checkout in the watched tree produces a whole burst.
    hsConfigReloadTimer = nil
    hsConfigWatcher = hs.pathwatcher.new(hs.configdir .. "/lua", function(files)
      local touchedLua = false
      for _, f in ipairs(files or {}) do
        if f:match("%.lua$") then
          touchedLua = true
          break
        end
      end
      if not touchedLua then
        return
      end
      if hsConfigReloadTimer then
        hsConfigReloadTimer:stop()
      end
      hsConfigReloadTimer = hs.timer.doAfter(0.5, hs.reload)
    end)
    hsConfigWatcher:start()

    -- The DOTTED name is load-bearing. A bare require("init") resolves through
    -- Hammerspoon's own <configdir>/?.lua template to THIS file whenever
    -- lua/init.lua is missing — and because Hammerspoon loads init.lua with
    -- loadfile rather than require, package.loaded never arms Lua's loop
    -- guard. Measured: the stub re-entered itself 96 times to a C stack
    -- overflow, which the pcall below then reported as ok=true, leaving ~96
    -- live watchers, no hotkeys and no error. "lua.init" maps to
    -- lua/init.lua and cannot collide with this file.
    local ok, err = pcall(require, "lua.init")
    if not ok then
      hs.notify.new({ title = "Hammerspoon config failed to load", informativeText = tostring(err) }):send()
      print("config load failed: " .. tostring(err))
    end
  '';
in
{
  options.local.hammerspoon.luaDir = lib.mkOption {
    type = lib.types.str;
    default = "${home}/project/github/tapppi/systems/modules/darwin/hammerspoon/lua";
    description = ''
      Absolute path to the live, hand-edited Lua directory, symlinked out of
      the store so edits apply without a rebuild.

      Defaults to the MAIN checkout: the running config should follow reviewed
      code, not whatever branch is checked out. Note the consequence — the
      reload watcher fires on any *.lua write there, so ordinary git
      operations in that tree are live deploys of this config.

      It is a plain string with no store context, so nix cannot verify it: a
      wrong or missing path builds cleanly and fails only at runtime, which is
      why activation checks it.

      Override it to a worktree path to activate an in-progress branch, and
      revert that before merging.
    '';
  };

  config = {
    # Must be systemPackages, not home.packages: the TCC argument in README.md
    # rests on nix-darwin rsyncing the bundle into /Applications/Nix Apps, and
    # that activation reads environment.systemPackages only. home-manager would
    # link it into ~/Applications/Home Manager Apps as a plain store symlink.
    environment.systemPackages = [ hammerspoon ];

    # Applied in the userDefaults activation phase, which runs before
    # postActivation places the files below. Hammerspoon reads this exactly
    # once, at launch — hence the restart branch further down.
    #
    # Write-only: nix-darwin's renderer emits `defaults write` and never a
    # delete, so removing this module leaves the key behind pointing at an
    # init.lua home-manager has just removed.
    system.defaults.CustomUserPreferences."org.hammerspoon.Hammerspoon" = {
      MJConfigFile = "${cfgDir}/init.lua";

      # The packaged Info.plist ships SUEnableAutomaticChecks = 1 with a live
      # feed. Sparkle cannot replace a read-only store bundle, so a successful
      # check can only ever advertise a version this host has no way to
      # install. Declared rather than left to the hand-set user-domain keys
      # that happen to suppress it today.
      SUEnableAutomaticChecks = false;
      SUAutomaticallyUpdate = false;
    };

    home-manager.users.${user} = { config, ... }: {
      home.file.".config/hammerspoon/init.lua".source = initLua;

      # Out of store on purpose, and the only such entry here: this is edited
      # live and reloaded by the watcher above without a rebuild. It is a
      # deliberate exception — store-managed content is the point everywhere
      # else in this migration.
      home.file.".config/hammerspoon/lua".source =
        config.lib.file.mkOutOfStoreSymlink luaDir;
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "configuring Hammerspoon" >&2

      if /bin/ps -o args= -p "$PPID" 2>/dev/null | /usr/bin/grep -q -- ' --dry-run'; then
        # darwin-rebuild routes --dry-run into build flags only and runs
        # activate regardless, so without this a documented preview command
        # would SIGTERM and relaunch the running Hammerspoon for real.
        echo "  hammerspoon: --dry-run; leaving the running instance alone." >&2
      elif [ ! -d ${lib.escapeShellArg luaDir} ]; then
        # The lua/ symlink is out of store, so nix could not check it at build
        # time. Restarting into a missing config would trade a working
        # Hammerspoon for one with no hotkeys.
        echo "  hammerspoon: luaDir is missing; leaving the running instance alone." >&2
        echo "  hammerspoon:   ${luaDir}" >&2
        echo "  hammerspoon: set local.hammerspoon.luaDir when activating from a worktree." >&2
      elif /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1; then
        hsUid="$(/usr/bin/id -u ${user})"
        asUser() {
          /bin/launchctl asuser "$hsUid" /usr/bin/sudo -u ${user} --set-home "$@"
        }

        # -a: exit rather than raise an interactive "launch Hammerspoon?"
        # prompt. stderr is discarded here and stdin is still the invoking
        # terminal, so a prompt would block activation invisibly.
        #
        # A failed probe means "does not match". On the first switch the
        # running instance is still the old config, which never loaded hs.ipc,
        # so the probe CANNOT answer on precisely the run that has to restart.
        have="$(asUser ${hammerspoon}/bin/hs -a -c 'print(hs.configdir)' 2>/dev/null || true)"

        if [ "$have" = '${cfgDir}' ]; then
          asUser ${hammerspoon}/bin/hs -a -c 'hs.reload()' >/dev/null 2>&1 || true
        else
          # Verify each step rather than assuming it worked. SIGTERM makes
          # Hammerspoon run Lua shutdown handlers that can outlast a fixed
          # sleep, and `open -a` against a live instance merely activates it.
          /usr/bin/killall Hammerspoon >/dev/null 2>&1 || true

          for _ in 1 2 3 4 5 6 7 8 9 10; do
            /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1 || break
            /bin/sleep 0.5
          done

          if /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1; then
            echo "  hammerspoon: old instance still running after 5s; not relaunching." >&2
            echo "  hammerspoon: quit it and reopen ${appPath}." >&2
          else
            asUser /usr/bin/open -a '${appPath}' >/dev/null 2>&1 || true

            now=""
            for _ in 1 2 3 4 5 6 7 8 9 10; do
              /bin/sleep 1
              now="$(asUser ${hammerspoon}/bin/hs -a -c 'print(hs.configdir)' 2>/dev/null || true)"
              [ "$now" = '${cfgDir}' ] && break
            done

            if [ "$now" != '${cfgDir}' ]; then
              echo "  hammerspoon: relaunched but configdir reports \"$now\"." >&2
            fi
          fi
        fi
      else
        # Not running, so there is nothing to restart into the new config. The
        # login item still points at the Homebrew bundle in this phase; both
        # bundles share org.hammerspoon.Hammerspoon and therefore the same
        # MJConfigFile, so either will read this config. Phase 3 removes the
        # cask and takes ownership of launching.
        echo "  hammerspoon: not running; start ${appPath} to pick up the new config." >&2
      fi
    '';
  };
}
