/*
================================================================================

  Muon Shaders - lib/common/post.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Final-image operations: grading, sharpening, vignette and dithering.

  Everything here operates on display-referred colour after tonemapping, which
  is the only point in the pipeline where a perceptual operation is correct.
  The grader is deliberately restrained: Muon's look comes from the lighting and
  the tonemap curve, not from stacking saturation on top of them.

================================================================================
*/

#ifndef MUON_COMMON_POST_GLSL
#define MUON_COMMON_POST_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/color.glsl"
#include "/lib/common/random.glsl"


// -----------------------------------------------------------------------------
//  Grading
// -----------------------------------------------------------------------------

vec3 muon_color_grade(vec3 color) {
#if !defined COLOR_GRADING
    return color;
#else
    vec3 graded = color;

    graded = muon_brightness(graded, GRADE_BRIGHTNESS);
    graded = muon_temperature(graded, GRADE_TEMPERATURE);
    graded = muon_tint(graded, GRADE_TINT);

    /* Split toning: cool, slightly blue shadows with warm highlights. This is
       what produces the "warm, vibrant" separation without tinting midtones. */
    float luminance = muon_luminance(graded);
    vec3 shadow_tint = vec3(0.86, 0.93, 1.06);
    vec3 highlight_tint = vec3(1.05, 1.00, 0.94);
    vec3 split = mix(shadow_tint, highlight_tint, muon_saturate(luminance * 2.2));
    graded = mix(graded, graded * split, GRADE_SHADOW_TINT);

    graded = muon_saturation(graded, GRADE_SATURATION);
    graded = muon_contrast(graded, GRADE_CONTRAST);

    return max(graded, vec3(0.0));
#endif
}

// -----------------------------------------------------------------------------
//  Vignette and aberration
// -----------------------------------------------------------------------------

vec3 muon_apply_vignette(vec3 color, vec2 uv) {
#if !defined VIGNETTE
    return color;
#else
    vec2 centered = (uv - vec2(0.5)) * vec2(muon_aspect_ratio(), 1.0);
    float distance = length(centered);
    float falloff = muon_saturate(1.0 - distance * distance * 1.15);
    return color * mix(1.0, falloff, VIGNETTE_STRENGTH);
#endif
}

vec3 muon_chromatic_aberration(vec2 uv) {
#if CHROMATIC_ABERRATION == 0
    return texture(colortex0, uv).rgb;
#else
    vec2 centered = uv - vec2(0.5);
    float amount = CHROMATIC_ABERRATION * 0.0016;
    vec2 offset = centered * amount * dot(centered, centered);

    float red = texture(colortex0, uv + offset).r;
    float green = texture(colortex0, uv).g;
    float blue = texture(colortex0, uv - offset).b;
    return vec3(red, green, blue);
#endif
}

// -----------------------------------------------------------------------------
//  Sharpening
// -----------------------------------------------------------------------------

/*
 * Contrast-adaptive sharpening in the spirit of AMD's CAS. The kernel shrinks
 * where local contrast is already high, which avoids the white fringing that a
 * plain unsharp mask produces on the block edges of a voxel world.
 */
vec3 muon_sharpen(vec2 uv) {
#if !defined SHARPEN
    return texture(colortex0, uv).rgb;
#else
    vec2 texel = muon_inv_viewport();

    vec3 center = texture(colortex0, uv).rgb;
    vec3 north = texture(colortex0, uv + vec2(0.0, texel.y)).rgb;
    vec3 south = texture(colortex0, uv - vec2(0.0, texel.y)).rgb;
    vec3 east = texture(colortex0, uv + vec2(texel.x, 0.0)).rgb;
    vec3 west = texture(colortex0, uv - vec2(texel.x, 0.0)).rgb;

    vec3 min_color = min(min(min(north, south), min(east, west)), center);
    vec3 max_color = max(max(max(north, south), max(east, west)), center);

    vec3 contrast = max_color - min_color;
    float adaptive = sqrt(muon_saturate(muon_luminance(contrast) * 4.0));
    float amount = SHARPEN_STRENGTH * (1.0 - adaptive * 0.75);

    vec3 blurred = (north + south + east + west) * 0.25;
    return clamp(center + (center - blurred) * amount, min_color, max_color);
#endif
}

// -----------------------------------------------------------------------------
//  Noise
// -----------------------------------------------------------------------------

float muon_vignette_weight(vec2 uv) {
    vec2 centered = (uv - vec2(0.5)) * vec2(muon_aspect_ratio(), 1.0);
    return muon_saturate(1.0 - dot(centered, centered) * 0.9);
}

/* Ordered dithering in display space: one blue-noise sample, quantised to the
   8-bit output grid so that gradients do not band. */
