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
    # Apple T2 support for automatix, via nixosModules.apple-t2: the patched
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

  outputs = { self, darwin, nix-homebrew, homebrew-bundle, homebrew-core, homebrew-cask, home-manager, nixpkgs, disko, nixCats, nvim, nix-rosetta-builder, nixos-hardware } @inputs:
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
          # Pass arguments, e.g. `nix run .#build-switch -- --dry-run`.
          exec ${self}/apps/${system}/${scriptName} "$@"
        '')}/bin/${scriptName}";
      };
      # Only apps that exist under apps/<system>/ (aarch64-linux is a symlink to
      # x86_64-linux). The starter also declared these, kept here as a record of
      # what it modelled — none had a script in this repo, so they could only
      # ever fail at exec:
      #
      #   "install"     = mkApp "install" system;      # bare-metal NixOS installer.
      #                     Superseded by scripts/install-dogmatix-emmc.sh; the
      #                     steady-state entrypoints are build-switch/rollback.
      #   "copy-keys"   = mkApp "copy-keys" system;    # ~/.ssh/id_ed25519{,_agenix}
      #   "create-keys" = mkApp "create-keys" system;  #   from/to a USB stick, for
      #   "check-keys"  = mkApp "check-keys" system;   #   the starter's agenix flow.
      #                     Secrets are going to 1Password now and a homelab manager
      #                     (vaultwarden?) later — see ADR-003 — so files-on-disk key
      #                     scripts are not the model we want; what to keep is how
      #                     they were wired, not the scripts.
      #
      #   "apply"       = mkApp "apply" system;        # token substitution. The
      #                     NixOS %HOST%/%DISK%/%INTERFACE% placeholders it fills are
      #                     still live, but it seds every file under the cwd including
      #                     .git — see apps/aarch64-darwin/apply. ADR-002 retires the
      #                     starter tree rather than fixing it.
      # NOTE build-switch is itself still the starter's: it resolves the target
      # from `uname -m` and switches to nixosConfigurations.<arch>, the untested
      # placeholder, rather than to a hostname-keyed host like dogmatix. It is
      # also non-executable, so it cannot currently run. Fix the target before
      # arming it — the placeholder's `keys` list is now empty, so activating it
      # would leave a host with no authorized SSH keys. Real deploys are
      # push-based (HLB-9) via remote nixos-rebuild.
      mkLinuxApps = system: {
        "build-switch" = mkApp "build-switch" system;
      };
      # Only apps used on darwin.
      mkDarwinApps = system: {
        "build" = mkApp "build" system;
        "build-switch" = mkApp "build-switch" system;
        "rollback" = mkApp "rollback" system;
      };
    in
    {
      devShells = forAllSystems devShell;
      apps = nixpkgs.lib.genAttrs linuxSystems mkLinuxApps // nixpkgs.lib.genAttrs darwinSystems mkDarwinApps;

      # Keyed by hostname only. The upstream starter's per-architecture entry is
      # not instantiated: it would override configuration that tapppi/macos-setup
      # still manages. See ./hosts/darwin/default.nix for that example config and
      # the flake wiring it used.
      darwinConfigurations = {
        # Minimal, self-contained config for this Mac (asterix): nvim, neovide
        # and nix-rosetta-builder plus the Determinate accommodations.
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

        # automatix — the 2018 MacBook Pro, an Apple T2 machine, run headless
        # as the fleet's x86_64-linux builder and media host. The only host
        # here that uses disko: nixos-anywhere requires it, and ADR-001 makes
        # nixos-anywhere the onboarding path. See hosts/nixos/automatix.
        automatix = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [
            # Supplies system.build.diskoScript, which nixos-anywhere runs to
            # partition, and system.build.installTest, which is what
            # `nixos-anywhere --vm-test` builds.
            disko.nixosModules.disko
            ./hosts/nixos/automatix
          ];
        };

        # The speech guest: Kokoro-82M behind the OpenAI /v1/audio/speech
        # contract for the vault's aloud-tts plugin, as a digest-pinned OCI
        # image under podman. Same imperative lifecycle as the other guests,
        # plus the podman-guest Incus profile — see hosts/nixos/tts.
        tts = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./hosts/nixos/tts ];
        };

        # The archive guest: agent session transcripts mirrored off the Macs
        # and host data evacuated from tmopro18, on an Incus custom storage
        # volume attached at /data. Same imperative lifecycle as the bench
        # guests — see modules/nixos/lxc-guest.nix.
        arkisto = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./hosts/nixos/arkisto ];
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

        # The same installer plus the patched t2linux kernel, for Apple T2
        # Macs whose internal keyboard a stock kernel cannot see. Separate
        # artifact so that onboarding any other host does not depend on a
        # third-party binary cache — see modules/nixos/installer/t2.nix.
        konehuone-installer-t2 = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = inputs // { inherit inputs; };
          modules = [ ./modules/nixos/installer/t2.nix ];
        };
      };

      # Buildable artifacts. The installer ISO needs an x86_64-linux + kvm
      # builder (the Mac's rosetta builder, or dogmatix once up).
      packages.x86_64-linux.konehuone-installer-iso =
        self.nixosConfigurations.konehuone-installer.config.system.build.isoImage;
      packages.x86_64-linux.konehuone-installer-t2-iso =
        self.nixosConfigurations.konehuone-installer-t2.config.system.build.isoImage;
  };
}
