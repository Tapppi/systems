# Everything that is true only because this machine is an Apple T2 Mac.
#
# The T2 is a coprocessor sitting between the OS and the internal keyboard,
# trackpad, audio, camera, Touch Bar and storage controller. Mainline Linux
# does not drive it; the t2linux patch set does, via `apple-bce`. nixos-hardware
# packages that as `apple-t2`, which sets boot.kernelPackages to a patched
# kernel — so nothing here may override kernelPackages, unlike dogmatix which
# pins the LTS series for ZFS.
#
# This host runs headless with the lid shut and no display attached. Most of
# the configuration below exists to make that safe rather than to make the
# laptop pleasant, and several settings would be wrong on a machine somebody
# sits in front of.
{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [ inputs.nixos-hardware.nixosModules.apple-t2 ];

  hardware.apple-t2 = {
    kernelChannel = "stable";

    # This model ships an AMD Radeon Pro 555X/560X alongside the UHD 630, and
    # firmware hands Linux the discrete GPU as primary. Left alone that costs
    # roughly 12 W of the ~24 W idle draw for a GPU nothing uses. It is also
    # the wrong GPU for us: the whole reason media lives on this host is the
    # UHD 630's QSV transcode path.
    enableIGPU = true;

    # Broadcom wifi and bluetooth firmware, built declaratively. The derivation
    # downloads a macOS recovery image from Apple and extracts the firmware
    # from it inside a VM, so it does not depend on this machine's own macOS
    # install and survives the wipe. That is the whole reason the wipe is not
    # gated on extracting firmware by hand first.
    #
    # Enabled despite the host being ethernet-only: the adapter is a single
    # USB dongle on a machine with no other network path, and wifi is the only
    # fallback that does not require standing at it.
    firmware.enable = true;

    # ventura, not the module's `sonoma` default, and this is load-bearing
    # rather than a preference. Against the sonoma image, nixos-hardware's
    # `get-wifi` extractor dies on `assert not props` — the plist carries
    # properties it does not expect — and the build VM then panics when its
    # init exits. That failure is not local to the firmware: it takes the
    # whole system closure with it, so the host will not build at all.
    #
    # ventura yields the complete set for this machine — BCM4364 rev B2 on
    # board `ekans`, including the .bin, .clm_blob, .txcap_blob and the
    # per-region HRPN tables.
    firmware.version = "ventura";
  };

  # Without this the patched kernel is compiled from source, which is hours on
  # any machine in this fleet. Scoped to this host rather than set globally:
  # it is a third-party cache and only this host's closure needs it.
  nix.settings = {
    extra-substituters = [ "https://cache.soopy.moe" ];
    extra-trusted-public-keys = [
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };

  # The internal panel never lights. Disabling the connector at the DRM level
  # rather than just blanking it also stops the Touch Bar and backlight drawing
  # power behind a closed lid, and avoids OLED burn-in on the Touch Bar.
  boot.kernelParams = [ "video=eDP-1:d" ];

  # A closed lid must mean nothing at all. All three keys are needed:
  # HandleLidSwitchExternalPower is ignored entirely unless set explicitly, and
  # HandleLidSwitchDocked takes precedence whenever more than one display is
  # connected — which is a state this machine can enter by accident.
  # HandlePowerKey defaults to poweroff, and the power button is reachable by
  # anyone who picks the machine up.
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandlePowerKey = "ignore";
    IdleAction = "ignore";
  };

  # Suspend on T2 is fragile even when configured correctly, and a headless
  # server has nothing to gain from it. Disabling the targets outright means a
  # stray `systemctl suspend` cannot strand the machine somewhere only a
  # physical visit recovers from. Shutting down with the lid shut is worse
  # still — it can hang mid-poweroff and cook the chassis with the fans
  # cycling — so the safest state is one where sleep is not reachable.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # The Intel TCO watchdog is disabled by this machine's firmware — the kernel
  # reports `iTCO_wdt: unable to reset NO_REBOOT flag, device disabled by
  # hardware/BIOS` — so nothing resets a wedged kernel. These sysctls are the
  # substitute: panic on a soft lockup or an oops rather than sitting there,
  # and reboot 30 seconds later.
  #
  # Note the interaction with the reboot problem below: a panic-reboot on this
  # firmware may well power the machine off rather than restart it. That is
  # still better than a wedged host, because a powered-off host is at least
  # unambiguous.
  boot.kernel.sysctl = {
    "kernel.softlockup_panic" = 1;
    "kernel.panic_on_oops" = 1;
    "kernel.panic" = 30;
  };

  # powertop's auto-tune puts the USB ethernet adapter into autosuspend, and
  # that adapter is the only network this machine has. mkForce because the
  # temptation to enable it on a laptop is obvious and this is the one machine
  # where it is a remote-hands call.
  powerManagement.powertop.enable = lib.mkForce false;
  powerManagement.cpuFreqGovernor = "schedutil";
  services.thermald.enable = true;

  # QSV/VAAPI on the UHD 630 — the transcode path media is placed here for.
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

  # ⚠️ `reboot` on this machine is expected to POWER IT OFF, not restart it.
  # The iBridge firmware treats every CPU/chipset reset method — ACPI, EFI and
  # PCI 0xcf9 alike — as a power-off, and no `reboot=` kernel parameter changes
  # that. Verified on a MacBookPro16,1 running headless NixOS; not yet verified
  # on this model.
  #
  # `systemctl kexec` sidesteps the firmware by jumping straight into the next
  # kernel, and is the restart path for a machine nobody is standing next to.
  # It boots the *currently activated* system, so use `nixos-rebuild switch`
  # rather than `boot` before restarting into a new kernel.
  environment.shellAliases.reboot = "echo 'On this host reboot powers off — use: systemctl kexec' >&2; false";
}
