/*
================================================================================

  Muon Shaders - voxy_translucent.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Voxy LOD geometry - translucent path.

  Writes the translucent g-buffer so that distant oceans and stained glass in the
  LOD ring are shaded by the same water and glass models as nearby geometry.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_write.glsl"

layout(location = 0) out vec4 out_albedo;
layout(location = 1) out vec4 out_normal;
layout(location = 2) out vec4 out_surface;

/* RENDERTARGETS: 9,10,11 */

vec3 muon_voxy_normal_t(uint face) {
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

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec3 albedo = muon_srgb_to_linear(parameters.sampledColour.rgb * parameters.tinting.rgb);

    MuonMaterial material = muon_material_default();
    material.albedo = albedo;
    material.normal = normalize(muon_world_to_view_dir(muon_voxy_normal_t(parameters.face)));
    material.alpha = muon_saturate(parameters.sampledColour.a * parameters.tinting.a);

    bool is_water = parameters.customId == 10004u;
    if (is_water) {
        material.id = MUON_MAT_WATER;
        material.f0 = vec3(0.02);
        material.smoothness = 0.96;
        material.alpha = max(material.alpha, 0.55);
        material.flag = MUON_FLAG_WATER;
    } else {
        material.id = MUON_MAT_GLASS;
        material.smoothness = 0.85;
        material.flag = MUON_FLAG_TRANSLUCENT;
    }

    float view_depth = gl_FragCoord.w > 0.0 ? 1.0 / gl_FragCoord.w : 1.0;

    out_albedo = muon_encode_translucent_albedo(material);
    out_normal = muon_encode_translucent_normal(material);
    out_surface = muon_encode_translucent_surface(material, view_depth);
}
