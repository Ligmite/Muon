/*
================================================================================

  Muon Shaders - program/gbuffers_weather.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Writes precipitation into the translucent targets. The streak texture supplies
  coverage, and a small emissive term keeps rain readable in deep shade where a
  purely reflective surface would vanish.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_write.glsl"


in vec2 texcoord;
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

    vec4 texel = texture(gtexture, texcoord) * tint;
    if (texel.a < 0.04) {
        discard;
    }

    MuonMaterial material = muon_material_default();
    material.id = material_id;
    material.albedo = muon_srgb_to_linear(texel.rgb) * 0.85;
    material.alpha = muon_saturate(texel.a * RAIN_OPACITY);
    material.smoothness = 0.9;
    material.f0 = vec3(0.02);
    material.emission = 0.12;
    material.normal = normalize(view_normal);
    material.flag = MUON_FLAG_TRANSLUCENT;

    out_albedo = muon_encode_translucent_albedo(material);
    out_normal = muon_encode_translucent_normal(material);
    out_surface = muon_encode_translucent_surface(material, -view_pos.z);
}
