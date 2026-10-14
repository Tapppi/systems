# Generic SSH-enabled minimal installer capability. Supply hostName, hostId, keys and image labels.
# installation-cd-minimal sets VARIANT_ID=installer, required by nixos-anywhere no-kexec onboarding.
# This module builds an image; it never partitions or activates a machine.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  nixpkgs.overlays = [ (import ../../../overlays/20-rsync.nix) ];


  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };


  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  environment.systemPackages = with pkgs; [
    nixos-install-tools # nixos-install, nixos-enter, nixos-generate-config
    nixos-facter # --generate-hardware-config nixos-facter, without a net fetch
    disko
    jq # disko's zap path shells out to it
    git
    pciutils
    usbutils
    smartmontools
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  boot.supportedFilesystems.zfs = true;

  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.max_pool_percent=50"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
  ];

  system.installer.channel.enable = false;
  documentation.enable = false;
  documentation.man.man-db.enable = false;
  isoImage.squashfsCompression = "zstd";

}
