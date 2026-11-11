/*
================================================================================

  Muon Shaders - program/dh_water.vsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Distant Horizons water vertex stage. Mirrors dh_terrain but writes the
  translucent g-buffer so that LOD oceans are shaded by the water model rather
  than as opaque surfaces.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/constants.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/taa.glsl"

out vec2 texcoord;
out vec2 lmcoord;
out vec4 tint;
out vec3 view_pos;
out vec3 view_normal;
flat out int material_id;

void main() {
    MUON_FRAME_INIT();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;

    vec3 camera_offset = fract(cameraPosition);
    vec3 position = gl_Vertex.xyz;
    position = floor(position + camera_offset + 0.5) - camera_offset;
    position = (gl_ModelViewMatrix * vec4(position, 1.0)).xyz;

    view_pos = position;
    view_normal = normalize(gl_NormalMatrix * gl_Normal);
    material_id = MUON_MAT_WATER;

    vec4 clip = dhProjection * vec4(position, 1.0);
    clip.xy += muon_taa_jitter_ndc() * clip.w;

    gl_Position = clip;
}
