# sshd. Key auth only — see users.nix for the authorized key.
{ ... }:

{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      # Key-only root login: the remote-deploy path (nixos-rebuild
      # --target-host / deploy-rs) and unattended sysadmin from the control
      # machine authenticate as root with the fleet key; password/interactive
      # root auth stays impossible.
      PermitRootLogin = "prohibit-password";
    };
  };
}
