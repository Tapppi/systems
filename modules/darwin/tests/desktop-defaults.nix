{
  darwin,
  pkgs,
  desktopModule,
}:
let
  evaluate =
    modules:
    (darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        {
          nix.enable = false;
          system.primaryUser = "desktop-test";
          system.stateVersion = 6;
        }
      ]
      ++ modules;
    }).config;
  scripts = config: {
    user = config.system.activationScripts.userDefaults.text;
    system = config.system.activationScripts.defaults.text;
  };
  fixtures = pkgs.writeText "desktop-defaults-fixtures.json" (
    builtins.toJSON {
      selected = scripts (evaluate [ desktopModule ]);
      absent = scripts (evaluate [ ]);
      overridden = scripts (evaluate [
        desktopModule
        {
          system.defaults.finder.FXPreferredViewStyle = "clmv";
          system.defaults.dock.tilesize = 68;
          system.defaults.dock.autohide = null;
        }
      ]);
    }
  );
in
pkgs.runCommand "desktop-defaults-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 ${./test-desktop-defaults.py} ${fixtures}
  touch "$out"
''
