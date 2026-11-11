/*
================================================================================

  Muon Shaders - lib/common/sss.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Subsurface scattering for leaves, foliage and plants.

  Two contributions are combined:

    * An analytic transmission term (muon_diffuse_transmission) that lets light
      pass through thin geometry, tinted by the foliage albedo. This is what
      makes a canopy glow when the sun is behind it.
    * A screen-space gather that pulls sunlit colour from neighbouring pixels
      along the light direction, approximating multi-scattering inside a thick
      cluster of blocks. The gather is what removes the "cardboard cutout" look
      from dense leaves.

  The gather is energy-normalised so that SSS_STEPS does not change the overall
  brightness, only the softness.

================================================================================
*/

#ifndef MUON_COMMON_SSS_GLSL
#define MUON_COMMON_SSS_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/brdf.glsl"
#include "/lib/common/sampling.glsl"
#include "/lib/common/material.glsl"


/*
 * Screen-space gather. Samples the already-lit image in the direction the
 * light is coming from, weighting each tap by how much of the surface normal
 * agrees with the light.
 *
 *   uv              current pixel
 *   view_pos        view-space position of the surface
 *   world_normal    surface normal
 *   albedo          material albedo (also the scatter tint)
 *   light_dir       unit vector towards the light, world space
 *   scatter_amount  0..1, from LabPBR porosity
 */
vec3 muon_subsurface_gather(
    vec2 uv,
    vec3 view_pos,
    vec3 world_normal,
    vec3 albedo,
    vec3 light_dir,
    float scatter_amount
) {
#if !defined SUBSURFACE_SCATTERING
    return vec3(0.0);
#else
    if (scatter_amount <= 0.01) {
        return vec3(0.0);
    }

    /* The gather radius shrinks with distance so that it stays sub-block and
       never bleeds across a silhouette. */
    float distance = length(view_pos);
    float radius = SSS_RADIUS * clamp(18.0 / max(distance, 1.0), 0.25, 1.0);

    /* Project the light direction into screen space. */
    vec3 probe_point = muon_view_to_world_pos(view_pos) + light_dir * radius;
    vec4 clip = muonFrame.projection * (muonFrame.view * vec4(probe_point, 1.0));
    if (clip.w <= 0.0) {
        return vec3(0.0);
    }
    vec2 light_uv = clip.xy / clip.w * 0.5 + 0.5;
    vec2 step_dir = (light_uv - uv) * radius;
    step_dir = clamp(step_dir, -muon_inv_viewport() * 48.0, muon_inv_viewport() * 48.0);

    float rotation = muon_pixel_rotation(gl_FragCoord.xy);
    float weight_sum = 0.0;
    vec3 accumulated = vec3(0.0);

    for (int i = 0; i < SSS_STEPS; i++) {
        float t = (float(i) + 1.0) / float(SSS_STEPS);
        vec2 offset = step_dir * t;

        /* Spread the taps perpendicular to the light direction so that the
           gather is a band rather than a line. */
        float spread = (fract(rotation * 3.17 + float(i) * 0.618) - 0.5) * 2.0;
        offset += vec2(-step_dir.y, step_dir.x) * spread * 0.45;

        vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
        vec3 sample_color = texture(colortex0, sample_uv).rgb;

        float weight = exp(-t * 2.4) * (1.0 - t * 0.35);
        accumulated += sample_color * weight;
        weight_sum += weight;
    }

    accumulated /= max(weight_sum, MUON_EPSILON);

    /* Tint by the material and modulate by how back-lit the surface is. */
    float back_light = muon_saturate(dot(-muon_world_to_view_dir(world_normal), muon_world_to_view_dir(light_dir)));
    vec3 tint = albedo * mix(vec3(1.0), vec3(1.15, 0.85, 0.55), back_light);

    return accumulated * tint * (scatter_amount * SSS_STRENGTH * 0.55);
#endif
}

/*
 * Analytic thin-surface transmission. Cheaper than the gather and used for
 * single-block plants where a screen-space band would be undefined.
 */
vec3 muon_subsurface_transmission(
    vec3 albedo,
    vec3 world_normal,
    vec3 view_dir,
    vec3 light_dir,
    float scatter_amount
) {
#if !defined SUBSURFACE_SCATTERING
    return vec3(0.0);
#else
    float n_dot_l = dot(world_normal, light_dir);
    float wrapped = muon_diffuse_wrap(n_dot_l, 0.55);

    vec3 transmission = muon_diffuse_transmission(
        albedo,
        view_dir,
        light_dir,
        1.0,
        scatter_amount * SSS_STRENGTH
    );

    return (albedo * wrapped * MUON_INV_PI + transmission) * scatter_amount;
#endif
}

#endif // MUON_COMMON_SSS_GLSL
