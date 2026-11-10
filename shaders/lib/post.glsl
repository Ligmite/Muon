/*
================================================================================

  Muon Shaders
  lib/post.glsl - TAA, bloom, depth of field, motion blur, AA, grading

  Every function here works on already-shaded linear colour (working space) and
  is called from exactly one composite pass.

================================================================================
*/

#if !defined MUON_POST
#define MUON_POST

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"
#include "/lib/color.glsl"
#include "/lib/atmosphere.glsl"

// ==========================
//   Temporal anti-aliasing
// ==========================

// 5-tap Catmull-Rom history fetch. Sharper than bilinear and avoids the
// typical TAA softening.
vec3 catmull_rom(sampler2D source, vec2 uv, vec2 texel) {
    vec2 sample_pos = uv / texel - 0.5;
    vec2 f = fract(sample_pos);
    sample_pos = floor(sample_pos);

    vec4 w0 = vec4(
        -0.5 * f.x * f.x * f.x + f.x * f.x - 0.5 * f.x,
        1.5 * f.x * f.x * f.x - 2.5 * f.x * f.x + 1.0,
        -1.5 * f.x * f.x * f.x + 2.0 * f.x * f.x + 0.5 * f.x,
        0.5 * f.x * f.x * f.x - 0.5 * f.x * f.x
    );

    vec4 w1 = vec4(
        -0.5 * f.y * f.y * f.y + f.y * f.y - 0.5 * f.y,
        1.5 * f.y * f.y * f.y - 2.5 * f.y * f.y + 1.0,
        -1.5 * f.y * f.y * f.y + 2.0 * f.y * f.y + 0.5 * f.y,
        0.5 * f.y * f.y * f.y - 0.5 * f.y * f.y
    );

    vec3 result = vec3(0.0);
    float weight_sum = 0.0;

    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            vec2 offset = vec2(float(i) - 1.0, float(j) - 1.0);
            vec2 sample_uv = (sample_pos + offset + 0.5) * texel;

            float weight = w0[i] * w1[j];

            result += texture(source, sample_uv).rgb * weight;
            weight_sum += weight;
        }
    }

    return result / max(weight_sum, 1e-4);
}

// Clamps the history colour to the neighbourhood of the current frame. This is
// what removes ghosting when the camera reveals new geometry.
vec3 clip_aabb(vec3 history, vec3 minimum, vec3 maximum, float amount) {
    vec3 center = 0.5 * (maximum + minimum);
    vec3 extent = 0.5 * (maximum - minimum);
    vec3 offset = history - center;

    vec3 unit = offset / max(extent, vec3(1e-5));
    float dist = max(max(abs(unit.x), abs(unit.y)), abs(unit.z));

    if (dist > 1.0) {
        offset /= dist;
    }

    return mix(history, center + offset, amount);
}

// Weight for the history sample. Low for fast motion, disocclusion and long
// history without change.
float taa_history_weight(float velocity_length, float depth_difference, float history_length) {
    float velocity_weight = exp(-velocity_length * 60.0);
    float depth_weight = step(depth_difference, 0.01);

    float weight = TAA_HISTORY_WEIGHT * velocity_weight * depth_weight;
    weight *= smoothstep(0.0, 4.0, history_length);

    return clamp(weight, 0.0, 0.98);
}

// ==========================
//   Bloom
// ==========================

// 13-tap downsample / prefilter (CoD Advanced Warfare style)
vec3 bloom_prefilter(sampler2D source, vec2 uv, vec2 texel, float threshold) {
    vec3 a = texture(source, uv + texel * vec2(-2.0, -2.0)).rgb;
    vec3 b = texture(source, uv + texel * vec2(0.0, -2.0)).rgb;
    vec3 c = texture(source, uv + texel * vec2(2.0, -2.0)).rgb;
    vec3 d = texture(source, uv + texel * vec2(-1.0, -1.0)).rgb;
    vec3 e = texture(source, uv + texel * vec2(1.0, -1.0)).rgb;
    vec3 f = texture(source, uv + texel * vec2(-2.0, 0.0)).rgb;
    vec3 g = texture(source, uv).rgb;
    vec3 h = texture(source, uv + texel * vec2(2.0, 0.0)).rgb;
    vec3 i = texture(source, uv + texel * vec2(-1.0, 1.0)).rgb;
    vec3 j = texture(source, uv + texel * vec2(1.0, 1.0)).rgb;
    vec3 k = texture(source, uv + texel * vec2(-2.0, 2.0)).rgb;
    vec3 l = texture(source, uv + texel * vec2(0.0, 2.0)).rgb;
    vec3 m = texture(source, uv + texel * vec2(2.0, 2.0)).rgb;

    vec3 color = (d + e + i + j) * 0.125
        + (a + c + k + m) * 0.03125
        + (b + f + h + l) * 0.0625
        + g * 0.125;

    // Soft knee threshold
    float luminance_value = luminance(color);
    float soft = clamp(luminance_value - threshold + threshold * 0.5, 0.0, 2.0 * threshold);
    soft = soft * soft / (4.0 * threshold + 1e-4);

    float contribution = max(soft, luminance_value - threshold) / max(luminance_value, 1e-4);

    return color * contribution;
}

