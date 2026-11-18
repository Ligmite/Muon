/*
================================================================================

  Muon Shaders - program/composite2.fsh
  Version 0.1.2

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Indirect compositing, screen-space god rays and the velocity buffer.

  God rays are traced radially towards the sun's screen position using the
  depth buffer as an occluder test, which is what makes shafts bend around
  terrain instead of being painted over it.

  Targets:
      0   combined scene (input for the temporal resolve)
      8   velocity.rg, linear depth.b, previous exposure.a

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_read.glsl"
#include "/lib/common/volumetric.glsl"
#include "/lib/common/taa.glsl"


in vec2 texcoord;

layout(location = 0) out vec4 out_scene;
layout(location = 1) out vec4 out_velocity;

/* RENDERTARGETS: 0,8 */

void main() {
    MUON_FRAME_INIT();

    vec2 uv = texcoord;

    vec3 color = texture(colortex15, uv).rgb;
    vec3 reflection = texture(colortex13, uv).rgb;
    vec3 indirect = texture(colortex7, uv).rgb;

    color += reflection;
    color += indirect;

    float depth = texture(depthtex1, uv).r;
    float linear_depth = depth >= 1.0 ? muonFrame.depthParams.y : muon_linear_depth(depth);
    vec3 view_ray = muon_view_pos_from_depth(uv, depth >= 1.0 ? 1.0 : depth);
    vec3 world_dir = normalize(muon_view_to_world_dir(view_ray));

#if defined GOD_RAYS
    color += muon_god_rays(uv, world_dir, linear_depth, color);
#endif

    /* Fireflies and NaNs from any upstream pass must not reach the temporal
       filter, which would then smear them across the frame. */
    out_scene = vec4(muon_clamp_hdr(color, 512.0), 1.0);

    /* --- velocity and exposure state ------------------------------------ */

    vec2 velocity = vec2(0.0);
    if (depth < 1.0) {
        vec3 view_pos = muon_view_pos_from_depth(uv, depth);
        velocity = muon_velocity(uv, view_pos);
    }

    /* The adapted exposure is carried into the next frame here, so that the
       exposure pass never has to read the buffer it writes. */
    float exposure = texture(colortex12, vec2(0.5)).r;

    out_velocity = vec4(velocity, linear_depth, exposure);
}
