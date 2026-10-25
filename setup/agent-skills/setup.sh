#!/usr/bin/env bash
# Packaged with explicit uv/Node and dependency manifests by agent-skills-setup.nix.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: agent-skills-setup [all|venv|markitdown|node]

Provision writable document/browser skill dependencies for the current HOME.
The default is all. No host activation or global Python/npm installation occurs.
Use agent-skills-python to run Python scripts in the managed skill environment.
HELP
}

action="${1:-all}"
case "$action" in
  -h|--help) usage; exit 0 ;;
  all|venv|markitdown|node) [[ $# -le 1 ]] || { usage >&2; exit 2; } ;;
  --python) shift; action=python ;;
  *) usage >&2; exit 2 ;;
esac
python_minor=3.14
uv='@uv@'
npm='@npm@'

fail() { printf 'agent-skills: %s\n' "$*" >&2; }
if ! agent_skills_home_spelling_valid "${HOME:-}"; then
  fail 'HOME must be absolute, outside root/store, with no trailing/repeated slashes or dot segments'
  exit 1
fi
root="${HOME}/.local/share/agent-skills"
venv="${root}/venv"
old="${venv}.old"
node="${root}/node"
# Never follow a redirected mutable root or move/delete a redirected environment.
for path in "$HOME" "$HOME/.local" "$HOME/.local/share" "$root" "$venv" "$node"; do
  if [[ -L "$path" ]]; then
    fail "refusing symlinked setup destination: $path"
    exit 1
  fi
  if [[ -e "$path" && ! -d "$path" ]]; then
    fail "setup destination is not a directory: $path"
    exit 1
  fi
done

venv_bound() {
  local venv_home managed_dir
  [[ -x "$venv/bin/python" ]] || return 1
  "$venv/bin/python" -c \
    'import sys; sys.exit(0 if "%d.%d" % sys.version_info[:2] == sys.argv[1] else 1)' \
    "$python_minor" 2>/dev/null || return 1
  venv_home="$(sed -n 's/^home = //p' "$venv/pyvenv.cfg" 2>/dev/null)" || return 1
  managed_dir="$("$uv" python dir)" || return 1
  case "$venv_home" in
    "$managed_dir/cpython-${python_minor}-"*) return 0 ;;
  esac
  return 1
}

if [[ "$action" = python ]]; then
  if [[ -e "$old" || -L "$old" ]] || ! venv_bound; then
    fail 'the managed Python environment is unavailable; run agent-skills-setup venv after resolving recovery state'
    exit 1
  fi
  exec "$venv/bin/python" "$@"
fi

mkdir -p "$root"
lock="$root/.setup-lock"
if ! mkdir "$lock" 2>/dev/null; then
  fail "setup already running or interrupted: $lock (remove only after confirming no setup process is running)"
  exit 1
fi
trap 'rmdir "$lock"' EXIT
trap 'exit 130' INT TERM

setup_venv() {
  local extras='' rebuilding=0 created=0 ok=1 dist_info
  if [[ -e "$old" || -L "$old" ]]; then
    fail "$old exists from an interrupted rebuild; venv left untouched." \
      "Restore or keep the desired venv before retrying."
    return 1
  fi
  if [[ -e "$venv" ]]; then
    if venv_bound; then
      printf 'Keeping existing managed Python %s environment\n' "$python_minor"
    else
      extras="$(mktemp "$root/.extras.XXXXXX")" || return 1
      if [[ -x "$venv/bin/python" ]]; then
        "$uv" pip freeze --python "$venv/bin/python" 2>/dev/null |
          sed -n 's/^\([A-Za-z0-9._-]*\)==.*/\1/p' > "$extras" || true
      fi
      # Freeze omits names for direct-URL/editable entries. Installed metadata also
      # works when the interpreter is broken; restore names, never embedded URLs.
      for dist_info in "$venv"/lib/python*/site-packages/*.dist-info; do
        [[ -d "$dist_info" ]] || continue
        basename "$dist_info" | sed -n 's/^\([A-Za-z0-9][A-Za-z0-9._-]*\)-[^-]*\.dist-info$/\1/p'
      done >> "$extras"
      sort -u -o "$extras" "$extras" || { rm -f "$extras"; return 1; }
      if ! mv "$venv" "$old"; then rm -f "$extras"; return 1; fi
      rebuilding=1
    fi
  fi
  if [[ ! -d "$venv" ]]; then
    created=1
    "$uv" python install --no-bin "$python_minor" &&
      "$uv" venv --managed-python --python "$python_minor" "$venv" || ok=0
  fi
  if [[ "$ok" = 1 ]]; then
    "$uv" pip install --python "$venv/bin/python" --quiet -r '@requirements@' || ok=0
  fi
  if [[ "$ok" = 1 && -n "$extras" && -s "$extras" ]]; then
    "$uv" pip install --python "$venv/bin/python" --quiet -r "$extras" || ok=0
  fi
  if [[ "$ok" = 1 ]]; then
    "$venv/bin/playwright" install chromium || ok=0
  fi
  [[ -z "$extras" ]] || rm -f "$extras"
  if [[ "$ok" = 0 ]]; then
    fail 'Python/browser setup failed'
    if [[ "$created" = 1 ]]; then
      rm -rf -- "$venv" || { fail 'could not remove incomplete venv; recovery copy retained'; return 1; }
    fi
    if [[ "$rebuilding" = 1 ]]; then
      mv "$old" "$venv" || { fail 'could not restore previous venv; recovery copy retained'; return 1; }
      printf 'Previous environment restored\n'
    fi
    return 1
  fi
  # Browser provisioning is part of successful recovery; only now retire the old copy.
  if [[ "$rebuilding" = 1 ]]; then rm -rf -- "$old" || return 1; fi
  printf 'Python/browser environment ready: %s\n' "$venv"
}

setup_markitdown() {
  "$uv" tool install --managed-python --python "$python_minor" 'markitdown[pptx,xlsx,xls]'
}

setup_node() {
  local -a packages
  mkdir -p "$node" || return 1
  mapfile -t packages < '@nodePackages@'
  "$npm" install --prefix "$node" --ignore-scripts --no-audit --no-fund --loglevel=error "${packages[@]}"
}

failed=0
case "$action" in
  all)
    setup_venv || failed=1
    setup_markitdown || failed=1
    setup_node || failed=1
    ;;
  venv) setup_venv || failed=1 ;;
  markitdown) setup_markitdown || failed=1 ;;
  node) setup_node || failed=1 ;;
esac
exit "$failed"
