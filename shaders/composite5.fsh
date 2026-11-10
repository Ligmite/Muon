#version 400 compatibility
/*
================================================================================

  Muon Shaders
  composite5.fsh - depth of field and motion blur

  Writes:
    colortex11 blurred image
    colortex5  TAA history (the sharp frame, so the history never contains blur)

  RENDERTARGETS: 11,5

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"
#include "/lib/color.glsl"
#include "/lib/post.glsl"

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_history;

/* RENDERTARGETS: 11,5 */

uniform sampler2D colortex0; // sharp TAA output

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    float dither = interleaved_gradient_noise(gl_FragCoord.xy, float(frameCounter));

    vec3 color = texture(colortex0, uv).rgb;

    // Focus distance: the world-space distance straight ahead at the centre of
    // the screen, shifted by the user's focus offset.
    float center_depth = texture(depthtex1, vec2(0.5)).r;
    float focus_distance = depth_to_distance(center_depth) + DOF_FOCUS;

    color = depth_of_field(colortex0, depthtex1, uv, focus_distance, DOF_RANGE, dither);

    // Camera motion blur
    float depth = texture(depthtex1, uv).r;
    if (depth < 1.0) {
        vec3 scene_pos = screen_to_scene_space(vec3(uv, depth));
        vec2 velocity = motion_vector(scene_pos).xy;

        // Skip blur for things that barely moved
        if (dot(velocity, velocity) > 1e-8) {
            color = motion_blur(colortex0, uv, velocity);
        }
    }

    out_color = vec4(sanitize_color(color), 1.0);
    out_history = vec4(texture(colortex0, uv).rgb, 1.0);
}
