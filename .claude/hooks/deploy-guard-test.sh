#!/usr/bin/env bash
# shellcheck disable=SC2016 # the commands under test are text, never expanded here
# Verdict table for deploy-guard.sh. Run it after any change to the guard:
#
#   .claude/hooks/deploy-guard-test.sh            # the guard beside this file
#   DEPLOY_GUARD=<path> .claude/hooks/deploy-guard-test.sh
#
# Needs jq to build payloads. Every case runs twice: once with jq on PATH, and
# once with jq off it, where the guard cannot read the command and asks about
# any payload that carries a deploy or activation word (even one it would deny
# or let through as read-only), and stays silent about the rest.
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

# expect_cwd <verdict> <cwd> <command> [<verdict without jq>]
# Without jq a payload that carries an activation word asks, and any other is
# silent. A case with no fourth argument says SILENT for the silent ones and ASK
# for the rest; a silent case that names a word, such as `cat apps/…/build-switch`,
# passes ASK.
expect_cwd() {
  local want=$1 cwd=$2 cmd=$3 want_no_jq=${4:-} payload
  if [ -z "$want_no_jq" ]; then
    if [ "$want" = SILENT ]; then want_no_jq=SILENT; else want_no_jq=ASK; fi
  fi
  payload=$(jq -nc --arg c "$cmd" --arg d "$cwd" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}')
  check jq "$want" "$payload" "$cmd"
  check no-jq "$want_no_jq" "$payload" "$cmd"
}

# expect <verdict> <command> [<verdict without jq>]: in a working directory
# that is not under apps/.
expect() { expect_cwd "$1" /tmp "$2" "${3:-}"; }

# expect_raw <verdict> <verdict without jq> <payload text as the harness sends it>
expect_raw() {
  check jq "$1" "$3" "$3"
  check no-jq "$2" "$3" "$3"
}

