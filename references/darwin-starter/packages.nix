{ pkgs }:

with pkgs;
let shared-packages = import ../shared-desktop/packages.nix { inherit pkgs; }; in
shared-packages ++ [
  dockutil
]
