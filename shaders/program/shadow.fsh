/*
================================================================================

  Muon Shaders - program/shadow.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Shadow caster fragment stage.

  Depth only: the shadow map's depth attachment is the shadow texel, so this
  stage exists purely to run the alpha test. Cutout geometry that fails the test
  leaves no depth and therefore does not occlude - which is what makes leaves and
  fences cast dappled shadows instead of solid slabs.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"


in vec2 texcoord;

void main() {
    MUON_FRAME_INIT();

    vec4 albedo = texture(gtexture, texcoord);

    /* Cutout geometry is the only thing that needs the test; water and other
       translucent casters are excluded by the pass itself. */
    if (albedo.a < muon_alpha_test_ref()) {
        discard;
    }
}
