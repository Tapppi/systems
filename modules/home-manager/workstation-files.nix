# File-only Home Manager settings for the Darwin workstation.
{ config, ... }:
{
  # Apps and fonts are supplied at system level. copyApps defaults on from
  # stateVersion 25.11; leave the per-user profile and directories untouched.
  targets.darwin.copyApps.enable = false;
  home.file."Library/Fonts/.home-manager-fonts-version".enable = false;
  home.file."${config.home.homeDirectory}/.cache/.keep".enable = false;
  home.file."${config.home.homeDirectory}/.local/state/.keep".enable = false;

  # This profile is not on manpath, so the generated reference is inaccessible.
  manual.manpages.enable = false;
}
