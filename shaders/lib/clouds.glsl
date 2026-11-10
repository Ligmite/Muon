/*
================================================================================

  Muon Shaders
  lib/clouds.glsl - layered volumetric clouds

  Four independent layers, each raymarched inside its own altitude slab:

    cumulus            low, dense, self-shadowing towers
    cumulus congestus  tall towers with anvil tops
    altocumulus        mid level, small cellular elements
    cirrus             high, thin, streak-like, no self-shadowing

  Lighting is Beer-Lambert with a powder term and a 3-octave multiple
  scattering approximation. Every layer can be disabled from the settings.

================================================================================
*/

#if !defined MUON_CLOUDS
#define MUON_CLOUDS

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/noise.glsl"
#include "/lib/brdf.glsl"
#include "/lib/atmosphere.glsl"

// ------------------------------
//   Weather / coverage fields
// ------------------------------

// Large scale 2D coverage. Returns [0, 1] where 1 is fully overcast.
float cloud_coverage(vec2 world_xz) {
    float wind_angle = radians_f(CLOUDS_WIND_ANGLE);
    vec2 wind_dir = vec2(cos(wind_angle), sin(wind_angle));

    vec2 p = (world_xz + wind_dir * frameTimeCounter * 2.0 * CLOUDS_WIND_SPEED) * 0.00021 * CLOUDS_SCALE;

    float n = fbm(p, 3);
    n = n * 0.85 + 0.15;

    // Rain pushes coverage towards overcast
    float coverage = n + CLOUDS_COVERAGE_BIAS + rainStrength * 0.35;

    return clamp01(coverage);
}

// ------------------------------
//   Layer density functions
// ------------------------------

// Shared shape: a coverage-thresholded FBM with value-noise erosion
float cloud_shape(vec3 p, float coverage, float detail) {
    float shape = fbm(p, 3);

    float threshold = 1.0 - coverage;
    float density = smoothstep(threshold, threshold + 0.25, shape);

    if (density <= 0.0) return 0.0;

    // Erode the edges with a higher frequency field. This is what makes the
    // cloud silhouettes look billowy instead of smooth blobs.
    float erosion = value_noise(p * 4.3 + vec3(0.0, frameTimeCounter * 0.02, 0.0));
    density -= erosion * 0.28 * detail;
    density = max0(density);

    return clamp01(density * 2.2);
}

float cumulus_density(vec3 world_pos, float coverage) {
#ifdef CLOUDS_CUMULUS
    float base = CLOUDS_CUMULUS_ALTITUDE;
    float top = base + CLOUDS_CUMULUS_THICKNESS;

    if (world_pos.y < base || world_pos.y > top) return 0.0;

    float height_fraction = (world_pos.y - base) / CLOUDS_CUMULUS_THICKNESS;

    // Rounded bottom, tapered top
    float vertical = smoothstep(0.0, 0.12, height_fraction)
        * (1.0 - smoothstep(0.55, 1.0, height_fraction));

    if (vertical <= 0.0) return 0.0;

    vec3 p = world_pos * 0.0022 * CLOUDS_SCALE / max(CLOUDS_CUMULUS_SIZE, 0.1);
    p.xz += vec2(value_noise(p * 0.7), value_noise(p * 0.7 + 11.0)) * 0.4;

    float density = cloud_shape(p, coverage * CLOUDS_CUMULUS_COVERAGE, CLOUDS_CUMULUS_DETAIL);

    return density * vertical * CLOUDS_CUMULUS_DENSITY;
#else
    return 0.0;
#endif
}