// 9-tap tent filter
vec3 bloom_blur(sampler2D source, vec2 uv, vec2 texel, float radius) {
    vec3 sum = texture(source, uv).rgb * 4.0;

    sum += texture(source, uv + texel * vec2(-radius, 0.0)).rgb * 2.0;
    sum += texture(source, uv + texel * vec2(radius, 0.0)).rgb * 2.0;
    sum += texture(source, uv + texel * vec2(0.0, -radius)).rgb * 2.0;
    sum += texture(source, uv + texel * vec2(0.0, radius)).rgb * 2.0;

    sum += texture(source, uv + texel * vec2(-radius, -radius)).rgb;
    sum += texture(source, uv + texel * vec2(radius, -radius)).rgb;
    sum += texture(source, uv + texel * vec2(-radius, radius)).rgb;
    sum += texture(source, uv + texel * vec2(radius, radius)).rgb;

    return sum / 16.0;
}

// ==========================
//   Depth of field
// ==========================

// Hexagonal bokeh-ish gather. `focus` is the focus distance in blocks.
vec3 depth_of_field(
    sampler2D color,
    sampler2D depth,
    vec2 uv,
    float focus_distance,
    float range,
    float dither
) {
#ifdef DOF
    float center_depth = texture(depth, uv).r;

    if (center_depth >= 1.0) return texture(color, uv).rgb;

    float center_distance = depth_to_distance(center_depth);

    float coc = abs(center_distance - focus_distance) / max(range, 0.1);
    coc = clamp01(coc * DOF_INTENSITY);

    if (coc < 0.002) return texture(color, uv).rgb;

    float radius = coc * 8.0;
    float rotation = dither * tau;

    vec3 sum = texture(color, uv).rgb;
    float weight_sum = 1.0;

    for (int i = 0; i < DOF_SAMPLES; i++) {
        float r = sqrt((float(i) + 0.5) / float(DOF_SAMPLES));
        float theta = float(i) * golden_angle + rotation;

        vec2 offset = vec2(cos(theta), sin(theta)) * r * radius * 0.01;

        vec2 sample_uv = uv + offset;

        if (any(lessThan(sample_uv, vec2(0.0))) || any(greaterThan(sample_uv, vec2(1.0)))) {
            continue;
        }

        float sample_depth = texture(depth, sample_uv).r;
        float sample_distance = depth_to_distance(sample_depth);

        // Only gather samples that are at least as far as the centre, which
        // prevents sharp foreground bleeding into blurred background
        float sample_coc = abs(sample_distance - focus_distance) / max(range, 0.1);
        float weight = sample_distance >= center_distance ? 1.0 : 0.35;
        weight *= clamp01(sample_coc * 2.0);

        sum += texture(color, sample_uv).rgb * weight;
        weight_sum += weight;
    }

    return sum / weight_sum;
#else
    return texture(color, uv).rgb;
#endif
}

// ==========================
//   Motion blur
// ==========================

vec3 motion_blur(sampler2D color, vec2 uv, vec2 velocity) {
#ifdef MOTION_BLUR
    vec2 texel = 1.0 / vec2(textureSize(color, 0));

    // Clamp the velocity so a single frame cannot smear across the screen
    velocity = clamp(velocity, vec2(-0.05), vec2(0.05)) * MOTION_BLUR_INTENSITY;

    vec3 sum = vec3(0.0);
    float weight_sum = 0.0;

    for (int i = 0; i < MOTION_BLUR_SAMPLES; i++) {
        float t = float(i) / float(MOTION_BLUR_SAMPLES - 1) - 0.5;

        vec2 sample_uv = uv + velocity * t;

        float weight = 1.0 - abs(t);

        sum += texture(color, sample_uv).rgb * weight;
        weight_sum += weight;
    }

    return sum / max(weight_sum, 1e-3);
#else
    return texture(color, uv).rgb;
#endif
}

// ==========================
//   FXAA
// ==========================

