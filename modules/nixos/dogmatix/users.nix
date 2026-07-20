# The single human user on the box.
{ pkgs, ... }:

let
  # "Asterix Identity" — asterix's own SSH identity, held in the 1Password
  # agent. Password auth over SSH is disabled in ssh.nix, so this key is the
  # only way in remotely.
  #
  # To retrieve it again, note that ssh-add ignores IdentityAgent from
  # ssh_config and only honours $SSH_AUTH_SOCK:
  #   SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock" ssh-add -L
  #
  # Do NOT use, despite both looking plausible:
  #   - "Asterix Git Sign" — commit signing key, not for auth
  #   - the key in ~/.ssh/authorized_keys — that is a key allowed *into*
  #     asterix (tmopro18's), not asterix's own identity
  #   - the key in hosts/nixos/default.nix — the dustinlyons starter
  #     template's, and a third party's
  keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmxkJJ/WnwVmYdvylfvp4D+qOAcNMQ/gzFLGkPXVVJ5" ];
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
