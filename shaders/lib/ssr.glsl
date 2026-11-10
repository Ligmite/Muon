/*
================================================================================

  Muon Shaders
  lib/ssr.glsl - screen space reflections

  View-space ray marching against the depth buffer with binary refinement and a
  thickness test. Reflection source is the previous frame's resolved colour
  buffer, which is what makes GPU-side feedback loops unnecessary.

  Misses fall back to the analytic sky, so water and metal always have
  something to reflect.

================================================================================
*/

#if !defined MUON_SSR
#define MUON_SSR

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"
#include "/lib/brdf.glsl"
#include "/lib/atmosphere.glsl"

// Depth including LoD mods
float ssr_scene_depth(vec2 uv) {
    float depth = texture(depthtex1, uv).r;

#ifdef DISTANT_HORIZONS
    if (depth >= 1.0) {
        float dh_depth = texture(dhDepthTex0, uv).r;
        if (dh_depth < 1.0) return dh_depth;
    }
#endif

    return depth;
}

vec3 ssr_view_position(vec2 uv, float depth) {
#ifdef DISTANT_HORIZONS
    if (depth >= 1.0 && texture(dhDepthTex0, uv).r < 1.0) {
        vec3 ndc = vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0);
        vec4 view = dhProjectionInverse * vec4(ndc, 1.0);
        return view.xyz / view.w;
    }
#endif
    return screen_to_view_space(gbufferProjectionInverse, vec3(uv, depth));
}

struct SSRResult {
    vec3 color;
    float confidence;
    vec2 uv;
};

// roughness: perceptual roughness of the reflecting surface
// dither: per-pixel random in [0, 1)
SSRResult ssr_trace(
    vec3 view_pos,
    vec3 view_normal,
    float roughness,
    float dither,
    sampler2D source
) {
    SSRResult result;
    result.color = vec3(0.0);
    result.confidence = 0.0;
    result.uv = vec2(0.0);

#ifdef REFLECTIONS
#if REFLECTIONS == 2

    roughness = max(roughness, SSR_MIN_ROUGHNESS);

    vec3 view_dir = normalize(view_pos);
    vec3 reflect_dir = reflect(view_dir, view_normal);

#ifdef SSR_RAY_JITTER
    // Rough surfaces reflect a cone, not a ray. Jitter the direction.
    if (roughness > 0.02) {
        float cone = roughness * roughness * 2.0;
        vec2 jitter = (vec2(dither, fract(dither * 13.37)) - 0.5) * cone;
        vec3 jittered = normalize(reflect_dir + vec3(jitter, 0.0));
        reflect_dir = normalize(mix(reflect_dir, jittered, clamp01(roughness * 3.0)));
    }
#endif

    float step_size = 0.35;
    float t = step_size;
    float max_distance = 96.0;

    vec2 hit_uv = vec2(0.0);

    float prev_t = 0.0;
    bool hit = false;

    // Very rough surfaces should not use screen space reflections at all
    if (roughness > SSR_ROUGHNESS * 2.0) {
        return result;
    }

    for (int i = 0; i < SSR_STEPS; i++) {
        vec3 sample_pos = view_pos + reflect_dir * t;
        vec3 screen = view_to_screen_space(gbufferProjection, sample_pos);

        if (any(lessThan(screen.xy, vec2(0.0))) || any(greaterThan(screen.xy, vec2(1.0)))) {
            break;
        }

        float scene_depth = ssr_scene_depth(screen.xy);
        if (scene_depth >= 1.0) {
            // Sky: stop, we will fall back to the analytic sky
            break;
        }

        vec3 scene_view = ssr_view_position(screen.xy, scene_depth);
        float ray_distance = -sample_pos.z;
        float surface_distance = -scene_view.z;

        // The ray has passed behind the visible surface
        float difference = ray_distance - surface_distance;

        if (difference > 0.0) {
            if (difference < SSR_THICKNESS * max(1.0, t * 0.02)) {
                hit = true;
                hit_uv = screen.xy;
                break;
            }
            // Overshot: refine between the previous and current sample
            float lo = prev_t;
            float hi = t;
            for (int j = 0; j < SSR_REFINEMENT_STEPS; j++) {
                float mid = (lo + hi) * 0.5;
                vec3 mid_pos = view_pos + reflect_dir * mid;
                vec3 mid_screen = view_to_screen_space(gbufferProjection, mid_pos);

                if (any(lessThan(mid_screen.xy, vec2(0.0))) || any(greaterThan(mid_screen.xy, vec2(1.0)))) {
                    break;
                }

                float mid_depth = ssr_scene_depth(mid_screen.xy);
                if (mid_depth >= 1.0) break;

                vec3 mid_view = ssr_view_position(mid_screen.xy, mid_depth);

                if (-mid_pos.z > -mid_view.z) {
                    hi = mid;
                    hit_uv = mid_screen.xy;
                } else {
                    lo = mid;
                }
            }
            hit = true;
            break;
        }

        prev_t = t;
        step_size *= 1.08;
        t += step_size;

        if (t > max_distance) break;
    }

    if (hit) {
        // Fade out close to the screen border and for long rays
        vec2 edge = abs(hit_uv * 2.0 - 1.0);
        float edge_fade = 1.0 - smoothstep(SSR_FADE_START, 1.0, max_of(edge));
        float distance_fade = 1.0 - smoothstep(0.7, 1.0, t / max_distance);

        float confidence = edge_fade * distance_fade;

        result.color = texture(source, hit_uv).rgb;
        result.confidence = clamp01(confidence);
        result.uv = hit_uv;
    }
#endif
#endif

    return result;
}

// Environment fallback: analytic sky + sun highlight
vec3 environment_reflection(
    vec3 view_normal,
    vec3 view_pos,
    vec3 f0,
    float roughness
) {
    vec3 scene_normal = normalize((gbufferModelViewInverse * vec4(view_normal, 0.0)).xyz);
    vec3 scene_view_dir = normalize((gbufferModelViewInverse * vec4(view_pos, 0.0)).xyz);

    vec3 reflect_dir = reflect(scene_view_dir, scene_normal);

    vec3 sun_dir = sun_dir_scene();
    vec3 sky = sky_reflection(reflect_dir, sun_dir);

    // Sun specular highlight, not part of the "sky"
    vec3 sun_color = blackbody(SUN_TEMPERATURE) * SUN_I * 2.0;
    float sun_dot = max0(dot(reflect_dir, sun_dir));
    float highlight = pow(sun_dot, max(2.0 / max(roughness * roughness, 0.001), 1.0));

    vec3 env = sky + sun_color * highlight * 8.0 * (1.0 - roughness);

    // Fresnel: grazing angles reflect much more
    float NoV = max0(dot(scene_normal, scene_view_dir));
    vec3 F = fresnel_schlick_roughness(f0, roughness, NoV);

    return env * F;
}

#endif // MUON_SSR
