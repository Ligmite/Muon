/*
================================================================================

  Muon Shaders - settings.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  This file is part of Muon, distributed under the Muon Proprietary Licence.
  See LICENSE.txt in the repository root. Redistribution of this file, in
  whole or in part, is restricted by that licence.

--------------------------------------------------------------------------------

  This file is the single source of truth for every user-facing option of the
  pack. Iris parses the `#define` directives below to build the in-game menu
  described by `shaders.properties`, and each program consumes them as
  compile-time constants.

  IMPORTANT: this file must only ever contain preprocessor directives and
  `const` declarations. Voxy includes it from `voxy.json` inside a JSON string,
  so any executable GLSL in here would break that file.

  Value options use the `// [a b c ...]` enumeration syntax so Iris renders
  them as discrete sliders. Boolean options are enabled by un-commenting the
  `#define` and disabled by prefixing it with `//`.

================================================================================
*/

#ifndef MUON_SETTINGS_GLSL
#define MUON_SETTINGS_GLSL

// -----------------------------------------------------------------------------
//  Engine-visible constants
//  Iris scans this file for these exact declarations, so keep the names and
//  types intact even if you re-organise everything else.
// -----------------------------------------------------------------------------

const int noiseTextureResolution = 512;

const int   shadowMapResolution     = 2048; // [1024 1536 2048 3072 4096 6144 8192]
const float shadowDistance          = 160.0; // [64.0 80.0 96.0 112.0 128.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0]
const float shadowDistanceRenderMul = 1.0;
const float shadowIntervalSize      = 2.0;
const float sunPathRotation         = -30.0; // [-40.0 -35.0 -30.0 -25.0 -20.0 -15.0 -10.0 -5.0 0.0 5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0]
const float wetnessHalflife         = 90.0;
const float drynessHalflife         = 220.0;
const float ambientOcclusionLevel   = 0.0;

// -----------------------------------------------------------------------------
//  Quality master switch
//  Profiles assign QUALITY; every derived constant below follows from it so a
//  preset only has to set one integer to scale the whole pipeline.
//    0 = Low    1 = Medium    2 = High (default)    3 = Ultra
// -----------------------------------------------------------------------------

#define QUALITY 2

// -----------------------------------------------------------------------------
//  World
// -----------------------------------------------------------------------------

#define WAVING_PLANTS
#define WAVING_LEAVES
#define SWAY_STRENGTH 0.55 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.90 1.00]

#define WETNESS
#define RAIN_PUDDLES
#define PUDDLE_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]
#define SNOW_COVER
#define SNOW_STRENGTH 0.85 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00]
#define RAIN_OPACITY 0.45 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.70 0.80]
#define SNOW_OPACITY 0.80 // [0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// -----------------------------------------------------------------------------
//  Lighting
// -----------------------------------------------------------------------------

#define SHADOW
#define SHADOW_SAMPLES 16 // [4 6 8 12 16 24 32]
#define PCSS
#define PCSS_SOFTNESS 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00]
#define SHADOW_SSRT
#define SHADOW_SSRT_STEPS 12 // [4 6 8 10 12 16 20 24]
#define SHADOW_SSRT_DISTANCE 48.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0 96.0]
#define CLOUD_SHADOWS
#define CLOUD_SHADOW_STRENGTH 0.75 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.75 0.80 0.90 1.00]

#define SUNLIGHT 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.80 2.00]
#define MOONLIGHT 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.80 2.00]
#define AMBIENT_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]
#define BLOCKLIGHT_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]
#define MINIMUM_LIGHT 0.008 // [0.000 0.002 0.004 0.006 0.008 0.010 0.015 0.020 0.030 0.050]
#define BOUNCED_LIGHT
#define BOUNCED_LIGHT_STRENGTH 0.45 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 1.00]

