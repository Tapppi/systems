# Prometheus alert rules for the bench.
#
# There is no Alertmanager and there is not going to be one: a bench with no
# on-call has nobody to page. The rules exist for the `ALERTS` series the rule
# manager generates on its own, which the Health row of /d/bench-overview
# renders as a table. That turns every signal below from "visible on a panel
# if someone opens it" into "announced on the landing page" — the distinction
# that let a postgres_exporter collector fail for sixteen hours in plain sight
# of its own panel.
#
# Two conventions the bench's failure history forced:
#
#   * Absence is a state. A scrape pool that fails to build emits no `up`
#     series at all, so `up == 0` is structurally blind to it — the metric
#     never existed to be zero. Every target that matters therefore gets an
#     `absent()` clause as well.
#   * Gauges rewritten by a poller evaporate. A poller that fails and recovers
#     inside one scrape interval leaves `*_poller_up` reading 1 forever after.
#     Where a monotonic counter exists, alert on the counter.
#
# `severity` is documentation, not routing: critical means the bench is not
# measuring what it claims to measure, warning means a signal is degraded.
#
# The inventory this file reasons about — which jobs are scraped, how many
# node targets exist, how many dashboards are provisioned — is passed in from
# the same Nix values that define those things, never restated here. A rule
# asserting a count that has quietly gone stale is the failure this file
# exists to prevent, committed by the file itself.
{ lib, jobs, nodeTargetCount, dashboardCount, soakEngines }:

let
  # Every poller writes the same liveness triplet (see
  # modules/nixos/bench/poller-footer.sh); the three rules below are generated
  # over this list so adding a poller is one line, not three edits in three
  # expressions that are easy to leave inconsistent.
  pollers = [
    { prefix = "absurd"; staleAfter = 300; }
    { prefix = "hatchet"; staleAfter = 300; }
    { prefix = "temporal"; staleAfter = 300; }
    { prefix = "zpool"; staleAfter = 300; }
    # 5 min timer, so the same threshold would be a permanent false positive.
    { prefix = "pg_table"; staleAfter = 1800; }
    # Daily by design: the value it samples moves once a decade.
    { prefix = "incus_trust"; staleAfter = 172800; }
  ];
  anyPoller = f: lib.concatMapStringsSep "\n  or " f pollers;

  # The soak drivers publish the same liveness triplet as the pollers but are
  # a different kind of thing: a poller that stops means a signal is missing,
  # a driver that stops means the experiment is missing. They get their own
  # rules so the distinction survives into the alert name someone reads at
  # hour 60 of a 72 h run.
  anySoak = f: lib.concatMapStringsSep "\n  or " f soakEngines;
