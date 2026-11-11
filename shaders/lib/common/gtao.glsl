/*
================================================================================

  Muon Shaders - lib/common/gtao.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Ambient occlusion.

  Two kernels share one interface so the presets can switch between them
  without touching a single consumer:

    * GTAO - horizon-based. For each azimuth slice the kernel finds the highest
      elevation still visible on both sides and integrates the cosine-weighted
      horizon. This produces the long, contact-darkening occlusion that a
      radius-limited point kernel cannot reproduce.
    * SSAO - the classic hemisphere kernel, kept for the low preset.

  Both write occlusion in the red channel and a bent normal in the green, blue
  and alpha channels of the half-resolution AO target. The bent normal lets the
  deferred stage rotate its sky ambient term away from occluded directions
  without a second trace.

================================================================================
*/

#ifndef MUON_COMMON_GTAO_GLSL
#define MUON_COMMON_GTAO_GLSL

#include "/lib/uniforms/samplers.glsl"

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/sampling.glsl"
#include "/lib/common/encoding.glsl"
#include "/lib/common/gbuffer_read.glsl"


// -----------------------------------------------------------------------------
//  Helpers
// -----------------------------------------------------------------------------

/* Reconstructs the view-space position of a full-resolution depth sample. */
vec3 muon_ao_view_pos(vec2 uv) {
    return muon_view_pos_from_depth(uv, texture(depthtex0, uv).r);
}

/*
 * Builds a view-space direction perpendicular to the view ray, aligned with a
 * screen-space azimuth. This keeps the kernel plane parallel to the image
 * plane, which is what makes horizon search cheap: every step projects to a
 * predictable screen offset.
 */
vec3 muon_ao_slice_direction(vec3 view_pos, vec2 screen_dir) {
    vec3 view_axis = normalize(view_pos);
    vec3 screen_tangent = vec3(screen_dir.x, screen_dir.y, 0.0);
    return normalize(screen_tangent - view_axis * dot(screen_tangent, view_axis));
}

// -----------------------------------------------------------------------------
//  Horizon search
// -----------------------------------------------------------------------------

/*
 * Marches one side of a slice and returns the largest tangent of the elevation
 * angle above the surface plane, clamped to the hemisphere.
 */
float muon_ao_horizon(
    vec3 view_pos,
    vec3 view_normal,
    vec3 march_dir,
    float radius,
    int steps
) {
    float max_tangent = 0.0;
    float radius_sq = radius * radius;

    for (int i = 1; i <= steps; i++) {
        /* Quadratic spacing: dense near the surface, sparse at the radius. */
        float fraction = float(i) / float(steps);
        float distance = radius * fraction * fraction;

        vec3 ray_point = view_pos + march_dir * distance;
        vec4 clip = muonFrame.projection * vec4(ray_point, 1.0);
        if (clip.w <= 0.0) {
            break;
        }
        vec2 sample_uv = clip.xy / clip.w * 0.5 + 0.5;
        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            break;
        }

        float scene_depth = texture(depthtex0, sample_uv).r;
        if (scene_depth >= 1.0) {
            continue;
        }

        vec3 scene_pos = muon_view_pos_from_depth(sample_uv, scene_depth);
        vec3 delta = scene_pos - view_pos;
        float length_sq = dot(delta, delta);

        if (length_sq < 1.0e-5 || length_sq > radius_sq) {
            continue;
        }

        /* Only geometry in front of the marching point can occlude. */
        float forward_gap = (-scene_pos.z) - (-ray_point.z);
        if (forward_gap > 0.0) {
            continue;
        }

        float inv_length = inversesqrt(length_sq);
        float cos_normal = dot(delta * inv_length, view_normal);
        if (cos_normal <= 0.0) {
            continue;
        }

        float sin_theta = muon_saturate(cos_normal);
        float tangent = sin_theta * inversesqrt(max(1.0 - sin_theta * sin_theta, 1.0e-4));
        max_tangent = max(max_tangent, tangent);
    }

    return max_tangent;
}

// -----------------------------------------------------------------------------
//  GTAO
// -----------------------------------------------------------------------------

struct MuonAO {
    float occlusion;
    vec3 bent_normal;
};

