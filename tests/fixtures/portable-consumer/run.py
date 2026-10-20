#!/usr/bin/env python3
"""Bootstrap an independent disposable flake; never activate or modify the source lock."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--systems", type=Path, required=True, help="Candidate systems checkout")
parser.add_argument("--output", type=Path, required=True, help="New external directory, kept for evidence")
parser.add_argument("--build-system", action="append", default=[], help="Realize consumer checks on this platform")
args = parser.parse_args()
source = args.systems.resolve()
out = args.output.resolve()
if out == source or source in out.parents:
    parser.error("output must be external to the systems checkout")
out.mkdir(parents=True, exist_ok=False)
shutil.copyfile(Path(__file__).with_name("flake.nix"), out / "flake.nix")
records = []


def run(name, command, expect_failure=False):
    start = time.monotonic()
    with (out / (name + ".log")).open("w") as log:
        result = subprocess.run(command, cwd=out, stdout=log, stderr=subprocess.STDOUT)
    records.append({"name": name, "command": command, "exit_code": result.returncode,
                    "seconds": time.monotonic() - start, "expected_failure": expect_failure})
    (out / "commands.json").write_text(json.dumps(records, indent=2) + "\n")
    if (result.returncode == 0) == expect_failure:
        raise RuntimeError(f"{name} unexpected exit {result.returncode}; see {out / (name + '.log')}")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


source_lock = source / "flake.lock"
source_hash = digest(source_lock)
lock = json.loads(source_lock.read_text())
root_inputs = lock["nodes"][lock["root"]]["inputs"]


def ref(name):
    locked = lock["nodes"][root_inputs[name]]["locked"]
    if locked["type"] != "github":
        raise ValueError(f"unsupported bootstrap source for {name}: {locked['type']}")
    return f"github:{locked['owner']}/{locked['repo']}/{locked['rev']}"


command = ["nix", "flake", "lock", "--override-input", "systems", "path:" + str(source)]
for name in ["nixpkgs", "nixpkgs-fresh", "home-manager"]:
    command += ["--override-input", name, ref(name)]
run("bootstrap", command)
locked_hash = digest(out / "flake.lock")
# Evaluate every architecture independently, retaining every failure.
for system in ["aarch64-darwin", "aarch64-linux", "x86_64-linux"]:
    run("eval-" + system, ["nix", "eval", "--raw", f".#checks.{system}.consumer.drvPath",
                          "--no-write-lock-file"])
for system in args.build_system:
    run("build-" + system, ["nix", "build", "-L", "--keep-failed", "--no-link",
                           f".#checks.{system}.consumer", "--no-write-lock-file"])
# A caller that fails to supply the fresh package input must fail explicitly.
expression = ('let f = builtins.getFlake ' + json.dumps(str(out))
              + '; in f.inputs.systems.lib.harnessPackages { names = [ "claude-code" ]; }')
run("missing-fresh", ["nix", "eval", "--impure", "--json", "--expr", expression], expect_failure=True)
assert "pkgsFresh" in (out / "missing-fresh.log").read_text(), "negative control failed for an unrelated reason"
assert digest(out / "flake.lock") == locked_hash, "consumer no-write checks changed lock"
assert digest(source_lock) == source_hash, "source lock changed"
(out / "integrity.json").write_text(json.dumps({
    "consumer_lock_sha256": locked_hash, "source_lock_sha256": source_hash,
    "no_write_checks": "passed", "release_pin": False,
}, indent=2) + "\n")
print(out)