# expect_msg <text the reason must contain> <command>: with jq, for a command
# the guard blocks.
expect_msg() {
  local payload out
  payload=$(jq -nc --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}, cwd: "/tmp"}')
  out=$(run_guard "$PATH" "$payload")
  if [[ $out == *"$1"* ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL the reason lacks "%s": %s\n%s\n' "$1" "$2" "$out"
  fi
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

# Generation selection activates the selected generation
expect DENY 'sudo darwin-rebuild --switch-generation 42'
expect DENY 'sudo darwin-rebuild -G 42'
expect DENY 'darwin-rebuild rollback'
expect DENY 'darwin-rebuild --switch-generation=42'

# Redirections, remote shells and other shells in front of a script
expect DENY '2>/dev/null ./apps/aarch64-darwin/build-switch'
expect DENY 'ssh asterix ./systems/apps/aarch64-darwin/build-switch'
expect DENY 'ssh asterix sudo darwin-rebuild switch --flake .#asterix'
expect DENY 'nix shell nixpkgs#bash -c apps/aarch64-darwin/build-switch'
expect DENY '"/Users/tapani/My Systems/apps/aarch64-darwin/build-switch"'
expect DENY 'echo x | xargs apps/aarch64-darwin/rollback'
expect DENY 'env -i HOME=/tmp apps/aarch64-darwin/rollback'
expect DENY 'cd apps/aarch64-darwin && ./rollback'
expect DENY 'nix run .#apps.aarch64-darwin.rollback'

# Quoted separators do not end a command
expect DENY "nix run 'git+file:///Users/tapani/project/github/tapppi/systems?ref=main&submodules=1#build-switch'"
expect DENY "darwin-rebuild --flake 'git+file:///Users/tapani/project/github/tapppi/systems?ref=main&submodules=1' switch"
expect ASK "nixos-rebuild --flake 'git+file:///Users/tapani/project/github/tapppi/systems?ref=main&submodules=1' switch"
expect DENY 'echo "a;b" && nix run .#build-switch'
expect DENY "echo 'a|b'; apps/aarch64-darwin/build-switch"

# A backslash-newline joins words, as the shell does, with no whitespace
expect DENY $'ni\\\nx run .#build-switch'
expect DENY $'nix run .#build-\\\nswitch'
expect DENY $'darwin-rebuild swi\\\ntch'
expect DENY $'nix run .#build\\\n-switch'
expect ASK $'nixos-rebuild swi\\\ntch --flake .#dogmatix'

# A system closure's activate script
expect DENY 'sudo /run/current-system/activate'
expect DENY 'sudo ./result/activate'
expect DENY 'cd /run/current-system && ./activate'
expect DENY 'sudo /nix/store/abc-darwin-system-25.11/activate'
expect DENY 'sudo "/run/current-system/activate"'

# The starter's apply script: by path or flake app anywhere, and bare from
# inside its directory, but never `git apply`
expect DENY 'bash apps/aarch64-darwin/apply'
expect DENY 'bash ./apps/x86_64-linux/apply'
expect DENY 'nix run .#apply'
expect DENY 'nix run .#apps.aarch64-darwin.apply'
expect_cwd DENY /Users/tapani/systems/apps/x86_64-linux 'bash ./apply'
expect_cwd DENY /Users/tapani/systems/apps/x86_64-linux 'bash apply'
expect_cwd DENY /Users/tapani/systems/apps/x86_64-linux 'sudo ./apply'
expect_cwd DENY /Users/tapani/systems/apps/aarch64-darwin './apply'
expect_cwd DENY /Users/tapani/systems/apps 'bash apply'
expect_cwd SILENT /Users/tapani/systems/apps/x86_64-linux 'git apply fix.patch'
expect_cwd SILENT /Users/tapani/systems/apps/x86_64-linux 'git apply --check fix.patch'
expect_cwd SILENT /Users/tapani/systems 'bash apply'
expect_cwd SILENT /Users/tapani/systems/applications 'bash apply'
expect_cwd SILENT /Users/tapani/systems/apps/x86_64-linux 'ls'
expect SILENT 'git apply fix.patch'

# Read-only calls stay silent, so the scripts can be worked on. Without jq the
# ones that carry a word cannot be told apart, and ask.
expect SILENT 'cat apps/aarch64-darwin/build-switch' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch | head -20' ASK
expect SILENT 'head -n 20 apps/aarch64-darwin/rollback && tail apps/aarch64-darwin/rollback' ASK
expect SILENT 'wc -l apps/aarch64-darwin/build-switch; file apps/aarch64-darwin/rollback' ASK
expect SILENT 'ls -l apps/aarch64-darwin/build-switch' ASK
expect SILENT 'rg -n "build-switch|rollback" apps/ docs/ 2>/dev/null' ASK
expect SILENT 'grep -rn darwin-rebuild docs/ AGENTS.md'
expect SILENT 'grep -c build-switch apps/aarch64-darwin/common.sh' ASK
expect SILENT 'git diff -- apps/aarch64-darwin/build-switch' ASK
expect SILENT 'git -C /Users/tapani/systems log --oneline -- apps/aarch64-darwin/rollback' ASK
expect SILENT 'git show HEAD:apps/aarch64-darwin/build-switch' ASK
expect SILENT 'git grep -n build-switch' ASK
expect SILENT 'git blame apps/aarch64-darwin/build-switch' ASK
expect SILENT 'git status --short apps/aarch64-darwin/build-switch' ASK
expect SILENT 'sed -n 1,20p apps/aarch64-darwin/build-switch' ASK
expect SILENT "awk 'NR < 10' apps/aarch64-darwin/rollback" ASK
expect SILENT 'shellcheck apps/aarch64-darwin/build-switch' ASK
expect SILENT 'bat apps/aarch64-darwin/rollback' ASK
expect SILENT 'diff apps/aarch64-darwin/build-switch apps/aarch64-linux/build-switch' ASK
expect SILENT 'cd apps/aarch64-darwin && cat apply' ASK
expect SILENT 'echo "nix run .#build-switch"' ASK
expect SILENT 'awk '"'"'$1 > 3 && $2 < 9'"'"' apps/aarch64-darwin/build-switch' ASK
expect SILENT "grep -n 'rollback;build-switch' apps/aarch64-darwin/build-switch" ASK
expect SILENT 'rg "a|b" apps/aarch64-darwin/rollback "docs/a&b.md"' ASK
expect SILENT $'cat apps/aarch64-darwin/build-\\\nswitch' ASK
expect_cwd SILENT /Users/tapani/systems/apps/aarch64-darwin 'cat apply' ASK
# Anything that can run or write another command is not read-only
expect DENY 'sudo cat apps/aarch64-darwin/build-switch'
expect DENY 'cat apps/aarch64-darwin/build-switch | sh'
expect DENY 'cat apps/aarch64-darwin/build-switch | bash -s'
# A multi-line call is never exempt: a quote in a comment must not hide the next line
expect DENY $'echo ready # don\'t wait\nnix run .#build-switch'
expect DENY $'cat AGENTS.md\nnix run .#build-switch'
expect DENY 'bash -c "cat apps/aarch64-darwin/build-switch"'
expect DENY 'cat apps/aarch64-darwin/build-switch > apps/aarch64-darwin/rollback'
expect DENY 'echo x >> apps/aarch64-darwin/build-switch'
expect DENY 'cat $(echo apps/aarch64-darwin/build-switch)'
expect DENY 'cat `apps/aarch64-darwin/build-switch`'
expect DENY 'ssh asterix cat apps/aarch64-darwin/build-switch'
expect DENY 'rg -l x | xargs apps/aarch64-darwin/build-switch'
expect DENY 'env cat apps/aarch64-darwin/build-switch'
expect DENY 'exec cat apps/aarch64-darwin/build-switch'
expect DENY 'cat apps/aarch64-darwin/build-switch; apps/aarch64-darwin/build-switch'
expect DENY 'cat apps/aarch64-darwin/build-switch && nix run .#build-switch'
expect DENY 'sed -i s/a/b/ apps/aarch64-darwin/build-switch'
expect DENY 'sed -n 1p apps/aarch64-darwin/build-switch -i'
expect DENY "awk 'BEGIN { system(\"apps/aarch64-darwin/build-switch\") }'"
expect DENY "awk 'BEGIN { \"apps/aarch64-darwin/build-switch\" | getline }'"
expect DENY 'rg --pre apps/aarch64-darwin/build-switch x .'
expect DENY 'git diff --ext-diff apps/aarch64-darwin/build-switch'
expect DENY 'git -c core.pager=apps/aarch64-darwin/build-switch log'
expect DENY 'cat apps/aarch64-darwin/build-switch & apps/aarch64-darwin/build-switch'
expect DENY 'FOO=1 cat apps/aarch64-darwin/build-switch'
expect DENY 'sudo -u root cat /run/current-system/activate'

# Building, checking and reading never trip it
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
expect SILENT 'nixos-rebuild build --flake .#dogmatix'
expect SILENT 'nix run nixpkgs#nixos-rebuild -- dry-activate --flake .#dogmatix --target-host root@dogmatix'
expect SILENT 'nix build .#nixosConfigurations.dogmatix.config.system.build.toplevel'
expect SILENT 'rg -n build-switch apps/' ASK
expect SILENT 'grep -n rollback docs/deploys.md'
expect SILENT 'less apps/aarch64-darwin/build-switch' ASK
expect SILENT 'echo darwin-rebuild; echo switch' ASK
expect SILENT 'darwin-rebuild build --flake .#asterix'
expect SILENT 'git log --oneline -5'
expect SILENT 'git push origin agent/x'

# Quotes inside a word do not split it
expect DENY 'nix run .#build-"switch"'
expect DENY "nix run .#build-'switch'"
expect DENY 'darwin-rebuild swi"tch"'
expect DENY "dar'win'-rebuild switch"
expect DENY '"darwin-rebuild" sw'"'itch'"
expect ASK 'nixos-rebuild sw"itch" --flake .#dogmatix'
expect ASK "nixos-rebuild te'st' --flake .#dogmatix"
expect DENY 'sudo /run/current-system/"activate"'
expect DENY "sudo /run/current-system/act'ivate'"
expect DENY 'bash apps/aarch64-darwin/ap"ply"'
# A backslash before a letter is that letter to the shell, and not a JSON escape
expect ASK 'nixos-rebuild \test --flake .#dogmatix'
expect ASK 'nixos-rebuild \boot --flake .#dogmatix'
expect DENY 'darwin-rebuild \rollback'
expect DENY 'darwin-rebuild \switch'
expect DENY '\nix run .#build-switch'
expect_cwd DENY /Users/tapani/systems/apps/x86_64-linux 'bash \apply'
expect_cwd SILENT /Users/tapani/systems/apps/x86_64-linux 'kubectl apply -f x.yaml'

# A word that can run another command is refused in a read-only call wherever it sits
expect ASK $'nixos-rebuild\rswitch --flake .#dogmatix'
expect DENY $'darwin-rebuild\tswitch'
expect SILENT 'bash scripts/activate-docs.sh'
expect SILENT 'bash scripts/deactivate'
expect DENY 'sudo /run/current-system/activate-user'
expect SILENT 'pwd; cat apps/aarch64-darwin/build-switch' ASK
expect SILENT 'printf "%s\n" apps/aarch64-darwin/build-switch' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch 2>&1' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch >/dev/null' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch > /dev/null' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch &>/dev/null' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch 2> /dev/null' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch >&2' ASK
expect SILENT 'cat apps/aarch64-darwin/build-switch 1>&2' ASK
expect DENY 'bat --pager sudo apps/aarch64-darwin/build-switch'
expect DENY 'bat --pager doas apps/aarch64-darwin/build-switch'
expect DENY 'bat --pager ssh apps/aarch64-darwin/build-switch'
expect DENY 'bat --pager xargs apps/aarch64-darwin/build-switch'
expect DENY 'bat --pager env apps/aarch64-darwin/build-switch'
expect DENY 'bat --pager exec apps/aarch64-darwin/build-switch'
expect DENY 'bat --pager eval apps/aarch64-darwin/build-switch'
expect DENY 'bat --pager source apps/aarch64-darwin/build-switch'
expect DENY 'cat apps/aarch64-darwin/build-switch <(apps/aarch64-darwin/build-switch)'
expect DENY 'cat apps/aarch64-darwin/build-switch >(apps/aarch64-darwin/build-switch)'
expect DENY "cat '\$(x)' apps/aarch64-darwin/build-switch"
expect DENY 'cat "$(x)" apps/aarch64-darwin/build-switch'
expect DENY 'cat "`x`" apps/aarch64-darwin/build-switch'
expect DENY 'git push origin agent/build-switch-fix'
expect DENY 'git commit -m "mention build-switch"'
expect DENY 'cat apps/aarch64-darwin/build-switch 2>/dev/null > /tmp/out'
expect DENY 'cat apps/aarch64-darwin/build-switch 2>&1 >/tmp/out'
expect DENY 'cat apps/aarch64-darwin/build-switch 2>out.txt'
expect SILENT 'cat apps/aarch64-darwin/build-switch &' ASK
expect DENY 'sed -n -i p apps/aarch64-darwin/build-switch'
expect DENY 'sed -ni p apps/aarch64-darwin/build-switch'
expect DENY 'sed -n --in-place p apps/aarch64-darwin/build-switch'
expect DENY 'sed s/a/b/ apps/aarch64-darwin/build-switch'
expect DENY 'awk -f apps/aarch64-darwin/build-switch | sh'

# The reason says which rule fired
expect_msg 'upstream starter'"'"'s placeholders' 'bash apps/x86_64-linux/build-switch'
expect_msg 'upstream starter'"'"'s placeholders' 'nix run .#apps.aarch64-linux.apply'
expect_msg 'apply script rewrites every file' 'bash apps/aarch64-darwin/apply'
expect_msg 'Activating macOS configuration is the user' 'nix run .#build-switch'
expect_msg 'Activating macOS configuration is the user' 'sudo /run/current-system/activate'
expect_msg 'A NixOS deploy changes a live machine' 'nixos-rebuild switch --flake .#dogmatix'

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

# A command that is not a string cannot be checked, so it asks when the payload
# carries a word, with or without jq, and is silent otherwise
expect_raw ASK ASK '{"tool_input":{"command":{"script":"apps/aarch64-darwin/build-switch"}}}'
expect_raw ASK ASK '{"tool_input":{"command":["apps/aarch64-darwin/build-switch"]}}'
expect_raw ASK ASK '{"tool_input":{"command":["sudo","darwin-rebuild","switch"]}}'
expect_raw ASK ASK '{"tool_input":{"command":{"script":"nixos-rebuild switch"}}}'
expect_raw SILENT SILENT '{"tool_input":{"command":{"script":"git status"}}}'
expect_raw SILENT SILENT '{"tool_input":{"command":5}}'
expect_raw SILENT SILENT '{"tool_input":{"command":null}}'
expect_raw SILENT SILENT '{"tool_input":"git status"}'
expect_raw SILENT ASK '{"tool_input":{"description":"apps/aarch64-darwin/build-switch"}}'
expect_raw ASK ASK 'cat apps/aarch64-darwin/build-switch'
expect_raw ASK ASK '{"tool_input":"apps/aarch64-darwin/build-switch"}'

# The working directory, when the payload is cut short
expect_raw ASK ASK '{"cwd":"/Users/tapani/systems/apps/x86_64-linux","tool_input":{"command":"bash apply"'
expect_raw ASK ASK '{"tool_input":{"command":"bash ./apply"},"cwd":"/Users/tapani/systems/apps/x86_64-linux"'
expect_raw SILENT SILENT '{"cwd":"/Users/tapani/systems","tool_input":{"command":"bash apply"'
expect_raw SILENT SILENT '{"cwd":"/Users/tapani/systems/apps/x86_64-linux","tool_input":{"command":"git apply x.patch"'

# Escapes and continuations in a payload that cannot be parsed
expect_raw ASK ASK $'{"tool_input":{"command":"ni\\\\\\nx run .#build-switch"'
expect_raw ASK ASK $'{"tool_input":{"command":"nix run .#build-\\\\\\nswitch"'
expect_raw ASK ASK $'{"tool_input":{"command":"darwin-rebuild swi\\\\\\ntch"'
expect_raw ASK ASK '{"tool_input":{"command":"darwin-rebuild\tswitch"'
expect_raw ASK ASK '{"tool_input":{"command":"sudo \/run\/current-system\/activate"'
expect_raw SILENT SILENT '{"tool_input":{"command":"echo \\\\nix"'

# A payload that is not JSON, or is cut short, asks when it carries a deploy
# word and stays silent when it does not, with or without jq.
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
