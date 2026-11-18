/*
================================================================================

  Muon Shaders - program/composite3.fsh
  Version 0.1.2

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Temporal anti-aliasing resolve.

  The previous frame's history is validated against the current 3x3 colour
  distribution before it is blended, which is what keeps fast-moving entities
  from leaving trails: a stale sample that no longer exists anywhere in the
  neighbourhood is clipped away instead of averaged in.

  This pass reads the history and writes the scene, and never writes colortex5.
  The history is written by composite4. That separation is deliberate: a pass
  that reads and writes one buffer needs a buffer flip, and a flip is loader
  behaviour that cannot be verified at build time - a broken flip looks exactly
  like a broken temporal filter.

  Targets:
      15  resolved scene

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/taa.glsl"

in vec2 texcoord;

layout(location = 0) out vec4 out_scene;

/* RENDERTARGETS: 15 */

void main() {
    MUON_FRAME_INIT();

    vec2 uv = texcoord;
    vec3 current = texture(colortex0, uv).rgb;

    vec2 velocity = texture(colortex8, uv).rg;
    vec2 history_uv = uv - velocity - muon_taa_jitter_delta_uv();

    bool history_valid = history_uv.x >= 0.0 && history_uv.x <= 1.0
        && history_uv.y >= 0.0 && history_uv.y <= 1.0
        && muon_frame_counter() > 2.0;

    vec3 history = history_valid ? texture(colortex5, history_uv).rgb : current;

    vec2 texel = muon_inv_viewport();
    vec3 sum = vec3(0.0);
    vec3 sum_squares = vec3(0.0);

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec3 tap = texture(colortex0, uv + vec2(float(x), float(y)) * texel).rgb;
            sum += tap;
            sum_squares += tap * tap;
        }
    }

    vec3 mean = sum / 9.0;
    vec3 variance = max(sum_squares / 9.0 - mean * mean, vec3(0.0));
    vec3 deviation = sqrt(variance);

    vec3 resolved = muon_resolve_taa(current, history, mean, deviation, velocity, history_valid);
    resolved = muon_clamp_hdr(resolved, 512.0);

    out_scene = vec4(resolved, 1.0);
}