/*
================================================================================

  Muon Shaders - lib/common/surface.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  The single surface-lighting entry point of the renderer.

  Every opaque surface, every translucent surface and every water body is lit
  by muon_shade_surface(). The deferred passes only decide *which* material to
  feed it and what to do with the result - they never re-derive a BRDF, a
  shadow term or an ambient term. That is the difference between a renderer and
  a pile of passes.

  Contributions, in the order they are added:

    emissive      the material's own emission, tinted by its albedo
    direct        sun or moon, PCSS shadowed, GGX specular + Lambert diffuse
    transmission  thin-surface subsurface scattering for foliage
    sky ambient   hemispherical sky irradiance, bent by AO and the lightmap
    bounce        a single cheap indirect term standing in for GI when the
                  path tracer is off
    blocklight    Minecraft's own block-light level with a physical falloff

================================================================================
*/

#ifndef MUON_COMMON_SURFACE_GLSL
#define MUON_COMMON_SURFACE_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/constants.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/brdf.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/shadow.glsl"
#include "/lib/common/atmosphere.glsl"
#include "/lib/common/clouds.glsl"
#include "/lib/common/sss.glsl"

// -----------------------------------------------------------------------------
//  Individual light contributions
// -----------------------------------------------------------------------------

vec3 muon_blocklight_contribution(MuonMaterial m) {
    if (m.blocklight <= 0.001) {
        return vec3(0.0);
    }

    /* Minecraft light levels are already a falloff curve; squaring them makes
       torch pools tighter and warmer without changing their peak. */
    float level = m.blocklight * m.blocklight;
    return MUON_BLOCKLIGHT_TINT * (level * MUON_BLOCKLIGHT_INTENSITY * BLOCKLIGHT_STRENGTH)
        * (m.albedo * MUON_INV_PI);
}

vec3 muon_emission_contribution(MuonMaterial m) {
    if (m.emission <= 0.0001) {
        return vec3(0.0);
    }
    /* Emissive blocks read as their own albedo glowing, which keeps coloured
       light sources (sea lanterns, shroomlights) the right colour. */
    return m.albedo * (m.emission * MUON_EMISSION_STRENGTH * 4.0);
}

/*
 * Direct lighting. `shadow` is passed in because the caller may have already
 * evaluated it (the water pass reuses the background's shadow term).
 */
vec3 muon_direct_contribution(
    MuonMaterial m,
    vec3 world_normal,
    vec3 view_dir,
    vec3 light_dir,
    vec3 light_color,
    float shadow
) {
    if (shadow <= 0.0005 || m.emission > 8.0) {
        return vec3(0.0);
    }

    float n_dot_l = max(dot(world_normal, light_dir), 0.0);
    float n_dot_v = max(dot(world_normal, view_dir), 0.0);
    if (n_dot_l <= 0.0 || n_dot_v <= 0.0) {
        return vec3(0.0);
    }

    float alpha = muon_alpha_from_smoothness(m.smoothness);
    vec3 f0 = m.f0;
    vec3 diffuse_albedo = muon_diffuse_albedo(m);

    vec3 specular = muon_specular_ggx(world_normal, view_dir, light_dir, f0, alpha);

    /* Energy that is neither reflected specularly nor absorbed is available
       for diffuse transport. */
    float specular_energy = muon_luminance(muon_fresnel_schlick(f0, n_dot_v));
    vec3 diffuse = diffuse_albedo * (MUON_INV_PI * (1.0 - muon_saturate(specular_energy)));

    vec3 radiance = light_color * shadow * n_dot_l;
    return radiance * (specular + diffuse);
}

/*
 * Cheap indirect term. Without a world-space tracer there is no way to know
 * what a surface actually sees, so this approximates bounce light with the
 * sky irradiance filtered through the material's own albedo and the amount of
 * sky it can see. It is deliberately subtle: its job is to stop shadowed
 * surfaces from crushing to black, not to replace the path tracer.
 */
vec3 muon_bounce_contribution(MuonMaterial m, vec3 bent_normal) {
#if !defined BOUNCED_LIGHT
    return vec3(0.0);
#else
    float sky_visibility = muon_saturate(m.skylight * m.ao);
    vec3 sky = muon_sky_ambient(bent_normal);
    vec3 bounced = sky * m.albedo * (MUON_INV_PI * BOUNCED_LIGHT_STRENGTH * 1.6 * sky_visibility);
    return bounced;
#endif
}

// -----------------------------------------------------------------------------
//  Main entry point
// -----------------------------------------------------------------------------

vec3 muon_shade_surface(
    MuonMaterial m,
    vec3 world_pos,
    vec3 view_pos,
    vec3 world_normal,
    float ao,
    vec3 bent_normal,
    float dither
) {
    /* Direction from the surface towards the eye. */
    vec3 view_dir = normalize(muon_camera_position() - world_pos);

    vec3 light_dir = muon_direct_light_direction();
    vec3 light_color = muon_direct_light_color();

    float shadow = 1.0;
#if defined SHADOW
    shadow = muon_direct_visibility(world_pos, world_normal, view_pos, light_dir, length(view_pos));
#endif

    /* Cloud shadows multiply the sun's contribution, so a passing cloud deck
       sweeps across the terrain. */
#if defined CLOUD_SHADOWS
    if (muon_sun_angle() < 0.5) {
        shadow *= muon_cloud_shadow(world_pos, light_dir);
    }
#endif

    vec3 color = vec3(0.0);

    color += muon_emission_contribution(m);
    color += muon_direct_contribution(m, world_normal, view_dir, light_dir, light_color, shadow);

#if defined SUBSURFACE_SCATTERING
    if (muon_uses_sss(m)) {
        float scatter = muon_saturate(m.porosity * 1.4);
        color += muon_subsurface_transmission(m.albedo, world_normal, view_dir, light_dir, scatter)
            * light_color * shadow * muon_saturate(dot(world_normal, light_dir) + 0.6);
    }
#endif

    /* Sky ambient: hemisphere irradiance, occluded by AO and the lightmap. */
    vec3 ambient = muon_sky_ambient(bent_normal);
    float sky_occlusion = muon_saturate(m.skylight) * muon_saturate(ao);
    color += ambient * m.albedo * (MUON_INV_PI * sky_occlusion);

#if defined SUBSURFACE_SCATTERING
    if (muon_uses_sss(m)) {
        /* Foliage catches a little ambient from below as well. */
        color += ambient * m.albedo * (m.porosity * 0.18);
    }
#endif

    color += muon_bounce_contribution(m, bent_normal);
    color += muon_blocklight_contribution(m);

    /* A floor keeps pitch-black caves from clipping to pure zero, which the
       temporal filter and the bloom chain both dislike. */
    color = max(color, m.albedo * MINIMUM_LIGHT);

    return color;
}

#endif // MUON_COMMON_SURFACE_GLSL
