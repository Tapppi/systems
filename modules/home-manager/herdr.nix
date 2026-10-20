{
  config,
  lib,
  pkgs,
  pkgsFresh,
  ...
}:
let
  cfg = config.programs.systems-herdr;
  format = pkgs.formats.toml { };
in
{
  options.programs.systems-herdr = {
    enable = lib.mkEnableOption "portable Herdr configuration and the herdr-win wrapper";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgsFresh.herdr;
      defaultText = lib.literalExpression "pkgsFresh.herdr";
      description = "Herdr package; use the same version for clients and remote servers.";
    };
    settings = lib.mkOption {
      type = format.type;
      default = { };
      description = "Additional Herdr settings; platform notification policy belongs to the consumer.";
    };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [
      cfg.package
      (import ../../packages/herdr-win.nix {
        inherit pkgs;
        herdr = cfg.package;
      })
    ];
    # Manage one file, leaving manifests, cache and other tool state writable.
    xdg.configFile."herdr/config.toml".source = format.generate "herdr-config.toml" (
      lib.recursiveUpdate (import ../shared/herdr/settings.nix) cfg.settings
    );
  };
}
