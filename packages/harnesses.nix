# Caller-owned fresh pin. Selecting one harness never implicitly selects another.
{ pkgsFresh, names }:
let
  supported = [
    "claude-code"
    "codex"
    "pi-coding-agent"
    "opencode"
    "herdr"
    "devenv"
  ];
  unknown = builtins.filter (name: !(builtins.elem name supported)) names;
in
if unknown != [ ] then
  throw "systems.harnessPackages: unknown names: ${builtins.concatStringsSep ", " unknown}"
else
  map (name: pkgsFresh.${name}) names
