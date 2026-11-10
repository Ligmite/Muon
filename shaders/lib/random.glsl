/*
================================================================================

  Muon Shaders
  lib/random.glsl - hashing, sequences and sampling

  Everything is deterministic per (pixel, frame) so that TAA and the path
  tracer converge instead of flickering.

================================================================================
*/

#if !defined MUON_RANDOM
#define MUON_RANDOM

#include "/lib/common.glsl"

// -----------------
//   Integer hashes
// -----------------

uint pcg(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

uint pcg2(uint v) {
    v = pcg(v);
    return pcg(v);
}

uint hash_uvec2(uvec2 v) {
    return pcg(v.x + pcg(v.y));
}

uint hash_uvec3(uvec3 v) {
    return pcg(v.x + pcg(v.y + pcg(v.z)));
}

// [0, 1)
float u01(uint v) {
    return float(pcg(v) & 0x00FFFFFFu) / float(0x01000000u);
}

float hash11(float x) {
    return u01(uint(int(x) * 1 + 0x9E3779B9));
}

float hash12(vec2 v) {
    return u01(hash_uvec2(uvec2(ivec2(v * 4096.0))));
}

float hash13(vec3 v) {
    return u01(hash_uvec3(uvec3(ivec3(v * 4096.0))));
}

vec2 hash22(vec2 v) {
    uvec2 u = uvec2(ivec2(v * 4096.0));
    uint h = hash_uvec2(u);
    return vec2(u01(h), u01(pcg(h)));
}

vec3 hash33(vec3 v) {
    uvec3 u = uvec3(ivec3(v * 4096.0));
    uint h = hash_uvec3(u);
    return vec3(u01(h), u01(pcg(h)), u01(pcg2(h)));
}

float rand(float seed) {
    return u01(uint(int(seed * 65536.0) + 1));
}

// -----------------------
//   Low discrepancy
// -----------------------

const float golden_angle = 2.399963229728653;

// R2 sequence: 2D low-discrepancy points. Excellent for per-pixel jitter.
vec2 r2_sequence(int n) {
    return vec2(fract(0.5 + float(n) * 0.7548776662), fract(0.5 + float(n) * 0.5698402909));
}

// Halton(2,3) - used when a stable, non-rotating pattern is useful
float halton(int index, int base) {
    float result = 0.0;
    float inv_base = 1.0 / float(base);
    float fraction = inv_base;
    int i = index;
    while (i > 0) {
        result += float(i - (i / base) * base) * fraction;
        i /= base;
        fraction *= inv_base;
    }
    return result;
}

vec2 halton23(int index) {
    return vec2(halton(index, 2), halton(index, 3));
}

// Jimenez 2014 interleaved gradient noise - cheap, TAA friendly dither
float interleaved_gradient_noise(vec2 pixel_pos, float frame) {
    vec3 p = vec3(pixel_pos, frame);
    return fract(52.9829189 * fract(dot(p, vec3(0.06711056, 0.00583715, 0.5))));
}

float ign(vec2 pixel_pos) {
    return interleaved_gradient_noise(pixel_pos, 0.0);
}

// ----------------------
//   Blue noise texture
// ----------------------

// noisetex holds a 256x256 (or noiseTextureResolution x noiseTextureResolution)
// tiled blue-noise volume: r/g/b are independent channels, a is the mask.
vec4 sample_blue_noise(vec2 uv) {
    return texture(noisetex, uv);
}

// Per-pixel, per-frame rotation of the blue noise tile. The tile count is
// chosen so that neighbouring pixels do not share the same rotation.
vec4 blue_noise_sample(ivec2 pixel, int frame) {
    const float tile = 64.0;
    vec2 res = vec2(textureSize(noisetex, 0));
    vec2 uv = fract((vec2(pixel) + r2_sequence(frame) * tile) / res);
    return texture(noisetex, uv);
}

float blue_noise(vec2 uv, int frame) {
    vec2 res = vec2(textureSize(noisetex, 0));
    vec2 offset = r2_sequence(frame) * 64.0;
    return texture(noisetex, fract((uv * res + offset) / res)).x;
}

// --------------------
//   Sampling helpers
// --------------------

mat2 rotate2(float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, s, -s, c);
}

// Unit square -> uniform point on the unit sphere (Malley's method is used
// elsewhere when a cosine weight is desired)
vec3 uniform_sphere(vec2 u) {
    float z = u.x * 2.0 - 1.0;
    float a = u.y * tau;
    float r = sqrt(max0(1.0 - z * z));
    return vec3(r * cos(a), r * sin(a), z);
}

// Uniform point on a hemisphere around +Z
vec3 uniform_hemisphere(vec2 u) {
    float z = u.x;
    float a = u.y * tau;
    float r = sqrt(max0(1.0 - z * z));
    return vec3(r * cos(a), r * sin(a), z);
}

// Cosine-weighted hemisphere around +Z (Malley)
vec3 cosine_hemisphere(vec2 u) {
    float r = sqrt(u.x);
    float a = u.y * tau;
    return vec3(r * cos(a), r * sin(a), sqrt(max0(1.0 - u.x)));
}

// Sample a cone of half-angle `angle` around direction `dir`
vec3 cone_sample(vec3 dir, float cos_theta_max, vec2 u) {
    float cos_theta = 1.0 - u.x * (1.0 - cos_theta_max);
    float sin_theta = sqrt(max0(1.0 - cos_theta * cos_theta));
    float phi = u.y * tau;

    vec3 t;
    vec3 b;
    build_basis(dir, t, b);

    return normalize(t * (sin_theta * cos(phi)) + b * (sin_theta * sin(phi)) + dir * cos_theta);
}

// Uniform point in a unit disk
vec2 sample_disk(vec2 u) {
    float r = sqrt(u.x);
    float a = u.y * tau;
    return vec2(r * cos(a), r * sin(a));
}

// Projected solid angle of a sphere with radius r at distance d, normalised
float sphere_solid_angle(float radius, float distance) {
    return clamp01(radius * radius / max(distance * distance, eps));
}

// ----------------------
//   Bayer / dithering
// ----------------------

float bayer2(vec2 a) {
    a = floor(a);
    return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) { return bayer2(0.5 * a) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(0.5 * a) * 0.25 + bayer2(a); }
float bayer16(vec2 a) { return bayer8(0.5 * a) * 0.25 + bayer2(a); }

#endif // MUON_RANDOM
