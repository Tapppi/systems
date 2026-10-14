# Boot and memory policy for the headless T2 profile.
# Keep boot.kernelPackages owned by t2.nix; see README.md for composition constraints.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot.loader.systemd-boot = {
    enable = true;
    # Size the ESP with this limit: each retained generation copies its kernel/initrd there.
    configurationLimit = 10;
  };

  # Avoid T2 EFI-variable writes. systemd-boot still installs EFI/BOOT/BOOTX64.EFI;
  # boot discovery must work through that fallback, without a saved NVRAM entry.
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

  # zram defaults to priority 5, above the composition's unprioritized disk swap.
  # Keep that ordering: swappiness 180 favors cheap compressed-RAM reclaim,
  # while disk swap is the overflow tier for memory-heavy builds.
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
