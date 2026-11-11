/*
================================================================================

  Muon Shaders - lib/common/water.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Water optics.

  The surface is described by a Gerstner wave sum: the vertex stage displaces
  the surface (real, not faked), and the fragment stage evaluates the analytic
  normal of the same sum at a higher frequency so that the shading reads as
  flowing water rather than a bumpy quad.

  Below the surface the model is Beer-Lambert extinction with a Snell's-law
  refraction offset and animated caustics projected onto the bottom. The three
  parts share the absorption coefficients, so a change to
  `WATER_ABSORPTION_*` moves the tint, the extinction and the caustic falloff
  together.

================================================================================
*/

#ifndef MUON_COMMON_WATER_GLSL
#define MUON_COMMON_WATER_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/noise.glsl"

const float MUON_WATER_IOR = 1.333;
const float MUON_WATER_F0 = 0.02;
const float MUON_WATER_BASE_AMPLITUDE = 0.055;

// -----------------------------------------------------------------------------
//  Gerstner waves
// -----------------------------------------------------------------------------

struct MuonWave {
    vec2 direction;
    float amplitude;
    float wavelength;
    float speed;
    float steepness;
};

/*
 * Four waves with co-prime-ish wavelengths. The irrational ratios between them
 * keep the sum from visibly repeating over a small area, which matters because
 * the player can see hundreds of blocks of water at once.
 */
MuonWave muon_wave(int index, float scale) {
    MuonWave w;
    if (index == 0) {
        w.direction = normalize(vec2(1.0, 0.35));
        w.amplitude = 1.00;
        w.wavelength = 16.0;
        w.speed = 1.00;
        w.steepness = 0.65;
    } else if (index == 1) {
        w.direction = normalize(vec2(0.42, 1.0));
        w.amplitude = 0.55;
        w.wavelength = 9.4;
        w.speed = 1.24;
        w.steepness = 0.55;
    } else if (index == 2) {
        w.direction = normalize(vec2(-0.70, 0.72));
        w.amplitude = 0.32;
        w.wavelength = 5.3;
        w.speed = 1.61;
        w.steepness = 0.48;
    } else {
        w.direction = normalize(vec2(0.90, -0.44));
        w.amplitude = 0.18;
        w.wavelength = 3.1;
        w.speed = 2.05;
        w.steepness = 0.40;
    }
    w.amplitude *= scale;
    return w;
}

float muon_wave_phase(MuonWave w, vec2 position, float time) {
    float k = MUON_TAU / max(w.wavelength, 1.0e-3);
    return k * dot(w.direction, position) - w.speed * sqrt(9.81 * k) * time * MUON_WATER_WAVE_SPEED;
}

/*
 * Vertical displacement of the surface. Used by the vertex stage, so it must
 * stay free of texture fetches.
 */
vec3 muon_gerstner_displacement(vec2 position, float time) {
    vec3 offset = vec3(0.0);
    if (MUON_WATER_WAVE_STRENGTH <= 0.0) {
        return offset;
    }

    float scale = MUON_WATER_WAVE_STRENGTH * MUON_WATER_BASE_AMPLITUDE;

    for (int i = 0; i < MUON_WATER_WAVE_COUNT; i++) {
        MuonWave w = muon_wave(i, scale);
        float phase = muon_wave_phase(w, position, time);
        float k = MUON_TAU / max(w.wavelength, 1.0e-3);
        float q = w.steepness / max(k * w.amplitude * float(MUON_WATER_WAVE_COUNT), 1.0e-4);

        offset.x += q * w.amplitude * w.direction.x * cos(phase);
        offset.z += q * w.amplitude * w.direction.y * cos(phase);
        offset.y += w.amplitude * sin(phase);
    }

    return offset;
}

/*
 * Analytic surface normal of the same wave sum, evaluated at higher spatial
 * frequency than the vertex displacement. Returns a unit normal in world
 * space (y up).
 *
 * The normal is the cross product of the two parametric derivatives of the
 * Gerstner sum, which is what makes the crests point forward instead of merely
 * bobbing up and down.
 */
vec3 muon_gerstner_normal(vec2 position, float time, float detail_gain) {
    vec3 ddx = vec3(1.0, 0.0, 0.0);
    vec3 ddz = vec3(0.0, 0.0, 1.0);

    float scale = MUON_WATER_WAVE_STRENGTH * MUON_WATER_BASE_AMPLITUDE * detail_gain;

    for (int i = 0; i < MUON_WATER_WAVE_COUNT; i++) {
        MuonWave w = muon_wave(i, scale);
        /* Higher frequency for the normal so that shading carries more detail
           than the coarse geometry can. */
        float k = MUON_TAU / max(w.wavelength, 1.0e-3) * 2.35;
        float phase = k * dot(w.direction, position) - w.speed * sqrt(9.81 * k) * time * MUON_WATER_WAVE_SPEED;
        float q = w.steepness / max(k * w.amplitude * float(MUON_WATER_WAVE_COUNT), 1.0e-4);

        float cos_phase = cos(phase);
        float sin_phase = sin(phase);
        float wa = k * w.amplitude;
        float d2x = w.direction.x * w.direction.x;
        float d2z = w.direction.y * w.direction.y;
        float dxz = w.direction.x * w.direction.y;

        ddx.x -= q * wa * d2x * sin_phase;
        ddx.y += wa * w.direction.x * cos_phase;
        ddx.z -= q * wa * dxz * sin_phase;

        ddz.x -= q * wa * dxz * sin_phase;
        ddz.y += wa * w.direction.y * cos_phase;
        ddz.z -= q * wa * d2z * sin_phase;
    }

    return normalize(cross(ddz, ddx));
}