// Ambient occlusion
#define GTAO
#define GTAO_SLICES 3 // [1 2 3 4 5]
#define GTAO_STEPS 6 // [2 3 4 5 6 8 10 12]
#define GTAO_RADIUS 1.30 // [0.20 0.40 0.60 0.80 1.00 1.20 1.40 1.60 2.00 2.50 3.00]
#define GTAO_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]
#define SSAO
#define SSAO_SAMPLES 12 // [2 4 6 8 10 12 16 20 24 32]
#define SSAO_RADIUS 1.00 // [0.20 0.40 0.60 0.80 1.00 1.20 1.40 1.60 2.00 2.50 3.00]
#define SSAO_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]

// Subsurface scattering
#define SUBSURFACE_SCATTERING
#define SSS_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.60 1.80 2.00]
#define SSS_STEPS 3 // [1 2 3 4 5 6]
#define SSS_RADIUS 0.55 // [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 1.00 1.20]

// -----------------------------------------------------------------------------
//  Sky, atmosphere and clouds
// -----------------------------------------------------------------------------

#define ATMOSPHERE
#define ATMOSPHERE_HAZE 0.55 // [0.00 0.10 0.20 0.30 0.40 0.50 0.55 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60]
#define ATMOSPHERE_MIE 0.65 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.65 0.70 0.80 0.90 1.00 1.20 1.40]
#define SKY_SATURATION 1.10 // [0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.40]
#define SKY_GROUND_TINT 0.35 // [0.00 0.10 0.20 0.30 0.35 0.40 0.50 0.60 0.70 0.80 1.00]
#define SUN_DISC
#define SUN_ANGULAR_RADIUS 0.70 // [0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.50]
#define MOON_DISC
#define STARS
#define STARS_INTENSITY 0.55 // [0.00 0.10 0.20 0.30 0.40 0.50 0.55 0.60 0.70 0.80 0.90 1.00]

#define CLOUDS
#define CLOUD_STEPS 40 // [12 16 20 24 32 40 48 56 64 80 96 128]
#define CLOUD_LIGHTING_STEPS 6 // [1 2 3 4 5 6 8 10]
#define CLOUD_ALTITUDE 320.0 // [120.0 180.0 240.0 300.0 320.0 360.0 420.0 500.0 640.0 800.0]
#define CLOUD_THICKNESS 640.0 // [160.0 240.0 320.0 400.0 480.0 560.0 640.0 800.0 1000.0 1400.0]
#define CLOUD_COVERAGE 0.42 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.42 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80]
#define CLOUD_DENSITY 1.00 // [0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.40 1.60 2.00]
#define CLOUD_SCALE 1.00 // [0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.40 1.60 2.00]
#define CLOUD_WIND_SPEED 1.00 // [0.00 0.20 0.40 0.60 0.80 1.00 1.20 1.40 1.60 2.00 2.50 3.00]
#define CLOUD_WIND_ANGLE 30.0 // [-180.0 -150.0 -120.0 -90.0 -60.0 -30.0 0.0 30.0 60.0 90.0 120.0 150.0 180.0]
#define CLOUD_WEATHER
#define CLOUD_AMBIENT_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60]

#define VOLUMETRIC_FOG
#define FOG_STEPS 12 // [4 6 8 10 12 16 20 24 32 48]
#define FOG_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.40 1.60]
#define FOG_RAIN_STRENGTH 1.60 // [0.00 0.20 0.40 0.60 0.80 1.00 1.20 1.40 1.60 1.80 2.00 2.50 3.00]
#define CAVE_FOG
#define CAVE_FOG_STRENGTH 0.55 // [0.00 0.10 0.20 0.30 0.40 0.50 0.55 0.60 0.70 0.80 0.90 1.00]

#define GOD_RAYS
#define GOD_RAYS_STRENGTH 0.65 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.65 0.70 0.80 0.90 1.00 1.20]
#define GOD_RAYS_STEPS 20 // [6 8 10 12 16 20 24 32 48]

