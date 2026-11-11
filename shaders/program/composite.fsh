/*
================================================================================

  Muon Shaders - program/composite.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Luminance reduction and eye adaptation.

  Runs at 64x64. Each texel averages one tile of the HDR image, the frame-wide
  average is reconstructed from those texels, and the adapted exposure is eased
  towards the target with separate time constants for brightening and darkening
  - eyes adapt far more slowly to brightness than to darkness.

  The adapted value is written back to the same target and read next frame, so
  walking out of a cave takes a few seconds to resolve instead of snapping.

  Target:
      12  exposure.r, average luminance.g

================================================================================
*/

#include "/lib/common/global.glsl"


in vec2 texcoord;

layout(location = 0) out vec4 out_exposure;

/* RENDERTARGETS: 12 */

const float MUON_EXPOSURE_KEY = 0.16;
const float MUON_ADAPT_BRIGHTEN_TAU = 2.4;
const float MUON_ADAPT_DARKEN_TAU = 0.9;

float muon_tile_luminance(vec2 uv) {
    /* 4x4 taps per tile is plenty for a value that is then temporally eased. */
    vec2 tile = muon_inv_viewport() * 16.0;
    float total = 0.0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            vec2 offset = (vec2(float(x), float(y)) + 0.5) * tile * 0.25;
            vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
            vec3 color = texture(colortex0, sample_uv).rgb;
            total += log2(max(muon_luminance(color), 1.0e-4));
        }
    }
    return total / 16.0;
}

void main() {
    MUON_FRAME_INIT();

    float log_luminance = muon_tile_luminance(texcoord);
    float average_luminance = exp2(log_luminance);

    /* --- previous state ------------------------------------------------ */

    vec4 previous = texture(colortex12, vec2(0.5));
    bool valid = previous.r > 0.0 && muon_is_finite(previous.r) && muon_is_finite(previous.g);

    float adapted;
    if (valid) {
        float delta = max(average_luminance - previous.g, 0.0);
        float tau = delta > 0.0 ? MUON_ADAPT_BRIGHTEN_TAU : MUON_ADAPT_DARKEN_TAU;
        float rate = 1.0 - exp(-muon_frame_time() / max(tau * MUON_EXPOSURE_SPEED, 0.02));
        adapted = mix(previous.r, 1.0 / max(average_luminance / MUON_EXPOSURE_KEY, 1.0e-4), muon_saturate(rate));
    } else {
        adapted = 1.0 / max(average_luminance / MUON_EXPOSURE_KEY, 1.0e-4);
    }

    adapted = clamp(adapted, exp2(EXPOSURE_MIN), exp2(EXPOSURE_MAX));
    adapted *= exp2(EXPOSURE_BIAS);

    out_exposure = vec4(adapted, average_luminance, 0.0, 1.0);
}
