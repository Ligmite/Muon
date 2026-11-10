/*
================================================================================

  Muon Shaders
  settings.glsl - every user-facing option lives here

  This file is parsed by Iris/OptiFine's settings parser:
    * "#define NAME"                -> boolean toggle
    * "#define NAME value // [...]" -> slider / enum (the bracketed list are the
                                       selectable values, or enum names)
    * "const ... NAME = value;"     -> special loader-recognised value

  Every option is also translated in lang/en_US.lang.

================================================================================
*/

#if !defined SETTINGS_INCLUDED
#define SETTINGS_INCLUDED

// ----------------
//   Version info
// ----------------

#define MUON_VERSION_MAJOR 1
#define MUON_VERSION_MINOR 0
#define MUON_VERSION_PATCH 0
#define MUON_CODENAME "Ion"

// -----------------------------
//   Loader-recognised constants
// -----------------------------

const int noiseTextureResolution      = 256;
const int shadowMapResolution         = 2048;   // [1024 1536 2048 3072 4096 6144 8192 12288 16384]
const float shadowDistance            = 160.0;  // [32.0 48.0 64.0 80.0 96.0 112.0 128.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0 768.0 1024.0]
const float shadowDistanceRenderMul   = 1.0;
const float shadowIntervalSize        = 2.0;
const float sunPathRotation           = -35.0;  // [-90.0 -80.0 -70.0 -60.0 -50.0 -40.0 -35.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 40.0 50.0 60.0 70.0 80.0 90.0]
const float ambientOcclusionLevel     = 0.0;    // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
const float wetnessHalflife           = 200.0;
const float drynessHalflife           = 400.0;
const float eyeBrightnessHalflife     = 10.0;

// ============================================================================
//   WORLD
// ============================================================================

  #define WAVING_PLANTS
  #define WAVING_LEAVES
  #define WIND_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00]
  #define EDGE_HIGHLIGHT
  #define EDGE_HIGHLIGHT_SCALE 32.0 // [8.0 16.0 32.0 64.0 128.0 256.0]
  #define RAIN_OPACITY 0.30 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.60 0.70 0.80 0.90 1.00]
  #define MOON_PHASE_AFFECTS_BRIGHTNESS
  #define SEA_LEVEL 63.0 // [-64.0 0.0 4.0 32.0 63.0 128.0]
  #define VANILLA_CLOUDS_LAYER // draw Minecraft's flat clouds in addition to volumetric ones

// ============================================================================
//   LIGHTING
// ============================================================================

// Shadows
  #define SHADOW
  #define SHADOW_SOFT
  #define SHADOW_PENUMBRA_SCALE 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.50 3.00]
  #define SHADOW_SAMPLES 24 // [8 12 16 24 32 48 64]
  #define SHADOW_BLOCKER_SAMPLES 12 // [4 8 12 16 24]
  #define SHADOW_BIAS 0.60 // [0.00 0.20 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.50]
  #define SHADOW_SSRT
  #define SHADOW_SSRT_STEPS 48 // [16 24 32 48 64 96]

// Ambient occlusion
  #define SHADER_AO 2 // [0 1 2] 0 = off, 1 = SSAO, 2 = GTAO
  #define SSAO_STEPS 12 // [4 6 8 10 12 16 24 32]
  #define SSAO_RADIUS 1.40 // [0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.50 3.00]
  #define GTAO_SLICES 5 // [2 3 4 5 6 8]
  #define GTAO_HORIZON_STEPS 6 // [3 4 5 6 7 8 10 12]
  #define GTAO_RADIUS 1.60 // [0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.50 3.00 4.00]
  #define AO_IN_SUNLIGHT

// Light sources
  #define SUN_I 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
  #define SUN_TEMPERATURE 5800.0 // [3000.0 3500.0 4000.0 4500.0 5000.0 5500.0 5800.0 6000.0 6500.0 7000.0 7500.0 8000.0]
  #define MOON_I 0.14 // [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20 0.25 0.30 0.40 0.50]
  #define MOON_TEMPERATURE 9000.0 // [5000.0 6000.0 7000.0 8000.0 9000.0 10000.0 12000.0]
  #define BLOCKLIGHT_I 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]
  #define BLOCKLIGHT_TEMPERATURE 2400.0 // [1500.0 1800.0 2000.0 2200.0 2400.0 2600.0 2800.0 3000.0]
  #define SKYLIGHT_I 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]
  #define BOUNCED_LIGHT_I 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]
  #define CAVE_LIGHTING_I 0.55 // [0.00 0.10 0.20 0.30 0.40 0.50 0.55 0.60 0.70 0.80 0.90 1.00]
  #define MINIMUM_LIGHT 0.00 // [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.08 0.10 0.15 0.20]

