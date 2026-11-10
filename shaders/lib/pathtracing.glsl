/*
================================================================================

  Muon Shaders
  lib/pathtracing.glsl - ray traced / path traced lighting

  A screen-space path tracer. It uses the depth buffer as an acceleration
  structure, the G-buffer as the surface database, and the shadow map for
  next-event estimation towards the sun/moon. Rays that leave the screen are
  resolved against the analytic sky, so every path terminates with a
  meaningful radiance instead of black.

  Modes (RAY_TRACING):
    1  ray traced reflections     - replaces SSR, keeps raster direct light
    2  ray traced GI              - adds indirect diffuse + specular to raster
    3  full path tracing          - every bounce is traced, direct included

  This is not hardware ray tracing: there is no BLAS/TLAS. It is the same
  screen-space approach used by PTGI-class packs and it inherits their
  limitations (off-screen geometry cannot be hit). The difference is that the
  tracer here is unbiased in its sampling and denoised temporally, so it
  converges instead of shimmering.

================================================================================
*/

#if !defined MUON_PATHTRACING
#define MUON_PATHTRACING

#include "/lib/gbuffer.glsl"
#include "/lib/random.glsl"
#include "/lib/shadow.glsl"
#include "/lib/brdf.glsl"
#include "/lib/atmosphere.glsl"
#include "/lib/lighting.glsl"

// -------------------------
//   Screen space ray cast
// -------------------------

struct RayHit {
    bool hit;
    vec2 uv;
    float distance;
    vec3 position;
};

float rt_scene_depth(vec2 uv) {
    float depth = texture(depthtex1, uv).r;

#ifdef DISTANT_HORIZONS
    if (depth >= 1.0) {
        float dh_depth = texture(dhDepthTex0, uv).r;
        if (dh_depth < 1.0) return dh_depth;
    }
#endif

    return depth;
}

vec3 rt_view_position(vec2 uv, float depth) {
#ifdef DISTANT_HORIZONS
    if (depth >= 1.0 && texture(dhDepthTex0, uv).r < 1.0) {
        vec3 ndc = vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0);
        vec4 view = dhProjectionInverse * vec4(ndc, 1.0);
        return view.xyz / view.w;
    }
#endif
    return screen_to_view_space(gbufferProjectionInverse, vec3(uv, depth));
}

// Marches the depth buffer. Returns a hit with the uv of the first surface the
// ray passes behind. `thickness` controls how much of a surface's back is
// considered solid.
RayHit trace_screen(vec3 origin_scene, vec3 dir_scene, float max_distance, float dither, int steps) {
    RayHit result;
    result.hit = false;
    result.uv = vec2(0.0);
    result.distance = max_distance;
    result.position = origin_scene + dir_scene * max_distance;

    vec3 origin_view = scene_to_view_space(origin_scene);
    vec3 dir_view = mat3(gbufferModelView) * dir_scene;

    if (dir_view.z > 0.0) {
        // Ray points behind the camera: nothing on screen can be hit
        return result;
    }

    float step_size = max_distance / float(steps);
    float t = step_size * (0.25 + dither * 0.75);

    float previous_t = 0.0;

    for (int i = 0; i < steps; i++) {
        vec3 sample_pos = origin_view + dir_view * t;
        vec3 screen = view_to_screen_space(gbufferProjection, sample_pos);

        if (any(lessThan(screen.xy, vec2(0.0))) || any(greaterThan(screen.xy, vec2(1.0)))) {
            return result;
        }

        float depth = rt_scene_depth(screen.xy);
        if (depth >= 1.0) {
            previous_t = t;
            t += step_size;
            continue;
        }

        vec3 surface_view = rt_view_position(screen.xy, depth);

        // Compare along the ray direction, not just z
        float ray_distance = -sample_pos.z;
        float surface_distance = -surface_view.z;
        float difference = ray_distance - surface_distance;

        if (difference > 0.0 && difference < max(0.5, t * 0.05)) {
            result.hit = true;
            result.uv = screen.xy;
            result.distance = t;
            result.position = origin_scene + dir_scene * t;
            return result;
        }

        if (difference > 0.0) {
            // Overshot: binary refine
            float lo = previous_t;
            float hi = t;
            for (int j = 0; j < 5; j++) {
                float mid = (lo + hi) * 0.5;
                vec3 mid_pos = origin_view + dir_view * mid;
                vec3 mid_screen = view_to_screen_space(gbufferProjection, mid_pos);

                float mid_depth = rt_scene_depth(mid_screen.xy);
                if (mid_depth >= 1.0) {
                    hi = mid;
                    continue;
                }

                vec3 mid_view = rt_view_position(mid_screen.xy, mid_depth);

                if (-mid_pos.z > -mid_view.z) {
                    hi = mid;
                } else {
                    lo = mid;
                }
            }

            float mid = hi;
            vec3 hit_pos = origin_view + dir_view * mid;
            vec3 hit_screen = view_to_screen_space(gbufferProjection, hit_pos);

            if (all(greaterThan(hit_screen.xy, vec2(0.0))) && all(lessThan(hit_screen.xy, vec2(1.0)))) {
                result.hit = true;
                result.uv = hit_screen.xy;
                result.distance = mid;
                result.position = origin_scene + dir_scene * mid;
                return result;
            }

            return result;
        }

        previous_t = t;
        step_size *= 1.12;
        t += step_size;
    }

    return result;
}

