# Intel N150 boot, locale, graphics and maintenance policy.
# The LTS kernel keeps ZFS compatible; retain eight boot generations on a 1 GiB ESP.
{ pkgs, ... }:

{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 8;
      };
      efi.canTouchEfiVariables = true;
    };
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
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  services.fstrim.enable = true;

  nix = {
    package = pkgs.nix;
    settings = {
      trusted-users = [ "root" ];
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
    pkgs.nixos-install-tools
    pkgs.parted
    pkgs.dosfstools

  ];

  system.stateVersion = "26.11";
}
