/*
================================================================================

  Muon Shaders
  program/dh_terrain_vsh.glsl - Distant Horizons terrain vertex stage

  Distant Horizons hands us already-generated LoD geometry. The vertex stage
  snaps positions to the LoD grid and projects with dhProjection, then the
  normal G-buffer stage shades it.

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/materials.glsl"
#include "/lib/encoding.glsl"

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

attribute vec2 mc_midTexCoord;

void main() {
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    uv_local = sign(uv - mc_midTexCoord) * 0.5 + 0.5;

    light_levels = clamp01(gl_MultiTexCoord1.xy * rcp(240.0));

    tint = gl_Color.rgb;

    // Snap to the LoD grid relative to the camera so the terrain does not
    // shimmer as the camera moves
    vec3 camera_offset = fract(cameraPosition);
    vec3 pos = gl_Vertex.xyz;
    pos = floor(pos + camera_offset + 0.5) - camera_offset;

    vec3 view_pos = transform(gl_ModelViewMatrix, pos);

    scene_pos = transform(gbufferModelViewInverse, view_pos);

    vec3 view_normal = mat3(gl_ModelViewMatrix) * gl_Normal;
    normal = normalize(mat3(gbufferModelViewInverse) * view_normal);

    vec3 tangent;
    vec3 bitangent;
    build_basis(normal, tangent, bitangent);
    tbn = mat3(tangent, bitangent, normal);

    material_id = 0u;

#if defined PROGRAM_DH_WATER
    material_id = MAT_WATER;
    normal = vec3(0.0, 1.0, 0.0);
#endif

    vanilla_ao = 1.0;

    view_pos_out = view_pos;

    gl_Position = dhProjection * vec4(view_pos, 1.0);
}