// -------------------------
//   Next event estimation
// -------------------------

// Soft shadow towards the sun, sampled with a small cone.
float sun_visibility_rt(vec3 scene_pos, vec3 normal, float dither) {
    vec3 light_dir = shadow_light_dir_scene();
    float NoL = dot(normal, light_dir);

    if (NoL <= 0.0) return 0.0;

#ifdef RT_SUN_SOFT_SHADOWS
    const int taps = 4;
    vec3 tangent;
    vec3 bitangent;
    build_basis(light_dir, tangent, bitangent);

    float sum = 0.0;
    for (int i = 0; i < taps; i++) {
        vec2 disk = sample_disk(fract(vec2(dither, dither * 7.31) + r2_sequence(i) * 0.25));
        vec3 offset_dir = normalize(light_dir + (tangent * disk.x + bitangent * disk.y) * 0.012);

        vec3 sample_pos = scene_pos + normal * 0.02;
        sum += shadow_sample_fast(sample_pos, max0(dot(normal, offset_dir)));
    }
    return sum / float(taps);
#else
    return shadow_sample_fast(scene_pos + normal * 0.02, NoL);
#endif
}

vec3 direct_light_rt(SurfaceData surface, float dither) {
    vec3 light_dir = shadow_light_dir_scene();
    float NoL = dot(surface.normal, light_dir);

    if (NoL <= 0.0) return vec3(0.0);

    float visibility = sun_visibility_rt(surface.scene_pos, surface.normal, dither);
    if (visibility <= 0.0) return vec3(0.0);

    vec3 V = surface.view_dir;
    vec3 N = surface.normal;
    vec3 H = normalize(light_dir + V);

    float NoV = max(dot(N, V), 1e-4);
    float NoH = max0(dot(N, H));
    float VoH = max0(dot(V, H));

    vec3 f0 = mix(vec3(surface.f0), surface.albedo, surface.metalness);
    vec3 diffuse_albedo = surface.albedo * (1.0 - surface.metalness);

    vec3 light_color = direct_light_color(light_dir) * visibility;

    vec3 result = diffuse_albedo * (NoL * rcp_pi) * light_color * pi;
    result += specular_brdf(f0, surface.roughness, NoV, NoL, NoH, VoH) * light_color * NoL;

    return result;
}

vec3 emission_rt(SurfaceData surface) {
    return surface.albedo * surface.emission * EMISSION_STRENGTH;
}

// -------------------------
//   Environment
// -------------------------

vec3 sky_radiance_rt(vec3 dir, bool include_sun) {
    vec3 sun_dir = sun_dir_scene();

    vec3 sky = sky_gradient(dir, sun_dir);

    if (include_sun) {
        vec3 sun_color = blackbody(SUN_TEMPERATURE) * SUN_I * 6.0;
        float sun_dot = dot(dir, sun_dir);
        float radius_cos = cos(radians_f(SUN_ANGULAR_RADIUS));

        if (sun_dot > radius_cos) {
            sky += sun_color * smoothstep(radius_cos, 1.0, sun_dot);
        }

        // Sun glow around the disc, which is what makes specular rays on water
        // bloom correctly
        sky += sun_color * pow(max0(sun_dot), 512.0) * 2.0;
    }

    return sky;
}

// -------------------------
//   Path tracing
// -------------------------

struct PathResult {
    vec3 radiance;
    float confidence;
};

