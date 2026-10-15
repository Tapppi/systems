# Optional closed-lid server policy; use the hardware export alone for a desktop.
# See README.md for the network, sleep and restart interactions.
{ lib, pkgs, ... }:
{
  # Disable the internal display connector, not merely a console screen saver.
  boot.kernelParams = [ "video=eDP-1:d" ];

  # External-power and docked lid handling have separate precedence in logind;
  # all three must ignore the lid, even when an external display is connected.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "ignore";
    IdleAction = "ignore";
  };

  # Lid policy alone does not block an explicit suspend request. Disable the
  # targets too so an unattended T2 cannot be stranded in an unreliable resume.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # Escalate detected lockups/oopses when no usable hardware watchdog is present.
  # This cannot recover every hang; a firmware reset may also power the host off.
  boot.kernel.sysctl = {
    "kernel.softlockup_panic" = 1;
    "kernel.panic_on_oops" = 1;
    "kernel.panic" = 30;
  };

  # powertop auto-tune can autosuspend the USB NIC carrying the SSH session.
  # A laptop power-saving profile must not silently enable it on this server.
  powerManagement.powertop.enable = lib.mkForce false;
  powerManagement.cpuFreqGovernor = "schedutil";
  services.thermald.enable = true;

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  environment.systemPackages = with pkgs; [
    pciutils
    usbutils
    intel-gpu-tools # verify QSV is actually being used, not silently software
  ];

  # Some T2 firmware powers off on reset. This alias only guards interactive
  # shells; it does not intercept systemctl reboot or kernel panic resets.
  # NixOS prepare-kexec loads the system profile unless a kernel is preloaded;
  # verify that profile before kexec (README.md), not just the boot-menu default.
  environment.shellAliases.reboot = "echo 'On this host reboot powers off — use: systemctl kexec' >&2; false";
}