float congestus_density(vec3 world_pos, float coverage) {
#ifdef CLOUDS_CUMULUS_CONGESTUS
    float base = CLOUDS_CONGESTUS_ALTITUDE;
    float top = base + CLOUDS_CONGESTUS_THICKNESS;

    if (world_pos.y < base || world_pos.y > top) return 0.0;

    float height_fraction = (world_pos.y - base) / CLOUDS_CONGESTUS_THICKNESS;

    float vertical = smoothstep(0.0, 0.10, height_fraction)
        * (1.0 - smoothstep(0.70, 1.0, height_fraction));

    // Anvil: widen near the top
    float anvil = smoothstep(0.65, 0.95, height_fraction);
    vertical *= mix(1.0, 1.6, anvil);

    if (vertical <= 0.0) return 0.0;

    vec3 p = world_pos * 0.0016 * CLOUDS_SCALE / max(CLOUDS_CUMULUS_SIZE, 0.1);
    p.xz += vec2(value_noise(p * 0.6), value_noise(p * 0.6 + 7.0)) * 0.5;

    // Congestus needs larger coverage to exist at all; it is a rarer cloud
    float local_coverage = clamp01((coverage - 0.45) * 1.6);

    float density = cloud_shape(p, local_coverage * CLOUDS_CUMULUS_COVERAGE, CLOUDS_CUMULUS_DETAIL);

    return density * vertical * CLOUDS_CUMULUS_DENSITY * 1.15;
#else
    return 0.0;
#endif
}

float altocumulus_density(vec3 world_pos, float coverage) {
#ifdef CLOUDS_ALTOCUMULUS
    float base = CLOUDS_ALTOCUMULUS_ALTITUDE;
    float top = base + CLOUDS_ALTOCUMULUS_THICKNESS;

    if (world_pos.y < base || world_pos.y > top) return 0.0;

    float height_fraction = (world_pos.y - base) / CLOUDS_ALTOCUMULUS_THICKNESS;
    float vertical = smoothstep(0.0, 0.25, height_fraction)
        * (1.0 - smoothstep(0.75, 1.0, height_fraction));

    if (vertical <= 0.0) return 0.0;

    // Cellular elements
    vec3 p = world_pos * 0.0045 * CLOUDS_SCALE / max(CLOUDS_ALTOCUMULUS_SIZE, 0.1);

    vec2 cells = worley_f1_f2(p);
    float cell_edge = 1.0 - smoothstep(0.0, 0.35, cells.y - cells.x);

    float shape = value_noise(p * 1.6);
    float local = clamp01((coverage - 0.30) * 1.4) * CLOUDS_ALTOCUMULUS_COVERAGE;

    float density = smoothstep(1.0 - local, 1.0 - local + 0.2, cell_edge * 0.6 + shape * 0.4);

    density *= mix(1.0, 0.75 + 0.5 * value_noise(p * 3.1), CLOUDS_ALTOCUMULUS_DETAIL);

    return density * vertical * CLOUDS_ALTOCUMULUS_DENSITY * 0.55;
#else
    return 0.0;
#endif
}

// Cirrus is a 2D field evaluated on a fixed altitude plane
float cirrus_density(vec3 world_pos, float coverage) {
#ifdef CLOUDS_CIRRUS
    vec3 p = world_pos * 0.00055 * CLOUDS_SCALE / max(CLOUDS_CIRRUS_SIZE, 0.1);

    // Streaks: stretch along one axis and warp
    p.xz *= vec2(0.35, 1.6);
    p.x += value_noise(p * 1.7) * CLOUDS_CIRRUS_CURL;
    p.z += value_noise(p * 1.4 + 3.0) * CLOUDS_CIRRUS_CURL * 0.5;

    float shape = ridged_fbm(p, 4);
    float local = clamp01((coverage - 0.15) * 1.3) * CLOUDS_CIRRUS_COVERAGE;

    return smoothstep(1.0 - local, 1.0 - local + 0.15, shape) * CLOUDS_CIRRUS_DENSITY;
#else
    return 0.0;
#endif
}

// --------------------------
//   Density / shadow queries
// --------------------------

float cloud_density(vec3 world_pos, float coverage, bool include_high_layers) {
    float density = cumulus_density(world_pos, coverage);
    density += congestus_density(world_pos, coverage);

    if (include_high_layers) {
        density += altocumulus_density(world_pos, coverage);
        density += cirrus_density(world_pos, coverage) * 0.4;
    }

    return density;
}

