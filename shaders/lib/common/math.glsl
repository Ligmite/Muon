/*
================================================================================

  Muon Shaders - lib/common/math.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Scalar and vector maths shared by every stage. Strict-type discipline: every
  overload takes and returns the same precision, and no function relies on
  implicit int-to-float conversion, so the same source cross-compiles cleanly to
  SPIR-V and WGSL.

================================================================================
*/

#ifndef MUON_COMMON_MATH_GLSL
#define MUON_COMMON_MATH_GLSL

const float MUON_PI = 3.14159265358979323846;
const float MUON_TAU = 6.28318530717958647692;
const float MUON_HALF_PI = 1.57079632679489661923;
const float MUON_INV_PI = 0.31830988618379067154;
const float MUON_INV_TAU = 0.15915494309189533577;
const float MUON_DEG2RAD = 0.01745329251994329577;
const float MUON_RAD2DEG = 57.29577951308232087680;
const float MUON_GOLDEN_RATIO = 1.61803398874989484820;
const float MUON_SQRT2 = 1.41421356237309504880;
const float MUON_EPSILON = 1.0e-6;
const float MUON_LARGE = 1.0e20;

// -----------------------------------------------------------------------------
//  Saturating helpers
// -----------------------------------------------------------------------------

float muon_saturate(float x) {
    return clamp(x, 0.0, 1.0);
}

vec2 muon_saturate(vec2 x) {
    return clamp(x, vec2(0.0), vec2(1.0));
}

vec3 muon_saturate(vec3 x) {
    return clamp(x, vec3(0.0), vec3(1.0));
}

vec4 muon_saturate(vec4 x) {
    return clamp(x, vec4(0.0), vec4(1.0));
}

// -----------------------------------------------------------------------------
//  Powers and roots
// -----------------------------------------------------------------------------

float muon_square(float x) {
    return x * x;
}

vec2 muon_square(vec2 x) {
    return x * x;
}

vec3 muon_square(vec3 x) {
    return x * x;
}

float muon_cube(float x) {
    return x * x * x;
}

vec3 muon_cube(vec3 x) {
    return x * x * x;
}

float muon_pow5(float x) {
    float x2 = x * x;
    return x2 * x2 * x;
}

float muon_pow8(float x) {
    float x2 = x * x;
    float x4 = x2 * x2;
    return x4 * x4;
}

float muon_rcp(float x) {
    return 1.0 / max(abs(x), MUON_EPSILON);
}

float muon_safe_div(float a, float b) {
    return a / max(abs(b), MUON_EPSILON);
}

vec3 muon_safe_div(vec3 a, float b) {
    return a / max(abs(b), MUON_EPSILON);
}

// -----------------------------------------------------------------------------
//  Ranges
// -----------------------------------------------------------------------------

float muon_remap(float x, float a, float b, float c, float d) {
    return c + (x - a) * (d - c) / max(b - a, MUON_EPSILON);
}

vec3 muon_remap(vec3 x, vec3 a, vec3 b, vec3 c, vec3 d) {
    return c + (x - a) * (d - c) / max(b - a, vec3(MUON_EPSILON));
}

float muon_remap_clamped(float x, float a, float b, float c, float d) {
    return clamp(muon_remap(x, a, b, c, d), min(c, d), max(c, d));
}

float muon_linear_step(float low, float high, float x) {
    return muon_saturate((x - low) / max(high - low, MUON_EPSILON));
}

vec2 muon_linear_step(vec2 low, vec2 high, vec2 x) {
    return muon_saturate((x - low) / max(high - low, vec2(MUON_EPSILON)));
}

float muon_smooth_inverse(float x) {
    return x * x * (3.0 - 2.0 * x);
}

/* Smooth-step that is numerically stable when the edges are equal. */
float muon_smoothstep(float edge0, float edge1, float x) {
    return muon_smooth_inverse(muon_linear_step(edge0, edge1, x));
}

float muon_bump(float x) {
    return muon_saturate(1.0 - abs(x));
}

/* Exponential falloff normalised so that it reaches 0 at x = 1. */
float muon_falloff(float x, float half_life) {
    return exp2(-max(x, 0.0) / max(half_life, MUON_EPSILON));
}

// -----------------------------------------------------------------------------
//  Aggregates
// -----------------------------------------------------------------------------

float muon_min3(vec3 v) {
    return min(min(v.x, v.y), v.z);
}

float muon_max3(vec3 v) {
    return max(max(v.x, v.y), v.z);
}

float muon_min_abs3(vec3 v) {
    return min(min(abs(v.x), abs(v.y)), abs(v.z));
}

float muon_average(vec3 v) {
    return (v.x + v.y + v.z) * 0.33333333333;
}

float muon_average(vec2 v) {
    return (v.x + v.y) * 0.5;
}

