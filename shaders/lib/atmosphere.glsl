/*
================================================================================

  Muon Shaders
  lib/atmosphere.glsl - physical sky, sun, moon, stars, galaxy, aurora

  Single-scattering Rayleigh + Mie atmosphere integrated along the view ray,
  with an analytic exponential-atmosphere transmittance for the sun ray. This
  is the model that gives the pack its sunset/sunrise colours. It costs about
  12 texture-free steps for sky pixels and is never evaluated for terrain.

  Units are Minecraft blocks. 1 block == 1 metre.

================================================================================
*/

#if !defined MUON_ATMOSPHERE
#define MUON_ATMOSPHERE

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"
#include "/lib/noise.glsl"
#include "/lib/brdf.glsl"
#include "/lib/color.glsl"

// -----------------
//   Atmosphere
// -----------------

const float planet_radius = 6371000.0;
const float atmosphere_radius = 6420000.0;

const vec3 rayleigh_beta = vec3(5.802e-6, 13.558e-6, 33.1e-6);
const float rayleigh_scale_height = 8000.0;

const vec3 mie_beta = vec3(3.996e-6);
const float mie_scale_height = 1200.0;
const float mie_g = 0.76;

const vec3 ozone_beta = vec3(0.650e-6, 1.881e-6, 0.085e-6);
const float ozone_scale_height = 15000.0;
const float ozone_center = 25000.0;

// Solar irradiance in "scene units". The pack's exposure is tuned around this.
const float solar_irradiance = 18.0;

// Kasten-Young relative air mass, clamped so the horizon does not explode
float relative_airmass(float cos_zenith) {
    return 1.0 / max(cos_zenith + 0.025 * exp(-11.0 * max(cos_zenith, 0.0)), 0.02);
}

// Optical depth of an exponential atmosphere layer seen from altitude `h`
float exponential_optical_depth(float h, float scale_height, float cos_zenith) {
    return scale_height * exp(-max(h, 0.0) / scale_height) * relative_airmass(cos_zenith);
}

// Transmittance from a point at altitude `h` towards a direction with the given
// cosine to the local zenith.
vec3 atmosphere_transmittance(float h, float cos_zenith) {
    if (cos_zenith < -0.05) return vec3(0.0);

    float c = max(cos_zenith, 0.0);

    vec3 tau_rayleigh = rayleigh_beta * exponential_optical_depth(h, rayleigh_scale_height, c);
    vec3 tau_mie = mie_beta * exponential_optical_depth(h, mie_scale_height, c) * 0.6;
    vec3 tau_ozone = ozone_beta * exponential_optical_depth(h, ozone_scale_height, c) * 3.0;

    return exp(-(tau_rayleigh + tau_mie + tau_ozone));
}

// Ray/sphere intersection. Returns false when there is no intersection.
bool ray_sphere(vec3 origin, vec3 dir, float radius, out float t0, out float t1) {
    float b = dot(origin, dir);
    float c = dot(origin, origin) - radius * radius;
    float d = b * b - c;

    if (d < 0.0) {
        t0 = 0.0;
        t1 = 0.0;
        return false;
    }

    float sqrt_d = sqrt(d);
    t0 = -b - sqrt_d;
    t1 = -b + sqrt_d;
    return true;
}

// -------------------------------------
//   Full single-scattering integral
// -------------------------------------

// Cornette-Shanks with a fixed Mie asymmetry (kept here so the atmosphere has
// no dependency on cloud code)
float phase_corny_shanks_mie(float cos_theta) {
    return phase_cornette_shanks(cos_theta, mie_g);
}