in
{
  fleet = {
    name = "bench-fleet";
    rules = [
      {
        alert = "BenchTargetDown";
        expr = "up == 0";
        for = "2m";
        labels.severity = "critical";
        annotations.summary = "{{ $labels.job }} target {{ $labels.instance }} is down";
      }
      {
        # The Incus scrape once failed to construct its pool at all (an
        # unreadable client cert) and produced no series to be zero. One
        # clause per job, because absent() cannot enumerate what was never
        # scraped; `node` is counted instead, having several instances.
        alert = "BenchTargetMissing";
        expr = ''
          ${lib.concatMapStringsSep "\n  or " (j: "absent(up{job=\"${j}\"})")
              (lib.filter (j: j != "node") jobs)}
          or count(up{job="node"}) < ${toString nodeTargetCount}
        '';
        for = "5m";
        labels.severity = "critical";
        annotations.summary = "A scrape target has vanished from discovery, not merely gone down";
      }
      {
        alert = "SystemdUnitFailed";
        expr = ''node_systemd_unit_state{state="failed"} == 1'';
        for = "5m";
        labels.severity = "warning";
        annotations.summary = "{{ $labels.name }} failed on {{ $labels.instance }}";
      }
      {
        # A unit that is stopped is not a unit that failed, and the bench has
        # already lost an hour of gpu-queue coverage to exactly that
        # distinction. Named units only — a general "not active" rule would
        # fire on every oneshot.
        #
        # Restricted to units with no better signal of their own. Grafana,
        # Prometheus, the exporters and Postgres are all covered more
        # precisely elsewhere (absent(grafana_build_info), the self-scrape,
        # BenchTargetDown, pg_up), and listing them here too would mean one
        # outage arriving as four alerts.
        #
        # These names are defined in bench-{temporal,absurd}/default.nix and
        # modules/nixos/dogmatix/; nothing there points back here.
        alert = "BenchUnitNotRunning";
        expr = ''
          node_systemd_unit_state{state="active", name=~"temporal\\.service|temporal-ui\\.service|absurd-worker-.*\\.service|habitat\\.service|incus\\.service"} == 0
        '';
        for = "5m";
        labels.severity = "critical";
        annotations.summary = "{{ $labels.name }} is not running on {{ $labels.instance }}";
      }
      {
        # Crash-and-restart is invisible to unit state: the service is active
        # again before the next scrape. Three dhcpcd segfaults on dogmatix in
        # one day left no trace anywhere until this counter was enabled.
        alert = "BenchUnitRestartLoop";
        expr = "increase(node_systemd_service_restart_total[30m]) > 3";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "{{ $labels.name }} restarted repeatedly on {{ $labels.instance }}";
      }
      {
        alert = "SystemdDegraded";
        expr = "node_systemd_system_running == 0";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "systemd reports degraded on {{ $labels.instance }}";
      }
      {
        alert = "BenchDiskLow";
        expr = ''
          node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|ramfs"}
            / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|ramfs"} < 0.10
        '';
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "Root filesystem below 10% free on {{ $labels.instance }}";
      }
    ];
  };

  signals = {
    name = "bench-signals";
    rules = [
      {
        # Generic across every textfile on every instance. The per-engine
        # dashboards carry the same expression scoped to one file; this is
        # the version that covers the ones nobody thought to scope.
        #
        # The two files written on slower timers are excluded and covered by
        # PollerStale at their own thresholds instead — a 30 s rule over a
        # 5 min writer flaps, and a flapping alert is a disabled one.
        alert = "TextfileStale";
        expr = ''time() - node_textfile_mtime_seconds{file!~".*(pg-tables|incus-trust)\\.prom"} > 300'';
        for = "5m";
        labels.severity = "warning";
        annotations.summary = "{{ $labels.file }} on {{ $labels.instance }} has not been rewritten";
      }
      {
        # node_exporter drops an unparseable file's metrics entirely, so the
        # depth panel reads "No data" while the poller's own up gauge — from
        # the last good file — still reads 1.
        alert = "TextfileParseError";
        expr = "node_textfile_scrape_error != 0";
        for = "2m";
        labels.severity = "warning";
        annotations.summary = "node_exporter could not parse a textfile on {{ $labels.instance }}";
      }
      {
        alert = "PollerDown";
        expr = anyPoller (p: "${p.prefix}_poller_up == 0");
        for = "2m";
        labels.severity = "warning";
        annotations.summary = "A queue-depth or host poller reported failure";
      }
      {
        # The gauge above is rewritten on every run and cannot survive a
        # sub-scrape outage; the counter accumulates, so a failure that
        # healed before Prometheus looked is still alertable afterwards.
        alert = "PollerFailing";
        expr = anyPoller (p: "increase(${p.prefix}_poller_failures_total[30m]) > 0");
        for = "0m";
        labels.severity = "warning";
        annotations.summary = "A poller failed at least once in the last 30 min";
      }
      {
        alert = "PollerStale";
        expr = anyPoller (p:
          "time() - ${p.prefix}_poller_last_success_timestamp_seconds > ${toString p.staleAfter}");
        for = "0m";
        labels.severity = "warning";
        annotations.summary = "A poller has not completed a successful run recently";
      }
      {
        # Prometheus self-scrape. checkConfig is syntax-only (the Incus client
        # cert cannot be stat'ed in the build sandbox), so a config that is
        # well-formed and unusable passes the build and fails at runtime.
        alert = "PrometheusConfigReloadFailed";
        expr = "prometheus_config_last_reload_successful == 0";
        for = "0m";
        labels.severity = "critical";
        annotations.summary = "Prometheus is running on a stale config";
      }
      {
        alert = "PrometheusRuleEvaluationFailing";
        expr = "increase(prometheus_rule_evaluation_failures_total[15m]) > 0";
        for = "5m";
        labels.severity = "warning";
        annotations.summary = "A rule in this file is failing to evaluate";
      }
      {
        alert = "PrometheusTSDBUnhealthy";
        expr = ''
          increase(prometheus_tsdb_compactions_failed_total[1h]) > 0
          or increase(prometheus_tsdb_wal_corruptions_total[1h]) > 0
        '';
        for = "0m";
        labels.severity = "critical";
        annotations.summary = "Prometheus TSDB compaction or WAL failure";
      }
      {
        # Grafana restarting faster than the scrape interval never reads as a
        # failed unit — it read `active` throughout a two-minute crashloop.
        # The build_info series going absent is the signal that survives it.
        alert = "GrafanaMissing";
        expr = "absent(grafana_build_info)";
        for = "3m";
        labels.severity = "critical";
        annotations.summary = "Grafana is not answering /metrics";
      }
      {
        # Dashboards are provisioned from the repo. A JSON that fails to load
        # leaves Grafana running and serving the previous copy, which is the
        # quietest possible failure. The gauge comes from Grafana's periodic
        # stats collector and reads 0 for the first few minutes after a
        # restart, so `for` has to outlast that.
        alert = "GrafanaDashboardsMissing";
        expr = "grafana_stat_totals_dashboard < ${toString dashboardCount}";
        for = "30m";
        labels.severity = "warning";
        annotations.summary = "Fewer dashboards provisioned than the repo defines";
      }
    ];
  };

  host = {
    name = "bench-host";
    rules = [
      {
        # The per-guest cgroup figures are the primary bench result. Their
        # absence is the failure that already happened once, so it gets an
        # absent() arm rather than only a count threshold.
        #
        # Five is written out rather than derived, unlike the other counts in
        # this file: guest lifecycle is imperative Incus (`incus launch`), and
        # only three of the five guests are nixosConfigurations, so no Nix
        # value knows the number.
        alert = "BenchGuestMissing";
        expr = "count(incus_memory_MemTotal_bytes) < 5 or absent(incus_memory_MemTotal_bytes)";
        for = "3m";
        labels.severity = "critical";
        annotations.summary = "Fewer than five guests are reporting cgroup metrics";
      }
      {
        # incus_boot_time_seconds reads the same value for every guest and is
        # unusable. A container restart resets its cgroup CPU counter; the
        # host's does not. This is the only working guest-restart signal.
        alert = "BenchGuestRestarted";
        expr = "resets(incus_cpu_seconds_total[10m]) > 0";
        for = "0m";
        labels.severity = "info";
        annotations.summary = "Guest {{ $labels.name }} restarted";
      }
      {
        alert = "BenchGuestOOMKilled";
        expr = "increase(incus_memory_OOM_kills_total[15m]) > 0";
        for = "0m";
        labels.severity = "critical";
        annotations.summary = "Guest {{ $labels.name }} OOM-killed a process — any run in flight is invalid";
      }
      {
        alert = "HostRebooted";
        expr = ''time() - node_boot_time_seconds{role="host"} < 900'';
        for = "0m";
        labels.severity = "info";
        annotations.summary = "dogmatix rebooted within the last 15 minutes";
      }
      {
        # node_exporter's zfs collector reports the same fact as
        # node_zfs_zpool_state, but only the textfile gauge is labelled the
        # way the /d/bench-host panels are, and carrying both meant a summary
        # that printed two label names hoping one was set.
        alert = "ZFSPoolNotOnline";
        expr = "zpool_health_online == 0";
        for = "1m";
        labels.severity = "critical";
        annotations.summary = "ZFS pool {{ $labels.pool }} is not ONLINE";
      }
      {
        # vmpool is a single non-replicated disk by design, so a checksum
        # error is unrecoverable rather than something a resilver repairs.
        alert = "ZFSDataErrors";
        expr = "zpool_checksum_errors_total > 0 or zpool_read_errors_total > 0 or zpool_write_errors_total > 0 or zpool_scan_errors > 0";
        for = "0m";
        labels.severity = "critical";
        annotations.summary = "ZFS reported errors on {{ $labels.pool }}";
      }
      {
        alert = "ZFSScrubStale";
        expr = "(time() - zpool_scrub_end_timestamp_seconds) > 45 * 86400";
        for = "1h";
        labels.severity = "warning";
        annotations.summary = "{{ $labels.pool }} has not completed a scrub in 45 days";
      }
      {
        alert = "ZFSPoolFilling";
        expr = "zpool_capacity_ratio > 80";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "ZFS pool {{ $labels.pool }} above 80% capacity";
      }
      {
        # The Incus metrics scrape authenticates with a client certificate.
        # An expired trust entry kills it the same silent way the unreadable
        # cert did — no target, so no `up` series to be zero.
        alert = "IncusMetricsCertExpiring";
        expr = "(incus_trust_cert_expiry_timestamp_seconds - time()) < 30 * 86400";
        for = "1h";
        labels.severity = "warning";
        annotations.summary = "Incus trust certificate {{ $labels.name }} expires within 30 days";
      }
    ];
  };

  postgres = {
    name = "bench-postgres";
    rules = [
      {
        # The exporter stays up when Postgres goes down, so up{job="postgres"}
        # is green through a database outage. pg_up is the real signal.
        alert = "PostgresDown";
        expr = "pg_up == 0";
        for = "1m";
        labels.severity = "critical";
        annotations.summary = "Postgres is not answering the exporter";
      }
      {
        # The `wal` collector failed for sixteen hours because its role
        # lacked a grant. The panel plotting it was on the dashboard the
        # whole time.
        alert = "PostgresCollectorFailing";
        expr = "pg_scrape_collector_success == 0";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "postgres_exporter collector {{ $labels.collector }} is failing";
      }
      {
        alert = "PostgresExporterScrapeError";
        expr = "pg_exporter_last_scrape_error != 0";
        for = "5m";
        labels.severity = "warning";
        annotations.summary = "postgres_exporter reported a scrape error";
      }
      {
        alert = "PostgresRestarted";
        expr = "changes(pg_postmaster_start_time_seconds[1h]) > 0";
        for = "0m";
        labels.severity = "info";
        annotations.summary = "Postgres restarted within the last hour";
      }
      {
        # Three idle engines already hold 60 of 100 backends, so the ceiling
        # is the most likely real failure here. The rejection itself
        # (`sorry, too many clients already`) only ever reaches the log.
        alert = "PostgresConnectionsHigh";
        expr = "100 * sum(pg_stat_database_numbackends) / scalar(pg_settings_max_connections) > 80";
        for = "5m";
        labels.severity = "warning";
        annotations.summary = "Postgres backends above 80% of max_connections";
      }
      {
        alert = "PostgresDeadlocks";
        expr = "increase(pg_stat_database_deadlocks[15m]) > 0";
        for = "0m";
        labels.severity = "warning";
        annotations.summary = "Deadlock in database {{ $labels.datname }}";
      }
      {
        # statement_timeout and idle_in_transaction_session_timeout are both
        # 0, so a stuck transaction holds its locks indefinitely.
        alert = "PostgresLongIdleTransaction";
        expr = ''max(pg_stat_activity_max_tx_duration{state="idle in transaction"}) > 300'';
        for = "5m";
        labels.severity = "warning";
        annotations.summary = "A transaction has been idle in transaction for over five minutes";
      }
      {
        alert = "PostgresWalGrowing";
        expr = "pg_wal_size_bytes > 0.8 * pg_settings_max_wal_size_bytes";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "WAL directory above 80% of max_wal_size";
      }
    ];
  };

  engines = {
    name = "bench-engines";
    rules = [
      {
        # Temporal's persistence layer lost its database for two minutes
        # during a Postgres restart and reported it only to the journal.
        alert = "TemporalPersistenceErrors";
        expr = "sum(rate(persistence_error_with_type[5m])) > 0.5";
        for = "5m";
        labels.severity = "critical";
        annotations.summary = "Temporal persistence is erroring";
      }
      {
        alert = "TemporalDynamicConfigUpdateFailing";
        expr = "increase(dynamic_config_update_failure[15m]) > 0";
        for = "0m";
        labels.severity = "warning";
        annotations.summary = "Temporal could not load its dynamic config file";
      }
      {
        # Every hatchet_* counter is process-local, so a restart silently
        # resets the throughput panels to zero. The engine came back
        # forty-nine minutes after a host reboot once and nothing recorded it.
        alert = "HatchetEngineRestarted";
        expr = ''changes(process_start_time_seconds{job="hatchet"}[1h]) > 0'';
        for = "0m";
        labels.severity = "info";
        annotations.summary = "hatchet-lite restarted — its counters restarted with it";
      }
      {
        # increase() rather than the raw counter: the instantaneous value
        # reads 0 after a restart even when the event really happened.
        alert = "HatchetTaskFailures";
        expr = ''
          increase(hatchet_failed_tasks_total[1h]) > 0
          or increase(hatchet_scheduling_timed_out[1h]) > 0
        '';
        for = "0m";
        labels.severity = "warning";
        annotations.summary = "Hatchet failed or timed out scheduling a task";
      }
      {
        # B4 parks a scheduled run five days out. A scheduled-but-not-due run
        # appears in no Hatchet metric, so if it were deleted every panel
        # would look identical — this gauge is published by the queue poller.
        alert = "HatchetScheduledRunsMissing";
        expr = "hatchet_scheduled_runs_total < 1";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "No scheduled Hatchet runs remain — the parked B4 run may be gone";
      }
      {
        # An Absurd task that has exhausted its retries sits dead in the
        # database forever. There is no engine-side signal for it — this
        # gauge is published by the queue poller.
        alert = "AbsurdTasksFailed";
        expr = ''sum by (queue) (absurd_tasks{state="failed"}) > 0'';
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "Queue {{ $labels.queue }} holds permanently failed tasks";
      }
      {
        # A worker that died mid-task leaves its claim behind; the run stays
        # `running` past the lease and nothing reclaims it.
        alert = "AbsurdExpiredLeases";
        expr = "absurd_run_expired_leases > 0";
        for = "5m";
        labels.severity = "warning";
        annotations.summary = "Queue {{ $labels.queue }} has runs past their claim expiry";
      }
      {
        # The poller enumerates queues from absurd.queues, so a queue that
        # exists but nothing polls shows up here as depth with no progress.
        alert = "AbsurdQueueBacklogged";
        expr = "absurd_queue_oldest_pending_seconds > 900";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "Queue {{ $labels.queue }} has work waiting over 15 min — is a worker attached?";
      }
    ];
  };

  soak = {
    name = "bench-soak";
    rules = [
      {
        # A dead driver and an idle engine are indistinguishable in every
        # engine-side metric — the queue is empty either way. This is the only
        # rule that separates them, and it is the one that decides whether a
        # three-day soak measured anything at all.
        alert = "SoakDriverDown";
        expr = ''${anySoak (e: "soak_driver_up{engine=\"${e}\"} == 0")}'';
        for = "5m";
        labels.severity = "critical";
        annotations.summary = "Soak driver for {{ $labels.engine }} reported failure";
      }
      {
        # Absence, not zero: a driver whose process is gone stops rewriting
        # its textfile and the gauge goes stale rather than false. The
        # timestamp is the only reading that degrades in the right direction.
        alert = "SoakDriverMissing";
        expr = ''
          ${anySoak (e: "absent(soak_driver_up{engine=\"${e}\"})")}
          or ${anySoak (e: "time() - soak_driver_last_success_timestamp_seconds{engine=\"${e}\"} > 300")}
        '';
        for = "5m";
        labels.severity = "critical";
        annotations.summary = "A soak driver has stopped publishing";
      }
      {
        # Restarts reset the counters, which is intended — but a driver that
        # restarts repeatedly invalidates the throughput series it publishes.
        alert = "SoakDriverRestarting";
        expr = ''increase(node_systemd_service_restart_total{name=~"soak-.*\\.service"}[1h]) > 2'';
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "{{ $labels.name }} has restarted repeatedly during the soak";
      }
      {
        # Backpressure is a safety rail, not a normal state: it means a queue
        # is not draining, which for the soak means a worker is gone. Brief
        # pauses after a burst are expected, hours of them are not.
        alert = "SoakDriverPaused";
        expr = "soak_paused == 1";
        for = "30m";
        labels.severity = "warning";
        annotations.summary = "Soak driver for {{ $labels.engine }} has been backpressured for 30 min";
      }
      {
        # The rail's own failure mode: if the depth cannot be read the driver
        # keeps producing for a grace window and then stops. Either half of
        # that is worth knowing before the pause arrives.
        alert = "SoakBacklogUnreadable";
        expr = "soak_backlog_known == 0";
        for = "5m";
        labels.severity = "warning";
        annotations.summary = "Soak driver for {{ $labels.engine }} cannot read its queue depth";
      }
      {
        # Submissions that raise are the driver's view of an engine being
        # unavailable, and they are counted rather than logged so a failure
        # that healed inside a scrape interval is still visible afterwards.
        alert = "SoakSubmitErrors";
        expr = "increase(soak_submit_errors_total[30m]) > 5";
        for = "0m";
        labels.severity = "warning";
        annotations.summary = "Soak driver for {{ $labels.engine }} failed to submit {{ $labels.kind }} work";
      }
      {
        # The composite share is the most fragile part of the load and the
        # first thing to break silently: a graph run that times out still
        # leaves a completed-looking engine run behind it.
        alert = "SoakGraphRunsFailing";
        expr = ''increase(soak_graph_runs_total{result!="ok"}[2h]) > 2'';
        for = "0m";
        labels.severity = "warning";
        annotations.summary = "Composite graph runs on {{ $labels.engine }} are failing ({{ $labels.result }})";
      }
      {
        # Growth that would not fit a year of homelab volume. Watched live
        # rather than only at evaluation, because a runaway table is the one
        # soak outcome that can fill the pool before the window closes.
        alert = "SoakDatabaseGrowth";
        expr = "pg_database_size_bytes > 8e9";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "{{ $labels.datname }} has passed 8 GB during the soak";
      }
    ];
  };
}
