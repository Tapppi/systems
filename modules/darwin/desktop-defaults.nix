# Opt-in desktop preferences; consumers override individual native options.
{ lib, ... }:
{
  system.defaults = {
    finder = {
      QuitMenuItem = lib.mkDefault true;
      ShowExternalHardDrivesOnDesktop = lib.mkDefault true;
      ShowHardDrivesOnDesktop = lib.mkDefault true;
      ShowMountedServersOnDesktop = lib.mkDefault true;
      ShowRemovableMediaOnDesktop = lib.mkDefault true;
      AppleShowAllFiles = lib.mkDefault true;
      ShowStatusBar = lib.mkDefault true;
      ShowPathbar = lib.mkDefault true;
      _FXShowPosixPathInTitle = lib.mkDefault true;
      _FXSortFoldersFirst = lib.mkDefault true;
      FXDefaultSearchScope = lib.mkDefault "SCcf";
      FXEnableExtensionChangeWarning = lib.mkDefault false;
      FXPreferredViewStyle = lib.mkDefault "Nlsv";
    };
    NSGlobalDomain = {
      AppleShowAllExtensions = lib.mkDefault true;
      "com.apple.springing.enabled" = lib.mkDefault true;
      "com.apple.springing.delay" = lib.mkDefault 0.0;
    };
    dock = {
      mouse-over-hilite-stack = lib.mkDefault true;
      tilesize = lib.mkDefault 52;
      mineffect = lib.mkDefault "scale";
      minimize-to-application = lib.mkDefault false;
      enable-spring-load-actions-on-all-items = lib.mkDefault true;
      show-process-indicators = lib.mkDefault true;
      launchanim = lib.mkDefault false;
      expose-animation-duration = lib.mkDefault 0.1;
      mru-spaces = lib.mkDefault false;
      autohide-delay = lib.mkDefault 0.0;
      autohide-time-modifier = lib.mkDefault 0.0;
      autohide = lib.mkDefault true;
      showhidden = lib.mkDefault true;
      show-recents = lib.mkDefault false;
    };
  };
}
