# Minimal nix-darwin configuration for asterix (M-series Mac, Determinate Nix).
#
# Scope: what is needed to bring the nix-rosetta-builder Linux builder online,
# provide nvim (plus its GUI, neovide) on PATH, and mirror this Mac's agent
# session transcripts to the homelab archive. No home-manager, no homebrew, no
# dock/system defaults. The full-featured starter lives in ../darwin/default.nix
# and is a reference for a later migration; this module deliberately does not
# import it.
#
# The nix-rosetta-builder module (wired in flake.nix) enables by default and
# advertises the kvm + x86_64-linux features required to build NixOS disk
# images (e.g. dogmatix's raw-efi). It populates nix.buildMachines, which the
# hand-rendered /etc/nix/machines below registers with Determinate's daemon.
# It is configured on-demand rather than always-resident — see the Linux builder
# section below.
{ config, pkgs, lib, inputs, ... }:

let
  user = "tapani";

  # Must match the darwinConfigurations attribute name in flake.nix — the apps
  # in apps/aarch64-darwin/ look the host up by the machine's own name.
  hostname = "asterix";

  # nvim from the flake's nvim input (nixCats-built package).
  nvim = inputs.nvim.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Neovide resolves plain `nvim` from $PATH by default, which is wrong in two
  # ways here. Launched from Finder/Dock/Spotlight it inherits launchd's PATH
  # (/usr/bin:/bin:/usr/sbin:/sbin), where no nvim exists at all — and macos-setup's
  # tasks/config.sh registers com.neovide.neovide as the duti editor for dozens
  # of file types, so GUI launches are the common case rather than the exception.
  # Launched from a shell it would pick up whatever nvim happens to be first on
  # PATH. Pin --neovim-bin to the nixCats build so every launch context gets the
  # configured editor.
  #
  # Upstream ships Neovide.app/Contents/MacOS as a relative symlink to
  # ../../../bin, so the bundle's CFBundleExecutable and the CLI entry point are
  # the same file. Copying the bundle preserves that symlink — now pointing at
  # this derivation's own bin/ — so wrapping bin/neovide once covers both the
  # shell invocation and the LaunchServices one.
  neovide = pkgs.stdenv.mkDerivation {
    pname = "neovide-wrapped";
    inherit (pkgs.neovide) version;

    nativeBuildInputs = [ pkgs.makeWrapper ];
    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin"
      cp -R ${pkgs.neovide}/Applications "$out/Applications"
      chmod -R u+w "$out/Applications"

      makeWrapper ${pkgs.neovide}/bin/neovide "$out/bin/neovide" \
        --add-flags "--neovim-bin ${nvim}/bin/nvim"

      runHook postInstall
    '';

    meta = pkgs.neovide.meta // {
      description = "${pkgs.neovide.meta.description} (pinned to the nixCats nvim)";
    };
  };
in

