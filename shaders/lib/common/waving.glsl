/*
================================================================================

  Muon Shaders - lib/common/waving.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Vertex animation.

  Kept out of the geometry stages so that terrain, entities and the Distant
  Horizons path all share one definition of how foliage moves. Everything here
  is a pure function of the vertex position and time, which is what keeps the
  shadow pass in sync with the camera pass: the same displacement is evaluated
  in both, so foliage never casts a shadow that does not match its position.

  Stiffness is derived from how far the vertex is from the block centre, so the
  base of a plant stays planted while the tip swings.

================================================================================
*/

#ifndef MUON_COMMON_WAVING_GLSL
#define MUON_COMMON_WAVING_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/water.glsl"

// -----------------------------------------------------------------------------
//  Foliage
// -----------------------------------------------------------------------------

/*
 * Swell used by all wind terms. Two incommensurate frequencies keep the motion
 * from looking like a single sine wave, and the world position seeds the phase
 * so that a whole forest is not moving in lockstep.
 */
float muon_wind_swell(vec2 world_xz, float time) {
    float t = time * 1.35;
    float a = sin(dot(world_xz, vec2(0.071, 0.093)) + t);
    float b = sin(dot(world_xz, vec2(-0.047, 0.061)) + t * 1.37);
    float c = sin(dot(world_xz, vec2(0.013, -0.021)) + t * 0.61);
    return (a * 0.5 + b * 0.3 + c * 0.2);
}

/*
 * Displaces a foliage vertex.
 *
 *   world_pos    vertex position in world space
 *   block_offset vertex offset from the block centre, in [-0.5, 0.5]
 *   top_weight   0 at the anchored base, 1 at the free tip
 *   strength     per-material multiplier
 */
vec3 muon_wave_foliage(vec3 world_pos, vec3 block_offset, float top_weight, float strength) {
#if !defined WAVING_PLANTS && !defined WAVING_LEAVES
    return world_pos;
#else
    float time = muon_time_counter();
    float swell = muon_wind_swell(world_pos.xz, time);
    float rain = 1.0 + muon_rain_strength() * 1.8;
    float storm = 1.0 + muon_thunder_strength() * 2.6;

    float anchored = muon_saturate(top_weight);
    float amount = SWAY_STRENGTH * strength * rain * storm * anchored * 0.14;

    /* Horizontal swing plus a small vertical bob, which reads as a plant being
       pushed rather than sliding. */
    vec3 displacement = vec3(
        swell * amount,
        abs(swell) * amount * 0.22,
        muon_wind_swell(world_pos.zx, time * 1.17) * amount
    );

    return world_pos + displacement;
#endif
}

/* Convenience wrapper for block models where only the vertical offset exists. */
float muon_foliage_top_weight(vec3 block_offset, float scale_height) {
    return muon_saturate((block_offset.y + 0.5) / max(scale_height, 0.001));
}

/*
 * How strongly a material reacts to wind. Leaves move more than grass because
 * they are supported by a branch rather than by the ground, and the numbers are
 * chosen so a forest reads as a mass of independent motion instead of a wave.
 */
float muon_sway_gain(int material) {
    if (material == MUON_MAT_LEAVES) {
        return 0.75;
    }
    if (material == MUON_MAT_FOLIAGE) {
        return 0.55;
    }
    if (material == MUON_MAT_PLANT) {
        return 0.95;
    }
    return 0.0;
}

// -----------------------------------------------------------------------------
//  Water
// -----------------------------------------------------------------------------

/*
 * Water displacement. Minecraft's water surface is made of one quad per block,
 * so a per-vertex Gerstner sum alone would produce faceted waves; the fragment
 * stage re-evaluates the analytic normal at a higher frequency to carry the
 * detail that the geometry cannot. This function provides the geometric half.
 */
vec3 muon_wave_water(vec3 world_pos, float top_weight) {
#if !defined WATER_WAVES || !defined WATER_EXTRUDE
    return world_pos;
#else
    /* Only surface vertices move; the sides of a water column stay put so that
       the surface does not tear away from the block edge. */
    float weight = muon_saturate(top_weight);
    vec3 displacement = muon_gerstner_displacement(world_pos.xz, muon_time_counter());
    return world_pos + displacement * (weight * 0.85);
#endif
}

// -----------------------------------------------------------------------------
//  Shadows
// -----------------------------------------------------------------------------

/*
 * The shadow pass needs the same displacement but without the camera-relative
 * bookkeeping. Both call into the same functions above; this wrapper only
 * exists to make the shadow stage's intent explicit at the call site.
 */
vec3 muon_wave_shadow_foliage(vec3 world_pos, vec3 block_offset, float top_weight, float strength) {
    return muon_wave_foliage(world_pos, block_offset, top_weight, strength);
}

#endif // MUON_COMMON_WAVING_GLSL
