#!/usr/bin/env python3
"""
Muon Shaders - program wrapper generator.

Iris expects a .vsh/.fsh pair per program. Most of them only differ by a
`#define PROGRAM_*`, so they are generated from this manifest instead of being
maintained by hand.

Run from the repository root:  python tools/gen_programs.py
"""

from __future__ import annotations

import os
import sys

VERSION = "#version 400 compatibility"

# (name, define, shared_stage)
OPAQUE = [
    ("gbuffers_basic", "PROGRAM_BASIC", "gbuffer"),
    ("gbuffers_line", "PROGRAM_BASIC", "gbuffer"),
    ("gbuffers_textured", "PROGRAM_TEXTURED", "gbuffer"),
    ("gbuffers_textured_lit", "PROGRAM_TEXTURED", "gbuffer"),
    ("gbuffers_terrain", "PROGRAM_TERRAIN", "gbuffer"),
    ("gbuffers_entities", "PROGRAM_ENTITIES", "gbuffer"),
    ("gbuffers_block", "PROGRAM_BLOCK", "gbuffer"),
    ("gbuffers_damagedblock", "PROGRAM_DAMAGEDBLOCK", "gbuffer"),
    ("gbuffers_beaconbeam", "PROGRAM_BEACONBEAM", "gbuffer"),
    ("gbuffers_spidereyes", "PROGRAM_SPIDEREYES", "gbuffer"),
    ("gbuffers_armor_glint", "PROGRAM_ARMOR_GLINT", "gbuffer"),
    ("gbuffers_hand", "PROGRAM_HAND", "gbuffer"),
    ("gbuffers_particles", "PROGRAM_PARTICLES", "gbuffer"),
    ("gbuffers_lightning", "PROGRAM_BASIC", "gbuffer"),
    ("gbuffers_clouds", "PROGRAM_BASIC", "gbuffer"),
]

TRANSLUCENT = [
    ("gbuffers_water", "PROGRAM_WATER", "translucent"),
    ("gbuffers_hand_water", "PROGRAM_WATER", "translucent"),
    ("gbuffers_entities_translucent", "PROGRAM_ENTITIES", "translucent"),
    ("gbuffers_block_translucent", "PROGRAM_TERRAIN", "translucent"),
    ("gbuffers_particles_translucent", "PROGRAM_PARTICLES", "translucent"),
    ("gbuffers_weather", "PROGRAM_WEATHER", "translucent"),
]

SKY = [
    ("gbuffers_skybasic", "PROGRAM_SKYBASIC", "sky"),
    ("gbuffers_skytextured", "PROGRAM_SKYTEXTURED", "sky"),
]

SHADOW = [
    ("shadow", None, "shadow"),
    ("shadow_solid", None, "shadow"),
    ("shadow_cutout", None, "shadow"),
    ("shadow_water", None, "shadow"),
    ("shadow_block", None, "shadow"),
    ("shadow_entities", None, "shadow"),
]

STAGE_FILE = {
    "gbuffer": ("/program/gbuffer_vsh.glsl", "/program/gbuffer_fsh.glsl"),
    "translucent": ("/program/translucent_vsh.glsl", "/program/translucent_fsh.glsl"),
    "sky": ("/program/sky_vsh.glsl", "/program/sky_fsh.glsl"),
    "shadow": ("/program/shadow_vsh.glsl", "/program/shadow_fsh.glsl"),
}


def write_program(root: str, name: str, define: str | None, stage: str) -> None:
    vsh, fsh = STAGE_FILE[stage]

    def content(which: str) -> str:
        lines = [VERSION]
        if define:
            lines.append(f"#define {define}")
        lines.append(f"#define {which}")
        lines.append(f'#include "{vsh if which == "vsh" else fsh}"')
        lines.append("")
        return "\n".join(lines)

    with open(os.path.join(root, f"{name}.vsh"), "w", encoding="utf-8") as handle:
        handle.write(content("vsh"))
    with open(os.path.join(root, f"{name}.fsh"), "w", encoding="utf-8") as handle:
        handle.write(content("fsh"))


def main() -> int:
    root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shaders")
    if not os.path.isdir(root):
        print(f"error: {root} not found", file=sys.stderr)
        return 1

    count = 0
    for group in (OPAQUE, TRANSLUCENT, SKY, SHADOW):
        for name, define, stage in group:
            write_program(root, name, define, stage)
            count += 1

    print(f"generated {count} program pairs in {root}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
