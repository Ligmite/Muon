/*
================================================================================

  Muon Shaders
  lib/uniforms.glsl - the standard Iris/OptiFine uniform block

  Every program includes this exactly once (guarded). Declaring a uniform that
  a given pass does not read is harmless; leaving one out is not.

================================================================================
*/

#if !defined MUON_UNIFORMS
#define MUON_UNIFORMS

#include "/lib/common.glsl"

// --------
//   Time
// --------

uniform float frameTimeCounter;
uniform int   frameCounter;

// -----------
//   Matrices
// -----------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousProjectionInverse;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

// ----------
//   Camera
// ----------

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;
uniform float aspectRatio;
uniform float viewWidth;
uniform float viewHeight;

uniform int isEyeInWater;      // 0 = air, 1 = water, 2 = lava, 3 = powder snow
uniform float eyeAltitude;
uniform float blindness;
uniform float nightVision;
uniform float darknessFactor;
uniform float screenBrightness;

uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;

// ----------------
//   Sun and moon
// ----------------

uniform vec3 sunPosition;        // view space
uniform vec3 moonPosition;       // view space
uniform vec3 shadowLightPosition; // view space
uniform vec3 upPosition;         // view space
uniform float sunAngle;          // 0..1, 0.5 = noon
uniform float shadowAngle;       // 0..1
uniform int moonPhase;

// ------------
//   Weather
// ------------

uniform float rainStrength;
uniform float wetness;

uniform vec3 fogColor;
uniform vec3 skyColor;

// -----------
//   World
// -----------

uniform int world;   // -1 = nether, 0 = overworld, 1 = end

// -------------
//   Hand lamp
// -------------

uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

// ----------
//   Alpha
// ----------

uniform float alphaTestRef;

// --------
//   FOV
// --------

uniform float fovY;
uniform float fovX;

// ----------
//   Textures
// ----------

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform sampler2D normals;
uniform sampler2D specular;

uniform sampler2D noisetex;

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D depthtex2;

uniform sampler2D shadowtex0;
uniform sampler2D shadowtex1;

// -----------
//   Entities
// -----------

#if defined PROGRAM_ENTITIES || defined PROGRAM_BLOCK || defined PROGRAM_HAND

uniform vec4 entityColor;
#endif

#if defined PROGRAM_ENTITIES
uniform int entityId;
#endif

#if defined PROGRAM_BLOCK
uniform int blockEntityId;
#endif

// -------------------------------------------------
//   Distant Horizons / Voxy (Level of Detail mods)
// -------------------------------------------------

#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex0;
uniform sampler2D dhDepthTex1;

uniform mat4 dhProjection;
uniform mat4 dhProjectionInverse;

uniform float dhNearPlane;
uniform float dhFarPlane;

uniform int dhRenderDistance;

uniform vec3 dhSunDir;
#endif

#ifdef VOXY
uniform sampler2D vxDepthTexOpaque;
uniform sampler2D vxDepthTexTrans;
#endif

#endif // MUON_UNIFORMS