// -----------------------------------------------------------------------------
//  Water
// -----------------------------------------------------------------------------

#define WATER_WAVES
#define WATER_WAVE_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60]
#define WATER_WAVE_ITERATIONS 3 // [1 2 3 4 5]
#define WATER_WAVE_SPEED 1.00 // [0.00 0.20 0.40 0.60 0.80 1.00 1.20 1.40 1.60 2.00]
#define WATER_WAVE_HEIGHT 1.00 // [0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 2.00]
#define WATER_EXTRUDE
#define WATER_REFRACTION
#define WATER_REFRACTION_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.40 1.60]
#define WATER_CAUSTICS
#define WATER_CAUSTICS_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60]
#define WATER_FOG
#define WATER_ABSORPTION_R 0.320 // [0.050 0.080 0.100 0.150 0.200 0.250 0.300 0.320 0.350 0.400 0.500]
#define WATER_ABSORPTION_G 0.060 // [0.010 0.020 0.030 0.040 0.050 0.060 0.070 0.080 0.100 0.120 0.150]
#define WATER_ABSORPTION_B 0.045 // [0.010 0.020 0.030 0.040 0.045 0.050 0.060 0.070 0.080 0.100 0.120]
#define WATER_SCATTERING 0.090 // [0.000 0.020 0.040 0.060 0.080 0.090 0.100 0.120 0.150 0.200 0.300]
#define WATER_REFLECTION_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20]

// -----------------------------------------------------------------------------
//  Materials
// -----------------------------------------------------------------------------

#define NORMAL_MAPPING
#define SPECULAR_MAPPING
#define HARDCODED_F0
#define HARDCODED_F0_VALUE 0.04 // [0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.10]
#define EMISSION_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 2.00]
#define PARALLAX
#define POM_DEPTH 0.16 // [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.20 0.25 0.30]
#define POM_SAMPLES 24 // [8 12 16 20 24 32 48 64]
#define POM_SELF_SHADOW
#define POM_SHADOW_SAMPLES 6 // [2 3 4 6 8 12]
#define POM_DISTANCE 48.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0 96.0 128.0]
#define POM_REFINE_STEPS 4 // [0 2 4 6 8]

// -----------------------------------------------------------------------------
//  Reflections and global illumination
// -----------------------------------------------------------------------------

#define SCREENSPACE_REFLECTIONS
#define SSR_STEPS 24 // [8 12 16 20 24 32 40 48 64]
#define SSR_REFINE_STEPS 4 // [0 2 4 6 8]
#define SSR_ROUGHNESS
#define SSR_MAX_DISTANCE 96.0 // [16.0 24.0 32.0 48.0 64.0 80.0 96.0 128.0 192.0]
#define SSR_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40]
#define SKY_REFLECTIONS
#define WATER_SSR
#define SSR_EDGE_FADE 0.15 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40]

//#define RTGI
#define RTGI_MODE 0 // [0 1 2]
#define RTGI_BOUNCES 1 // [1 2 3]
#define RTGI_SAMPLES 4 // [1 2 3 4 6 8 12]
#define RTGI_STEPS 16 // [6 8 12 16 24 32 48]
#define RTGI_RADIUS 6.00 // [1.00 1.50 2.00 3.00 4.00 5.00 6.00 8.00 10.00 12.00 16.00]
#define RTGI_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 2.00]
#define RTGI_DENOISE
#define RTGI_DENOISE_STRENGTH 0.65 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.65 0.70 0.80 0.90 1.00]
#define RTGI_SKY_FALLBACK

// -----------------------------------------------------------------------------
//  Post-processing
// -----------------------------------------------------------------------------

#define TAA
#define TAA_STRENGTH 0.90 // [0.00 0.20 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.92 0.94 0.96 0.98]
#define TAA_CLIPPING 1.00 // [0.00 0.20 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.50]
#define TAA_SHARPEN
#define FXAA
#define FXAA_STRENGTH 0.75 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.75 0.80 0.90 1.00]

