/*
================================================================================

  Muon Shaders - lib/common/tonemap.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Display transforms. All operators accept linear HDR radiance and return
  linear display-referred colour; the sRGB/Rec.709 transfer function is applied
  separately, in the final pass only.

  Operators:
    0 - AgX (default): filmic, very gentle highlight roll-off, preserves the
        warm/cool separation that Muon's grade is built around.
    1 - ACES (Hill fit): the classic cinematic curve, slightly more saturated.
    2 - Reinhard extended: neutral reference for comparisons.

================================================================================
*/

#ifndef MUON_COMMON_TONEMAP_GLSL
#define MUON_COMMON_TONEMAP_GLSL

#include "/lib/common/math.glsl"
#include "/lib/common/color.glsl"

// -----------------------------------------------------------------------------
//  ACES
// -----------------------------------------------------------------------------

const mat3 MUON_ACES_INPUT = mat3(
    0.59719, 0.07600, 0.02840,
    0.35458, 0.90834, 0.13383,
    0.04823, 0.01566, 0.83777
);

const mat3 MUON_ACES_OUTPUT = mat3(
    1.60475, -0.10208, -0.00327,
    -0.53108, 1.10813, -0.07276,
    -0.07367, -0.00605, 1.07602
);

vec3 muon_aces_rrt_and_odt_fit(vec3 v) {
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return a / b;
}

vec3 muon_tonemap_aces(vec3 color, float exposure) {
    vec3 v = color * exposure * (1.0 / 0.6);
    v = MUON_ACES_INPUT * v;
    v = muon_aces_rrt_and_odt_fit(v);
    v = MUON_ACES_OUTPUT * v;
    return muon_saturate(v);
}

// -----------------------------------------------------------------------------
//  AgX
//  Minimal AgX in linear Rec.709, following the published sigmoid fit. The
//  inset/outset matrices are the Rec.709 variants.
// -----------------------------------------------------------------------------

const mat3 MUON_AGX_INSET = mat3(
    0.842479062253094, 0.0423282422610123, 0.0423756549057051,
    0.0784335999999992, 0.878468636469772, 0.0784336000000000,
    0.0792237451477643, 0.0791661274605434, 0.879142973793104
);

const mat3 MUON_AGX_OUTSET = mat3(
    1.19687900512017, -0.0528968517574562, -0.0529716355144438,
    -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
    -0.0990297440797205, -0.0989611768448433, 1.15107367264116
);

/* The 6th order sigmoid from the AgX reference implementation. */
vec3 muon_agx_contrast_approx(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;
    return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}

vec3 muon_tonemap_agx(vec3 color, float exposure) {
    const float min_ev = -12.47393;
    const float max_ev = 4.026069;

    vec3 v = color * exposure;
    v = MUON_AGX_INSET * v;
    v = max(v, vec3(1.0e-10));
    v = log2(v);
    v = (v - vec3(min_ev)) / (max_ev - min_ev);
    v = muon_saturate(v);
    v = muon_agx_contrast_approx(v);
    v = MUON_AGX_OUTSET * v;
    return muon_saturate(v);
}

// -----------------------------------------------------------------------------
//  Reinhard
// -----------------------------------------------------------------------------

vec3 muon_tonemap_reinhard(vec3 color, float exposure, float white_point) {
    vec3 v = color * exposure;
    vec3 numerator = v * (1.0 + v / (white_point * white_point));
    return muon_saturate(numerator / (1.0 + v));
}

vec3 muon_tonemap_reinhard_simple(vec3 color, float exposure) {
    vec3 v = color * exposure;
    return muon_saturate(v / (1.0 + v));
}

// -----------------------------------------------------------------------------
//  Dispatcher
// -----------------------------------------------------------------------------

vec3 muon_tonemap(vec3 color, int mode, float exposure, float white_point) {
    if (mode == 0) {
        return muon_tonemap_agx(color, exposure);
    } else if (mode == 1) {
        return muon_tonemap_aces(color, exposure);
    }
    return muon_tonemap_reinhard(color, exposure, white_point);
}

// -----------------------------------------------------------------------------
//  Pre-tonemap range compression
//  A soft knee keeps specular highlights from clipping before the curve can
//  roll them off, which is what gives Muon its "vibrant but not blown out"
//  look at low exposure.
// -----------------------------------------------------------------------------

vec3 muon_soft_knee(vec3 color, float knee) {
    vec3 under = color;
    vec3 over = knee + (1.0 - exp(-(color - knee) / max(1.0 - knee, MUON_EPSILON))) * (1.0 - knee);
    return mix(over, under, step(color, vec3(knee)));
}

#endif // MUON_COMMON_TONEMAP_GLSL
