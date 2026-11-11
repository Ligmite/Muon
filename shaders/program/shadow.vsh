/*
================================================================================

  Muon Shaders - program/shadow.vsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Shadow caster vertex stage.

  Foliage is displaced by exactly the same function as in the camera pass, so a
  swaying leaf never casts a shadow that is detached from the visible leaf. The
  transform uses the shadow matrices explicitly instead of ftransform() so that
  the intent is visible and the same code can be translated to a native backend
  without relying on fixed-function state.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/constants.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/waving.glsl"

in vec4 mc_Entity;
in vec2 mc_midTexCoord;

out vec2 texcoord;

void main() {
    MUON_FRAME_INIT();

    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

    /* gl_Vertex is camera-relative world space in every geometry pass, which is
       what makes the displacement match the camera pass bit for bit. */
    vec3 world = gl_Vertex.xyz;

    float is_foliage;
    int material = 0;
    if (mc_Entity.x >= 10000.0) {
        int custom = int(mc_Entity.x - 10000.0 + 0.5);
        is_foliage = (custom == 1 || custom == 2 || custom == 9) ? 1.0 : 0.0;
        material = custom == 1 ? MUON_MAT_LEAVES : (custom == 2 ? MUON_MAT_FOLIAGE : MUON_MAT_PLANT);
    } else {
        is_foliage = 0.0;
    }

    if (is_foliage > 0.5) {
        float top_weight = step(mc_midTexCoord.y, texcoord.y);
        vec3 offset = vec3(0.0, texcoord.y - mc_midTexCoord.y, 0.0);
        world = muon_wave_foliage(world, offset, top_weight, muon_sway_gain(material));
    }

    gl_Position = shadowProjection * (shadowModelView * vec4(world, 1.0));
}