// Response
  #define HANDHELD_LIGHTING
  #define HANDHELD_LIGHTING_INTENSITY 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00]
  #define CLOUD_SHADOWS
  #define CLOUD_SHADOWS_INTENSITY 0.75 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.75 0.80 0.90 1.00]
  #define SSS_SHEEN
  #define SSS_INTENSITY 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]
  #define SHADING_STRENGTH 1.00 // [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]

// ============================================================================
//   SKY
// ============================================================================

  #define CUSTOM_SKY_BRIGHTNESS 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]
  #define SUN_ANGULAR_RADIUS 0.60 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.70 0.80 1.00 1.50 2.00]
  #define MOON_ANGULAR_RADIUS 0.55 // [0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.70 0.80 1.00 1.50 2.00]
  #define STARS
  #define STARS_INTENSITY 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]
  #define STARS_COVERAGE 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
  #define GALAXY
  #define GALAXY_INTENSITY 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00]
  #define AURORA
  #define AURORA_INTENSITY 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00]
  #define AURORA_CONDITIONS 0.55 // [0.00 0.10 0.20 0.30 0.40 0.50 0.55 0.60 0.70 0.80 0.90 1.00]
  #define ATMOSPHERE_SATURATION 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]

// ============================================================================
//   CLOUDS  (each layer can be disabled independently)
// ============================================================================

  #define CLOUDS
  #define CLOUDS_SCALE 1.00 // [0.50 0.75 1.00 1.25 1.50 2.00 3.00]
  #define CLOUDS_WIND_SPEED 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00 4.00]
  #define CLOUDS_WIND_ANGLE 40.0 // [0.0 15.0 30.0 40.0 45.0 60.0 75.0 90.0 120.0 150.0 180.0 210.0 240.0 270.0 300.0 330.0]
  #define CLOUDS_COVERAGE_BIAS 0.00 // [-0.50 -0.40 -0.30 -0.20 -0.10 0.00 0.10 0.20 0.30 0.40 0.50]
  #define CLOUDS_SUN_ABSORPTION 0.90 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.50]
  #define CLOUDS_MULTIPLE_SCATTERING 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]

  #define CLOUDS_CUMULUS
  #define CLOUDS_CUMULUS_STEPS 40 // [12 16 20 24 32 40 48 64 80]
  #define CLOUDS_CUMULUS_LIGHT_STEPS 5 // [1 2 3 4 5 6 8 10]
  #define CLOUDS_CUMULUS_ALTITUDE 620.0 // [300.0 400.0 500.0 620.0 700.0 800.0 1000.0 1200.0 1500.0]
  #define CLOUDS_CUMULUS_THICKNESS 900.0 // [300.0 400.0 500.0 600.0 700.0 800.0 900.0 1100.0 1300.0 1600.0 2000.0]
  #define CLOUDS_CUMULUS_DENSITY 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
  #define CLOUDS_CUMULUS_COVERAGE 1.00 // [0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40]
  #define CLOUDS_CUMULUS_SIZE 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
  #define CLOUDS_CUMULUS_DETAIL 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]

  #define CLOUDS_CUMULUS_CONGESTUS
  #define CLOUDS_CONGESTUS_ALTITUDE 1400.0 // [900.0 1100.0 1300.0 1400.0 1600.0 1800.0 2000.0 2400.0]
  #define CLOUDS_CONGESTUS_THICKNESS 1600.0 // [600.0 900.0 1200.0 1600.0 2000.0 2400.0 3000.0]

  #define CLOUDS_ALTOCUMULUS
  #define CLOUDS_ALTOCUMULUS_STEPS 16 // [4 8 12 16 20 24 32]
  #define CLOUDS_ALTOCUMULUS_LIGHT_STEPS 4 // [1 2 3 4 5 6 8]
  #define CLOUDS_ALTOCUMULUS_ALTITUDE 2600.0 // [1400.0 1800.0 2200.0 2600.0 3000.0 3500.0 4200.0]
  #define CLOUDS_ALTOCUMULUS_THICKNESS 420.0 // [100.0 200.0 300.0 420.0 550.0 700.0 900.0]
  #define CLOUDS_ALTOCUMULUS_DENSITY 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
  #define CLOUDS_ALTOCUMULUS_COVERAGE 1.00 // [0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40]
  #define CLOUDS_ALTOCUMULUS_SIZE 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
  #define CLOUDS_ALTOCUMULUS_DETAIL 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]

  #define CLOUDS_CIRRUS
  #define CLOUDS_CIRRUS_STEPS 10 // [4 6 8 10 12 16 24]
  #define CLOUDS_CIRRUS_ALTITUDE 7200.0 // [4000.0 5000.0 6200.0 7200.0 8000.0 9000.0 10000.0]
  #define CLOUDS_CIRRUS_DENSITY 0.55 // [0.00 0.10 0.20 0.30 0.40 0.50 0.55 0.70 0.90 1.10 1.40]
  #define CLOUDS_CIRRUS_COVERAGE 1.00 // [0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40]
  #define CLOUDS_CIRRUS_SIZE 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
  #define CLOUDS_CIRRUS_CURL 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]

