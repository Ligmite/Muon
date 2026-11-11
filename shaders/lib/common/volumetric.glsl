/*
================================================================================

  Muon Shaders - lib/common/volumetric.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Volumetric lighting: air fog, god rays and depth-aware compositing.

  The fog is a height-exponential medium with three contributors:

    * clear-air scattering, tuned so that the default look stays crisp instead
      of milky (this is the "clear, not hazy" brief),
    * a rain term that thickens the medium while precipitation is active,
    * a cave term for enclosed spaces, which is what gives underground shots
      their shafts of light.

  Each marched sample is lit with a single shadow-map lookup, so light shafts
  are real occlusion, not a screen-space approximation. The screen-space god
  ray pass then adds the long, soft diffraction streaks that a volumetric
  march at 12 steps cannot resolve on its own.

================================================================================
*/

#ifndef MUON_COMMON_VOLUMETRIC_GLSL
#define MUON_COMMON_VOLUMETRIC_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/sampling.glsl"
#include "/lib/common/shadow.glsl"
#include "/lib/common/atmosphere.glsl"
#include "/lib/common/clouds.glsl"


// -----------------------------------------------------------------------------
//  Medium
// -----------------------------------------------------------------------------

const float MUON_FOG_HEIGHT_FALLOFF = 0.0062;   // 1/m
const float MUON_FOG_BASE_HEIGHT = 62.0;
const float MUON_FOG_EXTINCTION = 0.55;
const float MUON_FOG_SCATTER_ALBEDO = 0.92;

float muon_fog_density(vec3 world_pos) {
    float altitude = max(world_pos.y - MUON_FOG_BASE_HEIGHT, 0.0);
    float height_term = exp(-altitude * MUON_FOG_HEIGHT_FALLOFF);

    float rain = muon_rain_strength();
    float weather_term = 1.0 + rain * (MUON_FOG_RAIN_STRENGTH - 1.0);

    /* Below sea level, in enclosed spaces, the air gets thicker. This is the
       only term that looks at the player's skylight, and it fades out before
       the player surfaces so the transition is never visible. */
    float cave = 1.0;
#if defined CAVE_FOG
    float underground = muon_saturate(1.0 - muon_eye_sky_light());
    float below = muon_saturate((muon_sea_level() + 24.0 - world_pos.y) / 40.0);
    cave = 1.0 + underground * below * CAVE_FOG_STRENGTH * 2.4;
#endif

    return MUON_FOG_STRENGTH * height_term * weather_term * cave * 0.0012;
}

// -----------------------------------------------------------------------------
//  Volumetric integration
// -----------------------------------------------------------------------------

struct MuonVolumetric {
    vec3 inscatter;
    float transmittance;
};

/*
 * Integrates the fog between the eye and the shaded surface.
 *
 *   view_distance   distance from the camera to the surface (or the far plane)
 *   world_dir       unit view direction in world space
 */
MuonVolumetric muon_volumetric_fog(float view_distance, vec3 world_dir) {
    MuonVolumetric result;
    result.inscatter = vec3(0.0);
    result.transmittance = 1.0;

#if !defined VOLUMETRIC_FOG
    return result;
#else
    if (view_distance <= 0.01) {
        return result;
    }

    vec3 origin = muon_camera_position();
    vec3 light_dir = muon_direct_light_direction();
    vec3 light_color = muon_direct_light_color();
    float phase = muon_mie_phase_dual(dot(world_dir, light_dir));

    vec3 ambient = muon_sky_ambient(vec3(0.0, 1.0, 0.0));

    float max_distance = min(view_distance, muonFrame.depthParams.y * 1.6);
    float step_size = max_distance / float(MUON_FOG_STEPS);
    float dither = muon_interleaved_gradient_noise(gl_FragCoord.xy);
    float jitter = dither * step_size;

    float shadow_accumulator = 0.0;
    float shadow_weight = 0.0;

    for (int i = 0; i < MUON_FOG_STEPS; i++) {
        float t = jitter + step_size * (float(i) + 0.5);
        vec3 p = origin + world_dir * t;

        float density = muon_fog_density(p);
        if (density <= 1.0e-7) {
            continue;
        }

        /* One shadow tap per sample: the fog is low-frequency, so it does not
           need the full PCSS kernel. */
        vec3 shadow_pos = muon_shadow_screen_pos(p + world_dir * 0.0);
        float visibility = 1.0;
        if (muon_shadow_in_bounds(shadow_pos.xy)) {
            float depth = muon_sample_shadow(shadow_pos.xy);
            visibility = shadow_pos.z - 0.002 <= depth ? 1.0 : 0.0;
        }
        shadow_accumulator += visibility * density;
        shadow_weight += density;

        vec3 radiance = light_color * (visibility * phase)
            + ambient * (0.35 + 0.65 * muon_saturate(world_dir.y * 0.5 + 0.5));

        float extinction = MUON_FOG_EXTINCTION * density * step_size;
        float sample_transmittance = exp(-extinction);

        result.inscatter += radiance * MUON_FOG_SCATTER_ALBEDO * (1.0 - sample_transmittance) * result.transmittance;
        result.transmittance *= sample_transmittance;
    }

    return result;
#endif
}

// -----------------------------------------------------------------------------
//  Compositing
// -----------------------------------------------------------------------------

vec3 muon_apply_volumetric(vec3 color, MuonVolumetric volume) {
    return color * volume.transmittance + volume.inscatter;
}

// -----------------------------------------------------------------------------
//  Screen-space god rays
//
//  A radial march from the sun's screen position along the view ray. The
//  occlusion term comes from the depth buffer, so the shafts bend around
//  geometry correctly instead of being a painterly overlay.
// -----------------------------------------------------------------------------

float muon_god_ray_visibility(vec2 uv, float depth) {
    if (depth >= 1.0) {
        return 0.0;
    }
    /* The sky is the light source; only geometry occludes. */
    return 1.0;
}

vec3 muon_god_rays(vec2 uv, vec3 world_dir, float view_distance, vec3 color_before_fog) {
#if !defined GOD_RAYS
    return vec3(0.0);
#else
    vec3 light_dir = muon_direct_light_direction();
    if (light_dir.y < -0.05) {
        return vec3(0.0);
    }

    vec4 sun_clip = muonFrame.projection * (muonFrame.view * vec4(muon_camera_position() + light_dir * 512.0, 1.0));
    if (sun_clip.w <= 0.0) {
        return vec3(0.0);
    }

    vec2 sun_uv = sun_clip.xy / sun_clip.w * 0.5 + 0.5;
    vec2 delta = (sun_uv - uv) / float(MUON_GODRAY_STEPS);

    float illumination = 0.0;
    float decay = 1.0;
    vec2 sample_uv = uv;

    for (int i = 0; i < MUON_GODRAY_STEPS; i++) {
        sample_uv += delta;
        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            break;
        }
        float sample_depth = texture(depthtex0, sample_uv).r;
        float visibility = sample_depth >= 1.0 ? 1.0 : 0.0;
        illumination += visibility * decay;
        decay *= 0.94;
    }

    illumination /= float(MUON_GODRAY_STEPS);

    float phase = muon_mie_phase_dual(dot(world_dir, light_dir));
    vec3 tint = muon_direct_light_color() * (MUON_GODRAY_STRENGTH * illumination * phase);
    tint *= 1.0 + muon_rain_strength() * 1.5;

    return tint * (1.0 - muon_saturate(view_distance / max(muonFrame.depthParams.y, 1.0)));
#endif
}

#endif // MUON_COMMON_VOLUMETRIC_GLSL
