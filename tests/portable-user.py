"""Check parsed configuration and the one-file immutable / writable-state boundary."""
import json
from pathlib import Path
import sys
import tomllib

home = Path(sys.argv[1])
expected = json.loads(Path(sys.argv[2]).read_text())
config = home / ".config/herdr/config.toml"
assert config.is_symlink()
assert not (config.stat().st_mode & 0o222), "store config must be immutable"
assert tomllib.loads(config.read_text()) == expected
before = config.read_bytes()
for relative in [".config/herdr/manifests/fixture.json", ".cache/herdr/fixture"]:
    state = home / relative
    state.parent.mkdir(parents=True, exist_ok=True)
    state.write_text("synthetic mutable state")
    state.write_text("updated mutable state")
    assert state.read_text() == "updated mutable state"
assert config.read_bytes() == before
print("parsed settings and writable sibling state: PASS")
