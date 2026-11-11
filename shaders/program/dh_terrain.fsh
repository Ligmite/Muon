/*
================================================================================

  Muon Shaders - program/dh_terrain.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Distant Horizons terrain fragment stage.

  LOD geometry has no LabPBR textures, no normal maps and no per-block lightmap
  detail, so it is shaded with conservative defaults: the LOD's own tint becomes
  the albedo, a moderate roughness keeps the far terrain from turning into a
  mirror, and the LOD lightmap value drives the block-light term.

  The optional noise term breaks up the flat colour afloat at distance, which is
  what stops the LOD ring from reading as a different renderer.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_write.glsl"
#include "/lib/common/noise.glsl"


in vec2 texcoord;
in vec2 lmcoord;
in vec4 tint;
in vec3 view_pos;
in vec3 view_normal;
flat in int material_id;

layout(location = 0) out vec4 out_albedo;
layout(location = 1) out vec4 out_normal;
layout(location = 2) out vec4 out_surface;
layout(location = 3) out vec4 out_lightmap;

/* RENDERTARGETS: 1,2,3,4 */

void main() {
    MUON_FRAME_INIT();

    vec4 texel = texture(gtexture, texcoord) * tint;
    if (texel.a < muon_alpha_test_ref()) {
        discard;
    }

    MuonMaterial material = muon_material_default();
    material.id = material_id;
    material.albedo = muon_srgb_to_linear(texel.rgb);
    material.normal = normalize(view_normal);

    vec2 light_levels = muon_decode_lightmap(lmcoord);
    material.blocklight = light_levels.x;
    material.skylight = light_levels.y;
    material.ao = 1.0;

    /* Material defaults by class, since LOD geometry has no LabPBR maps. */
    if (material_id == MUON_MAT_LEAVES) {
        material.smoothness = 0.25;
        material.porosity = 0.55;
        material.flag = MUON_FLAG_FOLIAGE;
    } else if (material_id == MUON_MAT_SNOW) {
        material.smoothness = 0.40;
        material.porosity = 0.45;
        material.f0 = vec3(0.02);
    } else if (material_id == MUON_MAT_METAL) {
        material.smoothness = 0.70;
        material.f0 = vec3(0.55);
    } else if (material_id == MUON_MAT_LAVA || material_id == MUON_MAT_EMISSIVE) {
        material.emission = muon_luminance(material.albedo) * 2.0 * EMISSION_STRENGTH;
    } else if (material_id == MUON_MAT_SAND) {
        material.smoothness = 0.30;
        material.porosity = 0.25;
    } else {
        material.smoothness = 0.35;
    }

#if defined DH_NOISE
    vec3 world_pos = muon_view_to_world_pos(view_pos);
    float variation = muon_value_noise_2d(world_pos.xz * 0.11) - 0.5;
    material.albedo *= 1.0 + variation * DH_NOISE_STRENGTH * 0.35;
#endif

    out_albedo = muon_encode_albedo(material);
    out_normal = vec4(material.normal, muon_encode_smoothness(material.smoothness));
    out_surface = muon_encode_surface(material, -view_pos.z);
    out_lightmap = muon_encode_lightmap(material);
}
