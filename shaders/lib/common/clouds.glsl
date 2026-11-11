/*
================================================================================

  Muon Shaders - lib/common/clouds.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Multi-layer volumetric clouds.

  Two layers share one density model and one lighting model:

    cumulus   a 640 m deep layer of Perlin-Worley base noise eroded by a
              high-frequency Worley volume, raymarched with height-dependent
              coverage so the tops round off and the bases flatten.
    cirrus    a thin, high, horizontally stretched layer that gives the sky
              depth without the cost of a second deep march.

  Weather coupling: coverage, thickness and the density floor all move with
  rainStrength and thunderStrength, so the same cloud field that looks like
  scattered cumulus in clear weather closes over into a storm deck in rain
  without any authored swap.

  The noise volumes are precomputed (tools/gen_noise.py); the shader only does
  trilinear fetches and the cover/erode remaps.

================================================================================
*/

#ifndef MUON_COMMON_CLOUDS_GLSL
#define MUON_COMMON_CLOUDS_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/noise.glsl"
#include "/lib/common/sampling.glsl"
#include "/lib/common/atmosphere.glsl"

// -----------------------------------------------------------------------------
//  Layout
// -----------------------------------------------------------------------------

const float MUON_CLOUD_WIND_ANGLE = CLOUD_WIND_ANGLE * MUON_DEG2RAD;
const float MUON_CIRRUS_ALTITUDE_MUL = 2.35;
const float MUON_CIRRUS_THICKNESS = 220.0;
const float MUON_CLOUD_LAYER_SCALE = 980.0;

// -----------------------------------------------------------------------------
//  Weather
// -----------------------------------------------------------------------------

struct MuonCloudWeather {
    float coverage;
    float density;
    float thickness;
    float bottom;
    vec3 wind;
    float detail_strength;
};

MuonCloudWeather muon_cloud_weather() {
    MuonCloudWeather w;

    float rain = muon_rain_strength();
    float thunder = muon_thunder_strength();

    /* Rain adds coverage first, then thickness - the visual order of a real
       weather front closing in. */
    w.coverage = muon_saturate(MUON_CLOUD_COVERAGE + rain * 0.24 + thunder * 0.12);
    w.density = MUON_CLOUD_DENSITY * (1.0 + rain * 0.55);
    w.thickness = MUON_CLOUD_THICKNESS * (1.0 + rain * 0.30);
    w.bottom = MUON_CLOUD_ALTITUDE;
    w.detail_strength = mix(0.35, 0.62, 1.0 - rain);

    float wind_speed = CLOUD_WIND_SPEED * (1.0 + rain * 0.85);
    vec2 wind_dir = vec2(cos(MUON_CLOUD_WIND_ANGLE), sin(MUON_CLOUD_WIND_ANGLE));
    float drift = muon_time_counter() * wind_speed * 6.0;
    w.wind = vec3(wind_dir.x * drift, 0.0, wind_dir.y * drift);

    return w;
}

// -----------------------------------------------------------------------------
//  Density field
// -----------------------------------------------------------------------------

/*
 * Height profile of the cumulus layer: rounded top, flat base, with a slightly
 * denser core so that light does not shine straight through thin cloud.
 */
float muon_cloud_height_gradient(float height_fraction) {
    float bottom = muon_smoothstep(0.0, 0.10, height_fraction);
    float top = 1.0 - muon_smoothstep(0.55, 1.0, height_fraction);
    return bottom * top;
}

float muon_cumulus_density(vec3 world_pos, MuonCloudWeather w) {
    float height_fraction = (world_pos.y - w.bottom) / max(w.thickness, 1.0);
    if (height_fraction <= 0.0 || height_fraction >= 1.0) {
        return 0.0;
    }

    float profile = muon_cloud_height_gradient(height_fraction);
    if (profile <= 0.001) {
        return 0.0;
    }

    float scale = MUON_CLOUD_LAYER_SCALE * CLOUD_SCALE;
    vec3 p = (world_pos + w.wind) / scale;

    /* Base shape: Perlin-Worley, gently domain-warped so the silhouettes are
       not obviously cellular. */
    vec3 warped = p + vec3(
        muon_cloud_base_noise(p * 0.61 + vec3(0.17, 0.41, 0.73)),
        muon_cloud_base_noise(p * 0.61 + vec3(0.52, 0.83, 0.29)),
        muon_cloud_base_noise(p * 0.61 + vec3(0.91, 0.11, 0.47))
    ) * 0.14;

    float base = muon_cloud_base_noise(warped);
    float coverage_height = muon_saturate(w.coverage * profile);
    float density = muon_remap(base, 1.0 - coverage_height, 1.0, 0.0, 1.0);

    /* Erosion: the detail volume eats the edges, which is what makes the
       cloud look sculpted rather than blobby. */
#if CLOUD_DETAIL_STEPS > 0
    if (density > 0.001) {
        vec3 detail_coord = (world_pos + w.wind * 1.35) / (scale * 0.14);
        float detail = muon_cloud_detail_noise(detail_coord);
        float erosion = muon_remap(detail, 1.0 - w.detail_strength, 1.0, 0.0, 1.0);
        density = max(density - erosion * 0.55, 0.0);
    }
#endif

    /* Powdery base: reduce density where the cloud is thin and low so that
       the underside reads as shaded rather than solid. */
    float powder = 1.0 - exp(-density * 4.0);
    density *= mix(1.0, powder, 0.35);

    return density * w.density;
}

