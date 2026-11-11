/*
================================================================================

  Muon Shaders - lib/common/raytrace.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Screen-space path tracing for the Raytraced, RTGI and PTGI presets.

  The tracer follows the structure of a path tracer, not a one-bounce SSAO-style
  gather:

    bounce 0  a cosine-weighted hemisphere ray is traced against the depth
              buffer until it finds a surface, and that surface's *lit* colour
              is taken from the previous bounce's radiance field.
    bounce N  the same gather is repeated, sourcing from the result of bounce
              N-1, which is how light that bounced twice reaches surfaces the
              first gather cannot see.

  Rays that miss geometry fall back to the analytic sky, so the sky is a proper
  light source rather than a black void. Results accumulate temporally through
  the normal TAA pipeline; the denoiser pass adds a bilateral spatial filter so
  that RTGI_BOUNCES=1 with few samples is still usable.

  This is a screen-space tracer: it cannot see geometry that is off-screen or
  hidden behind the camera. Muon falls back to the analytic sky and the bounce
  term whenever a ray misses, which keeps the image stable instead of
  introducing holes.

================================================================================
*/

#ifndef MUON_COMMON_RAYTRACE_GLSL
#define MUON_COMMON_RAYTRACE_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/sampling.glsl"
#include "/lib/common/ssr.glsl"
#include "/lib/common/atmosphere.glsl"
#include "/lib/common/gbuffer_read.glsl"


struct MuonGISample {
    vec3 radiance;
    float hit;
};

/*
 * Traces one cosine-weighted ray. `source` is the radiance field to sample on a
 * hit - the lit image for the first bounce, the GI target for later bounces.
 */
MuonGISample muon_trace_gi_ray(
    vec3 view_pos,
    vec3 view_normal,
    vec3 world_normal,
    vec2 xi,
    sampler2D source,
    float max_distance
) {
    MuonGISample result;
    result.radiance = vec3(0.0);
    result.hit = 0.0;

    /* Cosine-weighted direction in the hemisphere around the shading normal. */
    vec3 local_dir = muon_cosine_hemisphere(xi);
    vec3 view_dir = normalize(muon_tangent_frame(view_normal) * local_dir);
    if (dot(view_dir, view_normal) <= 0.0) {
        view_dir = view_normal;
    }

    vec3 origin = view_pos + view_normal * 0.04;
    float step_size = max_distance / float(MUON_RTGI_STEPS);

    for (int i = 1; i <= MUON_RTGI_STEPS; i++) {
        float t = step_size * float(i);
        vec3 ray_point = origin + view_dir * t;

        vec2 sample_uv;
        float ray_depth;
        if (!muon_project_view(ray_point, sample_uv, ray_depth)) {
            break;
        }
        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            break;
        }

        float scene_depth = muon_linear_depth(texture(depthtex0, sample_uv).r);
        float thickness = max(step_size * 2.0, 0.15);

        if (ray_depth > scene_depth && ray_depth < scene_depth + thickness) {
            result.radiance = texture(source, sample_uv).rgb;
            result.hit = 1.0;
            return result;
        }
    }

    /* Missed geometry: the sky is the light source. */
    vec3 world_dir = normalize(muon_view_to_world_dir(view_dir));
    result.radiance = muon_sky_radiance(world_dir, 6) * 1.0;
    result.hit = 0.0;

    return result;
}

/*
 * Gathers indirect radiance for one surface.
 * Returns the accumulated irradiance, already divided by the sample count.
 */
vec3 muon_trace_gi(
    vec2 frag_coord,
    vec3 view_pos,
    vec3 view_normal,
    vec3 world_normal,
    sampler2D source,
    int samples,
    float dither
) {
#if !defined RTGI
    return vec3(0.0);
#else
    if (samples <= 0) {
        return vec3(0.0);
    }

    uint seed = muon_pixel_seed(frag_coord, uint(muonFrame.time.x));
    vec3 accumulated = vec3(0.0);

    for (int i = 0; i < samples; i++) {
        uint ray_seed = muon_hash_combine(seed, uint(i));
        /* Cranley-Patterson rotation of a stratified set keeps the samples
           well distributed while staying temporally independent. */
        vec2 xi = muon_hammersley_2d(uint(i), uint(samples));
        xi = muon_rotate_point_set(xi, muon_rand_vec2(ray_seed));

        MuonGISample sample_result = muon_trace_gi_ray(
            view_pos,
            view_normal,
            world_normal,
            xi,
            source,
            MUON_RTGI_RADIUS
        );
        accumulated += sample_result.radiance;
    }

    return accumulated / float(samples);
#endif
}

/*
 * One iteration of the Jacobi solve. Called once per bounce by the RTGI pass;
 * the result of iteration N becomes the source of iteration N+1.
 */
vec3 muon_trace_gi_iteration(
    vec2 frag_coord,
    vec3 view_pos,
    vec3 view_normal,
    vec3 world_normal,
    sampler2D source,
    int bounce,
    float dither
) {
    int samples = MUON_RTGI_SAMPLES;
    /* Later bounces contribute less and can afford fewer rays. */
    if (bounce > 0) {
        samples = max(MUON_RTGI_SAMPLES / 2, 1);
    }
    return muon_trace_gi(frag_coord, view_pos, view_normal, world_normal, source, samples, dither);
}

// -----------------------------------------------------------------------------
//  Spatial denoiser
// -----------------------------------------------------------------------------

/*
 * Depth-aware bilateral filter over the GI target. The weights combine a
 * spatial falloff, a depth similarity test and a normal agreement test so that
 * light does not leak across geometric edges.
 */
vec3 muon_denoise_gi(sampler2D source, vec2 uv, float center_depth, vec3 center_normal) {
#if !defined RTGI_DENOISE
    return texture(source, uv).rgb;
#else
    vec2 texel = muon_inv_viewport();
    vec3 accumulated = texture(source, uv).rgb;
    float weight_sum = 1.0;

    const int radius = 2;
    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            if (x == 0 && y == 0) {
                continue;
            }

            vec2 sample_uv = uv + vec2(float(x), float(y)) * texel;
            float sample_depth = muon_linear_depth(texture(depthtex0, sample_uv).r);
            float depth_delta = abs(sample_depth - center_depth);
            if (depth_delta > 0.35) {
                continue;
            }

            vec3 sample_normal = muon_read_opaque_world_normal(sample_uv);
            float normal_agreement = muon_saturate(dot(sample_normal, center_normal));

            float spatial = exp(-float(x * x + y * y) * 0.35);
            float weight = spatial * normal_agreement * exp(-depth_delta * 8.0);

            accumulated += texture(source, sample_uv).rgb * weight;
            weight_sum += weight;
        }
    }

    vec3 filtered = accumulated / max(weight_sum, MUON_EPSILON);
    return mix(texture(source, uv).rgb, filtered, RTGI_DENOISE_STRENGTH);
#endif
}

#endif // MUON_COMMON_RAYTRACE_GLSL
