/*
================================================================================

  Muon Shaders
  lib/brdf.glsl - physically based BRDFs and phase functions

  Cook-Torrance GGX with height-correlated Smith visibility, Schlick Fresnel
  and a multi-scattering energy compensation term. All functions are energy
  conserving and usable from both the raster path and the path tracer.

================================================================================
*/

#if !defined MUON_BRDF
#define MUON_BRDF

#include "/lib/common.glsl"
#include "/lib/random.glsl"

// ---------------
//   Fresnel
// ---------------

vec3 fresnel_schlick(vec3 f0, float cos_theta) {
    return f0 + (1.0 - f0) * pow5(1.0 - cos_theta);
}

float fresnel_schlick(float f0, float cos_theta) {
    return f0 + (1.0 - f0) * pow5(1.0 - cos_theta);
}

// Roughness-aware Fresnel used for environment reflections away from normal
// incidence. Avoids the "white rim" of plain Schlick on rough materials.
vec3 fresnel_schlick_roughness(vec3 f0, float roughness, float cos_theta) {
    return f0 + (max(vec3(1.0 - roughness), f0) - f0) * pow5(1.0 - cos_theta);
}

// -----------------------------
//   Normal distribution (GGX)
// -----------------------------

float distribution_ggx(float NoH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;

    float d = (NoH * a2 - NoH) * NoH + 1.0;

    return a2 / (pi * d * d + eps);
}

// Height-correlated Smith visibility term, includes the 1/(4 NoL NoV) part
float visibility_smith_ggx(float NoV, float NoL, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;

    float lambda_v = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float lambda_l = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);

    return 0.5 / (lambda_v + lambda_l + eps);
}

// Geometry term alone, for the path tracer's PDF calculations
float smith_g1_ggx(float NoX, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    return 2.0 * NoX / (NoX + sqrt(a2 + (1.0 - a2) * NoX * NoX) + eps);
}

// -------------------------------
//   Multi-scattering energy
// -------------------------------

// Approximate average single-scatter Fresnel (Turquin / Fdez-Aguera)
vec3 multi_scatter_energy(vec3 f0, float roughness, float NoV) {
    float a = roughness * roughness;

    // Average Fresnel over the hemisphere for this roughness
    vec3 f_avg = f0 + (vec3(1.0) - f0) / (1.0 + 2.0 * a);

    // How much light is lost to the single-scatter assumption
    vec3 f_ms = f_avg * f_avg * (1.0 + 2.0 * a) / (1.0 - f_avg * (1.0 - 2.0 * a));

    return f_ms;
}

// Environment BRDF: split-sum approximation (Karis, mobile fit)
vec3 environment_brdf(vec3 f0, float roughness, float NoV) {
    const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
    const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);

    vec4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NoV)) * r.x + r.y;

    vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;

    vec3 specular = f0 * ab.x + ab.y;

    // Energy compensation for the lost multi-bounce
    return specular + multi_scatter_energy(f0, roughness, NoV) * 0.5;
}

// -------------------------
//   Specular BRDF (GGX)
// -------------------------

vec3 specular_brdf(vec3 f0, float roughness, float NoV, float NoL, float NoH, float VoH) {
    if (NoL <= 0.0 || NoV <= 0.0) return vec3(0.0);

    float D = distribution_ggx(NoH, roughness);
    float V = visibility_smith_ggx(NoV, NoL, roughness);
    vec3 F = fresnel_schlick(f0, VoH);

    vec3 single = D * V * F;

    // Add the energy lost to single scattering, weighted by the Fresnel
    vec3 F_avg = f0 + (vec3(1.0) - f0) * 0.045;
    vec3 multi = single * F_avg * (1.0 - smith_g1_ggx(NoL, roughness));

    return single + multi * 0.5;
}

// -------------------------
//   Diffuse BRDF
// -------------------------

float diffuse_lambert(float NoL) {
    return NoL * rcp_pi;
}

