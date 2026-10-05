#!/usr/bin/env bash
# shellcheck disable=SC2016 # the commands under test are text, never expanded here
# Verdict table for deploy-guard.sh. Run it after any change to the guard:
#
#   .claude/hooks/deploy-guard-test.sh            # the guard beside this file
#   DEPLOY_GUARD=<path> .claude/hooks/deploy-guard-test.sh
#
# Needs jq to build payloads. Every case runs twice: once with jq on PATH, and
# once with jq off it, where the guard cannot read the command and asks about
# any payload that mentions a deploy or activation word, and stays silent about
# the rest.
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
  *'"permissionDecision":"ask"'*) echo ASK ;;
  *) echo "UNKNOWN: $1" ;;
  esac
}

run_guard() { # <path-for-guard> <payload>
  printf '%s' "$2" | PATH=$1 "$BASH" "$guard"
}

check() { # <mode> <want> <payload> <label>
  local mode=$1 want=$2 payload=$3 label=$4 out got guard_path
  if [ "$mode" = jq ]; then guard_path=$PATH; else guard_path=$no_jq; fi
  out=$(run_guard "$guard_path" "$payload")
  got=$(verdict_of "$out")
  if [ "$got" != "$want" ]; then
    fail=$((fail + 1))
    printf 'FAIL [%s] want %s got %s: %s\n%s\n' "$mode" "$want" "$got" "$label" "$out"
  elif [ -n "$out" ] && ! printf '%s' "$out" |
    jq -e '.hookSpecificOutput | .hookEventName == "PreToolUse" and (.permissionDecisionReason | length > 0)' >/dev/null 2>&1; then
    fail=$((fail + 1))
    printf 'FAIL [%s] the verdict is not valid or has no reason: %s\n%s\n' "$mode" "$label" "$out"
  else
    pass=$((pass + 1))
  fi
}

# expect <verdict> <command> [<verdict without jq>]
# Without jq a payload that mentions an activation word asks, and any other is
# silent. A case with no third argument says SILENT for the silent ones and ASK
# for the rest; a silent case that names a word, such as `cat apps/…/build-switch`,
# passes ASK.
expect() {
  local want=$1 cmd=$2 want_no_jq=${3:-} payload
  if [ -z "$want_no_jq" ]; then
    if [ "$want" = SILENT ]; then want_no_jq=SILENT; else want_no_jq=ASK; fi
  fi
  payload=$(jq -nc --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}, cwd: "/tmp"}')
  check jq "$want" "$payload" "$cmd"
  check no-jq "$want_no_jq" "$payload" "$cmd"
}

# expect_raw <verdict> <verdict without jq> <payload text as the harness sends it>
expect_raw() {
  check jq "$1" "$3" "$3"
  check no-jq "$2" "$3" "$3"
}

# Activating macOS configuration
expect DENY 'nix run .#build-switch'
expect DENY 'cd /Users/tapani/project/github/tapppi/systems && nix run .#build-switch'
expect DENY 'nix run .#rollback'
expect DENY 'nix --extra-experimental-features "nix-command flakes" run .#build-switch'
expect DENY 'nix run .#apps.aarch64-darwin.build-switch'
expect DENY 'sudo darwin-rebuild switch --flake .#asterix'
expect DENY '/run/current-system/sw/bin/darwin-rebuild activate'
expect DENY 'darwin-rebuild switch --rollback'
expect DENY 'darwin-rebuild --rollback'
expect DENY 'nix run nix-darwin#darwin-rebuild -- switch --flake .#asterix'
expect DENY './apps/aarch64-darwin/build-switch'
expect DENY $'cd /tmp\n./apps/aarch64-darwin/build-switch'
expect DENY 'DARWIN_HOST=asterix bash apps/aarch64-darwin/rollback'
expect DENY 'nix build .#darwinConfigurations.asterix.system && nix run .#build-switch'
expect DENY $'nix run .#build\nnix run .#build-switch'
# Named only as text: a known false positive, and the deny says how to avoid it
expect DENY 'git commit -m "Tell the user to run nix run .#build-switch"'

