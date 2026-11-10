#version 400 compatibility
/*
================================================================================

  Muon Shaders
  composite6.fsh - exposure, bloom, grading and tone mapping

  Writes the final LDR image into colortex13.

  RENDERTARGETS: 13

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"
#include "/lib/color.glsl"
#include "/lib/post.glsl"

layout(location = 0) out vec4 out_color;

/* RENDERTARGETS: 13 */

uniform sampler2D colortex6;  // bloom
uniform sampler2D colortex11; // scene

// Average luminance over a fixed sparse grid. Every pixel computes the same
// value, which keeps exposure consistent across the frame without needing a
// reduction pass or a second buffer.
float scene_average_luminance() {
    float sum = 0.0;
    int count = 0;

    for (int y = 0; y < 6; y++) {
        for (int x = 0; x < 6; x++) {
            vec2 sample_uv = (vec2(float(x), float(y)) + 0.5) / 6.0;
            vec3 sample_color = texture(colortex11, sample_uv).rgb;

            float l = luminance(sample_color);

            if (l > 1e-4) {
                sum += log2(l);
                count++;
            }
        }
    }

    if (count == 0) return 0.18;

    return exp2(sum / float(count));
}

vec3 apply_clarity(vec3 color, vec2 uv) {
#ifdef CLARITY
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);

    vec3 blur = vec3(0.0);
    blur += texture(colortex11, uv + vec2(texel.x, 0.0)).rgb;
    blur += texture(colortex11, uv - vec2(texel.x, 0.0)).rgb;
    blur += texture(colortex11, uv + vec2(0.0, texel.y)).rgb;
    blur += texture(colortex11, uv - vec2(0.0, texel.y)).rgb;
    blur *= 0.25;

    vec3 detail = color - blur;

    // Local contrast only in the midtones, so highlights do not ring
    float l = clamp01(luminance(color));
    float weight = cubic_smooth(clamp01(l * 4.0)) * (1.0 - cubic_smooth(clamp01(l * 1.5 - 0.5)));

    return color + detail * CLARITY_INTENSITY * weight;
#else
    return color;
#endif
}

float scene_exposure() {
    float exposure;

#ifdef AUTO_EXPOSURE
    const float target_luminance = 0.18;

    float average = scene_average_luminance();
    exposure = log2(target_luminance / max(average, 1e-4)) + EXPOSURE_BIAS;
    exposure = clamp(exposure, EXPOSURE_MIN, EXPOSURE_MAX);
#else
    exposure = MANUAL_EXPOSURE;
#endif

    return exposure;
}

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    vec3 color = texture(colortex11, uv).rgb;

    // Bloom
#ifdef BLOOM
    vec3 bloom = texture(colortex6, uv).rgb;
    color += bloom * BLOOM_INTENSITY;
#endif

    color *= exp2(scene_exposure());

    // Clarity before tonemapping keeps the contrast in the scene-referred range
    color = apply_clarity(color, uv);

    // Chromatic aberration on the graded scene, before the tonemap
#ifdef CHROMATIC_ABERRATION
    apply_chromatic_aberration(color, colortex11, uv);
#endif

    color = tonemap_and_grade(color);

    apply_vignette(color, uv);
    apply_film_grain(color, uv);

    out_color = vec4(clamp01(color), 1.0);
}