// dir and sun_dir must be normalised, in scene space.
vec3 atmosphere_inscatter(vec3 dir, vec3 sun_dir, int steps) {
    float h0 = max(eyeAltitude, 0.0);
    vec3 origin = vec3(0.0, planet_radius + h0, 0.0);

    float t0;
    float t1;

    bool hit_ground = false;
    float t_max;

    if (ray_sphere(origin, dir, planet_radius, t0, t1)) {
        if (t0 > 0.0) {
            hit_ground = true;
            t_max = t0;
        } else {
            t_max = ray_sphere(origin, dir, atmosphere_radius, t0, t1) ? t1 : 0.0;
        }
    } else {
        t_max = ray_sphere(origin, dir, atmosphere_radius, t0, t1) ? t1 : 0.0;
    }

    if (t_max <= 0.0) return vec3(0.0);

    float cos_theta = dot(dir, sun_dir);
    float phase_r = phase_rayleigh(cos_theta);
    float phase_m = phase_corny_shanks_mie(cos_theta);

    float od_rayleigh = 0.0;
    float od_mie = 0.0;
    float od_ozone = 0.0;

    vec3 inscatter = vec3(0.0);

    float inv_steps = 1.0 / float(steps);

    for (int i = 0; i < steps; i++) {
        float f0 = float(i) * inv_steps;
        float f1 = float(i + 1) * inv_steps;

        // Quadratic distribution: more samples near the camera where the
        // density is highest
        float s0 = f0 * f0;
        float s1 = f1 * f1;

        float dt = (s1 - s0) * t_max;
        float t = s0 * t_max;
        vec3 pos = origin + dir * t;

        float h = max(length(pos) - planet_radius, 0.0);
        vec3 up = normalize(pos);

        float density_r = exp(-h / rayleigh_scale_height);
        float density_m = exp(-h / mie_scale_height);

        float ozone_profile = exp(-sqr((h - ozone_center) / ozone_scale_height));

        od_rayleigh += density_r * dt;
        od_mie += density_m * dt;
        od_ozone += ozone_profile * dt;

        float cos_sun = dot(up, sun_dir);
        vec3 sun_t = atmosphere_transmittance(h, cos_sun);

        vec3 tau_view = rayleigh_beta * od_rayleigh
            + mie_beta * od_mie
            + ozone_beta * od_ozone * 3.0;

        vec3 view_t = exp(-tau_view);

        vec3 scattering = rayleigh_beta * density_r * phase_r
            + mie_beta * density_m * phase_m * 1.4;

        inscatter += view_t * sun_t * scattering * dt;
    }

    // Multiple scattering approximation: a fraction of the single-scattered
    // light re-scatters towards the viewer. Without this the zenith is too dark
    // and twilight lacks the soft glow.
    float multiple_scattering = 1.0 / (1.0 + od_rayleigh * 1.2e-5);
    inscatter *= mix(1.0, 1.45, multiple_scattering);

    if (hit_ground) {
        // Ground bounce: average dirt albedo lit by the sky
        vec3 ground_albedo = vec3(0.16, 0.13, 0.09);
        vec3 ambient = atmosphere_transmittance(h0, max(sun_dir.y, 0.05)) * solar_irradiance * 0.06;
        inscatter += ground_albedo * ambient * 0.35;
    }

    return inscatter * solar_irradiance * 10.0;
}

// --------------------------------
//   Cheap analytic sky gradient
// --------------------------------

// Used for ambient light, cloud lighting and environment reflections where the
// full integral would be far too expensive. Returns radiance in the same units
// as atmosphere_inscatter().
vec3 sky_gradient(vec3 dir, vec3 sun_dir) {
    float h0 = max(eyeAltitude, 0.0);

    float cos_zenith = max(dir.y, -0.05);
    float sun_dot = dot(dir, sun_dir);
    float sun_height = sun_dir.y;

    // Sun transmittance at the ground, which drives the horizon colour
    vec3 sun_t = atmosphere_transmittance(h0, sun_dir.y);

    // Twilight factor: how close the sun is to the horizon
    float twilight = exp(-sqr(max(sun_height, -0.1) * 6.0));

    vec3 zenith_color = vec3(0.06, 0.16, 0.42) * (0.25 + 0.75 * clamp01(sun_dir.y + 0.2));
    zenith_color *= mix(vec3(1.0), sun_t, 0.35);
    zenith_color += vec3(0.25, 0.12, 0.04) * twilight * 0.6;

    vec3 horizon_color = vec3(0.55, 0.68, 0.88) * sun_t * 0.9;
    horizon_color += vec3(0.55, 0.20, 0.06) * twilight * 1.6;

    // Ground / night floor
    vec3 night_color = vec3(0.004, 0.006, 0.012);

    float horizon_blend = pow(1.0 - clamp01(abs(cos_zenith)), 3.0);

    vec3 sky = mix(zenith_color, horizon_color, horizon_blend);
    sky = mix(night_color, sky, smoothstep(-0.15, 0.10, sun_dir.y) * 0.9 + 0.1);

    // Mie forward-scattering glow around the sun
    float mie_glow = phase_henyey_greenstein(sun_dot, 0.82) * 0.35;
    sky += sun_t * mie_glow * smoothstep(-0.2, 0.2, sun_dir.y) * vec3(1.0, 0.75, 0.5);

    // Below the horizon: fade to a dark ground haze
    if (dir.y < 0.0) {
        sky = mix(sky, vec3(0.02, 0.02, 0.025) + horizon_color * 0.08, smoothstep(0.0, -0.25, dir.y));
    }

    return sky * solar_irradiance * 0.025;
}

