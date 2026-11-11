/*
================================================================================

  Muon Shaders - program/deferred1.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  The opaque lighting pass - the only place in Muon where a surface is lit.

  Sky pixels are identified by the far depth and filled with atmosphere, sun,
  moon, stars and volumetric clouds. Every other pixel is shaded through
  lib/common/surface.glsl with the material that the geometry stage wrote.

  Target:
      0  HDR scene colour

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_read.glsl"
#include "/lib/common/surface.glsl"
#include "/lib/common/atmosphere.glsl"
#include "/lib/common/clouds.glsl"
#include "/lib/common/sss.glsl"
#include "/lib/common/water.glsl"

in vec2 texcoord;

layout(location = 0) out vec4 out_scene;

/* RENDERTARGETS: 0 */

// -----------------------------------------------------------------------------
//  Sky elements
// -----------------------------------------------------------------------------

float muon_angular_distance(vec3 a, vec3 b) {
    return acos(clamp(dot(a, b), -1.0, 1.0));
}

vec3 muon_sun_disc(vec3 world_dir) {
#if !defined SUN_DISC
    return vec3(0.0);
#else
    float radius = SUN_ANGULAR_RADIUS * 0.545 * MUON_DEG2RAD;
    float angle = muon_angular_distance(world_dir, muon_sun_direction());
    if (angle > radius) {
        return vec3(0.0);
    }
    float normalized = angle / radius;
    /* Limb darkening: the centre of the disc is hotter than its edge. */
    float limb = sqrt(max(1.0 - normalized * normalized, 0.0));
    return MUON_SUN_TINT * (muon_sun_color() * (limb * 8.0 + 2.0));
#endif
}

vec3 muon_moon_disc(vec3 world_dir) {
#if !defined MOON_DISC
    return vec3(0.0);
#else
    float radius = 0.60 * MUON_DEG2RAD;
    float angle = muon_angular_distance(world_dir, muon_moon_direction());
    if (angle > radius) {
        return vec3(0.0);
    }

    /* Crater texture, evaluated on the disc's local coordinates. */
    vec3 local = world_dir * 240.0;
    float craters = muon_worley_3d(local).x;
    float surface = mix(0.55, 1.0, muon_saturate(1.0 - craters * 1.4));

    float normalized = angle / radius;
    float limb = sqrt(max(1.0 - normalized * normalized, 0.0));

    return MUON_MOON_TINT * (muon_moon_color() * (surface * limb * 9.0 + 1.5));
#endif
}

vec3 muon_stars(vec3 world_dir) {
#if !defined STARS
    return vec3(0.0);
#else
    float visibility = muon_smoothstep(0.02, -0.16, muon_sun_direction().y);
    visibility *= 1.0 - muon_rain_strength();
    visibility *= 1.0 - muon_saturate(muon_eye_sky_light() * 0.6);

    if (visibility <= 0.001 || world_dir.y < 0.0) {
        return vec3(0.0);
    }

    vec3 p = world_dir * 260.0;
    vec3 cell = floor(p);
    vec3 local = fract(p);

    float seed = muon_rand_3d(cell, 17u);
    if (seed < 0.9965) {
        return vec3(0.0);
    }

    vec3 offset = muon_rand_vec3(muon_hash_u32(uint(ivec3(cell).x) * 31u + uint(ivec3(cell).y) * 71u + uint(ivec3(cell).z)));
    float distance = length(local - offset);
    float intensity = smoothstep(0.16, 0.0, distance);

    vec3 tint = mix(vec3(1.0, 0.86, 0.72), vec3(0.72, 0.84, 1.0), fract(seed * 137.0));
    float twinkle = 0.75 + 0.25 * sin(muon_time_counter() * 2.3 + seed * 90.0);

    return tint * (intensity * twinkle * visibility * STARS_INTENSITY * 0.6);
#endif
}

vec3 muon_sky(vec3 world_dir) {
    vec3 color = vec3(0.0);

#if defined ATMOSPHERE
    color = muon_sky_radiance(world_dir, 8);
#endif

    color += muon_sun_disc(world_dir);
    color += muon_moon_disc(world_dir);
    color += muon_stars(world_dir);

#if defined CLOUDS
    MuonCloudSample clouds = muon_cloud_raymarch(
        muon_camera_position(),
        world_dir,
        muonFrame.depthParams.y * 4.0,
        MUON_CLOUD_STEPS
    );
    color = color * clouds.transmittance + clouds.scattering;
#endif

    color = muon_saturation(color, SKY_SATURATION);

    /* Looking down at the void should not show a second sky. */
    if (world_dir.y < 0.0) {
        color *= mix(0.15, 1.0, muon_saturate(world_dir.y + 1.0));
    }

    return color;
}

// -----------------------------------------------------------------------------
//  Main
// -----------------------------------------------------------------------------

void main() {
    MUON_FRAME_INIT();

    vec2 uv = texcoord;
    float depth = texture(depthtex0, uv).r;

    if (depth >= 1.0) {
        vec3 view_ray = muon_view_pos_from_depth(uv, 1.0);
        vec3 world_dir = normalize(muon_view_to_world_dir(view_ray));
        out_scene = vec4(muon_sky(world_dir), 1.0);
        return;
    }

    MuonMaterial material = muon_read_opaque_material(uv);
    float linear_depth = muon_read_opaque_linear_depth(uv);
    vec3 view_pos = muon_view_pos_from_linear_depth(uv, linear_depth);
    vec3 world_pos = muon_view_to_world_pos(view_pos);

    vec4 ao_texel = texture(colortex14, uv);
    float ao = ao_texel.r;
    vec3 bent_view = muon_octahedral_decode(ao_texel.gb);
    vec3 bent_normal = normalize(muon_view_to_world_dir(bent_view));

    float dither = muon_interleaved_gradient_noise(gl_FragCoord.xy);
    vec3 color = muon_shade_surface(
        material,
        world_pos,
        view_pos,
        material.normal,
        ao,
        bent_normal,
        dither
    );

    /* Underwater: the whole opaque pass is tinted by the medium. */
    color = muon_underwater_tint(color, length(view_pos));

    out_scene = vec4(color, 1.0);
}
