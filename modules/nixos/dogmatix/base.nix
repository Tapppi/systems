# Boot, locale, nix daemon settings, and the host-level package set.
{ pkgs, ... }:

{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 20;
      };
      efi.canTouchEfiVariables = true;
    };
    kernelPackages = pkgs.linuxPackages_latest;
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

  environment.systemPackages = pkgs.callPackage ./packages.nix { };

  # Don't change this — it tracks the initial version installed.
  system.stateVersion = "26.05";
}
