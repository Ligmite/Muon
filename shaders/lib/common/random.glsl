/*
================================================================================

  Muon Shaders - lib/common/random.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Deterministic, platform-stable random numbers.

  Every generator here is integer-based and therefore bit-identical on every
  GPU and on a CPU implementation, which matters because the temporal
  integrator and the path tracer rely on the same sample sequence being
  reproduced on a native backend.

================================================================================
*/

#ifndef MUON_COMMON_RANDOM_GLSL
#define MUON_COMMON_RANDOM_GLSL

#include "/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/uniforms/iris.glsl"
#include "/lib/uniforms/frame.glsl"

// -----------------------------------------------------------------------------
//  Integer hashes
// -----------------------------------------------------------------------------

uint muon_hash_u32(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352du;
    x ^= x >> 15;
    x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

uint muon_hash_combine(uint seed, uint value) {
    return muon_hash_u32(seed ^ (value * 0x9e3779b9u));
}

uint muon_pcg_next(inout uint state) {
    state = state * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

float muon_uint_to_float(uint x) {
    return float(x >> 8u) * (1.0 / 16777216.0);
}

// -----------------------------------------------------------------------------
//  Seeded sample streams
// -----------------------------------------------------------------------------

/* One random float per (pixel, frame, stream) triple. */
float muon_rand(uint seed) {
    return muon_uint_to_float(muon_hash_u32(seed));
}

float muon_rand_2d(vec2 coordinate, uint seed) {
    uvec2 icoord = uvec2(ivec2(coordinate + 4096.0));
    uint h = muon_hash_combine(seed, icoord.x);
    h = muon_hash_combine(h, icoord.y);
    return muon_uint_to_float(muon_hash_u32(h));
}

float muon_rand_3d(vec3 coordinate, uint seed) {
    uvec3 icoord = uvec3(ivec3(coordinate + 4096.0));
    uint h = muon_hash_combine(seed, icoord.x);
    h = muon_hash_combine(h, icoord.y);
    h = muon_hash_combine(h, icoord.z);
    return muon_uint_to_float(muon_hash_u32(h));
}

vec2 muon_rand_vec2(uint seed) {
    uint state = muon_hash_u32(seed);
    float a = muon_uint_to_float(muon_pcg_next(state));
    float b = muon_uint_to_float(muon_pcg_next(state));
    return vec2(a, b);
}

vec3 muon_rand_vec3(uint seed) {
    uint state = muon_hash_u32(seed);
    float a = muon_uint_to_float(muon_pcg_next(state));
    float b = muon_uint_to_float(muon_pcg_next(state));
    float c = muon_uint_to_float(muon_pcg_next(state));
    return vec3(a, b, c);
}

/* A per-pixel seed that changes every frame. */
uint muon_pixel_seed(vec2 frag_coord, uint frame) {
    uint h = muon_hash_combine(frame + 1u, uint(ivec2(frag_coord).x));
    h = muon_hash_combine(h, uint(ivec2(frag_coord).y));
    return h;
}

// -----------------------------------------------------------------------------
//  Low-discrepancy sequences
// -----------------------------------------------------------------------------

/* Radical inverse in base 2, the building block of the Halton sequence. */
float muon_radical_inverse_2(uint bits) {
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10;
}

/* Radical inverse in an arbitrary base, for decorrelated Halton dimensions. */
float muon_radical_inverse(uint index, uint base) {
    float result = 0.0;
    float inv_base = 1.0 / float(base);
    float fraction = inv_base;
    uint i = index;
    while (i > 0u) {
        result += float(i % base) * fraction;
        i /= base;
        fraction *= inv_base;
    }
    return result;
}

vec2 muon_halton_2d(uint index) {
    return vec2(muon_radical_inverse_2(index), muon_radical_inverse(index + 1u, 3u));
}

/*
 * R2 low-discrepancy sequence. Used for the camera jitter because it covers
 * the pixel footprint uniformly after only a handful of frames, which keeps
 * the temporal anti-aliasing stable while the player is standing still.
 */
vec2 muon_r2_sequence(uint index) {
    const float alpha_1 = 0.7548776662466927;
    const float alpha_2 = 0.5698402909980532;
    float i = float(index);
    return fract(vec2(0.5 + alpha_1 * i, 0.5 + alpha_2 * i));
}

// -----------------------------------------------------------------------------
//  Blue noise
// -----------------------------------------------------------------------------

/*
 * Fetches blue noise from the pack's noise texture. The texture is 512x512 and
 * tiles seamlessly, which gives all dithering and ray offsets a spatially
 * decorrelated pattern at no arithmetic cost.
 */
float muon_blue_noise(vec2 frag_coord, float channel) {
    vec2 uv = (frag_coord + vec2(0.5)) * (1.0 / float(noiseTextureResolution));
    if (channel < 0.5) {
        return texture(noisetex, uv).r;
    } else if (channel < 1.5) {
        return texture(noisetex, uv).g;
    }
    return texture(noisetex, uv).b;
}

float muon_blue_noise_temporal(vec2 frag_coord, uint frame) {
    float base = muon_blue_noise(frag_coord, 0.0);
    float offset = muon_radical_inverse_2(frame & 63u);
    return fract(base + offset);
}

/* Interleaved gradient noise: cheap, temporally stable dithering. */
float muon_interleaved_gradient_noise(vec2 frag_coord) {
    const vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(frag_coord, magic.xy) + muonFrame.time.x * 0.6180339887));
}

#endif // MUON_COMMON_RANDOM_GLSL