// -----------------------
//   Ray / slab intersect
// -----------------------

bool slab_intersect(vec3 ro, vec3 rd, float y0, float y1, float max_dist, out float t0, out float t1) {
    t0 = 0.0;
    t1 = max_dist;

    if (abs(rd.y) < 1e-5) {
        if (ro.y < y0 || ro.y > y1) return false;
        return true;
    }

    float inv = 1.0 / rd.y;
    float ta = (y0 - ro.y) * inv;
    float tb = (y1 - ro.y) * inv;

    t0 = max(min(ta, tb), 0.0);
    t1 = min(max(ta, tb), max_dist);

    return t1 > t0;
}

// -----------------------
//   Cloud lighting
// -----------------------

// Optical depth towards the sun inside the cumulus slab
float sun_optical_depth(vec3 pos, vec3 sun_dir, float coverage, int steps) {
    float base = CLOUDS_CUMULUS_ALTITUDE;
    float thickness = CLOUDS_CUMULUS_THICKNESS;

    float step_size = thickness * 0.55 / float(steps);

    float od = 0.0;
    vec3 p = pos;

    for (int i = 0; i < steps; i++) {
        p += sun_dir * step_size;
        if (p.y < base) break;
        od += cloud_density(p, coverage, false) * step_size;
    }

    return od;
}

vec3 cloud_sun_light(
    vec3 pos,
    vec3 sun_dir,
    vec3 sun_color,
    float coverage,
    int steps
) {
    float od = sun_optical_depth(pos, sun_dir, coverage, steps);

    float beer = exp(-od * CLOUDS_SUN_ABSORPTION * 1.6);
    float powder = 1.0 - exp(-od * 0.7);

    // Multiple scattering: three octaves of attenuated light
    float ms = 0.0;
    float attenuation = 1.0;
    float od_scale = 1.0;
    for (int i = 0; i < 3; i++) {
        ms += exp(-od * od_scale) * attenuation;
        attenuation *= 0.5;
        od_scale *= 0.45;
    }
    ms *= CLOUDS_MULTIPLE_SCATTERING / 1.75;

    return sun_color * (beer * powder + ms * 0.35) * 0.9;
}

// ----------------------
//   Main march
// ----------------------

struct CloudResult {
    vec3 scatter;      // premultiplied in-scatter
    float transmittance;
    float distance;    // distance to the first significant density
};

