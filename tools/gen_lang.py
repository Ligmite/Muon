#!/usr/bin/env python3
"""
Muon Shaders - language file generator.

Reads settings.glsl and shaders.properties and emits lang/en_US.lang so that
new options never appear as raw identifiers in the settings menu.

Run: python tools/gen_lang.py
"""

from __future__ import annotations

import os
import re
import sys

ACRONYMS = {
    "AO": "AO", "SSAO": "SSAO", "GTAO": "GTAO", "SSR": "SSR", "TAA": "TAA",
    "FXAA": "FXAA", "CAS": "CAS", "DOF": "DOF", "POM": "POM", "HDR": "HDR",
    "RT": "RT", "VL": "VL", "DH": "DH", "SSS": "SSS", "F0": "F0", "LOD": "LOD",
    "PT": "PT", "GI": "GI", "PBR": "PBR", "VPS": "VPS", "IRIS": "Iris",
    "MC": "MC", "UI": "UI", "FOV": "FOV", "FP16": "FP16", "PNG": "PNG",
}

# Curated tooltips for the options players ask about most
COMMENTS = {
    "SHADOW": "Enables the shadow map. Turning this off removes all cast shadows and is much faster.",
    "SHADOW_SOFT": "Percentage-closer soft shadows: penumbrae grow with the distance between the occluder and the receiver.",
    "SHADOW_SAMPLES": "Number of samples in the shadow filter. Higher is smoother but slower.",
    "SHADOW_PENUMBRA_SCALE": "Multiplier for the width of soft shadow penumbrae.",
    "SHADOW_SSRT": "Screen space contact shadows. Catches small details the shadow map is too coarse for.",
    "SHADER_AO": "Ambient occlusion method. GTAO is the horizon based method and is stable in motion.",
    "GTAO_RADIUS": "Radius of ambient occlusion, in blocks.",
    "GTAO_SLICES": "Number of slices around each pixel. More slices means less noise.",
    "SUN_I": "Direct sunlight intensity.",
    "MOON_I": "Moonlight intensity. Lower values give darker, more contrasty nights.",
    "SKYLIGHT_I": "Ambient sky light intensity.",
    "BLOCKLIGHT_I": "Torch and lantern light intensity.",
    "MINIMUM_LIGHT": "Artificial floor under the lighting, so caves are never completely black.",
    "VOLUMETRIC_LIGHTING": "Raymarched fog and light shafts. Requires the shadow map.",
    "VL_STEPS": "Number of raymarching steps for volumetric lighting.",
    "VL_MIE_G": "Forward scattering of the fog. Higher values give tighter, brighter light shafts.",
    "CLOUDS": "Master switch for the volumetric cloud layers.",
    "CLOUDS_CUMULUS": "Low, dense cumulus clouds. The main layer and the most expensive.",
    "CLOUDS_CUMULUS_STEPS": "Raymarching steps for the cumulus layer.",
    "CLOUDS_CUMULUS_CONGESTUS": "Tall cumulus congestus towers with anvil tops.",
    "CLOUDS_ALTOCUMULUS": "Mid level cellular cloud layer.",
    "CLOUDS_CIRRUS": "High, thin, streaky cirrus.",
    "RAY_TRACING": "Ray traced lighting. Mode 3 is a full screen space path tracer and replaces the analytic lighting.",
    "RT_MAX_BOUNCES": "Maximum number of path segments. More bounces means more global illumination and less performance.",
    "RT_TEMPORAL_ACCUMULATION": "Accumulate path samples over time. Strongly recommended, otherwise the image is very noisy.",
    "RT_DENOISE": "Edge aware spatial filter on the ray traced result.",
    "RT_GI_STRENGTH": "How much ray traced indirect light contributes.",
    "REFLECTIONS": "Reflection method. 2 uses screen space reflections with a sky fallback.",
    "SSR_STEPS": "Screen space reflection raymarching steps.",
    "POM": "Parallax occlusion mapping. Gives flat textures visible depth.",
    "POM_DEPTH": "Depth scale of the parallax effect.",
    "RESOURCEPACK_SUPPORT": "labPBR decodes roughness, F0 and emission from the resource pack specular maps.",
    "WATER_WAVES": "Procedural wave normals for water surfaces.",
    "WATER_ABSORPTION_R": "Absorption of red light in water. Higher values make deep water more red.",
    "WATER_CAUSTICS": "Animated caustic patterns on the floor under water.",
    "TAA": "Temporal anti-aliasing. Also resolves stochastic effects such as SSR and the path tracer.",
    "BLOOM": "HDR bloom.",
    "BLOOM_INTENSITY": "Strength of the bloom.",
    "DOF": "Depth of field. Focus follows the centre of the screen.",
    "TONEMAP": "Tone mapping curve. Filmic keeps the most colour in the highlights.",
    "GRADE_SATURATION": "Overall saturation of the final image.",
    "GRADE_TEMPERATURE": "White balance. Positive is warmer.",
    "AUTO_EXPOSURE": "Eye adaptation. Disable to use a fixed exposure.",
    "HDR_USE_FP16": "Use 16 bit float scene buffers when HDR output is active.",
    "DEBUG_VIEW": "Render an internal buffer instead of the final image.",
}