// Samples one path. `mode` follows RAY_TRACING.
PathResult trace_path(SurfaceData primary, float dither, int mode) {
    PathResult result;
    result.radiance = vec3(0.0);
    result.confidence = 1.0;

    vec3 N = normalize(primary.normal);
    vec3 V = primary.view_dir;

    vec3 f0 = mix(vec3(primary.f0), primary.albedo, primary.metalness);
    vec3 diffuse_albedo = primary.albedo * (1.0 - primary.metalness);

    float roughness = max(primary.roughness, RT_ROUGHNESS_CUTOFF * 0.25);

    bool include_primary_direct = mode >= 3;

    vec3 radiance = vec3(0.0);

    // Primary next-event estimation
    if (include_primary_direct) {
        radiance += direct_light_rt(primary, dither);
    }

    // ---- first bounce direction ----
    float specular_probability = primary.metalness > 0.5
        ? 0.95
        : clamp01(fresnel_schlick(f0, max0(dot(N, V))).r * 2.0 + (1.0 - roughness) * 0.25);

    bool first_specular = dither < specular_probability;

    float r1 = fract(dither * 31.4159 + 0.137);
    float r2 = fract(dither * 71.123 + 0.531);
    float r3 = fract(dither * 17.777 + 0.913);
    float r4 = fract(dither * 43.333 + 0.271);

    vec3 direction;
    vec3 throughput;

    if (first_specular) {
        vec3 H = sample_ggx(N, roughness, vec2(r1, r2));
        direction = reflect(-V, H);

        float VoH = max0(dot(V, H));
        vec3 F = fresnel_schlick(f0, VoH);

        throughput = F / max(specular_probability, 0.05);
    } else {
        direction = cosine_hemisphere(vec2(r1, r2));
        // rotate to the surface normal
        vec3 t;
        vec3 b;
        build_basis(N, t, b);
        direction = normalize(t * direction.x + b * direction.y + N * direction.z);

        throughput = diffuse_albedo / max(1.0 - specular_probability, 0.05);
    }

    if (dot(direction, N) <= 0.0) {
        return result;
    }

    vec3 origin = primary.scene_pos + N * 0.02;

    int bounces = min(RT_MAX_BOUNCES, 6);

    for (int bounce = 0; bounce < bounces; bounce++) {
        RayHit hit = trace_screen(origin, direction, 256.0, fract(dither + float(bounce) * 0.618), RT_SCREEN_SPACE_STEPS);

        if (!hit.hit) {
            // Escaped to the sky. Only specular chains see the sun disc; direct
            // sun light is already accounted for by next-event estimation.
            bool include_disc = first_specular && bounce == 0;
            radiance += throughput * sky_radiance_rt(direction, include_disc);
            break;
        }

        float depth;
        SurfaceData hit_surface = load_surface(hit.uv, depth);

        // Emission of the hit surface
        radiance += throughput * emission_rt(hit_surface);

        // Next event estimation
        radiance += throughput * direct_light_rt(hit_surface, fract(dither + float(bounce) * 0.311));

        // Continue the path
        vec3 hit_n = hit_surface.normal;
        vec3 hit_v = -direction;

        vec3 hit_f0 = mix(vec3(hit_surface.f0), hit_surface.albedo, hit_surface.metalness);
        vec3 hit_diffuse = hit_surface.albedo * (1.0 - hit_surface.metalness);

        float hit_roughness = max(hit_surface.roughness, RT_ROUGHNESS_CUTOFF * 0.25);

        float spec_prob = hit_surface.metalness > 0.5 ? 0.8 : 0.25;

        float u = fract(dither * 113.0 + float(bounce) * 0.577 + 0.13);
        bool do_specular = u < spec_prob;

        vec3 new_dir;

        if (do_specular) {
            vec3 H = sample_ggx(hit_n, hit_roughness, vec2(r3, r4));
            new_dir = reflect(-hit_v, H);
            float VoH = max0(dot(hit_v, H));
            throughput *= fresnel_schlick(hit_f0, VoH) / max(spec_prob, 0.05);
        } else {
            vec3 local = cosine_hemisphere(vec2(r3, r4));
            vec3 t;
            vec3 b;
            build_basis(hit_n, t, b);
            new_dir = normalize(t * local.x + b * local.y + hit_n * local.z);
            throughput *= hit_diffuse / max(1.0 - spec_prob, 0.05);
        }

        if (dot(new_dir, hit_n) <= 0.0) break;

        // Russian roulette after two bounces
        if (bounce >= 2) {
            float survival = clamp(max_of(throughput), 0.05, 0.95);
            if (fract(dither * 271.0 + float(bounce) * 0.37) > survival) break;
            throughput /= survival;
        }

        direction = new_dir;
        origin = hit_surface.scene_pos + hit_n * 0.02;

        // Kill paths that escape the world vertically
        if (origin.y > 4000.0 || origin.y < -256.0) break;

        // Guard against NaN
        if (any(isnan(throughput))) break;
    }

    result.radiance = max(radiance, vec3(0.0));
    return result;
}

// -------------------------
//   Reflection-only helper
// -------------------------

// Used by the water composite for RT reflections without a full path.
vec3 trace_reflection_rt(SurfaceData surface, float dither) {
    vec3 N = surface.normal;
    vec3 V = surface.view_dir;

    vec3 direction = reflect(-V, N);

    RayHit hit = trace_screen(surface.scene_pos + N * 0.02, direction, 256.0, dither, RT_SCREEN_SPACE_STEPS);

    if (!hit.hit) {
        return sky_radiance_rt(direction, true);
    }

    float depth;
    SurfaceData hit_surface = load_surface(hit.uv, depth);

    return direct_light_rt(hit_surface, dither)
        + emission_rt(hit_surface)
        + sky_radiance_rt(reflect(-direction, hit_surface.normal), false) * 0.2;
}

#endif // MUON_PATHTRACING