float muon_cirrus_density(vec3 world_pos, MuonCloudWeather w) {
    float height = w.bottom * MUON_CIRRUS_ALTITUDE_MUL;
    float height_fraction = (world_pos.y - height) / MUON_CIRRUS_THICKNESS;
    if (height_fraction <= 0.0 || height_fraction >= 1.0) {
        return 0.0;
    }

    float profile = muon_cloud_height_gradient(height_fraction * 0.9 + 0.05);
    float scale = MUON_CLOUD_LAYER_SCALE * CLOUD_SCALE * 2.6;
    vec3 p = vec3(world_pos.x, world_pos.y * 3.0, world_pos.z) + w.wind * 2.2;
    p /= scale;

    float base = muon_cloud_base_noise(p * 1.7);
    float coverage = muon_saturate(0.30 + muon_rain_strength() * 0.20) * CLOUD_COVERAGE;
    float density = muon_remap(base, 1.0 - coverage, 1.0, 0.0, 1.0);

    return density * profile * 0.32 * w.density;
}

/* Density including both layers, used by the shadow march. */
float muon_cloud_density(vec3 world_pos, MuonCloudWeather w) {
    float cumulus = muon_cumulus_density(world_pos, w);
#if QUALITY > 0
    float cirrus = muon_cirrus_density(world_pos, w);
    return cumulus + cirrus;
#else
    return cumulus;
#endif
}

// -----------------------------------------------------------------------------
//  Lighting
// -----------------------------------------------------------------------------

/* Dual-lobe Henyey-Greenstein, the standard cloud phase function. */
float muon_cloud_phase(float cos_theta) {
    float forward = muon_mie_phase(cos_theta, 0.72);
    float backward = muon_mie_phase(cos_theta, -0.28);
    return mix(forward, backward, 0.30);
}

/*
 * Marches towards the light inside the cloud layer and returns the fraction
 * of light that reaches the sample. Six steps is enough because the density
 * gradient - not the absolute density - is what drives the look.
 */
float muon_cloud_light_transmittance(vec3 world_pos, MuonCloudWeather w, vec3 light_dir) {
    const int steps = 6;
    float step_size = w.thickness * 0.10;
    float optical_depth = 0.0;

    for (int i = 0; i < steps; i++) {
        vec3 p = world_pos + light_dir * (step_size * (float(i) + 0.5));
        optical_depth += muon_cumulus_density(p, w) * step_size;
    }

    return exp(-optical_depth * MUON_CLOUD_EXTINCTION * 0.12);
}

struct MuonCloudSample {
    vec3 scattering;
    float transmittance;
};

/*
 * Raymarches a ray against both cloud layers.
 *   origin       world-space ray origin (camera position)
 *   direction    unit ray direction
 *   max_distance how far to march (the sky pass uses the atmosphere shell)
 */
