/*
================================================================================

  Muon Shaders - voxy_opaque.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Voxy LOD geometry - opaque path.

  Voxy compiles its own program around this file and calls voxy_emitFragment()
  once per LOD quad. Everything the pack needs is derived here and written into
  the same opaque g-buffer that vanilla terrain uses, so Voxy's LOD ring is lit,
  shadowed and temporally filtered identically to nearby chunks.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_write.glsl"
#include "/lib/common/noise.glsl"

layout(location = 0) out vec4 out_albedo;
layout(location = 1) out vec4 out_normal;
layout(location = 2) out vec4 out_surface;
layout(location = 3) out vec4 out_lightmap;

/* RENDERTARGETS: 1,2,3,4 */

/*
 * Voxy reports the face as an index 0..5. Bit 0 selects the sign, bits 1..2
 * select the axis, which decodes to an axis-aligned unit normal.
 */
vec3 muon_voxy_normal(uint face) {
    uint axis = face >> 1;
    uint positive = face & 1u;
    vec3 normal = vec3(0.0);

    if (axis == 0u) {
        normal.x = 1.0;
    } else if (axis == 1u) {
        normal.y = 1.0;
    } else {
        normal.z = 1.0;
    }

    return positive == 1u ? normal : -normal;
}

int muon_voxy_material(uint custom_id) {
    /* Voxy's custom id mirrors the block.properties id space. */
    if (custom_id < 10000u) {
        return MUON_MAT_STONE;
    }
    uint custom = custom_id - 10000u;
    if (custom == 1u) {
        return MUON_MAT_LEAVES;
    } else if (custom == 2u) {
        return MUON_MAT_FOLIAGE;
    } else if (custom == 3u) {
        return MUON_MAT_LAVA;
    } else if (custom == 4u) {
        return MUON_MAT_WATER;
    } else if (custom == 5u) {
        return MUON_MAT_METAL;
    } else if (custom == 6u) {
        return MUON_MAT_EMISSIVE;
    } else if (custom == 7u) {
        return MUON_MAT_SAND;
    } else if (custom == 8u) {
        return MUON_MAT_ICE;
    } else if (custom == 9u) {
        return MUON_MAT_PLANT;
    } else if (custom == 10u) {
        return MUON_MAT_WOOD;
    } else if (custom == 11u) {
        return MUON_MAT_SNOW;
    } else if (custom == 12u) {
        return MUON_MAT_GLASS;
    }
    return MUON_MAT_STONE;
}

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec3 albedo = muon_srgb_to_linear(parameters.sampledColour.rgb * parameters.tinting.rgb);

    MuonMaterial material = muon_material_default();
    material.albedo = albedo;
    material.id = muon_voxy_material(parameters.customId);
    material.normal = normalize(muon_world_to_view_dir(muon_voxy_normal(parameters.face)));

    vec2 light_levels = muon_saturate((parameters.lightMap * 16.0 - 0.5) / 15.0);
    material.blocklight = light_levels.x;
    material.skylight = light_levels.y;
    material.ao = 1.0;

    if (material.id == MUON_MAT_LEAVES || material.id == MUON_MAT_FOLIAGE) {
        material.porosity = 0.55;
        material.smoothness = 0.25;
        material.flag = MUON_FLAG_FOLIAGE;
    } else if (material.id == MUON_MAT_METAL) {
        material.f0 = vec3(0.55);
        material.smoothness = 0.70;
    } else if (material.id == MUON_MAT_LAVA || material.id == MUON_MAT_EMISSIVE) {
        material.emission = muon_luminance(albedo) * 2.0 * EMISSION_STRENGTH;
    } else if (material.id == MUON_MAT_SNOW) {
        material.smoothness = 0.40;
        material.f0 = vec3(0.02);
    } else {
        material.smoothness = 0.35;
    }

    float view_depth = gl_FragCoord.w > 0.0 ? 1.0 / gl_FragCoord.w : 1.0;

    out_albedo = muon_encode_albedo(material);
    out_normal = vec4(material.normal, muon_encode_smoothness(material.smoothness));
    out_surface = muon_encode_surface(material, view_depth);
    out_lightmap = muon_encode_lightmap(material);
}
