"""Exercise a local headless server in an empty home with private Unix sockets."""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import tomllib

binary, config, expected_version = sys.argv[1:]
# Short paths avoid the Unix-domain socket path limit on Darwin.
with tempfile.TemporaryDirectory(prefix="herdr-", dir=os.environ["TMPDIR"]) as root:
    root = Path(root)
    home = root / "home"
    home.mkdir()
    runtime_config = root / "config.toml"
    # Network refresh is independently covered by the parsed production settings.
    runtime_config.write_text(Path(config).read_text().replace("manifest_check = true", "manifest_check = false"))
    assert tomllib.loads(runtime_config.read_text())["update"]["manifest_check"] is False
    env = {
        "HOME": str(home), "PATH": os.environ["PATH"], "TMPDIR": str(root),
        "XDG_CONFIG_HOME": str(home / ".config"), "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_CACHE_HOME": str(home / ".cache"), "HERDR_CONFIG_PATH": str(runtime_config),
        "HERDR_SOCKET_PATH": str(root / "api.sock"), "TERM": "xterm-256color",
    }
    with (root / "server.log").open("w+") as log:
        server = subprocess.Popen([binary, "server"], env=env, cwd=home,
                                  stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            deadline = time.monotonic() + 15
            status = None
            while time.monotonic() < deadline:
                if server.poll() is not None:
                    raise RuntimeError(f"server exited {server.returncode}")
                result = subprocess.run([binary, "status", "--json"], env=env, cwd=home,
                                        capture_output=True, text=True, timeout=3)
                if result.returncode == 0:
                    status = json.loads(result.stdout)
                    if status["server"]["running"]:
                        break
                time.sleep(0.1)
            assert status and status["server"]["running"], status
            assert status["client"]["version"] == expected_version, status
            assert status["server"]["version"] == expected_version, status
            assert status["server"]["compatible"] is True, status
            assert status["server"]["endpoint_compatible"] is True, status
            assert Path(status["server"]["socket"]).parent == root, status
            print(json.dumps(status, sort_keys=True))
            subprocess.run([binary, "server", "stop"], env=env, cwd=home, check=True, timeout=5)
            assert server.wait(timeout=5) == 0
        finally:
            if server.poll() is None:
                os.killpg(server.pid, signal.SIGTERM)
                try:
                    server.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(server.pid, signal.SIGKILL)
                    server.wait(timeout=3)
            log.seek(0)
            print(log.read())
