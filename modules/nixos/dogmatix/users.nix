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
  # Single fleet key: it lives in the 1Password vault, which every control
  # machine (asterix, tmopro18) accesses via the 1Password SSH agent — so one
  # key serves all control machines and lockout is governed by 1Password
  # availability, not per-machine key files.
  keys = [
    # "Asterix Identity" — held in 1Password.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPmxkJJ/WnwVmYdvylfvp4D+qOAcNMQ/gzFLGkPXVVJ5"
  ];
in
{
  users.users = {
    tapani = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = keys;

      # yescrypt hash, safe to commit — it is a hash, not the password.
      # Applies only at account creation; `passwd tapani` afterwards is not
      # undone by a later rebuild.
      initialHashedPassword = "$y$j9T$YevMrl0WUC7YtrDDWmPfz.$EDUz9VrFjcBkl6bBfpRAYMcq201TKxlr.Get6D/gQB9";
    };

    root.openssh.authorizedKeys.keys = keys;
  };

  # Do not switch this to false as a shortcut on an always-on host.
  security.sudo.wheelNeedsPassword = true;
}
