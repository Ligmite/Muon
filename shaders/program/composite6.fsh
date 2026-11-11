/*
================================================================================

  Muon Shaders - program/composite6.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Bloom upsample.

  Reads the defocused scene, adds the bloom pyramid sampled at five levels, and
  writes the result to the scene target that the final pass reads.

  Target:
      0  scene with bloom

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/bloom.glsl"


in vec2 texcoord;

layout(location = 0) out vec4 out_scene;

/* RENDERTARGETS: 0 */

void main() {
    MUON_FRAME_INIT();

    vec3 color = texture(colortex15, texcoord).rgb;

#if defined BLOOM
    vec3 bloom = muon_bloom_upsample(texcoord);
    float exposure = max(texture(colortex12, vec2(0.5)).r, 0.01);
    color = muon_apply_bloom(color, bloom, exposure);
#endif

    out_scene = vec4(color, 1.0);
}
