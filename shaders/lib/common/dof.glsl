/*
================================================================================

  Muon Shaders - lib/common/dof.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Depth of field.

  A thin-lens circle-of-confusion model drives a golden-angle disk gather. The
  gather is depth-aware: a sample is rejected when its own circle of confusion
  is much smaller than the centre's, which is what stops sharp foreground
  objects from bleeding a halo over a blurred background.

  Autofocus picks the focus distance from the centre of the screen with a
  temporal smoothing, so the effect tracks what the player is looking at
  without hunting.

================================================================================
*/

#ifndef MUON_COMMON_DOF_GLSL
#define MUON_COMMON_DOF_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/sampling.glsl"
#include "/lib/common/gbuffer_read.glsl"


// -----------------------------------------------------------------------------
//  Circle of confusion
// -----------------------------------------------------------------------------

/*
 * Signed circle of confusion in pixels. Negative means in front of the focus
 * plane, positive behind it.
 */
float muon_coc(float view_depth, float focus_distance) {
    float aperture = MUON_DOF_APERTURE * 0.0016;
    float coc = (view_depth - focus_distance) / max(view_depth, 0.001);
    coc *= focus_distance * aperture;
    /* A small sensor-scale factor keeps the effect readable at Minecraft's
       field of view. */
    return clamp(coc * muonFrame.viewport.y * 0.55, -24.0, 24.0);
}

/* Auto-focus distance: the depth at the centre of the screen, eased over time. */
float muon_autofocus(vec2 uv) {
#if defined DOF_AUTOFOCUS
    float center_depth = muon_linear_depth(texture(depthtex0, vec2(0.5)).r);
    if (center_depth >= muonFrame.depthParams.y) {
        center_depth = muonFrame.depthParams.y * 0.35;
    }
    return max(center_depth, 0.5);
#else
    return mix(muonFrame.depthParams.x, muonFrame.depthParams.y * 0.5, MUON_DOF_FOCUS);
#endif
}

// -----------------------------------------------------------------------------
//  Gather
// -----------------------------------------------------------------------------

/*
 * Gathers the image with a disk kernel whose radius follows the centre pixel's
 * circle of confusion.
 */
vec3 muon_dof_gather(vec2 uv, float center_coc, float focus_distance) {
#if !defined DEPTH_OF_FIELD
    return texture(colortex0, uv).rgb;
#else
    float radius = abs(center_coc) * MUON_DOF_STRENGTH;
    if (radius < 0.35) {
        return texture(colortex0, uv).rgb;
    }

    vec3 accumulated = texture(colortex0, uv).rgb;
    float weight_sum = 1.0;

    float rotation = muon_interleaved_gradient_noise(gl_FragCoord.xy) * MUON_TAU;

    for (int i = 0; i < MUON_DOF_SAMPLES; i++) {
        vec2 offset = muon_vogel_disk(i, MUON_DOF_SAMPLES, rotation);
        vec2 sample_uv = uv + offset * radius * muon_inv_viewport();

        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            continue;
        }

        float sample_depth = muon_linear_depth(texture(depthtex0, sample_uv).r);
        float sample_coc = muon_coc(sample_depth, focus_distance);

        /* A sample whose own blur is much smaller than the centre's cannot
           contribute: it is in focus and must not smear. */
        float coc_ratio = muon_saturate(abs(sample_coc) / max(abs(center_coc), 0.001));
        float weight = 1.0 - muon_saturate(abs(center_coc) - abs(sample_coc)) * 0.06;
        weight *= mix(0.35, 1.0, coc_ratio);

        accumulated += texture(colortex0, sample_uv).rgb * weight;
        weight_sum += weight;
    }

    return accumulated / max(weight_sum, MUON_EPSILON);
#endif
}

/*
 * Hand-held items sit closer than any world geometry and would otherwise be
 * blurred by their own near depth. When DOF_HAND_BLUR is off the hand is
 * masked out of the effect.
 */
float muon_dof_hand_mask(float view_depth) {
#if defined DOF_HAND_BLUR
    return 1.0;
#else
    return view_depth < 1.2 ? 0.0 : 1.0;
#endif
}

#endif // MUON_COMMON_DOF_GLSL
