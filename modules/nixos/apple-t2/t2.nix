# Apple T2 hardware: patched stable kernel, Intel graphics and declarative Broadcom firmware.
# Ventura firmware extraction avoids the pinned extractor failure with Sonoma recovery metadata.
# Kernel cache reuse requires matching inputs; missing outputs and firmware
# extraction build on Linux.
{
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [ inputs.nixos-hardware.nixosModules.apple-t2 ./kernel-patches.nix ];

  hardware.apple-t2 = {
    kernelChannel = "stable";

    enableIGPU = true;

    firmware.enable = true;

    firmware.version = "ventura";
  };

  nix.settings = {
    extra-substituters = [ "https://cache.soopy.moe" ];
    extra-trusted-public-keys = [
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };

}