// Ambient sky light on a surface with the given normal
vec3 sky_ambient(vec3 normal, vec3 sun_dir) {
    vec3 up = sky_gradient(vec3(0.0, 1.0, 0.0), sun_dir);
    vec3 horizon = sky_gradient(normalize(vec3(normal.x, 0.1, normal.z) + vec3(0.0, 0.0, 0.0)), sun_dir);

    float up_weight = clamp01(normal.y * 0.5 + 0.5);
    return mix(horizon, up, up_weight) * 0.85;
}

// ---------------------------------
//   Sun and moon discs
// ---------------------------------

vec3 sun_disc(vec3 dir, vec3 sun_dir, vec3 sun_color) {
    float cos_angle = dot(dir, sun_dir);
    float cos_radius = cos(radians_f(SUN_ANGULAR_RADIUS));

    if (cos_angle < cos_radius) return vec3(0.0);

    // Limb darkening: the edge of the disc is dimmer and redder
    float r = clamp01((cos_angle - cos_radius) / (1.0 - cos_radius));
    float limb = 0.45 + 0.55 * sqrt(r);

    vec3 color = sun_color * limb;

    // Very hot core
    color += vec3(1.0, 0.95, 0.85) * pow(r, 8.0) * 0.5;

    return color;
}

vec3 moon_disc(vec3 dir, vec3 moon_dir, vec3 moon_color) {
    float cos_angle = dot(dir, moon_dir);
    float cos_radius = cos(radians_f(MOON_ANGULAR_RADIUS));

    if (cos_angle < cos_radius) return vec3(0.0);

    // Build a local frame on the moon's tangent plane so we can draw craters
    vec3 t;
    vec3 b;
    build_basis(moon_dir, t, b);

    float radius = radians_f(MOON_ANGULAR_RADIUS);
    vec2 local = vec2(dot(dir, t), dot(dir, b)) / max(radius, eps);

    float r2 = dot(local, local);
    if (r2 > 1.0) return vec3(0.0);

    float z = sqrt(max0(1.0 - r2));

    // Crater field
    float craters = 0.0;
    craters += smoothstep(0.55, 0.9, value_noise(vec3(local * 3.1, 1.7)));
    craters += 0.6 * smoothstep(0.62, 0.95, value_noise(vec3(local * 7.3, 5.1)));
    craters += 0.35 * smoothstep(0.7, 0.98, value_noise(vec3(local * 17.0, 9.0)));
    float albedo = 0.72 + 0.28 * (1.0 - clamp01(craters * 0.6));

    // Phase: 0 = full, 4 = new
    float phase = float(moonPhase);
    float phase_angle = phase / 8.0 * tau;

    // The terminator is a great circle; shift the sphere's light vector
    vec3 light_local = vec3(sin(phase_angle), 0.0, cos(phase_angle));
    float illumination = smoothstep(-0.12, 0.12, dot(vec3(local, z), light_local));

    // New moon should not be visible at all (except earthshine)
    illumination = mix(illumination, 0.0, smoothstep(0.35, 0.5, abs(phase - 4.0) / 4.0) * 0.85);

    vec3 color = moon_color * albedo * illumination;

    // Soft edge
    color *= smoothstep(1.0, 0.96, r2);

    return color;
}

// ----------------
//   Stars
// ----------------

vec3 stars(vec3 dir) {
    // Rotate the star field with the day cycle so it drifts correctly
    float angle = sunAngle * tau;
    mat2 rot = rotate2(angle);

    vec3 p = vec3(dir.xz * rot, dir.y) * 220.0;
    ivec3 cell = ivec3(floor(p));
    vec3 local = p - vec3(cell);

    float h = hash13i(cell);
    if (h > 0.996 * STARS_COVERAGE) {
        vec3 offset = hash33i(cell) * 0.8 + 0.1;
        float dist = length(local - offset);
        float brightness = pow(hash13i(cell + ivec3(37, 11, 7)), 3.0) * 3.0 + 0.1;
        float twinkle = 0.75 + 0.25 * sin(frameTimeCounter * (2.0 + h * 3.0) + h * 40.0);
        float star = smoothstep(0.22, 0.0, dist) * brightness * twinkle;
        return vec3(0.85, 0.92, 1.0) * star;
    }

    return vec3(0.0);
}

