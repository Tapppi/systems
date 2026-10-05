#!/usr/bin/env bash
# PreToolUse guard for this repository's deploy rules.
#
# These are not git rules, and none of them hinges on git state, so they run as
# their own hook beside the ikeh-git plugin's guards rather than inside them:
#
#   deny  activating macOS configuration: a build-switch or rollback app or
#         script, darwin-rebuild switch, activate, rollback or a generation
#         selection, and a direct run of a system closure's activate script.
#         It needs interactive sudo, and it is the user's call.
#   deny  the upstream starter's linux build-switch and its apply script, which
#         target nixosConfigurations.<arch>, whose keys list is empty, and
#         rewrite every file under the working directory.
#   ask   nixos-rebuild switch, boot or test: the user approves each NixOS
#         deploy, and the preflight comes first.
#   ask   a call whose command cannot be read (jq is missing, the payload is
#         not JSON, or the command is not a string) while the payload still
#         carries one of the words above.
#
# The command is matched as text, and conservatively. It is normalised first —
# quotes and backslashes removed, a backslash-newline joined — so quoting and
# escaping do not hide a word. The words are then looked for anywhere in it,
# with no notion of which command they belong to: behind sudo, ssh, env, a
# `bash -c` body or a `nix shell -c` body, after a quoted `&` or `;`, all the
# same. A call that only names one of them, such as a commit message, therefore
# fires too, as does a Python venv's `bin/activate`; the deny says how to pass
# such text instead.
#
# The one exemption keeps the scripts readable. A single-line call is silent
# about its words when every simple command in it starts with a read-only program (cat,
# rg, sed -n, git diff and the like) and nothing in it can run or write another
# command: no sudo, ssh, xargs, env, exec, command substitution, or redirection
# other than to /dev/null. `cat apps/<system>/build-switch` is silent;
# `sudo cat …`, `cat … | sh` and `bash -c "cat …"` are not.
#
# Uses only bash builtins apart from jq, and finds jq only on an absolute PATH
# entry, so a checkout's own jq never runs here. It avoids here-strings, which
# deadlock on mid-sized inputs under bash 5.3, and runs under bash 3.2.
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
nl=$'\n'

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

