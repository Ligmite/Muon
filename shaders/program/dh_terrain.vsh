/*
================================================================================

  Muon Shaders - program/dh_terrain.vsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Distant Horizons terrain vertex stage.

  DH hands the pack geometry in its own coordinate space with its own projection
  matrix. The only thing that has to happen here is the same snapping Minecraft
  applies so that LOD terrain does not shimmer relative to nearby chunks, and the
  same temporal jitter so that TAA sees a consistent sample pattern across the
  LOD boundary.

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

#ifndef DH_BLOCK_GRASS
    #define DH_BLOCK_GRASS 13
    #define DH_BLOCK_DIRT 14
    #define DH_BLOCK_STONE 15
    #define DH_BLOCK_DEEPSLATE 16
    #define DH_BLOCK_NETHER_STONE 17
    #define DH_BLOCK_SAND 18
    #define DH_BLOCK_WOOD 19
    #define DH_BLOCK_LEAVES 20
    #define DH_BLOCK_METAL 21
    #define DH_BLOCK_LAVA 22
    #define DH_BLOCK_ILLUMINATED 23
    #define DH_BLOCK_SNOW 24
    #define DH_BLOCK_WATER 25
    #define DH_BLOCK_AIR 26
#endif

int muon_dh_material(int dh_material) {
    if (dh_material == DH_BLOCK_LEAVES) {
        return MUON_MAT_LEAVES;
    }
    if (dh_material == DH_BLOCK_GRASS) {
        return MUON_MAT_GRASS;
    }
    if (dh_material == DH_BLOCK_SAND) {
        return MUON_MAT_SAND;
    }
    if (dh_material == DH_BLOCK_WOOD) {
        return MUON_MAT_WOOD;
    }
    if (dh_material == DH_BLOCK_METAL) {
        return MUON_MAT_METAL;
    }
    if (dh_material == DH_BLOCK_LAVA) {
        return MUON_MAT_LAVA;
    }
    if (dh_material == DH_BLOCK_ILLUMINATED) {
        return MUON_MAT_EMISSIVE;
    }
    if (dh_material == DH_BLOCK_SNOW) {
        return MUON_MAT_SNOW;
    }
    if (dh_material == DH_BLOCK_WATER) {
        return MUON_MAT_WATER;
    }
    return MUON_MAT_STONE;
}

void main() {
    MUON_FRAME_INIT();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    tint = gl_Color;

    /* Snap to the block grid in camera-relative space so that DH and vanilla
       geometry agree about where the world is. */
    vec3 camera_offset = fract(cameraPosition);
    vec3 position = gl_Vertex.xyz;
    position = floor(position + camera_offset + 0.5) - camera_offset;
    position = (gl_ModelViewMatrix * vec4(position, 1.0)).xyz;

    view_pos = position;
    view_normal = normalize(gl_NormalMatrix * gl_Normal);
    material_id = muon_dh_material(dhMaterialId);

    vec4 clip = dhProjection * vec4(position, 1.0);
    clip.xy += muon_taa_jitter_ndc() * clip.w;

    gl_Position = clip;
}