CloudResult march_clouds(
    vec3 ray_origin,
    vec3 ray_dir,
    float max_distance,
    vec3 sun_dir,
    vec3 sun_color,
    float dither
) {
    CloudResult result;
    result.scatter = vec3(0.0);
    result.transmittance = 1.0;
    result.distance = max_distance;

    float coverage = cloud_coverage(ray_origin.xz + ray_dir.xz * 100.0);

    // ---- Cirrus (highest, marched first so it ends up behind) ----
#ifdef CLOUDS_CIRRUS
    {
        float t0;
        float t1;
        if (slab_intersect(ray_origin, ray_dir, CLOUDS_CIRRUS_ALTITUDE, CLOUDS_CIRRUS_ALTITUDE + 60.0, max_distance, t0, t1)) {
            float step_size = (t1 - t0) / float(CLOUDS_CIRRUS_STEPS);
            vec3 inscatter = vec3(0.0);
            float transmittance = 1.0;

            vec3 ambient = sky_gradient(vec3(0.0, 1.0, 0.0), sun_dir) * 0.5;

            for (int i = 0; i < CLOUDS_CIRRUS_STEPS; i++) {
                float t = t0 + (float(i) + dither) * step_size;
                vec3 pos = ray_origin + ray_dir * t;

                float density = cirrus_density(pos, coverage);
                if (density <= 0.0) continue;

                float od = density * 900.0;
                float phase = phase_cloud(dot(sun_dir, -ray_dir), 0.55, 0.1);
                vec3 light = sun_color * exp(-od * 0.6) * phase * 0.8 + ambient;

                inscatter += light * density * transmittance * step_size * 6.0;
                transmittance *= exp(-density * step_size * 0.35);

                if (transmittance < 0.01) break;
            }

            result.scatter = inscatter;
            result.transmittance = transmittance;
            result.distance = t0;
        }
    }
#endif

    // ---- Altocumulus ----
#ifdef CLOUDS_ALTOCUMULUS
    {
        float t0;
        float t1;
        float top = CLOUDS_ALTOCUMULUS_ALTITUDE + CLOUDS_ALTOCUMULUS_THICKNESS;
        if (slab_intersect(ray_origin, ray_dir, CLOUDS_ALTOCUMULUS_ALTITUDE, top, max_distance, t0, t1)) {
            float step_size = (t1 - t0) / float(CLOUDS_ALTOCUMULUS_STEPS);
            vec3 inscatter = vec3(0.0);
            float transmittance = 1.0;

            for (int i = 0; i < CLOUDS_ALTOCUMULUS_STEPS; i++) {
                float t = t0 + (float(i) + dither) * step_size;
                vec3 pos = ray_origin + ray_dir * t;

                float density = altocumulus_density(pos, coverage);
                if (density <= 0.0001) continue;

                float od = 0.0;
                vec3 p = pos;
                float light_step = CLOUDS_ALTOCUMULUS_THICKNESS / float(CLOUDS_ALTOCUMULUS_LIGHT_STEPS);

                for (int j = 0; j < CLOUDS_ALTOCUMULUS_LIGHT_STEPS; j++) {
                    p += sun_dir * light_step;
                    od += altocumulus_density(p, coverage) * light_step;
                }

                float beer = exp(-od * CLOUDS_SUN_ABSORPTION * 2.0);
                float phase = phase_cloud(dot(sun_dir, -ray_dir), 0.5, 0.1);
                vec3 ambient = sky_gradient(vec3(0.0, 1.0, 0.0), sun_dir) * 0.35;

                vec3 light = sun_color * beer * phase + ambient;

                inscatter += light * density * transmittance * step_size * 4.0;
                transmittance *= exp(-density * step_size * 0.8);

                if (transmittance < 0.01) break;
            }

            result.scatter = result.scatter * transmittance + inscatter;
            result.transmittance *= transmittance;
            result.distance = min(result.distance, t0);
        }
    }
#endif

    // ---- Cumulus (and congestus) ----
#if defined CLOUDS_CUMULUS || defined CLOUDS_CUMULUS_CONGESTUS
    {
        float base = CLOUDS_CUMULUS_ALTITUDE;
        float top = base + CLOUDS_CUMULUS_THICKNESS;

#ifdef CLOUDS_CUMULUS_CONGESTUS
        base = min(base, CLOUDS_CONGESTUS_ALTITUDE);
        top = max(top, CLOUDS_CONGESTUS_ALTITUDE + CLOUDS_CONGESTUS_THICKNESS);
#endif

        float t0;
        float t1;

        if (slab_intersect(ray_origin, ray_dir, base, top, max_distance, t0, t1)) {
            float step_size = (t1 - t0) / float(CLOUDS_CUMULUS_STEPS);

            vec3 inscatter = vec3(0.0);
            float transmittance = 1.0;

            vec3 sun_light = sun_color;
            float phase = phase_cloud(dot(sun_dir, -ray_dir), 0.65, 0.2);
            vec3 ambient = sky_gradient(vec3(0.0, 1.0, 0.0), sun_dir) * 0.6;

            for (int i = 0; i < CLOUDS_CUMULUS_STEPS; i++) {
                float t = t0 + (float(i) + dither) * step_size;
                vec3 pos = ray_origin + ray_dir * t;

                float density = cloud_density(pos, coverage, false);
                if (density <= 0.0001) {
                    continue;
                }

                // Reduce the expensive lighting work at distance
                int light_steps = t > 3000.0 ? max(CLOUDS_CUMULUS_LIGHT_STEPS / 2, 1) : CLOUDS_CUMULUS_LIGHT_STEPS;

                vec3 light = cloud_sun_light(pos, sun_dir, sun_light, coverage, light_steps) * phase
                    + ambient * (0.35 + 0.65 * density);

                // Absorption of the ambient light through the cloud body
                float extinction = density * step_size * 0.010;
                inscatter += light * density * transmittance * step_size * 0.010;

                transmittance *= exp(-extinction);

                if (transmittance < 0.012) break;
            }

            result.scatter = result.scatter * transmittance + inscatter;
            result.transmittance *= transmittance;
            result.distance = min(result.distance, t0);
        }
    }
#endif

    return result;
}

