/*
================================================================================

  Muon Shaders - program/gbuffers_sky.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Discards every vanilla sky fragment. See gbuffers_sky.vsh for the rationale.

================================================================================
*/

#include "/lib/common/global.glsl"

void main() {
    MUON_FRAME_INIT();
    discard;
}
