/*
================================================================================

  Muon Shaders - lib/common/taa.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Temporal anti-aliasing.

  The velocity buffer is produced by reprojecting the shaded surface through
  the previous frame's matrices, so camera translation and rotation are both
  represented. Sub-pixel jitter is applied in every geometry vertex shader
  (muon_taa_jitter_offset) and resolved here.

  Fast-moving geometry has no analytic velocity in the Iris API - a pack only
  receives the previous *camera* transform, not previous model transforms. That
  class of error is handled where it actually shows up: the history is clipped
  to the local colour distribution in YCoCg space before it is blended, which
  rejects stale samples instead of smearing them. That is what keeps a sprinting
  mob from leaving a trail.

================================================================================
*/

#ifndef MUON_COMMON_TAA_GLSL
#define MUON_COMMON_TAA_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/color.glsl"
#include "/lib/common/random.glsl"

// -----------------------------------------------------------------------------
//  Jitter
// -----------------------------------------------------------------------------

/*
 * Sub-pixel offset in NDC units for the current frame. The R2 sequence spreads
 * consecutive frames across the pixel footprint evenly, so a static camera
 * converges within a handful of frames.
 */
vec2 muon_taa_jitter_ndc() {
    vec2 sequence = muon_r2_sequence(uint(muonFrame.time.x));
    return (sequence - 0.5) * 2.0 * muonFrame.viewport.zw;
}

vec2 muon_taa_jitter_pixels() {
    return muon_taa_jitter_ndc() * muonFrame.viewport.xy * 0.5;
}

// -----------------------------------------------------------------------------
//  Velocity
// -----------------------------------------------------------------------------

/*
 * Screen-space motion of the surface at `uv` between the previous frame and
 * this one, expressed in UV units. Positive values mean the surface moved
 * towards increasing UV this frame.
 */
vec2 muon_velocity(vec2 uv, vec3 view_pos) {
    vec3 world_pos = muon_view_to_world_pos(view_pos);

    vec4 clip_current = muonFrame.projection * vec4(view_pos, 1.0);
    vec4 clip_previous = muonFrame.previousProjection * (muonFrame.previousView * vec4(world_pos, 1.0));

    if (abs(clip_current.w) < 1.0e-5 || abs(clip_previous.w) < 1.0e-5) {
        return vec2(0.0);
    }

    vec2 ndc_current = clip_current.xy / clip_current.w;
    vec2 ndc_previous = clip_previous.xy / clip_previous.w;

    vec2 velocity = (ndc_current - ndc_previous) * 0.5;

    /* A surface that reprojects outside the screen has no history to use. */
    vec2 previous_uv = uv - velocity;
    if (previous_uv.x < 0.0 || previous_uv.x > 1.0 || previous_uv.y < 0.0 || previous_uv.y > 1.0) {
        return vec2(0.0);
    }

    return velocity;
}

// -----------------------------------------------------------------------------
//  Colour space used for neighbourhood clipping
// -----------------------------------------------------------------------------

vec3 muon_rgb_to_ycocg(vec3 c) {
    return vec3(
        dot(c, vec3(0.25, 0.5, 0.25)),
        dot(c, vec3(0.5, 0.0, -0.5)),
        dot(c, vec3(-0.25, 0.5, -0.25))
    );
}

vec3 muon_ycocg_to_rgb(vec3 c) {
    float y = c.x;
    float co = c.y;
    float cg = c.z;
    return vec3(y + co - cg, y + cg, y - co - cg);
}

// -----------------------------------------------------------------------------
//  History validation
// -----------------------------------------------------------------------------

/*
 * Variance clipping (Salvi 2016): the history is clipped to a box derived from
 * the mean and standard deviation of the current 3x3 neighbourhood. Compared
 * with a plain min/max box this keeps more detail while still rejecting ghost
 * samples from geometry that was not in the neighbourhood a frame ago.
 */
vec3 muon_clip_history(vec3 history, vec3 neighbourhood_mean, vec3 neighbourhood_deviation) {
    vec3 ycocg = muon_rgb_to_ycocg(history);
    vec3 mean = muon_rgb_to_ycocg(neighbourhood_mean);
    vec3 deviation = muon_rgb_to_ycocg(neighbourhood_deviation);

    vec3 extent = deviation * (1.25 * TAA_CLIPPING);
    vec3 low = mean - extent;
    vec3 high = mean + extent;

    vec3 clipped = clamp(ycocg, low, high);
    return muon_ycocg_to_rgb(clipped);
}

/* Scalar variant for the luminance used by the temporal blend weight. */
float muon_temporal_blend_weight(vec2 velocity, float material_change) {
    float speed = length(velocity * muonFrame.viewport.xy);
    /* Faster motion means less history, which trades a little noise for
       sharply reduced smearing. */
    float speed_weight = muon_saturate(1.0 - speed * 0.06);
    float base = muon_saturate(TAA_STRENGTH);
    return muon_saturate(base * speed_weight * (1.0 - material_change));
}

// -----------------------------------------------------------------------------
//  Resolve
// -----------------------------------------------------------------------------

vec3 muon_resolve_taa(
    vec3 current,
    vec3 history,
    vec3 neighbourhood_mean,
    vec3 neighbourhood_deviation,
    vec2 velocity,
    bool history_valid
) {
#if !defined TAA
    return current;
#else
    if (!history_valid || any(isnan(history)) || any(isinf(history))) {
        return current;
    }

    vec3 clipped_history = muon_clip_history(history, neighbourhood_mean, neighbourhood_deviation);
    float weight = muon_temporal_blend_weight(velocity, 0.0);

    /* A long history is worth less when the sample had to be clipped hard. */
    float clipping_delta = length(muon_rgb_to_ycocg(clipped_history) - muon_rgb_to_ycocg(history));
    weight *= muon_saturate(1.0 - clipping_delta * 4.0);

    return mix(current, clipped_history, weight);
#endif
}

#endif // MUON_COMMON_TAA_GLSL
