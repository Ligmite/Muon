/*
================================================================================

  Muon Shaders
  lib/space.glsl - coordinate spaces

  Terminology (same as Iris/OptiFine):
    screen space : [0, 1] uv + depth in [0, 1]
    view space   : camera at origin, -Z forward, axes follow the camera
    scene space  : camera at origin, world-oriented axes (sun direction is fixed)
    world space  : scene space + cameraPosition

  All of these are pure functions so they can be translated to WGSL verbatim.

================================================================================
*/

#if !defined MUON_SPACE
#define MUON_SPACE

#include "/lib/uniforms.glsl"

// Remaps vanilla hand depth into the normal projection depth range.
// Returns true when the fragment belongs to the hand.
bool fix_hand_depth(inout float depth) {
    if (depth < hand_depth) {
        depth = (depth * 2.0 - 1.0) / hand_depth * 0.5 + 0.5;
        return true;
    }
    return false;
}

// -------------------------
//   Projection transforms
// -------------------------

vec3 screen_to_view_space(mat4 projection_inverse, vec3 screen_pos, bool hand) {
    float depth = screen_pos.z;
    if (hand) fix_hand_depth(depth);
    vec3 ndc = vec3(screen_pos.xy * 2.0 - 1.0, depth * 2.0 - 1.0);
    vec4 view = projection_inverse * vec4(ndc, 1.0);
    return view.xyz / view.w;
}

vec3 screen_to_view_space(mat4 projection_inverse, vec3 screen_pos) {
    return screen_to_view_space(projection_inverse, screen_pos, false);
}

vec3 view_to_screen_space(mat4 projection, vec3 view_pos) {
    vec4 clip = projection * vec4(view_pos, 1.0);
    return clip.xyz / clip.w * 0.5 + 0.5;
}

vec3 view_to_ndc(mat4 projection, vec3 view_pos) {
    vec4 clip = projection * vec4(view_pos, 1.0);
    return clip.xyz / clip.w;
}

// -------------------------
//   Camera-relative spaces
// -------------------------

vec3 view_to_scene_space(vec3 view_pos) {
    return (gbufferModelViewInverse * vec4(view_pos, 1.0)).xyz;
}

vec3 scene_to_view_space(vec3 scene_pos) {
    return (gbufferModelView * vec4(scene_pos, 1.0)).xyz;
}

vec3 scene_to_screen_space(vec3 scene_pos) {
    return view_to_screen_space(gbufferProjection, scene_to_view_space(scene_pos));
}

vec3 screen_to_scene_space(vec3 screen_pos) {
    return view_to_scene_space(screen_to_view_space(gbufferProjectionInverse, screen_pos));
}

vec3 world_to_scene_space(vec3 world_pos) {
    return world_pos - cameraPosition;
}

vec3 scene_to_world_space(vec3 scene_pos) {
    return scene_pos + cameraPosition;
}

// -------------------------
//   Depth helpers
// -------------------------

// Linear distance from the camera for a given screen depth, in blocks.
float depth_to_distance(float depth) {
    return 2.0 * near * far / (far + near - (depth * 2.0 - 1.0) * (far - near));
}

float distance_to_depth(float distance) {
    float z = far + near - 2.0 * near * far / max(distance, near);
    return z / (far - near) * 0.5 + 0.5;
}

vec3 reconstruct_view_position(vec2 uv, float depth) {
    return screen_to_view_space(gbufferProjectionInverse, vec3(uv, depth));
}

// -------------------------
//   Motion vectors
// -------------------------

// Screen-space motion of a world-space point from the previous frame to this
// frame. Returns (delta_uv, valid).
vec3 motion_vector(vec3 scene_pos) {
    vec3 world_pos = scene_to_world_space(scene_pos);
    vec3 prev_scene_pos = world_pos - previousCameraPosition;

    vec3 prev_view_pos = (gbufferPreviousModelView * vec4(prev_scene_pos, 1.0)).xyz;
    vec4 prev_clip = gbufferPreviousProjection * vec4(prev_view_pos, 1.0);

    if (prev_clip.w <= 0.0) return vec3(0.0);

    vec3 prev_screen = prev_clip.xyz / prev_clip.w * 0.5 + 0.5;
    vec3 curr_screen = scene_to_screen_space(scene_pos);

    return vec3(curr_screen.xy - prev_screen.xy, 1.0);
}

vec2 reproject_uv(vec2 uv, float depth) {
    vec3 scene_pos = screen_to_scene_space(vec3(uv, depth));
    return uv - motion_vector(scene_pos).xy;
}

// -------------------------
//   Sky reconstruction
// -------------------------

// Cubemap-style direction used for sky LUT-free evaluation, kept for shaders
// that need a stable "up" vector in scene space.
vec3 scene_up() {
    return normalize((gbufferModelViewInverse * vec4(upPosition, 0.0)).xyz);
}

// Light direction in scene space (points from the surface towards the light)
vec3 sun_dir_scene() {
    return normalize((gbufferModelViewInverse * vec4(sunPosition, 0.0)).xyz);
}

vec3 moon_dir_scene() {
    return normalize((gbufferModelViewInverse * vec4(moonPosition, 0.0)).xyz);
}

// The direction of the light that currently casts shadows (sun or moon)
vec3 shadow_light_dir_scene() {
    return normalize((gbufferModelViewInverse * vec4(shadowLightPosition, 0.0)).xyz);
}

#endif // MUON_SPACE
