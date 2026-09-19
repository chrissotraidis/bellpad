#!/usr/bin/env python3
"""Record source identity in a package without local paths or signing identifiers."""
import hashlib
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parents[1]
def command(*args):
    return subprocess.check_output(args, text=True).strip()

if (root / ".git").exists():
    commit = command("git", "-C", str(root), "rev-parse", "HEAD")
    dirty = bool(command("git", "-C", str(root), "status", "--porcelain", "--untracked-files=all"))
else:
    commit = json.loads((root / "SOURCE_MANIFEST.json").read_text())["appCommit"]
    dirty = False
data = {"schema": 1, "appCommit": commit, "developmentChanges": dirty,
        "sources": json.loads((root / "sources.lock.json").read_text()),
        "productDependencies": json.loads((root / "product-dependencies.lock.json").read_text()),
        "noticesSha256": hashlib.sha256((root / "THIRD_PARTY_NOTICES.txt").read_bytes()).hexdigest(),
        "xcode": command("xcodebuild", "-version"), "clang": command("xcrun", "clang", "--version").splitlines()[0]}
if sys.argv[1] == "--verify":
    recorded = json.loads(pathlib.Path(sys.argv[2]).read_text())
    if data["developmentChanges"] or recorded != data:
        raise SystemExit("Package provenance is stale or records uncommitted changes; build from the clean selected source")
    print(f"Verified clean package provenance {commit}")
else:
    pathlib.Path(sys.argv[1]).write_text(json.dumps(data, indent=2) + "\n")
