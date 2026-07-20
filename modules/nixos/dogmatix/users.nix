# The single human user on the box.
{ pkgs, ... }:

let
  # Taken from ~/.ssh/authorized_keys on asterix. Password auth over SSH is
  # disabled in ssh.nix, so this key is the only way in remotely — verify it
  # before installing.
  #
  # NOTE: hosts/nixos/default.nix still carries the dustinlyons starter
  # template's key, which is a third party's. Do not copy it here.
  keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII80FjrMxHj4v1vIH5i8HGplMAVeNvMyMWocjrBIWRhH" ];
in
{
  users.users = {
    tapani = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = keys;

      # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      # !!!  INSECURE PLACEHOLDER — CHANGE THIS ON FIRST CONSOLE LOGIN.   !!!
      # !!!                                                              !!!
      # !!!  This password exists ONLY so the machine is usable at the    !!!
      # !!!  physical console (and for sudo) before SSH works. It is      !!!
      # !!!  stored in PLAINTEXT in the world-readable nix store, so it   !!!
      # !!!  is effectively public.                                      !!!
      # !!!                                                              !!!
      # !!!  On first boot:   passwd tapani                              !!!
      # !!!  Then replace this line with a hash:                          !!!
      # !!!      mkpasswd -m yescrypt                                     !!!
      # !!!      initialHashedPassword = "$y$...";                        !!!
      # !!!  (initialPassword/initialHashedPassword only apply when the   !!!
      # !!!   account is first created, so `passwd` is not undone by a    !!!
      # !!!   later rebuild — but leaving this here is still bad.)        !!!
      # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
      initialPassword = "changeme";
    };

    root.openssh.authorizedKeys.keys = keys;
  };

  # Do not switch this to false as a shortcut on an always-on host.
  security.sudo.wheelNeedsPassword = true;
}
