/*
================================================================================

  Muon Shaders - lib/uniforms/settings.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  The compile-time half of Muon's uniform discipline.

  User options are compile-time by nature: Iris recompiles the pack when an
  option changes. In SPIR-V/WGSL the correct equivalent is a specialisation
  constant, not a uniform buffer, so this header mirrors `settings.glsl` into
  typed, named constants that the feature libraries consume.

  Mapping for a native backend:

      const int MUON_GTAO_STEPS = 6;    ->    @id(3) override gtao_steps: i32 = 6;

  Keeping them here means a backend port rewrites one file instead of hunting
  magic numbers across every pass.

================================================================================
*/

#ifndef MUON_UNIFORMS_SETTINGS_GLSL
#define MUON_UNIFORMS_SETTINGS_GLSL

// --- shadows ---------------------------------------------------------------

const bool MUON_SHADOWS_ENABLED = true;
const int MUON_SHADOW_SAMPLES = SHADOW_SAMPLE_COUNT;
const float MUON_SHADOW_SOFTNESS = PCSS_SOFTNESS;

// --- ambient occlusion -----------------------------------------------------

#if defined GTAO
const bool MUON_GTAO_ENABLED = true;
#else
const bool MUON_GTAO_ENABLED = false;
#endif

#if defined SSAO
const bool MUON_SSAO_ENABLED = true;
#else
const bool MUON_SSAO_ENABLED = false;
#endif

const int MUON_AO_SLICES = AO_SLICES;
const int MUON_AO_STEPS = AO_STEPS;
const float MUON_AO_RADIUS = GTAO_RADIUS;
const float MUON_AO_STRENGTH = GTAO_STRENGTH;

// --- sky and clouds --------------------------------------------------------

const int MUON_CLOUD_STEPS = CLOUD_PRIMARY_STEPS;
const int MUON_CLOUD_LIGHT_STEPS = CLOUD_LIGHTING_STEPS;
const float MUON_CLOUD_ALTITUDE = CLOUD_ALTITUDE;
const float MUON_CLOUD_THICKNESS = CLOUD_THICKNESS;
const float MUON_CLOUD_COVERAGE = CLOUD_COVERAGE;
const float MUON_CLOUD_DENSITY = CLOUD_DENSITY;
const float MUON_CLOUD_SCALE = CLOUD_SCALE;
const float MUON_CLOUD_EXTINCTION = 12.0;
const float MUON_CLOUD_SCATTER_ALBEDO = 0.94;

const int MUON_FOG_STEPS = VOLUMETRIC_STEPS;
const float MUON_FOG_STRENGTH = FOG_STRENGTH;
const float MUON_FOG_RAIN_STRENGTH = FOG_RAIN_STRENGTH;

const int MUON_GODRAY_STEPS = GOD_RAYS_STEPS;
const float MUON_GODRAY_STRENGTH = GOD_RAYS_STRENGTH;

// --- water -----------------------------------------------------------------

const int MUON_WATER_WAVE_COUNT = WATER_WAVE_ITERATIONS;
const float MUON_WATER_WAVE_STRENGTH = WATER_WAVE_STRENGTH * WATER_WAVE_HEIGHT;
const float MUON_WATER_WAVE_SPEED = WATER_WAVE_SPEED;
const vec3 MUON_WATER_ABSORPTION = vec3(
    WATER_ABSORPTION_R,
    WATER_ABSORPTION_G,
    WATER_ABSORPTION_B
);
const float MUON_WATER_SCATTERING = WATER_SCATTERING;
const float MUON_WATER_REFRACTION = WATER_REFRACTION_STRENGTH;
const float MUON_WATER_CAUSTICS = WATER_CAUSTICS_STRENGTH;
const float MUON_WATER_REFLECTION = WATER_REFLECTION_STRENGTH;

// --- materials -------------------------------------------------------------

const int MUON_POM_SAMPLES = POM_SAMPLES;
const int MUON_POM_REFINE_STEPS = POM_REFINE_STEPS;
const int MUON_POM_SHADOW_SAMPLES = POM_SHADOW_SAMPLES;
const float MUON_POM_DEPTH = POM_DEPTH;
const float MUON_POM_DISTANCE = POM_DISTANCE;
const float MUON_EMISSION_STRENGTH = EMISSION_STRENGTH;
const float MUON_HARDCODED_F0 = HARDCODED_F0_VALUE;

// --- reflections -----------------------------------------------------------

const int MUON_SSR_STEPS = SSR_STEPS;
const int MUON_SSR_REFINE_STEPS = SSR_REFINE_STEPS;
const float MUON_SSR_MAX_DISTANCE = SSR_MAX_DISTANCE;
const float MUON_SSR_STRENGTH = SSR_STRENGTH;

// --- global illumination ---------------------------------------------------

const int MUON_RTGI_BOUNCES = RTGI_BOUNCES;
const int MUON_RTGI_SAMPLES = RTGI_SAMPLES;
const int MUON_RTGI_STEPS = RTGI_STEPS;
const float MUON_RTGI_RADIUS = RTGI_RADIUS;
const float MUON_RTGI_STRENGTH = RTGI_STRENGTH;

// --- post ------------------------------------------------------------------

const int MUON_DOF_SAMPLES = DOF_SAMPLES;
const float MUON_DOF_APERTURE = DOF_APERTURE;
const float MUON_DOF_FOCUS = DOF_FOCUS;

const int MUON_EXPOSURE_LUMA_STEPS = EXPOSURE_LUMA_STEPS;
const float MUON_EXPOSURE_SPEED = EXPOSURE_SPEED;

const float MUON_BLOOM_THRESHOLD = BLOOM_THRESHOLD;
const float MUON_BLOOM_STRENGTH = BLOOM_STRENGTH;
const float MUON_BLOOM_RADIUS = BLOOM_RADIUS;

// --- debug -----------------------------------------------------------------

const int MUON_DEBUG_VIEW = DEBUG_VIEW;

#endif // MUON_UNIFORMS_SETTINGS_GLSL