// Burley / Disney diffuse - subtle retro-reflection, nice on rough stone
float diffuse_burley(float NoV, float NoL, float VoH, float roughness) {
    float fd90 = 0.5 + 2.0 * roughness * VoH * VoH;
    float light_scatter = 1.0 + (fd90 - 1.0) * pow5(1.0 - NoL);
    float view_scatter = 1.0 + (fd90 - 1.0) * pow5(1.0 - NoV);
    return light_scatter * view_scatter * NoL * rcp_pi;
}

// Wrapped diffuse for foliage and cloth
float diffuse_wrapped(float NoL, float wrap) {
    return max0((NoL + wrap) / (1.0 + wrap)) * rcp_pi;
}

// Cheaper subsurface approximation: two wrapped lobes tinted by the albedo
vec3 subsurface_brdf(vec3 albedo, float NoV, float NoL, float VoH, float sss) {
    if (sss <= 0.0) return vec3(0.0);

    float wrap = mix(0.1, 0.6, sss);
    float back = diffuse_wrapped(-NoL, wrap);

    vec3 tint = pow(albedo, vec3(0.6)) * vec3(1.0, 0.85, 0.75);

    return tint * back * sss * 0.6;
}

// -------------------------
//   Cloth sheen
// -------------------------

float sheen_brdf(float roughness, float NoV, float NoL, float VoH) {
    float D = distribution_ggx(VoH, max(roughness, 0.3));
    return D * NoL * 0.25;
}

// ----------------
//   Sampling
// ----------------

// Importance sample GGX half vectors (VNDF-free approximation: NDF sampling)
vec3 sample_ggx(vec3 N, float roughness, vec2 u) {
    float a = roughness * roughness;

    float phi = tau * u.y;
    float cos_theta = sqrt((1.0 - u.x) / (1.0 + (a * a - 1.0) * u.x));
    float sin_theta = sqrt(max0(1.0 - cos_theta * cos_theta));

    vec3 h_local = vec3(sin_theta * cos(phi), sin_theta * sin(phi), cos_theta);

    vec3 t;
    vec3 b;
    build_basis(N, t, b);

    return normalize(t * h_local.x + b * h_local.y + N * h_local.z);
}

// PDF of the NDF sampling above, for MIS weights
float pdf_ggx(vec3 N, vec3 H, float roughness) {
    float NoH = max0(dot(N, H));
    float a = roughness * roughness;
    float a2 = a * a;
    float d = (NoH * a2 - NoH) * NoH + 1.0;
    return a2 * NoH / (pi * d * d + eps);
}

// Cosine hemisphere PDF
float pdf_cosine(vec3 N, vec3 L) {
    return max0(dot(N, L)) * rcp_pi;
}

// ---------------------
//   Phase functions
// ---------------------

// Henyey-Greenstein. g > 0 forward scattering, g < 0 back scattering.
float phase_henyey_greenstein(float cos_theta, float g) {
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cos_theta;
    return (1.0 - g2) / (4.0 * pi * max(denom * sqrt(max(denom, eps)), eps));
}

// Two-lobe HG for clouds: strong forward lobe + weak isotropic lobe
float phase_cloud(float cos_theta, float forward, float back) {
    return mix(phase_henyey_greenstein(cos_theta, forward),
               phase_henyey_greenstein(cos_theta, -back),
               0.35);
}

// Rayleigh phase
float phase_rayleigh(float cos_theta) {
    return (3.0 / (16.0 * pi)) * (1.0 + cos_theta * cos_theta);
}

// Cornette-Shanks: improved Rayleigh phase for aerosols
float phase_cornette_shanks(float cos_theta, float g) {
    float g2 = g * g;
    float num = 3.0 * (1.0 - g2) * (1.0 + cos_theta * cos_theta);
    float den = 8.0 * pi * (2.0 + g2) * pow(1.0 + g2 - 2.0 * g * cos_theta, 1.5);
    return num / max(den, eps);
}

// -------------------------
//   Specular occlusion
// -------------------------

// Reduces environment specular in occluded areas. Without this, SSAO/GTAO
// makes the scene look wrong because reflections keep full strength.
float specular_occlusion(float NoV, float ao, float roughness) {
    return clamp01(pow(NoV + ao, exp2(-16.0 * roughness - 1.0)) - 1.0 + ao);
}

#endif // MUON_BRDF