vec3 muon_dither(vec3 color, vec2 frag_coord) {
#if !defined DITHER
    return color;
#else
    float noise = muon_blue_noise(frag_coord, 0.0);
    return color + (noise - 0.5) / 255.0;
#endif
}

vec3 muon_film_grain(vec3 color, vec2 frag_coord) {
#if FILM_GRAIN == 0
    return color;
#else
    float grain = muon_blue_noise(frag_coord + vec2(muon_frame_counter() * 37.0), 1.0) - 0.5;
    float luminance = muon_luminance(color);
    /* Grain is strongest in the midtones, as with real film. */
    float response = 1.0 - abs(luminance * 2.0 - 1.0);
    return color + grain * (FILM_GRAIN * 0.06 * response);
#endif
}

// -----------------------------------------------------------------------------
//  Debug views
//
//  Every branch reads a buffer that is genuinely populated, so a debug view can
//  never show the inside of an unbound texture. The set is closed on purpose:
//  adding an entry here means adding one to DEBUG_VIEW in settings.glsl and one
//  to the lang file.
// -----------------------------------------------------------------------------

vec3 muon_debug_view(vec2 uv) {
    int view = MUON_DEBUG_VIEW;

    if (view == 1) {
        return muon_linear_to_srgb(texture(colortex1, uv).rgb);
    } else if (view == 2) {
        vec3 normal = muon_view_to_world_dir(normalize(texture(colortex2, uv).xyz));
        return normal * 0.5 + 0.5;
    } else if (view == 3) {
        float depth = muon_linear_depth(texture(depthtex0, uv).r);
        return muon_heat_map(muon_saturate(depth / max(muonFrame.depthParams.y, 1.0)));
    } else if (view == 4) {
        return vec3(texture(colortex14, uv).r);
    } else if (view == 5) {
        return muon_linear_to_srgb(texture(colortex13, uv).rgb);
    } else if (view == 6) {
        return muon_linear_to_srgb(texture(colortex7, uv).rgb);
    } else if (view == 7) {
        vec2 velocity = texture(colortex8, uv).rg;
        return vec3(0.5 + velocity * 40.0, 0.5);
    } else if (view == 8) {
        return texture(colortex4, uv).rgb;
    } else if (view == 9) {
        float material = texture(colortex3, uv).g;
        return muon_heat_map(material);
    } else if (view == 10) {
        float exposure = texture(colortex12, vec2(0.5)).r;
        return vec3(exposure * 0.25);
    } else if (view == 11) {
        return muon_linear_to_srgb(texture(colortex6, uv).rgb * 4.0);
    }

    return vec3(0.0);
}

// -----------------------------------------------------------------------------
//  FXAA
// -----------------------------------------------------------------------------

/*
 * Luminance-only FXAA, run before the tonemap so that it operates on the
 * perceptual response of the HDR image rather than clipped 8-bit values.
 */
vec3 muon_fxaa(vec2 uv) {
#if !defined FXAA
    return texture(colortex0, uv).rgb;
#else
    vec2 texel = muon_inv_viewport();

    vec3 center = texture(colortex0, uv).rgb;
    float luma_center = muon_luminance(center);

    float luma_north = muon_luminance(texture(colortex0, uv + vec2(0.0, texel.y)).rgb);
    float luma_south = muon_luminance(texture(colortex0, uv - vec2(0.0, texel.y)).rgb);
    float luma_east = muon_luminance(texture(colortex0, uv + vec2(texel.x, 0.0)).rgb);
    float luma_west = muon_luminance(texture(colortex0, uv - vec2(texel.x, 0.0)).rgb);

    float luma_min = min(luma_center, min(min(luma_north, luma_south), min(luma_east, luma_west)));
    float luma_max = max(luma_center, max(max(luma_north, luma_south), max(luma_east, luma_west)));

    float contrast = luma_max - luma_min;
    if (contrast < max(0.0312, luma_max * 0.125) * (1.5 - FXAA_STRENGTH)) {
        return center;
    }

    vec2 direction;
    direction.x = -((luma_north + luma_south) - (luma_east + luma_west));
    direction.y = (luma_north - luma_south) + (luma_east - luma_west);

    float direction_reduce = 1.0 / (min(abs(direction.x), abs(direction.y)) + 0.0078125);
    direction = clamp(direction * direction_reduce, vec2(-8.0), vec2(8.0)) * texel;

    vec3 result = center * 0.5;
    result += texture(colortex0, uv + direction * (1.0 / 3.0 - 0.5)).rgb * 0.125;
    result += texture(colortex0, uv + direction * (2.0 / 3.0 - 0.5)).rgb * 0.125;
    result += texture(colortex0, uv + direction * 0.5).rgb * 0.25;

    return mix(center, result, FXAA_STRENGTH);
#endif
}

#endif // MUON_COMMON_POST_GLSL