vec2 muon_cartesian_to_polar(vec2 v) {
    return vec2(length(v), atan(v.y, v.x));
}

vec2 muon_polar_to_cartesian(vec2 p) {
    return p.x * vec2(cos(p.y), sin(p.y));
}

// -----------------------------------------------------------------------------
//  Geometry
// -----------------------------------------------------------------------------

mat2 muon_rotation_2d(float radians) {
    float s = sin(radians);
    float c = cos(radians);
    return mat2(c, s, -s, c);
}

vec3 muon_safe_normalize(vec3 v) {
    float len = length(v);
    return len > MUON_EPSILON ? v / len : vec3(0.0, 0.0, 1.0);
}

vec3 muon_safe_normalize(vec3 v, vec3 fallback) {
    float len = length(v);
    return len > MUON_EPSILON ? v / len : fallback;
}

/*
 * Builds an orthonormal tangent frame from a normal using the branchless
 * Duff et al. method. Cheaper and more robust than the naive cross-product
 * approach for normals close to the up axis.
 */
mat3 muon_tangent_frame(vec3 n) {
    float sign_n = n.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (sign_n + n.z);
    float b = n.x * n.y * a;
    vec3 t = vec3(1.0 + sign_n * n.x * n.x * a, sign_n * b, -sign_n * n.x);
    vec3 bitangent = vec3(b, sign_n + n.y * n.y * a, -n.y);
    return mat3(t, bitangent, n);
}

/* Reflects a direction about a unit normal. */
vec3 muon_reflect(vec3 incident, vec3 normal) {
    return incident - 2.0 * dot(normal, incident) * normal;
}

/* Refracts according to Snell's law; returns zero vector on total internal reflection. */
vec3 muon_refract(vec3 incident, vec3 normal, float eta) {
    float cos_i = clamp(dot(-incident, normal), -1.0, 1.0);
    float sin_t2 = eta * eta * (1.0 - cos_i * cos_i);
    if (sin_t2 >= 1.0) {
        return vec3(0.0);
    }
    float cos_t = sqrt(max(1.0 - sin_t2, 0.0));
    return eta * incident + (eta * cos_i - cos_t) * normal;
}

/* Intersects a ray with the sphere of the given radius centred at the origin. */
float muon_ray_sphere(vec3 origin, vec3 direction, float radius) {
    float b = dot(origin, direction);
    float c = dot(origin, origin) - radius * radius;
    float h = b * b - c;
    if (h < 0.0) {
        return -1.0;
    }
    h = sqrt(h);
    float t0 = -b - h;
    float t1 = -b + h;
    if (t1 < 0.0) {
        return -1.0;
    }
    return t0 >= 0.0 ? t0 : t1;
}

/* Intersects a ray with the plane y = height; returns -1.0 when it misses. */
float muon_ray_plane_y(vec3 origin, vec3 direction, float height) {
    float denom = direction.y;
    if (abs(denom) < MUON_EPSILON) {
        return -1.0;
    }
    float t = (height - origin.y) / denom;
    return t > 0.0 ? t : -1.0;
}

/*
 * Intersects a ray with an axis-aligned box. Returns tMin (>= 0) on a hit and
 * -1.0 on a miss, matching the convention used by the screen-space tracers.
 */
float muon_ray_box(vec3 origin, vec3 direction, vec3 boxMin, vec3 boxMax) {
    vec3 inv = 1.0 / direction;
    vec3 t0 = (boxMin - origin) * inv;
    vec3 t1 = (boxMax - origin) * inv;
    vec3 tmin = min(t0, t1);
    vec3 tmax = max(t0, t1);
    float tNear = max(max(tmin.x, tmin.y), tmin.z);
    float tFar = min(min(tmax.x, tmax.y), tmax.z);
    if (tFar < max(tNear, 0.0)) {
        return -1.0;
    }
    return tNear >= 0.0 ? tNear : -1.0;
}

// -----------------------------------------------------------------------------
//  Numerical hygiene
// -----------------------------------------------------------------------------

bool muon_is_finite(float x) {
    return !(isnan(x) || isinf(x));
}

bool muon_is_finite(vec3 v) {
    return muon_is_finite(v.x) && muon_is_finite(v.y) && muon_is_finite(v.z);
}

vec3 muon_sanitize(vec3 v) {
    return muon_is_finite(v) ? max(v, vec3(0.0)) : vec3(0.0);
}

float muon_sanitize(float x) {
    return muon_is_finite(x) ? x : 0.0;
}

/* Clamps to a sane HDR range to stop fireflies from poisoning the history. */
vec3 muon_clamp_hdr(vec3 c, float max_value) {
    return min(muon_sanitize(c), vec3(max_value));
}

#endif // MUON_COMMON_MATH_GLSL
