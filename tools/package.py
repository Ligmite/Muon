#!/usr/bin/env python3
"""
Muon Shaders - tools/package.py

Shared packaging implementation used by build.ps1, build.sh and CI.

A shader pack is a zip whose top level is `shaders/`. This script:

  1. runs the static validator (and the generator checks) unless --skip-checks;
  2. writes <output-root>/release/Muon-<version>.zip with a deterministic layout;
  3. optionally copies the zip into <output-root>/archive/<version>/.

The output root defaults to the directory *containing* the repository, so a
checkout at `Muon/` produces `release/` and `archive/` beside it. Set
MUON_OUTPUT_ROOT to override that (CI points it at the checkout itself).

Determinism matters: the same checkout must produce the same archive bytes so
that a release can be verified by hash. Timestamps are therefore fixed.

Usage:
    python tools/package.py [--archive] [--skip-checks]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHADERS = ROOT / "shaders"

# Release artefacts live beside the repository, not inside it, so that a clone
# never carries build output. CI overrides this with MUON_OUTPUT_ROOT.
OUTPUT_ROOT = pathlib.Path(os.environ.get("MUON_OUTPUT_ROOT", ROOT.parent)).resolve()
DIST = OUTPUT_ROOT / "release"
ARCHIVE_ROOT = OUTPUT_ROOT / "archive"

FIXED_TIMESTAMP = (2026, 11, 11, 0, 0, 0)

# Files that exist in the repository but must never ship in the pack.
EXCLUDED_SUFFIXES = {".psd", ".blend", ".kra", ".bak", ".orig"}
EXCLUDED_NAMES = {"desktop.ini", ".DS_Store", "Thumbs.db"}


def read_version() -> str:
    data = json.loads((ROOT / "version.json").read_text(encoding="utf-8"))
    return data["version"]


def run(command: list[str]) -> int:
    print("$ " + " ".join(command))
    return subprocess.call(command, cwd=ROOT)


def collect_files() -> list[pathlib.Path]:
    files: list[pathlib.Path] = []
    for path in sorted(SHADERS.rglob("*")):
        if not path.is_file():
            continue
        if path.suffix.lower() in EXCLUDED_SUFFIXES or path.name in EXCLUDED_NAMES:
            continue
        files.append(path)
    return files


def build_zip(version: str) -> pathlib.Path:
    DIST.mkdir(exist_ok=True)
    target = DIST / f"Muon-v{version}.zip"
    if target.exists():
        target.unlink()

    files = collect_files()
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            relative = path.relative_to(ROOT).as_posix()
            info = zipfile.ZipInfo(relative, date_time=FIXED_TIMESTAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, path.read_bytes())

    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    size_kb = target.stat().st_size / 1024.0
    print(f"\n{target}  {size_kb:.1f} KiB  {len(files)} files")
    print(f"sha256 {digest}")
    return target


def archive_release(version: str, package: pathlib.Path) -> None:
    destination = ARCHIVE_ROOT / f"v{version}"
    destination.mkdir(parents=True, exist_ok=True)

    shutil.copy2(package, destination / package.name)

    manifest = {
        "version": version,
        "zip": package.name,
        "sha256": hashlib.sha256(package.read_bytes()).hexdigest(),
        "files": len(collect_files()),
        "license": "Muon Proprietary Licence (LICENSE.txt)",
        "copyright": 'Copyright (c) 2026 Keyon Fatemi ("Ligmite")',
        "note": "Frozen release. Never modify the contents of this directory.",
    }
    (destination / "MANIFEST.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )

    readme = destination / "README.md"
    if not readme.exists():
        readme.write_text(
            f"# Muon v{version} (frozen)\n\n"
            f"This directory contains the released archive for **v{version}** and\n"
            f"its manifest. The `.zip` is what users download; `MANIFEST.json`\n"
            f"records its SHA-256 so a copy can be verified.\n\n"
            f"Archives are append-only. Do not rebuild or edit them.\n",
            encoding="utf-8",
        )

    print(f"archived into {destination}/")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", action="store_true", help="also freeze into archive/<version>/")
    parser.add_argument("--skip-checks", action="store_true", help="skip static validation")
    args = parser.parse_args()

    version = read_version()

    if not args.skip_checks:
        if run([sys.executable, "tools/validate.py"]) != 0:
            print("\nvalidation failed; refusing to package", file=sys.stderr)
            return 1
        if run([sys.executable, "tools/gen_wrappers.py", "--check"]) != 0:
            print("\nwrapper files are out of date; run tools/gen_wrappers.py", file=sys.stderr)
            return 1

    package = build_zip(version)
    if args.archive:
        archive_release(version, package)

    return 0


if __name__ == "__main__":
    sys.exit(main())
