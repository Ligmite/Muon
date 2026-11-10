/*
================================================================================

  Muon Shaders
  program/translucent_vsh.glsl - shared translucent vertex stage

  Used by gbuffers_water, gbuffers_hand_water, gbuffers_entities_translucent,
  gbuffers_block_translucent, gbuffers_particles_translucent and
  gbuffers_weather.

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/materials.glsl"

out vec2 uv;
out vec2 light_levels;
out vec3 scene_pos;
out vec3 normal;
out vec3 tint;
out float surface_depth;

flat out uint material_id;

attribute vec3 mc_Entity;
attribute vec2 mc_midTexCoord;

// Lightweight copy of the wave height used by lib/water.glsl so that the
// vertex stage does not need to pull in the whole shading library.
float vertex_wave_height(vec3 world_pos) {
#if defined WATER_WAVES
    vec2 p = world_pos.xz;
    float height = 0.0;

    float amplitude = 0.06 * WATER_WAVE_STRENGTH;
    float frequency = 0.55 * WATER_WAVE_FREQUENCY;
    float angle = 0.0;

    for (int i = 0; i < WATER_WAVE_ITERATIONS; i++) {
        angle += 2.39996323;
        vec2 dir = vec2(cos(angle), sin(angle));
        float k = frequency * tau;
        float phase = dot(dir, p) * k + frameTimeCounter * 0.55 * WATER_WAVE_SPEED * (1.0 + float(i) * 0.35);
        height += amplitude * sin(phase);
        amplitude *= WATER_WAVE_PERSISTENCE;
        frequency *= WATER_WAVE_LACUNARITY;
    }

    return height * 0.5;
#else
    return 0.0;
#endif
}

void main() {
    uv = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    light_levels = clamp01(gl_MultiTexCoord1.xy * rcp(240.0));
    tint = gl_Color.rgb;

    material_id = 0u;

#if defined PROGRAM_WATER
    material_id = MAT_WATER;
#elif defined PROGRAM_TERRAIN
    material_id = material_from_block_id(int(mc_Entity.x));
#endif

    vec3 view_normal = mat3(gl_ModelViewMatrix) * gl_Normal;
    normal = normalize(mat3(gbufferModelViewInverse) * view_normal);

    vec3 pos_view = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 pos_scene = view_to_scene_space(pos_view);

#if defined WATER_DISPLACEMENT && defined PROGRAM_WATER
    // Only the top face of the water body is displaced
    if (gl_Normal.y > 0.5) {
        vec3 world_pos = pos_scene + cameraPosition;
        float displacement = vertex_wave_height(world_pos);
        pos_scene.y += displacement;
    }
#endif

    scene_pos = pos_scene;
    pos_view = scene_to_view_space(pos_scene);

    vec4 clip_pos = gl_ProjectionMatrix * vec4(pos_view, 1.0);

#if defined TAA
    vec2 jitter = vec2(halton(frameCounter + 1, 2), halton(frameCounter + 1, 3));
    clip_pos.xy += (jitter - 0.5) * 2.0 / vec2(viewWidth, viewHeight) * clip_pos.w;
#endif

    gl_Position = clip_pos;

    // Screen-space depth of this surface, used to reconstruct its position in
    // the composite pass (translucents do not write to the depth buffer).
    surface_depth = clip_pos.z / max(clip_pos.w, 1e-5) * 0.5 + 0.5;
}
