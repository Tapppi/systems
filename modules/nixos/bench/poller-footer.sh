# Shared tail for every bench textfile poller, sourced rather than executed.
#
# Anything that reaches Prometheus through a poller can fail silently into a
# plausible-looking zero, so each one publishes its own liveness alongside its
# data. That contract is consumed uniformly by the PollerDown / PollerFailing /
# PollerStale rules in hosts/nixos/bench-obs/alert-rules.nix, so it has to be
# implemented uniformly too — when it was copied per poller instead, two of
# them silently lacked the failure counter and the rule covered two of five.
#
# Three metrics, because no one of them is sufficient:
#   <prefix>_poller_up                              gauge, this run's verdict
#   <prefix>_poller_failures_total                  counter, so a failure
#     shorter than one scrape interval still exists afterwards; the gauge is
#     rewritten every run and evaporates
#   <prefix>_poller_last_success_timestamp_seconds  carried forward across a
#     failed run, so the size of the gap is readable from the metric alone
#
# The counter's state lives in the previous .prom file. The textfile collector
# offers no other persistence, and Prometheus handles the reset correctly if
# the file is ever lost.
#
# Callers set PREFIX, OUT, TMP and ok, having already written their data lines
# to $TMP, then call poller_footer as the last statement in the script. It
# publishes atomically and returns the run's exit status.
poller_footer() {
  local fails last

  fails=$(sed -n "s/^${PREFIX}_poller_failures_total \([0-9]*\)$/\1/p" "$OUT" 2>/dev/null | tail -1)
  fails=${fails:-0}
  [ "$ok" = 1 ] || fails=$((fails + 1))

  if [ "$ok" = 1 ]; then
    last=$(date +%s)
  else
    last=$(sed -n "s/^${PREFIX}_poller_last_success_timestamp_seconds \([0-9]*\)$/\1/p" "$OUT" 2>/dev/null | tail -1)
    last=${last:-0}
  fi

  {
    echo "# HELP ${PREFIX}_poller_up 1 when every source answered on this run."
    echo "# TYPE ${PREFIX}_poller_up gauge"
    echo "${PREFIX}_poller_up $ok"
    echo "# HELP ${PREFIX}_poller_failures_total Runs that failed at least one source."
    echo "# TYPE ${PREFIX}_poller_failures_total counter"
    echo "${PREFIX}_poller_failures_total $fails"
    echo "# HELP ${PREFIX}_poller_last_success_timestamp_seconds Unix time of the last fully successful run."
    echo "# TYPE ${PREFIX}_poller_last_success_timestamp_seconds gauge"
    echo "${PREFIX}_poller_last_success_timestamp_seconds $last"
  } >> "$TMP"

  mv "$TMP" "$OUT"
  trap - EXIT
  # Non-zero exit as well, so a failed run also registers as a failed unit and
  # not only as a gauge the next run overwrites. The metrics are published
  # first: a failed poll must still succeed at publishing its own failure.
  [ "$ok" = 1 ]
}
