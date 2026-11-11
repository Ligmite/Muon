/*
================================================================================

  Muon Shaders - program/gbuffers_weather.vsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Rain and snow particles.

  Weather is written into the translucent g-buffer rather than blended into the
  scene colour, because the deferred stage runs after all geometry and owns the
  only lit image. Precipitation therefore gets fogged, shadowed and temporally
  filtered like every other surface.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/constants.glsl"
#include "/lib/common/taa.glsl"

out vec2 texcoord;
out vec4 tint;
out vec3 view_pos;
out vec3 view_normal;
flat out int material_id;

void main() {
    MUON_FRAME_INIT();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    tint = gl_Color;

    vec3 position = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 normal = normalize(gl_NormalMatrix * gl_Normal);

    view_pos = position;
    view_normal = normal;
    material_id = MUON_MAT_GLASS;

    gl_Position = gl_ProjectionMatrix * vec4(position, 1.0);
    gl_Position.xy += muon_taa_jitter_ndc() * gl_Position.w;
}