MuonAO muon_gtao(vec3 view_pos, vec3 view_normal, float radius) {
    MuonAO result;
    result.occlusion = 1.0;
    result.bent_normal = view_normal;

    float rotation = muon_pixel_rotation(gl_FragCoord.xy);
    float visibility = 0.0;
    vec3 tilt = vec3(0.0);

    for (int slice = 0; slice < AO_SLICES; slice++) {
        float angle = rotation + (float(slice) / float(AO_SLICES)) * MUON_PI;
        vec2 screen_dir = vec2(cos(angle), sin(angle));
        vec3 march_dir = muon_ao_slice_direction(view_pos, screen_dir);

        float tangent_a = muon_ao_horizon(view_pos, view_normal, march_dir, radius, AO_STEPS);
        float tangent_b = muon_ao_horizon(view_pos, view_normal, -march_dir, radius, AO_STEPS);

        float cos_a = inversesqrt(1.0 + tangent_a * tangent_a);
        float cos_b = inversesqrt(1.0 + tangent_b * tangent_b);

        visibility += 0.5 * (cos_a + cos_b);

        /* The more occluded side pulls the bent normal away from itself. */
        tilt += march_dir * (cos_a - cos_b) * 0.5;
    }

    visibility /= float(max(AO_SLICES, 1));
    result.occlusion = muon_saturate(visibility);
    result.bent_normal = normalize(view_normal + tilt * 0.85);

    return result;
}

// -----------------------------------------------------------------------------
//  SSAO
// -----------------------------------------------------------------------------

MuonAO muon_ssao(vec3 view_pos, vec3 view_normal, float radius) {
    MuonAO result;
    result.occlusion = 1.0;
    result.bent_normal = view_normal;

    const int samples = SSAO_SAMPLES;
    float rotation = muon_pixel_rotation(gl_FragCoord.xy);
    vec3 bent = vec3(0.0);
    float occlusion = 0.0;
    mat3 frame = muon_tangent_frame(view_normal);

    for (int i = 0; i < samples; i++) {
        vec2 xi = muon_hammersley_2d(uint(i), uint(samples));
        xi = muon_rotate_point_set(xi, vec2(fract(rotation), fract(rotation * 1.618)));

        vec3 direction = normalize(frame * muon_cosine_hemisphere(xi));
        /* Bias the kernel towards the surface so that self-occlusion is
           impossible without a per-sample epsilon. */
        float scale = mix(0.25, 1.0, float(i) / float(samples));
        vec3 sample_pos = view_pos + direction * radius * scale;

        vec4 clip = muonFrame.projection * vec4(sample_pos, 1.0);
        if (clip.w <= 0.0) {
            continue;
        }
        vec2 sample_uv = clip.xy / clip.w * 0.5 + 0.5;
        if (sample_uv.x < 0.0 || sample_uv.x > 1.0 || sample_uv.y < 0.0 || sample_uv.y > 1.0) {
            continue;
        }

        float scene_distance = muon_linear_depth(texture(depthtex0, sample_uv).r);
        float sample_distance = -sample_pos.z;

        if (scene_distance < sample_distance - 0.05) {
            occlusion += muon_saturate(1.0 - abs(scene_distance - sample_distance) / radius);
        } else {
            bent += direction;
        }
    }

    occlusion /= float(samples);
    result.occlusion = muon_saturate(1.0 - occlusion);
    result.bent_normal = length(bent) > 0.001 ? normalize(bent) : view_normal;

    return result;
}

// -----------------------------------------------------------------------------
//  Dispatcher
// -----------------------------------------------------------------------------

MuonAO muon_compute_ao(vec3 view_pos, vec3 view_normal) {
    MuonAO result;
    result.occlusion = 1.0;
    result.bent_normal = view_normal;

#if defined GTAO || defined SSAO
    if (-view_pos.z > muonFrame.depthParams.y * 0.98) {
        return result;
    }

#if defined GTAO
    result = muon_gtao(view_pos, view_normal, GTAO_RADIUS);
    const float strength = GTAO_STRENGTH;
#else
    result = muon_ssao(view_pos, view_normal, SSAO_RADIUS);
    const float strength = SSAO_STRENGTH;
#endif

    result.occlusion = mix(1.0, pow(result.occlusion, mix(1.0, 2.2, muon_saturate(strength))), muon_saturate(strength));
#endif

    return result;
}

#endif // MUON_COMMON_GTAO_GLSL
