# Boot, locale, nix and the small CLI toolset. The dogmatix equivalent, minus
# everything the apple-t2 module owns — notably boot.kernelPackages, which must
# not be set here: the patched t2linux kernel is the only one that can see this
# machine's keyboard and storage controller.
{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot.loader.systemd-boot = {
    enable = true;
    # Each generation's kernel and initrd is copied to the ESP. 10 against
    # dogmatix's 8, on a 2 GiB ESP rather than 1 GiB, because this host is the
    # builder and rebuilds far more often.
    configurationLimit = 10;
  };

  # ⚠️ Deliberate, T2-specific, and the opposite of what dogmatix sets.
  #
  # Writing EFI variables at runtime is the canonical way to upset a T2 —
  # enabling EFI runtime services on these machines has crashed the kernel
  # since at least 5.x, and the documented workaround is `efi=noruntime`, i.e.
  # give up on NVRAM writes entirely. So the bootloader must never need them.
  #
  # This is NixOS's default, and it is load-bearing rather than incidental:
  # with it false, the systemd-boot builder passes `--no-variables` to
  # `bootctl install`, which still writes both EFI/systemd/systemd-bootx64.efi
  # and the fallback EFI/BOOT/BOOTX64.EFI. That fallback path is exactly what
  # Apple's Startup Manager scans for, so the machine is bootable with no
  # NVRAM entry at all — and stays bootable across an NVRAM reset, which on a
  # Mac is a four-key chord anybody might try while troubleshooting.
  #
  # There is no `efiInstallAsRemovable` to set here: that option belongs to
  # GRUB, and systemd-boot writes the removable path unconditionally.
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

  # /tmp on tmpfs: this host builds, and build trees are exactly the kind of
  # write volume worth keeping off a soldered SSD that cannot be replaced.
  boot.tmp.useTmpfs = true;
  boot.tmp.tmpfsSize = "50%";

  # Root is btrfs — see hosts/nixos/automatix/disko.nix for why. Scrub monthly
  # to catch bitrot on a disk that cannot be swapped out.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Two swap tiers, doing different jobs. zram absorbs cold anonymous pages in
  # compressed RAM with no disk I/O and is what keeps 16 GB responsive under a
  # wide build; the 8 GiB partition in disko.nix is the overflow beneath it, so
  # a `-j6` link step that briefly wants more than the machine has fails slowly
  # instead of being OOM-killed.
  #
  # zramSwap sets priority 5, and the disk partition takes a negative
  # kernel-assigned priority, so the ordering is already right. The high
  # swappiness is deliberate and only makes sense with zram present: it pushes
  # cold pages into compressed RAM eagerly, where reclaiming them is cheap.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
  boot.kernel.sysctl."vm.swappiness" = 180;

  nix = {
    settings = {
      trusted-users = [
        "root"
        "tapani"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # The point of this host. Six cores, twelve threads.
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

  # Matches the nixpkgs this flake is locked to. Do not raise it to chase a
  # newer release; it records the release this host's stateful data was
  # created under.
  system.stateVersion = "26.11";
}
