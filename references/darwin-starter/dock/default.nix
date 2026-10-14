{ config, pkgs, lib, ... }:

# Original source: https://gist.github.com/antifuchs/10138c4d838a63c0a05e725ccd7bccdd

with lib;
let
  cfg = config.local.dock;
  inherit (pkgs) stdenv dockutil;
in
{
  options = {
    local.dock.enable = mkOption {
      description = "Enable dock";
      default = stdenv.isDarwin;
      example = false;
    };

    local.dock.entries = mkOption
      {
        description = "Entries on the Dock";
        type = with types; listOf (submodule {
          options = {
            path = lib.mkOption { type = str; };
            section = lib.mkOption {
              type = str;
              default = "apps";
            };
            options = lib.mkOption {
              type = str;
              default = "";
            };
          };
        });
        readOnly = true;
      };
  };

  config =
    mkIf cfg.enable
      (
        let
          normalize = path: if hasSuffix ".app" path then path + "/" else path;
          entryURI = path: "file://" + (builtins.replaceStrings
            [" "   "!"   "\""  "#"   "$"   "%"   "&"   "'"   "("   ")"]
            ["%20" "%21" "%22" "%23" "%24" "%25" "%26" "%27" "%28" "%29"]
            (normalize path)
          );
          wantURIs = concatMapStrings
            (entry: "${entryURI entry.path}\n")
            cfg.entries;
        in
        {
          # nix-darwin removed the user activation scripts; everything runs as
          # root now, so drop back to the primary user for the dock, which is
          # per-user state.
          system.activationScripts.postActivation.text = ''
            echo >&2 "Setting up the Dock..."
            asUser() { /usr/bin/sudo --user=${config.system.primaryUser} -- "$@"; }
            haveURIs="$(asUser ${dockutil}/bin/dockutil --list | ${pkgs.coreutils}/bin/cut -f2)"
            if ! diff -wu <(echo -n "$haveURIs") <(echo -n '${wantURIs}') >&2 ; then
              echo >&2 "Resetting Dock."
              asUser ${dockutil}/bin/dockutil --no-restart --remove all
              ${concatMapStrings
                (entry: "asUser ${dockutil}/bin/dockutil --no-restart --add '${entry.path}' --section ${entry.section} ${entry.options}\n")
                cfg.entries}
              asUser /usr/bin/killall Dock
            else
              echo >&2 "Dock setup complete."
            fi
          '';
        }
      );
}
