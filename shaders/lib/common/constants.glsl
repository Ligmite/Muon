/*
================================================================================

  Muon Shaders - lib/common/constants.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Behavioural constants, material identifiers and render-target indices.

  Nothing here depends on a graphics API. Every value is either a physical
  constant, a fixed pipeline contract, or a tuning constant that is shared by
  more than one library.

================================================================================
*/

#ifndef MUON_COMMON_CONSTANTS_GLSL
#define MUON_COMMON_CONSTANTS_GLSL

// -----------------------------------------------------------------------------
//  Render target contract
//  Every program and every C-side description (docs/buffers.md, the Vulkan
//  descriptor layout plan) refers to these indices, never to bare numbers.
// -----------------------------------------------------------------------------

#define MUON_TARGET_SCENE        0  // HDR colour chain
#define MUON_TARGET_ALBEDO       1  // opaque: albedo.rgb, F0.a
#define MUON_TARGET_NORMAL       2  // opaque: view normal.xyz, smoothness.a
#define MUON_TARGET_SURFACE      3  // opaque: depth.r, material.g, emission.b, porosity.a
#define MUON_TARGET_LIGHTMAP     4  // opaque: block.r, sky.g, ao.b, flags.a
#define MUON_TARGET_HISTORY      5  // TAA history
#define MUON_TARGET_BLOOM        6  // bloom mip chain
#define MUON_TARGET_VOLUME       7  // inscatter.rgb, transmittance.a
#define MUON_TARGET_VELOCITY     8  // velocity.rg, depth.b, flags.a
#define MUON_TARGET_T_ALBEDO     9  // translucent albedo.rgb, F0.a
#define MUON_TARGET_T_NORMAL    10  // translucent normal.xyz, smoothness.a
#define MUON_TARGET_T_SURFACE   11  // translucent material.r, opacity.g, emission.b, porosity.a
#define MUON_TARGET_EXPOSURE    12  // exposure.r, average luminance.g
#define MUON_TARGET_INDIRECT    13  // reflections / GI.rgb, hit mask.a
#define MUON_TARGET_AO          14  // occlusion.r, bent normal.gba
#define MUON_TARGET_AUX         15  // reserved: atmosphere LUT / debug

// -----------------------------------------------------------------------------
//  Material identifiers
//  Stored in the green channel of the surface target. Values above 127 are
//  reserved for block.properties-driven "custom" materials so that resource
//  packs and mods can extend the set without renumbering.
// -----------------------------------------------------------------------------

#define MUON_MAT_NONE       0
#define MUON_MAT_STONE      1
#define MUON_MAT_DIRT       2
#define MUON_MAT_GRASS      3
#define MUON_MAT_SAND       4
#define MUON_MAT_WOOD       5
#define MUON_MAT_LEAVES     6
#define MUON_MAT_METAL      7
#define MUON_MAT_WATER      8
#define MUON_MAT_GLASS      9
#define MUON_MAT_LAVA      10
#define MUON_MAT_SNOW      11
#define MUON_MAT_ICE       12
#define MUON_MAT_EMISSIVE  13
#define MUON_MAT_PLANT     14
#define MUON_MAT_FOLIAGE   15
#define MUON_MAT_CORAL     16
#define MUON_MAT_CONCRETE  17
#define MUON_MAT_NETHER    18
#define MUON_MAT_END       19
#define MUON_MAT_ENTITY    20
#define MUON_MAT_HAND      21

// Custom material base offset: block.properties ids >= 10000 map to
// (id - 10000) + MUON_MAT_CUSTOM_BASE.
#define MUON_MAT_CUSTOM_BASE 128

// -----------------------------------------------------------------------------
//  Surface flags (lightmap target alpha)
// -----------------------------------------------------------------------------

#define MUON_FLAG_NONE          0.0
#define MUON_FLAG_TRANSLUCENT   1.0
#define MUON_FLAG_FOLIAGE       2.0
#define MUON_FLAG_EMISSIVE      3.0
#define MUON_FLAG_WATER         4.0
#define MUON_FLAG_HAND          5.0

// -----------------------------------------------------------------------------
//  Physical / rendering constants
// -----------------------------------------------------------------------------

const float MUON_SUN_ANGULAR_RADIUS_DEG = 0.545;
const float MUON_MOON_ANGULAR_RADIUS_DEG = 0.60;
const float MUON_EARTH_RADIUS_KM = 6360.0;
const float MUON_ATMOSPHERE_HEIGHT_KM = 100.0;
const float MUON_RAYLEIGH_SCALE_HEIGHT_KM = 8.0;
const float MUON_MIE_SCALE_HEIGHT_KM = 1.2;
const float MUON_ATMOSPHERE_KM_PER_BLOCK = 0.001;

const vec3 MUON_RAYLEIGH_BETA = vec3(5.802e-3, 13.558e-3, 33.1e-3);
const float MUON_MIE_BETA = 3.996e-3;
const float MUON_MIE_EXTINCTION = 4.440e-3;
const float MUON_OZONE_BETA = 0.650e-3;

const float MUON_SUN_INTENSITY = 20.0;
const float MUON_MOON_INTENSITY = 1.2;
const float MUON_SKY_INTENSITY = 1.0;
const float MUON_BLOCKLIGHT_INTENSITY = 2.4;

const vec3 MUON_SUN_TINT = vec3(1.0, 0.96, 0.90);
const vec3 MUON_MOON_TINT = vec3(0.72, 0.80, 1.0);
const vec3 MUON_BLOCKLIGHT_TINT = vec3(1.0, 0.68, 0.38);

// -----------------------------------------------------------------------------
//  Limits
// -----------------------------------------------------------------------------

const int MUON_MAX_MATERIALS = 256;
const float MUON_INFINITE = 1.0e20;

#endif // MUON_COMMON_CONSTANTS_GLSL
