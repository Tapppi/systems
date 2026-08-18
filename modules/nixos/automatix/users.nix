# The single human user on the box.
{ pkgs, ... }:

let
  # "Asterix Identity" — asterix's own SSH identity, held in the 1Password
  # agent. Password auth over SSH is disabled in ssh.nix, so this key is the
  # only way in remotely.
  #
  # Single fleet key, the same string as modules/nixos/dogmatix/users.nix and
  # modules/nixos/lxc-guest.nix: it lives in the 1Password vault that every
  # control machine reaches through the 1Password SSH agent, so one key serves
  # all control machines and lockout is governed by 1Password availability
  # rather than by per-machine key files.
  #
  # This matters more here than on dogmatix. That host has a keyboard and a
  # monitor port; this one runs lid-shut with the internal panel disabled at
  # the DRM level and its internal keyboard driven by an out-of-tree module.
  # Losing SSH means opening the lid and attaching a USB keyboard, not typing
  # at a console that is already there.
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
      # undone by a later rebuild. Same hash as dogmatix.
      initialHashedPassword = "$y$j9T$YevMrl0WUC7YtrDDWmPfz.$EDUz9VrFjcBkl6bBfpRAYMcq201TKxlr.Get6D/gQB9";
    };

    root.openssh.authorizedKeys.keys = keys;
  };

  # Do not switch this to false as a shortcut on an always-on host.
  security.sudo.wheelNeedsPassword = true;
}
