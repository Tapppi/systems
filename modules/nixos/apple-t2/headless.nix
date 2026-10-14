# Optional headless T2 laptop policy: disable panel/sleep, keep USB networking awake, and use kexec.
# Firmware may power off instead of rebooting; the reboot alias refuses that ambiguous operation.
# Panic sysctls prevent a soft-lockup from leaving an unreachable host indefinitely.
{ lib, pkgs, ... }:
{
  boot.kernelParams = [ "video=eDP-1:d" ];

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "ignore";
    IdleAction = "ignore";
  };

  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  boot.kernel.sysctl = {
    "kernel.softlockup_panic" = 1;
    "kernel.panic_on_oops" = 1;
    "kernel.panic" = 30;
  };

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

  environment.shellAliases.reboot = "echo 'On this host reboot powers off — use: systemctl kexec' >&2; false";
}
