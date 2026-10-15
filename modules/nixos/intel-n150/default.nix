# Intel N150 server profile. The composition supplies identity, filesystems and ZFS pool bindings.
{ ... }:

{
  imports = [
    ../../shared
    ./base.nix
    ./storage.nix
    ./networking.nix
    ./ssh.nix
    ./incus.nix
    ./observability.nix
  ];
}
