/*
================================================================================

  Muon Shaders - lib/common/shadow.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Cascaded shadowing with percentage-closer soft shadows.

  Iris exposes one hardware shadow map per frame, so Muon builds its cascade
  ladder from two different techniques that share the same penumbra model:

      cascade 0  hardware shadow map, 0 .. shadowDistance
                 PCSS with a real blocker search, so contact hardening is
                 physical rather than faked.
      cascade 1  screen-space ray-marched shadows, shadowDistance .. 4x that
                 for surfaces the map no longer covers. This is the tier that
                 keeps distant terrain and Distant Horizons geometry from
                 popping out of shadow.

  Both tiers return a visibility factor in [0,1] and both use the same
  muon_penumbra_radius() so the transition between them is seamless.

================================================================================
*/

#ifndef MUON_COMMON_SHADOW_GLSL
#define MUON_COMMON_SHADOW_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/sampling.glsl"


// -----------------------------------------------------------------------------
//  Tuning
// -----------------------------------------------------------------------------

const float MUON_SHADOW_NORMAL_BIAS = 0.055;
const float MUON_SHADOW_DEPTH_BIAS = 0.00035;
const float MUON_SHADOW_MAX_PENUMBRA_TEXELS = 22.0;
const float MUON_SHADOW_MIN_PENUMBRA_TEXELS = 0.85;
const float MUON_SSRT_THICKNESS = 0.65;

// -----------------------------------------------------------------------------
//  Projection into the shadow map
// -----------------------------------------------------------------------------

vec3 muon_shadow_screen_pos(vec3 world_pos) {
    vec4 clip = muonFrame.shadowProjection * (muonFrame.shadowView * vec4(world_pos, 1.0));
    return clip.xyz / clip.w * 0.5 + 0.5;
}

bool muon_shadow_in_bounds(vec2 uv) {
    return uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0;
}

float muon_sample_shadow(vec2 uv) {
    return texture(shadowtex1, uv).r;
}

// -----------------------------------------------------------------------------
//  Penumbra model
//  Contact hardening is expressed as a radius in shadow-map texels. The upper
//  bound keeps grazing geometry from turning into a blob and the lower bound
//  keeps the near field from aliasing.
// -----------------------------------------------------------------------------

float muon_penumbra_radius(float receiver_depth, float blocker_depth, float view_distance) {
    float delta = max(receiver_depth - blocker_depth, 0.0);
    float contact = muon_saturate(delta * 48.0);
    float hard_far = muon_saturate(view_distance / max(muonFrame.shadowParams.z, 1.0));
    float radius = mix(
        MUON_SHADOW_MIN_PENUMBRA_TEXELS,
        MUON_SHADOW_MAX_PENUMBRA_TEXELS,
        max(contact, hard_far * 0.65)
    );
    return radius * MUON_SHADOW_SOFTNESS;
}

// -----------------------------------------------------------------------------
//  Percentage-closer soft shadows
// -----------------------------------------------------------------------------

float muon_pcss_shadow(vec3 world_pos, vec3 world_normal, vec3 light_dir, float view_distance) {
    vec3 offset_pos = world_pos + world_normal * MUON_SHADOW_NORMAL_BIAS;
    vec3 shadow_pos = muon_shadow_screen_pos(offset_pos);

    if (!muon_shadow_in_bounds(shadow_pos.xy) || shadow_pos.z >= 1.0) {
        return 1.0;
    }

    float texel = muonFrame.shadowParams.x;
    float receiver = shadow_pos.z;
    float slope = 1.0 - muon_saturate(dot(world_normal, light_dir));
    float bias = MUON_SHADOW_DEPTH_BIAS * (1.0 + slope * 4.0);

    /* The rotation comes from the fragment position so that neighbouring
       pixels use different tap patterns; PCSS without this is visibly banded. */
    float rotation = muon_pixel_rotation(gl_FragCoord.xy);

    /* --- blocker search ------------------------------------------------ */

    float search_radius = MUON_SHADOW_MAX_PENUMBRA_TEXELS * texel * 1.5;
    float blocker_sum = 0.0;
    float blocker_count = 0.0;

    for (int i = 0; i < MUON_SHADOW_SAMPLES; i++) {
        vec2 offset = muon_vogel_disk(i, MUON_SHADOW_SAMPLES, rotation) * search_radius;
        float sample_depth = muon_sample_shadow(shadow_pos.xy + offset);
        if (sample_depth < receiver - bias) {
            blocker_sum += sample_depth;
            blocker_count += 1.0;
        }
    }

    if (blocker_count < 0.5) {
        return 1.0;
    }

    float blocker_depth = blocker_sum / blocker_count;
    float radius = muon_penumbra_radius(receiver, blocker_depth, view_distance) * texel;

    /* --- filtered hard test ------------------------------------------- */

    float visible = 0.0;
    for (int i = 0; i < MUON_SHADOW_SAMPLES; i++) {
        vec2 offset = muon_vogel_disk(i, MUON_SHADOW_SAMPLES, rotation + 1.7) * radius;
        float sample_depth = muon_sample_shadow(shadow_pos.xy + offset);
        visible += sample_depth >= receiver - bias ? 1.0 : 0.0;
    }

    return visible / float(MUON_SHADOW_SAMPLES);
}

