# automatix — 2018 15" MacBook Pro (MacBookPro15,1), always-on CPU server.
#
# Purpose: the fleet's x86_64-linux builder and UAT target, and the media host
# for the QSV transcode path its UHD 630 provides. Six cores against dogmatix's
# four low-power ones, which is the whole reason this machine is in the fleet
# rather than in a drawer.
#
# The hardware is an Apple T2 Mac, which is the difficult part and is confined
# to modules/nixos/automatix/t2.nix. Everything the T2 owns — internal
# keyboard, trackpad, audio, the storage controller — needs an out-of-tree
# kernel, and the machine has no built-in ethernet, so it reaches the network
# through a USB adapter.
#
# Runs headless with the lid shut. There is no display, no internal input
# device in use, and no keyboard at the console, so anything that requires
# somebody standing at the machine is a design error here — that constraint is
# why the root filesystem is unencrypted and why sleep is disabled outright
# rather than made to work.
#
# This file is a composition point; everything real lives in
# modules/nixos/automatix/ and in ./disko.nix.
{ ... }:

{
  imports = [
    ./disko.nix
    ../../../modules/nixos/automatix
  ];
}
