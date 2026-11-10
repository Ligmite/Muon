/*
================================================================================

  Muon Shaders
  lib/water.glsl - wave simulation, water surface shading, caustics

  Waves are a sum of directional sine waves with an analytic gradient, which is
  what makes the normal map resolution-independent and lets the same function
  drive both the normal and the vertex displacement.

================================================================================
*/

#if !defined MUON_WATER
#define MUON_WATER

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/noise.glsl"
#include "/lib/brdf.glsl"
#include "/lib/atmosphere.glsl"

// -------------------------
//   Wave field
// -------------------------

// Returns the world-space normal of the water surface at `world_pos`.
vec3 water_normal(vec3 world_pos, float rain_ripples) {
#ifdef WATER_WAVES
    vec2 p = world_pos.xz;

    float amplitude = 0.06 * WATER_WAVE_STRENGTH;
    float frequency = 0.55 * WATER_WAVE_FREQUENCY;
    float speed = 0.55 * WATER_WAVE_SPEED;

    vec2 gradient = vec2(0.0);

    float angle = 0.0;

    for (int i = 0; i < WATER_WAVE_ITERATIONS; i++) {
        // Golden angle distribution of wave directions
        angle += 2.39996323;

        vec2 dir = vec2(cos(angle), sin(angle));

        float k = frequency * tau;
        float phase = dot(dir, p) * k + frameTimeCounter * speed * (1.0 + float(i) * 0.35);

        float d = amplitude * cos(phase) * k;

        gradient += dir * d;

        // Lacunarity / persistence
        amplitude *= WATER_WAVE_PERSISTENCE;
        frequency *= WATER_WAVE_LACUNARITY;
        speed *= 1.18;
    }

    // Rain ripples: expanding rings
    if (rain_ripples > 0.01) {
        float ripple_scale = 3.0;
        vec2 rp = p * ripple_scale;
        vec2 cell = floor(rp);
        vec2 f = fract(rp);

        vec2 offset = hash22(cell);
        float dist = length(f - offset);
        float phase = dist * 18.0 - frameTimeCounter * 5.0 + hash12(cell) * tau;

        float ripple = cos(phase) * exp(-dist * 2.0) * rain_ripples * 0.6;
        vec2 dir = normalize(f - offset + 1e-4);
        gradient += dir * ripple * 0.05;
    }

    return normalize(vec3(-gradient.x, 1.0, -gradient.y));
#else
    return vec3(0.0, 1.0, 0.0);
#endif
}

// Vertical displacement for the water surface vertices
float water_displacement(vec3 world_pos) {
#ifdef WATER_DISPLACEMENT
    vec2 p = world_pos.xz;
    float height = 0.0;

    float amplitude = 0.06 * WATER_WAVE_STRENGTH;
    float frequency = 0.55 * WATER_WAVE_FREQUENCY;
    float angle = 0.0;

    for (int i = 0; i < WATER_WAVE_ITERATIONS; i++) {
        angle += 2.39996323;
        vec2 dir = vec2(cos(angle), sin(angle));
        float k = frequency * tau;
        float phase = dot(dir, p) * k + frameTimeCounter * 0.55 * WATER_WAVE_SPEED * (1.0 + float(i) * 0.35);

        height += amplitude * sin(phase);

        amplitude *= WATER_WAVE_PERSISTENCE;
        frequency *= WATER_WAVE_LACUNARITY;
    }

    return height * 0.5;
#else
    return 0.0;
#endif
}

// -------------------------
//   Caustics
// -------------------------

// Animated caustic pattern projected on the floor below the water surface.
float water_caustics(vec3 world_pos, float time) {
#ifdef WATER_CAUSTICS
    vec2 p = world_pos.xz * 0.9;

    float c1 = caustic_noise(p * 0.5, time * 0.6);
    float c2 = caustic_noise(p * 0.5 + 17.0, time * 0.8 + 3.0);

    float caustic = (c1 * c2) * 2.0;
    caustic = pow(clamp01(caustic), 1.6);

    return caustic * WATER_CAUSTICS_INTENSITY;
#else
    return 0.0;
#endif
}

// -------------------------
//   Water shading
// -------------------------

struct WaterSurface {
    vec3 normal;
    vec3 albedo;
    float roughness;
    float f0;
    float opacity;
};

// Builds the surface description from the g-buffer data of the water pass
WaterSurface make_water_surface(vec3 normal, vec3 albedo, float opacity) {
    WaterSurface surface;
    surface.normal = normal;
    surface.albedo = albedo;
    surface.roughness = 0.02;
    surface.f0 = 0.02;
    surface.opacity = opacity;
    return surface;
}

// Refraction offset in uv space. The offset is larger the deeper the water and
// the rougher the surface.
vec2 water_refraction_offset(vec3 normal, float sigma, float depth_difference) {
#ifdef WATER_REFRACTION
    vec2 offset = normal.xz * WATER_REFRACTION_INTENSITY * clamp01(depth_difference * 0.08);
    return offset * 0.06;
#else
    return vec2(0.0);
#endif
}

// Beer-Lambert absorption of the water body, returns the surviving colour
vec3 water_absorbtion(vec3 color, float distance) {
    vec3 absorption = vec3(
        WATER_ABSORPTION_R,
        WATER_ABSORPTION_G,
        WATER_ABSORPTION_B
    ) * 0.08;

    return color * exp(-absorption * distance);
}

// Scattering colour of the water body (what you see in the deep)
vec3 water_scattering_color(vec3 light_color, vec3 sky_color, vec3 biome_color) {
    vec3 scattered = light_color * 0.15 + sky_color * 0.35;

#ifdef BIOME_WATER_COLOR
    scattered = mix(scattered, biome_color * scattered, 0.5);
#endif

    return scattered * WATER_SCATTERING;
}

// -------------------------
//   Edge highlight / foam
// -------------------------

float water_edge_foam(vec3 scene_pos, vec3 normal, float depth_difference) {
#ifdef WATER_EDGE_HIGHLIGHT
    // Objects close to the surface get a thin bright rim
    float thin = 1.0 - clamp01(depth_difference * 0.9);
    float fresnel = pow(1.0 - clamp01(abs(normal.y)), 3.0);

    return thin * fresnel * WATER_EDGE_HIGHLIGHT_INTENSITY;
#else
    return 0.0;
#endif
}

#endif // MUON_WATER
