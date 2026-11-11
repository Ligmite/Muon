/*
================================================================================

  Muon Shaders - lib/common/atmosphere.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Single-scattering atmosphere.

  Muon uses a Rayleigh + Mie + ozone model integrated on the GPU. The planet is
  deliberately compressed relative to reality: at Minecraft's scale a
  physically sized atmosphere produces no visible aerial perspective within a
  512 block render distance, so the model uses a 24 km planet with 420 m and
  90 m scale heights. The result keeps the physically correct *shape* of the
  effect - blue zenith, warm horizon, reddening sun near the horizon, forward
  Mie glow - but at a scale that reads correctly when standing on a hill.

  The model is band-limited on purpose: `ATMOSPHERE_HAZE` scales density so the
  default look stays crisp rather than milky.

================================================================================
*/

#ifndef MUON_COMMON_ATMOSPHERE_GLSL
#define MUON_COMMON_ATMOSPHERE_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/common/math.glsl"
#include "/lib/common/color.glsl"
#include "/lib/common/constants.glsl"

// -----------------------------------------------------------------------------
//  Model
// -----------------------------------------------------------------------------

const float MUON_ATMO_PLANET_RADIUS = 24000.0;   // metres
const float MUON_ATMO_HEIGHT = 5200.0;           // metres
const float MUON_ATMO_RAYLEIGH_H = 420.0;        // metres
const float MUON_ATMO_MIE_H = 90.0;              // metres
const float MUON_ATMO_OZONE_CENTER = 2600.0;
const float MUON_ATMO_OZONE_WIDTH = 900.0;

const float MUON_ATMO_RAYLEIGH_BETA = 3.6e-4;   // 1/m, tuned for a 420 m scale height
const float MUON_ATMO_MIE_BETA = 4.2e-4;        // 1/m, tuned for a 90 m scale height
const float MUON_ATMO_OZONE_BETA = 6.0e-5;      // 1/m at the ozone layer peak

/* Relative spectral weights (Rec.709) of Rayleigh scattering. */
const vec3 MUON_ATMO_RAYLEIGH_RGB = vec3(0.195, 0.415, 0.850);
const vec3 MUON_ATMO_OZONE_RGB = vec3(0.058, 0.135, 0.055);
const float MUON_ATMO_MIE_G = 0.76;

// -----------------------------------------------------------------------------
//  Ray geometry
// -----------------------------------------------------------------------------

/* Returns (t_near, t_far); t_far < 0 means the ray misses the shell. */
vec2 muon_atmosphere_intersect(vec3 origin, vec3 direction) {
    float radius = MUON_ATMO_PLANET_RADIUS + MUON_ATMO_HEIGHT;
    float b = dot(origin, direction);
    float c = dot(origin, origin) - radius * radius;
    float discriminant = b * b - c;
    if (discriminant < 0.0) {
        return vec2(-1.0);
    }
    float root = sqrt(discriminant);
    return vec2(-b - root, -b + root);
}

float muon_atmosphere_density_rayleigh(float altitude) {
    return exp(-max(altitude, 0.0) / MUON_ATMO_RAYLEIGH_H);
}

float muon_atmosphere_density_mie(float altitude) {
    return exp(-max(altitude, 0.0) / MUON_ATMO_MIE_H);
}

float muon_atmosphere_density_ozone(float altitude) {
    float t = (altitude - MUON_ATMO_OZONE_CENTER) / MUON_ATMO_OZONE_WIDTH;
    return max(0.0, 1.0 - t * t);
}

// -----------------------------------------------------------------------------
//  Phase functions
// -----------------------------------------------------------------------------

float muon_rayleigh_phase(float cos_theta) {
    return (3.0 / (16.0 * MUON_PI)) * (1.0 + cos_theta * cos_theta);
}

float muon_mie_phase(float cos_theta, float g) {
    float g2 = g * g;
    float num = (1.0 - g2);
    float denom = 4.0 * MUON_PI * pow(max(1.0 + g2 - 2.0 * g * cos_theta, 1.0e-4), 1.5);
    return num / denom;
}

/* Dual-lobe Mie phase: a wide lobe for the glow and a tight one for the disc. */
float muon_mie_phase_dual(float cos_theta) {
    return mix(muon_mie_phase(cos_theta, 0.76), muon_mie_phase(cos_theta, 0.92), 0.35);
}

// -----------------------------------------------------------------------------
//  Optical depth
// -----------------------------------------------------------------------------

/*
 * Integrates optical depth from `origin` along `direction` for the given
 * number of steps. Returns (rayleigh, mie, ozone) in unscaled units.
 */
vec3 muon_atmosphere_optical_depth(vec3 origin, vec3 direction, float distance, int steps) {
    vec3 total = vec3(0.0);
    float step_size = distance / float(steps);
    for (int i = 0; i < steps; i++) {
        vec3 p = origin + direction * (step_size * (float(i) + 0.5));
        float altitude = length(p) - MUON_ATMO_PLANET_RADIUS;
        total.x += muon_atmosphere_density_rayleigh(altitude) * step_size;
        total.y += muon_atmosphere_density_mie(altitude) * step_size;
        total.z += muon_atmosphere_density_ozone(altitude) * step_size;
    }
    return total;
}

