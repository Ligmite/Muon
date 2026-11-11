/*
================================================================================

  Muon Shaders - lib/uniforms/iris.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Every uniform that the Iris/OptiFine shader API injects is declared here, and
  only here. Program files and feature libraries never declare loose uniforms:
  they read the grouped MuonFrame block from lib/uniforms/frame.glsl instead.

  On a native Vulkan/WGSL backend the whole MuonFrame block is supplied by a
  std140 uniform buffer, so this file - and the loader - are the only places
  that need to change.

================================================================================
*/

#ifndef MUON_UNIFORMS_IRIS_GLSL
#define MUON_UNIFORMS_IRIS_GLSL

// -----------------------------------------------------------------------------
//  Viewport
// -----------------------------------------------------------------------------

uniform float viewWidth;
uniform float viewHeight;

// -----------------------------------------------------------------------------
//  Camera and matrices
// -----------------------------------------------------------------------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform float near;
uniform float far;
uniform float aspectRatio;

// -----------------------------------------------------------------------------
//  Celestial state
// -----------------------------------------------------------------------------

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 upPosition;
uniform vec3 shadowLightPosition;

uniform float sunAngle;
uniform float shadowAngle;
uniform int moonPhase;

uniform float starAngle;
uniform vec3 skyColor;
uniform vec3 fogColor;

uniform float frameTime;
uniform float frameTimeCounter;
uniform int frameCounter;

uniform int worldTime;
uniform int worldDay;

// -----------------------------------------------------------------------------
//  Weather, biome and player state
// -----------------------------------------------------------------------------

uniform float rainStrength;
uniform float wetness;
uniform float thunderStrength;

uniform float nightVision;
uniform float blindness;
uniform float darknessFactor;
uniform float screenBrightness;

uniform float eyeAltitude;
uniform float eyeHeight;
uniform ivec2 eyeBrightness;
uniform ivec2 eyeBrightnessSmooth;
uniform int isEyeInWater;

uniform int heldBlockLightValue;
uniform int heldItemId;

uniform float temperature;
uniform float rainfall;
uniform int biome;
uniform int biome_category;
uniform int biome_precipitation;

uniform int seaLevel;

// -----------------------------------------------------------------------------
//  Geometry state
// -----------------------------------------------------------------------------

uniform int entityId;
uniform int blockEntityId;
uniform int currentRenderedItemId;
uniform int renderStage;
uniform float alphaTestRef;

// -----------------------------------------------------------------------------
//  Textures
//  These are the loader-provided samplers. The pack's own render targets are
//  declared in samplers.glsl, and the 3D noise volumes in lib/common/noise.glsl.
// -----------------------------------------------------------------------------

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
uniform sampler2D shadowcolor0;

// -----------------------------------------------------------------------------
//  Distant Horizons
//  Iris defines DISTANT_HORIZONS only when the mod is installed and its
//  compatibility layer is active.
// -----------------------------------------------------------------------------

#ifdef DISTANT_HORIZONS
uniform sampler2D dhDepthTex;
uniform sampler2D dhDepthTex1;
uniform sampler2D dhDepthTex2;
uniform mat4 dhProjection;
uniform mat4 dhProjectionInverse;
uniform mat4 dhPreviousProjection;
uniform mat4 dhModelView;
uniform mat4 dhModelViewInverse;
uniform float dhNearPlane;
uniform float dhFarPlane;
uniform int dhRenderDistance;
/* dhMaterialId is deliberately NOT declared here: Iris' Distant Horizons
   integration injects `uniform int dhMaterialId;` into the prefix of every
   dh_* program, and declaring it again is a duplicate-definition error. */
#endif

// -----------------------------------------------------------------------------
//  Voxy
//  Voxy defines VOXY itself when its shader integration is loaded.
// -----------------------------------------------------------------------------

#ifdef VOXY
uniform sampler2D vxDepthTexOpaque;
uniform sampler2D vxDepthTexTrans;
uniform mat4 vxProj;
uniform mat4 vxProjInv;
uniform mat4 vxProjPrev;
uniform int vxRenderDistance;
#endif

// -----------------------------------------------------------------------------
//  Iris extras (only meaningful on Iris; harmlessly zero elsewhere)
// -----------------------------------------------------------------------------

uniform int currentColorSpace;
uniform vec4 lightningBoltPosition;
uniform float endFlashIntensity;
uniform int textureFilteringMode;

#endif // MUON_UNIFORMS_IRIS_GLSL
