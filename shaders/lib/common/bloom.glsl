/*
================================================================================

  Muon Shaders - lib/common/bloom.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Dynamic bloom.

  Muon uses a mip-pyramid bloom: the bright-pass writes the base level of the
  bloom target, the driver generates the mip chain, and the upsample pass
  samples several levels at once. That is two full-screen passes for a bloom
  with a much wider and smoother falloff than a fixed-tap blur, and the cost
  scales with the radius instead of the tap count.

  The threshold uses a soft knee so that a bright surface fades into bloom
  instead of switching on at a hard cutoff, which is what makes the effect look
  like a lens rather than an overlay.

================================================================================
*/

#ifndef MUON_COMMON_BLOOM_GLSL
#define MUON_COMMON_BLOOM_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/uniforms/frame.glsl"
#include "/lib/common/math.glsl"
#include "/lib/uniforms/frame.glsl"
#include "/lib/common/color.glsl"
#include "/lib/uniforms/frame.glsl"


// -----------------------------------------------------------------------------
//  Bright pass
// -----------------------------------------------------------------------------

vec3 muon_bloom_bright_pass(vec3 color) {
    float luminance = muon_luminance(color);
    float threshold = MUON_BLOOM_THRESHOLD;

    /* Soft knee over the decade above the threshold. */
    float knee = threshold * 0.65;
    float soft = muon_saturate(luminance - threshold + knee) / max(2.0 * knee, 1.0e-4);
    soft = soft * soft * knee;

    float contribution = max(luminance - threshold, soft) / max(luminance, 1.0e-4);
    return color * contribution;
}

// -----------------------------------------------------------------------------
//  Upsample
// -----------------------------------------------------------------------------

/*
 * Samples the bloom pyramid at several mip levels and weights them so that the
 * widest level dominates on its own scale. The number of levels is fixed at
 * five: enough for a radius that spans a good fraction of the screen, few
 * enough that the whole pass stays bandwidth bound rather than compute bound.
 */
vec3 muon_bloom_upsample(vec2 uv) {
    vec3 accumulated = vec3(0.0);
    float weight_sum = 0.0;

    /* Wider levels are sampled closer to the centre of the screen so that the
       bloom does not smear past the frame edge. */
    vec2 clamped_uv = clamp(uv, muon_inv_viewport() * 2.0, vec2(1.0) - muon_inv_viewport() * 2.0);

    for (int level = 0; level < 5; level++) {
        float weight = exp(-float(level) * 0.55) * MUON_BLOOM_RADIUS;
        vec3 sample_color = textureLod(colortex6, clamped_uv, float(level)).rgb;
        accumulated += sample_color * weight;
        weight_sum += weight;
    }

    return accumulated / max(weight_sum, MUON_EPSILON);
}

/* Applies the bloom with a strength that follows exposure so that a dark scene
   does not get washed out by a constant additive term. */
vec3 muon_apply_bloom(vec3 color, vec3 bloom, float exposure) {
    float response = 1.0 / (1.0 + exposure * 0.35);
    return color + bloom * (MUON_BLOOM_STRENGTH * response);
}

#endif // MUON_COMMON_BLOOM_GLSL
