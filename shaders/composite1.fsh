#version 400 compatibility
/*
================================================================================

  Muon Shaders
  composite1.fsh - temporal anti-aliasing

  Resolves the current frame (colortex11) against the history (colortex5), with
  a neighbourhood clamp to remove ghosting and a Catmull-Rom history fetch to
  keep detail.

  RENDERTARGETS: 0

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"
#include "/lib/color.glsl"
#include "/lib/post.glsl"

layout(location = 0) out vec4 out_color;

/* RENDERTARGETS: 0 */

uniform sampler2D colortex5;  // history
uniform sampler2D colortex11; // current frame

vec2 jitter_offset(int frame) {
    vec2 jitter = vec2(halton(frame + 1, 2), halton(frame + 1, 3));
    return (jitter - 0.5) * 2.0 / vec2(viewWidth, viewHeight);
}

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);

    vec3 current = texture(colortex11, uv).rgb;

#ifdef TAA
    // Neighbourhood bounds (3x3) used to clip the history
    vec3 minimum = current;
    vec3 maximum = current;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            if (x == 0 && y == 0) continue;
            vec3 sample_color = texture(colortex11, uv + vec2(float(x), float(y)) * texel).rgb;
            minimum = min(minimum, sample_color);
            maximum = max(maximum, sample_color);
        }
    }

    // Motion vector from depth reprojection
    float depth = texture(depthtex1, uv).r;

    vec2 motion = vec2(0.0);
    float depth_difference = 0.0;

    if (depth < 1.0) {
        vec3 scene_pos = screen_to_scene_space(vec3(uv, depth));
        motion = motion_vector(scene_pos).xy;
    }

    vec2 history_uv = uv - motion;

    // Account for the sub-pixel jitter difference between the two frames
    history_uv += jitter_offset(frameCounter) - jitter_offset(frameCounter - 1);

    float weight = 0.0;

    if (all(greaterThan(history_uv, vec2(0.001))) && all(lessThan(history_uv, vec2(0.999)))) {
        float history_depth = texture(depthtex1, history_uv).r;
        depth_difference = abs(history_depth - depth) / max(depth, 1e-4);

        vec3 history = catmull_rom(colortex5, history_uv, texel);
        history = clip_aabb(history, minimum, maximum, TAA_CLIP_STRENGTH);

        weight = taa_history_weight(length(motion), depth_difference, 10.0);

        current = mix(current, history, clamp(weight, 0.0, 0.95));
    }
#endif

    out_color = vec4(sanitize_color(current), 1.0);
}
