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
          # "$@" matters: without it every flag passed as `nix run .#x -- --flag`
          # is silently dropped, so e.g. `nix run .#build-switch -- --dry-run`
          # would activate the system for real.
          exec ${self}/apps/${system}/${scriptName} "$@"
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
      # Only apps that actually exist under apps/aarch64-darwin/. The starter
      # also declared apply/copy-keys/create-keys/check-keys, but no such
      # scripts are present for darwin, so those attributes could only ever
      # fail at exec. `apply` in particular is the starter's token-substitution
      # script — see apps/aarch64-darwin/apply for why it stays unwired.
      mkDarwinApps = system: {
        "build" = mkApp "build" system;
        "build-switch" = mkApp "build-switch" system;
        "rollback" = mkApp "rollback" system;
      };
    in
    {
      devShells = forAllSystems devShell;
      apps = nixpkgs.lib.genAttrs linuxSystems mkLinuxApps // nixpkgs.lib.genAttrs darwinSystems mkDarwinApps;

      # Keyed by hostname only. The upstream starter's per-architecture entry
      # (darwinConfigurations.aarch64-darwin, built from ./hosts/darwin) is
      # deliberately NOT instantiated here: it has never been activated, and
      # switching to it would hand the Homebrew install that tapppi/macos-setup
      # manages over to nix-homebrew. ./hosts/darwin and modules/darwin/ remain
      # on disk as the reference for the eventual full migration; re-add an
      # entry here when one of them is actually ready to activate.
      darwinConfigurations = {
        # Minimal, self-contained config for this Mac (asterix): nvim, neovide
        # and nix-rosetta-builder plus the Determinate accommodations. Mirrors
        # nixosConfigurations.dogmatix below in being hostname-keyed.
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
        bench-load = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./hosts/nixos/bench-load ];
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
