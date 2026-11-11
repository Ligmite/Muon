/*
================================================================================

  Muon Shaders - program/composite5.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Bloom bright pass.

  Writes the soft-knee thresholded image into the base level of the bloom
  target. Iris generates the mip chain afterwards, which the next pass then
  samples at several levels at once.

  Target:
      6  bloom pyramid base

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/bloom.glsl"


in vec2 texcoord;

layout(location = 0) out vec4 out_bloom;

/* RENDERTARGETS: 6 */

void main() {
    MUON_FRAME_INIT();

    vec3 color = texture(colortex15, texcoord).rgb;
    out_bloom = vec4(muon_bloom_bright_pass(color), 1.0);
}
