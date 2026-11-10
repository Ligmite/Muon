#version 400 compatibility
/*
================================================================================

  Muon Shaders
  lib/buffers.glsl - buffer declaration block

  Iris/OptiFine read `const ...` declarations that live inside a leading
  comment. This file exists purely so those declarations are part of a compiled
  program (it is included by final.fsh).

  Texture formats and sizes live in shaders.properties. Only the clear flags
  are declared here, because the default is "clear every frame" and that would
  destroy the TAA and ray tracing history.

================================================================================
*/
/*
const bool colortex0Clear  = true;   // scene colour, fully rewritten
const bool colortex1Clear  = false;  // gbuffer albedo
const bool colortex2Clear  = false;  // gbuffer normal
const bool colortex3Clear  = false;  // gbuffer material
const bool colortex4Clear  = false;  // ambient occlusion
const bool colortex5Clear  = false;  // TAA history - MUST persist
const bool colortex6Clear  = false;  // volumetrics
const bool colortex7Clear  = false;  // clouds
const bool colortex8Clear  = false;  // ray tracing result
const bool colortex9Clear  = true;   // translucent extras (accumulated)
const bool colortex10Clear = true;   // translucent colour (accumulated)
const bool colortex11Clear = false;  // composite scratch
const bool colortex12Clear = false;  // ray tracing history - MUST persist
const bool colortex13Clear = false;  // tonemapped colour
const bool colortex14Clear = false;  // light levels
const bool colortex15Clear = false;  // spare

const vec4 colortex9ClearColor  = vec4(0.0);
const vec4 colortex10ClearColor = vec4(0.0);
*/
