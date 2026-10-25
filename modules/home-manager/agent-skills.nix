{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.systems-agent-skills;
in
{
  options.programs.systems-agent-skills = {
    enable = lib.mkEnableOption "the explicit writable agent-skills setup command";
    package = lib.mkOption {
      type = lib.types.package;
      default = import ../../packages/agent-skills-setup.nix { inherit pkgs; };
      defaultText = lib.literalExpression "systems.lib.mkAgentSkillsSetup { inherit pkgs; }";
      description = "Setup package with the consumer's explicit uv and Node dependencies.";
    };
  };
  # Provisioning downloads and writes mutable state only when the user runs the command.
  config.home.packages = lib.mkIf cfg.enable [ cfg.package ];
}
