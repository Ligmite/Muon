/*
================================================================================

  Muon Shaders - lib/common/material.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  The material description that flows through the whole renderer, plus the
  shared rules that turn raw texture data into shading inputs.

  Standardised layout (LabPBR 1.3), identical on every backend:

      R = F0 (linear, 0..1)
      G = perceptual smoothness (0..1)
      B = porosity (0..1; drives subsurface scattering)
      A = 0..254 emissive luminance, 255 = subsurface-scattering dielectric

  Frostbite/Disney style reflectance-to-F0 remapping is deliberately *not*
  applied: LabPBR defines the red channel as F0 directly, so applying a second
  mapping would make Muon disagree with every compliant resource pack.

================================================================================
*/

#ifndef MUON_COMMON_MATERIAL_GLSL
#define MUON_COMMON_MATERIAL_GLSL

#include "/lib/common/constants.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/brdf.glsl"
#include "/lib/common/color.glsl"

struct MuonMaterial {
    vec3 albedo;
    vec3 normal;
    vec3 f0;
    float smoothness;
    float roughness;
    float alpha;
    float porosity;
    float emission;
    float blocklight;
    float skylight;
    float ao;
    float flag;
    int id;
};

MuonMaterial muon_material_default() {
    MuonMaterial m;
    m.albedo = vec3(0.5);
    m.normal = vec3(0.0, 0.0, 1.0);
    m.f0 = vec3(MUON_HARDCODED_F0);
    m.smoothness = 0.4;
    m.roughness = 0.6;
    m.alpha = 1.0;
    m.porosity = 0.0;
    m.emission = 0.0;
    m.blocklight = 0.0;
    m.skylight = 1.0;
    m.ao = 1.0;
    m.flag = MUON_FLAG_NONE;
    m.id = MUON_MAT_STONE;
    return m;
}

// -----------------------------------------------------------------------------
//  Queries
// -----------------------------------------------------------------------------

bool muon_is_water(MuonMaterial m) {
    return m.id == MUON_MAT_WATER || m.flag == MUON_FLAG_WATER;
}

bool muon_is_translucent(MuonMaterial m) {
    return m.alpha < 0.999 || m.flag == MUON_FLAG_TRANSLUCENT || m.flag == MUON_FLAG_WATER;
}

bool muon_is_foliage(MuonMaterial m) {
    return m.id == MUON_MAT_LEAVES
        || m.id == MUON_MAT_PLANT
        || m.id == MUON_MAT_FOLIAGE
        || m.flag == MUON_FLAG_FOLIAGE;
}

bool muon_is_emissive(MuonMaterial m) {
    return m.emission > 0.001 || m.flag == MUON_FLAG_EMISSIVE;
}

bool muon_uses_sss(MuonMaterial m) {
    return m.porosity > 0.01 || muon_is_foliage(m);
}

/* Dielectrics and metals are distinguished by LabPBR's F0, not by a flag. */
bool muon_is_metal(MuonMaterial m) {
    return muon_luminance(m.f0) > 0.35;
}

/* Diffuse albedo of a metal is zero: all of its reflection is specular. */
vec3 muon_diffuse_albedo(MuonMaterial m) {
    return muon_is_metal(m) ? vec3(0.0) : m.albedo;
}

// -----------------------------------------------------------------------------
//  Wetness
//
//  Rain darkens and polishes exposed surfaces. The effect is driven by the
//  game's own wetness value (Iris exposes it with the correct halflife) so
//  that it dries out naturally when the rain stops.
// -----------------------------------------------------------------------------

MuonMaterial muon_apply_wetness(MuonMaterial m, float wetness, float puddle_mask) {
    if (wetness <= 0.001) {
        return m;
    }

    float exposed = muon_saturate(m.skylight);
    float amount = muon_saturate(wetness * exposed);
    float puddles = muon_saturate(puddle_mask * wetness * exposed);

    /* Water fills the micro-surface first: albedo darkens, roughness drops. */
    vec3 wet_albedo = m.albedo * mix(1.0, 0.62, amount);
    float wet_smoothness = mix(m.smoothness, 0.93, muon_saturate(amount * 1.25 + puddles * 0.6));
    vec3 wet_f0 = mix(m.f0, vec3(0.02), muon_saturate(puddles));

    m.albedo = mix(m.albedo, wet_albedo, amount);
    m.smoothness = wet_smoothness;
    m.roughness = muon_roughness_from_smoothness(wet_smoothness);
    m.f0 = wet_f0;
    return m;
}

// -----------------------------------------------------------------------------
//  Snow cover
//  Applied to upward faces during snowfall. Purely a material change; the
//  geometry is untouched.
// -----------------------------------------------------------------------------

MuonMaterial muon_apply_snow(MuonMaterial m, float snow_amount, float up_facing) {
    float cover = muon_saturate(snow_amount * up_facing);
    if (cover <= 0.001) {
        return m;
    }
    m.albedo = mix(m.albedo, vec3(0.86, 0.90, 0.95), cover);
    m.smoothness = mix(m.smoothness, 0.35, cover);
    m.roughness = muon_roughness_from_smoothness(m.smoothness);
    m.f0 = mix(m.f0, vec3(0.02), cover);
    m.porosity = mix(m.porosity, 0.65, cover);
    return m;
}

#endif // MUON_COMMON_MATERIAL_GLSL
