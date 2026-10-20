{
  config,
  lib,
  pkgs,
  pkgsFresh,
  ...
}:
let
  cfg = config.programs.systems-portable-user;
in
{
  options.programs.systems-portable-user = {
    base.enable = lib.mkEnableOption "the portable base CLI and runtime packages";
    harnesses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Explicit harness package names from the caller's pkgsFresh argument.";
    };
  };
  config.home.packages =
    lib.optionals cfg.base.enable (import ../../packages/user-base.nix { inherit pkgs; })
    ++ lib.optionals (cfg.harnesses != [ ]) (
      import ../../packages/harnesses.nix {
        inherit pkgsFresh;
        names = cfg.harnesses;
      }
    );
}
