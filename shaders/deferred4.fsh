#version 400 compatibility
/*
================================================================================

  Muon Shaders
  deferred4.fsh - deferred shading

  The heart of the raster path: reconstruct every surface, resolve its shadow,
  ambient occlusion and reflections, and shade it. Sky pixels are resolved with
  the physical atmosphere. Clouds and volumetrics are composited on top.

  RENDERTARGETS: 0,12

    colortex0  shaded scene colour (HDR)
    colortex12 ray tracing history (copy of colortex8)

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/color.glsl"
#include "/lib/encoding.glsl"
#include "/lib/ao.glsl"
#include "/lib/volumetrics.glsl"
#include "/lib/ssr.glsl"
#include "/lib/lighting.glsl"
#include "/lib/gbuffer.glsl"
#include "/lib/denoise.glsl"
#include "/lib/pathtracing.glsl"
#include "/lib/water.glsl"

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec4 out_history;

/* RENDERTARGETS: 0,12 */

uniform sampler2D colortex4;  // ambient occlusion
uniform sampler2D colortex5;  // previous frame colour (SSR source)
uniform sampler2D colortex6;  // volumetrics
uniform sampler2D colortex7;  // clouds
uniform sampler2D colortex8;  // ray tracing result

vec3 nether_sky(vec3 dir) {
    float glow = exp(-abs(dir.y) * 3.0);
    vec3 color = vec3(0.35, 0.06, 0.03) * glow;
    color += vec3(0.10, 0.02, 0.01);
    return color * 0.6;
}

vec3 end_sky(vec3 dir) {
    vec3 color = mix(vec3(0.06, 0.03, 0.12), vec3(0.16, 0.09, 0.28), clamp01(dir.y * 0.5 + 0.5));

    // Sparse end stars
    vec3 p = dir * 180.0;
    ivec3 cell = ivec3(floor(p));
    float h = hash13i(cell);

    if (h > 0.998) {
        vec3 offset = hash33i(cell) * 0.8 + 0.1;
        float dist = length(p - vec3(cell) - offset);
        color += vec3(0.8, 0.7, 1.0) * smoothstep(0.15, 0.0, dist) * 2.0;
    }

    return color;
}

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    ivec2 pixel = ivec2(gl_FragCoord.xy);

    float depth = texture(depthtex1, uv).r;

    vec3 color;

    bool is_sky = depth >= 1.0;

    if (is_sky) {
        vec3 ray_dir = normalize(screen_to_scene_space(vec3(uv, 1.0)));

        if (world == -1) {
            color = nether_sky(ray_dir);
        } else if (world == 1) {
            color = end_sky(ray_dir);
        } else {
            vec3 sun_dir = sun_dir_scene();
            vec3 moon_dir = moon_dir_scene();

            vec3 sun_color = blackbody(SUN_TEMPERATURE) * SUN_I * 14.0;
            vec3 moon_color = blackbody(MOON_TEMPERATURE) * 4.0;

            color = sky_color(ray_dir, sun_dir, moon_dir, sun_color, moon_color, true);
        }
    } else {
        // ----- surface shading -----
        SurfaceData surface = load_surface(uv, depth);

        float dither = interleaved_gradient_noise(gl_FragCoord.xy, float(frameCounter));

        // Ambient occlusion (half resolution, bilinear is plenty)
        float shader_ao = texture(colortex4, uv).r;
        surface.ao = apply_ao(shader_ao, surface.ao, 1.0);

        vec3 light_dir = shadow_light_dir_scene();

        surface.shadow = direct_light_visibility(surface.scene_pos, surface.normal, light_dir, dither);

        // Reflection radiance
        vec3 view_pos = scene_to_view_space(surface.scene_pos);
        vec3 view_normal = normalize(mat3(gbufferModelView) * surface.normal);

        vec3 scene_normal = surface.normal;
        vec3 reflection = sky_gradient(reflect(-surface.view_dir, scene_normal), light_dir);

#if REFLECTIONS == 2
        SSRResult ssr = ssr_trace(view_pos, view_normal, surface.roughness, dither, colortex5);
        if (ssr.confidence > 0.0) {
            reflection = mix(reflection, ssr.color, ssr.confidence);
        }
#endif

#if RAY_TRACING == 1
        {
            vec3 rt_reflection = trace_reflection_rt(surface, dither);
            vec4 rt_history = texture(colortex8, uv);
            float rt_confidence = clamp01(rt_history.a * 4.0);
            reflection = mix(reflection, rt_reflection, rt_confidence);
        }
#endif

        color = shade_surface(surface, light_dir, reflection);

        // Ray traced indirect lighting
#if RAY_TRACING >= 2
        {
            vec4 rt = texture(colortex8, uv);
            float rt_confidence = clamp01(rt.a * 4.0);

            vec3 rt_color = rt.rgb;

#ifdef RT_DENOISE
            if (RT_DENOISE_STRENGTH > 0.0) {
                rt_color = spatial_denoise(colortex8, colortex2, uv, depth, scene_normal, RT_DENOISE_STRENGTH);
            }
#endif

#if RAY_TRACING >= 3
            // Full path tracing replaces the analytic lighting entirely once
            // the history is long enough.
            color = mix(color, rt_color, rt_confidence * 0.9);
#else
            // Indirect only: add it on top of the raster direct light.
            color += rt_color * RT_GI_STRENGTH * 0.55 * mix(0.3, 1.0, rt_confidence);
#endif
        }
#endif

        // Nether and end ambience
        if (world == -1) {
            color = mix(color, color * vec3(1.25, 0.72, 0.62), 0.55);
            color += vec3(0.06, 0.015, 0.005) * surface.albedo;
        } else if (world == 1) {
            color = mix(color, color * vec3(0.85, 0.82, 1.15), 0.4);
        }

        // Blindness / darkness
        if (blindness > 0.0) {
            color = desaturate(color, clamp01(blindness * 1.5));
            color *= 1.0 - blindness * 0.7;
        }

        if (nightVision > 0.0) {
            color *= 1.0 + nightVision * 1.5;
        }
    }

    // Clouds, fog and translucents are composited in composite.fsh, after the
    // translucent layer has been shaded against the opaque scene.

    // Debug view
#if DEBUG_VIEW == 1
    color = texture(colortex1, uv).rgb;
#elif DEBUG_VIEW == 2
    color = gbuffer_normal(uv) * 0.5 + 0.5;
#elif DEBUG_VIEW == 3
    color = vec3(texture(colortex4, uv).r);
#elif DEBUG_VIEW == 7
    color = texture(colortex8, uv).rgb;
#elif DEBUG_VIEW == 8
    color = vec3(texture(colortex2, uv).z);
#endif

    out_color = vec4(sanitize_color(color), 1.0);
    out_history = texture(colortex8, uv);
}
