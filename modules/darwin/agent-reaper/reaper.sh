# Reaps what coding-agent sessions leave running. See ./default.nix for why.
#
#   agent-reaper            act, logging only what it kills or removes
#   agent-reaper --dry-run  print every decision, change nothing
#
# Three passes:
#   1. codex-companion brokers whose app-server has been idle for IDLE_SECS
#      are killed together with their whole subtree. The MCP servers under a
#      broker each run in their own process group, so the subtree is walked by
#      ppid rather than signalled as a group.
#   2. MCP servers and codex app-servers reparented to launchd are killed once
#      older than ORPHAN_MIN_AGE_SECS. Their parent is gone, so nothing will
#      ever talk to them again.
#   3. broker.json state pointing at a dead broker is removed. The plugin's
#      teardown signals the stored pid's process group unchecked, so a stale
#      file plus pid reuse would SIGTERM an unrelated process group.

dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

IDLE_SECS=${AGENT_REAPER_IDLE_SECS:-1800}
ORPHAN_MIN_AGE_SECS=${AGENT_REAPER_ORPHAN_MIN_AGE_SECS:-600}
# A job left "running" by a crashed companion would otherwise pin its broker
# forever; one silent for this long is treated as dead.
STALE_JOB_SECS=21600
# Each tracked broker keeps "<cpu-seconds> <idle-since-epoch>" here, keyed by
# pid and start time (lstart, which unlike now - etime is stable between runs)
# so a reused pid starts a fresh record.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/agent-reaper"
plugin_state_glob="$HOME/.claude/plugins/data/*/state/*/broker.json"

# Matched against only the program and its first two arguments (head_of), and
# never against a shell: a full command line also matches a shell or an agent's
# tool call that merely mentions one of these, and killing that subtree could
# take a live session down with it.
# A codex app-server is the exception: global options such as -c may precede
# the subcommand, so it is recognised by program name plus an `app-server`
# argument anywhere instead.
broker_re='^[^ ]*node [^ ]*/app-server-broker\.mjs serve$'
orphan_re='npm exec .*mcp|[-/@]mcp(@| |$)|chrome-devtools-mcp|playwright/mcp|mcp-chrome|context7-mcp|/node_repl( |$)|cua-repl|cgc_launch\.py|codex-code-mode-host'

now=$(date +%s)
mkdir -p "$state_dir"

say() {
  if ((dry_run)); then
    echo "$*"
  else
    echo "$(date -Iseconds) $*"
  fi
}

