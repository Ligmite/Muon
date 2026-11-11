/*
================================================================================

  Muon Shaders - lib/common/brdf.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Physically based shading models.

  One implementation of each term is shared by every consumer: the deferred
  lighting pass, the water pass, the reflection tracer and the path tracer all
  call these functions. No stage re-derives a BRDF locally.

  Conventions:
    * Directions point away from the shading point (towards the light for L).
    * n_dot_v and n_dot_l are clamped to zero by the callers.
    * Roughness is perceptual (alpha = roughness^2) and taken from LabPBR's
      "smoothness" as: roughness = (1 - smoothness)^2.

================================================================================
*/

#ifndef MUON_COMMON_BRDF_GLSL
#define MUON_COMMON_BRDF_GLSL

#include "/lib/common/math.glsl"
#include "/lib/common/color.glsl"

// -----------------------------------------------------------------------------
//  Microfacet distribution
// -----------------------------------------------------------------------------

float muon_ggx_distribution(float n_dot_h, float alpha) {
    float a2 = alpha * alpha;
    float d = (n_dot_h * a2 - n_dot_h) * n_dot_h + 1.0;
    return a2 / max(MUON_PI * d * d, MUON_EPSILON);
}

float muon_smith_g1(float n_dot_x, float alpha) {
    float a2 = alpha * alpha;
    float lambda = 0.5 * (sqrt(1.0 + a2 * (1.0 - n_dot_x * n_dot_x) / max(n_dot_x * n_dot_x, MUON_EPSILON)) - 1.0);
    return 1.0 / (1.0 + lambda);
}

/* Height-correlated Smith visibility term: V = G / (4 NdotL NdotV). */
float muon_visibility_smith_correlated(float n_dot_v, float n_dot_l, float alpha) {
    float a2 = alpha * alpha;
    float gv = n_dot_l * sqrt(n_dot_v * n_dot_v * (1.0 - a2) + a2);
    float gl = n_dot_v * sqrt(n_dot_l * n_dot_l * (1.0 - a2) + a2);
    return 0.5 / max(gv + gl, MUON_EPSILON);
}

// -----------------------------------------------------------------------------
//  Fresnel
// -----------------------------------------------------------------------------

vec3 muon_fresnel_schlick(vec3 f0, float cos_theta) {
    float f = muon_pow5(1.0 - cos_theta);
    return f0 + (vec3(1.0) - f0) * f;
}

float muon_fresnel_schlick(float f0, float cos_theta) {
    return f0 + (1.0 - f0) * muon_pow5(1.0 - cos_theta);
}

/* Fresnel with a roughness-aware ceiling, used for image-based lighting. */
vec3 muon_fresnel_schlick_roughness(vec3 f0, float cos_theta, float roughness) {
    float ceiling = max(1.0 - roughness, f0.r);
    return f0 + (vec3(ceiling) - f0) * muon_pow5(1.0 - cos_theta);
}

/* Exact dielectric Fresnel for a given IOR. */
float muon_fresnel_dielectric(float cos_theta, float ior) {
    float f0 = (ior - 1.0) / (ior + 1.0);
    f0 *= f0;
    float sin_theta_t2 = (1.0 - cos_theta * cos_theta) / (ior * ior);
    if (sin_theta_t2 >= 1.0) {
        return 1.0;
    }
    float cos_theta_t = sqrt(max(1.0 - sin_theta_t2, 0.0));
    float rs = (cos_theta - ior * cos_theta_t) / max(cos_theta + ior * cos_theta_t, MUON_EPSILON);
    float rp = (ior * cos_theta - cos_theta_t) / max(ior * cos_theta + cos_theta_t, MUON_EPSILON);
    return muon_saturate(0.5 * (rs * rs + rp * rp));
}

// -----------------------------------------------------------------------------
//  Specular and diffuse lobes
// -----------------------------------------------------------------------------

/*
 * Cook-Torrance specular for a punctual light. Returns radiance already
 * multiplied by the incoming radiance; the caller adds NdotL scaling.
 */
vec3 muon_specular_ggx(
    vec3 normal,
    vec3 view_dir,
    vec3 light_dir,
    vec3 f0,
    float alpha
) {
    vec3 half_vector = normalize(view_dir + light_dir);
    float n_dot_v = max(dot(normal, view_dir), 0.0);
    float n_dot_l = max(dot(normal, light_dir), 0.0);
    float n_dot_h = max(dot(normal, half_vector), 0.0);
    float v_dot_h = max(dot(view_dir, half_vector), 0.0);

    float d = muon_ggx_distribution(n_dot_h, alpha);
    float vis = muon_visibility_smith_correlated(n_dot_v, n_dot_l, alpha);
    vec3 f = muon_fresnel_schlick(f0, v_dot_h);

    return d * vis * f;
}

/* Lambertian diffuse with an energy-preserving (1 - F) factor. */
vec3 muon_diffuse_lambert(vec3 albedo, float n_dot_l) {
    return albedo * (n_dot_l * MUON_INV_PI);
}

/*
 * Wrapped diffuse for foliage and other thin, light-transmitting surfaces.
 * "scatter" is the fraction that bleeds through to the shaded side.
 */
float muon_diffuse_wrap(float n_dot_l, float scatter) {
    return muon_saturate((n_dot_l + scatter) / ((1.0 + scatter) * (1.0 + scatter)));
}

/*
 * Transmission through a thin leaf: light that passes through is tinted by the
 * leaf's own albedo and strongest when looking towards the sun.
 */
vec3 muon_diffuse_transmission(
    vec3 albedo,
    vec3 view_dir,
    vec3 light_dir,
    float scatter_amount,
    float transmission
) {
    float forward = muon_saturate(dot(view_dir, -light_dir));
    float strength = pow(forward, 3.0) * transmission;
    return albedo * (strength * scatter_amount * MUON_INV_PI);
}

// -----------------------------------------------------------------------------
//  Image-based lighting helpers
// -----------------------------------------------------------------------------

/*
 * Analytic approximation of the split-sum environment BRDF (Karis 2013).
 * Returns (scale, bias) such that:
 *     env = radiance * (f0 * scale + bias)
 */
vec2 muon_environment_brdf(float roughness, float n_dot_v) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
    vec4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * n_dot_v)) * r.x + r.y;
    return vec2(-1.04, 1.04) * a004 + r.zw;
}

vec3 muon_environment_specular(vec3 radiance, vec3 f0, float roughness, float n_dot_v) {
    vec2 ab = muon_environment_brdf(roughness, n_dot_v);
    return radiance * (f0 * ab.x + vec3(ab.y));
}

// -----------------------------------------------------------------------------
//  Material remapping
// -----------------------------------------------------------------------------

/* LabPBR perceptual smoothness to GGX alpha. */
float muon_alpha_from_smoothness(float smoothness) {
    float roughness = 1.0 - muon_saturate(smoothness);
    return roughness * roughness;
}

/*
 * Muon interprets LabPBR 1.3's red channel as a linear F0 in [0,1], which is
 * how the specification defines it: 0 is a perfect dielectric absence of
 * reflection, 255 is a mirror. Metals therefore read back as their measured
 * reflectance without an extra mapping.
 */
vec3 muon_f0_from_labpbr(float red) {
    return vec3(muon_saturate(red));
}

/* Perceptual roughness from LabPBR smoothness, for the IBL terms. */
float muon_roughness_from_smoothness(float smoothness) {
    return 1.0 - muon_saturate(smoothness);
}

#endif // MUON_COMMON_BRDF_GLSL
