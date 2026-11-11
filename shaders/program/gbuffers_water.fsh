/*
================================================================================

  Muon Shaders - program/gbuffers_water.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Translucent g-buffer writer.

  Writes a separate set of targets (9/10/11) and never touches the opaque
  g-buffer or the scene colour. That invariant lets the deferred stage light the
  surface *behind* water, which is what the water pass then refracts.

  Targets:
      9   albedo.rgb, F0.a
      10  view normal.xyz, smoothness.a
      11  material.r, opacity.g, emission.b, linear depth.a

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/texture.glsl"
#include "/lib/common/gbuffer_write.glsl"
#include "/lib/common/wetness.glsl"
#include "/lib/common/water.glsl"


in vec2 texcoord;
in vec2 lmcoord;
in vec4 tint;
in vec3 view_pos;
in vec3 view_normal;
in vec3 world_pos;
flat in int material_id;
flat in float surface_weight;

layout(location = 0) out vec4 out_albedo;
layout(location = 1) out vec4 out_normal;
layout(location = 2) out vec4 out_surface;

/* RENDERTARGETS: 9,10,11 */

void main() {
    MUON_FRAME_INIT();

    vec4 albedo_texel = texture(gtexture, texcoord) * tint;

    if (albedo_texel.a < 0.02) {
        discard;
    }

    vec3 albedo = muon_srgb_to_linear(albedo_texel.rgb);

    MuonMaterial material = muon_material_default();
    material.id = material_id;
    material.albedo = albedo;
    material.alpha = albedo_texel.a;

    float linear_depth = -view_pos.z;
    vec3 normal = normalize(view_normal);

    if (material.id == MUON_MAT_WATER) {
        /* The analytic Gerstner normal replaces the flat quad normal; the
           vertex stage only provides the large-scale displacement. */
        vec3 world_normal = muon_gerstner_normal(world_pos.xz, muon_time_counter(), 1.0);
        vec2 ripple = muon_water_ripple(world_pos.xz, muon_time_counter(), muon_rain_strength());
        world_normal = normalize(world_normal + vec3(ripple.x, 0.0, ripple.y));
        normal = normalize(muon_world_to_view_dir(world_normal));

        material.f0 = vec3(MUON_WATER_F0);
        material.smoothness = 0.98;
        /* The water model in deferred2 produces a complete surface colour -
           refraction, extinction and reflection - so it replaces the pixel
           instead of blending over it. */
        material.alpha = 1.0;

        /* Optional per-block parallax-style distortion of the UV so the surface
           texture follows the waves. */
        vec2 distorted = texcoord + muon_gerstner_normal(world_pos.xz, muon_time_counter() * 1.31, 0.6).xz * 0.035;
        vec4 shifted = texture(gtexture, distorted) * tint;
        material.albedo = mix(muon_srgb_to_linear(shifted.rgb), albedo, 0.35);
    } else {
        MuonSpecular specular = muon_decode_specular(texcoord);
        material.f0 = specular.f0;
        material.smoothness = specular.smoothness;
        material.porosity = specular.porosity;
        material.emission = specular.emission * EMISSION_STRENGTH;

        normal = muon_apply_normal_map(normal, texcoord, view_pos);

        vec3 world_pos_ws = world_pos;
        float up_facing = muon_saturate(normalize(muon_view_to_world_dir(normal)).y * 0.5 + 0.5);
        material = muon_apply_wetting(material, world_pos_ws, up_facing, 0.0);
        normal = material.normal;
    }

    material.normal = normal;
    material.flag = material.id == MUON_MAT_WATER ? MUON_FLAG_WATER : MUON_FLAG_TRANSLUCENT;

    out_albedo = muon_encode_translucent_albedo(material);
    out_normal = muon_encode_translucent_normal(material);
    out_surface = muon_encode_translucent_surface(material, linear_depth);
}
