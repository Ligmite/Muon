/*
================================================================================

  Muon Shaders - lib/common/noise.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Noise primitives for clouds, fog, water and caustics.

  Two classes of noise live here:

    * Analytic noise (value, gradient, Worley). Free of any resource binding and
      therefore usable from any stage, including the vertex shader.
    * Tiled volume noise read from the pack's 3D textures. The Perlin-Worley
      base volume is precomputed offline by tools/gen_noise.py because a
      correct Perlin-Worley evaluation costs 27 Worley cells per octave -
      affordable once on the CPU, never inside a 40-step cloud march.

  All analytic functions are tileable over their period argument, so cloud
  densities do not seam when a sample crosses the repeat boundary.

================================================================================
*/

#ifndef MUON_COMMON_NOISE_GLSL
#define MUON_COMMON_NOISE_GLSL

#include "/lib/common/math.glsl"
#include "/lib/common/random.glsl"

// -----------------------------------------------------------------------------
//  Tiled volume noise
//  Bound with `texture.deferred1.<name>` and friends; see shaders.properties.
//  Dimensions: 64^3 for the weather volume, 32^3 for the detail erosion volume.
// -----------------------------------------------------------------------------

uniform sampler3D muonCloudNoise;
uniform sampler3D muonDetailNoise;

const vec3 MUON_CLOUD_NOISE_SIZE = vec3(64.0);
const vec3 MUON_DETAIL_NOISE_SIZE = vec3(32.0);

/* Samples the Perlin-Worley base volume; p is in tile units and wraps. */
float muon_cloud_base_noise(vec3 p) {
    return texture(muonCloudNoise, p).r;
}

/* Samples the high-frequency Worley volume used to erode cloud edges. */
float muon_cloud_detail_noise(vec3 p) {
    return texture(muonDetailNoise, p).r;
}

/* Trilinearly filtered sample of a 2D texture repacked as a tileable volume. */
vec2 muon_cloud_base_noise_2(vec3 p, vec3 offset) {
    return vec2(
        texture(muonCloudNoise, p).r,
        texture(muonCloudNoise, p + offset).r
    );
}

// -----------------------------------------------------------------------------
//  Value noise
// -----------------------------------------------------------------------------

float muon_value_noise_2d(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);

    float a = muon_rand_2d(i, 0u);
    float b = muon_rand_2d(i + vec2(1.0, 0.0), 0u);
    float c = muon_rand_2d(i + vec2(0.0, 1.0), 0u);
    float d = muon_rand_2d(i + vec2(1.0, 1.0), 0u);

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float muon_value_noise_3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * (3.0 - 2.0 * f);

    float c000 = muon_rand_3d(i, 0u);
    float c100 = muon_rand_3d(i + vec3(1.0, 0.0, 0.0), 0u);
    float c010 = muon_rand_3d(i + vec3(0.0, 1.0, 0.0), 0u);
    float c110 = muon_rand_3d(i + vec3(1.0, 1.0, 0.0), 0u);
    float c001 = muon_rand_3d(i + vec3(0.0, 0.0, 1.0), 0u);
    float c101 = muon_rand_3d(i + vec3(1.0, 0.0, 1.0), 0u);
    float c011 = muon_rand_3d(i + vec3(0.0, 1.0, 1.0), 0u);
    float c111 = muon_rand_3d(i + vec3(1.0, 1.0, 1.0), 0u);

    float x00 = mix(c000, c100, u.x);
    float x10 = mix(c010, c110, u.x);
    float x01 = mix(c001, c101, u.x);
    float x11 = mix(c011, c111, u.x);

    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

// -----------------------------------------------------------------------------
//  Gradient (Perlin) noise
// -----------------------------------------------------------------------------

vec3 muon_gradient_3d(vec3 cell) {
    vec3 r = muon_rand_vec3(
        muon_hash_combine(
            muon_hash_combine(uint(ivec3(cell).x + 1024), uint(ivec3(cell).y + 1024)),
            uint(ivec3(cell).z + 1024)
        )
    );
    return normalize(r * 2.0 - 1.0);
}

float muon_perlin_3d(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    float n000 = dot(muon_gradient_3d(i), f);
    float n100 = dot(muon_gradient_3d(i + vec3(1.0, 0.0, 0.0)), f - vec3(1.0, 0.0, 0.0));
    float n010 = dot(muon_gradient_3d(i + vec3(0.0, 1.0, 0.0)), f - vec3(0.0, 1.0, 0.0));
    float n110 = dot(muon_gradient_3d(i + vec3(1.0, 1.0, 0.0)), f - vec3(1.0, 1.0, 0.0));
    float n001 = dot(muon_gradient_3d(i + vec3(0.0, 0.0, 1.0)), f - vec3(0.0, 0.0, 1.0));
    float n101 = dot(muon_gradient_3d(i + vec3(1.0, 0.0, 1.0)), f - vec3(1.0, 0.0, 1.0));
    float n011 = dot(muon_gradient_3d(i + vec3(0.0, 1.0, 1.0)), f - vec3(0.0, 1.0, 1.0));
    float n111 = dot(muon_gradient_3d(i + vec3(1.0, 1.0, 1.0)), f - vec3(1.0, 1.0, 1.0));

    float x00 = mix(n000, n100, u.x);
    float x10 = mix(n010, n110, u.x);
    float x01 = mix(n001, n101, u.x);
    float x11 = mix(n011, n111, u.x);

    return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

// -----------------------------------------------------------------------------
//  Fractal sums
// -----------------------------------------------------------------------------

float muon_fbm_2d(vec2 p, int octaves, float lacunarity, float gain, float period) {
    float total = 0.0;
    float amplitude = 1.0;
    float normalization = 0.0;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        /* Sampling fBm on integers of the period keeps every octave tileable. */
        vec2 wrapped = p * frequency;
        wrapped = fract(wrapped / period) * period;
        total += muon_value_noise_2d(wrapped) * amplitude;
        normalization += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }
    return total / max(normalization, MUON_EPSILON);
}

