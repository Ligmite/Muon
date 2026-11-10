/*
================================================================================

  Muon Shaders
  lib/color.glsl - transfer functions, colour spaces, tonemapping, grading

  Working space is linear Rec.709 (sRGB primaries). All lighting math happens
  there; display encoding happens exactly once, in final.fsh.

================================================================================
*/

#if !defined MUON_COLOR
#define MUON_COLOR

#include "/lib/common.glsl"

// --------------------------------
//   Transfer functions (sRGB)
// --------------------------------

vec3 srgb_eotf(vec3 linear) { // linear -> sRGB
    return 1.14374 * (-0.126893 * linear + sqrt(max(linear, vec3(0.0))));
}

vec3 srgb_eotf_inv(vec3 srgb) { // sRGB -> linear
    return srgb * (srgb * (srgb * 0.305306011 + 0.682171111) + 0.012522878);
}

// Accurate sRGB curve. Required for HDR output so that the peak value survives.
vec3 srgb_eotf_hq(vec3 x) {
    bvec3 cutoff = lessThan(x, vec3(0.0031308));
    vec3 higher = vec3(1.055) * pow(max(x, vec3(0.0)), vec3(1.0 / 2.4)) - vec3(0.055);
    vec3 lower = x * 12.92;
    return mix(higher, lower, cutoff);
}

vec3 srgb_eotf_inv_hq(vec3 x) {
    bvec3 cutoff = lessThan(x, vec3(0.04045));
    vec3 higher = pow((x + 0.055) / 1.055, vec3(2.4));
    vec3 lower = x / 12.92;
    return mix(higher, lower, cutoff);
}

vec3 srgb_eotf_hq_safe(vec3 x) {
    return sign_nonzero(x) * srgb_eotf_hq(abs(x));
}

// linear PQ (SMPTE ST 2084). Only used by the HDR debug view.
vec3 pq_eotf(vec3 linear, float max_luminance) {
    const float m1 = 0.1593017578125;
    const float m2 = 78.84375;
    const float c1 = 0.8359375;
    const float c2 = 18.8515625;
    const float c3 = 18.6875;

    vec3 y = clamp01(linear / max_luminance);
    vec3 num = c1 + c2 * pow(y, vec3(m1));
    vec3 den = 1.0 + c3 * pow(y, vec3(m1));
    return pow(num / den, vec3(m2));
}

// -------------------------------------------------------
//   Display encoding (single place that knows about HDR)
// -------------------------------------------------------

vec3 display_eotf(vec3 linear) {
#ifdef MUON_HDR_OUTPUT
    // The mod maps the encoded framebuffer through the display transfer
    // function. Scaling by paper-white/UI brightness keeps the artistic
    // mid-grey when the user changes their HDR paper-white level.
    float scale = HdrGamePaperWhiteBrightness / max(HdrUIBrightness, 1.0);
    return srgb_eotf_hq_safe(linear * scale);
#else
    return srgb_eotf(linear);
#endif
}

vec3 display_eotf_inv(vec3 srgb) {
#ifdef MUON_HDR_OUTPUT
    float scale = HdrGamePaperWhiteBrightness / max(HdrUIBrightness, 1.0);
    return srgb_eotf_inv_hq(srgb) / scale;
#else
    return srgb_eotf_inv(srgb);
#endif
}

// -------------------------------------------------
//   HSL / YCoCg / HSV
// -------------------------------------------------

vec3 rgb_to_hsl(vec3 c) {
    const vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);

    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1e-6;

    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsl_to_rgb(vec3 c) {
    const vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);

    c.yz = clamp01(c.yz);

    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);

    return c.z * mix(K.xxx, clamp01(p - K.xxx), c.y);
}

vec3 rgb_to_ycocg(vec3 rgb) {
    const mat3 cm = mat3(0.25, 0.5, 0.25, 0.5, 0.0, -0.5, -0.25, 0.5, -0.25);
    return rgb * cm;
}

vec3 ycocg_to_rgb(vec3 ycocg) {
    float tmp = ycocg.x - ycocg.z;
    return vec3(tmp + ycocg.y, ycocg.x + ycocg.z, tmp - ycocg.y);
}

vec3 rgb_to_hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp01(p - K.xxx), c.y);
}