# Quoting and escaping around the words
expect DENY '"nix" run .#build-switch'
expect DENY "nix 'run' .#build-switch"
expect DENY 'darwin-rebuild "switch"'
expect DENY '"darwin-rebuild" '"'activate'"
expect DENY 'n"i"x run .#build-switch'
expect DENY "nix run '.#build-switch'"
expect DENY 'nix run .\#build-switch'
expect DENY 'nix run ".#rollback"'
expect DENY 'n\ix run .#build-switch'
expect DENY 'darwin-rebuild swit\ch'
expect DENY './apps/aarch64-darwin/build\-switch'
expect DENY '`apps/aarch64-darwin/build-switch`'
expect DENY $'nix\trun .#build-switch'
expect DENY 'nix   run    .#build-switch'
expect DENY $'nix run \\\n  .#build-switch'
expect DENY $'nix run\r.#build-switch'
expect DENY 'echo `sudo -n apps/aarch64-darwin/build-switch`'
expect DENY './apps/aarch64-darwin/"build-switch"'
expect DENY '"./apps/aarch64-darwin/rollback"'
expect DENY 'bash "$PWD/apps/aarch64-darwin/build-switch"'

# Wrappers
expect DENY 'sudo -n apps/aarch64-darwin/build-switch'
expect DENY 'sudo -u root nix run .#build-switch'
expect DENY '/usr/bin/sudo ./apps/aarch64-darwin/build-switch'
expect DENY '/bin/bash apps/aarch64-darwin/build-switch'
expect DENY 'sh ./apps/aarch64-darwin/rollback'
expect DENY "bash -c 'apps/aarch64-darwin/build-switch'"
expect DENY 'bash -c "cd /tmp && ./apps/aarch64-darwin/build-switch"'
expect DENY "zsh -c 'nix run .#build-switch'"
expect DENY "bash -lc 'darwin-rebuild switch --flake .#asterix'"
expect DENY 'env FOO=1 apps/aarch64-darwin/build-switch'
expect DENY 'FOO=bar sudo apps/aarch64-darwin/build-switch'
expect DENY 'nohup apps/aarch64-darwin/build-switch &'
expect DENY 'time ./apps/aarch64-darwin/rollback'
expect DENY 'exec ./apps/aarch64-darwin/build-switch'
expect DENY 'command apps/aarch64-darwin/build-switch'
expect DENY 'timeout 600 apps/aarch64-darwin/build-switch'
expect DENY 'sudo nix run .#rollback'
expect DENY 'cd apps/aarch64-darwin && ./build-switch'
expect DENY 'if true; then apps/aarch64-darwin/build-switch; fi'
expect DENY '(apps/aarch64-darwin/build-switch)'
expect DENY 'echo ok; sudo darwin-rebuild switch'

# The starter's linux placeholders
expect DENY 'nix run .#apps.x86_64-linux.build-switch'
expect DENY 'nix run .#apps.aarch64-linux.apply'
expect DENY 'bash apps/x86_64-linux/build-switch'
expect DENY 'sudo ./apps/aarch64-linux/build-switch'
expect DENY "bash -c 'apps/x86_64-linux/apply'"
expect DENY '"nix" run ".#apps.x86_64-linux.build-switch"'
expect DENY 'cd apps/aarch64-linux && ./apply'

# NixOS deploys ask, whatever the spelling
expect ASK 'nix run nixpkgs#nixos-rebuild -- switch --flake .#dogmatix --target-host root@dogmatix'
expect ASK 'nixos-rebuild boot --flake .#tts --target-host root@tts'
expect ASK 'nixos-rebuild test --flake .#arkisto --target-host root@arkisto'
expect ASK 'nixos-rebuild-ng switch --flake .#dogmatix'
expect ASK 'scripts/deploy-preflight.sh dogmatix && nix run nixpkgs#nixos-rebuild -- switch --flake .#dogmatix --target-host root@dogmatix'
expect ASK 'sudo nixos-rebuild switch --flake .#dogmatix'
expect ASK '"nixos-rebuild" '"'switch'"' --flake .#dogmatix'
expect ASK "bash -c 'nix run nixpkgs#nixos-rebuild -- switch --flake .#dogmatix --target-host root@dogmatix'"
expect ASK $'nix\trun nixpkgs#nixos-rebuild -- switch --flake .#dogmatix'
expect ASK 'ssh root@dogmatix nixos-rebuild switch'
# A deny outranks the ask
expect DENY 'nixos-rebuild switch --flake .#tts --target-host root@tts && nix run .#build-switch'

