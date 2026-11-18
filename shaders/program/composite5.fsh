/*
================================================================================

  Muon Shaders - program/composite5.fsh
  Version 0.1.2

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Depth of field.

  The circle of confusion comes from a thin-lens model, with autofocus taking
  the depth at the centre of the screen. The gather is depth-aware, so a sharp
  foreground object cannot bleed a halo over a blurred background.

  When DEPTH_OF_FIELD is off this pass is a straight copy. It is never skipped,
  because it is the only thing that carries colortex15 into colortex0 before the
  bloom chain.

  Targets:
      0  scene (defocused)

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/dof.glsl"

in vec2 texcoord;

layout(location = 0) out vec4 out_scene;

/* RENDERTARGETS: 0 */

void main() {
    MUON_FRAME_INIT();

    vec2 uv = texcoord;

#if defined DEPTH_OF_FIELD
    float depth = texture(depthtex1, uv).r;
    float view_depth = depth >= 1.0 ? muonFrame.depthParams.y : muon_linear_depth(depth);

    float focus = muon_autofocus(uv);
    float coc = muon_coc(view_depth, focus) * muon_dof_hand_mask(view_depth);

    vec3 color = muon_dof_gather(uv, coc, focus);
#else
    vec3 color = texture(colortex15, uv).rgb;
#endif

    out_scene = vec4(color, 1.0);
}