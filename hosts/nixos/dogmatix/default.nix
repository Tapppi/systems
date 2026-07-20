# dogmatix — Intel N150 mini-PC, always-on low-power homelab substrate.
#
# Purpose: an Incus host. Workloads (NAS, media, services) run in LXC/OCI
# containers and microVMs on top, so the host itself stays deliberately thin —
# boot, network, SSH, one user, Incus, Tailscale, and a small CLI toolset.
#
# This file is intentionally just a composition point; everything real lives in
# modules/nixos/dogmatix/.
{ ... }:

{
  imports = [
    # PLACEHOLDER — regenerate from the installer. See the file's own header.
    ./hardware-configuration.nix
    ../../../modules/nixos/dogmatix
  ];
}
