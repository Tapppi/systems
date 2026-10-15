# Prometheus rules for the benchmark service stack. The rule manager publishes
# ALERTS for dashboard consumption; no Alertmanager is required for that series.
# Critical means measurement validity is lost; warning means a degraded signal.
# Scrape absence needs absent(), not just up == 0. Poller failure counters retain
# short failures which a freshly rewritten liveness gauge cannot show.
# Inventory counts come from the same values used for scrape/provisioning config.
{
  lib,
  jobs,
  nodeTargetCount,
  dashboardCount,
  soakEngines,
}:

let
  # These pollers share the liveness triplet from ../../bench/poller-footer.sh.
  # One inventory keeps the down, failure-counter and freshness rules aligned.
  pollers = [
    {
      prefix = "absurd";
      staleAfter = 300;
    }
    {
      prefix = "hatchet";
      staleAfter = 300;
    }
    {
      prefix = "temporal";
      staleAfter = 300;
    }
    {
      prefix = "zpool";
      staleAfter = 300;
    }
    # 5 min timer, so the same threshold would be a permanent false positive.
    {
      prefix = "pg_table";
      staleAfter = 1800;
    }
    # The certificate inventory timer runs daily.
    {
      prefix = "incus_trust";
      staleAfter = 172800;
    }
  ];
  anyPoller = f: lib.concatMapStringsSep "\n  or " f pollers;

  # The soak drivers publish the same liveness triplet as the pollers but are
  # a different kind of thing: a poller that stops means a signal is missing,
  # a driver that stops means the experiment is missing. They get their own
  # rules so the alert identifies whether collection or workload stopped.
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
        # An unreadable client certificate can prevent an entire scrape pool
        # from being constructed, leaving no up series to compare with zero.
        # absent() cannot enumerate missing jobs, so each gets its own clause;
        # node has multiple instances and is counted against the inventory.
        alert = "BenchTargetMissing";
        expr = ''
          ${lib.concatMapStringsSep "\n  or " (j: "absent(up{job=\"${j}\"})") (
            lib.filter (j: j != "node") jobs
          )}
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
        # A stopped unit is not a failed unit. Select persistent bench services:
        # a general "not active" rule would fire between every oneshot run.
        #
        # Restricted to units with no better signal of their own. Grafana,
        # Prometheus, the exporters and Postgres are all covered more
        # precisely elsewhere (absent(grafana_build_info), the self-scrape,
        # BenchTargetDown, pg_up), and listing them here too would mean one
        # outage arriving as four alerts.
        #
        # Names come from the Temporal/Absurd service modules and Incus.
        alert = "BenchUnitNotRunning";
        expr = ''
          node_systemd_unit_state{state="active", name=~"temporal\\.service|temporal-ui\\.service|absurd-worker-.*\\.service|habitat\\.service|incus\\.service"} == 0
        '';
        for = "5m";
        labels.severity = "critical";
        annotations.summary = "{{ $labels.name }} is not running on {{ $labels.instance }}";
      }
      {
        # A crash-and-restart between scrapes is invisible to the active-state
        # gauge; the monotonic restart counter retains it.
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
        expr = anyPoller (
          p: "time() - ${p.prefix}_poller_last_success_timestamp_seconds > ${toString p.staleAfter}"
        );
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
        # Use the textfile gauge's pool label consistently with the dashboard;
        # the native ZFS collector uses a different label schema.
        alert = "ZFSPoolNotOnline";
        expr = "zpool_health_online == 0";
        for = "1m";
        labels.severity = "critical";
        annotations.summary = "ZFS pool {{ $labels.pool }} is not ONLINE";
      }
      {
        # Read, write, checksum and scan errors all threaten benchmark validity;
        # redundancy and recovery policy belong to the storage composition.
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
        # An expired trust entry can remove the scrape target entirely, leaving
        # no up series to compare with zero.
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
        # An exporter may stay up while an individual collector lacks grants.
        # Its success gauge distinguishes missing data from an idle database.
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
        # Connection-limit rejections are logged rather than exported; monitor
        # shared connection headroom before new connections start failing.
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
        # An idle transaction retains locks and xmin until it ends or times out.
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
        # Engine persistence errors can outlast a healthy Postgres scrape.
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
        # Hatchet counters are process-local; a restart resets throughput state.
        # Process start time distinguishes that reset from an idle engine.
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
        expr = "${anySoak (e: "soak_driver_up{engine=\"${e}\"} == 0")}";
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
        # Monitor the benchmark's 8 GB database budget throughout the soak:
        # runaway growth can exhaust storage before the run completes.
        alert = "SoakDatabaseGrowth";
        expr = "pg_database_size_bytes > 8e9";
        for = "10m";
        labels.severity = "warning";
        annotations.summary = "{{ $labels.datname }} has passed 8 GB during the soak";
      }
    ];
  };
}
