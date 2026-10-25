{
  pkgs,
  uv ? pkgs.uv,
  nodejs ? pkgs.nodejs_24,
}:
let
  setup = pkgs.writeShellApplication {
    name = "agent-skills-setup";
    # npm uses /usr/bin/env node; this PATH binds it to the caller's Node selection.
    runtimeInputs = [
      nodejs
      pkgs.coreutils
      pkgs.gnused
    ];
    text =
      (builtins.readFile ../setup/agent-skills/home-path.sh)
      + "\n"
      +
        builtins.replaceStrings
          [ "@uv@" "@npm@" "@requirements@" "@nodePackages@" ]
          [
            "${uv}/bin/uv"
            "${nodejs}/bin/npm"
            "${../setup/agent-skills/python-requirements.txt}"
            "${../setup/agent-skills/node-packages.txt}"
          ]
          (builtins.readFile ../setup/agent-skills/setup.sh);
  };
  python = pkgs.writeShellApplication {
    name = "agent-skills-python";
    text = ''exec ${setup}/bin/agent-skills-setup --python "$@"'';
  };
in
pkgs.symlinkJoin {
  name = "agent-skills-setup";
  paths = [
    setup
    python
  ];
  passthru = { inherit uv nodejs; };
  meta = {
    description = "Explicit setup and Python launcher for writable document/browser skill environments";
    mainProgram = "agent-skills-setup";
    platforms = [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
}
