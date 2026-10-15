# Hardware/kernel capability; README.md explains firmware and headless composition.
# nixos-hardware owns boot.kernelPackages: replacing it with a stock/LTS kernel
# loses the apple-bce input support that both the installed host and installer need.
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

    # On dual-GPU models, apple-gmux must expose Intel graphics for QSV/VAAPI.
    # Userspace media drivers alone cannot make a firmware-hidden iGPU available.
    enableIGPU = true;

    # Extract from an Apple recovery image in a Linux build VM, independently
    # of the target's macOS partition. No firmware archive belongs in this repo.
    firmware.enable = true;

    # The pinned get-wifi extractor fails on Sonoma metadata (assert not props).
    # Ventura is the working extraction input; revisit it with the hardware pin.
    firmware.version = "ventura";
  };

  # Substitution requires the exact derivation, including local patch adaptations.
  # The cache is not a guarantee; missing kernel/firmware outputs build on Linux.
  nix.settings = {
    extra-substituters = [ "https://cache.soopy.moe" ];
    extra-trusted-public-keys = [
      "cache.soopy.moe-1:0RZVsQeR+GOh0VQI9rvnHz55nVXkFardDqfm4+afjPo="
    ];
  };

}
