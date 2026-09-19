#!/usr/bin/env python3
"""Prepare pinned submodules without rewriting existing sources; verify exports offline."""
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def git(path, *args):
    return subprocess.check_output(["git", "-C", str(path), *args], text=True).strip()


def fail(message):
    raise SystemExit(message)


def verify_export():
    manifest = json.loads((ROOT / "SOURCE_MANIFEST.json").read_text())
    for name, expected in manifest["files"].items():
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            fail(f"Missing or unsafe exported source: {name}")
        actual = [hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mode & 0o777]
        if actual != expected:
            fail(f"Modified exported source: {name}")
    lock = json.loads((ROOT / "sources.lock.json").read_text())
    if manifest["components"] != lock["components"]:
        fail("Export provenance and source pins disagree")
    for component in lock["components"]:
        source = ROOT / component["path"]
        for path in source.rglob("*"):
            relative = path.relative_to(source)
            # Normal out-of-source build outputs are permitted after restoration.
            if any(part.startswith("build-") for part in relative.parts):
                continue
            if path.is_file() and str(path.relative_to(ROOT)) not in manifest["files"]:
                fail(f"Unrecorded exported source: {path.relative_to(ROOT)}")
    print(f"Verified {len(manifest['files'])} exported files without Git or network")


def verify_component(component, prepare=False):
    path = ROOT / component["path"]
    if not (path / ".git").exists():
        if not prepare:
            fail(f"Missing submodule: {path}; run the fetch scripts")
        if path.exists() and any(path.iterdir()):
            fail(f"Refusing to replace existing source at {path}")
        subprocess.run(["git", "-C", str(ROOT), "submodule", "update", "--init", "--recursive", "--", component["path"]], check=True)
    if git(path, "rev-parse", "HEAD") != component["commit"]:
        fail(f"Source pin mismatch: {path}. Preserve local work before selecting the locked commit.")
    if git(path, "rev-parse", "HEAD^{tree}") != component["tree"]:
        fail(f"Source tree mismatch: {path}")
    if git(path, "status", "--porcelain", "--untracked-files=all"):
        fail(f"Dirty source: {path}. Commit and update the app pin, or preserve edits separately.")
    entry = git(ROOT, "ls-files", "--stage", "--", component["path"]).split()
    if entry[:2] != ["160000", component["commit"]]:
        fail(f"Gitlink and lock disagree: {component['path']}")
    configured = git(ROOT, "config", "-f", ".gitmodules", "--get", f"submodule.{component['path']}.url")
    if configured != component["url"]:
        fail(f"Submodule URL and lock disagree: {component['path']}")
    print(f"Verified {component['name']} {component['commit']}")


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if command not in ("verify", "prepare"):
        fail("Usage: maintained-sources.py verify | prepare [component]")
    if not (ROOT / ".git").exists():
        verify_export()
        return
    selected = sys.argv[2] if len(sys.argv) > 2 else None
    components = json.loads((ROOT / "sources.lock.json").read_text())["components"]
    if selected and selected not in [c["name"] for c in components]:
        fail(f"Unknown component: {selected}")
    for component in components:
        if not selected or selected == component["name"]:
            verify_component(component, command == "prepare")


if __name__ == "__main__":
    main()
