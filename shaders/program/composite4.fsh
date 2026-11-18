/*
================================================================================

  Muon Shaders - program/composite4.fsh
  Version 0.1.2

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  History copy.

  Copies the resolved image into the temporal history buffer, so that the
  resolve in composite3 can read the history and write the scene without ever
  touching one buffer twice.

  Target:
      5  history for the next frame

================================================================================
*/

#include "/lib/common/global.glsl"

in vec2 texcoord;

layout(location = 0) out vec4 out_history;

/* RENDERTARGETS: 5 */

void main() {
    MUON_FRAME_INIT();
    out_history = vec4(texture(colortex15, texcoord).rgb, 1.0);
}