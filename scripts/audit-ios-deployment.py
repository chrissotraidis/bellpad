#!/usr/bin/env python3
"""Keep Ninja-produced bundle deployment metadata consistent with its Mach-O."""
import argparse
import pathlib
import plistlib
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--write", action="store_true", help="Finalize an unsigned development bundle")
parser.add_argument("app", type=pathlib.Path)
args = parser.parse_args()
plist_path = args.app / "Info.plist"
info = plistlib.loads(plist_path.read_bytes())
binary = args.app / info["CFBundleExecutable"]
build = subprocess.check_output(["xcrun", "vtool", "-show-build", str(binary)], text=True)
platforms = re.findall(r"^\s*platform\s+(\S+)", build, re.MULTILINE)
versions = re.findall(r"^\s*minos\s+(\S+)", build, re.MULTILINE)
if len(versions) != 1 or platforms not in (["IOS"], ["IOSSIMULATOR"]):
    raise SystemExit("Expected one iOS device or Simulator Mach-O deployment target")
minimum = versions[0]
if args.write:
    # Xcode normally writes this field; CMake's Ninja bundle path does not.
    info["MinimumOSVersion"] = minimum
    plist_path.write_bytes(plistlib.dumps(info, sort_keys=False))
if info.get("MinimumOSVersion") != minimum:
    raise SystemExit(f"MinimumOSVersion {info.get('MinimumOSVersion')!r} does not match executable {minimum}")
print(f"Verified {platforms[0]} MinimumOSVersion {minimum}")