ENUMS = {
    "SHADER_AO": {0: "Off", 1: "SSAO", 2: "GTAO"},
    "REFLECTIONS": {0: "Off", 1: "Sky only", 2: "Screen space"},
    "RESOURCEPACK_SUPPORT": {0: "Off", 1: "Legacy specular", 2: "labPBR"},
    "TONEMAP": {0: "Muon Filmic", 1: "ACES", 2: "Khronos Neutral", 3: "Uncharted 2",
                4: "Reinhard", 5: "ACES punchy"},
    "RAY_TRACING": {0: "Off", 1: "RT reflections", 2: "RT reflections + GI", 3: "Full path tracing"},
    "DEBUG_VIEW": {0: "Off", 1: "Albedo", 2: "Normal", 3: "AO", 4: "Shadows", 5: "Volumetrics",
                   6: "Clouds", 7: "Ray tracing", 8: "Roughness", 9: "Light levels"},
}

SCREENS = {
    "world": "World", "lighting": "Lighting", "sky": "Sky", "clouds": "Clouds",
    "atmosphere": "Atmosphere", "water": "Water", "materials": "Materials",
    "reflections": "Reflections", "raytracing": "Ray Tracing", "post": "Post Processing",
    "color": "Colour Grading", "misc": "Miscellaneous", "weather": "Weather",
    "shadows": "Shadows", "ao": "Ambient Occlusion", "light_sources": "Light Sources",
    "stars": "Stars", "galaxy": "Galaxy", "clouds_cumulus": "Cumulus",
    "clouds_congestus": "Cumulus Congestus", "clouds_altocumulus": "Altocumulus",
    "clouds_cirrus": "Cirrus", "water_waves": "Waves", "pom": "Parallax Mapping",
    "exposure": "Exposure", "bloom": "Bloom", "lens": "Lens", "aa": "Anti-Aliasing",
    "mods": "Mod Integration",
}


def humanise(name: str) -> str:
    parts = name.split("_")
    out = []
    for part in parts:
        if part in ACRONYMS:
            out.append(ACRONYMS[part])
        else:
            out.append(part.capitalize())
    return " ".join(out)


def main() -> int:
    root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shaders")

    settings_path = os.path.join(root, "settings.glsl")
    with open(settings_path, "r", encoding="utf-8") as handle:
        text = handle.read()

    bools = []
    numbers = {}
    for line in text.splitlines():
        m = re.match(r"\s*#define\s+([A-Z_][A-Z0-9_]*)\s*(.*)$", line)
        if not m:
            continue
        name, rest = m.group(1), m.group(2).strip()
        if rest.startswith("("):
            continue
        if rest == "":
            bools.append(name)
        else:
            numbers[name] = rest

    lines = ["# Muon Shaders - en_US language file",
             "# Generated by tools/gen_lang.py",
             ""]

    # Profiles
    lines += [
        "profile.low=Low",
        "profile.medium=Medium",
        "profile.high=High",
        "profile.ultra=Ultra",
        "profile.pathtraced=Path Traced",
        "",
    ]

    # Screens
    for key, label in SCREENS.items():
        lines.append(f"screen.{key}={label}")
    lines.append("")

    # Options
    for name in sorted(set(bools) | set(numbers)):
        lines.append(f"option.{name}={humanise(name)}")
        if name in COMMENTS:
            lines.append(f"option.{name}.comment={COMMENTS[name]}")
        if name in ENUMS:
            for value, label in ENUMS[name].items():
                lines.append(f"value.{name}.{value}={label}")

    lines.append("")

    out = os.path.join(root, "lang", "en_US.lang")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))

    print(f"wrote {out} ({len(bools)} toggles, {len(numbers)} values)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
