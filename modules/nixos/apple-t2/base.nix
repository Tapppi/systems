# T2 server boot, compressed swap and build-host maintenance policy.
# EFI variable writes must stay disabled: systemd-boot writes the removable fallback path without NVRAM.
# zram absorbs cold memory ahead of the disk swap declared by the composition.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 10;
  };

  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.efi.efiSysMountPoint = "/boot";

  time.timeZone = "Europe/Helsinki";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fi_FI.UTF-8";
    LC_MEASUREMENT = "fi_FI.UTF-8";
    LC_MONETARY = "fi_FI.UTF-8";
    LC_NAME = "fi_FI.UTF-8";
    LC_NUMERIC = "fi_FI.UTF-8";
    LC_PAPER = "fi_FI.UTF-8";
    LC_TELEPHONE = "fi_FI.UTF-8";
    LC_TIME = "fi_FI.UTF-8";
  };
  console.keyMap = "fi";

  services.fstrim.enable = true;

  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
  boot.kernel.sysctl."vm.swappiness" = 180;

  nix = {
    settings = {
      trusted-users = [
        "root"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      max-jobs = lib.mkDefault 6;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  programs.zsh.enable = true;

  environment.systemPackages = with pkgs; [
    git
    htop
    tmux
    rsync
    curl
    jq
    lm_sensors # thermals matter on a laptop chassis running lid-shut
    smartmontools
  ];

  system.stateVersion = "26.11";
}
