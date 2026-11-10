#!/usr/bin/env python3
"""
Muon Shaders - packaging script.

Builds:
    release/Muon-v<version>.zip      ready to drop into .minecraft/shaderpacks
    iterations/v<version>/           archived snapshot of this iteration
    iterations/v<version>/manifest.json

The zip contains the `shaders/` folder at its root plus the licence and readme,
which is what Iris and OptiFine expect.

Run from the repository root:  python tools/build.py
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import sys
import zipfile
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUTPUT = os.path.dirname(ROOT)  # release/ and iterations/ live next to the repo folder


def read_version() -> tuple[str, str]:
    path = os.path.join(ROOT, "shaders", "settings.glsl")
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()

    def grab(name: str) -> str:
        m = re.search(rf"#define\s+{name}\s+(\d+)", text)
        if not m:
            raise SystemExit(f"error: {name} not found in settings.glsl")
        return m.group(1)

    major = grab("MUON_VERSION_MAJOR")
    minor = grab("MUON_VERSION_MINOR")
    patch = grab("MUON_VERSION_PATCH")

    codename_match = re.search(r'#define\s+MUON_CODENAME\s+"([^"]+)"', text)
    codename = codename_match.group(1) if codename_match else ""

    return f"{major}.{minor}.{patch}", codename


def collect_files() -> list[tuple[str, str]]:
    """Returns (absolute path, archive path) pairs."""
    files: list[tuple[str, str]] = []

    for base, _dirs, names in os.walk(os.path.join(ROOT, "shaders")):
        for name in sorted(names):
            if name.startswith("."):
                continue
            absolute = os.path.join(base, name)
            relative = os.path.relpath(absolute, ROOT).replace(os.sep, "/")
            files.append((absolute, relative))

    for extra in ("LICENSE", "README.md", "CHANGELOG.md"):
        absolute = os.path.join(ROOT, extra)
        if os.path.isfile(absolute):
            files.append((absolute, extra))

    files.sort(key=lambda pair: pair[1])
    return files


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build() -> int:
    version, codename = read_version()
    release_dir = os.path.join(OUTPUT, "release")
    iterations_dir = os.path.join(OUTPUT, "iterations")
    os.makedirs(release_dir, exist_ok=True)

    zip_path = os.path.join(release_dir, f"Muon-v{version}.zip")

    files = collect_files()

    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for absolute, relative in files:
            archive.write(absolute, relative)

    size = os.path.getsize(zip_path)
    digest = sha256_of(zip_path)

    print(f"built {os.path.relpath(zip_path, OUTPUT)} "
          f"({size / 1024.0:.1f} KiB, {len(files)} files)")

    # Archived iteration: source snapshot + the built zip + a manifest
    iteration_dir = os.path.join(iterations_dir, f"v{version}")
    if os.path.isdir(iteration_dir):
        shutil.rmtree(iteration_dir)
    os.makedirs(iteration_dir, exist_ok=True)

    shutil.copytree(os.path.join(ROOT, "shaders"), os.path.join(iteration_dir, "shaders"))
    shutil.copy2(zip_path, os.path.join(iteration_dir, os.path.basename(zip_path)))

    manifest = {
        "name": "Muon",
        "version": version,
        "codename": codename,
        "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "file": os.path.basename(zip_path),
        "size_bytes": size,
        "sha256": digest,
        "file_count": len(files),
        "shader_programs": sum(1 for _a, r in files if r.endswith((".vsh", ".fsh"))),
    }

    with open(os.path.join(iteration_dir, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)
        handle.write("\n")

    print(f"archived iterations/v{version}/")

    # Also write a checksum next to the release for the GitHub release page
    with open(zip_path + ".sha256", "w", encoding="utf-8") as handle:
        handle.write(f"{digest}  {os.path.basename(zip_path)}\n")

    return 0


if __name__ == "__main__":
    sys.exit(build())
