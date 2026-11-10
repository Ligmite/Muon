/*
================================================================================

  Muon Shaders
  lib/lighting.glsl - the analytic lighting model shared by every pass

  Direct sun/moon light with PCSS shadows, cloud shadows and contact shadows,
  ambient sky light with ambient occlusion, block light, subsurface scattering,
  cloth sheen, emission and environment specular.

  The raster path and the path tracer both call into this file so that the two
  produce the same image when the path tracer is disabled.

================================================================================
*/

#if !defined MUON_LIGHTING
#define MUON_LIGHTING

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/brdf.glsl"
#include "/lib/color.glsl"
#include "/lib/materials.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/shadow.glsl"
#include "/lib/clouds.glsl"
#include "/lib/ssr.glsl"
#include "/lib/ao.glsl"

// -------------------------
//   Light source colours
// -------------------------

// Direct sun/moon irradiance, including atmospheric reddening.
vec3 direct_light_color(vec3 light_dir) {
    float sun_height = sun_dir_scene().y;

    vec3 sun_color = blackbody(SUN_TEMPERATURE) * SUN_I * 3.0;
    vec3 moon_color = blackbody(MOON_TEMPERATURE) * MOON_I * 1.6;

    // Extinction through the atmosphere: this is what turns the sun orange at
    // sunrise and red at sunset.
    vec3 extinction = atmosphere_transmittance(max(eyeAltitude, 0.0), sun_height);

    vec3 color = mix(moon_color, sun_color * extinction, smoothstep(-0.06, 0.06, sun_height));

#ifdef MOON_PHASE_AFFECTS_BRIGHTNESS
    // A new moon is dark, a full moon is bright
    float phase_brightness = 1.0 - abs(float(moonPhase) - 4.0) / 4.0;
    color *= mix(1.0, mix(0.25, 1.0, phase_brightness), 1.0 - smoothstep(-0.06, 0.06, sun_height));
#endif

    // Weather dims and desaturates direct light
    color *= mix(1.0, 0.25, rainStrength);
    color *= mix(vec3(1.0), vec3(1.0, 0.95, 0.9), rainStrength);

    return color;
}

vec3 block_light_color() {
    return blackbody(BLOCKLIGHT_TEMPERATURE) * BLOCKLIGHT_I;
}

// Ambient sky irradiance. The 0.45 factor converts sky radiance to an
// irradiance that sits at a physically plausible ratio to direct sunlight.
vec3 ambient_light_color(vec3 normal, vec3 light_dir) {
    vec3 sky = sky_ambient(normal, light_dir) * 0.45 * SKYLIGHT_I;

    // Bounced light from the ground, tinted by the average world albedo
    vec3 ground_bounce = vec3(0.16, 0.13, 0.09) * direct_light_color(light_dir)
        * max0(light_dir.y) * BOUNCED_LIGHT_I * 0.12;

    return sky + ground_bounce;
}

// -------------------------
//   Shadow composition
// -------------------------

// Returns the visibility of the direct light, in [0, 1].
float direct_light_visibility(vec3 scene_pos, vec3 normal, vec3 light_dir, float dither) {
    float NoL = dot(normal, light_dir);
    if (NoL <= 0.0) return 0.0;

    float visibility = 1.0;

#ifdef SHADOW
    visibility *= shadow_pcss(scene_pos, normal, NoL, dither);

    if (visibility > 0.0) {
        visibility *= contact_shadow(scene_pos, light_dir, dither);
    }
#endif

    visibility *= cloud_shadow(scene_pos, light_dir);

    // Both layers of shadowing fade out when the light is below the horizon
    visibility *= smoothstep(-0.02, 0.06, light_dir.y);

    return visibility;
}

// -------------------------
//   Surface description
// -------------------------

struct SurfaceData {
    vec3 albedo;
    vec3 normal;       // scene space, unit length
    vec3 view_dir;     // scene space, surface -> camera
    vec3 scene_pos;
    float roughness;
    float metalness;
    float f0;
    float sss;
    float emission;
    float ao;
    float skylight;    // 0..1
    float blocklight;  // 0..1
    uint material;
    float shadow;      // direct light visibility
};

bool is_eye_in_water() {
    return isEyeInWater == 1;
}

// -------------------------
//   BRDF evaluation
// -------------------------

