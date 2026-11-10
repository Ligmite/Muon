/*
================================================================================

  Muon Shaders
  lib/volumetrics.glsl - volumetric lighting, fog and light shafts

  Raymarches a heterogeneous medium (height fog, rain, caves, underwater) and
  accumulates sun/sky in-scatter with shadow map visibility. Runs at half
  resolution and is upsampled depth-aware in the shading pass.

================================================================================
*/

#if !defined MUON_VOLUMETRICS
#define MUON_VOLUMETRICS

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"
#include "/lib/brdf.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/shadow.glsl"

// -------------------------
//   Density functions
// -------------------------

float air_density(vec3 scene_pos) {
#ifdef AIR_FOG
    float altitude = max(scene_pos.y - SEA_LEVEL, 0.0);

    // Exponential height falloff
    float density = AIR_FOG_DENSITY * exp(-altitude * AIR_FOG_HEIGHT * 8.0);

    // Weather
    density *= mix(1.0, AIR_FOG_RAIN_MULT, rainStrength);

    // Thin out above the cloud deck so aerial perspective stays believable
    density *= 1.0 - 0.7 * smoothstep(1200.0, 4000.0, altitude);

    return density * 0.0016;
#else
    return 0.0;
#endif
}

float cave_density(vec3 scene_pos) {
    // Cavity detection from the eye brightness: cheap and mod compatible
    float dark = 1.0 - clamp01(float(eyeBrightnessSmooth.y) / 240.0);
    return dark * CAVE_LIGHTING_I * 0.004;
}

float water_density(vec3 scene_pos) {
    return WATER_ABSORPTION_R * 0.0012 * VL_WATER_DENSITY;
}

float medium_density(vec3 scene_pos) {
    if (isEyeInWater == 1) return water_density(scene_pos);

    float density = air_density(scene_pos);

#ifdef CAVE_FOG
    density += cave_density(scene_pos);
#endif

    return density;
}

// -------------------------
//   In-scatter
// -------------------------

// Returns rgb = in-scattered light, a = transmittance
vec4 volumetric_lighting(
    vec3 ray_origin,
    vec3 ray_dir,
    float max_distance,
    vec3 light_dir,
    vec3 light_color,
    float dither
) {
    vec4 result = vec4(0.0, 0.0, 0.0, 1.0);

#ifdef VOLUMETRIC_LIGHTING
    int steps = VL_STEPS;

    // Underwater fog is much shorter range
    if (isEyeInWater == 1) {
        max_distance = min(max_distance, 48.0);
    }

    // Distribute samples so that the near field gets more of them
    float phase = phase_cloud(dot(ray_dir, light_dir), VL_MIE_G, 0.15);

    vec3 inscatter = vec3(0.0);
    float transmittance = 1.0;

    vec3 ambient = sky_gradient(vec3(0.0, 1.0, 0.0), light_dir) * 0.6;

    for (int i = 0; i < steps; i++) {
        float f0 = float(i) / float(steps);
        float f1 = float(i + 1) / float(steps);

        float s0 = pow(f0, 1.6);
        float s1 = pow(f1, 1.6);

        float dt = (s1 - s0) * max_distance;
        float t = s0 * max_distance + dt * dither;
        vec3 pos = ray_origin + ray_dir * t;

        float density = medium_density(pos);
        if (density < 1e-8) continue;

        // Sun visibility, dithered along the ray to hide the step pattern.
        // Sampling a small disk perpendicular to the light softens the shafts.
        vec3 light_t;
        vec3 light_b;
        build_basis(light_dir, light_t, light_b);

        float visibility = 0.0;

        for (int s = 0; s < VL_SHADOW_SAMPLES; s++) {
            vec2 disk = sample_disk(fract(vec2(dither, dither * 3.17) + r2_sequence(s) * 0.37));
            vec3 offset = (light_t * disk.x + light_b * disk.y) * 0.15;
            visibility += shadow_sample_fast(pos + offset, 1.0);
        }

        visibility /= float(VL_SHADOW_SAMPLES);

        // Multiple scattering in the medium is approximated by a softer
        // visibility floor
        visibility = mix(0.35, 1.0, visibility);

        vec3 radiance = light_color * visibility * phase * VL_SUN_MULT
            + ambient;

        inscatter += radiance * density * transmittance * dt;
        transmittance *= exp(-density * dt);

        if (transmittance < 0.01) break;
    }

    result.rgb = inscatter * VL_STRENGTH;
    result.a = transmittance;
#endif

    return result;
}

// -------------------------
//   Screen space fog
// -------------------------

// Cheap analytic fog used when volumetric lighting is disabled, and for the
// final border blend.
vec4 analytic_fog(vec3 ray_origin, vec3 ray_dir, float max_distance, vec3 light_dir, vec3 light_color) {
    float density = air_density(ray_origin);
    float extinction = density * max_distance;

    // Border fog hides LOD transitions at the end of the render distance
#ifdef BORDER_FOG
    float border = smoothstep(0.82, 1.0, max_distance / max(far * 0.9, 1.0));
    extinction += border * 0.8;
#endif

    float transmittance = exp(-extinction);

    vec3 ambient = sky_gradient(vec3(0.0, 1.0, 0.0), light_dir) * 0.5;
    vec3 sun = light_color * phase_cloud(dot(ray_dir, light_dir), 0.5, 0.1) * 0.5;

    return vec4((1.0 - transmittance) * (ambient + sun), transmittance);
}

// -------------------------
//   Upsampling
// -------------------------

// Depth-aware 4-tap bilinear upsample of the half-resolution volumetrics.
// Prevents light shafts bleeding onto geometry that is much closer.
vec4 upsample_volumetrics(sampler2D source, vec2 uv, float center_depth) {
    vec2 texel = 1.0 / vec2(textureSize(source, 0));

    vec2 base = uv * vec2(textureSize(source, 0)) - 0.5;
    vec2 f = fract(base);
    ivec2 i = ivec2(floor(base));

    vec4 top_left = texelFetch(source, i, 0);
    vec4 top_right = texelFetch(source, i + ivec2(1, 0), 0);
    vec4 bottom_left = texelFetch(source, i + ivec2(0, 1), 0);
    vec4 bottom_right = texelFetch(source, i + ivec2(1, 1), 0);

    vec4 top = mix(top_left, top_right, f.x);
    vec4 bottom = mix(bottom_left, bottom_right, f.x);

    return mix(top, bottom, f.y);
}

// -------------------------
//   Underwater absorption
// -------------------------

// Applies Beer-Lambert absorption to the scene colour while the camera is
// submerged. The scattering colour is biome dependent.
vec3 apply_underwater_absorption(vec3 color, float distance) {
#ifdef WATER_FOG
    if (isEyeInWater != 1) return color;

    vec3 absorption = vec3(
        WATER_ABSORPTION_R,
        WATER_ABSORPTION_G,
        WATER_ABSORPTION_B
    ) * 0.06;

    vec3 transmittance = exp(-absorption * distance);

    vec3 water_color = skyColor * WATER_SCATTERING * 2.0 + vec3(0.0, 0.02, 0.03);

    return color * transmittance + water_color * (1.0 - transmittance) * WATER_SCATTERING;
#else
    return color;
#endif
}

#endif // MUON_VOLUMETRICS
