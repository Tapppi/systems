"""Poll the Hatchet REST API and write node-exporter textfile metrics.

Hatchet exports no queue-depth gauge: every hatchet_* Prometheus series is
an unlabelled tenant-global counter, and no exported metric carries a
worker-class or queue label. Depth per queue is only available over REST,
so this poller turns two REST reads into gauges.

Endpoints (tenant-scoped, worker JWT as bearer):
  GET /api/v1/tenants/{tenant}/step-run-queue-metrics
      -> {"queues": {"<workflow>:<step>": <depth>, ...}}
         Only non-empty queues appear.
  GET /api/v1/stable/tenants/{tenant}/task-metrics?since=<ISO8601>
      -> [{"status": "QUEUED", "count": n}, ...]  tenant-global
         `since` is required; without it every count is 0 and the call
         still returns 200.
  GET /api/v1/tenants/{tenant}/workflows/scheduled
      -> {"rows": [{"metadata": {"id": ...}, "triggerAt": <ISO8601>,
                    "workflowName": ...}, ...]}
         A run scheduled for the future is in no Hatchet metric and no
         queue: until it fires it exists only here.
"""

import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timedelta, timezone

BASE = os.environ.get("HATCHET_API_URL", "http://dogmatix:8888").rstrip("/")
# Missing credentials are reported as hatchet_poller_up 0 like any other
# failure, so they are fetched leniently here and checked in collect().
TOKEN = os.environ.get("HATCHET_API_TOKEN", "")
TENANT = os.environ.get("HATCHET_TENANT_ID", "")
OUT = os.environ.get("OUT", "/var/lib/node-exporter-textfile/hatchet.prom")
# Queues that must always report a value. A queue with no pending work is
# absent from the API response, and an absent series is indistinguishable
# from a dead poller on a dashboard, so these are zero-filled.
KNOWN_QUEUES = os.environ.get("HATCHET_QUEUES", "").split()
SINCE_HOURS = float(os.environ.get("HATCHET_SINCE_HOURS", "24"))
TIMEOUT = float(os.environ.get("HATCHET_HTTP_TIMEOUT", "10"))

# Statuses the API reports; zero-filled for the same reason as queues.
STATUSES = ["QUEUED", "RUNNING", "COMPLETED", "FAILED", "CANCELLED"]


