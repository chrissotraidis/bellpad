#!/usr/bin/env python3
"""Export clean app and exact maintained sources, never ignored/private working data."""
import hashlib
import io
import json
import pathlib
import subprocess
import sys
import tarfile

from importlib.machinery import SourceFileLoader

ROOT = pathlib.Path(__file__).resolve().parents[1]
sources = SourceFileLoader("maintained_sources", str(ROOT / "scripts/maintained-sources.py")).load_module()


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: source-archive.py /absolute/path/to/source.tar.gz")
    output = pathlib.Path(sys.argv[1]).resolve()
    if ROOT in output.parents:
        raise SystemExit("Write the archive outside the source checkout")
    lock = json.loads((ROOT / "sources.lock.json").read_text())
    for component in lock["components"]:
        sources.verify_component(component)
    if sources.git(ROOT, "status", "--porcelain", "--untracked-files=all"):
        raise SystemExit("Source delivery requires a clean committed app checkout")
    manifest = {"schema": 1, "appCommit": sources.git(ROOT, "rev-parse", "HEAD"), "components": lock["components"], "files": {}}
    inputs = [(ROOT, "")] + [(ROOT / c["path"], c["path"] + "/") for c in lock["components"]]
    output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(output, "w:gz") as out:
        for checkout, prefix in inputs:
            data = subprocess.check_output(["git", "-C", str(checkout), "archive", "HEAD"])
            with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                for member in archive:
                    if member.isdir():
                        continue
                    if not member.isfile():
                        raise SystemExit(f"Unsupported archive entry: {prefix}{member.name}")
                    contents = archive.extractfile(member).read()
                    member.name = prefix + member.name
                    # Git tracks the executable bit, not group-write permissions.
                    # Normalize modes so extraction under umask 022 is identical.
                    member.mode = 0o755 if member.mode & 0o111 else 0o644
                    member.uid = member.gid = 0
                    member.uname = member.gname = ""
                    out.addfile(member, io.BytesIO(contents))
                    manifest["files"][member.name] = [hashlib.sha256(contents).hexdigest(), member.mode]
        contents = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
        member = tarfile.TarInfo("SOURCE_MANIFEST.json")
        member.size = len(contents)
        member.mode = 0o644
        out.addfile(member, io.BytesIO(contents))
    print(f"{hashlib.sha256(output.read_bytes()).hexdigest()}  {output}")


if __name__ == "__main__":
    main()