vec3 muon_atmosphere_extinction(vec3 optical_depth, float haze) {
    vec3 rayleigh = MUON_ATMO_RAYLEIGH_RGB * (MUON_ATMO_RAYLEIGH_BETA * optical_depth.x * haze);
    vec3 mie = vec3(MUON_ATMO_MIE_BETA * optical_depth.y * haze * 1.1);
    vec3 ozone = MUON_ATMO_OZONE_RGB * (MUON_ATMO_OZONE_BETA * optical_depth.z);
    return exp(-(rayleigh + mie + ozone));
}

// -----------------------------------------------------------------------------
//  Sun and moon colour
// -----------------------------------------------------------------------------

/* Transmittance between the eye and the sun, in eye space (world origin). */
vec3 muon_sun_transmittance(vec3 sun_direction, float haze) {
    vec3 origin = vec3(0.0, MUON_ATMO_PLANET_RADIUS + muon_eye_altitude(), 0.0);
    vec2 hit = muon_atmosphere_intersect(origin, sun_direction);
    if (hit.y <= 0.0) {
        return vec3(0.0);
    }
    vec3 optical = muon_atmosphere_optical_depth(origin, sun_direction, hit.y, 6);
    return muon_atmosphere_extinction(optical, haze);
}

/* Colour of direct sunlight after atmospheric extinction. */
vec3 muon_sun_color() {
    float haze = ATMOSPHERE_HAZE * HAZE_QUALITY_FACTOR;
    vec3 transmittance = muon_sun_transmittance(muon_sun_direction(), haze);
    float visibility = muon_smoothstep(-0.06, 0.02, muon_sun_direction().y);
    return MUON_SUN_TINT * transmittance * visibility * (MUON_SUN_INTENSITY * SUNLIGHT);
}

vec3 muon_moon_color() {
    float phase = muonFrame.moonDirection.w;
    /* Waning and waxing crescents are dimmer than a full moon. */
    float phase_brightness = 1.0 - abs(phase - 4.0) / 4.0 * 0.55;
    float visibility = muon_smoothstep(-0.04, 0.05, muon_moon_direction().y);
    float day_fade = 1.0 - muon_smoothstep(-0.02, 0.14, muon_sun_direction().y);
    return MUON_MOON_TINT * (MUON_MOON_INTENSITY * MOONLIGHT * phase_brightness * visibility * day_fade);
}

/* The light that actually reaches the world: sun by day, moon by night. */
vec3 muon_direct_light_color() {
    return muon_sun_angle() < 0.5 ? muon_sun_color() : muon_moon_color();
}

vec3 muon_direct_light_direction() {
    return muon_sun_angle() < 0.5 ? muon_sun_direction() : muon_moon_direction();
}

// -----------------------------------------------------------------------------
//  Sky radiance
// -----------------------------------------------------------------------------

/*
 * Single-scattering sky radiance for a view direction, integrated from the eye
 * out to the top of the atmosphere. `steps` trades quality for speed: the sky
 * pass can afford 12-16, the fog pass 4-6.
 */
vec3 muon_sky_radiance(vec3 view_direction, int steps) {
    vec3 origin = vec3(0.0, MUON_ATMO_PLANET_RADIUS + muon_eye_altitude(), 0.0);
    vec2 hit = muon_atmosphere_intersect(origin, view_direction);
    if (hit.y <= 0.0) {
        return vec3(0.0);
    }

    float haze = ATMOSPHERE_HAZE * HAZE_QUALITY_FACTOR;
    float max_distance = min(hit.y, 40000.0);
    float step_size = max_distance / float(steps);

    vec3 sun_direction = muon_sun_direction();
    vec3 sun_intensity = muon_sun_color();
    float cos_theta = dot(view_direction, sun_direction);
    float rayleigh_phase = muon_rayleigh_phase(cos_theta);
    float mie_phase = muon_mie_phase_dual(cos_theta);

    vec3 accumulated_rayleigh = vec3(0.0);
    vec3 accumulated_mie = vec3(0.0);
    vec3 optical_view = vec3(0.0);

    for (int i = 0; i < steps; i++) {
        float t = step_size * (float(i) + 0.5);
        vec3 p = origin + view_direction * t;
        float altitude = max(length(p) - MUON_ATMO_PLANET_RADIUS, 0.0);

        float density_r = muon_atmosphere_density_rayleigh(altitude);
        float density_m = muon_atmosphere_density_mie(altitude);
        float density_o = muon_atmosphere_density_ozone(altitude);

        optical_view += vec3(density_r, density_m, density_o) * step_size;

        /* Light travelling from this sample towards the sun. */
        vec2 sun_hit = muon_atmosphere_intersect(p, sun_direction);
        if (sun_hit.y <= 0.0) {
            continue;
        }
        vec3 optical_sun = muon_atmosphere_optical_depth(p, sun_direction, sun_hit.y, 3);
        vec3 transmittance = muon_atmosphere_extinction(optical_sun + optical_view, haze);

        accumulated_rayleigh += density_r * transmittance * step_size;
        accumulated_mie += density_m * transmittance * step_size;
    }

    vec3 rayleigh = MUON_ATMO_RAYLEIGH_RGB * (MUON_ATMO_RAYLEIGH_BETA * haze) * accumulated_rayleigh * rayleigh_phase;
    vec3 mie = vec3(MUON_ATMO_MIE_BETA * haze * ATMOSPHERE_MIE) * accumulated_mie * mie_phase;

    vec3 radiance = (rayleigh + mie) * sun_intensity;

    /* Night side: a dim, cool sky so that shadows are never pure black. */
    float night = 1.0 - muon_saturate(muon_sun_direction().y * 6.0 + 0.35);
    vec3 night_sky = vec3(0.0016, 0.0026, 0.0062) * night;
    radiance += night_sky * muon_saturate(view_direction.y * 0.5 + 0.6);

    return radiance;
}

