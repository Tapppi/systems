#!/usr/bin/env bash
# PreToolUse guard for this repository's deploy rules.
#
# These are not git rules, and none of them hinges on git state, so they run as
# their own hook beside the ikeh-git plugin's guards rather than inside them:
#
#   deny  activating macOS configuration: a build-switch or rollback app, a
#         build-switch or rollback script, darwin-rebuild switch, activate or
#         --rollback. It needs interactive sudo, and it is the user's call.
#   deny  the upstream starter's linux build-switch and apply apps, which
#         target nixosConfigurations.<arch>, whose keys list is empty.
#   ask   nixos-rebuild switch, boot or test: the user approves each NixOS
#         deploy, and the preflight comes first.
#   ask   a call whose command cannot be read (jq is missing, or the payload is
#         not JSON) while the payload still mentions one of the above.
#
# The command is matched as text, and conservatively. It is normalised first —
# quotes and backslashes removed — so quoting and escaping do not hide a word,
# and the activation words are then matched anywhere in it: behind sudo, env,
# nohup and the like, and inside a `bash -c` body. A rule therefore also fires
# on a command that only names one of these, such as a commit message; the deny
# says how to pass such text instead. Reading the files, as in
# `cat apps/<system>/build-switch`, stays silent.
#
# Uses only bash builtins apart from jq, and finds jq only on an absolute PATH
# entry, so a checkout's own jq never runs here. It avoids here-strings, which
# deadlock on mid-sized inputs under bash 5.3.
#
# stdin: the PreToolUse payload. stdout: a permission decision or nothing.
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

bs=\\
dq='"'
sq="'"

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

decision() { # <deny|ask> <reason>
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}\n' \
    "$1" "$(json_string "$2")"
  exit 0
}

# Sets $normalised: quotes and backslashes removed, and a backslash-newline
# joined into one line. Runs of whitespace need no folding: every pattern below
# spans whitespace with [[:space:]].
normalise() {
  local s=$1
  s=${s//"$bs"$'\n'/ }
  s=${s//"$bs"/}
  s=${s//"$dq"/}
  s=${s//"$sq"/}
  normalised=$s
}

# Sets $decoded: a payload read as JSON text without jq, with its ASCII unicode
# escapes (the six characters backslash, u, 0, 0 and two hex digits) turned into
# the characters they stand for, so that a word they spell shows through.
decode_unicode_escapes() {
  local s=$1 re_u='[\]u00([0-7][0-9a-fA-F])' ch
  while [[ $s =~ $re_u ]]; do
    printf -v ch '%b' "\\x${BASH_REMATCH[1]}"
    s=${s/"${BASH_REMATCH[0]}"/"$ch"}
  done
  decoded=$s
}

# Words that could make a command one of the rules below, whatever surrounds
# them. Used only on a payload that could not be read as JSON.
loose_words='(build-switch|rollback|darwin-rebuild|nixos-rebuild|[#/.]apply)'

command_text=
if command -v jq >/dev/null 2>&1 &&
  command_text=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  normalise "$command_text"
else
  decode_unicode_escapes "$payload"
  normalise "$decoded"
  [[ $normalised =~ $loose_words ]] || exit 0
  decision ask "The deploy guard could not read this call's command, because jq is missing or the payload is not JSON, and the call mentions a deploy or an activation step (build-switch, rollback, darwin-rebuild, nixos-rebuild or the linux apply app), so it needs your approval. Tell the user if jq is missing. Activating macOS configuration is the user's call, a NixOS deploy runs only when the user asked and after 'scripts/deploy-preflight.sh <host>', and none of it runs from a command that cannot be checked. See docs/deploys.md."
fi
command_text=$normalised

# Building blocks for the patterns below. A newline counts as a word edge, and
# as a command separator in the spans that must stay inside one command.
edge_before='(^|[^[:alnum:]_.-])'
edge_after='([^[:alnum:]_-]|$)'
same_command=$'[^;&|\n]*'
command_start=$'(^|[;&|(`\n])[[:space:]]*'
linux_system='(x86_64|aarch64)-linux'
# Words that run another command: sudo and its kin, shells (so `bash -c <body>`
# and `bash <script>` both count), and the keywords that open a command.
wrapper='(sudo|doas|exec|command|env|nohup|time|nice|ionice|setsid|timeout|xargs|bash|sh|zsh|dash|ksh|then|do|else|elif|if|while|until|!)'
# The start of a command, possibly behind VAR=value words and one wrapper whose
# own options and words run up to the command, and then a path to it.
command_head="${command_start}([[:alnum:]_]+=[^[:space:]]*[[:space:]]+)*(([^[:space:];&|]*/)?${wrapper}[[:space:]]+(${same_command}[[:space:]])?)?([^[:space:];&|]*/)?"
# `nix … run <flake>#<app>`, or `#apps.<system>.<app>`, up to the app name.
nix_run_app="${edge_before}nix([[:space:]]${same_command})?[[:space:]]run[[:space:]]${same_command}#([^[:space:]#]*\\.)?"

linux_flake_app="${nix_run_app}(build-switch|apply)${edge_after}"
linux_script="${command_head}(build-switch|apply)${edge_after}"
darwin_flake_app="${nix_run_app}(build-switch|rollback)${edge_after}"
darwin_script="${command_head}(build-switch|rollback)${edge_after}"
darwin_rebuild="${edge_before}darwin-rebuild${same_command}[[:space:]](switch|activate|--rollback)${edge_after}"
nixos_deploy="${edge_before}nixos-rebuild(-ng)?${same_command}[[:space:]](switch|boot|test)${edge_after}"

if [[ $command_text =~ $linux_system ]] &&
  { [[ $command_text =~ $linux_script ]] || [[ $command_text =~ $linux_flake_app ]]; }; then
  decision deny "apps/<linux>/build-switch and apply are the upstream starter's placeholders: build-switch switches to nixosConfigurations.<arch>, whose keys list is empty, so activating it would leave the host with no authorized SSH keys. Deploy a NixOS host with 'nix run nixpkgs#nixos-rebuild -- switch --flake .#<host> --target-host root@<host>', after 'scripts/deploy-preflight.sh <host>', and only when the user asked for the deploy. If the command only names it as text, such as in a commit message, write that text to a file and pass the file (git commit -F <file>). See docs/deploys.md."
fi

if [[ $command_text =~ $darwin_flake_app ]] || [[ $command_text =~ $darwin_script ]] ||
  [[ $command_text =~ $darwin_rebuild ]]; then
  decision deny "Activating macOS configuration is the user's call, and it needs interactive sudo this session does not have. Build instead — 'nix run .#build' or 'nix build .#darwinConfigurations.asterix.system' — then ask the user to run 'nix run .#build-switch' themselves. If the command only names it as text, such as in a commit message, write that text to a file and pass the file (git commit -F <file>). See AGENTS.md → Building Configurations."
fi

if [[ $command_text =~ $nixos_deploy ]]; then
  decision ask "A NixOS deploy changes a live machine, so the user approves each one, and it runs only when they asked for it. Run 'scripts/deploy-preflight.sh <host>' first, unless you already did for this host at this revision, and never deploy past its refusal: it refuses when the host runs a closure this branch does not contain. Every new file must be git-added first, because nix cannot see untracked files. See docs/deploys.md."
fi

exit 0
