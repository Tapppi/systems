{
  description = "Independent synthetic consumer of systems portable interfaces";
  inputs = {
    # Bootstrap template: run the adjacent runner against a candidate checkout.
    systems.url = "github:Tapppi/systems";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-fresh.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      systems,
      nixpkgs,
      nixpkgs-fresh,
      home-manager,
      ...
    }:
    let
      platforms = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAll = nixpkgs.lib.genAttrs platforms;
      fresh =
        system:
        import nixpkgs-fresh {
          inherit system;
          config.allowUnfreePredicate = p: nixpkgs.lib.getName p == "claude-code";
        };
      mkHome =
        system: names:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs.pkgsFresh = fresh system;
          modules = [
            systems.homeManagerModules.portableUser
            systems.homeManagerModules.herdr
            {
              home.username = "external";
              home.homeDirectory = if system == "aarch64-darwin" then "/Users/external" else "/home/external";
              home.stateVersion = "26.05";
              programs.systems-portable-user = {
                base.enable = true;
                harnesses = names;
              };
              programs.systems-herdr.enable = true;
            }
          ];
        };
    in
    {
      packages = forAll (system: {
        herdr = (fresh system).herdr;
        claude = (fresh system).claude-code;
        pi = (fresh system).pi-coding-agent;
        uv = nixpkgs.legacyPackages.${system}.uv;
        node = nixpkgs.legacyPackages.${system}.nodejs_24;
      });
      checks = forAll (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          both = mkHome system [
            "claude-code"
            "pi-coding-agent"
          ];
          claudeOnly = mkHome system [ "claude-code" ];
          selected = map toString claudeOnly.config.home.packages;
          config = both.config.xdg.configFile."herdr/config.toml".source;
        in
        {
          consumer =
            assert builtins.isString both.activationPackage.drvPath;
            assert builtins.isString claudeOnly.activationPackage.drvPath;
            assert builtins.elem (toString (fresh system).claude-code) selected;
            assert !(builtins.elem (toString (fresh system).codex) selected);
            assert !(builtins.elem (toString (fresh system).pi-coding-agent) selected);
            pkgs.runCommand "external-portable-consumer" { nativeBuildInputs = [ pkgs.python3 ]; } ''
                            python3 - ${config} <<'PYTHON'
              import sys, tomllib
              from pathlib import Path
              settings = tomllib.loads(Path(sys.argv[1]).read_text())
              assert settings["update"] == {"version_check": False, "manifest_check": True}
              assert "toast" not in settings["ui"]
              PYTHON
                            cp ${config} "$out"
            '';
        }
      );
    };
}