MuonCloudSample muon_cloud_raymarch(vec3 origin, vec3 direction, float max_distance, int steps) {
    MuonCloudSample result;
    result.scattering = vec3(0.0);
    result.transmittance = 1.0;

    MuonCloudWeather w = muon_cloud_weather();

    /* Intersect the cumulus slab. */
    float top = w.bottom + w.thickness;
    float cirrus_bottom = w.bottom * MUON_CIRRUS_ALTITUDE_MUL;
    float cirrus_top = cirrus_bottom + MUON_CIRRUS_THICKNESS;

    float t_bottom = muon_ray_plane_y(origin, direction, w.bottom);
    float t_top = muon_ray_plane_y(origin, direction, top);
    float t_cirrus_bottom = muon_ray_plane_y(origin, direction, cirrus_bottom);
    float t_cirrus_top = muon_ray_plane_y(origin, direction, cirrus_top);

    bool has_cumulus = t_bottom > 0.0 && t_top > 0.0;
    bool has_cirrus = t_cirrus_bottom > 0.0 && t_cirrus_top > 0.0;

    if (!has_cumulus && !has_cirrus) {
        return result;
    }

    vec3 light_dir = muon_direct_light_direction();
    vec3 light_color = muon_direct_light_color();
    float cos_theta = dot(direction, light_dir);
    float phase = muon_cloud_phase(cos_theta);

    vec3 ambient = muon_sky_ambient(vec3(0.0, 1.0, 0.0)) * CLOUD_AMBIENT_STRENGTH;
    vec3 ambient_ground = ambient * 0.35;

    float dither = muon_interleaved_gradient_noise(gl_FragCoord.xy);

    if (has_cumulus) {
        float start = min(t_bottom, t_top);
        float end = max(t_bottom, t_top);
        end = min(end, start + w.thickness * 2.2);
        end = min(end, max_distance);
        start = max(start, 0.0);

        if (start < end) {
            float step_size = (end - start) / float(steps);
            float jitter = dither * step_size;

            for (int i = 0; i < steps; i++) {
                vec3 p = origin + direction * (start + jitter + step_size * float(i));
                float density = muon_cumulus_density(p, w);
                if (density <= 0.002) {
                    continue;
                }

                float height_fraction = muon_saturate((p.y - w.bottom) / max(w.thickness, 1.0));
                float light_transmittance = muon_cloud_light_transmittance(p, w, light_dir);

                /* Multiple scattering approximation: a little light survives
                   even in the deepest part of the cloud. */
                light_transmittance = light_transmittance * 0.75 + 0.25;
                light_transmittance = pow(light_transmittance, 1.35);

                vec3 ambient_term = mix(ambient_ground, ambient, muon_saturate(height_fraction * 1.6));
                vec3 radiance = light_color * (light_transmittance * phase * MUON_CLOUD_SCATTER_ALBEDO)
                    + ambient_term * MUON_CLOUD_SCATTER_ALBEDO;

                float extinction = exp(-density * MUON_CLOUD_EXTINCTION * step_size);
                float sample_transmittance = 1.0 - extinction;
                result.scattering += radiance * sample_transmittance * result.transmittance;
                result.transmittance *= extinction;

                if (result.transmittance < 0.02) {
                    break;
                }
            }
        }
    }

    if (has_cirrus) {
        float start = min(t_cirrus_bottom, t_cirrus_top);
        float jitter = dither * ((max(t_cirrus_bottom, t_cirrus_top) - start) / 4.0);
        const int cirrus_steps = 4;
        float step_size = (max(t_cirrus_bottom, t_cirrus_top) - start) / float(cirrus_steps);

        for (int i = 0; i < cirrus_steps; i++) {
            vec3 p = origin + direction * (start + jitter + step_size * float(i));
            float density = muon_cirrus_density(p, w);
            if (density <= 0.001) {
                continue;
            }
            float extinction = exp(-density * MUON_CLOUD_EXTINCTION * step_size);
            vec3 radiance = light_color * (phase * 0.55 * MUON_CLOUD_SCATTER_ALBEDO)
                + ambient * 1.35 * MUON_CLOUD_SCATTER_ALBEDO;
            result.scattering += radiance * (1.0 - extinction) * result.transmittance;
            result.transmittance *= extinction;
        }
    }

    return result;
}

// -----------------------------------------------------------------------------
//  Cloud shadows on the ground
// -----------------------------------------------------------------------------

/*
 * Optical depth from a surface point towards the light, through the cloud
 * layer. Cheap and band-limited: eight steps over the layer are enough to
 * produce convincing drifting cloud shadows on the terrain.
 */
float muon_cloud_shadow(vec3 world_pos, vec3 light_dir) {
#if !defined CLOUD_SHADOWS
    return 1.0;
#else
    MuonCloudWeather w = muon_cloud_weather();

    /* Nothing to intersect if the light is not above the layer. */
    if (light_dir.y < 0.02) {
        return 1.0;
    }

    float top = w.bottom + w.thickness;
    float t_enter = (top - world_pos.y) / max(light_dir.y, 0.02);
    if (t_enter < 0.0) {
        return 1.0;
    }

    float optical_depth = 0.0;
    float step_size = w.thickness / 8.0;
    for (int i = 0; i < 8; i++) {
        vec3 p = world_pos + light_dir * (t_enter + step_size * (float(i) + 0.5));
        optical_depth += muon_cumulus_density(p, w) * step_size;
    }

    float transmittance = exp(-optical_depth * MUON_CLOUD_EXTINCTION * 0.018);
    return mix(1.0, transmittance, CLOUD_SHADOW_STRENGTH);
#endif
}

#endif // MUON_COMMON_CLOUDS_GLSL
