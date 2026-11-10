/*
================================================================================

  Muon Shaders
  program/gbuffer_vsh.glsl - shared opaque G-buffer vertex stage

  Included by gbuffers_terrain, gbuffers_entities, gbuffers_hand,
  gbuffers_block, gbuffers_basic, gbuffers_textured, ...

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/materials.glsl"

// -----------
//   Outputs
// -----------

out vec2 uv;
out vec2 uv_local;
out vec2 light_levels;
out vec3 scene_pos;
out vec3 view_pos_out;
out vec3 normal;
out vec3 tint;
out float vanilla_ao;

flat out uint material_id;
flat out mat3 tbn;

// --------------
//   Attributes
// --------------

attribute vec4 at_tangent;
attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

// --------------
//   Jitter
// --------------

vec2 taa_jitter() {
#if defined TAA
    // Halton(2,3) sub-pixel jitter, one sample per frame
    vec2 jitter = vec2(halton(frameCounter + 1, 2), halton(frameCounter + 1, 3));
    return (jitter - 0.5) * 2.0 / vec2(viewWidth, viewHeight);
#else
    return vec2(0.0);
#endif
}

void main() {
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    uv_local = sign(uv - mc_midTexCoord) * 0.5 + 0.5;

    light_levels = clamp01(gl_MultiTexCoord1.xy * rcp(240.0));

    tint = gl_Color.rgb;

    // Scene-space normal
    vec3 view_normal = mat3(gl_ModelViewMatrix) * gl_Normal;
    normal = normalize(mat3(gbufferModelViewInverse) * view_normal);

    // Tangent frame for normal mapping
    vec3 tangent = mat3(gl_ModelViewMatrix) * at_tangent.xyz;
    tangent = normalize(mat3(gbufferModelViewInverse) * tangent);
    vec3 bitangent = cross(normal, tangent) * at_tangent.w;
    tbn = mat3(tangent, bitangent, normal);

    // Material id
    material_id = 0u;

#if defined PROGRAM_TERRAIN
    material_id = material_from_block_id(int(mc_Entity.x));
#elif defined PROGRAM_HAND
    material_id = MAT_GENERIC;
#elif defined PROGRAM_BLOCK
    material_id = MAT_GENERIC;
#endif

    vanilla_ao = 1.0;

#if defined PROGRAM_TERRAIN
    vanilla_ao = gl_Color.a < 0.1 ? 1.0 : gl_Color.a;
#endif

    // View-space position from the fixed function pipeline
    vec3 pos_view = (gl_ModelViewMatrix * gl_Vertex).xyz;

    // Scene space (camera relative, world oriented)
    vec3 pos_scene = view_to_scene_space(pos_view);

#if defined WAVING_PLANTS || defined WAVING_LEAVES
    bool is_top_vertex = uv.y < mc_midTexCoord.y;
    vec3 world_pos = pos_scene + cameraPosition;
    pos_scene = apply_wave(pos_scene, world_pos, is_top_vertex ? 1.0 : 0.0, light_levels.y, material_id);
#endif

    scene_pos = pos_scene;
    pos_view = scene_to_view_space(pos_scene);
    view_pos_out = pos_view;

    vec4 clip_pos = gl_ProjectionMatrix * vec4(pos_view, 1.0);

#if defined TAA
    clip_pos.xy += taa_jitter() * clip_pos.w;
#endif

    gl_Position = clip_pos;
}
