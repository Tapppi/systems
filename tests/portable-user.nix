{
  self,
  inputs,
  system,
  pkgs,
}:
let
  lib = pkgs.lib;
  pkgsFresh = import inputs.nixpkgs-fresh {
    inherit system;
    config.allowUnfreePredicate = p: lib.getName p == "claude-code";
  };
  baseNames = [
    "ripgrep"
    "fd"
    "fzf"
    "jq"
    "yq-go"
    "uv"
    "nodejs_24"
  ];
  freshNames = [
    "claude-code"
    "codex"
    "pi-coding-agent"
    "opencode"
    "herdr"
    "devenv"
  ];
  sentinel = prefix: names: lib.genAttrs names (n: "${prefix}:${n}");
  fakeBase = self.lib.userPackages { pkgs = sentinel "base" baseNames; };
  fakeFresh = self.lib.harnessPackages {
    pkgsFresh = sentinel "fresh" freshNames;
    names = freshNames;
  };
  rejected = builtins.tryEval (
    builtins.deepSeq (self.lib.harnessPackages {
      pkgsFresh = { };
      names = [ "unknown-harness" ];
    }) true
  );
  home = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit pkgsFresh; };
    modules = [
      self.homeManagerModules.portableUser
      self.homeManagerModules.herdr
      {
        home.username = "fixture";
        home.homeDirectory =
          if pkgs.stdenv.hostPlatform.isDarwin then "/Users/fixture" else "/home/fixture";
        home.stateVersion = "26.05";
        programs.systems-portable-user = {
          base.enable = true;
          harnesses = [
            "claude-code"
            "pi-coding-agent"
          ];
        };
        programs.systems-herdr.enable = true;
      }
    ];
  };
  emptyHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      self.homeManagerModules.portableUser
      self.homeManagerModules.herdr
      {
        home.username = "fixture";
        home.homeDirectory = "/tmp/fixture";
        home.stateVersion = "26.05";
      }
    ];
  };
  cfg = home.config;
  configFile = cfg.xdg.configFile."herdr/config.toml".source;
  expected = {
    onboarding = false;
    update = {
      version_check = false;
      manifest_check = true;
    };
    ui = {
      status_indicators = "symbols";
      show_agent_labels_on_pane_borders = true;
    };
  };
  herdrStub = pkgs.writeShellScriptBin "herdr" ''
    printf '%s\n' "$@" >> "$CALLS"
  '';
  wrapper = self.lib.mkHerdrWin {
    inherit pkgs;
    herdr = herdrStub;
  };
  tmuxStub = pkgs.writeShellScriptBin "tmux" ''
    test "$1" = display-message
    test "$2" = -p
    test "$3" = '#S'
    printf '%s\n' 'workspace session'
  '';
  selected = map toString cfg.home.packages;
  activation = cfg.home.activationPackage;
in
assert fakeBase == map (n: "base:${n}") baseNames;
assert fakeFresh == map (n: "fresh:${n}") freshNames;
assert !rejected.success;
assert
  self.lib.harnessPackages {
    inherit pkgsFresh;
    names = [ ];
  } == [ ];
assert
  map toString (
    self.lib.harnessPackages {
      inherit pkgsFresh;
      names = [ "claude-code" ];
    }
  ) == [ (toString pkgsFresh.claude-code) ];
assert lib.all (p: builtins.elem (toString p) selected) (self.lib.userPackages { inherit pkgs; });
assert builtins.elem (toString pkgsFresh.pi-coding-agent) selected;
assert builtins.elem (toString pkgsFresh.claude-code) selected;
assert !(builtins.elem (toString pkgsFresh.codex) selected);
assert !(builtins.hasAttr "system" cfg);
assert cfg.launchd.agents == { };
assert !(builtins.hasAttr "herdr/config.toml" emptyHome.config.xdg.configFile);
assert !(builtins.elem (toString pkgs.uv) (map toString emptyHome.config.home.packages));
# Force normal HM assertion/activation evaluation, without activating any home.
assert builtins.isString activation.drvPath;
pkgs.runCommand "portable-user-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgsFresh.herdr
    ];
    expectedFile = pkgs.writeText "expected-herdr.json" (builtins.toJSON expected);
    inherit configFile;
  }
  ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME/.config/herdr" "$HOME/.cache/herdr"
      ln -s "$configFile" "$HOME/.config/herdr/config.toml"
      python3 ${./portable-user.py} "$HOME" "$expectedFile"
      # Actual executable/version evidence; no session, network or credentials.
      herdr --version | tee herdr-version.txt
      grep -F '${pkgsFresh.herdr.version}' herdr-version.txt

      python3 ${./herdr-runtime.py} ${pkgsFresh.herdr}/bin/herdr "$configFile" '${pkgsFresh.herdr.version}' \
      > runtime.txt
    cat runtime.txt

    export CALLS="$TMPDIR/calls"
      export PATH=${tmuxStub}/bin:$PATH
      unset TMUX
      HERDR_SESSION='local session' ${wrapper}/bin/herdr-win </dev/null
      printf '%s\n' --session 'local session' > expected-calls
      diff -u expected-calls "$CALLS"
      : > "$CALLS"
      TMUX=fixture ${wrapper}/bin/herdr-win example.invalid </dev/null
      printf '%s\n' --remote example.invalid --session 'workspace session' > expected-calls
      diff -u expected-calls "$CALLS"
      mkdir "$out"
      cp herdr-version.txt runtime.txt "$out/"
      cp "$configFile" "$out/herdr.toml"
  ''
