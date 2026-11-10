/*
================================================================================

  Muon Shaders
  lib/gbuffer.glsl - reading the G-buffer back

  Declares the G-buffer samplers once and provides load_surface(), the single
  entry point every deferred pass uses to reconstruct a surface.

================================================================================
*/

#if !defined MUON_GBUFFER
#define MUON_GBUFFER

#include "/lib/lighting.glsl"
#include "/lib/encoding.glsl"
#include "/lib/materials.glsl"

uniform sampler2D colortex1;  // albedo, material id
uniform sampler2D colortex2;  // normal, roughness, metalness
uniform sampler2D colortex3;  // emission, sss, ao, f0
uniform sampler2D colortex14; // light levels, porosity, flags

// Reconstructs a SurfaceData from the G-buffer.
// `depth` returns the raw scene depth used.
SurfaceData load_surface(vec2 uv, out float depth) {
    depth = texture(depthtex1, uv).r;

#ifdef DISTANT_HORIZONS
    if (depth >= 1.0) {
        float dh_depth = texture(dhDepthTex0, uv).r;
        if (dh_depth < 1.0) depth = dh_depth;
    }
#endif

    vec4 g0 = texture(colortex1, uv);
    vec4 g1 = texture(colortex2, uv);
    vec4 g2 = texture(colortex3, uv);
    vec4 g3 = texture(colortex14, uv);

    SurfaceData surface;

    uint material_id;
    unpack_gbuffer_0(g0, surface.albedo, material_id);

    float roughness;
    float metalness;
    unpack_gbuffer_1(g1, surface.normal, roughness, metalness);

    float f0;
    unpack_gbuffer_2(g2, surface.emission, surface.sss, surface.ao, f0);

    surface.roughness = roughness;
    surface.metalness = metalness;
    surface.f0 = f0;
    surface.material = material_id;

    surface.skylight = g3.r;
    surface.blocklight = g3.g;

    vec3 scene_pos = screen_to_scene_space(vec3(uv, depth));
    surface.scene_pos = scene_pos;
    surface.view_dir = normalize(-scene_pos);

    surface.shadow = 1.0;

    return surface;
}

vec3 gbuffer_normal(vec2 uv) {
    return decode_normal_octa(texture(colortex2, uv).xy);
}

#endif // MUON_GBUFFER
