# Boot, locale, nix daemon settings, and the host-level package set.
{ pkgs, ... }:

{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        # systemd-boot copies each generation's kernel + initrd (~100 MB) onto
        # the ESP. The install ESP is ~1 GiB, so keep the generation count low
        # enough that it cannot fill and break boot.
        configurationLimit = 8;
      };
      efi.canTouchEfiVariables = true;
    };
    # Default (LTS-tracking) kernel rather than linuxPackages_latest: the ZFS
    # module (storage.nix) must build against the kernel, and upstream ZFS
    # regularly lags the newest mainline. Alder Lake-N is fully supported by
    # the default kernel.
    kernelPackages = pkgs.linuxPackages;
  };

  time.timeZone = "Europe/Helsinki";

  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_TIME = "fi_FI.UTF-8";
      LC_MONETARY = "fi_FI.UTF-8";
      LC_MEASUREMENT = "fi_FI.UTF-8";
    };
  };

  console.keyMap = "fi";

  hardware.graphics = {
    enable = true;
    # Alder Lake-N iGPU: VA-API for future media transcoding.
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  # Small, slow boot drive — keep the store from growing unattended.
  services.fstrim.enable = true;

  nix = {
    package = pkgs.nix;
    settings = {
      trusted-users = [ "root" "tapani" ];
      substituters = [ "https://nix-community.cachix.org" "https://cache.nixos.org" ];
      trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  programs.zsh.enable = true;

  environment.systemPackages = pkgs.callPackage ./packages.nix { } ++ [
    # Self-install/recovery tooling: a dogmatix system booted from the
    # root-on-USB stick can partition and install the internal eMMC itself
    # (`install-dogmatix-emmc`), making the stick a standalone recovery +
    # reinstall medium with no installer ISO or control machine needed.
    pkgs.nixos-install-tools
    pkgs.parted
    pkgs.dosfstools
    (pkgs.runCommandLocal "konehuone-install-scripts" { } ''
      mkdir -p $out/bin
      cp ${../../../scripts/install-dogmatix-emmc.sh} $out/bin/install-dogmatix-emmc
      chmod +x $out/bin/install-dogmatix-emmc
    '')
  ];

  # Tracks the initial version installed. Must not exceed the nixpkgs this
  # flake builds against — verify with:
  #   nix eval .#nixosConfigurations.dogmatix.config.system.build.toplevel.drvPath
  #
  # 26.11 matches the locked nixos-unstable (26.11-dev). Note the installer ISO
  # is 26.05 — that is fine and irrelevant, the ISO is only an environment to
  # run nixos-install from; the system built is whatever this flake says.
  system.stateVersion = "26.11";
}
