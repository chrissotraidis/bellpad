"""Exercise artifact identity failures without retail data or a game build."""
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

PROJECT = pathlib.Path(__file__).resolve().parents[1]


class SourceDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="bellpad-delivery-")
        self.addCleanup(self.temporary.cleanup)
        self.work = pathlib.Path(self.temporary.name)
        self.root = self.work / "source"
        (self.root / "scripts").mkdir(parents=True)
        for name in ("maintained-sources.py", "source-archive.py", "build-provenance.py"):
            shutil.copyfile(PROJECT / "scripts" / name, self.root / "scripts" / name)
        (self.root / "sources.lock.json").write_text('{"schema":1,"components":[]}\n')
        (self.root / "product-dependencies.lock.json").write_text('{"dependencies":[]}\n')
        (self.root / "THIRD_PARTY_NOTICES.txt").write_text("Synthetic test fixture\n")
        (self.root / ".gitignore").write_text("build/\n__pycache__/\n")
        (self.root / "example.c").write_text("int example(void) { return 0; }\n")
        self.command("git", "init", "-q", str(self.root))
        self.command("git", "-C", str(self.root), "add", ".")
        self.command("git", "-C", str(self.root), "-c", "user.name=Fixture", "-c",
                     "user.email=fixture@example.invalid", "commit", "-qm", "Fixture")
        self.app = self.root / "build/Bellpad.app"
        self.app.mkdir(parents=True)
        self.info = {"CFBundleExecutable": "Bellpad", "CFBundleIdentifier": "dev.bellpad.fixture",
                     "CFBundleVersion": "1", "CFBundleShortVersionString": "0.1.0",
                     "MinimumOSVersion": "17.0"}
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))
        # This tests content binding, not executable validity (audited separately).
        (self.app / "Bellpad").write_bytes(b"synthetic executable fixture")

    def command(self, *args, success=True):
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def provenance(self, verify=False, root=None, app=None, success=True):
        root, app = root or self.root, app or self.app
        return self.command(sys.executable, str(root / "scripts/build-provenance.py"),
                            *(["--verify"] if verify else []), str(app / "SourceProvenance.json"),
                            success=success)

    def test_executable_and_bundle_identity_are_bound(self):
        self.provenance()
        self.provenance(verify=True)
        binary = self.app / "Bellpad"
        original = binary.read_bytes()
        binary.write_bytes(original + b" changed")
        self.provenance(verify=True, success=False)
        binary.write_bytes(original)
        self.info["CFBundleVersion"] = "999"
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info))
        self.provenance(verify=True, success=False)

    def test_archive_is_deterministic_and_offline_changes_are_rejected(self):
        first, second = self.work / "first.tar.gz", self.work / "different-name.tar.gz"
        for output in (first, second):
            self.command(sys.executable, str(self.root / "scripts/source-archive.py"), str(output))
        self.assertEqual(first.read_bytes(), second.read_bytes())
        restored = self.work / "restored"
        restored.mkdir()
        self.command("tar", "-xzf", str(first), "-C", str(restored))
        self.command(sys.executable, str(restored / "scripts/maintained-sources.py"), "verify")
        app = restored / "build/Bellpad.app"
        shutil.copytree(self.app, app)
        self.provenance(root=restored, app=app)
        (restored / "example.c").write_text("int example(void) { return 1; }\n")
        self.provenance(root=restored, app=app, success=False)
        self.provenance(root=restored, app=app, verify=True, success=False)

    def test_dirty_source_cannot_be_packaged_or_archived(self):
        self.provenance()
        (self.root / "example.c").write_text("int example(void) { return 2; }\n")
        self.provenance(verify=True, success=False)
        self.command(sys.executable, str(self.root / "scripts/source-archive.py"),
                     str(self.work / "dirty.tar.gz"), success=False)


if __name__ == "__main__":
    unittest.main()
