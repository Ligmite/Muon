/*
================================================================================

  Muon Shaders - lib/common/ssr.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Screen-space reflections.

  The tracer marches in view space, projects each step and compares against the
  opaque depth buffer, then refines the hit with a short binary search. Rays are
  jittered by roughness so that a rough surface integrates to a blurred
  reflection instead of a mirror image with sparkle.

  Reflections are blended out towards the screen edge (where the march has no
  information) and fall back to the analytic sky reflection, which is why Muon
  can afford an aggressive step count.

================================================================================
*/

#ifndef MUON_COMMON_SSR_GLSL
#define MUON_COMMON_SSR_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/sampling.glsl"
#include "/lib/common/encoding.glsl"


struct MuonReflection {
    vec3 color;
    float hit;
    float confidence;
    float distance;
};

/* Projects a view-space point to screen UV; returns false when behind the eye. */
bool muon_project_view(vec3 view_pos, out vec2 uv, out float view_depth) {
    vec4 clip = muonFrame.projection * vec4(view_pos, 1.0);
    if (clip.w <= 0.0) {
        uv = vec2(0.0);
        view_depth = 0.0;
        return false;
    }
    uv = clip.xy / clip.w * 0.5 + 0.5;
    view_depth = -view_pos.z;
    return true;
}

MuonReflection muon_reflection_empty() {
    MuonReflection r;
    r.color = vec3(0.0);
    r.hit = 0.0;
    r.confidence = 0.0;
    r.distance = 0.0;
    return r;
}

/*
 * Traces a single reflection ray.
 *
 *   view_pos        origin of the ray in view space
 *   view_dir        incident direction (from the eye towards the surface)
 *   view_normal     surface normal in view space
 *   roughness       perceptual roughness, drives the jitter cone
 *   dither          0..1 per-pixel noise source
 */
MuonReflection muon_trace_reflection(
    vec3 view_pos,
    vec3 view_dir,
    vec3 view_normal,
    float roughness,
    float dither
) {
    MuonReflection result = muon_reflection_empty();

#if !defined SCREENSPACE_REFLECTIONS
    return result;
#else
    vec3 ray_dir = muon_reflect(view_dir, view_normal);

    /* Rough surfaces get a randomised direction within a cone that grows with
       roughness; combined with temporal accumulation this converges to a
       genuinely blurred reflection. */
    if (roughness > 0.02) {
        vec3 random_dir = muon_uniform_sphere(vec2(dither, fract(dither * 7.13)));
        ray_dir = normalize(mix(ray_dir, random_dir, roughness * 0.85));
    }

    /* Keep the ray in front of the surface so it cannot self-intersect. */
    if (dot(ray_dir, view_normal) < 0.0) {
        return result;
    }

    vec3 origin = view_pos + view_normal * 0.035;

    float step_size = MUON_SSR_MAX_DISTANCE / float(MUON_SSR_STEPS);
    float jitter = dither * step_size;
    float previous_t = 0.0;

    for (int i = 0; i < MUON_SSR_STEPS; i++) {
        float t = jitter + step_size * (float(i) + 1.0);
        vec3 ray_point = origin + ray_dir * t;

        vec2 sample_uv;
        float ray_depth;
        if (!muon_project_view(ray_point, sample_uv, ray_depth)) {
            break;
        }
        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            break;
        }

        float scene_depth = muon_linear_depth(texture(depthtex0, sample_uv).r);
        float thickness = max(step_size * 1.8, 0.05);

        if (scene_depth > 0.0 && ray_depth > scene_depth && ray_depth < scene_depth + thickness) {
            /* Binary search between the last free point and this hit. */
            float low = previous_t;
            float high = t;
            for (int refine = 0; refine < MUON_SSR_REFINE_STEPS; refine++) {
                float mid = 0.5 * (low + high);
                vec3 mid_point = origin + ray_dir * mid;
                vec2 mid_uv;
                float mid_depth;
                if (!muon_project_view(mid_point, mid_uv, mid_depth)) {
                    break;
                }
                float mid_scene = muon_linear_depth(texture(depthtex0, mid_uv).r);
                if (mid_depth > mid_scene) {
                    high = mid;
                } else {
                    low = mid;
                }
            }

            vec3 hit_point = origin + ray_dir * high;
            vec2 hit_uv;
            float hit_depth;
            if (muon_project_view(hit_point, hit_uv, hit_depth)) {
                /* Reject hits that would sample across a depth discontinuity. */
                float verify = muon_linear_depth(texture(depthtex0, hit_uv).r);
                if (abs(verify - hit_depth) < thickness * 2.5) {
                    result.color = texture(colortex0, hit_uv).rgb;
                    result.hit = 1.0;
                    result.distance = high;

                    /* Fade at the screen edge and with distance. */
                    vec2 edge = smoothstep(vec2(0.0), vec2(SSR_EDGE_FADE), hit_uv)
                        * smoothstep(vec2(0.0), vec2(SSR_EDGE_FADE), vec2(1.0) - hit_uv);
                    float distance_fade = 1.0 - muon_saturate(high / MUON_SSR_MAX_DISTANCE);
                    result.confidence = edge.x * edge.y * distance_fade;
                    return result;
                }
            }
            break;
        }

        previous_t = t;

        /* Very far misses are not worth continuing. */
        if (ray_depth > muonFrame.depthParams.y) {
            break;
        }
    }

    return result;
#endif
}

/*
 * Blends a screen-space hit with the analytic sky reflection. Called by both
 * the deferred water pass and the general composite pass so that the two never
 * disagree about how a reflection is composed.
 */
vec3 muon_compose_reflection(
    MuonReflection reflection,
    vec3 sky_reflection,
    float fresnel,
    float roughness
) {
    vec3 base = mix(sky_reflection, reflection.color, reflection.hit * reflection.confidence);

    /* Rough surfaces lean on the sky term because a single screen-space ray
       cannot represent a wide lobe. */
    float sky_weight = muon_saturate(roughness * 1.4);
    base = mix(base, sky_reflection, sky_weight * (1.0 - reflection.hit));

    return base * fresnel;
}

#endif // MUON_COMMON_SSR_GLSL