// ---------------------------
//   Blackbody radiation
// ---------------------------

// Planckian locus approximation (Tanner Helland), normalised so that the
// brightest channel is 1.0. Temperature in Kelvin.
vec3 blackbody(float temperature) {
    temperature = clamp(temperature, 1000.0, 40000.0);
    float t = temperature / 100.0;

    float r;
    float g;
    float b;

    if (t <= 66.0) {
        r = 255.0;
        g = 99.4708025861 * log(t) - 161.1195681661;
        b = t <= 19.0 ? 0.0 : 138.5177312231 * log(t - 10.0) - 305.0447927307;
    } else {
        r = 329.698727446 * pow(t - 60.0, -0.1332047592);
        g = 288.1221695283 * pow(t - 60.0, -0.0755148492);
        b = 255.0;
    }

    vec3 rgb = clamp(vec3(r, g, b) / 255.0, 0.0, 1.0);
    return rgb / max_of(rgb.xyzz);
}

// White balance gains for a target colour temperature, normalised to green.
vec3 white_balance_gains(float temperature) {
    vec3 gains = blackbody(temperature);
    return gains / max(gains.y, eps);
}

// -------------------------
//   Tonemapping operators
// -------------------------

// ACES filmic fit (Narkowicz). Punchy, slightly saturated, good default.
vec3 tonemap_aces(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp01((x * (a * x + b)) / (x * (c * x + d) + e));
}

