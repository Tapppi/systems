# Hammerspoon: the application, and the configuration it runs.
#
# Read ./README.md before changing anything here. Most of what follows looks
# arbitrary and is not — the config path, the restart-vs-reload branch, the
# Lua version of the syntax gate and the choice of environment.systemPackages
# over home.packages each have a specific failure they exist to prevent.
{ config, pkgs, lib, ... }:

let
  user = "tapani";
  home = "/Users/${user}";
  cfgDir = "${home}/.config/hammerspoon";

  hammerspoon = pkgs.callPackage ./package.nix { };

  # The bundle is rsynced to a stable path by nix-darwin's applications
  # activation; the store path is not usable as a launch target.
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
    require("hs.ipc")

    -- Guards a regression class rather than a specific bug: 0.9.79 shipped a
    -- symlink-resolution change that broke sibling require(), reverted in
    -- 0.9.81, with no test since. Loud, because the silent failure is a stale
    -- config that looks correct.
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

    -- hs.configdir carries no trailing slash. `lua/` already resolves as
    -- require("lua.x") through the configdir template; this prepend only lets
    -- the modules require each other by bare name.
    package.path = hs.configdir .. "/lua/?.lua;" .. hs.configdir .. "/lua/?/init.lua;" .. package.path

    -- Reload on edits in the repo. The watcher must target lua/, not the
    -- config dir: pathwatcher resolves symlinks before creating the FSEvents
    -- stream, so watching the parent would only ever see a symlink entry.
    -- Filtered and debounced: an editor writing one file emits several events
    -- (Neovim alone writes 4913, a swapfile and the target), and reloading on
    -- the first can read a half-flushed file and report a spurious failure. A
    -- git checkout produces a whole burst.
    local reloadTimer
    hs.pathwatcher.new(hs.configdir .. "/lua", function(files)
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
      if reloadTimer then
        reloadTimer:stop()
      end
      reloadTimer = hs.timer.doAfter(0.5, hs.reload)
    end):start()

    local ok, err = pcall(require, "init")
    if not ok then
      hs.notify.new({ title = "Hammerspoon config failed to load", informativeText = tostring(err) }):send()
      print("config load failed: " .. tostring(err))
    end
  '';
  repoLua = config.local.hammerspoon.luaDir;
in
{
  options.local.hammerspoon.luaDir = lib.mkOption {
    type = lib.types.str;
    default = "${home}/project/github/tapppi/systems/modules/darwin/hammerspoon/lua";
    description = ''
      Absolute path to the live, hand-edited Lua directory, symlinked out of
      the store so edits apply without a rebuild.

      Defaults to the MAIN checkout on purpose: the running config should
      follow reviewed code, not whatever branch happens to be checked out. It
      is a plain string with no store context, so nix cannot verify it — a
      wrong or missing path builds cleanly and fails only at runtime, which is
      why activation checks it below.

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
    # postActivation places the files below. Hammerspoon reads this exactly once,
    # at launch — hence the restart branch further down.
    system.defaults.CustomUserPreferences."org.hammerspoon.Hammerspoon".MJConfigFile = "${cfgDir}/init.lua";

    home-manager = {
      useGlobalPkgs = true;
      # Keeps home.profileDirectory at /etc/profiles/per-user and away from
      # ~/.nix-profile, which does not exist on this machine and should not start
      # existing now.
      useUserPackages = true;

      users.${user} = { config, ... }: {
        home.stateVersion = "26.05";

        # This config manages one directory. Suppress the incidental files
        # home-manager would otherwise place on darwin.
        targets.darwin.copyApps.enable = false;
        home.file."Library/Fonts/.home-manager-fonts-version".enable = false;
        home.file."${home}/.cache/.keep".enable = false;
        home.file."${home}/.local/state/.keep".enable = false;

        home.file.".config/hammerspoon/init.lua".source = initLua;

        # Out of store on purpose, and the only such entry here: this is edited
        # live and reloaded by the watcher above without a rebuild. It is a
        # deliberate exception — store-managed content is the point everywhere
        # else in this migration.
        home.file.".config/hammerspoon/lua".source =
          config.lib.file.mkOutOfStoreSymlink repoLua;
      };
    };

    users.users.${user}.home = home;

    # mkAfter so this lands after home-manager's own postActivation block, which
    # is what places the files above.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "configuring Hammerspoon" >&2

      # The lua/ symlink is out of store, so nix could not check it at build
      # time. Restarting into a missing config would trade a working Hammerspoon
      # for one with no hotkeys, so leave the running instance alone and say so.
      if [ ! -d ${lib.escapeShellArg repoLua} ]; then
        echo "  hammerspoon: ${repoLua} is missing — leaving the running instance alone." >&2
        echo "  hammerspoon: set local.hammerspoon.luaDir if activating from a worktree." >&2
      elif /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1; then
        hsUid="$(/usr/bin/id -u ${user})"
        asUser() {
          /bin/launchctl asuser "$hsUid" /usr/bin/sudo -u ${user} "$@"
        }

        # A failed probe means "does not match". On the first switch the running
        # instance is still the old config, which never loaded hs.ipc, so the
        # probe CANNOT answer on precisely the run that has to restart. Reading
        # that as a match would leave this Mac on the stale config while
        # activation reported success.
        have="$(asUser ${hammerspoon}/bin/hs -c 'print(hs.configdir)' 2>/dev/null || true)"

        if [ "$have" = '${cfgDir}' ]; then
          asUser ${hammerspoon}/bin/hs -c 'hs.reload()' >/dev/null 2>&1 || true
        else
          # Verify each step rather than assuming it worked. SIGTERM makes
          # Hammerspoon run its Lua shutdown handlers, which can outlast a fixed
          # sleep — and `open -a` against a still-running instance merely
          # activates it, leaving this Mac on the stale config while activation
          # claims success.
          /usr/bin/killall Hammerspoon >/dev/null 2>&1 || true

          for _ in 1 2 3 4 5 6 7 8 9 10; do
            /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1 || break
            /bin/sleep 0.5
          done

          if /usr/bin/pgrep -qx Hammerspoon >/dev/null 2>&1; then
            echo "  hammerspoon: old instance still running after 5s; not relaunching." >&2
            echo "  hammerspoon: quit it and reopen ${appPath} to pick up the new config." >&2
          else
            asUser /usr/bin/open -a '${appPath}' >/dev/null 2>&1 || true

            now=""
            for _ in 1 2 3 4 5 6 7 8 9 10; do
              /bin/sleep 1
              now="$(asUser ${hammerspoon}/bin/hs -c 'print(hs.configdir)' 2>/dev/null || true)"
              [ "$now" = '${cfgDir}' ] && break
            done

            if [ "$now" != '${cfgDir}' ]; then
              echo "  hammerspoon: relaunched but configdir reports \"$now\"." >&2
            fi
          fi
        fi
      fi
    '';
  };
}
