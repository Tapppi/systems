"""Exercise the provisioned static directory, including consumer extension."""
import json
from pathlib import Path
import sys

base, extended = map(Path, sys.argv[1:])
assert {p.name for p in base.iterdir()} == {"bench-incus.json", "bench-postgres.json"}
assert {p.name for p in extended.iterdir()} == {"bench-incus.json", "bench-postgres.json", "sample.json"}
uids = set()
for path in extended.iterdir():
    dashboard = json.loads(path.read_text())
    assert dashboard["uid"] not in uids, "dashboard UID collision"
    uids.add(dashboard["uid"])
    if path.name == "sample.json":
        continue
    assert dashboard == json.loads((base / path.name).read_text())
    variables = {v["name"]: v for v in dashboard["templating"]["list"]}
    assert variables["ds"]["current"]["value"] == "bench-prometheus"
    selection = "guest" if path.name == "bench-incus.json" else "db"
    assert variables[selection]["type"] == "query"
    assert variables[selection]["includeAll"] and variables[selection]["multi"]
    expressions = [t["expr"] for p in dashboard["panels"] for t in p.get("targets", [])]
    assert any(f"${selection}" in expr for expr in expressions), "selection must affect queries"
print("Static dashboard provisioning and query selectors passed")
