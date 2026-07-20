# dogmatix module set.
#
# Deliberately does NOT import ../../nixos or ../../shared beyond `shared`'s
# nixpkgs config: the starter's nixos modules are X11-desktop-shaped and this
# is a headless 6W box. Keep these modules plain — no option abstractions.
{ ... }:

{
  imports = [
    ../../shared
    ./base.nix
    ./networking.nix
    ./ssh.nix
    ./users.nix
    ./incus.nix
  ];
}