// ============================================================================
//   ATMOSPHERE / VOLUMETRICS
// ============================================================================

  #define VOLUMETRIC_LIGHTING
  #define VL_STEPS 20 // [4 6 8 10 12 14 16 20 24 32 48 64]
  #define VL_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 2.00]
  #define VL_MIE_G 0.72 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.65 0.70 0.72 0.75 0.80 0.85 0.90 0.95]
  #define VL_SUN_MULT 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
  #define VL_SHADOW_SAMPLES 5 // [1 2 3 4 5 6 8]
  #define VL_WATER_DENSITY 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]

  #define AIR_FOG
  #define AIR_FOG_DENSITY 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00]
  #define AIR_FOG_HEIGHT 0.02 // [0.005 0.01 0.015 0.02 0.03 0.04 0.05 0.07 0.10]
  #define AIR_FOG_RAIN_MULT 2.00 // [1.00 1.25 1.50 1.75 2.00 2.50 3.00 4.00]
  #define CAVE_FOG
  #define BORDER_FOG
  #define WATER_FOG
  #define WATER_ABSORPTION_R 0.35 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.50 0.60 0.80 1.00 1.50 2.00 3.00]
  #define WATER_ABSORPTION_G 0.08 // [0.00 0.02 0.04 0.06 0.08 0.10 0.15 0.20 0.30 0.40 0.50 0.75 1.00]
  #define WATER_ABSORPTION_B 0.04 // [0.00 0.01 0.02 0.03 0.04 0.05 0.07 0.10 0.15 0.20 0.30 0.50 0.75 1.00]
  #define WATER_SCATTERING 0.10 // [0.00 0.01 0.02 0.03 0.05 0.07 0.10 0.15 0.20 0.30 0.50]

// ============================================================================
//   MATERIALS
// ============================================================================

  #define RESOURCEPACK_SUPPORT 2 // [0 1 2] 0 = off, 1 = legacy specular, 2 = labPBR
  #define NORMAL_MAPPING
  #define SPECULAR_MAPPING
  #define POM
  #define POM_DEPTH 0.50 // [0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 1.00 1.25 1.50 2.00]
  #define POM_SAMPLES 24 // [8 12 16 24 32 48 64 96]
  #define POM_DISTANCE 32.0 // [8.0 16.0 24.0 32.0 48.0 64.0 96.0 128.0]
  #define EMISSION_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50 2.00 3.00 5.00]
  #define HARDCODED_SPECULAR
  #define HARDCODED_EMISSION
  #define HARDCODED_SSS
  #define RAIN_PUDDLES
  #define PUDDLE_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50]

