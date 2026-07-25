# Minimal nix-darwin configuration for asterix (M-series Mac, Determinate Nix).
#
# Scope: only what is needed to bring the nix-rosetta-builder Linux builder
# online and provide nvim on PATH. No home-manager, no homebrew, no dock/system
# defaults. The full-featured starter lives in ../darwin/default.nix and is a
# reference for a later migration; this module deliberately does not import it.
#
# The nix-rosetta-builder module (wired in flake.nix) enables by default and
# advertises the kvm + x86_64-linux features required to build NixOS disk
# images (e.g. dogmatix's raw-efi). It populates nix.buildMachines, which the
# hand-rendered /etc/nix/machines below registers with Determinate's daemon.
{ config, pkgs, lib, inputs, ... }:

let user = "tapani"; in

{
  # nvim from the flake's nvim input (nixCats-built package).
  environment.systemPackages = [
    inputs.nvim.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

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

  system.checks.verifyNixPath = false;
  system.primaryUser = user;

  # Tracks the nix-darwin option-default era for backwards compatibility; do
  # not change.
  system.stateVersion = 6;
}
