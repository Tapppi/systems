#!/usr/bin/env bash
# Per-table and per-index sizes for each engine's database -> node-exporter
# textfile.
#
# postgres_exporter's stat_user_tables collector only ever reports the one
# database its DSN names, because the collectors run against a single
# connection; --auto-discover-databases predates the collector framework and
# does not extend it. Storage cost per engine is a scored bench dimension, so
# the sizes are read directly instead, one psql call per database.
#
# Only the largest TOP_N tables per database are emitted: the engine schemas
# have long tails of tiny tables that would multiply the series count for no
# signal. Aggregate database size is already covered by pg_database_size_bytes
# from the exporter.
#
# Connection settings arrive as libpq's own PG* environment variables, from
# the same root-only env file the exporter uses. Passing a DSN on the command
# line would put the password in argv, where any process can read it; the
# environment of a process is readable only by its own user.
set -u

PSQL=${PSQL:-psql}
: "${PGHOST:?PGHOST must be set}"
: "${PGUSER:?PGUSER must be set}"
: "${PGPASSWORD:?PGPASSWORD must be set}"
export PGSSLMODE=${PGSSLMODE:-disable} # lib/pq defaults to require
# Bound the run well inside the unit's TimeoutStartSec: a black-holed database
# would otherwise sit in TCP connect until systemd kills the script mid-write,
# leaving the previous file — and its up 1 — in place.
export PGCONNECT_TIMEOUT=${PGCONNECT_TIMEOUT:-5}
DATABASES=${PG_DATABASES:-temporal temporal_visibility hatchet bench}
TOP_N=${PG_TOP_N:-15}
OUT=${OUT:-/var/lib/node-exporter-textfile/pg-tables.prom}
TMP="$OUT.tmp"
trap 'rm -f "$TMP"' EXIT

ok=1

{
  echo '# HELP pg_table_total_bytes Table size including indexes and TOAST.'
  echo '# TYPE pg_table_total_bytes gauge'
  echo '# HELP pg_table_heap_bytes Table heap size, excluding indexes and TOAST.'
  echo '# TYPE pg_table_heap_bytes gauge'
  echo '# HELP pg_table_index_bytes Total size of all indexes on the table.'
  echo '# TYPE pg_table_index_bytes gauge'
} > "$TMP"

for db in $DATABASES; do
  rows=$("$PSQL" -d "$db" -Atq -F'|' -v ON_ERROR_STOP=1 -c "
    select schemaname, relname,
           pg_total_relation_size(relid),
           pg_relation_size(relid),
           pg_indexes_size(relid)
    from pg_catalog.pg_statio_user_tables
    order by pg_total_relation_size(relid) desc
    limit $TOP_N
  ") || { ok=0; continue; }

  while IFS='|' read -r schema table total heap idx; do
    [ -n "$table" ] || continue
    lbl="datname=\"$db\",schema=\"$schema\",table=\"$table\""
    echo "pg_table_total_bytes{$lbl} $total"
    echo "pg_table_heap_bytes{$lbl} $heap"
    echo "pg_table_index_bytes{$lbl} $idx"
  done <<< "$rows" >> "$TMP"
done

{
  echo '# HELP pg_table_poller_up 1 when every database answered on this run.'
  echo '# TYPE pg_table_poller_up gauge'
  echo "pg_table_poller_up $ok"
  echo '# HELP pg_table_poller_last_success_timestamp_seconds Unix time of the last fully successful poll.'
  echo '# TYPE pg_table_poller_last_success_timestamp_seconds gauge'
} >> "$TMP"

# Carried forward on a failed run so the gap is measurable from the metric.
if [ "$ok" = 1 ]; then
  echo "pg_table_poller_last_success_timestamp_seconds $(date +%s)" >> "$TMP"
elif [ -f "$OUT" ]; then
  grep '^pg_table_poller_last_success_timestamp_seconds ' "$OUT" >> "$TMP" \
    || echo "pg_table_poller_last_success_timestamp_seconds 0" >> "$TMP"
else
  echo "pg_table_poller_last_success_timestamp_seconds 0" >> "$TMP"
fi

mv "$TMP" "$OUT"
trap - EXIT
