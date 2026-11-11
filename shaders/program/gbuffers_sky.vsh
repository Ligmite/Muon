/*
================================================================================

  Muon Shaders - program/gbuffers_sky.vsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  The vanilla sky, sun, moon, stars and cloud renderers are suppressed.

  Muon draws its own atmosphere in the deferred stage because it needs the same
  scattering model for the sky, the fog and the ambient light. Discarding here
  leaves the depth buffer untouched at the far plane, which is exactly the
  signal the deferred stage uses to identify sky pixels.

================================================================================
*/

#include "/lib/common/global.glsl"

void main() {
    MUON_FRAME_INIT();
    gl_Position = ftransform();
}
