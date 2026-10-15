# Headless T2 composition; flake.nix supplies disko and the apple-t2 profile.
# Keep its patched kernel, /boot ESP, zram-before-disk swap and USB-driver DHCP
# together. A stock kernel override or blanket DHCP defeats the profile's guards.
# The disk is destructive and synthetic; supply verified identity and SSH grants.
# Composition rationale: ../modules/nixos/apple-t2/README.md.
{ ... }:
{
  imports = [ ./t2-disko.nix ];
  networking.hostName = "nixos-on-t2";
  users.users.demo = { isNormalUser = true; extraGroups = [ "wheel" ]; };
}
