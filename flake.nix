{
  description = "Reusable NixOS, nix-darwin and Home Manager modules with buildable examples";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Same channel as `nixpkgs`, locked separately so fast-moving tools can be
    # refreshed on their own cadence. The main pin stays put because bumping it
    # rebuilds nvim and the Rosetta builder's guest image; agent tooling like
    # herdr ships every week or two and is worth updating far more often than
    # that. Update with `nix flake update nixpkgs-fresh`.
    nixpkgs-fresh.url = "github:nixos/nixpkgs/nixos-unstable";
    # Must follow nixpkgs; left bare it pulls in a second one.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Apple T2 support for Apple T2 hardware, via nixosModules.apple-t2: the patched
    # t2linux kernel that drives the internal keyboard, trackpad and audio, and
    # a derivation that extracts Broadcom wifi firmware from an Apple recovery
    # image so the host needs no surviving macOS install.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nixCats declares no inputs of its own — it takes pkgs from the caller — so
    # it gets no `inputs.nixpkgs.follows`. Adding one is a no-op override and
    # makes Nix warn on every evaluation. The nixpkgs pin that matters for the
    # editor is the one `nvim` follows, just below.
    nixCats.url = "github:BirdeeHub/nixCats-nvim";
    nvim = {
      url = "path:./flakes/nvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixCats.follows = "nixCats";
    };
    # Rosetta 2-backed Linux builder: aarch64-linux natively, x86_64-linux via
    # Rosetta rather than QEMU. Used instead of nix-darwin's built-in
    # nix.linux-builder, which asserts on nix.enable and only emulates x86.
    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, darwin, home-manager, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      mkNixos = { modules, system ? "x86_64-linux", specialArgs ? {} }:
        nixpkgs.lib.nixosSystem {
          inherit system modules;
          specialArgs = inputs // { inherit inputs; } // specialArgs;
        };
      mkDarwin = { modules, system ? "aarch64-darwin", specialArgs ? {} }:
        darwin.lib.darwinSystem {
          inherit system;
          specialArgs = inputs // { inherit inputs; } // specialArgs;
          modules = [ home-manager.darwinModules.home-manager inputs.nix-rosetta-builder.darwinModules.default ] ++ modules;
        };
    in {
      lib = {
        inherit mkNixos mkDarwin;
        userPackages = import ./packages/user-base.nix;
        harnessPackages = import ./packages/harnesses.nix;
        mkHerdrWin = import ./packages/herdr-win.nix;
        mkAgentSkillsSetup = import ./packages/agent-skills-setup.nix;
      };
      nixosModules = {
        intel-n150 = ./modules/nixos/intel-n150;
        apple-t2 = ./modules/nixos/apple-t2;
        apple-t2-hardware = ./modules/nixos/apple-t2/t2.nix;
        headless-t2 = ./modules/nixos/apple-t2/headless.nix;
        lxc-guest = ./modules/nixos/lxc-guest.nix;
        installer = ./modules/nixos/installer/default.nix;
        installer-t2 = ./modules/nixos/installer/t2.nix;
        speech = ./modules/nixos/services/speech;
        archive = ./modules/nixos/services/archive;
        bench-absurd = ./modules/nixos/services/bench-absurd;
        bench-load = ./modules/nixos/services/bench-load;
        bench-obs = ./modules/nixos/services/bench-obs;
        bench-temporal = ./modules/nixos/services/bench-temporal;
      };
      darwinModules = {
        workstation = ./modules/darwin/workstation.nix;
        hammerspoon = ./modules/darwin/hammerspoon;
        codex = ./modules/darwin/codex.nix;
        herdr = ./modules/darwin/herdr.nix;
        session-sync = ./modules/darwin/session-sync.nix;
        agent-reaper = ./modules/darwin/agent-reaper;
        opencode = ./modules/darwin/opencode.nix;
        devenv = ./modules/darwin/devenv.nix;
        pi-coding-agent = ./modules/darwin/pi-coding-agent.nix;
      };
      homeManagerModules = {
        workstationFiles = ./modules/home-manager/workstation-files.nix;
        portableUser = ./modules/home-manager/portable-user.nix;
        herdr = ./modules/home-manager/herdr.nix;
        agentSkills = ./modules/home-manager/agent-skills.nix;
      };
      packages = forAllSystems (system: {
        agent-skills-setup = self.lib.mkAgentSkillsSetup { pkgs = nixpkgs.legacyPackages.${system}; };
      });
      apps = forAllSystems (system: {
        agent-skills-setup = {
          type = "app";
          program = "${self.packages.${system}.agent-skills-setup}/bin/agent-skills-setup";
        };
      });
      devShells = forAllSystems (system: {
        default = nixpkgs.legacyPackages.${system}.mkShell {
          nativeBuildInputs = with nixpkgs.legacyPackages.${system}; [ bashInteractive git ];
        };
      });
      checks = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          agent-skills-setup = import ./tests/agent-skills/check.nix { inherit self inputs system pkgs; };
          portable-user = import ./tests/portable-user.nix { inherit self inputs system pkgs; };
          bench-observability = import ./modules/nixos/services/bench-obs/tests/check.nix {
            inherit nixpkgs pkgs;
          };
          hammerspoon-lua =
            let
              # The stub the module generates, built with test values so the
              # suite can execute the real thing rather than a copy of it.
              #
              # cfgDir is a placeholder substituted with a path inside the build
              # directory. The stub prepends <cfgDir>/lua to package.path ahead
              # of everything else, so a fixed /tmp name would let any local
              # process shadow the modules under test — and this flake is built
              # without the sandbox.
              #
              # The bundle the stub hard-codes. Restated here so the spec fails
              # if that ever changes to something not present on every Mac.
              stubFallback = "com.apple.Safari";
              stub = pkgs.writeText "hammerspoon-init-under-test.lua"
                (import ./modules/darwin/hammerspoon/stub.nix { cfgDir = "@stubCfgDir@"; });
            in
            pkgs.runCommand "hammerspoon-lua-check"
            { nativeBuildInputs = [ pkgs.lua5_4 pkgs.stylua ]; } ''
            cp -r ${./modules/darwin/hammerspoon/lua} lua
            cp -r ${./modules/darwin/hammerspoon/tests} tests
            cp ${./stylua.toml} stylua.toml
            chmod -R u+w lua tests

            stubCfgDir="$PWD/cfg"
            mkdir -p "$stubCfgDir/lua/lua"
            substitute ${stub} stub.lua --replace-fail '@stubCfgDir@' "$stubCfgDir"

            # find, not a glob: subdirectories must be checked too.
            find lua tests -name '*.lua' -print0 | xargs -0 -n1 luac -p
            luac -p stub.lua

            stylua --check lua tests

            # The Lua is symlinked out of the store, so no build ever loads it.
            # This is the only thing that runs it: a stub `hs` exercises the
            # profile matching, the launch argv and the picker sequencing.
            # HOME is set because the modules derive the Local State paths from
            # it, and the sandbox provides none.
            # $PWD/?.lua resolves the stub's dotted require("lua.router") and
            # require("lua.init"); fixtures/ resolves its require("hs.ipc").
            HOME="$PWD/fakehome" lua \
              -e "HARNESS='$PWD/tests/harness.lua'" \
              -e "STUBLUA='$PWD/stub.lua'" \
              -e "STUBCFGDIR='$stubCfgDir'" \
              -e "STUBFALLBACK='${stubFallback}'" \
              -e "package.path='$PWD/?.lua;$PWD/lua/?.lua;$PWD/tests/fixtures/?.lua;'..package.path" \
              tests/spec.lua

            touch "$out"
          '';
        });

      nixosConfigurations = {
        nixos-intel-n150 = mkNixos { modules = [ self.nixosModules.intel-n150 ./examples/nixos-intel-n150.nix ]; };
        nixos-on-t2 = mkNixos { modules = [ self.nixosModules.apple-t2 inputs.disko.nixosModules.disko ./examples/nixos-on-t2.nix ]; };
      };
      darwinConfigurations.apple-silicon-host = mkDarwin {
        modules = [ self.darwinModules.workstation ./examples/apple-silicon-host.nix ];
      };
      # Generic builders are selected through exported modules. Fleet ISO names
      # and authorized access keys belong to the composing repository.
    };
}
