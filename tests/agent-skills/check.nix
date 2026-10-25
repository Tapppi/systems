{
  self,
  inputs,
  system,
  pkgs,
}:
let
  fakeUv = pkgs.writeShellScriptBin "uv" ''
    exec ${pkgs.python3}/bin/python ${./fake-tools.py} uv "$@"
  '';
  fakeNode = pkgs.writeShellScriptBin "npm" ''
    exec ${pkgs.python3}/bin/python ${./fake-tools.py} npm "$@"
  '';
  candidate = self.lib.mkAgentSkillsSetup {
    inherit pkgs;
    uv = fakeUv;
    nodejs = fakeNode;
  };
  mkHome =
    enable:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        self.homeManagerModules.agentSkills
        {
          home.username = "fixture";
          home.homeDirectory =
            if pkgs.stdenv.hostPlatform.isDarwin then "/Users/fixture" else "/home/fixture";
          home.stateVersion = "26.05";
          programs.systems-agent-skills.enable = enable;
        }
      ];
    };
  enabled = mkHome true;
  disabled = mkHome false;
  package = self.packages.${system}.agent-skills-setup;
in
assert builtins.isString enabled.activationPackage.drvPath;
assert builtins.elem (toString package) (map toString enabled.config.home.packages);
assert !(builtins.elem (toString package) (map toString disabled.config.home.packages));
pkgs.runCommand "agent-skills-setup-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.shellcheck
    ];
    HOME_VALIDATOR = ../../setup/agent-skills/home-path.sh;
    SETUP_UNDER_TEST = "${candidate}/bin/agent-skills-setup";
    PYTHON_UNDER_TEST = "${candidate}/bin/agent-skills-python";
  }
  ''
    shellcheck ${../../setup/agent-skills/setup.sh} ${../../setup/agent-skills/home-path.sh}
    python3 ${./test_setup.py}
    export HOME="$TMPDIR/help-home"
    mkdir "$HOME"
    ${package}/bin/agent-skills-setup --help > "$out"
    test ! -e "$HOME/.local"
  ''