vec3 galaxy(vec3 dir) {
#ifdef GALAXY
    // Galactic plane tilted relative to the world
    vec3 galactic_normal = normalize(vec3(0.35, 0.55, -0.75));
    float band = exp(-sqr(dot(dir, galactic_normal) * 3.2));

    if (band < 0.01) return vec3(0.0);

    float n = fbm(dir * 6.0 + 3.0, 5);
    float n2 = fbm(dir * 18.0 + 9.0, 4);

    float dust = smoothstep(0.35, 0.75, n2);

    vec3 color = mix(vec3(0.35, 0.42, 0.75), vec3(0.85, 0.75, 0.95), n);
    color *= band * (0.4 + 0.6 * dust);

    return color * 0.035 * GALAXY_INTENSITY;
#else
    return vec3(0.0);
#endif
}

// ----------------
//   Aurora
// ----------------

vec3 aurora(vec3 dir, vec3 sun_dir) {
#ifdef AURORA
    // Only at night and only sometimes
    float night = smoothstep(0.02, -0.18, sun_dir.y);
    if (night <= 0.0) return vec3(0.0);

    float activity = smoothstep(0.35, 0.75, AURORA_CONDITIONS);
    activity *= smoothstep(0.2, 0.9, sin(sunAngle * 7.0 + 1.3) * 0.5 + 0.5);
    if (activity * night < 0.01) return vec3(0.0);

    // Only above the horizon
    if (dir.y < 0.02) return vec3(0.0);

    // Project onto a curtain plane
    float azimuth = atan(dir.z, dir.x);
    float height = dir.y;

    float curtain = 0.0;

    for (int i = 0; i < 3; i++) {
        float scale = 1.0 + float(i) * 1.7;
        float wave = value_noise(vec2(azimuth * 3.0 * scale + frameTimeCounter * 0.05, float(i) * 3.7));
        float ribbon = exp(-sqr((height - 0.15 - wave * 0.45) * (3.5 + float(i))));
        ribbon *= smoothstep(0.0, 0.35, height);
        curtain += ribbon * (0.6 - float(i) * 0.15);
    }

    float flicker = 0.8 + 0.2 * sin(frameTimeCounter * 1.7 + azimuth * 12.0);

    vec3 color = mix(vec3(0.15, 1.0, 0.45), vec3(0.55, 0.25, 0.95), smoothstep(0.1, 0.6, height));

    return color * curtain * activity * night * 0.06 * AURORA_INTENSITY * flicker;
#else
    return vec3(0.0);
#endif
}

// ----------------
//   Full sky
// ----------------

vec3 sky_color(vec3 dir, vec3 sun_dir, vec3 moon_dir, vec3 sun_color, vec3 moon_color, bool include_discs) {
    float h0 = max(eyeAltitude, 0.0);

    // Day / night blend, based on the sun's altitude
    float day = smoothstep(-0.12, 0.10, sun_dir.y);

    vec3 sky = atmosphere_inscatter(dir, sun_dir, 12);

    // Night sky: stars, galaxy, aurora
    float night = 1.0 - day;
    if (night > 0.01) {
        vec3 night_sky = galaxy(dir) + aurora(dir, sun_dir);

#ifdef STARS
        night_sky += stars(dir) * STARS_INTENSITY;
#endif

        night_sky *= night;
        sky += night_sky;
    }

    if (include_discs) {
        sky += sun_disc(dir, sun_dir, sun_color) * day;
        sky += moon_disc(dir, moon_dir, moon_color) * night;
    }

    // Weather: overcast skies are desaturated and darker
    float overcast = rainStrength;
    vec3 overcast_color = vec3(0.55, 0.60, 0.68) * (0.05 + 0.35 * day) * solar_irradiance * 0.10;
    sky = mix(sky, overcast_color, overcast * 0.85);

    // Desaturate in rain
    sky = desaturate(sky, overcast * 0.35);

    // Atmosphere saturation control
    sky = saturation(sky * CUSTOM_SKY_BRIGHTNESS, ATMOSPHERE_SATURATION);

    return sky;
}

// Sky colour without the discs, used for reflections and cloud lighting
vec3 sky_reflection(vec3 dir, vec3 sun_dir) {
    vec3 sky = sky_gradient(dir, sun_dir);

    // Add the sun glow so water highlights still work when SSR misses
    float sun_dot = max0(dot(dir, sun_dir));
    sky += vec3(1.0, 0.85, 0.7) * pow(sun_dot, 256.0) * 4.0 * smoothstep(-0.05, 0.1, sun_dir.y);

    return sky;
}

#endif // MUON_ATMOSPHERE
