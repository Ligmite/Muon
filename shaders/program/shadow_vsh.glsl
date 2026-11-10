/*
================================================================================

  Muon Shaders
  program/shadow_vsh.glsl - shadow map vertex stage

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/materials.glsl"
#include "/lib/shadow.glsl"
#include "/lib/encoding.glsl"

out vec2 uv;

attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

void main() {
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    vec3 pos_view = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 pos_scene = (shadowModelViewInverse * vec4(pos_view, 1.0)).xyz;

#if defined WAVING_PLANTS || defined WAVING_LEAVES
    uint material_id = material_from_block_id(int(mc_Entity.x));
    bool is_top_vertex = uv.y < mc_midTexCoord.y;
    vec3 world_pos = pos_scene + cameraPosition;
    pos_scene = apply_wave(pos_scene, world_pos, is_top_vertex ? 1.0 : 0.0, 1.0, material_id);
#endif

    pos_view = (shadowModelView * vec4(pos_scene, 1.0)).xyz;

    vec4 clip_pos = gl_ProjectionMatrix * vec4(pos_view, 1.0);

    // Distort towards the camera so the shadow map resolution is spent where it
    // matters. The same warp is applied when sampling.
    vec2 ndc = clip_pos.xy / max(clip_pos.w, 1e-5);
    clip_pos.xy = (distort_shadow(ndc) * 2.0 - 1.0) * clip_pos.w;

    gl_Position = clip_pos;
}