// Uncharted 2 / Hable filmic
vec3 uncharted2_curve(vec3 x) {
    const float A = 0.15;
    const float B = 0.50;
    const float C = 0.10;
    const float D = 0.20;
    const float E = 0.02;
    const float F = 0.30;

    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

vec3 tonemap_uncharted2(vec3 x) {
    const float W = 11.2;
    vec3 curr = uncharted2_curve(x * 2.0);
    vec3 white_scale = 1.0 / uncharted2_curve(vec3(W));
    return clamp01(curr * white_scale);
}

vec3 tonemap_reinhard(vec3 x) {
    return x / (1.0 + x);
}

vec3 tonemap_reinhard_extended(vec3 x, float white_point) {
    float l = luminance(x);
    float scale = (1.0 + l / (white_point * white_point)) / (1.0 + l);
    return x * scale;
}

// Khronos PBR Neutral - preserves hue and saturation in the midtones
vec3 tonemap_neutral(vec3 color) {
    const float start_compression = 0.8 - 0.04;
    const float desaturation = 0.15;

    float x = min(color.r, min(color.g, color.b));
    float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
    color -= offset;

    float peak = max(color.r, max(color.g, color.b));

    if (peak < start_compression) {
        return color;
    }

    float d = 1.0 - start_compression;
    float new_peak = 1.0 - d * d / (peak + d - start_compression);
    color *= new_peak / peak;

    float g = 1.0 - 1.0 / (desaturation * (peak - new_peak) + 1.0);

    return mix(color, vec3(new_peak), g);
}

// Muon filmic: hue-preserving luminance compression with a controllable
// highlight desaturation. This is what gives the pack its clean, unsaturated-
// only-at-the-top look instead of a milky haze.
vec3 tonemap_muon(vec3 color, float desaturation_amount) {
    float l = luminance(color);
    float compressed = tonemap_aces(vec3(l)).x;

    // Blend between full hue preservation and luminance-only compression as
    // the pixel gets brighter. Keeps sunsets saturated but stops fire from
    // turning into white blobs.
    float blend = smoothstep(0.15, 2.5, l) * desaturation_amount;

    vec3 chroma_scaled = color * (compressed / max(l, eps));
    return mix(chroma_scaled, vec3(compressed), blend);
}

vec3 tonemap_operator(vec3 color, int op) {
#if TONEMAP == 0
    return tonemap_muon(color, 0.45);
#elif TONEMAP == 1
    return tonemap_aces(color);
#elif TONEMAP == 2
    return tonemap_neutral(color);
#elif TONEMAP == 3
    return tonemap_uncharted2(color);
#elif TONEMAP == 4
    return tonemap_reinhard_extended(color, 4.0);
#elif TONEMAP == 5
    return tonemap_aces(color * 1.1);
#else
    return tonemap_muon(color, 0.45);
#endif
}

// -------------------
//   Grade helpers
// -------------------

// Filmic contrast around a pivot of 0.18 (linear mid grey)
vec3 contrast(vec3 color, float amount) {
    const float pivot = 0.18;
    return max(vec3(0.0), (color - pivot) * amount + pivot);
}

// Saturation, luminance preserving
vec3 saturation(vec3 color, float amount) {
    float l = luminance(color);
    return max(vec3(0.0), mix(vec3(l), color, amount));
}

// Vibrance: boosts low-saturation colours more than already saturated ones
vec3 vibrance(vec3 color, float amount) {
    float max_c = max_of(color);
    float min_c = min_of(color);
    float sat = max_c - min_c;
    float boost = amount * (1.0 - sat) * (1.0 - sat);
    return saturation(color, 1.0 + boost);
}

// Hue-selective saturation, used for the warm orange / teal grade
vec3 hue_saturation(vec3 color, float center_degrees, float width_degrees, float amount) {
    vec3 hsl = rgb_to_hsl(color);

    float hue = hsl.x * 360.0;
    float weight = pulse(hue, center_degrees, width_degrees, 360.0);

    hsl.y = clamp01(hsl.y * (1.0 + amount * weight));
    hsl.x = fract(hsl.x + 0.0);

    return hsl_to_rgb(hsl);
}

vec3 hue_shift(vec3 color, float center_degrees, float width_degrees, float amount) {
    vec3 hsl = rgb_to_hsl(color);

    float hue = hsl.x * 360.0;
    float weight = pulse(hue, center_degrees, width_degrees, 360.0);

    hsl.x = fract(hsl.x + amount * weight / 360.0);

    return hsl_to_rgb(hsl);
}

// Split toning: tint the shadows and highlights in opposite directions
vec3 split_tone(vec3 color, vec3 shadow_tint, vec3 highlight_tint, float strength) {
    float l = clamp01(luminance(color));
    float shadow_weight = 1.0 - cubic_smooth(clamp01(l * 2.0));
    float highlight_weight = cubic_smooth(clamp01(l * 2.0 - 1.0));

    vec3 tint = shadow_tint * shadow_weight + highlight_tint * highlight_weight;
    return color * mix(vec3(1.0), tint, strength);
}

// Lift / gamma / gain, all in one
vec3 lift_gamma_gain(vec3 color, vec3 lift_v, vec3 gamma_v, vec3 gain_v) {
    color = color * gain_v + lift_v * (1.0 - color);
    return pow(max(color, vec3(0.0)), 1.0 / max(gamma_v, vec3(eps)));
}

// Purkinje shift: rods are more sensitive to blue, so night scenes lose red
// sensitivity and everything reads cooler.
vec3 purkinje_shift(vec3 color, float amount) {
    float blue_bias = 0.25 * amount;
    vec3 shifted = color * vec3(1.0 - blue_bias, 1.0 - blue_bias * 0.5, 1.0 + blue_bias);
    return mix(color, shifted, amount * clamp01(1.0 - luminance(color) * 4.0));
}

// Desaturate towards a target luminance while keeping a little chroma
vec3 desaturate(vec3 color, float amount) {
    return mix(color, vec3(luminance(color)), amount);
}

// Isolate a hue band, returns [0, 1]
float isolate_hue(vec3 hsl, float center_degrees, float width_degrees) {
    if (hsl.y < 0.02 || hsl.z < 0.02) return 0.0;
    return pulse(hsl.x * 360.0, center_degrees, width_degrees, 360.0);
}

// ----------------------------
//   Dithering / quantising
// ----------------------------

vec3 dither_8bit(vec3 color, float noise) {
    // Triangular PDF, +/- 0.5 LSB at 8 bit
    float amplitude = 1.0 / 255.0;
    return color + (noise - 0.5) * amplitude;
}

// Highlight-safe clamp, avoids negatives blowing up filters
vec3 sanitize_color(vec3 c) {
    c = max(c, vec3(0.0));
    // Kill NaN/Inf that occasionally comes out of screen-space ray misses
    bvec3 bad = bvec3(isnan(c));
    if (any(bad)) c = vec3(0.0);
    return min(c, vec3(60000.0));
}

#endif // MUON_COLOR
