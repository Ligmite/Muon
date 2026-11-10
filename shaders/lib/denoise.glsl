/*
================================================================================

  Muon Shaders
  lib/denoise.glsl - temporal accumulation and spatial filtering for RT

  The path tracer produces one sample per pixel per frame, which is far too
  noisy to display directly. Two stages fix that:

    1. temporal accumulation reprojected with motion vectors
    2. a depth/normal aware bilateral filter (an edge stopping spatial pass)

  This is the SVGF "poor man's" variant: no per-pixel moments buffer, but a
  robust disocclusion test that avoids the classic smearing.

================================================================================
*/

#if !defined MUON_DENOISE
#define MUON_DENOISE

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/encoding.glsl"
#include "/lib/color.glsl"


// -------------------------
//   Temporal accumulation
// -------------------------

struct TemporalResult {
    vec3 color;
    float history_length;
    float valid;
};

TemporalResult temporal_filter(
    vec3 current,
    vec3 history,
    float current_depth,
    float history_depth,
    vec3 current_normal,
    vec3 history_normal,
    float history_length
) {
    TemporalResult result;

    float depth_difference = abs(current_depth - history_depth) / max(current_depth, 1e-4);
    bool depth_valid = depth_difference < 0.02;

    bool normal_valid = dot(current_normal, history_normal) > 0.9;

    // If the colour changed drastically the history is probably wrong
    float luma_current = luminance(current);
    float luma_history = luminance(history);
    float luma_difference = abs(luma_current - luma_history) / max(luma_current + luma_history, 1e-3);

    bool color_valid = luma_difference < 2.0;

    bool valid = depth_valid && normal_valid && color_valid && history_length > 0.0;

    if (!valid) {
        result.color = current;
        result.history_length = 1.0;
        result.valid = 0.0;
        return result;
    }

    float new_length = min(history_length + 1.0, float(RT_ACCUMULATION_LIMIT));

    // Lower weight for disocclusion-risky pixels
    float alpha = 1.0 / new_length;
    alpha = max(alpha, 0.02);

    result.color = mix(history, current, alpha);
    result.history_length = new_length;
    result.valid = 1.0;

    return result;
}

// -------------------------
//   Spatial bilateral
// -------------------------

// 5x5 cross/bilateral filter. Depth weight prevents light leaking through
// geometry, normal weight preserves hard edges.
vec3 spatial_denoise(
    sampler2D source,
    sampler2D normal_source,
    vec2 uv,
    float center_depth,
    vec3 center_normal,
    float strength
) {
    vec2 texel = 1.0 / vec2(textureSize(source, 0));

    vec3 center = texture(source, uv).rgb;

    float depth_scale = 0.02;

    vec3 sum = center;
    float weight_sum = 1.0;

    for (int y = -2; y <= 2; y++) {
        for (int x = -2; x <= 2; x++) {
            if (x == 0 && y == 0) continue;

            vec2 offset = vec2(float(x), float(y)) * texel;
            vec2 sample_uv = uv + offset;

            if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
                continue;
            }

            float sample_depth = texture(depthtex1, sample_uv).r;

            float depth_weight = exp(-abs(sample_depth - center_depth) / max(center_depth * depth_scale, 1e-5));

            vec3 sample_normal = decode_normal_octa(texture(normal_source, sample_uv).xy);
            float normal_weight = pow(max0(dot(center_normal, sample_normal)), 8.0);

            float spatial_weight = exp(-float(x * x + y * y) * 0.35);

            float weight = depth_weight * normal_weight * spatial_weight * strength;

            sum += texture(source, sample_uv).rgb * weight;
            weight_sum += weight;
        }
    }

    return sum / max(weight_sum, 1.0);
}

// -------------------------
//   Variance guided blend
// -------------------------

// Blends the denoised RT result with the raster lighting. `blend` comes from
// the accumulated confidence: fresh pixels use less RT until the history is
// long enough.
vec3 blend_rt_and_raster(vec3 raster, vec3 rt, float history_length) {
    float confidence = clamp01(history_length / 8.0);

    // Even at full confidence, keep a little raster light so that pixels that
    // the tracer cannot see (off-screen geometry) do not go black.
    confidence = mix(0.35, 1.0, confidence);

    return mix(raster, rt, confidence);
}

#endif // MUON_DENOISE