{
  imports = [
    ../../modules/darwin/session-sync.nix
    ../../modules/darwin/herdr.nix
  ];

  environment.systemPackages = [ nvim neovide ];

  # --- Linux builder ---

  # The module's default is a KeepAlive launchd daemon, so the VM runs whether or
  # not anything is building — on a laptop that is a permanently resident ~1.4GB
  # and a steady CPU trickle for the sake of builds that happen a few times a
  # month. onDemand swaps that for socket activation: the VM is off at rest and
  # boots itself when a Linux build arrives, then powers off again once idle.
  # A cold build blocks for the boot rather than failing — measured at 19s from
  # a powered-off VM, against 2s warm.
  #
  # 15 minutes rather than the module's 180: the linger only needs to span the
  # gaps *within* a working session on dogmatix or the bench hosts, and paying
  # three hours of resident VM for one build defeats the point of onDemand.
  #
  # Caveat worth knowing before it bites: the daemon's start script compares the
  # rendered lima.yaml against the deployed one and, on any difference, deletes
  # and recreates the VM instead of booting it. The yaml embeds the guest disk
  # image's store path, so a nixpkgs bump — or touching cores/memory/diskSize/
  # onDemandLingerMinutes, which rebuild that image — makes the next wake a
  # multi-minute re-create. A Linux build that lands in that window can fail
  # outright ("Cannot build … platform mismatch") because nix's build hook gives
  # up before the VM exists; re-running it then succeeds. Enabling onDemand did
  # exactly this once. To absorb it deliberately, run `builder up` (macos-setup
  # .functions) after a switch that changed the builder.
  nix-rosetta-builder = {
    onDemand = true;
    onDemandLingerMinutes = 15;
  };

  # --- Four Determinate-Nix accommodations (mirrored from ../darwin/default.nix;
  # keep the machines renderer in sync if nix-darwin's own format changes) ---

  # Determinate Nix owns the daemon and /etc/nix/nix.conf, so nix-darwin must
  # not manage Nix. Everything under `nix.*` becomes inert as a result.
  nix.enable = false;

  # `nix.enable = false` stops nix-darwin writing /etc/nix/machines, so
  # nix.buildMachines (populated by nix-rosetta-builder) would be configured but
  # never registered. Determinate's nix.conf reads `builders = @/etc/nix/machines`,
  # so re-render that file field-for-field as nix-darwin's own renderer does:
  #   protocol://sshUser@host  systems  sshKey  maxJobs  speedFactor \
  #   supportedFeatures+mandatoryFeatures  mandatoryFeatures  publicHostKey
  # with "-" standing in for every unset field.
  environment.etc."nix/machines" =
    lib.mkIf (config.nix.buildMachines != [ ]) {
      text = lib.concatMapStrings
        (machine: (lib.concatStringsSep " " [
          ("${lib.optionalString (machine.protocol != null) "${machine.protocol}://"}"
            + "${lib.optionalString (machine.sshUser != null) "${machine.sshUser}@"}"
            + machine.hostName)
          (if machine.system != null then machine.system
           else if machine.systems != [ ] then lib.concatStringsSep "," machine.systems
           else "-")
          (if machine.sshKey != null then machine.sshKey else "-")
          (toString machine.maxJobs)
          (toString machine.speedFactor)
          (let res = machine.supportedFeatures ++ machine.mandatoryFeatures;
           in if res == [ ] then "-" else lib.concatStringsSep "," res)
          (let res = machine.mandatoryFeatures;
           in if res == [ ] then "-" else lib.concatStringsSep "," res)
          (if machine.publicHostKey != null then machine.publicHostKey else "-")
        ]) + "\n")
        config.nix.buildMachines;
    };

  # Determinate leaves nix.custom.conf for user settings and !includes it, so it
  # can be managed declaratively even though nix.conf itself cannot.
  environment.etc."nix/nix.custom.conf".text = ''
    # Managed by nix-darwin. Determinate Nix owns nix.conf and !includes this.
    auto-optimise-store = true

    # `builders` defaults to `@/etc/nix/machines` in Nix itself, so rendering
    # that file above is all that is needed to register the builder. This line
    # lets the builder fetch from binary caches directly rather than
    # round-tripping every path via this Mac.
    builders-use-substitutes = true

    # The t2linux kernel automatix needs (modules/nixos/automatix/t2.nix). It
    # is not in cache.nixos.org, and building it from source is hours on the
    # Rosetta builder.
    #
    # It has to live here rather than being passed as `--extra-substituters`
    # on the command line: this Mac's `trusted-users` is root only, so the
    # daemon accepts that flag from the CLI and then silently ignores it —
    # `nix config show` reports the substituter as active while substitution
    # quietly falls back to building. The failure looks like an unexplained
    # multi-hour compile rather than an error.
    extra-substituters = https://cache.soopy.moe
    extra-trusted-public-keys = cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo=

    # Disk-pressure GC: collect once free space drops below min-free, freeing up
    # to max-free. Removes only unreachable paths; old profile generations are
    # GC roots, so the scheduled nix-collect-garbage below still prunes those.
    min-free = ${toString (10 * 1024 * 1024 * 1024)}
    max-free = ${toString (50 * 1024 * 1024 * 1024)}
  '';

  # Scheduled GC via launchd, because `nix.gc` is inert under
  # nix.enable = false. Only --delete-older-than prunes old generations.
  # Sundays at 02:00.
  launchd.daemons.nix-gc = {
    script = ''
      exec /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 30d
    '';
    serviceConfig = {
      RunAtLoad = false;
      StartCalendarInterval = [{ Weekday = 0; Hour = 2; Minute = 0; }];
    };
  };

  # --- Base darwin requirements ---

  # Set machine names on activation. The machine name is what apps/ resolves the
  # darwinConfigurations entry from, so it must not drift: localHostName defaults
  # to hostName, but mDNSResponder rewrites it (asterix -> asterix-2) on a
  # Bonjour name conflict on the LAN, so state it explicitly to put it back.
  networking = {
    hostName = hostname;
    localHostName = hostname;
    # Display name only; hostName is the source of truth.
    computerName = lib.toSentenceCase hostname;
  };

  system.checks.verifyNixPath = false;
  system.primaryUser = user;

  # Tracks the nix-darwin option-default era for backwards compatibility; do
  # not change.
  system.stateVersion = 6;
}
