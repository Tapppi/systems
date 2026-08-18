# automatix's module set. Mirrors modules/nixos/dogmatix/ — same split, same
# order — so the two bare-metal hosts read the same way. The one addition is
# t2.nix, which carries everything that is true only because this machine is a
# Mac.
{ ... }:

{
  imports = [
    ../../shared
    ./base.nix
    ./t2.nix
    ./networking.nix
    ./ssh.nix
    ./users.nix
  ];
}