def get(path):
    req = urllib.request.Request(
        BASE + path, headers={"Authorization": "Bearer " + TOKEN}
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.load(resp)


def esc(value):
    return value.replace("\\", "\\\\").replace('"', '\\"')


def short_queue(key):
    """Collapse the "<workflow>:<step>" key to one name when both halves
    match, which is the shape single-step bench tasks produce."""
    head, sep, tail = key.partition(":")
    return head if sep and head == tail else key


def previous(name):
    """Read a value back out of the file this poller wrote last time.

    The textfile collector offers no other persistence, and two of the
    liveness metrics need it: the last-success timestamp is carried across a
    failed poll so the gap is measurable, and the failure counter has to
    accumulate rather than be rewritten — a gauge that fails and recovers
    inside one scrape interval leaves no trace at all."""
    try:
        with open(OUT, encoding="utf-8") as fh:
            for line in fh:
                key, _, value = line.partition(" ")
                if key == name:
                    return float(value)
    except (OSError, ValueError):
        pass
    return 0.0


def collect_queue_depth():
    """Per-queue depth — the wake-on-LAN signal, and the reason this poller
    exists at all."""
    queues = get(f"/api/v1/tenants/{TENANT}/step-run-queue-metrics").get("queues") or {}
    depths = {}
    for key, depth in queues.items():
        depths[short_queue(key)] = int(depth)
    for name in KNOWN_QUEUES:
        depths.setdefault(name, 0)

    lines = [
        "# HELP hatchet_queue_depth Tasks queued per Hatchet step queue.",
        "# TYPE hatchet_queue_depth gauge",
    ]
    for name in sorted(depths):
        lines.append(f'hatchet_queue_depth{{queue="{esc(name)}"}} {depths[name]}')
    return lines


def collect_task_status():
    """Tenant-global counts over a trailing window. Informational — a failure
    here must not take the depth gauges down with it."""
    since = (datetime.now(timezone.utc) - timedelta(hours=SINCE_HOURS)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    metrics = get(f"/api/v1/stable/tenants/{TENANT}/task-metrics?since={since}")
    counts = {s: 0 for s in STATUSES}
    running_detail = {}
    for entry in metrics or []:
        status = entry.get("status")
        if not status:
            continue
        counts[status] = counts.get(status, 0) + int(entry.get("count") or 0)
        for detail, value in (entry.get("runningDetailCount") or {}).items():
            running_detail[detail] = int(value or 0)

    lines = [
        "# HELP hatchet_tasks_by_status Tenant-global task counts over the "
        f"trailing {SINCE_HOURS:g}h window.",
        "# TYPE hatchet_tasks_by_status gauge",
    ]
    for status in sorted(counts):
        lines.append(f'hatchet_tasks_by_status{{status="{esc(status)}"}} {counts[status]}')

    if running_detail:
        lines.append(
            "# HELP hatchet_tasks_running_detail Running tasks split by placement."
        )
        lines.append("# TYPE hatchet_tasks_running_detail gauge")
        for detail in sorted(running_detail):
            lines.append(
                f'hatchet_tasks_running_detail{{detail="{esc(detail)}"}} '
                f"{running_detail[detail]}"
            )
    return lines


def collect_scheduled_runs():
    """Runs scheduled for a future trigger time. Nothing else observes them:
    they hold no queue slot, move no counter, and appear on no dashboard, so
    a scheduled run silently disappearing looks exactly like nothing
    happening. The bench parks a five-day run this way."""
    rows = get(f"/api/v1/tenants/{TENANT}/workflows/scheduled?limit=200").get("rows") or []
    lines = [
        "# HELP hatchet_scheduled_runs_total Runs scheduled for a future trigger.",
        "# TYPE hatchet_scheduled_runs_total gauge",
        f"hatchet_scheduled_runs_total {len(rows)}",
        "# HELP hatchet_scheduled_run_next_trigger_timestamp_seconds Unix time the "
        "soonest scheduled run of a workflow fires.",
        "# TYPE hatchet_scheduled_run_next_trigger_timestamp_seconds gauge",
    ]
    # Grouped by workflow rather than emitted per run: a run id is unbounded
    # over time, and every one ever scheduled would mint a permanent series.
    soonest = {}
    for row in rows:
        trigger = row.get("triggerAt")
        if not trigger:
            continue
        epoch = datetime.fromisoformat(trigger.replace("Z", "+00:00")).timestamp()
        name = row.get("workflowName") or ""
        soonest[name] = min(soonest.get(name, epoch), epoch)
    for name in sorted(soonest):
        lines.append(
            f'hatchet_scheduled_run_next_trigger_timestamp_seconds'
            f'{{workflow_name="{esc(name)}"}} {soonest[name]:.0f}'
        )
    return lines


def write(lines):
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    os.replace(tmp, OUT)


def main():
    started = time.time()
    lines, errors = [], []
    if not TOKEN or not TENANT:
        errors.append("HATCHET_API_TOKEN and HATCHET_TENANT_ID must be set")
    else:
        # Each section stands alone: a fault in the informational one must not
        # blank the depth gauges. Any exception at all means up 0 — a handler
        # that lets an unexpected type escape would leave the previous file,
        # and its up 1, in place indefinitely.
        for section in (collect_queue_depth, collect_task_status, collect_scheduled_runs):
            try:
                lines.extend(section())
            except Exception as exc:  # noqa: BLE001 — see above
                errors.append(f"{section.__name__}: {exc}")

    up = 0 if errors else 1
    last_success = (
        time.time() if up else previous("hatchet_poller_last_success_timestamp_seconds")
    )
    failures = int(previous("hatchet_poller_failures_total")) + (0 if up else 1)

    lines.append("# HELP hatchet_poller_up 1 when the last REST poll succeeded.")
    lines.append("# TYPE hatchet_poller_up gauge")
    lines.append(f"hatchet_poller_up {up}")
    lines.append("# HELP hatchet_poller_failures_total Polls that failed a section.")
    lines.append("# TYPE hatchet_poller_failures_total counter")
    lines.append(f"hatchet_poller_failures_total {failures}")
    lines.append(
        "# HELP hatchet_poller_last_success_timestamp_seconds Unix time of the "
        "last successful poll."
    )
    lines.append("# TYPE hatchet_poller_last_success_timestamp_seconds gauge")
    lines.append(f"hatchet_poller_last_success_timestamp_seconds {last_success:.0f}")
    lines.append("# HELP hatchet_poller_duration_seconds Wall time of the last poll.")
    lines.append("# TYPE hatchet_poller_duration_seconds gauge")
    lines.append(f"hatchet_poller_duration_seconds {time.time() - started:.3f}")

    write(lines)
    for err in errors:
        print(f"hatchet queue poll failed: {err}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
