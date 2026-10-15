{ ... }:
{
  local.workstation = { user = "demo"; home = "/Users/demo"; };
  local.hammerspoon.luaDir = "/Users/demo/src/systems/modules/darwin/hammerspoon/lua";
  networking = {
    hostName = "apple-silicon-host";
    localHostName = "apple-silicon-host";
    computerName = "Apple Silicon Host";
  };
  home-manager.users.demo.home.stateVersion = "26.11";
}
