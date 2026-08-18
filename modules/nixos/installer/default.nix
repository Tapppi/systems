# konehuone-installer — SSH-enabled NixOS installer image for headless host
# onboarding, and the DR reinstall stick.
#
# A minimal NixOS installer CD with a fleet-authorized SSH key baked in, sshd
# on at boot, and mDNS so the booted stick is reachable at a predictable
# `.local` name without hunting DHCP leases. Boot it on a headless host and it
# is immediately reachable over SSH with no keyboard or monitor.
#
# It is host-agnostic on purpose: nothing here knows about any particular
# machine's disks. Partitioning is disko's, driven remotely by nixos-anywhere
# from the control host, per ADR-001.
#
# THE ONE LOAD-BEARING LINE IS THE IMPORT BELOW. `installation-cd-minimal.nix`
# pulls in `profiles/installation-device.nix`, which sets
# `system.nixos.variant_id = "installer"`, which lands in /etc/os-release.
# nixos-anywhere reads that and skips its kexec phase, using this running
# environment instead of booting its own generic image over the top. That is
# what makes it possible to onboard hardware whose kernel the generic kexec
# image does not carry. Verify on a booted stick with:
#
#   grep VARIANT_ID /etc/os-release
#
# Drive an install from the control host with:
#
#   nixos-anywhere --flake .#<host> --build-on local \
#     --phases disko,install,reboot --target-host root@konehuone-installer.local
#
# `--build-on local` is not optional from a Mac. Left on `auto`, a failed probe
# falls back to building the entire closure in the target's RAM — after disko
# has already wiped its disks.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

let
  # "Asterix Identity" — asterix's own SSH identity, held in the 1Password
  # agent. This is a PUBLIC key: committing it in plaintext is fine per the
  # decided secrets policy (see konehuone/homelab-automation.md, Secrets), the
  # same key and rationale as modules/nixos/dogmatix/users.nix.  It is the only
  # credential in the image — there is no password on any account.
  asterixIdentity =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmxkJJ/WnwVmYdvylfvp4D+qOAcNMQ/gzFLGkPXVVJ5";
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Reachable as konehuone-installer.local the moment it boots.
  networking.hostName = lib.mkDefault "konehuone-installer";

  # Key-only SSH for root and the live `nixos` user. The installer CD profile
  # already starts sshd; pin the settings so only the embedded key gets in.
  #
  # Root specifically, and not only the `nixos` user: nixos-anywhere reads
  # ~/.ssh/authorized_keys of the account it lands on, and dropping its kexec
  # phase makes it switch the connection user to root regardless of what was
  # passed on the command line.
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
  # konehuone-installer.local without finding its lease on the router. Stock
  # NixOS installer profiles carry no mDNS at all, so this is the difference
  # between one command and an ARP scan.
  #
  # Every stick built from this image answers to the same name — fine when
  # onboarding one machine at a time, ambiguous when two are booted at once.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  # nixos-anywhere runs these on the target and aborts if any is missing. tar,
  # cpio and a GNU setsid that honours --wait come from the stock installer
  # profile and are checked even when the kexec phase is skipped; the rest are
  # ours.
  environment.systemPackages = with pkgs; [
    nixos-install-tools # nixos-install, nixos-enter, nixos-generate-config
    nixos-facter # --generate-hardware-config nixos-facter, without a net fetch
    disko
    jq # disko's zap path shells out to it
    git
    # Hardware identification before committing a disk layout — the one check
    # `nixos-anywhere --vm-test` cannot do for you, since disko's test harness
    # rewrites every device path to /dev/vdX.
    pciutils
    usbutils
    smartmontools
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # ZFS userland, so this image is also the DR stick ADR-004 assumes: a
  # `zfs receive` has to run from the live environment to restore a downed
  # host from the NAS. A pool import needs a hostId even in a live
  # environment.
  boot.supportedFilesystems.zfs = true;
  networking.hostId = "6b0f9a21";

  # The system closure is written straight to /mnt, so what has to fit in the
  # installer's RAM-backed store is the disko script and its dependency
  # closure. zswap buys headroom on thin machines for nothing.
  boot.kernelParams = [
    "zswap.enabled=1"
    "zswap.max_pool_percent=50"
    "zswap.compressor=zstd"
    "zswap.zpool=zsmalloc"
  ];

  # Size. The stick this is written to is 1.87 GiB and the image is already
  # ~1.35 GiB, so the ZFS userland and tooling above have to be paid for
  # somewhere. Dropping the channel is the big lever — it keeps a full nixpkgs
  # checkout out of the image, which a flake-driven install never reads.
  #
  # If it still overruns, the next lever is squashfs compression: the default
  # here is chosen for build speed, and `xz -Xdict-size 100%` trades minutes of
  # build time for a materially smaller image.
  system.installer.channel.enable = false;
  documentation.enable = false;
  documentation.man.man-db.enable = false;
  isoImage.squashfsCompression = "zstd";

  # A distinct volume label so the written stick is recognisable, and the ISO
  # filename carries the image's purpose rather than the generic nixos default.
  # The iso-image module sets image.baseName unconditionally (it, not
  # image.fileName, names the output .iso), so mkForce to override it.
  image.baseName = lib.mkForce "konehuone-installer-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";
  isoImage.volumeID = lib.mkForce "KONEHUONE_INST";
}