# [[dd-]hh:]mm:ss[.cc] -> whole seconds. Covers both etime and cputime.
to_secs() {
  local t=$1 days=0 total=0 part
  if [[ $t == *-* ]]; then
    days=$((10#${t%%-*}))
    t=${t#*-}
  fi
  t=${t%%.*}
  local IFS=:
  for part in $t; do
    total=$((total * 60 + 10#$part))
  done
  echo $((days * 86400 + total))
}

is_app_server() {
  local exe=${1%% *}
  [[ ${exe##*/} == codex && " $1 " == *" app-server "* ]]
}

is_shell() {
  local exe=${1%% *}
  exe=${exe##*/}
  [[ ${exe#-} =~ ^(bash|sh|zsh|dash|fish)$ ]]
}

declare -A ppid_of args_of head_of age_of cpu_of children_of
while read -r pid ppid etime cputime cmd; do
  ppid_of[$pid]=$ppid
  args_of[$pid]=$cmd
  read -ra words <<<"$cmd"
  head_of[$pid]="${words[*]:0:3}"
  age_of[$pid]=$(to_secs "$etime")
  cpu_of[$pid]=$(to_secs "$cputime")
  children_of[$ppid]+="$pid "
done < <(/bin/ps -x -o pid=,ppid=,etime=,time=,args=)

subtree() {
  local stack=("$1") out=() p
  while ((${#stack[@]})); do
    p=${stack[-1]}
    unset 'stack[-1]'
    out+=("$p")
    # shellcheck disable=SC2206
    stack+=(${children_of[$p]:-})
  done
  echo "${out[@]}"
}

kill_tree() {
  local root=$1 reason=$2 pids
  pids=$(subtree "$root")
  say "kill $root (${reason}): $(wc -w <<<"$pids") procs: ${args_of[$root]:0:140}"
  ((dry_run)) && return 0
  # shellcheck disable=SC2086
  kill -TERM $pids 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    # shellcheck disable=SC2086
    /bin/ps -p "${pids// /,}" >/dev/null 2>&1 || return 0
    sleep 1
  done
  # shellcheck disable=SC2086
  kill -KILL $pids 2>/dev/null || true
}

broker_json_for() {
  local f
  for f in $plugin_state_glob; do
    [[ -f $f ]] || continue
    [[ $(jq -r '.pid // empty' "$f") == "$1" ]] && { echo "$f"; return 0; }
  done
  return 0
}

remove_broker_state() {
  local f=$1 dir
  dir=$(jq -r '.sessionDir // empty' "$f")
  say "remove broker state $f"
  ((dry_run)) && return 0
  rm -f -- "$f"
  if [[ -n $dir && -d $dir && $(basename "$dir") == cxc-* ]]; then
    rm -rf -- "$dir"
  fi
}

# --- 1. idle brokers -------------------------------------------------------
declare -A seen_keys
for pid in "${!args_of[@]}"; do
  [[ ${head_of[$pid]} =~ $broker_re ]] || continue

  key="$pid-$(date -d "$(/bin/ps -o lstart= -p "$pid")" +%s 2>/dev/null)" || continue
  seen_keys[$key]=1

  cpu=0
  for c in ${children_of[$pid]:-}; do
    is_app_server "${args_of[$c]}" && cpu=$((cpu + cpu_of[$c]))
  done

  running=0
  last_activity=0
  bj=$(broker_json_for "$pid")
  if [[ -n $bj && -f $(dirname "$bj")/state.json ]]; then
    read -r running last_activity < <(jq -r --argjson now "$now" --argjson stale "$STALE_JOB_SECS" '
      def ts: (. // "") | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch 0);
      [.jobs[]? | {s: .status, t: (.updatedAt | ts)}] as $j
      | [ ([$j[] | select((.s == "running" or .s == "queued") and .t > $now - $stale)] | length),
          ([$j[].t, 0] | max) ]
      | @tsv' "$(dirname "$bj")/state.json") || true
  fi

  prev_cpu=""
  idle_since=$now
  [[ -f $state_dir/$key ]] && read -r prev_cpu idle_since <"$state_dir/$key"

  # Under 2s of app-server CPU between runs is timer noise, not a turn.
  if ((running > 0)) || { [[ -n $prev_cpu ]] && ((cpu - prev_cpu >= 2)); }; then
    idle_since=$now
  fi
  ((last_activity > idle_since)) && idle_since=$last_activity

  idle=$((now - idle_since))
  ((dry_run)) && say "broker $pid idle ${idle}s running=$running cpu=${cpu}s cwd=$(sed -E 's/.*--cwd ([^ ]+).*/\1/' <<<"${args_of[$pid]}")"

  if ((idle >= IDLE_SECS)); then
    kill_tree "$pid" "broker idle ${idle}s"
    if [[ -n $bj ]]; then remove_broker_state "$bj"; fi
    ((dry_run)) || rm -f -- "${state_dir:?}/$key"
  elif ((!dry_run)); then
    echo "$cpu $idle_since" >"$state_dir/$key"
  fi
done

if ((!dry_run)); then
  for f in "$state_dir"/*; do
    [[ -f $f ]] || continue
    [[ -n ${seen_keys[$(basename "$f")]:-} ]] || rm -f -- "$f"
  done
fi

# --- 2. orphaned MCP servers and app-servers -------------------------------
declare -A launchd_managed
while read -r lpid _; do
  [[ $lpid =~ ^[0-9]+$ ]] && launchd_managed[$lpid]=1
done < <(launchctl list 2>/dev/null)

for pid in "${!args_of[@]}"; do
  [[ ${ppid_of[$pid]} == 1 ]] || continue
  [[ -z ${launchd_managed[$pid]:-} ]] || continue
  ((age_of[$pid] >= ORPHAN_MIN_AGE_SECS)) || continue
  is_shell "${args_of[$pid]}" && continue
  [[ ${head_of[$pid]} =~ $orphan_re ]] || is_app_server "${args_of[$pid]}" || continue
  kill_tree "$pid" "orphan, age ${age_of[$pid]}s"
done

# --- 3. stale broker state ---------------------------------------------------
for f in $plugin_state_glob; do
  [[ -f $f ]] || continue
  bpid=$(jq -r '.pid // empty' "$f")
  # Checked live, not against the snapshot: passes 1 and 2 can take minutes,
  # and a broker started since then has a broker.json the snapshot cannot see.
  live=""
  if [[ $bpid =~ ^[0-9]+$ ]]; then
    words=()
    read -ra words < <(/bin/ps -o args= -p "$bpid" 2>/dev/null) || true
    live="${words[*]:0:3}"
  fi
  if [[ ! $live =~ $broker_re ]]; then
    remove_broker_state "$f"
  fi
done