vec3 shade_surface(SurfaceData s, vec3 light_dir, vec3 reflection_color) {
    vec3 N = normalize(s.normal);
    vec3 V = normalize(s.view_dir);

    float NoV = max(dot(N, V), 1e-4);

    vec3 f0 = mix(vec3(s.f0), s.albedo, s.metalness);
    vec3 diffuse_albedo = s.albedo * (1.0 - s.metalness);

    vec3 light_color = direct_light_color(light_dir);

    float NoL = max0(dot(N, light_dir));

    vec3 result = vec3(0.0);

    // --- direct light ---
    if (NoL > 0.0 && s.shadow > 0.0) {
        vec3 H = normalize(light_dir + V);
        float NoH = max0(dot(N, H));
        float VoH = max0(dot(V, H));

        vec3 radiance = light_color * s.shadow;

        // Diffuse (Lambert, energy conserving)
        float diffuse_brdf = NoL * rcp_pi;
        result += diffuse_albedo * diffuse_brdf * radiance * pi;

        // Specular. specular_brdf() already folds in the 1/(4 NoL NoV)
        // visibility term, so only NoL is applied here.
        result += specular_brdf(f0, s.roughness, NoV, NoL, NoH, VoH) * radiance * NoL;

        // Subsurface / sheen
        if (s.sss > 0.0) {
            result += subsurface_brdf(s.albedo, NoV, NoL, VoH, s.sss * SSS_INTENSITY) * radiance * NoL;
        }

#ifdef SSS_SHEEN
        if (s.material == MAT_CLOTH) {
            float sheen = sheen_brdf(s.roughness, NoV, NoL, VoH);
            result += vec3(0.9, 0.85, 0.8) * sheen * radiance * NoL * 0.15;
        }
#endif
    }

    // --- ambient sky light ---
    float ao_ambient = 1.0;
#ifdef AO_IN_SUNLIGHT
    ao_ambient = s.ao;
#endif

    vec3 ambient = ambient_light_color(N, light_dir) * s.skylight;

    result += diffuse_albedo * ambient * ao_ambient;

    // Environment specular. The caller supplies the radiance: analytic sky,
    // screen space reflection, or the ray traced result.
    vec3 env_brdf = environment_brdf(f0, s.roughness, NoV);

    float spec_occlusion = specular_occlusion(NoV, ao_ambient, s.roughness);

    result += env_brdf * reflection_color * spec_occlusion * s.skylight;

    // --- block light ---
    float block = s.blocklight * s.blocklight;
    if (block > 0.001) {
        vec3 block_rgb = block_light_color() * block;

        result += diffuse_albedo * block_rgb * mix(0.35, 1.0, ao_ambient);

        // A little specular so torches reflect in stone
        float NoH = max0(dot(N, normalize(vec3(0.0, 1.0, 0.0) + V)));
        result += f0 * pow(NoH, mix(64.0, 4.0, s.roughness)) * block_rgb * spec_occlusion * 0.25;
    }

    // --- emission ---
    if (s.emission > 0.0) {
        result += s.albedo * s.emission * EMISSION_STRENGTH;
    }

    // --- handheld light ---
#ifdef HANDHELD_LIGHTING
    {
        float held = float(max(heldBlockLightValue, heldBlockLightValue2)) / 15.0;

        if (held > 0.01 && !is_eye_in_water()) {
            float dist = length(s.scene_pos);
            float attenuation = 1.0 / (1.0 + dist * dist * 0.35);
            vec3 held_rgb = block_light_color() * held * attenuation * HANDHELD_LIGHTING_INTENSITY;

            result += diffuse_albedo * held_rgb * 0.6;
            result += f0 * held_rgb * 0.15;
        }
    }
#endif

    // --- rim / edge highlight ---
#ifdef EDGE_HIGHLIGHT
    {
        float rim = pow(1.0 - NoV, EDGE_HIGHLIGHT_SCALE);
        result += diffuse_albedo * rim * (ambient + direct_light_color(light_dir) * s.shadow * 0.15) * 0.06;
    }
#endif

    // --- minimum light, so caves are not pitch black ---
    result += diffuse_albedo * MINIMUM_LIGHT * 0.2;

    return max(result, vec3(0.0));
}

// Converts Minecraft's lightmap coordinates to a linear [0, 1] light level
float lightmap_level(float raw) {
    return pow(clamp01(raw), 2.2);
}

// Directional lightmap: uses the lightmap texture gradient to derive a light
// direction. Cheap approximation of OptiFine's directional lightmaps.
vec3 directional_lightmap_dir(vec2 light_levels) {
#ifdef DIRECTIONAL_LIGHTMAPS
    // Shift the lookup towards the brighter axis
    vec2 levels = light_levels;

    vec2 gradient = vec2(0.0);

    // The lightmap is sampled by the vertex shader normally; here we just use
    // the block/sky balance as a proxy for direction.
    float sky = levels.y;
    float block = levels.x;

    return normalize(vec3(0.0, sky, 0.0) + vec3(block * 0.3, block, 0.0) + vec3(0.0, 0.001, 0.0));
#else
    return vec3(0.0, 1.0, 0.0);
#endif
}

// Applies the debug white world mode
vec3 debug_white_world(vec3 color, vec3 albedo, float ao) {
#ifdef WHITE_WORLD
    return albedo * (0.4 + 0.6 * ao);
#else
    return color;
#endif
}

#endif // MUON_LIGHTING
