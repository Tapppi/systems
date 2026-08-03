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
# Publishes the poller liveness triplet and the file itself; see its header.
. "${POLLER_FOOTER:-../../../modules/nixos/bench/poller-footer.sh}"
PREFIX=pg_table
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
  echo '# HELP pg_table_dead_tuples Dead tuples awaiting vacuum.'
  echo '# TYPE pg_table_dead_tuples gauge'
  echo '# HELP pg_table_live_tuples Live tuple estimate.'
  echo '# TYPE pg_table_live_tuples gauge'
  echo '# HELP pg_table_last_autovacuum_timestamp_seconds Unix time of the last autovacuum, 0 if never.'
  echo '# TYPE pg_table_last_autovacuum_timestamp_seconds gauge'
} > "$TMP"

# Dead tuples ride along with the sizes for the same reason the sizes are here
# at all: the exporter's stat_user_tables collector reports only the database
# its DSN names, which is `postgres` and has no user tables. Autovacuum falling
# behind on a Temporal history table or an Absurd runs table is otherwise
# invisible until it shows up as size growth, by which point it is the finding
# rather than the warning.
for db in $DATABASES; do
  rows=$("$PSQL" -d "$db" -Atq -F'|' -v ON_ERROR_STOP=1 -c "
    select s.schemaname, s.relname,
           pg_total_relation_size(s.relid),
           pg_relation_size(s.relid),
           pg_indexes_size(s.relid),
           coalesce(u.n_dead_tup, 0),
           coalesce(u.n_live_tup, 0),
           coalesce(extract(epoch from greatest(u.last_autovacuum, u.last_vacuum)), 0)::bigint
    from pg_catalog.pg_statio_user_tables s
    left join pg_catalog.pg_stat_user_tables u on u.relid = s.relid
    order by pg_total_relation_size(s.relid) desc
    limit $TOP_N
  ") || { ok=0; continue; }

  while IFS='|' read -r schema table total heap idx dead live vac; do
    [ -n "$table" ] || continue
    lbl="datname=\"$db\",schema=\"$schema\",table=\"$table\""
    echo "pg_table_total_bytes{$lbl} $total"
    echo "pg_table_heap_bytes{$lbl} $heap"
    echo "pg_table_index_bytes{$lbl} $idx"
    echo "pg_table_dead_tuples{$lbl} $dead"
    echo "pg_table_live_tuples{$lbl} $live"
    echo "pg_table_last_autovacuum_timestamp_seconds{$lbl} $vac"
  done <<< "$rows" >> "$TMP"
done

# Cluster-wide WAL volume. postgres_exporter's `wal` collector reads
# pg_ls_waldir, which describes the directory as it stands and sawtooths as
# segments recycle — a rate over it is not bytes written. pg_stat_wal.wal_bytes
# is a genuine cumulative counter, and it is the cleanest cross-engine measure
# of write amplification the bench can get. One row, one connection, any
# database.
wal=$("$PSQL" -d postgres -Atq -F'|' -v ON_ERROR_STOP=1 -c "
  select wal_records, wal_fpi, wal_bytes, wal_buffers_full from pg_stat_wal
") || ok=0
if [ -n "${wal:-}" ]; then
  IFS='|' read -r wrecords wfpi wbytes wbuffull <<< "$wal"
  {
    echo '# HELP pg_stat_wal_records_total WAL records generated since stats reset.'
    echo '# TYPE pg_stat_wal_records_total counter'
    echo "pg_stat_wal_records_total $wrecords"
    echo '# HELP pg_stat_wal_fpi_total WAL full-page images written.'
    echo '# TYPE pg_stat_wal_fpi_total counter'
    echo "pg_stat_wal_fpi_total $wfpi"
    echo '# HELP pg_stat_wal_bytes_total WAL bytes actually written.'
    echo '# TYPE pg_stat_wal_bytes_total counter'
    echo "pg_stat_wal_bytes_total $wbytes"
    echo '# HELP pg_stat_wal_buffers_full_total Times a WAL buffer flush was forced.'
    echo '# TYPE pg_stat_wal_buffers_full_total counter'
    echo "pg_stat_wal_buffers_full_total $wbuffull"
  } >> "$TMP"
fi

poller_footer