// ============================================================================
//   REFLECTIONS
// ============================================================================

  #define REFLECTIONS 1 // [0 1 2] 0 = off, 1 = sky/environment only, 2 = SSR + environment
  #define SSR_STEPS 32 // [8 12 16 24 32 48 64 96]
  #define SSR_REFINEMENT_STEPS 5 // [0 2 3 4 5 6 8]
  #define SSR_THICKNESS 0.35 // [0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.50 0.75 1.00 1.50 2.00]
  #define SSR_ROUGHNESS 0.30 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.40 0.50 0.60 0.75 1.00]
  #define SSR_RAY_JITTER // stochastic SSR, resolved by TAA
  #define SSR_FADE_START 0.65 // [0.30 0.40 0.50 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95]
  #define SSR_MIN_ROUGHNESS 0.05 // [0.00 0.02 0.04 0.05 0.06 0.08 0.10 0.15 0.20]

// ============================================================================
//   WATER
// ============================================================================

  #define WATER_WAVES
  #define WATER_WAVE_ITERATIONS 5 // [1 2 3 4 5 6 7 8]
  #define WATER_WAVE_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50]
  #define WATER_WAVE_FREQUENCY 1.00 // [0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
  #define WATER_WAVE_SPEED 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00]
  #define WATER_WAVE_PERSISTENCE 0.50 // [0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80]
  #define WATER_WAVE_LACUNARITY 2.00 // [1.50 1.75 2.00 2.25 2.50 3.00]
  #define WATER_CAUSTICS
  #define WATER_CAUSTICS_INTENSITY 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50 2.00]
  #define WATER_REFRACTION
  #define WATER_REFRACTION_INTENSITY 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50]
  #define WATER_DISPLACEMENT
  #define BIOME_WATER_COLOR
  #define WATER_EDGE_HIGHLIGHT
  #define WATER_EDGE_HIGHLIGHT_INTENSITY 0.60 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

// ============================================================================
//   RAY TRACING / PATH TRACING
// ============================================================================

  #define RAY_TRACING 0 // [0 1 2 3] 0 = off, 1 = RT reflections, 2 = RT reflections + GI, 3 = full path tracing
  #define RT_SAMPLES_PER_PIXEL 1 // [1 2 3 4 6 8 12 16]
  #define RT_MAX_BOUNCES 3 // [1 2 3 4 5 6]
  #define RT_ROUGHNESS_CUTOFF 0.55 // [0.00 0.10 0.20 0.30 0.40 0.50 0.55 0.60 0.70 0.80 0.90 1.00]
  #define RT_GI_STRENGTH 1.00 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.20 1.40 1.60 1.80 2.00]
  #define RT_TEMPORAL_ACCUMULATION
  #define RT_ACCUMULATION_LIMIT 32 // [4 8 12 16 24 32 48 64 128]
  #define RT_DENOISE
  #define RT_DENOISE_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
  #define RT_SCREEN_SPACE_STEPS 48 // [16 24 32 48 64 96 128]
  #define RT_SUN_SOFT_SHADOWS

