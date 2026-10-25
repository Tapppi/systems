"""Offline process doubles for the setup lifecycle; never used by production packages."""
import json
import os
from pathlib import Path
import sys

mode, *args = sys.argv[1:]
home = Path(os.environ["HOME"])
root = home / ".local/share/agent-skills"
managed = home / ".local/share/uv/python"
with (home / "events.jsonl").open("a") as log:
    log.write(json.dumps([mode, *args]) + "\n")
failure = os.environ.get("FAKE_FAIL", "")


def make_script(path, kind, venv):
    path.write_text(f"#!{sys.executable}\nimport os,runpy,sys\nos.environ['FAKE_VENV']={str(venv)!r}\n"
                    f"sys.argv.insert(1,{kind!r})\n"
                    f"runpy.run_path({str(Path(__file__).resolve())!r},run_name='__main__')\n")
    path.chmod(0o755)


def packages(venv):
    file = venv / "installed.json"
    return json.loads(file.read_text()) if file.exists() else {}


if mode == "uv":
    if args == ["python", "dir"]:
        print(managed)
    elif args[:2] == ["python", "install"]:
        assert args[2:] == ["--no-bin", "3.14"]
        managed.mkdir(parents=True, exist_ok=True)
    elif args[0] == "venv":
        if failure == "venv": sys.exit(1)
        assert args[1:4] == ["--managed-python", "--python", "3.14"]
        venv = Path(args[-1]); (venv / "bin").mkdir(parents=True)
        (venv / "pyvenv.cfg").write_text(f"home = {managed}/cpython-3.14-test/bin\n")
        (venv / "minor").write_text("3.14")
        make_script(venv / "bin/python", "python", venv)
    elif args[:2] == ["pip", "freeze"]:
        venv = Path(args[args.index("--python") + 1]).parent.parent
        for name, version in packages(venv).items():
            print(f"{name} @ file:///synthetic/package.whl" if name == "retained_extra" else f"{name}=={version}")
    elif args[:2] == ["pip", "install"]:
        venv = Path(args[args.index("--python") + 1]).parent.parent
        requirements = Path(args[args.index("-r") + 1])
        if failure == "install" or (failure == "extras" and requirements.name.startswith(".extras.")):
            sys.exit(1)
        installed = packages(venv)
        for name in requirements.read_text().splitlines():
            if not name or name.startswith("#"): continue
            installed[name] = "1.0"
            (venv / "lib/python3.14/site-packages" / f"{name}-1.0.dist-info").mkdir(parents=True, exist_ok=True)
        (venv / "installed.json").write_text(json.dumps(installed))
        make_script(venv / "bin/playwright", "playwright", venv)
    elif args[:2] == ["tool", "install"]:
        assert args[2:] == ["--managed-python", "--python", "3.14", "markitdown[pptx,xlsx,xls]"]
        if failure == "tool": sys.exit(1)
        (home / "tool-installed").touch()
    else: raise AssertionError(args)
elif mode == "python":
    venv = Path(os.environ["FAKE_VENV"])
    if args[:1] == ["-c"]:
        sys.exit(0 if (venv / "minor").read_text() == args[-1] else 1)
    print(json.dumps(args))
elif mode == "playwright":
    assert args == ["install", "chromium"]
    if failure == "browser": sys.exit(1)
    (Path(os.environ["FAKE_VENV"]) / "browser-ready").touch()
elif mode == "npm":
    if failure == "npm": sys.exit(1)
    assert args[0] == "install"
    assert all(flag in args for flag in ["--ignore-scripts", "--no-audit", "--no-fund"])
    prefix = Path(args[args.index("--prefix") + 1]); manifest = prefix / "package.json"
    data = json.loads(manifest.read_text()) if manifest.exists() else {"dependencies": {}}
    for package in args:
        if package.endswith("@latest"): data["dependencies"][package[:-7]] = "latest"
    manifest.write_text(json.dumps(data))
else: raise AssertionError(mode)