/*
 * Fast ambient approximation for surfaces. Two cheap transmittance evaluations
 * give the zenith and horizon tint; the hemisphere blend is analytic. This is
 * what the deferred stage uses for every lit pixel, so it must stay cheap.
 */
vec3 muon_sky_ambient(vec3 normal) {
    float up = muon_saturate(normal.y * 0.5 + 0.5);
    float ground = muon_saturate(-normal.y);

    vec3 sun_transmittance = muon_sun_transmittance(vec3(0.0, 1.0, 0.0), ATMOSPHERE_HAZE * HAZE_QUALITY_FACTOR);
    vec3 horizon_transmittance = muon_sun_transmittance(normalize(vec3(muon_sun_direction().x, 0.04, muon_sun_direction().z)), ATMOSPHERE_HAZE * HAZE_QUALITY_FACTOR);

    vec3 zenith = vec3(0.20, 0.38, 0.82) * sun_transmittance;
    vec3 horizon = vec3(0.62, 0.66, 0.72) * horizon_transmittance;

    vec3 ambient = mix(horizon, zenith, pow(up, 0.75));
    ambient *= MUON_SUN_INTENSITY * 0.055;

    /* Bounce from the ground adds a warm, low-frequency term. */
    vec3 ground_bounce = vec3(0.16, 0.13, 0.10) * sun_transmittance * MUON_SUN_INTENSITY * 0.012;
    ambient += ground_bounce * ground * SKY_GROUND_TINT;

    vec3 moon_ambient = vec3(0.006, 0.010, 0.022) * (1.0 - muon_saturate(muon_sun_direction().y * 4.0 + 0.4));
    ambient += moon_ambient;

    return ambient * AMBIENT_STRENGTH;
}

// -----------------------------------------------------------------------------
//  Aerial perspective
// -----------------------------------------------------------------------------

struct MuonFogSample {
    vec3 inscatter;
    vec3 transmittance;
};

/*
 * Analytic fog for the post-lighting stages and the translucent pass. The
 * expensive volumetric pass in lib/common/volumetric.glsl supersedes this when
 * enabled; this function is the fallback and the far-field limit.
 */
MuonFogSample muon_atmosphere_fog(vec3 view_direction, float distance) {
    MuonFogSample result;
    result.inscatter = vec3(0.0);
    result.transmittance = vec3(1.0);

#if defined ATMOSPHERE
    float haze = ATMOSPHERE_HAZE * HAZE_QUALITY_FACTOR * MUON_FOG_STRENGTH;
    if (haze * distance < 1.0e-4) {
        return result;
    }

    vec3 origin = vec3(0.0, MUON_ATMO_PLANET_RADIUS + muon_eye_altitude(), 0.0);
    vec3 direction = normalize(view_direction);
    float clamped = min(distance, MUON_ATMO_HEIGHT * 0.85);
    vec3 optical = muon_atmosphere_optical_depth(origin, direction, clamped, 6);
    vec3 transmittance = muon_atmosphere_extinction(optical, haze);

    vec3 sun_transmittance = muon_sun_transmittance(muon_sun_direction(), haze);
    float cos_theta = dot(direction, muon_sun_direction());
    float phase = muon_mie_phase_dual(cos_theta);

    vec3 inscatter = (vec3(0.24, 0.42, 0.85) * 0.35 + MUON_SUN_TINT * phase) * sun_transmittance;
    inscatter *= (MUON_SUN_INTENSITY * 0.006) * (1.0 - transmittance);

    result.inscatter = inscatter;
    result.transmittance = transmittance;
#endif

    return result;
}

#endif // MUON_COMMON_ATMOSPHERE_GLSL
