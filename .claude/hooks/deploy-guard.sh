#!/usr/bin/env bash
# PreToolUse guard for this repository's deploy rules.
#
# These are not git rules, and none of them hinges on git state, so they run as
# their own hook beside the ikeh-git plugin's guards rather than inside them:
#
#   deny    activating macOS configuration: a build-switch or rollback app,
#           an apps/<system>/build-switch or rollback script, darwin-rebuild
#           switch or activate. It needs interactive sudo, and it is the
#           user's call.
#   deny    the upstream starter's linux build-switch and apply apps, which
#           target nixosConfigurations.<arch>, whose keys list is empty.
#   inform  nixos-rebuild switch, boot or test: run the deploy preflight first.
#
# The command is matched as text. A rule therefore also fires on a command that
# only names one of these, such as a commit message; the deny says how to pass
# such text instead. Without jq the raw payload is matched, which can only
# match more, and every verdict says so.
#
# Uses only bash builtins apart from jq, and finds jq only on an absolute PATH
# entry, so a checkout's own jq never runs here.
#
# stdin: the PreToolUse payload. stdout: a permission decision, context, or
# nothing.
set -uo pipefail
export LC_ALL=C

safe_path=
rest=${PATH:-}:
while [ -n "$rest" ]; do
  entry=${rest%%:*}
  rest=${rest#*:}
  case $entry in
  /*) safe_path=${safe_path:+$safe_path:}$entry ;;
  esac
done
PATH=$safe_path

payload=
IFS= read -r -d '' payload || true

json_string() {
  local s=$1 out='' c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
    '"') out+='\"' ;;
    \\) out+="\\\\" ;;
    $'\n') out+='\n' ;;
    $'\r') out+='\r' ;;
    $'\t') out+='\t' ;;
    *)
      if [[ $c < ' ' ]]; then
        printf -v c '\\u%04x' "'$c"
      fi
      out+=$c
      ;;
    esac
  done
  printf '"%s"' "$out"
}

note=
command_text=
if command -v jq >/dev/null 2>&1 &&
  command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  :
else
  note=" (The deploy guard could not read this call's command — jq is missing or the payload is not JSON — so it matched the raw payload text. Tell the user if jq is missing.)"
  # Everything from the command's value on, with the escapes that separate
  # commands or quote words turned back into the characters they stand for.
  command_text=$payload
  command_key='"command"[[:space:]]*:[[:space:]]*"'
  if [[ $payload =~ $command_key ]]; then
    command_text=${payload#*"${BASH_REMATCH[0]}"}
  fi
  command_text=${command_text//\\n/$'\n'}
  command_text=${command_text//\\\"/\"}
fi
[ -n "$command_text" ] || exit 0

# Building blocks for the patterns below. A newline counts as a word edge, and
# as a command separator in the spans that must stay inside one command.
edge_before='(^|[^[:alnum:]_.-])'
edge_after='([^[:alnum:]_-]|$)'
same_command=$'[^;&|\n]*'
command_start=$'(^|[;&|(\n])[[:space:]]*'
linux_system='(x86_64|aarch64)-linux'
# `nix … run <flake>#<app>`, or `#apps.<system>.<app>`, up to the app name.
nix_run_app="${edge_before}nix([[:space:]]${same_command})?[[:space:]]run[[:space:]]${same_command}#([^[:space:]#]*\\.)?"
# An apps/<system>/ script run as a command, directly or through a wrapper.
apps_script="${command_start}(([[:alnum:]_]+=[^[:space:]]*|sudo|exec|command|env|bash|sh)[[:space:]]+)*([^[:space:];&|]*/)?apps/"

linux_flake_app="${nix_run_app}(build-switch|apply)${edge_after}"
linux_script="${apps_script}${linux_system}/(build-switch|apply)${edge_after}"
darwin_flake_app="${nix_run_app}(build-switch|rollback)${edge_after}"
darwin_script="${apps_script}[^[:space:]/]+/(build-switch|rollback)${edge_after}"
darwin_rebuild="${edge_before}darwin-rebuild${same_command}[[:space:]](switch|activate)${edge_after}"
nixos_deploy="${edge_before}nixos-rebuild(-ng)?${same_command}[[:space:]](switch|boot|test)${edge_after}"

deny() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(json_string "$1$note")"
  exit 0
}

inform() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' \
    "$(json_string "$1$note")"
  exit 0
}

if [[ $command_text =~ $linux_script ]] ||
  { [[ $command_text =~ $linux_flake_app ]] && [[ $command_text =~ $linux_system ]]; }; then
  deny "apps/<linux>/build-switch and apply are the upstream starter's placeholders: build-switch switches to nixosConfigurations.<arch>, whose keys list is empty, so activating it would leave the host with no authorized SSH keys. Deploy a NixOS host with 'nix run nixpkgs#nixos-rebuild -- switch --flake .#<host> --target-host root@<host>', after 'scripts/deploy-preflight.sh <host>', and only when the user asked for the deploy. See docs/deploys.md."
fi

if [[ $command_text =~ $darwin_flake_app ]] || [[ $command_text =~ $darwin_script ]] ||
  [[ $command_text =~ $darwin_rebuild ]]; then
  deny "Activating macOS configuration is the user's call, and it needs interactive sudo this session does not have. Build instead — 'nix run .#build' or 'nix build .#darwinConfigurations.asterix.system' — then ask the user to run 'nix run .#build-switch' themselves. If the command only names it as text, such as in a commit message, write that text to a file and pass the file (git commit -F <file>). See AGENTS.md → Building Configurations."
fi

if [[ $command_text =~ $nixos_deploy ]]; then
  inform "Deploy guardrail: a NixOS deploy changes a live machine, so run it only when the user asked for it. Run 'scripts/deploy-preflight.sh <host>' first, unless you already did for this host at this revision, and never deploy past its refusal: it refuses when the host runs a closure this branch does not contain. Every new file must be git-added first, because nix cannot see untracked files. See docs/deploys.md."
fi

exit 0
