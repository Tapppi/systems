# TODO: karabiner-elements, rust, go, zig, typescript
# TODO: migrate brewfiles
{
  description = "Starter Configuration for MacOS and NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
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
    nixCats = {
      url = "github:BirdeeHub/nixCats-nvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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

  outputs = { self, darwin, nix-homebrew, homebrew-bundle, homebrew-core, homebrew-cask, home-manager, nixpkgs, disko, nixCats, nvim, nix-rosetta-builder } @inputs:
    let
      user = "tapani";
      linuxSystems = [ "x86_64-linux" "aarch64-linux" ];
      darwinSystems = [ "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs (linuxSystems ++ darwinSystems) f;
      devShell = system: let pkgs = nixpkgs.legacyPackages.${system}; in {
        default = with pkgs; mkShell {
          nativeBuildInputs = with pkgs; [ bashInteractive git ];
          shellHook = with pkgs; ''
            export EDITOR=nvim
          '';
        };
      };
      mkApp = scriptName: system: {
        type = "app";
        program = "${(nixpkgs.legacyPackages.${system}.writeScriptBin scriptName ''
          #!/usr/bin/env bash
          PATH=${nixpkgs.legacyPackages.${system}.git}/bin:$PATH
          echo "Running ${scriptName} for ${system}"
          exec ${self}/apps/${system}/${scriptName}
        '')}/bin/${scriptName}";
      };
      mkLinuxApps = system: {
        "apply" = mkApp "apply" system;
        "build-switch" = mkApp "build-switch" system;
        "copy-keys" = mkApp "copy-keys" system;
        "create-keys" = mkApp "create-keys" system;
        "check-keys" = mkApp "check-keys" system;
        "install" = mkApp "install" system;
      };
      mkDarwinApps = system: {
        "apply" = mkApp "apply" system;
        "build" = mkApp "build" system;
        "build-switch" = mkApp "build-switch" system;
        "copy-keys" = mkApp "copy-keys" system;
        "create-keys" = mkApp "create-keys" system;
        "check-keys" = mkApp "check-keys" system;
        "rollback" = mkApp "rollback" system;
      };
    in
    {
      devShells = forAllSystems devShell;
      apps = nixpkgs.lib.genAttrs linuxSystems mkLinuxApps // nixpkgs.lib.genAttrs darwinSystems mkDarwinApps;

      darwinConfigurations = nixpkgs.lib.genAttrs darwinSystems (system: let
        user = "tapani";
      in
        darwin.lib.darwinSystem {
          inherit system;
          # Spread the inputs as individual module args (upstream starter's
          # convention) *and* expose the whole set as `inputs`, which the
          # home-manager modules take as an argument.
          specialArgs = inputs // { inherit inputs; };
          modules = [
            home-manager.darwinModules.home-manager
            nix-homebrew.darwinModules.nix-homebrew
            inputs.nix-rosetta-builder.darwinModules.default
            {
              nix-homebrew = {
                inherit user;
                enable = true;
                taps = {
                  "homebrew/homebrew-core" = homebrew-core;
                  "homebrew/homebrew-cask" = homebrew-cask;
                  "homebrew/homebrew-bundle" = homebrew-bundle;
                };
                mutableTaps = false;
                autoMigrate = true;
              };
            }
            ./hosts/darwin
          ];
        }
      ) // {
        # Minimal, self-contained config for this Mac (asterix): only nvim +
        # nix-rosetta-builder + the Determinate accommodations. Deliberately
        # does NOT reuse the genAttrs starter above (no home-manager, homebrew,
        # or dock). Used to bring the rosetta Linux builder online. Keyed by
        # hostname, mirroring nixosConfigurations.dogmatix below.
        asterix = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = inputs // { inherit inputs; };
          modules = [
            inputs.nix-rosetta-builder.darwinModules.default
            ./hosts/darwin-minimal
          ];
        };
      };

      nixosConfigurations = nixpkgs.lib.genAttrs linuxSystems (system: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = inputs // { inherit inputs; };
        modules = [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.${user} = import ./modules/nixos/home-manager.nix;
            };
          }
          ./hosts/nixos
        ];
     }) // {
        # Real machines, keyed by hostname. The per-architecture entries above
        # are the upstream starter's untested desktop placeholder.
        dogmatix = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./hosts/nixos/dogmatix ];
        };

        # Workflow-engine bench guests: NixOS LXC system containers under
        # Incus on dogmatix (tieto goldmill/wiki/reviews/bench/). Lifecycle
        # is imperative (`incus launch images:nixos/unstable <name> -p
        # default -p bench-guest`); contents deploy via nixos-rebuild — see
        # modules/nixos/bench/guest-base.nix.
        bench-absurd = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./hosts/nixos/bench-absurd ];
        };
        bench-obs = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./hosts/nixos/bench-obs ];
        };
        bench-temporal = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./hosts/nixos/bench-temporal ];
        };

        # SSH-enabled installer image for headless host onboarding: boots with
        # the Asterix Identity key authorized and sshd up, reachable at
        # konehuone-installer.local. Build the ISO via
        # packages.x86_64-linux.konehuone-installer-iso below.
        konehuone-installer = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./modules/nixos/installer ];
        };
      };

      # Buildable artifacts. The installer ISO needs an x86_64-linux + kvm
      # builder (the Mac's rosetta builder, or dogmatix once up).
      packages.x86_64-linux.konehuone-installer-iso =
        self.nixosConfigurations.konehuone-installer.config.system.build.isoImage;
  };
}
