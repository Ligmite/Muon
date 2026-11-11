/*
================================================================================

  Muon Shaders - program/gbuffers_solid.vsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Vertex stage for every opaque geometry source: terrain, entities, block
  entities, the hand and the debug renderers.

  It writes no lighting. Its whole job is to place the vertex, animate foliage
  and water, and hand the fragment stage a clean interpolated basis plus the
  material classification that the fragment stage cannot compute on its own
  (block identity is a per-quad attribute).

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/constants.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/waving.glsl"
#include "/lib/common/taa.glsl"

// --- per-vertex attributes supplied by Iris --------------------------------

in vec4 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_tangent;

// --- interpolants -----------------------------------------------------------

out vec2 texcoord;
out vec2 lmcoord;
out vec4 tint;
out vec3 view_pos;
out vec3 view_normal;
flat out int material_id;
flat out float vertex_ao;

// -----------------------------------------------------------------------------
//  Material classification
// -----------------------------------------------------------------------------

int muon_classify_block(float entity_id, out float is_foliage) {
    is_foliage = 0.0;

    if (entity_id < 10000.0) {
        return MUON_MAT_STONE;
    }

    int custom = int(entity_id - 10000.0 + 0.5);
    if (custom == 1) {
        is_foliage = 1.0;
        return MUON_MAT_LEAVES;
    } else if (custom == 2) {
        is_foliage = 1.0;
        return MUON_MAT_FOLIAGE;
    } else if (custom == 3) {
        return MUON_MAT_LAVA;
    } else if (custom == 4) {
        return MUON_MAT_WATER;
    } else if (custom == 5) {
        return MUON_MAT_METAL;
    } else if (custom == 6) {
        return MUON_MAT_EMISSIVE;
    } else if (custom == 7) {
        return MUON_MAT_SAND;
    } else if (custom == 8) {
        return MUON_MAT_ICE;
    } else if (custom == 9) {
        is_foliage = 1.0;
        return MUON_MAT_PLANT;
    } else if (custom == 10) {
        return MUON_MAT_WOOD;
    } else if (custom == 11) {
        return MUON_MAT_SNOW;
    } else if (custom == 12) {
        return MUON_MAT_GLASS;
    }

    return MUON_MAT_CUSTOM_BASE;
}

void main() {
    MUON_FRAME_INIT();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;

    vec3 position = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 normal = normalize(gl_NormalMatrix * gl_Normal);

    /* --- foliage animation -------------------------------------------- */

    float is_foliage;
    int material = muon_classify_block(mc_Entity.x, is_foliage);

#if defined MUON_STAGE_HAND
    material = MUON_MAT_HAND;
    is_foliage = 0.0;
#endif

    if (is_foliage > 0.5) {
        /* Vertices above the middle of the sprite are the free end of a plant
           and swing; the lower half stays anchored. */
        float top_weight = step(mc_midTexCoord.y, texcoord.y);
        vec3 world = (gbufferModelViewInverse * vec4(position, 1.0)).xyz;
        vec3 offset = vec3(0.0, texcoord.y - mc_midTexCoord.y, 0.0);
        vec3 animated = muon_wave_foliage(world, offset, top_weight, muon_sway_gain(material));
        position = (gbufferModelView * vec4(animated, 1.0)).xyz;
    }

    material_id = material;
    vertex_ao = 1.0;
    view_pos = position;
    view_normal = normal;

    gl_Position = gl_ProjectionMatrix * vec4(position, 1.0);

    /* Sub-pixel jitter for the temporal anti-aliasing resolve. */
    gl_Position.xy += muon_taa_jitter_ndc() * gl_Position.w;
}
