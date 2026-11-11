/*
================================================================================

  Muon Shaders - lib/common/color.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Colour space plumbing.

  Muon maintains one rule everywhere: the scene is linear Rec.709 (sRGB
  primaries) from the first write to the colour targets until the final pass,
  which is the only place a display transfer function is applied. Every helper
  that could break that rule is named so that it is obvious at the call site.

================================================================================
*/

#ifndef MUON_COMMON_COLOR_GLSL
#define MUON_COMMON_COLOR_GLSL

#include "/lib/common/math.glsl"

// -----------------------------------------------------------------------------
//  Transfer functions
// -----------------------------------------------------------------------------

vec3 muon_srgb_to_linear(vec3 c) {
    vec3 low = c / 12.92;
    vec3 high = pow((c + 0.055) / 1.055, vec3(2.4));
    return mix(low, high, step(vec3(0.04045), c));
}

vec3 muon_linear_to_srgb(vec3 c) {
    vec3 safe = max(c, vec3(0.0));
    vec3 low = safe * 12.92;
    vec3 high = 1.055 * pow(safe, vec3(1.0 / 2.4)) - 0.055;
    return mix(low, high, step(vec3(0.0031308), safe));
}

float muon_srgb_to_linear(float c) {
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float muon_linear_to_srgb(float c) {
    float safe = max(c, 0.0);
    return safe <= 0.0031308 ? safe * 12.92 : 1.055 * pow(safe, 1.0 / 2.4) - 0.055;
}

// -----------------------------------------------------------------------------
//  Perceptual helpers
// -----------------------------------------------------------------------------

float muon_luminance(vec3 c) {
    return dot(max(c, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));
}

/* Perceptual brightness, useful for matching perceived contrast. */
float muon_perceived_brightness(vec3 c) {
    return sqrt(muon_luminance(c));
}

vec3 muon_saturation(vec3 c, float amount) {
    float l = muon_luminance(c);
    return mix(vec3(l), c, amount);
}

vec3 muon_contrast(vec3 c, float amount) {
    return (c - vec3(0.18)) * amount + vec3(0.18);
}

vec3 muon_brightness(vec3 c, float amount) {
    return c * amount;
}

/* Adds warmth without shifting the luminance. */
vec3 muon_temperature(vec3 c, float amount) {
    vec3 warm = vec3(1.0 + 0.12 * amount, 1.0 + 0.02 * amount, 1.0 - 0.14 * amount);
    return c * warm;
}

vec3 muon_tint(vec3 c, float amount) {
    vec3 shifted = vec3(1.0 - 0.06 * amount, 1.0 + 0.05 * amount, 1.0 - 0.05 * amount);
    return c * shifted;
}

/* Rotates hue about the luma axis, preserving luminance (Rec.709 weights). */
vec3 muon_hue_rotate(vec3 c, float degrees) {
    float angle = degrees * MUON_DEG2RAD;
    float s = sin(angle);
    float co = cos(angle);

    /* Row-major reference matrix; columns are rebuilt below so that the
       column-major construction of GLSL mat3 cannot invert the rotation. */
    float m00 = 0.213 + co * 0.787 - s * 0.213;
    float m01 = 0.715 - co * 0.715 - s * 0.715;
    float m02 = 0.072 - co * 0.072 + s * 0.928;
    float m10 = 0.213 - co * 0.213 + s * 0.143;
    float m11 = 0.715 + co * 0.285 + s * 0.140;
    float m12 = 0.072 - co * 0.072 - s * 0.283;
    float m20 = 0.213 - co * 0.213 - s * 0.787;
    float m21 = 0.715 - co * 0.715 + s * 0.715;
    float m22 = 0.072 + co * 0.928 + s * 0.072;

    return vec3(
        dot(c, vec3(m00, m10, m20)),
        dot(c, vec3(m01, m11, m21)),
        dot(c, vec3(m02, m12, m22))
    );
}

// -----------------------------------------------------------------------------
//  Blackbody / light colour
// -----------------------------------------------------------------------------

/*
 * Approximate blackbody radiance in linear Rec.709, normalised to unit
 * luminance. Valid between roughly 1000 K and 40000 K, which covers every
 * in-game light temperature Muon uses.
 */
vec3 muon_blackbody(float kelvin) {
    float t = clamp(kelvin, 1000.0, 40000.0) / 100.0;
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

    vec3 rgb = clamp(vec3(r, g, b) / 255.0, vec3(0.0), vec3(1.0));
    return rgb / max(muon_luminance(rgb), MUON_EPSILON);
}

// -----------------------------------------------------------------------------
//  Vectors to colours
// -----------------------------------------------------------------------------

vec3 muon_direction_to_color(vec3 direction) {
    return direction * 0.5 + 0.5;
}

vec3 muon_debug_color(float value, vec3 negative, vec3 positive) {
    return value >= 0.0 ? mix(vec3(0.0), positive, abs(value)) : mix(vec3(0.0), negative, abs(value));
}

/* Rainbow ramp used by the debug views. */
vec3 muon_heat_map(float t) {
    float v = muon_saturate(t);
    vec3 cold = vec3(0.02, 0.05, 0.25);
    vec3 mid = vec3(0.10, 0.55, 0.65);
    vec3 warm = vec3(0.95, 0.70, 0.20);
    vec3 hot = vec3(1.00, 0.20, 0.05);
    if (v < 0.33) {
        return mix(cold, mid, v / 0.33);
    } else if (v < 0.66) {
        return mix(mid, warm, (v - 0.33) / 0.33);
    }
    return mix(warm, hot, (v - 0.66) / 0.34);
}

#endif // MUON_COMMON_COLOR_GLSL