# Sets $normalised: a backslash-newline removed without leaving whitespace, as
# the shell does, and then every backslash and quote removed. Runs of
# whitespace need no folding: every pattern spans whitespace with [[:space:]].
normalise() {
  local s=$1
  s=${s//"$bs$nl"/}
  s=${s//"$bs"/}
  s=${s//"$dq"/}
  s=${s//"$sq"/}
  normalised=$s
}

# Sets $decoded: a payload that could not be parsed, read as JSON text, so that
# a word its escapes spell shows through: \\ (kept apart so that a shell
# backslash is not taken for an escape), \n, \t, \r and the ASCII \u00XX forms.
# Any other escape, such as \" or \/, is a backslash that normalise removes.
decode_json_text() {
  local s=$1 re_u='[\]u00([0-7][0-9a-fA-F])' ch ph=$'\001'
  s=${s//"$bs$bs"/$ph}
  s=${s//"${bs}n"/$nl}
  s=${s//"${bs}t"/$'\t'}
  s=${s//"${bs}r"/$'\r'}
  while [[ $s =~ $re_u ]]; do
    printf -v ch '%b' "\\x${BASH_REMATCH[1]}"
    s=${s/"${BASH_REMATCH[0]}"/"$ch"}
  done
  s=${s//"$ph"/$bs}
  decoded=$s
}

# Reads the payload. $readable is 1 when jq parsed it and the command is a
# string (or absent), and then $command_text and $cwd come from it. Anything
# else is read as raw text, with the working directory taken from it if it can
# be found.
command_text=
cwd=
readable=0
re_cwd='"cwd"[[:space:]]*:[[:space:]]*"([^"]*)"'
if command -v jq >/dev/null 2>&1 &&
  command_text=$(printf '%s' "$payload" |
    jq -r '.tool_input.command | if type == "string" then . elif type == "null" then "" else error("not a string") end' 2>/dev/null); then
  readable=1
  cwd=$(printf '%s' "$payload" | jq -r '.cwd | strings' 2>/dev/null) || cwd=
else
  [[ $payload =~ $re_cwd ]] && cwd=${BASH_REMATCH[1]}
  decode_json_text "$payload"
  command_text=$decoded
fi
normalise "$command_text"
text=$normalised

# The programs that only read, one regex per way of starting a simple command.
ro_plain='^(cat|less|head|tail|wc|file|ls|rg|grep|shellcheck|bat|diff|cd|pwd|echo|printf)([[:space:]]|$)'
ro_sed='^sed[[:space:]]+-n([[:space:]]|$)'
ro_awk='^awk([[:space:]]|$)'
ro_git='^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(diff|log|show|status|grep|blame)([[:space:]]|$)'
# Words and options that can run or write another command, wherever they sit.
ro_unsafe_word='(^|[^[:alnum:]_.-])(sudo|doas|ssh|xargs|env|exec|eval|source)([^[:alnum:]_.-]|$)'
ro_unsafe_option='(^|[[:space:]])(--pre|--pre-glob|--output|--ext-diff|--open-files-in-pager)([[:space:]=]|$)'
ro_sed_inplace='(^|[[:space:]])(-[a-zA-Z]*i[a-zA-Z]*|--in-place)([[:space:]=]|$)'

# Sets $masked: a command as the shell would see its unquoted text. Quotes and
# escape backslashes are removed, a backslash-newline is joined, and a `;`, `&`,
# `|`, `<`, `>` or newline that is quoted or escaped becomes an underscore, so
# that it cannot be taken for a separator or a redirection.
mask_quoted() {
  local s=$1 out='' c i state=
  if [[ $s != *["$sq$dq$bs"]* ]]; then
    masked=$s
    return
  fi
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $state in
    sq)
      if [ "$c" = "$sq" ]; then state=; else out+=${c//[;&|<>$nl]/_}; fi
      ;;
    dq)
      case $c in
      "$dq") state= ;;
      "$bs")
        i=$((i + 1))
        c=${s:i:1}
        [ "$c" = "$nl" ] || out+=${c//[;&|<>]/_}
        ;;
      *) out+=${c//[;&|<>$nl]/_} ;;
      esac
      ;;
    *)
      case $c in
      "$sq") state=sq ;;
      "$dq") state=dq ;;
      "$bs")
        i=$((i + 1))
        c=${s:i:1}
        [ "$c" = "$nl" ] || out+=${c//[;&|<>]/_}
        ;;
      *) out+=$c ;;
      esac
      ;;
    esac
  done
  masked=$out
}

# Succeeds when the whole call is read-only, as described at the top. Takes the
# command as the agent wrote it.
read_only_call() {
  local t seg redirect masked
  # Cheap refusals on the text as written come first, because masking walks it
  # a character at a time. A quoted word refuses too, which only errs safe.
  [[ $1 == *"\$("* || $1 == *'`'* ]] && return 1
  # A multi-line call is never exempt: a quote inside a comment would otherwise
  # mask the lines after it. A backslash continuation is not a new line.
  t=${1//$'\\\n'/}
  [[ $t == *$'\n'* ]] && return 1
  [[ $1 =~ $ro_unsafe_word ]] && return 1
  [[ $1 =~ $ro_unsafe_option ]] && return 1
  mask_quoted "$1"
  t=$masked
  [[ $t == *"\$("* || $t == *'`'* || $t == *'<('* || $t == *'>('* ]] && return 1
  [[ $t =~ $ro_unsafe_word ]] && return 1
  [[ $t =~ $ro_unsafe_option ]] && return 1
  for redirect in '>/dev/null' '> /dev/null' '2>&1' '>&2'; do
    t=${t//"$redirect"/}
  done
  [[ $t == *'>'* ]] && return 1
  t=${t//;/$nl}
  t=${t//&/$nl}
  t=${t//|/$nl}
  while [ -n "$t" ]; do
    seg=${t%%"$nl"*}
    if [[ $t == *"$nl"* ]]; then t=${t#*"$nl"}; else t=; fi
    seg=${seg#"${seg%%[![:space:]]*}"}
    [ -n "$seg" ] || continue
    if [[ $seg =~ $ro_plain ]] || [[ $seg =~ $ro_git ]]; then
      continue
    elif [[ $seg =~ $ro_sed ]]; then
      [[ $seg =~ $ro_sed_inplace ]] && return 1
    elif [[ $seg =~ $ro_awk ]]; then
      [[ $seg == *system* || $seg == *getline* ]] && return 1
    else
      return 1
    fi
  done
  return 0
}

# The words, each matched anywhere in the text. An edge is a character that
# cannot continue a word, and a hyphen counts as one, so `build` is not
# `build-switch`, and `--switch-generation` is a word of its own.
edge_after='([^[:alnum:]_-]|$)'
word_before='(^|[^[:alnum:]_-])'
# `#<app>` and `#apps.<system>.<app>` after a flake reference, and a path
# word that reads `apps/<system>/<app>`.
flake_app='#([^[:space:]#]*\.)?'
apps_script='apps/[^[:space:]]*/'

re_rollback_app="(${flake_app}|${apps_script})rollback${edge_after}"
re_apply_app="(${flake_app}|${apps_script})apply${edge_after}"
re_activate='/activate(-user)?([^[:alnum:]_-]|$)'
re_darwin_action="${word_before}(switch|activate|rollback)${edge_after}|(^|[[:space:]])(--rollback|--switch-generation|-G)${edge_after}"
re_nixos_action="${word_before}(switch|boot|test)${edge_after}"
re_linux_system='(x86_64|aarch64)-linux'
# The starter's apply script also runs from inside its directory, as a bare
# `apply` or `./apply`. A working directory under apps/, or a cd into one, is
# the cue; `git apply` and `kubectl apply` are not it.
re_in_apps_dir='(^|/)apps(/|$)'
re_cd_apps='cd[[:space:]]+[^;&|]*apps'
re_bare_apply='(^|[^[:alnum:]_./-])(\./)?(apply|rollback)([^[:alnum:]_.-]|$)'

# Sets $hit to deny-linux, deny-apply, deny-darwin or ask-nixos, or leaves it
# empty. A deny outranks an ask.
hit=
scan() {
  local t=$1 starter=0 darwin=0 stripped
  if [[ $t == *build-switch* ]]; then
    starter=1
    darwin=1
  fi
  [[ $t =~ $re_apply_app ]] && starter=1
  if [[ $cwd =~ $re_in_apps_dir ]] || [[ $t =~ $re_cd_apps ]]; then
    stripped=${t//git[[:space:]]apply/git}
    stripped=${stripped//kubectl[[:space:]]apply/kubectl}
    [[ $stripped =~ $re_bare_apply ]] && starter=1
  fi
  [[ $t =~ $re_rollback_app ]] && darwin=1
  [[ $t =~ $re_activate ]] && darwin=1
  if [[ $t == *darwin-rebuild* ]] && [[ $t =~ $re_darwin_action ]]; then
    darwin=1
  fi
  if [ "$starter" = 1 ] && [[ $t =~ $re_linux_system ]]; then
    hit=deny-linux
  elif [ "$darwin" = 1 ]; then
    hit=deny-darwin
  elif [ "$starter" = 1 ]; then
    hit=deny-apply
  elif [[ $t == *nixos-rebuild* ]] && [[ $t =~ $re_nixos_action ]]; then
    hit=ask-nixos
  fi
}

scan "$text"
[ -n "$hit" ] || exit 0

if [ "$readable" = 1 ] && read_only_call "$command_text"; then
  exit 0
fi

if [ "$readable" = 0 ]; then
  decision ask "The deploy guard could not read this call's command, because jq is missing, the payload is not JSON or the command is not a string, and the call carries a deploy or an activation word (build-switch, rollback, apply, activate, darwin-rebuild or nixos-rebuild), so it needs your approval. Tell the user if jq is missing. Activating macOS configuration is the user's call, a NixOS deploy runs only when the user asked and after 'scripts/deploy-preflight.sh <host>', and none of it runs from a command that cannot be checked. See docs/deploys.md."
fi

case $hit in
deny-linux)
  decision deny "apps/<linux>/build-switch and apply are the upstream starter's placeholders: build-switch switches to nixosConfigurations.<arch>, whose keys list is empty, so activating it would leave the host with no authorized SSH keys. Deploy a NixOS host with 'nix run nixpkgs#nixos-rebuild -- switch --flake .#<host> --target-host root@<host>', after 'scripts/deploy-preflight.sh <host>', and only when the user asked for the deploy. If the command only names it as text, such as in a commit message, write that text to a file and pass the file (git commit -F <file>). See docs/deploys.md."
  ;;
deny-apply)
  decision deny "The upstream starter's apply script rewrites every file under the working directory, .git included, and nothing here uses it. If the command only names it as text, such as in a commit message, write that text to a file and pass the file (git commit -F <file>). See the notes at the top of apps/aarch64-darwin/apply."
  ;;
deny-darwin)
  decision deny "Activating macOS configuration is the user's call, and it needs interactive sudo this session does not have. Build instead — 'nix run .#build' or 'nix build .#darwinConfigurations.asterix.system' — then ask the user to run 'nix run .#build-switch' themselves. If the command only names it as text, such as in a commit message, write that text to a file and pass the file (git commit -F <file>). See AGENTS.md → Building Configurations."
  ;;
ask-nixos)
  decision ask "A NixOS deploy changes a live machine, so the user approves each one, and it runs only when they asked for it. Run 'scripts/deploy-preflight.sh <host>' first, unless you already did for this host at this revision, and never deploy past its refusal: it refuses when the host runs a closure this branch does not contain. Every new file must be git-added first, because nix cannot see untracked files. See docs/deploys.md."
  ;;
esac

exit 0
