/*
================================================================================

  Muon Shaders - lib/uniforms/samplers.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Declarations for every sampler the pack creates itself.

  The loader-provided samplers (depthtex*, shadowtex*, gtexture, lightmap,
  normals, specular, noisetex) live in lib/uniforms/iris.glsl. Everything that
  Muon owns - the colour targets and the noise volumes - is declared exactly
  once, here, so that no two libraries can declare the same uniform with
  different qualifiers.

  A native backend replaces this file with a descriptor-set binding table; the
  names are chosen so that the mapping is one-to-one.

================================================================================
*/

#ifndef MUON_UNIFORMS_SAMPLERS_GLSL
#define MUON_UNIFORMS_SAMPLERS_GLSL

#include "/lib/uniforms/iris.glsl"

// --- scene chain -----------------------------------------------------------

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex5;
uniform sampler2D colortex6;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D colortex9;
uniform sampler2D colortex10;
uniform sampler2D colortex11;
uniform sampler2D colortex12;
uniform sampler2D colortex13;
uniform sampler2D colortex14;
uniform sampler2D colortex15;

#endif // MUON_UNIFORMS_SAMPLERS_GLSL
