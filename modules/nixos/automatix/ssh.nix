# sshd. Key auth only — see users.nix for the authorized key.
#
# Identical to modules/nixos/dogmatix/ssh.nix. Kept as its own file per host
# rather than shared, matching the existing layout; if a third bare-metal host
# arrives, this is the first thing worth lifting into a common module.
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
      #
      # nixos-anywhere additionally requires root SSH during onboarding —
      # dropping its kexec phase makes it force the connection user to root
      # regardless of what was passed on the command line.
      PermitRootLogin = "prohibit-password";
    };
  };
}
