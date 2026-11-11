/*
================================================================================

  Muon Shaders - lib/common/wetness.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Weather-driven surface state.

  Two independent effects share this file because they are driven by the same
  weather inputs and are applied at the same point in the geometry stage:

    rain     darkens and polishes exposed surfaces, fills puddles in low-lying
             noise minima, and adds animated ripple normals to the water film.
    snow     accumulates on upward faces during snowfall, with a coverage that
             follows the world's precipitation type.

  Iris updates the wetness value itself (with the halflife declared in
  settings.glsl), so the pack only has to read it; drying out after a storm
  happens without any extra state.

================================================================================
*/

#ifndef MUON_COMMON_WETNESS_GLSL
#define MUON_COMMON_WETNESS_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/uniforms/samplers.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/material.glsl"

// -----------------------------------------------------------------------------
//  Puddles
// -----------------------------------------------------------------------------

/*
 * Puddle mask. Large, low-frequency noise cells become puddles; the mask is
 * biased upwards on flat surfaces so that a wall never turns into a puddle.
 */
float muon_puddle_mask(vec2 world_xz, float up_facing) {
#if !defined RAIN_PUDDLES
    return 0.0;
#else
    if (up_facing < 0.65) {
        return 0.0;
    }
    float area = muon_fbm_2d(world_xz * 0.055, 3, 2.1, 0.55, 64.0);
    float mask = muon_smoothstep(0.44, 0.62, area);
    return mask * muon_saturate((up_facing - 0.65) / 0.35) * PUDDLE_STRENGTH;
#endif
}

/*
 * Ripple normal perturbation. Two counter-moving cellular layers produce
 * short-lived interference rings in the water film.
 */
vec2 muon_rain_ripple_normal(vec2 world_xz, float time, float intensity) {
    if (intensity <= 0.001) {
        return vec2(0.0);
    }
    vec2 p = world_xz * 3.1;
    vec2 a = muon_worley_2d(p + vec2(time * 0.31, time * 0.19));
    vec2 b = muon_worley_2d(p * 1.7 - vec2(time * 0.23, time * 0.29));

    float ring_a = sin((a.x - a.y) * 22.0 - time * 7.0);
    float ring_b = sin((b.x - b.y) * 19.0 - time * 5.3);

    return vec2(ring_a, ring_b) * (0.055 * intensity);
}

// -----------------------------------------------------------------------------
//  Snow
// -----------------------------------------------------------------------------

float muon_snow_amount() {
#if !defined SNOW_COVER
    return 0.0;
#else
    /* Precipitation type 2 is snow in the vanilla biome data Iris exposes. */
    bool snowing = muonFrame.climate.w > 1.5 && muonFrame.climate.w < 2.5;
    if (!snowing) {
        return 0.0;
    }
    float cold = 1.0 - muon_saturate(muonFrame.climate.x * 2.0);
    return muon_saturate(muon_rain_strength() * 1.2) * cold * SNOW_STRENGTH;
#endif
}

// -----------------------------------------------------------------------------
//  Application
// -----------------------------------------------------------------------------

/*
 * Applies the weather state to a material. Must be called after the normal map
 * has been resolved because the ripple modifies the final normal.
 */
MuonMaterial muon_apply_wetting(
    MuonMaterial m,
    vec3 world_pos,
    float up_facing,
    float height
) {
    float wetness = muon_wetness();
    float rain = muon_rain_strength();

    if (wetness > 0.001) {
        float exposure = muon_saturate(m.skylight);
        float puddles = muon_puddle_mask(world_pos.xz, up_facing) * wetness;

        m = muon_apply_wetness(m, wetness, puddles);

        if (rain > 0.001 && up_facing > 0.35) {
            vec3 world_normal = normalize(muon_view_to_world_dir(m.normal));
            vec2 ripple = muon_rain_ripple_normal(world_pos.xz, muon_time_counter(), rain * puddles);
            vec3 perturbed = normalize(world_normal + vec3(ripple.x, 0.0, ripple.y));
            m.normal = normalize(muon_world_to_view_dir(perturbed));
        }
    }

    float snow = muon_snow_amount() * (1.0 - muon_saturate(wetness * 0.5));
    if (snow > 0.001) {
        float cover = muon_saturate(snow * muon_saturate((up_facing - 0.55) / 0.45));
        m = muon_apply_snow(m, cover, up_facing);
    }

    return m;
}

#endif // MUON_COMMON_WETNESS_GLSL