// ============================================================================
//   POST PROCESSING
// ============================================================================

  #define AUTO_EXPOSURE
  #define EXPOSURE_BIAS 0.00 // [-3.00 -2.50 -2.00 -1.75 -1.50 -1.25 -1.00 -0.75 -0.50 -0.25 0.00 0.25 0.50 0.75 1.00 1.25 1.50 1.75 2.00 2.50 3.00]
  #define EXPOSURE_MIN -4.00 // [-8.00 -7.00 -6.00 -5.00 -4.00 -3.00 -2.00 -1.00 0.00]
  #define EXPOSURE_MAX 4.00 // [0.00 1.00 2.00 3.00 4.00 5.00 6.00 7.00 8.00]
  #define EXPOSURE_SPEED 1.50 // [0.10 0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00 5.00]
  #define MANUAL_EXPOSURE 0.00 // [-8.00 -7.00 -6.00 -5.00 -4.00 -3.00 -2.00 -1.00 0.00 1.00 2.00 3.00 4.00 5.00 6.00 7.00 8.00]

  #define TONEMAP 0 // [0 1 2 3 4 5] 0 = Muon Filmic, 1 = ACES, 2 = Khronos Neutral, 3 = Uncharted 2, 4 = Reinhard, 5 = ACES punchy
  #define EXPOSURE_BRIGHTNESS 1.00 // [0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]

  #define BLOOM
  #define BLOOM_INTENSITY 0.12 // [0.00 0.02 0.04 0.06 0.08 0.10 0.12 0.14 0.16 0.18 0.20 0.25 0.30 0.40 0.50]
  #define BLOOM_THRESHOLD 0.90 // [0.00 0.20 0.40 0.60 0.80 0.90 1.00 1.20 1.50 2.00 3.00]
  #define BLOOM_SPREAD 1.00 // [0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]

  #define DOF
  #define DOF_INTENSITY 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]
  #define DOF_SAMPLES 32 // [8 12 16 24 32 48 64]
  #define DOF_FOCUS 0.00 // [-8.00 -7.00 -6.00 -5.00 -4.00 -3.00 -2.00 -1.00 0.00 1.00 2.00 3.00 4.00 5.00 6.00 7.00 8.00]
  #define DOF_RANGE 2.00 // [0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00 4.00 6.00]

  #define MOTION_BLUR
  #define MOTION_BLUR_INTENSITY 0.50 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00 1.25 1.50]
  #define MOTION_BLUR_SAMPLES 8 // [4 6 8 10 12 16 24]

  #define TAA
  #define TAA_CLIP_STRENGTH 1.00 // [0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
  #define TAA_HISTORY_WEIGHT 0.94 // [0.70 0.75 0.80 0.85 0.88 0.90 0.92 0.94 0.96 0.98]
  #define FXAA
  #define CAS
  #define CAS_INTENSITY 0.60 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]

  #define VIGNETTE
  #define VIGNETTE_INTENSITY 0.35 // [0.00 0.10 0.20 0.30 0.35 0.40 0.50 0.60 0.70 0.80 1.00]
  #define CHROMATIC_ABERRATION
  #define CHROMATIC_ABERRATION_INTENSITY 0.30 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.80 1.00]
  #define FILM_GRAIN
  #define FILM_GRAIN_INTENSITY 0.25 // [0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.60 0.80 1.00]
  #define CLARITY
  #define CLARITY_INTENSITY 0.25 // [0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.75 1.00]

  #define GRADE_BRIGHTNESS 1.00 // [0.60 0.70 0.80 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40]
  #define GRADE_CONTRAST 1.06 // [0.70 0.80 0.90 0.95 1.00 1.05 1.06 1.10 1.15 1.20 1.30 1.40 1.50]
  #define GRADE_SATURATION 1.10 // [0.00 0.20 0.40 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]
  #define GRADE_TEMPERATURE 0.04 // [-0.10 -0.08 -0.06 -0.04 -0.02 0.00 0.02 0.03 0.04 0.05 0.06 0.08 0.10]
  #define GRADE_TINT 0.00 // [-0.06 -0.04 -0.02 0.00 0.02 0.04 0.06]
  #define GRADE_HIGHLIGHT_WARMTH 0.35 // [0.00 0.10 0.20 0.30 0.35 0.40 0.50 0.60 0.70 0.80 1.00]
  #define GRADE_SHADOW_COOLNESS 0.25 // [0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.60 0.70 0.80 1.00]
  #define GRADE_ORANGE_BOOST 0.25 // [0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.75 1.00]
  #define GRADE_TEAL_BOOST 0.10 // [0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.75 1.00]
  #define GRADE_GREEN_BOOST 0.05 // [0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.75 1.00]
  #define GRADE_GREEN_HUE 0.00 // [-0.10 -0.05 0.00 0.05 0.10]
  #define GRADE_BLACK_LEVEL 0.00 // [0.00 0.01 0.02 0.03 0.04 0.05 0.07 0.10]
  #define PURKINJE_SHIFT
  #define PURKINJE_INTENSITY 0.50 // [0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 1.00]

// ============================================================================
//   HDR OUTPUT
// ============================================================================


// ============================================================================
//   COMPATIBILITY
// ============================================================================


// ============================================================================
//   MISC / DEBUG
// ============================================================================

  #define DEBUG_VIEW 0 // [0 1 2 3 4 5 6 7 8 9] 0 = off, 1 = albedo, 2 = normal, 3 = AO, 4 = shadows, 5 = volumetrics, 6 = clouds, 7 = RT radiance, 8 = roughness, 9 = light levels
  #define WHITE_WORLD // fullbright debug

#endif // SETTINGS_INCLUDED
