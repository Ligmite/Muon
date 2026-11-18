/*
================================================================================

  Muon Shaders - program/composite.fsh
  Version 0.1.2

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Luminance reduction and eye adaptation.

  Runs at 64x64. Each texel averages one tile of the HDR image, the frame-wide
  average is reconstructed from those texels, and the adapted exposure is eased
  towards the target with separate time constants for opening up and stopping
  down - eyes adapt far more slowly to brightness than to darkness.

  The previous exposure is carried in colortex8's alpha channel, which
  composite2 writes at the end of the frame. Keeping the state there means this
  pass never reads the buffer it writes, so the chain needs no buffer flips.

  Target:
      12  exposure.r, average luminance.g

================================================================================
*/

#include "/lib/common/global.glsl"


in vec2 texcoord;

layout(location = 0) out vec4 out_exposure;

/* RENDERTARGETS: 12 */

const float MUON_EXPOSURE_KEY = 0.16;
const float MUON_ADAPT_OPEN_TAU = 0.9;
const float MUON_ADAPT_CLOSE_TAU = 2.4;

/* Must match `size.buffer.colortex12` in shaders.properties. Each texel of this
   target owns one tile of the screen. */
const float MUON_EXPOSURE_RESOLUTION = 64.0;

float muon_tile_luminance(vec2 uv) {
    /* The 4x4 taps are spread across the texel's *whole* screen tile. Sampling
       a small patch around the centre instead would estimate the exposure from
       whatever happened to be under the middle of the screen. */
    vec2 tile = vec2(1.0 / MUON_EXPOSURE_RESOLUTION);
    vec2 base = uv - tile * 0.5;

    float total = 0.0;
    float weight_sum = 0.0;

    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            vec2 offset = (vec2(float(x), float(y)) + 0.5) * tile * 0.25;
            vec2 sample_uv = clamp(base + offset, vec2(0.0), vec2(1.0));
            vec3 color = texture(colortex15, sample_uv).rgb;
            float luminance = muon_luminance(color);
            if (!muon_is_finite(luminance)) {
                luminance = 1.0e-4;
            }
            /* Centre-weighted so that the exposure follows what the player is
               looking at instead of being dragged around by a bright sky. The
               floor keeps the edges of the frame from being ignored entirely. */
            vec2 centred = (sample_uv - vec2(0.5)) * vec2(1.6, 1.0);
            float weight = exp(-dot(centred, centred) * 2.5) + 0.15;

            /* The ceiling is deliberately low: the sun disc and its Mie glow
               reach radiance in the hundreds, and if the meter sees them it
               exposes the whole frame for the sun. */
            total += weight * clamp(log2(max(luminance, 1.0e-4)), -14.0, 1.0);
            weight_sum += weight;
        }
    }
    return total / max(weight_sum, 1.0e-4);
}

void main() {
    MUON_FRAME_INIT();

    float log_luminance = muon_tile_luminance(texcoord);
    float average_luminance = clamp(exp2(log_luminance), 1.0e-4, 256.0);

    /* --- previous state ------------------------------------------------ */

    float previous_exposure = texture(colortex8, vec2(0.5)).a;
    bool valid = previous_exposure > 0.0 && muon_is_finite(previous_exposure);

    float target = 1.0 / max(average_luminance / MUON_EXPOSURE_KEY, 1.0e-4);

    /* Opening up (target above the current exposure) is fast; stopping down is
       slow, which is how a real eye behaves walking out of a cave. */
    float tau = target > previous_exposure ? MUON_ADAPT_OPEN_TAU : MUON_ADAPT_CLOSE_TAU;
    float rate = muon_saturate(1.0 - exp(-muon_frame_time() / max(tau * MUON_EXPOSURE_SPEED, 0.02)));

    float adapted = valid ? mix(previous_exposure, target, rate) : target;

    adapted = clamp(adapted, exp2(EXPOSURE_MIN), exp2(EXPOSURE_MAX));
    adapted *= exp2(EXPOSURE_BIAS);

    out_exposure = vec4(adapted, average_luminance, 0.0, 1.0);
}
