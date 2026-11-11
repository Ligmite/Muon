/*
================================================================================

  Muon Shaders - program/composite1.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Screen-space reflections and global illumination.

  Reflections are traced for every opaque surface whose specular weight is high
  enough to matter; the sky is used as the fallback so a ray that leaves the
  screen never goes black. Global illumination is traced with the screen-space
  path tracer, and when RTGI_BOUNCES is greater than one the previous frame's
  indirect field becomes a second light source, which turns a single gather into
  a temporally accumulated multi-bounce solution.

  Targets:
      13  reflection radiance (already weighted by the BRDF)
       7  indirect diffuse radiance (read and written, with buffer flipping)

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/material.glsl"
#include "/lib/common/gbuffer_read.glsl"
#include "/lib/common/ssr.glsl"
#include "/lib/common/raytrace.glsl"
#include "/lib/common/atmosphere.glsl"


in vec2 texcoord;

layout(location = 0) out vec4 out_reflection;
layout(location = 1) out vec4 out_indirect;

/* RENDERTARGETS: 13,7 */

/*
 * Weight of the temporally accumulated second bounce. Each extra bounce carries
 * less energy, so the contribution falls off as the configuration asks for more
 * bounces; without this the indirect term would grow without bound over frames.
 */
float muon_mix_bounce_weight() {
    return RTGI_BOUNCES >= 3 ? 0.55 : 0.75;
}

void main() {
    MUON_FRAME_INIT();

    vec2 uv = texcoord;
    float dither = muon_interleaved_gradient_noise(gl_FragCoord.xy);

    out_reflection = vec4(0.0);
    out_indirect = vec4(0.0);

    float opaque_depth = texture(depthtex0, uv).r;
    if (opaque_depth >= 1.0) {
        return;
    }

    /* Water and translucent surfaces are shaded against the lit image inside
       deferred2; tracing them again here would double-count their reflection. */
    float translucent_depth = texture(depthtex1, uv).r;
    if (muon_pixel_has_translucent(uv, opaque_depth, translucent_depth)) {
        return;
    }

    MuonMaterial material = muon_read_opaque_material(uv);
    float linear_depth = muon_read_opaque_linear_depth(uv);
    vec3 view_pos = muon_view_pos_from_linear_depth(uv, linear_depth);
    vec3 world_pos = muon_view_to_world_pos(view_pos);
    vec3 view_dir = normalize(view_pos);
    vec3 view_normal = normalize(muon_world_to_view_dir(material.normal));

    float n_dot_v = muon_saturate(dot(material.normal, normalize(muon_camera_position() - world_pos)));
    vec3 fresnel = muon_fresnel_schlick_roughness(material.f0, n_dot_v, material.roughness);

    /* --- specular reflection ------------------------------------------- */

    if (muon_luminance(fresnel) > 0.005) {
        MuonReflection reflection = muon_trace_reflection(
            view_pos,
            view_dir,
            view_normal,
            material.roughness,
            dither
        );

        vec3 world_reflect = normalize(muon_view_to_world_dir(muon_reflect(view_dir, view_normal)));
        vec3 sky_reflection = muon_sky_radiance(world_reflect, 4);

        vec3 reflected = muon_compose_reflection(
            reflection,
            sky_reflection,
            1.0,
            material.roughness
        );

        float weight = muon_saturate(muon_luminance(fresnel) * MUON_SSR_STRENGTH);
        out_reflection = vec4(reflected * weight, weight);
    }

    /* --- indirect diffuse ----------------------------------------------- */

#if defined RTGI
    vec3 indirect = muon_trace_gi_iteration(
        gl_FragCoord.xy,
        view_pos,
        view_normal,
        material.normal,
        colortex0,
        0,
        dither
    );

#if RTGI_BOUNCES >= 2
    /* The previous frame's indirect field acts as a second bounce: light that
       bounced off something off-screen still contributes. */
    vec3 second_bounce = muon_trace_gi_iteration(
        gl_FragCoord.xy,
        view_pos,
        view_normal,
        material.normal,
        colortex7,
        1,
        dither
    );
    indirect += second_bounce * muon_mix_bounce_weight();
#endif

    if (muon_is_finite(indirect)) {
        vec3 albedo = muon_diffuse_albedo(material);
        out_indirect = vec4(albedo * indirect * MUON_RTGI_STRENGTH, 1.0);
    }
#endif
}