/* Plain PCF, used by the low quality profile. */
float muon_pcf_shadow(vec3 world_pos, vec3 world_normal, vec3 light_dir) {
    vec3 offset_pos = world_pos + world_normal * MUON_SHADOW_NORMAL_BIAS;
    vec3 shadow_pos = muon_shadow_screen_pos(offset_pos);

    if (!muon_shadow_in_bounds(shadow_pos.xy) || shadow_pos.z >= 1.0) {
        return 1.0;
    }

    float texel = muonFrame.shadowParams.x;
    float receiver = shadow_pos.z;
    float slope = 1.0 - muon_saturate(dot(world_normal, light_dir));
    float bias = MUON_SHADOW_DEPTH_BIAS * (1.0 + slope * 4.0);
    float rotation = muon_pixel_rotation(gl_FragCoord.xy);

    float visible = 0.0;
    for (int i = 0; i < MUON_SHADOW_SAMPLES; i++) {
        vec2 offset = muon_vogel_disk(i, MUON_SHADOW_SAMPLES, rotation) * texel * 2.0;
        visible += muon_sample_shadow(shadow_pos.xy + offset) >= receiver - bias ? 1.0 : 0.0;
    }
    return visible / float(MUON_SHADOW_SAMPLES);
}

// -----------------------------------------------------------------------------
//  Screen-space cascade
// -----------------------------------------------------------------------------

float muon_screen_space_shadow(
    vec3 view_pos,
    vec3 view_normal,
    vec3 view_light_dir,
    float dither
) {
    vec3 origin = view_pos + view_normal * 0.08;
    float max_distance = SHADOW_SSRT_DISTANCE;
    float stride = max_distance / float(SHADOW_SSRT_STEPS);
    vec2 inv_size = muon_inv_viewport();

    for (int i = 0; i < SHADOW_SSRT_STEPS; i++) {
        float t = (float(i) + dither + 0.5) * stride;
        vec3 sample_pos = origin + view_light_dir * t;

        vec4 clip = muonFrame.projection * vec4(sample_pos, 1.0);
        if (clip.w <= 0.0) {
            break;
        }
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            break;
        }

        float scene_distance = muon_linear_depth(texture(depthtex0, uv).r);
        float ray_distance = -sample_pos.z;

        if (ray_distance > scene_distance + MUON_SSRT_THICKNESS) {
            return 0.0;
        }
    }

    return 1.0;
}

// -----------------------------------------------------------------------------
//  Combined visibility
// -----------------------------------------------------------------------------

/*
 * Returns the direct-light visibility for a world-space shading point.
 *
 *   world_pos        shading position in world space
 *   world_normal     unit normal
 *   view_pos         the same point in view space
 *   light_dir        unit vector towards the sun or moon, world space
 *   view_distance    distance from the camera, used for the cascade blend
 */
float muon_direct_visibility(
    vec3 world_pos,
    vec3 world_normal,
    vec3 view_pos,
    vec3 light_dir,
    float view_distance
) {
#if !defined SHADOW
    return 1.0;
#else
    float dither = muon_interleaved_gradient_noise(gl_FragCoord.xy);
    vec3 view_light_dir = normalize(muon_world_to_view_dir(light_dir));

    float hardware = 1.0;
#if defined PCSS
    hardware = muon_pcss_shadow(world_pos, world_normal, light_dir, view_distance);
#else
    hardware = muon_pcf_shadow(world_pos, world_normal, light_dir);
#endif

#if defined SHADOW_SSRT
    /* The screen-space tier is only worth tracing where the hardware map is
       about to run out of range, and only if the pixel is still in shadow. */
    float ssrt_weight = muon_smoothstep(muonFrame.shadowParams.z * 0.55, muonFrame.shadowParams.z, view_distance);
    if (ssrt_weight > 0.001 && hardware > 0.001) {
        vec3 view_normal = normalize(muon_world_to_view_dir(world_normal));
        float screen = muon_screen_space_shadow(view_pos, view_normal, view_light_dir, dither);
        hardware = mix(hardware, min(hardware, screen), ssrt_weight * 0.75);
    }
#endif

    /* Fade the shadow map out smoothly at its far edge so that the transition
       to the screen-space tier is invisible. */
    float fade = 1.0 - muon_smoothstep(muonFrame.shadowParams.z * 0.92, muonFrame.shadowParams.z, view_distance);
    return mix(1.0, hardware, fade);
#endif
}

#endif // MUON_COMMON_SHADOW_GLSL