vec3 fxaa(sampler2D color, vec2 uv, vec2 texel) {
#ifdef FXAA
    vec3 center = texture(color, uv).rgb;

    vec3 north = texture(color, uv + vec2(0.0, texel.y)).rgb;
    vec3 south = texture(color, uv - vec2(0.0, texel.y)).rgb;
    vec3 east = texture(color, uv + vec2(texel.x, 0.0)).rgb;
    vec3 west = texture(color, uv - vec2(texel.x, 0.0)).rgb;

    float luma_center = luminance(center);
    float luma_north = luminance(north);
    float luma_south = luminance(south);
    float luma_east = luminance(east);
    float luma_west = luminance(west);

    float luma_min = min(luma_center, min(min(luma_north, luma_south), min(luma_east, luma_west)));
    float luma_max = max(luma_center, max(max(luma_north, luma_south), max(luma_east, luma_west)));

    float range = luma_max - luma_min;
    if (range < max(0.0312, luma_max * 0.125)) {
        return center;
    }

    vec3 north_west = texture(color, uv + vec2(-texel.x, texel.y)).rgb;
    vec3 north_east = texture(color, uv + vec2(texel.x, texel.y)).rgb;
    vec3 south_west = texture(color, uv + vec2(-texel.x, -texel.y)).rgb;
    vec3 south_east = texture(color, uv + vec2(texel.x, -texel.y)).rgb;

    float luma_nw = luminance(north_west);
    float luma_ne = luminance(north_east);
    float luma_sw = luminance(south_west);
    float luma_se = luminance(south_east);

    float luma_down = luma_nw + luma_ne + luma_center * 2.0;
    float luma_up = luma_sw + luma_se + luma_center * 2.0;
    float luma_left = luma_nw + luma_sw + luma_center * 2.0;
    float luma_right = luma_ne + luma_se + luma_center * 2.0;

    float edge_horizontal = abs(luma_down - luma_up);
    float edge_vertical = abs(luma_left - luma_right);

    bool horizontal = edge_horizontal >= edge_vertical;

    float luma1 = horizontal ? luma_down : luma_left;
    float luma2 = horizontal ? luma_up : luma_right;

    float gradient1 = luma1 - luma_center;
    float gradient2 = luma2 - luma_center;

    bool steepest = abs(gradient1) >= abs(gradient2);
    float gradient = max(abs(gradient1), abs(gradient2));

    if (gradient < 0.0156) {
        return center;
    }

    float step_length = steepest ? 1.0 : 0.5;
    vec2 step_uv = horizontal ? vec2(texel.x, 0.0) : vec2(0.0, texel.y);

    // Walk along the edge in both directions
    float luma_local_average = luma_center * 0.5 + (steepest ? luma1 : luma2) * 0.25;
    float luma_local_min = min(luma_center, steepest ? luma1 : luma2);

    vec2 uv_a = uv - step_uv * step_length * 0.5;
    vec2 uv_b = uv + step_uv * step_length * 0.5;

    float luma_a = luminance(texture(color, uv_a).rgb);
    float luma_b = luminance(texture(color, uv_b).rgb);

    float gradient_a = luma_a - luma_local_average;
    float gradient_b = luma_b - luma_local_average;

    bool a_better = abs(gradient_a) < abs(gradient_b);

    float gradient_best = a_better ? gradient_a : gradient_b;

    if (a_better) {
        uv_b = uv_a;
    }

    float sub_pixel_offset = clamp(abs(gradient_best) / max(gradient, 1e-4), 0.0, 1.0);
    sub_pixel_offset = cubic_smooth(sub_pixel_offset);

    vec2 final_uv = uv_b - step_uv * sub_pixel_offset * step_length * 0.5;

    return texture(color, final_uv).rgb;
#else
    return texture(color, uv).rgb;
#endif
}

// ==========================
//   Contrast adaptive sharpen
// ==========================

vec3 cas_sharpen(vec3 a, vec3 b, vec3 c, vec3 d, vec3 e, vec3 f, vec3 g, vec3 h, vec3 i, float sharpness) {
    vec3 min_color = min(min(min(d, e), min(f, b)), h);
    min_color += min(min(min_color, a), min(min(c, g), i));

    vec3 max_color = max(max(max(d, e), max(f, b)), h);
    max_color += max(max(max_color, a), max(max(c, g), i));

    vec3 w = clamp01(min(min_color, 2.0 - max_color) / max(max_color, vec3(1e-4)));
    w = 1.0 - sqr(1.0 - w);
    w *= -1.0 / mix(8.0, 5.0, sharpness);

    vec3 weight_sum = 1.0 + 4.0 * w;

    return clamp01((b + d + f + h) * w + e) / weight_sum;
}

// ==========================
//   Grading
// ==========================

