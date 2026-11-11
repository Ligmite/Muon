/*
================================================================================

  Muon Shaders - program/gbuffers_water.vsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Vertex stage for translucent geometry: water, stained glass, ice, slime,
  weather particles and translucent entities.

  Water surfaces get a real Gerstner displacement on their top vertices. The
  wave sum is evaluated here and re-evaluated at a higher frequency in the
  fragment stage, so the geometry carries the large swell and the normal carries
  the chop.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/constants.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/waving.glsl"
#include "/lib/common/taa.glsl"

in vec4 mc_Entity;
in vec2 mc_midTexCoord;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 tint;
out vec3 view_pos;
out vec3 view_normal;
out vec3 world_pos;
flat out int material_id;
flat out float surface_weight;

void main() {
    MUON_FRAME_INIT();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;

    vec3 position = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 normal = normalize(gl_NormalMatrix * gl_Normal);
    vec3 world = (gbufferModelViewInverse * vec4(position, 1.0)).xyz;

    /* Water is identified by the program itself, not by block identity: every
       triangle rendered by gbuffers_water belongs to the translucent layer. */
    int material = MUON_MAT_GLASS;
#if defined MUON_STAGE_WATER
    material = MUON_MAT_WATER;
#endif

    /* Only the top face of a water column is displaced. */
    float top_weight = step(0.5, normalize(gl_Normal).y);
    if (material == MUON_MAT_WATER) {
        world = muon_wave_water(world, top_weight);
        position = (gbufferModelView * vec4(world, 1.0)).xyz;
    }

    material_id = material;
    surface_weight = top_weight;
    world_pos = world;
    view_pos = position;
    view_normal = normal;

    gl_Position = gl_ProjectionMatrix * vec4(position, 1.0);
    gl_Position.xy += muon_taa_jitter_ndc() * gl_Position.w;
}
