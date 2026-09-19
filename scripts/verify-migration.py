#!/usr/bin/env python3
"""One-time/history regression: archived patches must reproduce the imported trees."""
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def git(path, *args, **kwargs):
    return subprocess.check_output(["git", "-C", str(path), *args], **kwargs)


mapping = json.loads((ROOT / "docs/source-maintenance/migration.json").read_text())
for name, folder in [("pc-port", "acgc-64bit"), ("aurora", "aurora")]:
    record = mapping[name]
    source = ROOT / "source" / folder
    with tempfile.TemporaryDirectory(prefix="bellpad-history-") as temp:
        git(temp, "init", "--quiet")
        git(temp, "fetch", "--quiet", str(source), record["base"])
        git(temp, "checkout", "--quiet", "--detach", "FETCH_HEAD")
        for patch in record["patches"]:
            args = ["apply", "--index"]
            if name == "pc-port":
                args.append("--unidiff-zero")
            git(temp, *args, str(ROOT / patch["patch"]))
        tree = git(temp, "write-tree", text=True).strip()
        if tree != record["tree"]:
            raise SystemExit(f"Prepared source parity failed: {name}")
        changes = git(source, "diff", "--name-only", record["commit"], record["selectedCommit"], text=True).splitlines()
        if set(changes) != {".gitignore", "BELLPAD.md"}:
            raise SystemExit(f"Unexpected migration differences: {name}: {changes}")
        print(f"{name}: {len(record['patches'])} patches reproduce tree {tree}; only documented metadata differs")
