/*
================================================================================

  Muon Shaders - program/final.fsh
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  The only pass that leaves linear colour space.

  Order matters here and is fixed:
      anti-aliasing (FXAA when TAA is off) -> lens flare -> exposure ->
      tonemap -> grade -> vignette -> grain -> sRGB transfer -> dither

  Everything before the transfer function is linear HDR; everything after it is
  display-referred. Iris' own colour-space conversion runs after this pass, so
  Muon always emits Rec.709 sRGB and lets the loader adapt it to the display.

================================================================================
*/

#include "/lib/common/global.glsl"
#include "/lib/common/tonemap.glsl"
#include "/lib/common/post.glsl"
#include "/lib/common/lensflare.glsl"
#include "/lib/common/atmosphere.glsl"


in vec2 texcoord;

layout(location = 0) out vec4 frag_color;

void main() {
    MUON_FRAME_INIT();

    vec2 uv = texcoord;

    if (MUON_DEBUG_VIEW != 0) {
        frag_color = vec4(muon_debug_view(uv), 1.0);
        return;
    }

    /* --- anti-aliasing -------------------------------------------------- */

#if defined FXAA && !defined TAA
    vec3 hdr = muon_fxaa(uv);
#else
    vec3 hdr = muon_sharpen(uv);
#endif

    /* --- lens ------------------------------------------------------------ */

#if defined LENS_FLARE
    MuonSunScreen sun = muon_sun_screen_position();
    hdr = muon_apply_lens_flare(hdr, sun, muon_sun_color());
#endif

    /* --- exposure -------------------------------------------------------- */

#if defined AUTO_EXPOSURE
    float exposure = texture(colortex12, vec2(0.5)).r;
    if (!(exposure > 0.0) || isinf(exposure)) {
        exposure = 1.0;
    }
#else
    float exposure = exp2(MANUAL_EXPOSURE);
#endif

    hdr *= exposure * TONEMAP_EXPOSURE_PRESCALE;

    /* --- tonemap --------------------------------------------------------- */

    vec3 mapped = muon_tonemap(hdr, TONEMAP_MODE, 1.0, TONEMAP_WHITE_POINT);

    /* --- display-referred grading ---------------------------------------- */

    mapped = muon_color_grade(mapped);
    mapped = muon_apply_vignette(mapped, uv);
    mapped = muon_film_grain(mapped, gl_FragCoord.xy);

    /* --- transfer function ------------------------------------------------ */

    vec3 srgb = muon_linear_to_srgb(mapped);
    srgb = muon_dither(srgb, gl_FragCoord.xy);

    frag_color = vec4(muon_saturate(srgb), 1.0);
}
