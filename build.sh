#!/usr/bin/env bash
#
# Muon Shaders - build.sh
#
# Packages shaders/ into <workspace>/release/Muon-v<version>.zip, after running
# the static validator and the generator checks. The release and archive
# directories sit beside the repository, not inside it.
#
#   ./build.sh              package only
#   ./build.sh --archive    also freeze into archive/v<version>/
#   ./build.sh --skip-checks
#
# Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
# Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

set -euo pipefail

cd "$(dirname "$0")"

PYTHON="${MUON_PYTHON:-}"
if [ -z "$PYTHON" ]; then
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1; then
            PYTHON="$candidate"
            break
        fi
    done
fi

if [ -z "$PYTHON" ]; then
    echo "error: python 3 is required (set MUON_PYTHON to an interpreter path)" >&2
    exit 1
fi

echo "Muon build - python: $PYTHON"

"$PYTHON" tools/package.py "$@"

echo
echo "Done. Copy release/*.zip into .minecraft/shaderpacks/."
