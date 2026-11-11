/*
================================================================================

  Muon Shaders - program/dh_water.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Distant Horizons water fragment stage. Writes the translucent targets with the
  water material so that the deferred water model handles extinction, refraction
  and reflection at LOD distances too.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_write.glsl"
#include "/lib/common/water.glsl"

in vec2 texcoord;
in vec2 lmcoord;
in vec4 tint;
in vec3 view_pos;
in vec3 view_normal;
flat in int material_id;

layout(location = 0) out vec4 out_albedo;
layout(location = 1) out vec4 out_normal;
layout(location = 2) out vec4 out_surface;

/* RENDERTARGETS: 9,10,11 */

void main() {
    MUON_FRAME_INIT();

#if !defined DH_WATER
    discard;
#endif

    MuonMaterial material = muon_material_default();
    material.id = MUON_MAT_WATER;
    material.albedo = vec3(0.06, 0.20, 0.28);
    material.f0 = vec3(MUON_WATER_F0);
    material.smoothness = 0.95;
    material.normal = normalize(view_normal);
    material.alpha = 0.85;
    material.flag = MUON_FLAG_WATER;

    out_albedo = muon_encode_translucent_albedo(material);
    out_normal = muon_encode_translucent_normal(material);
    out_surface = muon_encode_translucent_surface(material, -view_pos.z);
}
