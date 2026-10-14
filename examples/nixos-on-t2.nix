# Headless T2 example; the disk path is deliberately not a real device.
{ ... }:
{
  imports = [ ./t2-disko.nix ];
  networking.hostName = "nixos-on-t2";
  users.users.demo = { isNormalUser = true; extraGroups = [ "wheel" ]; };
}
