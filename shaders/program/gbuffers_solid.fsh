/*
================================================================================

  Muon Shaders - program/gbuffers_solid.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Opaque g-buffer writer.

  Writes albedo, normal, surface and lightmap data. It deliberately writes no
  colour: the deferred stage owns lighting, so there is exactly one
  implementation of every lighting term in the pack.

  Targets:
      1  albedo.rgb, F0.a
      2  view normal.xyz, smoothness.a
      3  linear depth.r, material.g, emission.b, porosity.a
      4  blocklight.r, skylight.g, vertex AO.b, flags.a

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/texture.glsl"
#include "/lib/common/gbuffer_write.glsl"
#include "/lib/common/wetness.glsl"


in vec2 texcoord;
in vec2 lmcoord;
in vec4 tint;
in vec3 view_pos;
in vec3 view_normal;
flat in int material_id;
flat in float vertex_ao;

layout(location = 0) out vec4 out_albedo;
layout(location = 1) out vec4 out_normal;
layout(location = 2) out vec4 out_surface;
layout(location = 3) out vec4 out_lightmap;

/* RENDERTARGETS: 1,2,3,4 */

// -----------------------------------------------------------------------------
//  Material properties
// -----------------------------------------------------------------------------

float muon_material_sss_bias(int material) {
    if (material == MUON_MAT_LEAVES || material == MUON_MAT_FOLIAGE || material == MUON_MAT_PLANT) {
        return 0.55;
    }
    if (material == MUON_MAT_SNOW) {
        return 0.35;
    }
    return 0.0;
}

float muon_material_emission_bias(int material) {
    if (material == MUON_MAT_LAVA || material == MUON_MAT_EMISSIVE) {
        return 1.0;
    }
    return 0.0;
}

bool muon_material_allows_parallax(int material) {
    if (material == MUON_MAT_WATER || material == MUON_MAT_HAND || material == MUON_MAT_PLANT) {
        return false;
    }
    return true;
}

void main() {
    MUON_FRAME_INIT();

    vec4 albedo_texel = texture(gtexture, texcoord) * tint;
    vec3 albedo = muon_srgb_to_linear(albedo_texel.rgb);
    float albedo_luminance = muon_luminance(albedo);

    MuonMaterial material = muon_material_default();
    material.id = material_id;
    material.albedo = albedo;

    MuonSpecular specular = muon_decode_specular(texcoord);
    material.f0 = specular.f0;
    material.smoothness = specular.smoothness;
    material.porosity = specular.porosity;

    float emission = specular.emission;
    if (muon_material_emission_bias(material.id) > 0.5) {
        emission = max(emission, albedo_luminance * 1.8);
    }
    material.emission = emission * EMISSION_STRENGTH;

    material.porosity = max(material.porosity, muon_material_sss_bias(material.id));

    /* --- normal and parallax ------------------------------------------ */

    vec2 surface_uv = texcoord;
    float parallax_height = 0.0;

    /* Built before the alpha test so that the screen-space derivatives used by
       the cotangent frame are always taken in uniform control flow. */
    mat3 tbn = muon_cotangent_frame(normalize(view_normal), view_pos, texcoord);
    vec3 view_tangent = transpose(tbn) * normalize(-view_pos);

    if (muon_material_allows_parallax(material.id)) {
        surface_uv = muon_parallax_offset(texcoord, view_tangent, albedo_luminance, 1.0, parallax_height);
    }

    /* Alpha test. Iris' own test is disabled for this program, so the discard
       happens here, after the derivative work. */
    if (albedo_texel.a < muon_alpha_test_ref()) {
        discard;
    }

    vec3 normal = muon_apply_normal_map(normalize(view_normal), surface_uv, view_pos);
    material.normal = normal;

    /* --- light data ---------------------------------------------------- */

    /* Read before the weather pass: wetness and snow are both gated by how
       much sky a surface can see. */
    vec2 light_levels = muon_decode_lightmap(lmcoord);
    material.blocklight = light_levels.x;
    material.skylight = light_levels.y;
    material.ao = vertex_ao;
    material.flag = muon_is_foliage(material) ? MUON_FLAG_FOLIAGE : MUON_FLAG_NONE;

    /* --- wetness and snow --------------------------------------------- */

    vec3 world_pos = muon_view_to_world_pos(view_pos);
    float up_facing = muon_saturate(normalize(muon_view_to_world_dir(normal)).y * 0.5 + 0.5);
    material = muon_apply_wetting(material, world_pos, up_facing, parallax_height);

    /* --- write --------------------------------------------------------- */

    float linear_depth = -view_pos.z;

    out_albedo = muon_encode_albedo(material);
    out_normal = vec4(material.normal, muon_encode_smoothness(material.smoothness));
    out_surface = muon_encode_surface(material, linear_depth);
    out_lightmap = muon_encode_lightmap(material);
}