#define AUTO_EXPOSURE
#define EXPOSURE_BIAS 0.00 // [-2.00 -1.50 -1.00 -0.75 -0.50 -0.25 0.00 0.25 0.50 0.75 1.00 1.50 2.00]
#define EXPOSURE_MIN -2.50 // [-6.00 -5.00 -4.50 -4.00 -3.50 -3.00 -2.50 -2.00 -1.50 -1.00 -0.50 0.00]
#define EXPOSURE_MAX 2.50 // [0.00 0.50 1.00 1.50 2.00 2.50 3.00 4.00 5.00 6.00]
#define EXPOSURE_SPEED 1.00 // [0.10 0.25 0.50 0.75 1.00 1.50 2.00 3.00 4.00]
#define MANUAL_EXPOSURE 0.00 // [-4.00 -3.00 -2.00 -1.50 -1.00 -0.50 0.00 0.50 1.00 1.50 2.00 3.00 4.00]

#define TONEMAP_MODE 0 // [0 1 2]
#define TONEMAP_EXPOSURE_PRESCALE 1.00 // [0.50 0.70 0.85 1.00 1.15 1.30 1.50 1.80]
#define TONEMAP_WHITE_POINT 6.00 // [2.00 3.00 4.00 5.00 6.00 8.00 10.00 16.00]

#define BLOOM
#define BLOOM_STRENGTH 0.060 // [0.000 0.010 0.020 0.030 0.040 0.050 0.060 0.070 0.080 0.100 0.120 0.150 0.200]
#define BLOOM_THRESHOLD 1.00 // [0.00 0.20 0.40 0.60 0.80 1.00 1.20 1.50 2.00 3.00]
#define BLOOM_RADIUS 1.00 // [0.40 0.60 0.80 1.00 1.20 1.40 1.60 2.00]

//#define DEPTH_OF_FIELD
#define DOF_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40]
#define DOF_APERTURE 1.50 // [0.10 0.20 0.30 0.40 0.50 0.60 0.80 1.00 1.20 1.50 2.00 3.00 4.00]
#define DOF_SAMPLES 24 // [6 8 12 16 20 24 32 48]
#define DOF_FOCUS 0.55 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]
#define DOF_HAND_BLUR
#define DOF_HAND_BLUR_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40]

#define LENS_FLARE
#define LENS_FLARE_STRENGTH 0.30 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60]
#define LENS_FLARE_GHOSTS 3 // [1 2 3 4 5]

#define COLOR_GRADING
#define GRADE_BRIGHTNESS 1.00 // [0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20]
#define GRADE_CONTRAST 1.04 // [0.80 0.85 0.90 0.95 1.00 1.02 1.04 1.06 1.08 1.10 1.15 1.20]
#define GRADE_SATURATION 1.06 // [0.60 0.70 0.80 0.90 0.95 1.00 1.04 1.06 1.08 1.10 1.15 1.20 1.30 1.40]
#define GRADE_TEMPERATURE 0.55 // [-1.00 -0.50 0.00 0.20 0.40 0.55 0.70 0.85 1.00]
#define GRADE_TINT 0.10 // [-1.00 -0.50 0.00 0.10 0.20 0.30 0.50 1.00]
#define GRADE_SHADOW_TINT 0.15 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50]

#define VIGNETTE
#define VIGNETTE_STRENGTH 0.22 // [0.00 0.05 0.10 0.15 0.20 0.22 0.25 0.30 0.35 0.40 0.50]
#define SHARPEN
#define SHARPEN_STRENGTH 0.28 // [0.00 0.10 0.20 0.25 0.28 0.30 0.35 0.40 0.50 0.60 0.80]
#define CHROMATIC_ABERRATION 0.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.75 1.00]
#define FILM_GRAIN 0.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.75 1.00]
#define DITHER

