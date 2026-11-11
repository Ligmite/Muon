/*
================================================================================

  Muon Shaders - lib/common/global.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  The only include a program file needs.

  It pulls in the user settings, the loader uniforms, the MuonFrame block and
  the platform-agnostic core maths. Feature libraries are *not* included here:
  each program includes exactly the features it uses, which keeps shader
  compilation fast and makes every program's dependencies explicit.

  Include order inside this file matters and is fixed:
      settings -> loader uniforms -> frame block -> settings constants -> core

================================================================================
*/

#ifndef MUON_COMMON_GLOBAL_GLSL
#define MUON_COMMON_GLOBAL_GLSL

#include "/settings.glsl"

#include "/lib/uniforms/iris.glsl"
#include "/lib/uniforms/frame.glsl"
#include "/lib/uniforms/settings.glsl"
#include "/lib/uniforms/samplers.glsl"

#include "/lib/common/constants.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/random.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/color.glsl"
#include "/lib/common/tonemap.glsl"

// -----------------------------------------------------------------------------
//  Pass identification
//  Programs define one of these before including global; the value is used by
//  debug views and by the vertex stage to decide which animation applies.
// -----------------------------------------------------------------------------

#if !defined MUON_PASS_OPAQUE
    #define MUON_PASS_OPAQUE 0
#endif
#if !defined MUON_PASS_TRANSLUCENT
    #define MUON_PASS_TRANSLUCENT 0
#endif
#if !defined MUON_PASS_SHADOW
    #define MUON_PASS_SHADOW 0
#endif

// -----------------------------------------------------------------------------
//  Debug view names
//  Kept as an enum-like block of constants so that shaders.properties and the
//  debug visualiser cannot drift apart.
// -----------------------------------------------------------------------------

const int MUON_DEBUG_OFF = 0;
const int MUON_DEBUG_ALBEDO = 1;
const int MUON_DEBUG_NORMAL = 2;
const int MUON_DEBUG_DEPTH = 3;
const int MUON_DEBUG_AO = 4;
const int MUON_DEBUG_REFLECTION = 5;
const int MUON_DEBUG_GI = 6;
const int MUON_DEBUG_VELOCITY = 7;
const int MUON_DEBUG_LIGHTMAP = 8;
const int MUON_DEBUG_MATERIAL = 9;
const int MUON_DEBUG_EXPOSURE = 10;
const int MUON_DEBUG_BLOOM = 11;

#endif // MUON_COMMON_GLOBAL_GLSL
