#!/usr/bin/env bash
# Temporal task-queue backlog -> node-exporter textfile. This is the
# wake-on-LAN signal: "work is waiting for a host that is switched off".
#
# The server's own approximate_backlog_count gauge cannot carry that signal.
# It is emitted per matching partition, and matching unloads an idle
# partition after about five minutes, so the series decays to zero and then
# stops being exported entirely — precisely in the state the signal exists
# for, a task queued with no worker polling.
#
# DescribeTaskQueue over the frontend HTTP API reads the backlog counter from
# persistence and loads the partition to answer, so it is correct from cold
# and already aggregated across partitions. It needs reportStats=true —
# without it the call returns pollers only and no stats block at all. Polling
# on a timer also keeps the partition resident, which keeps the native gauge
# alive as a side effect.
#
# approximateBacklogAge is the one field that does not survive an unload: the
# first call after a reload reports 0s and the next is accurate, so the age is
# only meaningful while the timer has been running. Alert on the count.
#
# CURL/JQ are injected by the nix wrapper; defaults let the script run
# standalone for testing.
set -u

CURL=${CURL:-curl}
JQ=${JQ:-jq}
API=${TEMPORAL_HTTP_API:-http://127.0.0.1:7243}
NS=${TEMPORAL_NAMESPACE:-default}
QUEUES=${TEMPORAL_QUEUES:-bench-default bench-gpu}
OUT=${OUT:-/var/lib/node-exporter-textfile/temporal.prom}
TMP="$OUT.tmp"
# An aborted run must not leave a partial file behind for the next one
# to carry forward.
trap 'rm -f "$TMP"' EXIT
# Six calls per run, so the per-call ceiling has to leave the whole run
# inside the unit's TimeoutStartSec and the timer interval.
TIMEOUT=${TEMPORAL_HTTP_TIMEOUT:-3}

ok=1

# DescribeTaskQueue over the server's HTTP API. Prints "<count> <age_seconds>",
# or nothing when the call fails or carries no stats block.
describe() {
  local tq=$1 type=$2 body
  body=$("$CURL" -sf --max-time "$TIMEOUT" \
    "$API/api/v1/namespaces/$NS/task-queues/$tq?taskQueueType=TASK_QUEUE_TYPE_$type&reportStats=true") || return 1
  printf '%s' "$body" | "$JQ" -er '
    .stats // empty
    | [ (.approximateBacklogCount // "0" | tonumber)
      , ((.approximateBacklogAge // "0s") | rtrimstr("s") | tonumber)
      ]
    | @tsv'
}

# Visibility-store count of running workflows whose *workflow* task queue is
# $1. Independent of matching: it reads the visibility DB, so it still answers
# after an idle partition unloads.
running_workflows() {
  local tq=$1
  "$CURL" -sfG --max-time "$TIMEOUT" \
    "$API/api/v1/namespaces/$NS/workflow-count" \
    --data-urlencode "query=ExecutionStatus='Running' AND TaskQueue='$tq'" \
    | "$JQ" -er '.count // "0" | tonumber'
}

: > "$TMP"
{
  echo '# HELP temporal_taskqueue_backlog_count Tasks queued on a task queue and not yet dispatched.'
  echo '# TYPE temporal_taskqueue_backlog_count gauge'
  echo '# HELP temporal_taskqueue_backlog_age_seconds Age of the oldest queued task.'
  echo '# TYPE temporal_taskqueue_backlog_age_seconds gauge'
  echo '# HELP temporal_taskqueue_running_workflows Running workflows whose workflow task queue is this queue.'
  echo '# TYPE temporal_taskqueue_running_workflows gauge'
} >> "$TMP"

for q in $QUEUES; do
  for t in workflow activity; do
    if read -r count age < <(describe "$q" "${t^^}"); then
      printf 'temporal_taskqueue_backlog_count{namespace="%s",task_queue="%s",task_type="%s"} %s\n' \
        "$NS" "$q" "$t" "$count" >> "$TMP"
      printf 'temporal_taskqueue_backlog_age_seconds{namespace="%s",task_queue="%s",task_type="%s"} %s\n' \
        "$NS" "$q" "$t" "$age" >> "$TMP"
    else
      ok=0
    fi
  done

  if wf=$(running_workflows "$q"); then
    printf 'temporal_taskqueue_running_workflows{namespace="%s",task_queue="%s"} %s\n' \
      "$NS" "$q" "$wf" >> "$TMP"
  else
    ok=0
  fi
done

{
  echo '# HELP temporal_poller_up 1 when every source answered on this run.'
  echo '# TYPE temporal_poller_up gauge'
  echo "temporal_poller_up $ok"
} >> "$TMP"

{
  echo '# HELP temporal_poller_last_success_timestamp_seconds Unix time of the last fully successful poll.'
  echo '# TYPE temporal_poller_last_success_timestamp_seconds gauge'
} >> "$TMP"
# Carried forward on a failed run so the gap is measurable from the metric.
if [ "$ok" = 1 ]; then
  echo "temporal_poller_last_success_timestamp_seconds $(date +%s)" >> "$TMP"
else
  grep '^temporal_poller_last_success_timestamp_seconds ' "$OUT" 2>/dev/null >> "$TMP" \
    || echo 'temporal_poller_last_success_timestamp_seconds 0' >> "$TMP"
fi

mv "$TMP" "$OUT"
trap - EXIT
