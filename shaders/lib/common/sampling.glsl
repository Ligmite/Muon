/*
================================================================================

  Muon Shaders - lib/common/sampling.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Sample distributions shared by the post-processing chain, the reflection
  tracer and the path tracer.

  Every function returns directions in tangent space (z = normal). The caller
  transforms with muon_tangent_frame(), which keeps this file free of any
  assumption about how a normal is stored.

================================================================================
*/

#ifndef MUON_COMMON_SAMPLING_GLSL
#define MUON_COMMON_SAMPLING_GLSL

#include "/lib/common/math.glsl"
#include "/lib/common/random.glsl"

// -----------------------------------------------------------------------------
//  Low-discrepancy point sets
// -----------------------------------------------------------------------------

vec2 muon_hammersley_2d(uint index, uint count) {
    return vec2(float(index) / float(count), muon_radical_inverse_2(index));
}

/* Cranley-Patterson rotation: decorrelates a point set without losing its
   stratification. */
vec2 muon_rotate_point_set(vec2 point, vec2 rotation) {
    return fract(point + rotation);
}

vec2 muon_vogel_disk(int index, int count, float rotation) {
    float golden = 2.39996322972865332;
    float r = sqrt((float(index) + 0.5) / float(count));
    float theta = float(index) * golden + rotation;
    return r * vec2(cos(theta), sin(theta));
}

// -----------------------------------------------------------------------------
//  Hemisphere sampling
// -----------------------------------------------------------------------------

/* Uniformly distributed direction on the sphere. */
vec3 muon_uniform_sphere(vec2 xi) {
    float cos_theta = 1.0 - 2.0 * xi.x;
    float sin_theta = sqrt(max(1.0 - cos_theta * cos_theta, 0.0));
    float phi = MUON_TAU * xi.y;
    return vec3(sin_theta * cos(phi), sin_theta * sin(phi), cos_theta);
}

/* Cosine-weighted hemisphere direction (important sampling of Lambert). */
vec3 muon_cosine_hemisphere(vec2 xi) {
    float r = sqrt(xi.x);
    float phi = MUON_TAU * xi.y;
    return vec3(r * cos(phi), r * sin(phi), sqrt(max(1.0 - xi.x, 0.0)));
}

/* Powers of a cosine lobe, used by the subsurface scatter gather. */
vec3 muon_cosine_power_hemisphere(vec2 xi, float power) {
    float phi = MUON_TAU * xi.y;
    float cos_theta = pow(xi.x, 1.0 / (power + 1.0));
    float sin_theta = sqrt(max(1.0 - cos_theta * cos_theta, 0.0));
    return vec3(sin_theta * cos(phi), sin_theta * sin(phi), cos_theta);
}

/*
 * GGX visible-normal importance sample (Heitz 2018). Returns a half vector in
 * tangent space; the caller reflects the view direction about it.
 */
vec3 muon_ggx_sample_half_vector(vec2 xi, vec2 alpha) {
    vec3 vh = normalize(vec3(alpha.x * sqrt(xi.x), alpha.y * sqrt(xi.y), sqrt(max(1.0 - xi.x - xi.y, 0.0))));
    return normalize(vec3(vh.xy + vh.z * vh.xy, vh.z));
}

/* Cheap disk sample for depth-of-field and screen-space tracing. */
vec2 muon_sample_disk(vec2 xi, float radius) {
    float r = radius * sqrt(xi.x);
    float phi = MUON_TAU * xi.y;
    return r * vec2(cos(phi), sin(phi));
}

/* Concentric disk mapping: keeps the centre of the disk denser than a polar
   mapping, which is what makes small apertures look clean. */
vec2 muon_concentric_disk(vec2 xi, float radius) {
    vec2 offset = xi * 2.0 - 1.0;
    if (abs(offset.x) < MUON_EPSILON && abs(offset.y) < MUON_EPSILON) {
        return vec2(0.0);
    }
    float r;
    float theta;
    if (abs(offset.x) > abs(offset.y)) {
        r = offset.x;
        theta = (MUON_PI * 0.25) * (offset.y / offset.x);
    } else {
        r = offset.y;
        theta = (MUON_PI * 0.5) - (MUON_PI * 0.25) * (offset.x / offset.y);
    }
    return radius * r * vec2(cos(theta), sin(theta));
}

/* Cone sampling around an axis for soft shadow and ambient occlusion rays. */
vec3 muon_cone_sample(vec3 axis, float cone_angle_radians, vec2 xi) {
    float cos_theta = mix(cos(cone_angle_radians), 1.0, xi.x);
    float sin_theta = sqrt(max(1.0 - cos_theta * cos_theta, 0.0));
    float phi = MUON_TAU * xi.y;
    vec3 local = vec3(sin_theta * cos(phi), sin_theta * sin(phi), cos_theta);
    mat3 frame = muon_tangent_frame(axis);
    return normalize(frame * local);
}

// -----------------------------------------------------------------------------
//  Interleaved gradient sampling used by the AO and reflection kernels
// -----------------------------------------------------------------------------

/* Offsets a rotation per pixel so that neighbouring kernels are decorrelated. */
float muon_pixel_rotation(vec2 frag_coord) {
    return muon_interleaved_gradient_noise(frag_coord) * MUON_TAU;
}

/* Rotates a 2D basis by the per-pixel rotation. */
vec2 muon_rotate_kernel(vec2 v, vec2 frag_coord) {
    float angle = muon_pixel_rotation(frag_coord);
    float s = sin(angle);
    float c = cos(angle);
    return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

#endif // MUON_COMMON_SAMPLING_GLSL
