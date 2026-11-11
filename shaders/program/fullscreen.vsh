/*
================================================================================

  Muon Shaders - program/fullscreen.vsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Vertex stage shared by every deferred, composite and final pass.

  Iris supplies a unit quad in gl_Vertex with its texture coordinates in
  gl_MultiTexCoord0, so the vertex stage only has to emit screen-space
  positions. The UV is passed through instead of reconstructed in the fragment
  stage so that half-resolution passes stay correctly parameterised.

================================================================================
*/

#include "/lib/common/global.glsl"

out vec2 texcoord;

void main() {
    texcoord = gl_MultiTexCoord0.xy;
    gl_Position = vec4(gl_Vertex.xy * 2.0 - 1.0, 0.0, 1.0);
}