float muon_fbm_3d(vec3 p, int octaves, float lacunarity, float gain, float period) {
    float total = 0.0;
    float amplitude = 1.0;
    float normalization = 0.0;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        vec3 wrapped = fract(p * frequency / period) * period;
        total += muon_value_noise_3d(wrapped) * amplitude;
        normalization += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }
    return total / max(normalization, MUON_EPSILON);
}

float muon_perlin_fbm_3d(vec3 p, int octaves, float lacunarity, float gain) {
    float total = 0.0;
    float amplitude = 1.0;
    float normalization = 0.0;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        total += muon_perlin_3d(p * frequency) * amplitude;
        normalization += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }
    return total / max(normalization, MUON_EPSILON) * 0.5 + 0.5;
}

// -----------------------------------------------------------------------------
//  Worley / cellular noise
// -----------------------------------------------------------------------------

/* Returns (F1, F2) distances of the nearest two feature points. */
vec2 muon_worley_3d(vec3 p) {
    vec3 cell = floor(p);
    vec3 local = fract(p);
    float f1 = 1.0e9;
    float f2 = 1.0e9;

    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec3 offset = vec3(float(x), float(y), float(z));
                vec3 neighbour = cell + offset;
                vec3 point = offset + muon_rand_vec3(
                    muon_hash_combine(
                        muon_hash_combine(uint(ivec3(neighbour).x + 1024), uint(ivec3(neighbour).y + 1024)),
                        uint(ivec3(neighbour).z + 1024)
                    )
                );
                vec3 delta = point - local;
                float d = dot(delta, delta);
                if (d < f1) {
                    f2 = f1;
                    f1 = d;
                } else if (d < f2) {
                    f2 = d;
                }
            }
        }
    }

    return sqrt(vec2(max(f1, 0.0), max(f2, 0.0)));
}

float muon_worley_fbm_3d(vec3 p, int octaves, float lacunarity, float gain) {
    float total = 0.0;
    float amplitude = 1.0;
    float normalization = 0.0;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        total += muon_worley_3d(p * frequency).x * amplitude;
        normalization += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }
    return total / max(normalization, MUON_EPSILON);
}

/* Cellular noise in 2D, used for rain ripples and puddle break-up. */
vec2 muon_worley_2d(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    float f1 = 1.0e9;
    float f2 = 1.0e9;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 neighbour = cell + offset;
            vec2 point = offset + muon_rand_vec2(
                muon_hash_combine(uint(ivec2(neighbour).x + 1024), uint(ivec2(neighbour).y + 1024))
            );
            vec2 delta = point - local;
            float d = dot(delta, delta);
            if (d < f1) {
                f2 = f1;
                f1 = d;
            } else if (d < f2) {
                f2 = d;
            }
        }
    }
    return sqrt(vec2(max(f1, 0.0), max(f2, 0.0)));
}

// -----------------------------------------------------------------------------
//  Domain warping
// -----------------------------------------------------------------------------

vec3 muon_domain_warp(vec3 p, float amount, float period) {
    vec3 warp = vec3(
        muon_cloud_base_noise(p * (1.0 / period) + vec3(0.13, 0.71, 0.37)),
        muon_cloud_base_noise(p * (1.0 / period) + vec3(0.51, 0.19, 0.83)),
        muon_cloud_base_noise(p * (1.0 / period) + vec3(0.79, 0.43, 0.11))
    );
    return p + (warp * 2.0 - 1.0) * amount;
}

// -----------------------------------------------------------------------------
//  Water caustics
//  Two counter-rotating cellular layers, remapped so that their cell
//  boundaries become thin bright filaments - the classic pool-floor look.
// -----------------------------------------------------------------------------

float muon_caustics(vec2 uv, float time) {
    vec2 p = uv * 2.4;
    vec2 drift_a = p + vec2(time * 0.21, time * 0.17);
    vec2 drift_b = muon_rotation_2d(1.2) * p - vec2(time * 0.19, time * 0.23);

    vec2 a = muon_worley_2d(drift_a);
    vec2 b = muon_worley_2d(drift_b);

    float ridge_a = 1.0 - smoothstep(0.0, 0.55, a.y - a.x);
    float ridge_b = 1.0 - smoothstep(0.0, 0.55, b.y - b.x);

    float caustic = pow(max(ridge_a * ridge_b, 0.0), 1.6);
    return caustic;
}

#endif // MUON_COMMON_NOISE_GLSL
