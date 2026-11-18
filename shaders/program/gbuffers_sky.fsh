/*
================================================================================

  Muon Shaders - program/gbuffers_sky.fsh
  Version 0.1.2

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  The vanilla sky, sun, moon, stars and cloud renderers are suppressed; Muon
  draws its own atmosphere in the deferred stage.

  This stage does not simply discard. It writes zeros to the translucent targets,
  which makes them a reliable per-frame record of "is there water or glass at
  this pixel". The sky pass covers every pixel that no geometry does, so between
  this, the opaque pass (which also writes zero) and the translucent pass (which
  writes its own material) the marker is always current - and water detection
  needs no depth test at all. That matters because Minecraft's translucent layer
  does not write depth, and over deep ocean the opaque depth is the far plane,
  which made an earlier depth-based test reject every water pixel on a coast.

  Targets:
      9,10,11  cleared

================================================================================
*/

#include "/lib/common/global.glsl"

layout(location = 0) out vec4 out_translucent_albedo;
layout(location = 1) out vec4 out_translucent_normal;
layout(location = 2) out vec4 out_translucent_surface;

/* RENDERTARGETS: 9,10,11 */

void main() {
    MUON_FRAME_INIT();

    out_translucent_albedo = vec4(0.0);
    out_translucent_normal = vec4(0.0);
    out_translucent_surface = vec4(0.0);
}