# Building, checking and reading never trip it. Without jq the ones that name
# an activation word cannot be told apart, and ask.
expect SILENT 'nix run .#build'
expect SILENT 'nix run .#build -- --help'
expect SILENT 'nix build .#darwinConfigurations.asterix.system'
expect SILENT 'nix flake check'
expect SILENT 'nix eval .#nixosConfigurations.dogmatix.config.system.configurationRevision'
expect SILENT 'git status'
expect SILENT 'git apply fix.patch'
expect SILENT 'kubectl apply -f service.yaml'
expect SILENT 'ls apps/aarch64-darwin'
expect SILENT 'echo "docs mention build"'
expect SILENT 'nixos-rebuild build --flake .#dogmatix' ASK
expect SILENT 'nix run nixpkgs#nixos-rebuild -- dry-activate --flake .#dogmatix --target-host root@dogmatix' ASK
expect SILENT 'rg -n build-switch apps/' ASK
expect SILENT 'grep -n rollback docs/deploys.md' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch' ASK
expect SILENT 'less apps/aarch64-darwin/build-switch' ASK
expect SILENT 'sed -n 1,20p apps/aarch64-darwin/rollback' ASK
expect SILENT 'echo darwin-rebuild; echo switch' ASK
expect SILENT 'nix run .#apply' ASK

# A long command: matched in full, and fast
filler=$(printf 'x%.0s' $(seq 1 4000))
expect SILENT "echo $filler; git status"
expect DENY "echo $filler; nix run .#build-switch"
expect DENY "echo $filler && sudo -n apps/aarch64-darwin/build-switch"

# A payload that carries no command
expect_raw SILENT SILENT '{"tool_name":"Bash","tool_input":{}}'

# The payload as the harness encodes it. With jq the escapes decode and the
# verdict is the command's own; without jq the guard cannot read it, and asks.
#
# The unicode escapes are built here, not written out, so nothing between this
# file and bash can decode them first.
bsl=\\
uni() { printf '%su00%s' "$bsl" "$1"; } # uni 6e -> the escape for "n"
expect_raw DENY ASK '{"tool_input":{"command":"nix run .#build-switch"}}'
expect_raw DENY ASK '{"tool_input":{"command":"nix\trun .#build-switch"}}'
expect_raw DENY ASK '{"tool_input":{"command":"cd /tmp\n./apps/aarch64-darwin/build-switch"}}'
expect_raw DENY ASK '{"tool_input":{"command":"nix run \".#build-switch\""}}'
expect_raw DENY ASK '{"tool_input":{"command":"sudo -n apps/aarch64-darwin/build-switch"}}'
expect_raw DENY ASK "{\"tool_input\":{\"command\":\"$(uni 6e)ix run .#build-switch\"}}"
expect_raw DENY ASK "{\"tool_input\":{\"command\":\"./apps/aarch64-darwin/$(uni 62)uild-switch\"}}"
expect_raw DENY ASK "{\"tool_input\":{\"command\":\"darwin-$(uni 72)ebuild switch\"}}"
expect_raw DENY ASK "{\"tool_input\":{\"command\":\"nix$(uni 20)run$(uni 20).#build-switch\"}}"
expect_raw ASK ASK "{\"tool_input\":{\"command\":\"nix\\trun nixpkgs#nixos-rebuild -- $(uni 73)witch --flake .#h\"}}"
expect_raw ASK ASK "{\"tool_input\":{\"command\":\"nixos-rebuild$(uni 09)switch\"}}"
expect_raw SILENT SILENT '{"tool_input":{"command":"echo \\nix"}}'
expect_raw SILENT SILENT '{"tool_input":{"command":"git status"}}'
expect_raw SILENT SILENT "{\"tool_input\":{\"command\":\"echo $(uni 6e)ix\"}}"

# A payload that is not JSON, or is cut short, asks when it names a deploy word
# and stays silent when it does not, with or without jq.
expect_raw ASK ASK '{"tool_input":{"command":"nix run .#build-switch"'
expect_raw ASK ASK "{\"tool_input\":{\"command\":\"./apps/aarch64-darwin/$(uni 62)uild-switch\""
expect_raw ASK ASK 'nix run .#build-switch'
expect_raw ASK ASK 'sudo darwin-rebuild switch'
expect_raw ASK ASK '{"tool_input":{"command":"nixos-rebuild switch'
expect_raw SILENT SILENT '{"tool_input":{"command":"git status"'
expect_raw SILENT SILENT 'not json at all'
expect_raw SILENT SILENT ''

echo "deploy-guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
