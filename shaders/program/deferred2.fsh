/*
================================================================================

  Muon Shaders - program/deferred2.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Translucent compositing and volumetric fog.

  The opaque image in colortex0 already contains the lit surface behind any
  water. This pass shades the translucent layer against that image, refracts it
  through Snell's law, extinguishes it with Beer-Lambert, and then applies the
  volumetric medium to the composite.

  Fog is applied here rather than in the lighting pass so that it also covers
  the water surface, which is the physically correct order: the medium sits
  between the eye and everything else.

  Target:
      0  HDR scene colour (read and written, with buffer flipping)

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_read.glsl"
#include "/lib/common/surface.glsl"
#include "/lib/common/water.glsl"
#include "/lib/common/ssr.glsl"
#include "/lib/common/volumetric.glsl"
#include "/lib/common/atmosphere.glsl"

in vec2 texcoord;

layout(location = 0) out vec4 out_scene;

/* RENDERTARGETS: 0 */

// -----------------------------------------------------------------------------
//  Water
// -----------------------------------------------------------------------------

vec3 muon_shade_water(
    MuonMaterial material,
    vec3 view_pos,
    vec3 world_pos,
    vec3 view_normal,
    float background_linear_depth,
    vec2 uv,
    float dither
) {
    vec3 view_dir = normalize(view_pos);
    vec3 world_normal = material.normal;

    float fresnel = muon_water_fresnel(world_normal, normalize(muon_camera_position() - world_pos));

    /* --- refraction -------------------------------------------------- */

    vec2 refraction_uv = uv + muon_water_refraction_offset(uv, view_pos, view_normal, 1.0);
    refraction_uv = clamp(refraction_uv, vec2(0.0), vec2(1.0));
    vec3 background = texture(colortex0, refraction_uv).rgb;

    /* Path length through the water: the distance between the two depth
       layers, stretched from view-axis distance to ray distance. */
    float thickness = max(background_linear_depth - (-view_pos.z), 0.0);
    thickness *= length(view_pos) / max(-view_pos.z, 0.001);

    vec3 transmittance = muon_water_transmittance(thickness);
    vec3 refracted = background * transmittance + muon_water_inscatter(thickness);

    /* Caustics on the bottom, projected from the surface pattern. */
    float caustics = muon_water_caustics(world_pos.xz, thickness, length(view_pos));
    refracted += material.albedo * (caustics * muon_direct_light_color() * 0.35);

    /* --- reflection --------------------------------------------------- */

    vec3 world_reflect = normalize(muon_reflect(view_dir, world_normal));
    vec3 world_reflect_ws = normalize(muon_view_to_world_dir(world_reflect));

    MuonReflection reflection = muon_trace_reflection(
        view_pos,
        view_dir,
        view_normal,
        material.roughness,
        dither
    );

    vec3 sky_reflection = muon_sky_radiance(world_reflect_ws, 6);
    vec3 reflected = muon_compose_reflection(reflection, sky_reflection, 1.0, material.roughness);

    /* --- combine ------------------------------------------------------ */

    float reflection_weight = fresnel * MUON_WATER_REFLECTION;
    vec3 color = mix(refracted, reflected, muon_saturate(reflection_weight));

    /* Rain darkens the water surface and roughens its reflection. */
    color = mix(color, color * vec3(0.82, 0.88, 0.92), muon_rain_strength() * 0.25);

    return color;
}

// -----------------------------------------------------------------------------
//  Main
// -----------------------------------------------------------------------------

void main() {
    MUON_FRAME_INIT();

    vec2 uv = texcoord;
    float opaque_depth = texture(depthtex0, uv).r;
    float translucent_depth = texture(depthtex1, uv).r;

    vec3 color = texture(colortex0, uv).rgb;
    float surface_distance = opaque_depth >= 1.0
        ? muonFrame.depthParams.y
        : muon_linear_depth(opaque_depth);

    float fog_depth = opaque_depth >= 1.0 ? 1.0 : opaque_depth;
    vec3 view_ray = muon_view_pos_from_depth(uv, fog_depth);
    vec3 world_dir = normalize(muon_view_to_world_dir(view_ray));

    float dither = muon_interleaved_gradient_noise(gl_FragCoord.xy);

    if (muon_pixel_has_translucent(uv, opaque_depth, translucent_depth)) {
        MuonMaterial material = muon_read_translucent_material(uv);
        float linear_depth = muon_read_translucent_linear_depth(uv);
        vec3 view_pos = muon_view_pos_from_linear_depth(uv, linear_depth);
        vec3 world_pos = muon_view_to_world_pos(view_pos);
        vec3 view_normal = normalize(muon_world_to_view_dir(material.normal));

        vec3 shaded;
        if (material.id == MUON_MAT_WATER) {
            shaded = muon_shade_water(material, view_pos, world_pos, view_normal, surface_distance, uv, dither);
        } else {
            /* Glass, ice and other translucent blocks are shaded with the same
               surface model as opaque geometry, then alpha-blended. */
            float ao = texture(colortex14, uv).r;
            shaded = muon_shade_surface(material, world_pos, view_pos, material.normal, ao, material.normal, dither);
        }

        float alpha = muon_saturate(material.alpha);
        color = mix(color, shaded, alpha);
        surface_distance = length(view_pos);
    }

    /* --- volumetric medium -------------------------------------------- */

    MuonVolumetric fog = muon_volumetric_fog(surface_distance, world_dir);
    color = muon_apply_volumetric(color, fog);

    /* --- underwater ---------------------------------------------------- */

    if (muon_eye_in_water() > 0.5) {
        color = muon_underwater_tint(color, surface_distance * 0.65);
    }

    out_scene = vec4(color, 1.0);
}
