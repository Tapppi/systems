# dogmatix — Intel N150 mini-PC, always-on low-power homelab substrate.
#
# MVP scope: boots headless, gets a DHCP address on the built-in 2.5GbE, and
# accepts SSH with key auth only. No NAS/router/media services yet — this is a
# test boot on a machine that currently runs something else.
{ pkgs, ... }:

let
  user = "tapani";
  # Taken from ~/.ssh/authorized_keys on asterix. Password auth is disabled
  # below, so this key is the only way in — verify it before installing.
  #
  # NOTE: hosts/nixos/default.nix still carries the dustinlyons starter
  # template's key, which is a third party's. Do not copy it here.
  keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII80FjrMxHj4v1vIH5i8HGplMAVeNvMyMWocjrBIWRhH" ];
in
{
  imports = [
    ./hardware-configuration.nix
    ../../../modules/shared
  ];

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

  networking = {
    hostName = "dogmatix";
    # Both 2.5GbE NICs take DHCP. Interface names are not known until first
    # boot; the global flag covers whatever they turn out to be. Revisit with
    # explicit per-interface config (and static addressing) when this box takes
    # on routing duties.
    useDHCP = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
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

  # 6W TDP always-on box; nothing here should spin up a desktop stack.
  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    # Small, slow boot drive — keep the store from growing unattended.
    fstrim.enable = true;
  };

  nix = {
    package = pkgs.nix;
    settings = {
      trusted-users = [ "root" "${user}" ];
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

  users.users = {
    ${user} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = keys;
    };

    root.openssh.authorizedKeys.keys = keys;
  };

  # PLACEHOLDER — no password is declared for ${user}, so sudo will be unusable
  # until you either set one at the console on first boot (`passwd tapani`) or
  # add `hashedPassword = "$y$..."` above (generate with `mkpasswd -m yescrypt`).
  # Do not switch this to false as a shortcut on an always-on host.
  security.sudo.wheelNeedsPassword = true;

  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    vim
  ];

  # Don't change this — it tracks the initial version installed.
  system.stateVersion = "26.05";
}
