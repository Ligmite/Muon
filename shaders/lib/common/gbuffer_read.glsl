/*
================================================================================

  Muon Shaders - lib/common/gbuffer_read.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  G-buffer decoders. Included by the deferred, composite and final stages only.

  The opaque g-buffer is never overwritten by translucent geometry: water and
  other translucent blocks write their own targets (9/10/11). That invariant is
  what lets the deferred stage light the surface *behind* water and the water
  stage refract that already-lit image, instead of the two fighting over one
  set of channels.

================================================================================
*/

#ifndef MUON_COMMON_GBUFFER_READ_GLSL
#define MUON_COMMON_GBUFFER_READ_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_write.glsl"
#include "/lib/uniforms/frame.glsl"


// -----------------------------------------------------------------------------
//  Depth reconstruction
// -----------------------------------------------------------------------------

/*
 * Rebuilds the view-space position of a pixel from the linear depth stored in
 * the surface target. This is the authoritative reconstruction inside the
 * shading stages: it always matches the material that the g-buffer describes,
 * whereas the raw depth buffer may belong to a different layer.
 */
vec3 muon_view_pos_from_linear_depth(vec2 uv, float linear_depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
    vec4 view = muonFrame.projectionInverse * clip;
    vec3 direction = view.xyz / max(view.w, MUON_EPSILON);
    return direction * (linear_depth / max(-direction.z, MUON_EPSILON));
}

vec3 muon_world_pos_from_linear_depth(vec2 uv, float linear_depth) {
    return muon_view_to_world_pos(muon_view_pos_from_linear_depth(uv, linear_depth));
}

float muon_view_distance(vec3 view_pos) {
    return length(view_pos);
}

// -----------------------------------------------------------------------------
//  Opaque material
// -----------------------------------------------------------------------------

MuonMaterial muon_read_opaque_material(vec2 uv) {
    MuonMaterial m = muon_material_default();

    vec4 albedo_texel = texture(colortex1, uv);
    vec4 normal_texel = texture(colortex2, uv);
    vec4 surface_texel = texture(colortex3, uv);
    vec4 lightmap_texel = texture(colortex4, uv);

    m.albedo = max(albedo_texel.rgb, vec3(0.0));
    m.f0 = muon_f0_from_labpbr(albedo_texel.a);
    m.normal = muon_view_to_world_dir(normal_texel.xyz);
    m.smoothness = muon_saturate(normal_texel.a);
    m.roughness = muon_roughness_from_smoothness(m.smoothness);
    m.porosity = muon_saturate(surface_texel.a);
    m.emission = max(surface_texel.b, 0.0);
    m.id = muon_decode_material(surface_texel.g);
    m.blocklight = muon_saturate(lightmap_texel.r);
    m.skylight = muon_saturate(lightmap_texel.g);
    m.ao = muon_saturate(lightmap_texel.b);
    m.flag = lightmap_texel.a;
    m.alpha = 1.0;

    return m;
}

vec3 muon_read_opaque_view_normal(vec2 uv) {
    return normalize(texture(colortex2, uv).xyz);
}

vec3 muon_read_opaque_world_normal(vec2 uv) {
    return normalize(muon_view_to_world_dir(texture(colortex2, uv).xyz));
}

float muon_read_opaque_linear_depth(vec2 uv) {
    return max(texture(colortex3, uv).r, 0.0);
}

/* Raw albedo without any material interpretation - used by screen-space GI. */
vec3 muon_read_opaque_albedo(vec2 uv) {
    return max(texture(colortex1, uv).rgb, vec3(0.0));
}

// -----------------------------------------------------------------------------
//  Translucent material
// -----------------------------------------------------------------------------

MuonMaterial muon_read_translucent_material(vec2 uv) {
    MuonMaterial m = muon_material_default();

    vec4 albedo_texel = texture(colortex9, uv);
    vec4 normal_texel = texture(colortex10, uv);
    vec4 surface_texel = texture(colortex11, uv);

    m.albedo = max(albedo_texel.rgb, vec3(0.0));
    m.f0 = muon_f0_from_labpbr(albedo_texel.a);
    m.normal = muon_view_to_world_dir(normal_texel.xyz);
    m.smoothness = muon_saturate(normal_texel.a);
    m.roughness = muon_roughness_from_smoothness(m.smoothness);
    m.id = muon_decode_material(surface_texel.r);
    m.alpha = muon_saturate(surface_texel.g);
    m.emission = max(surface_texel.b, 0.0);
    m.blocklight = 1.0;
    m.skylight = 1.0;
    m.ao = 1.0;
    m.porosity = 0.0;
    m.flag = muon_is_water(m) ? MUON_FLAG_WATER : MUON_FLAG_TRANSLUCENT;

    return m;
}

float muon_read_translucent_linear_depth(vec2 uv) {
    return max(texture(colortex11, uv).a, 0.0);
}

/*
 * A pixel carries a translucent surface when the translucent depth buffer is
 * nearer than the opaque one. The test is done in metric depth so that it is
 * independent of the projection's precision.
 */
bool muon_pixel_has_translucent(vec2 uv, float opaque_depth, float translucent_depth) {
    if (translucent_depth >= 1.0) {
        return false;
    }
    if (opaque_depth >= 1.0) {
        return translucent_depth < 1.0;
    }
    float opaque_linear = muon_linear_depth(opaque_depth);
    float translucent_linear = muon_linear_depth(translucent_depth);
    return translucent_linear < opaque_linear - 0.002;
}

#endif // MUON_COMMON_GBUFFER_READ_GLSL