// -----------------------------------------------------------------------------
//  Mod integration
// -----------------------------------------------------------------------------

#define DH_RENDER
#define DH_SHADOWS
#define DH_WATER
#define DH_NOISE
#define DH_NOISE_STRENGTH 0.35 // [0.00 0.10 0.20 0.30 0.35 0.40 0.50 0.60 0.80 1.00]
#define DH_FOG_START 0.65 // [0.10 0.20 0.30 0.40 0.50 0.60 0.65 0.70 0.80 0.90 1.00]

// -----------------------------------------------------------------------------
//  Developer
// -----------------------------------------------------------------------------

#define DEBUG_VIEW 0 // [0 1 2 3 4 5 6 7 8 9 10 11]
#define TONEMAP_COMPARISON
#define DOF_AUTOFOCUS

// -----------------------------------------------------------------------------
//  Derived constants
//
//  These are computed from QUALITY and the options above. Nothing below this
//  line is exposed in the menu; it exists so that the programs can stay free of
//  magic numbers and so that presets scale coherently.
// -----------------------------------------------------------------------------

#if QUALITY == 0
    #define VOLUMETRIC_STEPS        (FOG_STEPS / 2)
    #define CLOUD_PRIMARY_STEPS     (CLOUD_STEPS / 2)
    #define CLOUD_DETAIL_STEPS      0
    #define SHADOW_SAMPLE_COUNT     (SHADOW_SAMPLES / 2)
    #define AO_SLICES               1
    #define AO_STEPS                3
    #define EXPOSURE_LUMA_STEPS     4
    #define ROUGH_REFLECTION_SAMPLES 0
#elif QUALITY == 1
    #define VOLUMETRIC_STEPS        (FOG_STEPS)
    #define CLOUD_PRIMARY_STEPS     (CLOUD_STEPS)
    #define CLOUD_DETAIL_STEPS      2
    #define SHADOW_SAMPLE_COUNT     (SHADOW_SAMPLES)
    #define AO_SLICES               2
    #define AO_STEPS                (GTAO_STEPS)
    #define EXPOSURE_LUMA_STEPS     8
    #define ROUGH_REFLECTION_SAMPLES 1
#elif QUALITY == 2
    #define VOLUMETRIC_STEPS        (FOG_STEPS + 4)
    #define CLOUD_PRIMARY_STEPS     (CLOUD_STEPS)
    #define CLOUD_DETAIL_STEPS      4
    #define SHADOW_SAMPLE_COUNT     (SHADOW_SAMPLES)
    #define AO_SLICES               (GTAO_SLICES)
    #define AO_STEPS                (GTAO_STEPS)
    #define EXPOSURE_LUMA_STEPS     16
    #define ROUGH_REFLECTION_SAMPLES 2
#else
    #define VOLUMETRIC_STEPS        (FOG_STEPS * 2)
    #define CLOUD_PRIMARY_STEPS     (CLOUD_STEPS + 16)
    #define CLOUD_DETAIL_STEPS      6
    #define SHADOW_SAMPLE_COUNT     (SHADOW_SAMPLES)
    #define AO_SLICES               (GTAO_SLICES)
    #define AO_STEPS                (GTAO_STEPS + 2)
    #define EXPOSURE_LUMA_STEPS     32
    #define ROUGH_REFLECTION_SAMPLES 3
#endif

#if QUALITY == 0
    #define HAZE_QUALITY_FACTOR 0.5
#else
    #define HAZE_QUALITY_FACTOR 1.0
#endif

// -----------------------------------------------------------------------------
//  Version
// -----------------------------------------------------------------------------

#define MUON_VERSION_MAJOR 0
#define MUON_VERSION_MINOR 0
#define MUON_VERSION_PATCH 1
#define MUON_VERSION_STRING "v0.0.1"

#endif // MUON_SETTINGS_GLSL