// -----------------------------------------------------------------------------
//  Rain ripples on the water surface
// -----------------------------------------------------------------------------

vec2 muon_water_ripple(vec2 position, float time, float rain) {
    if (rain <= 0.001) {
        return vec2(0.0);
    }
    vec2 p = position * 0.55;
    vec2 cell = muon_worley_2d(p + vec2(time * 0.2, time * 0.13));
    float ripple = sin((cell.x - cell.y) * 26.0 - time * 9.0);
    return vec2(ripple, ripple * 0.6) * (rain * 0.035);
}

// -----------------------------------------------------------------------------
//  Fresnel and refraction
// -----------------------------------------------------------------------------

float muon_water_fresnel(vec3 normal, vec3 view_dir_to_eye) {
    float cos_theta = muon_saturate(dot(normal, view_dir_to_eye));
    return muon_saturate(MUON_WATER_F0 + (1.0 - MUON_WATER_F0) * muon_pow5(1.0 - cos_theta));
}

/*
 * Screen-space refraction offset derived from Snell's law. The refracted ray
 * is computed exactly from the real view directions, projected back to the
 * screen, and clamped so that the offset can never sample across a depth
 * discontinuity.
 */
vec2 muon_water_refraction_offset(
    vec2 uv,
    vec3 view_pos,
    vec3 view_normal,
    float strength
) {
#if !defined WATER_REFRACTION
    return vec2(0.0);
#else
    vec3 view_dir = normalize(view_pos);
    vec3 refracted = muon_refract(view_dir, view_normal, 1.0 / MUON_WATER_IOR);
    if (dot(refracted, refracted) < 0.5) {
        return vec2(0.0);
    }

    float travel = max(length(view_pos) * 0.35, 0.25);
    vec4 clip = muonFrame.projection * vec4(view_pos + refracted * travel, 1.0);
    if (clip.w <= 0.0) {
        return vec2(0.0);
    }
    vec2 refracted_uv = clip.xy / clip.w * 0.5 + 0.5;
    vec2 offset = (refracted_uv - uv) * strength * MUON_WATER_REFRACTION;

    /* Keep the offset inside a fraction of the screen so that a grazing wave
       cannot rip the image across a whole chunk. */
    vec2 limit = muon_inv_viewport() * 24.0;
    return clamp(offset, -limit, limit);
#endif
}

// -----------------------------------------------------------------------------
//  Extinction, scattering and caustics
// -----------------------------------------------------------------------------

/* Beer-Lambert transmittance through `depth` metres of water. */
vec3 muon_water_transmittance(float depth) {
    return exp(-MUON_WATER_ABSORPTION * max(depth, 0.0));
}

vec3 muon_water_inscatter(float depth) {
    vec3 transmittance = muon_water_transmittance(depth);
    return (vec3(1.0) - transmittance) * (vec3(0.32, 0.62, 0.78) * MUON_WATER_SCATTERING * 6.0);
}

/*
 * Caustics projected onto the bottom. The pattern fades with depth through the
 * same absorption coefficients, and its scale tightens as the light focuses.
 */
float muon_water_caustics(vec2 world_xz, float depth, float view_distance) {
#if !defined WATER_CAUSTICS
    return 0.0;
#else
    float time = muon_time_counter();
    float pattern = muon_caustics(world_xz * 0.12, time * 1.35);

    float depth_fade = exp(-depth * 0.05);
    float distance_fade = 1.0 - muon_saturate(view_distance / 96.0);

    return pattern * depth_fade * distance_fade * MUON_WATER_CAUSTICS;
#endif
}

/*
 * Tint of the water body itself, blending the shallow (scattering-dominated)
 * and deep (absorption-dominated) regimes.
 */
vec3 muon_water_body_color(float depth) {
    vec3 shallow = vec3(0.24, 0.62, 0.62);
    vec3 deep = vec3(0.02, 0.13, 0.22);
    float t = 1.0 - exp(-max(depth, 0.0) * 0.09);
    return mix(shallow, deep, t);
}

// -----------------------------------------------------------------------------
//  Underwater view
// -----------------------------------------------------------------------------

/* Applies the underwater medium when the camera itself is submerged. */
vec3 muon_underwater_tint(vec3 color, float distance) {
    if (muon_eye_in_water() < 0.5) {
        return color;
    }
    vec3 transmittance = muon_water_transmittance(distance * 0.55);
    vec3 inscatter = muon_water_inscatter(distance * 0.55);
    return color * transmittance + inscatter;
}

#endif // MUON_COMMON_WATER_GLSL