// ---------------------------------
//   Cheap cloud shadow for terrain
// ---------------------------------

// Samples the cloud density where the sun ray crosses the cumulus layer. This
// is a 2-tap analytic shadow and far cheaper than projecting a shadow map.
float cloud_shadow(vec3 scene_pos, vec3 sun_dir) {
#if defined CLOUD_SHADOWS && defined CLOUDS_CUMULUS
    if (sun_dir.y < 0.02) return 1.0;

    float target_altitude = CLOUDS_CUMULUS_ALTITUDE + CLOUDS_CUMULUS_THICKNESS * 0.5;

    if (scene_pos.y > target_altitude) return 1.0;

    float t = (target_altitude - scene_pos.y) / max(sun_dir.y, 0.02);
    vec3 sample_pos = scene_pos + sun_dir * t;

    float coverage = cloud_coverage(sample_pos.xz);

    vec3 p = sample_pos * 0.0022 * CLOUDS_SCALE / max(CLOUDS_CUMULUS_SIZE, 0.1);
    p.xz += vec2(value_noise(p * 0.7), value_noise(p * 0.7 + 11.0)) * 0.4;

    float density = cloud_shape(p, coverage * CLOUDS_CUMULUS_COVERAGE, CLOUDS_CUMULUS_DETAIL);

    // Fade out at grazing angles where the approximation breaks down
    float grazing = smoothstep(0.02, 0.25, sun_dir.y);

    return 1.0 - clamp01(density) * CLOUD_SHADOWS_INTENSITY * grazing;
#else
    return 1.0;
#endif
}

// ------------------------------
//   Vanilla-style flat clouds
// ------------------------------

// Minecraft's iconic 4-block-thick layer, kept as an option for players who
// like the classic silhouette. Rendered as a single plane intersection.
vec4 flat_cloud_layer(vec3 ray_origin, vec3 ray_dir, float max_distance) {
#ifdef VANILLA_CLOUDS_LAYER
    const float altitude = 192.0;

    if (abs(ray_dir.y) < 1e-4) return vec4(0.0, 0.0, 0.0, 1.0);

    float t = (altitude - ray_origin.y) / ray_dir.y;
    if (t < 0.0 || t > max_distance) return vec4(0.0, 0.0, 0.0, 1.0);

    vec3 pos = ray_origin + ray_dir * t;

    // Blocky, world-aligned cells
    vec2 cell_uv = floor(pos.xz / 12.0) * 12.0;
    float n = value_noise(cell_uv * 0.021);

    if (n < 0.42) return vec4(0.0, 0.0, 0.0, 1.0);

    float density = smoothstep(0.42, 0.55, n);

    vec3 sun_dir = sun_dir_scene();
    vec3 sun_color = vec3(1.0);

    vec3 ambient = sky_gradient(vec3(0.0, 1.0, 0.0), sun_dir) * 0.5;
    vec3 light = sun_color * 0.8 + ambient;

    float fade = 1.0 - smoothstep(max_distance * 0.6, max_distance, t);

    return vec4(light * density * 0.4 * fade, 1.0 - density * 0.9 * fade);
#else
    return vec4(0.0, 0.0, 0.0, 1.0);
#endif
}

#endif // MUON_CLOUDS
