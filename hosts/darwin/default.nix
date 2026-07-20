{ config, pkgs, lib, ... }:

let user = "tapani"; in

{
  imports = [
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
  ];

  # Determinate Nix owns the daemon and /etc/nix/nix.conf — that file's own
  # header says "do not modify! this file will be replaced!". So nix-darwin
  # must not try to manage Nix, or the two fight over it.
  #
  # Consequence: everything under `nix.*` is inert, including `nix.gc`.
  # Determinate does NOT garbage collect by default (min-free = 0,
  # max-free = maxint, auto-optimise-store = false), so the store would grow
  # unbounded. GC is reinstated declaratively via launchd below — nix.enable
  # only disables nix-darwin's *Nix* management, not its launchd management.
  #
  # Note `nix.linux-builder` is unavailable while this is false — nix-darwin
  # asserts `nix.linux-builder.enable requires nix.enable`. Determinate's own
  # native Linux builder is gated behind a FlakeHub account plus manual access
  # approval, so neither is usable today. Accepted: dogmatix is x86_64-linux,
  # which a builder here would have to emulate via QEMU anyway, and once it is
  # up it can act as its own native remote builder.
  nix.enable = false;

  # `nix.enable = false` also stops nix-darwin writing /etc/nix/machines, so
  # nix.buildMachines (populated by nix-rosetta-builder) would be configured
  # but never registered, and the builder would sit unused. Determinate's
  # nix.conf does read `builders = @/etc/nix/machines`, so re-render that file
  # ourselves.
  #
  # This mirrors nix-darwin's own renderer in modules/nix/default.nix
  # ("List of machines for distributed Nix builds in the format expected by
  # build-remote.pl") field-for-field:
  #   protocol://sshUser@host  systems  sshKey  maxJobs  speedFactor \
  #   supportedFeatures+mandatoryFeatures  mandatoryFeatures  publicHostKey
  # with "-" standing in for every unset field. Keep in sync if nix-darwin
  # changes it; drop this whole block if nix.enable ever goes back to true.
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

  # Determinate leaves nix.custom.conf for user settings and does not
  # overwrite it, so it can be managed declaratively from here even though
  # nix.conf itself cannot.
  environment.etc."nix/nix.custom.conf".text = ''
    # Managed by nix-darwin. Determinate Nix owns nix.conf and !includes this.
    auto-optimise-store = true

    # `builders` defaults to `@/etc/nix/machines` in Nix itself (verified via
    # `nix config show --json`: value == defaultValue), so rendering that file
    # above is all that is needed to register the builder — nothing has to be
    # set here for it, and it does not depend on Determinate. This one line
    # just lets the builder fetch from binary caches itself rather than
    # round-tripping every path via this Mac.
    builders-use-substitutes = true

    # Disk-pressure GC: collect once free space drops below min-free, freeing
    # up to max-free. Note this only removes unreachable paths — old profile
    # generations are GC roots, so this does NOT prune them. That is why the
    # scheduled nix-collect-garbage below still exists.
    min-free = ${toString (10 * 1024 * 1024 * 1024)}
    max-free = ${toString (50 * 1024 * 1024 * 1024)}
  '';

  # Replaces the old `nix.gc` block, which nix.enable = false makes inert.
  # Not redundant with min-free/max-free above: only --delete-older-than
  # prunes old generations. Sundays at 02:00, same retention as before.
  launchd.daemons.nix-gc = {
    script = ''
      exec /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 30d
    '';
    serviceConfig = {
      RunAtLoad = false;
      StartCalendarInterval = [{ Weekday = 0; Hour = 2; Minute = 0; }];
    };
  };

  system.checks.verifyNixPath = false;

  # nix-darwin now activates system-wide as root; user-scoped options
  # (homebrew, system.defaults.*) apply to system.primaryUser instead.
  system.primaryUser = user;

  environment.systemPackages = with pkgs; [ ]
    ++ (import ../../modules/shared/packages.nix { inherit pkgs; });

  system = {
    # Don't change this, it tracks the initial version installed for internal
    # backwards-compatibility. See https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
    # Before changing this value read the documentation for this option
    # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html)
    stateVersion = 6;

    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        KeyRepeat = 2; # Values: 120, 90, 60, 30, 12, 6, 2
        InitialKeyRepeat = 15; # Values: 120, 94, 68, 35, 25, 15

        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
      };

      dock = {
        autohide = false;
        show-recents = false;
        launchanim = true;
        orientation = "bottom";
        tilesize = 48;
      };

      finder = {
        _FXShowPosixPathInTitle = false;
      };

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
  };
}
