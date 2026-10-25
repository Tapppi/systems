"""Behavioral recovery checks execute the packaged shell, with offline process doubles."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SETUP = os.environ["SETUP_UNDER_TEST"]
PYTHON = os.environ["PYTHON_UNDER_TEST"]


class Setup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="skills test ")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.root = self.home / ".local/share/agent-skills"
        self.venv = self.root / "venv"
        self.env = {"HOME": str(self.home), "PATH": os.environ["PATH"], "TMPDIR": str(self.home)}

    def run_setup(self, action="venv", failure="", success=True):
        result = subprocess.run([SETUP, action], env=self.env | {"FAKE_FAIL": failure},
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def seed_extra(self):
        file = self.venv / "installed.json"
        data = json.loads(file.read_text()); data["retained_extra"] = "7.2"
        file.write_text(json.dumps(data))
        (self.venv / "lib/python3.14/site-packages/retained_extra-7.2.dist-info").mkdir()

    def snapshot(self):
        return {str(p.relative_to(self.venv)): ("link", os.readlink(p)) if p.is_symlink() else p.read_bytes()
                for p in self.venv.rglob("*") if p.is_symlink() or p.is_file()}

    def test_help_has_no_writes(self):
        self.run_setup("--help")
        self.assertEqual(list(self.home.iterdir()), [])

    def test_repeat_preserves_valid_environment_and_python_extra(self):
        self.run_setup(); self.seed_extra()
        inode = self.venv.stat().st_ino
        self.run_setup()
        self.assertEqual(self.venv.stat().st_ino, inode)
        self.assertEqual(json.loads((self.venv / "installed.json").read_text())["retained_extra"], "7.2")
        events = [json.loads(line) for line in (self.home / "events.jsonl").read_text().splitlines()]
        self.assertEqual(sum(event[:2] == ["uv", "venv"] for event in events), 1)

    def test_node_prefix_preserves_declared_extra(self):
        self.run_setup("node")
        manifest = self.root / "node/package.json"
        data = json.loads(manifest.read_text()); data["dependencies"]["retained-extra"] = "7.2"
        manifest.write_text(json.dumps(data)); self.run_setup("node")
        self.assertEqual(json.loads(manifest.read_text())["dependencies"]["retained-extra"], "7.2")

    def test_wrong_minor_rebuild_restores_extra_names(self):
        self.run_setup(); self.seed_extra(); (self.venv / "minor").write_text("3.13")
        self.run_setup()
        self.assertEqual((self.venv / "minor").read_text(), "3.14")
        self.assertIn("retained_extra", json.loads((self.venv / "installed.json").read_text()))
        self.assertFalse((self.root / "venv.old").exists())

    def test_broken_interpreter_recovers_from_metadata(self):
        self.run_setup(); self.seed_extra()
        (self.venv / "bin/python").unlink(); (self.venv / "bin/python").symlink_to("/missing-synthetic-python")
        self.run_setup()
        self.assertFalse((self.venv / "bin/python").is_symlink())
        self.assertIn("retained_extra", json.loads((self.venv / "installed.json").read_text()))

    def test_wrong_binding_rebuilds(self):
        self.run_setup(); (self.venv / "pyvenv.cfg").write_text("home = /synthetic/other-python\n")
        self.run_setup()
        self.assertIn("/uv/python/cpython-3.14-", (self.venv / "pyvenv.cfg").read_text())

    def test_failed_rebuild_restores_exact_old_environment(self):
        for failure in ["venv", "install", "extras", "browser"]:
            with self.subTest(failure=failure):
                self.run_setup(); self.seed_extra(); (self.venv / "minor").write_text("3.13")
                before = self.snapshot()
                self.run_setup(failure=failure, success=False)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse((self.root / "venv.old").exists())
                # Return to valid state before the next subcase.
                self.run_setup()
                import shutil
                shutil.rmtree(self.venv)

    def test_interrupted_old_copy_is_not_removed(self):
        self.run_setup(); before = self.snapshot()
        old = self.root / "venv.old"; old.mkdir(); (old / "keep").write_text("recovery")
        self.run_setup(success=False)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual((old / "keep").read_text(), "recovery")

    def test_failed_new_environment_is_removed(self):
        self.run_setup(failure="browser", success=False)
        self.assertFalse(self.venv.exists())
        self.assertFalse((self.root / ".setup-lock").exists())

    def test_all_stages_run_and_failure_propagates(self):
        self.run_setup("all", failure="install", success=False)
        self.assertTrue((self.home / "tool-installed").exists())
        self.assertTrue((self.root / "node/package.json").exists())

    def test_lock_refuses_concurrent_setup(self):
        (self.root / ".setup-lock").mkdir(parents=True)
        self.run_setup(success=False)
        self.assertFalse((self.home / "events.jsonl").exists())

    def test_redirected_destination_is_not_modified(self):
        outside = self.home / "outside"; outside.mkdir(); (outside / "keep").touch()
        self.root.mkdir(parents=True); (self.root / "venv").symlink_to(outside)
        self.run_setup(success=False)
        self.assertEqual(list(outside.iterdir()), [outside / "keep"])

    def test_home_symlink_spellings_refuse_without_redirected_writes(self):
        target = self.home / "redirect-target"; target.mkdir()
        (target / "keep").write_text("untouched")
        link = self.home / "home-link"; link.symlink_to(target)
        spellings = [str(link), str(link) + "/", str(link) + "///", str(link) + "/.",
                     str(self.home) + "//home-link", str(self.home) + "/./home-link",
                     str(link) + "/../redirect-target"]
        for spelling in spellings:
            with self.subTest(home=spelling):
                result = subprocess.run([SETUP, "node"], env=self.env | {"HOME": spelling},
                                        capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(target.iterdir()), [target / "keep"])
                self.assertEqual((target / "keep").read_text(), "untouched")
                self.assertFalse((self.home / "events.jsonl").exists())
                self.assertFalse((self.home / ".local").exists())

    def test_ordinary_home_redundant_spellings_refuse_without_writes(self):
        for suffix in ["/", "//", "/.", "/child/..", "/./child"]:
            with self.subTest(suffix=suffix):
                result = subprocess.run([SETUP, "node"], env=self.env | {"HOME": str(self.home) + suffix},
                                        capture_output=True, timeout=10)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(self.home.iterdir()), [])

    def test_root_store_aliases_use_pure_preflight_without_filesystem_writes(self):
        # Call only the production lexical function: never run setup against real root/store paths.
        invalid = ["", "/", "//", "/.", "/..", "/nix/store", "/nix/store/", "/nix//store",
                   "/nix/./store", "/nix/../nix/store", "/nix/store/child", "/other/../nix/store",
                   "relative", "/ordinary/../"]
        valid = [str(self.home), "/tmp/ordinary", "/var/ordinary", "/nix/storehouse", "/ordinary/.hidden"]
        for spelling in invalid + valid:
            with self.subTest(home=spelling):
                result = subprocess.run(["bash", "-c", 'source "$1"; agent_skills_home_spelling_valid "$2"',
                                         "preflight-test", os.environ["HOME_VALIDATOR"], spelling],
                                        env=self.env, capture_output=True, timeout=10)
                self.assertEqual(result.returncode == 0, spelling in valid)
                self.assertEqual(list(self.home.iterdir()), [])

    def test_unrelated_file_at_environment_destination_is_preserved(self):
        self.root.mkdir(parents=True); self.venv.write_text("unrelated file")
        self.run_setup(success=False)
        self.assertEqual(self.venv.read_text(), "unrelated file")

    def test_python_launcher_forwards_arguments_and_rejects_missing_environment(self):
        args = ["script with spaces.py", "a;not-a-command", "--flag"]
        missing = subprocess.run([PYTHON, *args], env=self.env, capture_output=True)
        self.assertNotEqual(missing.returncode, 0)
        self.run_setup()
        result = subprocess.run([PYTHON, *args], env=self.env, capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout), args)


unittest.main()
