# konehuone-installer — SSH-enabled NixOS installer image for headless host
# onboarding.
#
# A minimal NixOS installer CD with a fleet-authorized SSH key baked in, sshd
# on at boot, and mDNS so the booted stick is reachable at a predictable
# `.local` name without hunting DHCP leases. Boot it on a headless host and it
# is immediately reachable over SSH with no keyboard/monitor — the entry point
# for the homelab onboarding flow (installer USB -> remote probe -> remote
# install from asterix).
#
# The install scripts from ../../../scripts are on PATH inside the live
# environment, so an operator (or asterix over SSH) can run e.g.
# `install-dogmatix-emmc --flake /root/systems` directly.
{ config, lib, pkgs, modulesPath, ... }:

let
  # "Asterix Identity" — asterix's own SSH identity, held in the 1Password
  # agent. This is a PUBLIC key: committing it in plaintext is fine per the
  # decided secrets policy (see konehuone/homelab-automation.md, Secrets), the
  # same key and rationale as modules/nixos/dogmatix/users.nix. It is the only
  # credential in the image — there is no password on any account.
  asterixIdentity =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmxkJJ/WnwVmYdvylfvp4D+qOAcNMQ/gzFLGkPXVVJ5";

  # The onboarding scripts from scripts/, dropped onto PATH under their bare
  # command names. The live installer already provides parted, e2fsprogs,
  # dosfstools, util-linux and nixos-install, which the scripts' `env bash`
  # shebang resolves at run time — no wrapping needed.
  installScripts = pkgs.runCommandLocal "konehuone-install-scripts" { } ''
    mkdir -p $out/bin
    cp ${../../../scripts/install-dogmatix-emmc.sh} $out/bin/install-dogmatix-emmc
    chmod +x $out/bin/install-dogmatix-emmc
  '';
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Reachable as konehuone-installer.local the moment it boots.
  networking.hostName = "konehuone-installer";

  # Key-only SSH for root and the live `nixos` user. The installer CD profile
  # already starts sshd; pin the settings so only the embedded key gets in.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      # Key-based root login is the whole point of this image; no password auth.
      PermitRootLogin = "prohibit-password";
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [ asterixIdentity ];
  users.users.nixos.openssh.authorizedKeys.keys = [ asterixIdentity ];

  # mDNS so the headless, DHCP-addressed installer is reachable as
  # konehuone-installer.local without finding its lease on the router.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # Onboarding scripts on PATH in the live environment.
  environment.systemPackages = [ installScripts ];

  # A distinct volume label so the written stick is recognisable, and the ISO
  # filename carries the image's purpose rather than the generic nixos default.
  # The iso-image module sets image.baseName unconditionally (it, not
  # image.fileName, names the output .iso), so mkForce to override it.
  image.baseName = lib.mkForce "konehuone-installer-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";
  isoImage.volumeID = lib.mkForce "KONEHUONE_INST";
}
