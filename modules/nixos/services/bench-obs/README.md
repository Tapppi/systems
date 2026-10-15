# Benchmark observability

The module provisions Prometheus, Grafana, pollers, two static dashboards and alert rules for
Temporal, Hatchet, Absurd, Postgres and an Incus/ZFS host. The composing configuration supplies
scrape targets, queues, databases and soak-engine labels. Credentials remain runtime files.
The bundled rules assume this benchmark stack and its poller timings; adapt `alertRules` when
monitoring a different stack. Prometheus uses syntax-only config checking because its Incus
client certificate is available only at runtime.

Incus guest and Postgres database selectors query metric labels dynamically. The dashboards use
the module's `bench-prometheus` datasource. Their measurement caveats belong with the panels;
hardware limits, placement and workload expectations belong to the composition.

## Composition

`services.systems-bench-obs.dashboardFiles` maps JSON filenames to source paths. The public
`bench-incus.json` and `bench-postgres.json` entries are defaults; add files or override an entry
with a source path. `lib.mkForce { ... }` replaces the entire set if needed. A standard link farm
provisions the selected files without rewriting JSON. Its source-map size supplies the dashboard
inventory alert, so evaluation never reads a built directory.

`extraAlertRules` maps existing rule-generator group keys to lists of alerts. Each alert has
`alert`, `expr`, optional `for` (default `0m`), `labels` and `annotations`. The default group keys
are `engines`, `fleet`, `host`, `postgres`, `signals` and `soak`. Unknown keys fail a NixOS
assertion. Add deployment-specific guest-count, host-reboot and scheduled-workload expectations
here. The public rules do not assume those policies.

```nix
services.systems-bench-obs = {
  dashboardFiles."workload.json" = ./workload.json;
  extraAlertRules.host = [{
    alert = "ExpectedGuestsMissing";
    expr = "count(incus_memory_MemTotal_bytes) < 2 or absent(incus_memory_MemTotal_bytes)";
    for = "3m";
    labels.severity = "critical";
  }];
};
```

The explicit `dashboards` directory option replaces `dashboardFiles` provisioning entirely.
Its entry count supplies the alert inventory, preserving the directory override contract; keep
only dashboard files in that directory. `alertRules` can replace the generator with a Nix file
accepting `lib`, `jobs`, `nodeTargetCount`, `dashboardCount` and `soakEngines`. It returns an
attribute set of Prometheus groups (`name`, `rules`). Extra rules append to those groups' keys,
so custom generators define their own valid keys. Keep names unique and avoid rule-order
dependencies when composing groups. The bundled rules contain only alerts, with no recording
rules or expressions reading `ALERTS`.

## Targeted check

From the public repository root:

```sh
nix build --no-link .#checks.aarch64-darwin.bench-observability
```

The same check is available under `checks.aarch64-linux` and `checks.x86_64-linux`.

This evaluates standalone synthetic compositions, exercises extension and legacy overrides,
rejects unknown groups and invalid filenames, builds the static dashboard directory, and runs
`promtool check rules`. It does not boot or activate a host, test network reachability, or verify
that exporters emit all expected runtime metrics.
