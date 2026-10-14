# Headless Apple T2 server profile. Hardware and closed-lid policy are also exported separately.
{ ... }:

{
  imports = [
    ../../shared
    ./base.nix
    ./t2.nix
    ./headless.nix
    ./networking.nix
    ./ssh.nix
  ];
}
