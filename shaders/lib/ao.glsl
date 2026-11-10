/*
================================================================================

  Muon Shaders
  lib/ao.glsl - screen space ambient occlusion

  Two algorithms share one interface:

    GTAO - horizon-based, sliced, physically motivated and stable in motion.
    SSAO - classic hemisphere kernel, cheaper and noisier.

  Both output visibility in [0, 1] where 1 is fully open.

================================================================================
*/

#if !defined MUON_AO
#define MUON_AO

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"

// Scene depth including the LoD mods
float ao_scene_depth(vec2 uv) {
    float depth = texture(depthtex1, uv).r;

#ifdef DISTANT_HORIZONS
    if (depth >= 1.0) {
        float dh_depth = texture(dhDepthTex0, uv).r;
        if (dh_depth < 1.0) return dh_depth;
    }
#endif

    return depth;
}

vec3 ao_view_position(vec2 uv, float depth) {
#ifdef DISTANT_HORIZONS
    if (depth >= 1.0 && texture(dhDepthTex0, uv).r < 1.0) {
        vec3 ndc = vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0);
        vec4 view = dhProjectionInverse * vec4(ndc, 1.0);
        return view.xyz / view.w;
    }
#endif
    return screen_to_view_space(gbufferProjectionInverse, vec3(uv, depth));
}

// -------------------------
//   GTAO
// -------------------------

// Horizon-based ambient occlusion. For each slice we march both directions and
// keep the highest elevation angle seen; the occlusion of a slice is the
// integral of the unoccluded cosine-weighted hemisphere above that horizon.
float gtao(vec3 view_pos, vec3 view_normal, float dither) {
    float radius = GTAO_RADIUS;
    float visibility = 0.0;

    // Build a tangent frame from the view-space normal
    vec3 tangent;
    vec3 bitangent;
    build_basis(view_normal, tangent, bitangent);

    float slice_angle = pi / float(GTAO_SLICES);
    float step_size = radius / float(GTAO_HORIZON_STEPS);

    for (int s = 0; s < GTAO_SLICES; s++) {
        float phi = (float(s) + dither) * slice_angle * 2.0;

        vec2 dir = vec2(cos(phi), sin(phi));
        vec3 slice_dir = tangent * dir.x + bitangent * dir.y;

        float horizon_pos = 0.0;
        float horizon_neg = 0.0;

        for (int i = 1; i <= GTAO_HORIZON_STEPS; i++) {
            float t = (float(i) - 0.5 + dither * 0.5) * step_size;

            // Forward direction
            vec3 sample_pos = view_pos + slice_dir * t;
            vec3 sample_screen = view_to_screen_space(gbufferProjection, sample_pos);

            if (all(greaterThan(sample_screen.xy, vec2(0.0))) && all(lessThan(sample_screen.xy, vec2(1.0)))) {
                float depth = ao_scene_depth(sample_screen.xy);
                if (depth < 1.0) {
                    vec3 actual = ao_view_position(sample_screen.xy, depth);
                    float height = dot(actual - view_pos, view_normal);
                    float falloff = 1.0 - sqr(t / radius);
                    horizon_pos = max(horizon_pos, height / t * falloff);
                }
            }

            // Backward direction
            sample_pos = view_pos - slice_dir * t;
            sample_screen = view_to_screen_space(gbufferProjection, sample_pos);

            if (all(greaterThan(sample_screen.xy, vec2(0.0))) && all(lessThan(sample_screen.xy, vec2(1.0)))) {
                float depth = ao_scene_depth(sample_screen.xy);
                if (depth < 1.0) {
                    vec3 actual = ao_view_position(sample_screen.xy, depth);
                    float height = dot(actual - view_pos, view_normal);
                    float falloff = 1.0 - sqr(t / radius);
                    horizon_neg = max(horizon_neg, height / t * falloff);
                }
            }
        }

        // Cosine of the horizon angles
        float cos_pos = inversesqrt(1.0 + horizon_pos * horizon_pos);
        float cos_neg = inversesqrt(1.0 + horizon_neg * horizon_neg);

        // Vertices above the surface contribute nothing, below fully occlude
        if (horizon_pos < 0.0) cos_pos = 1.0;
        if (horizon_neg < 0.0) cos_neg = 1.0;

        visibility += 0.5 * (cos_pos + cos_neg);
    }

    visibility /= float(GTAO_SLICES);

    // Multi-bounce approximation: occlusion never reaches zero in a real scene
    // because light bounces between surfaces.
    visibility = pow(clamp01(visibility), 1.0 / 1.35);
    visibility = mix(visibility, 1.0, 0.10);

    return clamp01(visibility);
}

// -------------------------
//   SSAO
// -------------------------

float ssao(vec3 view_pos, vec3 view_normal, float dither) {
    float visibility = 0.0;

    float radius = SSAO_RADIUS;

    vec3 tangent;
    vec3 bitangent;
    build_basis(view_normal, tangent, bitangent);

    mat3 rotation = mat3(
        tangent,
        bitangent,
        view_normal
    );

    for (int i = 0; i < SSAO_STEPS; i++) {
        // Cosine distributed kernel
        vec2 u = fract(r2_sequence(i) + vec2(dither, fract(dither * 7.13)));
        vec3 local = cosine_hemisphere(u);

        // Bias towards the origin to avoid self-occlusion
        float scale = mix(0.15, 1.0, float(i) / float(SSAO_STEPS));
        vec3 sample_pos = view_pos + (rotation * local) * radius * scale;

        vec3 screen = view_to_screen_space(gbufferProjection, sample_pos);
        if (any(lessThan(screen.xy, vec2(0.0))) || any(greaterThan(screen.xy, vec2(1.0)))) {
            continue;
        }

        float depth = ao_scene_depth(screen.xy);
        if (depth >= 1.0) continue;

        vec3 actual = ao_view_position(screen.xy, depth);
        float delta = dot(actual - sample_pos, view_normal);

        if (delta > 0.02) {
            float range = clamp01(1.0 - length(actual - view_pos) / radius);
            visibility += sqr(range);
        }
    }

    return clamp01(1.0 - visibility / float(SSAO_STEPS));
}

// -------------------------
//   Entry point
// -------------------------

float compute_ao(vec3 view_pos, vec3 view_normal, float dither) {
#if SHADER_AO == 2
    return gtao(view_pos, view_normal, dither);
#elif SHADER_AO == 1
    return ssao(view_pos, view_normal, dither);
#else
    return 1.0;
#endif
}

// Blends the AO screen space result with the vanilla AO that the G-buffer
// already carries. Vanilla AO is free and handles corners well.
float apply_ao(float shader_ao, float vanilla_ao, float shading_strength) {
    float ao = shader_ao * vanilla_ao;

    // A little lift keeps the image from looking dirty
    ao = pow(clamp01(ao), 1.0 / max(shading_strength, 0.01));

    return mix(1.0, ao, SHADING_STRENGTH);
}

#endif // MUON_AO
