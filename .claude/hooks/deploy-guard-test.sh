#!/usr/bin/env bash
# Verdict table for deploy-guard.sh. Run it after any change to the guard:
#
#   .claude/hooks/deploy-guard-test.sh            # the guard beside this file
#   DEPLOY_GUARD=<path> .claude/hooks/deploy-guard-test.sh
#
# Needs jq to build payloads; every case also runs once with jq off PATH, where
# the guard must reach the same verdict from the raw payload.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
guard=${DEPLOY_GUARD:-$here/deploy-guard.sh}
command -v jq >/dev/null 2>&1 || {
  echo "deploy-guard-test: jq is required to build payloads" >&2
  exit 2
}
no_jq=$(mktemp -d) || exit 2
trap 'rm -rf "$no_jq"' EXIT

pass=0
fail=0

verdict_of() { # <output>
  case $1 in
  '') echo SILENT ;;
  *'"permissionDecision":"deny"'*) echo DENY ;;
  *'"additionalContext"'*) echo INFORM ;;
  *) echo "UNKNOWN: $1" ;;
  esac
}

run_guard() { # <path-for-guard> <payload>
  printf '%s' "$2" | PATH=$1 "$BASH" "$guard"
}

expect() { # <verdict> <command>
  local want=$1 cmd=$2 payload out got mode
  payload=$(jq -nc --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}, cwd: "/tmp"}')
  for mode in jq no-jq; do
    if [ "$mode" = jq ]; then
      out=$(run_guard "$PATH" "$payload")
    else
      out=$(run_guard "$no_jq" "$payload")
    fi
    got=$(verdict_of "$out")
    if [ "$got" = "$want" ] && { [ -z "$out" ] || printf '%s' "$out" | jq -e . >/dev/null 2>&1; }; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      printf 'FAIL [%s] want %s got %s: %s\n%s\n' "$mode" "$want" "$got" "$cmd" "$out"
    fi
  done
}

# Activating macOS configuration
expect DENY 'nix run .#build-switch'
expect DENY 'cd /Users/tapani/project/github/tapppi/systems && nix run .#build-switch'
expect DENY 'nix run .#rollback'
expect DENY 'nix --extra-experimental-features "nix-command flakes" run .#build-switch'
expect DENY 'nix run .#apps.aarch64-darwin.build-switch'
expect DENY 'sudo darwin-rebuild switch --flake .#asterix'
expect DENY '/run/current-system/sw/bin/darwin-rebuild activate'
expect DENY 'nix run nix-darwin#darwin-rebuild -- switch --flake .#asterix'
expect DENY './apps/aarch64-darwin/build-switch'
expect DENY $'cd /tmp\n./apps/aarch64-darwin/build-switch'
expect DENY 'DARWIN_HOST=asterix bash apps/aarch64-darwin/rollback'
expect DENY 'nix build .#darwinConfigurations.asterix.system && nix run .#build-switch'
expect DENY $'nix run .#build\nnix run .#build-switch'
# Named only as text: a known false positive, and the deny says how to avoid it
expect DENY 'git commit -m "Tell the user to run nix run .#build-switch"'

# The starter's linux placeholders
expect DENY 'nix run .#apps.x86_64-linux.build-switch'
expect DENY 'nix run .#apps.aarch64-linux.apply'
expect DENY 'bash apps/x86_64-linux/build-switch'
expect DENY 'sudo ./apps/aarch64-linux/build-switch'

# NixOS deploys
expect INFORM 'nix run nixpkgs#nixos-rebuild -- switch --flake .#dogmatix --target-host root@dogmatix'
expect INFORM 'nixos-rebuild boot --flake .#tts --target-host root@tts'
expect INFORM 'nixos-rebuild test --flake .#arkisto --target-host root@arkisto'
expect INFORM 'scripts/deploy-preflight.sh dogmatix && nix run nixpkgs#nixos-rebuild -- switch --flake .#dogmatix --target-host root@dogmatix'
# A deny outranks the inform
expect DENY 'nixos-rebuild switch --flake .#tts --target-host root@tts && nix run .#build-switch'

# Building, checking and reading never trip it
expect SILENT 'nix run .#build'
expect SILENT 'nix build .#darwinConfigurations.asterix.system'
expect SILENT 'nix flake check'
expect SILENT 'nix eval .#nixosConfigurations.dogmatix.config.system.configurationRevision'
expect SILENT 'nixos-rebuild build --flake .#dogmatix'
expect SILENT 'nix run nixpkgs#nixos-rebuild -- dry-activate --flake .#dogmatix --target-host root@dogmatix'
expect SILENT 'rg -n build-switch apps/'
expect SILENT 'cat apps/aarch64-darwin/build-switch'
expect SILENT 'sed -n 1,20p apps/aarch64-darwin/rollback'
expect SILENT 'echo darwin-rebuild; echo switch'
expect SILENT 'git status'
expect SILENT 'nix run .#apply'

# A payload that carries no command
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{}}' | "$BASH" "$guard")
if [ -z "$out" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1))
  printf 'FAIL: a payload without a command got output: %s\n' "$out"
fi

# The no-jq verdict names itself
out=$(run_guard "$no_jq" "$(jq -nc '{tool_input: {command: "nix run .#build-switch"}}')")
case $out in
*'could not read'*) pass=$((pass + 1)) ;;
*)
  fail=$((fail + 1))
  printf 'FAIL: the no-jq deny does not say it matched raw text: %s\n' "$out"
  ;;
esac

echo "deploy-guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
