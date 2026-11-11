/*
================================================================================

  Muon Shaders - program/deferred.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Ambient occlusion pass.

  Runs at half resolution and writes the occlusion factor and an octahedrally
  encoded bent normal into the AO target. Half resolution is enough because
  GTAO's horizon search is a low-frequency signal; the deferred stage filters it
  back up with a depth-aware tap pattern.

  Target:
      14  occlusion.r, bent normal.gb

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/gtao.glsl"

in vec2 texcoord;

layout(location = 0) out vec4 out_ao;

/* RENDERTARGETS: 14 */

void main() {
    MUON_FRAME_INIT();

    out_ao = vec4(1.0, 0.0, 0.0, 0.0);

    float depth = texture(depthtex0, texcoord).r;
    if (depth >= 1.0) {
        return;
    }

    vec3 view_pos = muon_view_pos_from_depth(texcoord, depth);
    vec3 view_normal = normalize(muon_read_opaque_view_normal(texcoord));

    MuonAO ao = muon_compute_ao(view_pos, view_normal);
    vec2 bent = muon_octahedral_encode(ao.bent_normal);

    out_ao = vec4(ao.occlusion, bent, 0.0);
}
