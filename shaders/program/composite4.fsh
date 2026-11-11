/*
================================================================================

  Muon Shaders - program/composite4.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Depth of field.

  The circle of confusion is computed from the thin-lens model with a focus
  distance taken either from the centre of the screen (autofocus) or from the
  user's slider. The gather is depth-aware, so a sharp foreground object cannot
  bleed a halo over a blurred background.

  Target:
      15  defocused scene

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/dof.glsl"

in vec2 texcoord;

layout(location = 0) out vec4 out_scene;

/* RENDERTARGETS: 15 */

void main() {
    MUON_FRAME_INIT();

    vec2 uv = texcoord;

    float depth = texture(depthtex0, uv).r;
    float view_depth = depth >= 1.0 ? muonFrame.depthParams.y : muon_linear_depth(depth);

    float focus = muon_autofocus(uv);
    float coc = muon_coc(view_depth, focus) * muon_dof_hand_mask(view_depth);

    vec3 color = muon_dof_gather(uv, coc, focus);

    out_scene = vec4(color, 1.0);
}