// Exposure estimation. Samples a coarse fixed grid so every pixel computes the
// same value (the result is written back to a single texel).
float estimate_scene_luminance(sampler2D color) {
    vec2 resolution = vec2(textureSize(color, 0));

    float sum = 0.0;
    int count = 0;

    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            vec2 uv = (vec2(float(x), float(y)) + 0.5) / 8.0;
            ivec2 texel = ivec2(uv * resolution);

            vec3 sample_color = texelFetch(color, texel, 0).rgb;

            float l = luminance(sample_color);

            // Log average, ignoring pure black
            if (l > 1e-4) {
                sum += log2(l);
                count++;
            }
        }
    }

    if (count == 0) return 0.18;

    return exp2(sum / float(count));
}

float compute_exposure(float average_luminance, float previous_exposure, float frame_time) {
#ifdef AUTO_EXPOSURE
    const float target_luminance = 0.18;

    float target = log2(target_luminance / max(average_luminance, 1e-4));

    target += EXPOSURE_BIAS;
    target = clamp(target, EXPOSURE_MIN, EXPOSURE_MAX);

    float speed = EXPOSURE_SPEED * frame_time;
    float new_exposure = mix(previous_exposure, target, clamp01(speed));

    return new_exposure;
#else
    return MANUAL_EXPOSURE;
#endif
}

// White balance in linear RGB. Temperature shifts from blue to orange.
vec3 apply_white_balance(vec3 color, float temperature, float tint) {
    if (abs(temperature) < 1e-4 && abs(tint) < 1e-4) return color;

    vec3 warm = vec3(1.0 + temperature, 1.0 + tint * 0.5, 1.0 - temperature);
    return color * warm;
}

// The full grade pipeline. Input and output are linear working space.
vec3 grade(vec3 color) {
    // Purkinje shift first: it models the eye, not the film
#ifdef PURKINJE_SHIFT
    color = purkinje_shift(color, PURKINJE_INTENSITY);
#endif

    color *= GRADE_BRIGHTNESS;

    color = apply_white_balance(color, GRADE_TEMPERATURE * 2.0, GRADE_TINT * 2.0);

    // Contrast around middle grey
    color = contrast(color, GRADE_CONTRAST);

    // Saturation and vibrance
    color = saturation(color, GRADE_SATURATION);
    color = vibrance(color, 0.10);

    // Hue selective boosts: the "warm vibrant" signature
    color = hue_saturation(color, 30.0, 45.0, GRADE_ORANGE_BOOST);
    color = hue_saturation(color, 190.0, 60.0, GRADE_TEAL_BOOST);
    color = hue_saturation(color, 110.0, 40.0, GRADE_GREEN_BOOST);

    if (abs(GRADE_GREEN_HUE) > 1e-4) {
        color = hue_shift(color, 110.0, 60.0, GRADE_GREEN_HUE);
    }

    // Warm highlights, cool shadows
    color = split_tone(
        color,
        vec3(0.92, 0.97, 1.08),
        vec3(1.06, 1.01, 0.94),
        GRADE_SHADOW_COOLNESS * 0.5 + GRADE_HIGHLIGHT_WARMTH * 0.5
    );

    // Black level
    color = max(color - GRADE_BLACK_LEVEL, vec3(0.0));

    return color;
}

// Tonemap + grade + display prep, in the right order.
vec3 tonemap_and_grade(vec3 color) {
    color = grade(color);

    color *= EXPOSURE_BRIGHTNESS;

    color = tonemap_operator(color, TONEMAP);

    // Slight lift after tonemapping to avoid crushed blacks
    color = color * 1.01 + 0.002;

    return max(color, vec3(0.0));
}

void apply_vignette(inout vec3 color, vec2 uv) {
#ifdef VIGNETTE
    vec2 centered = uv * 2.0 - 1.0;
    float vignette = 1.0 - dot(centered * 0.55, centered * 0.55) * VIGNETTE_INTENSITY;
    color *= clamp01(vignette);
#endif
}

void apply_chromatic_aberration(inout vec3 color, sampler2D source, vec2 uv) {
#ifdef CHROMATIC_ABERRATION
    vec2 centered = uv - 0.5;
    vec2 offset = centered * CHROMATIC_ABERRATION_INTENSITY * 0.004;

    color.r = texture(source, uv + offset).r;
    color.b = texture(source, uv - offset).b;
#endif
}

void apply_film_grain(inout vec3 color, vec2 uv) {
#ifdef FILM_GRAIN
    float grain = hash12(uv * vec2(1920.0, 1080.0) + frameCounter * 37.0) - 0.5;
    color += grain * FILM_GRAIN_INTENSITY * 0.02;
#endif
}

#endif // MUON_POST
