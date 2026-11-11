/*
================================================================================

  Muon Shaders - lib/common/lensflare.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Lens flare.

  Three physically motivated pieces make up the effect:

    * an occlusion test - the flare only exists when the sun's screen position
      is actually visible, which is what keeps it from shining through a hill,
    * ghosts - a few scaled copies of the sun's screen position reflected
      through the centre of the frame, with chromatic tint,
    * a halo - the faint ring produced by light scattered inside the lens
      assembly.

  Sun visibility is read back from the depth buffer rather than assumed, so the
  flare disappears correctly when the player walks into shadow.

================================================================================
*/

#ifndef MUON_COMMON_LENSFLARE_GLSL
#define MUON_COMMON_LENSFLARE_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/color.glsl"
#include "/lib/common/sampling.glsl"
#include "/lib/common/atmosphere.glsl"


// -----------------------------------------------------------------------------
//  Sun on screen
// -----------------------------------------------------------------------------

struct MuonSunScreen {
    vec2 uv;
    float visible;
    float radius;
};

MuonSunScreen muon_sun_screen_position() {
    MuonSunScreen result;
    result.uv = vec2(0.5);
    result.visible = 0.0;
    result.radius = 0.0;

    vec3 light_dir = muon_direct_light_direction();
    vec4 clip = muonFrame.projection * (muonFrame.view * vec4(muon_camera_position() + light_dir * 1024.0, 1.0));
    if (clip.w <= 0.0) {
        return result;
    }

    vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
    if (uv.x < -0.35 || uv.x > 1.35 || uv.y < -0.35 || uv.y > 1.35) {
        return result;
    }

    /* Only light that actually reaches the eye can flare. */
    vec2 clamped_uv = clamp(uv, vec2(0.0), vec2(1.0));
    float center_depth = texture(depthtex0, clamped_uv).r;

    result.uv = uv;
    result.visible = center_depth >= 1.0 ? 1.0 : 0.0;
    result.radius = 0.018 * SUN_ANGULAR_RADIUS;

    /* Fade the flare as the light approaches the horizon so that sunset do/es
       not produce a full-strength ghost train. */
    result.visible *= muon_smoothstep(-0.02, 0.12, light_dir.y);
    result.visible *= 1.0 - muon_rain_strength() * 0.6;

    return result;
}

// -----------------------------------------------------------------------------
//  Ghost train
// -----------------------------------------------------------------------------

/*
 * A ghost is a disc placed on the line from the sun through the centre of the
 * frame. Its position and size follow the standard photograph convention: each
 * ghost sits at `-t * (sun - centre)` with its own scale.
 */
vec3 muon_lens_ghosts(MuonSunScreen sun) {
#if !defined LENS_FLARE
    return vec3(0.0);
#else
    if (sun.visible <= 0.001) {
        return vec3(0.0);
    }

    vec2 uv = gl_FragCoord.xy * muon_inv_viewport();
    vec2 axis = vec2(0.5) - sun.uv;
    float aspect = muon_aspect_ratio();

    vec3 flare = vec3(0.0);

    for (int i = 1; i <= LENS_FLARE_GHOSTS; i++) {
        float t = float(i) * 0.42;
        vec2 ghost_center = sun.uv + axis * t;
        float ghost_radius = mix(0.012, 0.075, fract(float(i) * 0.37));

        vec2 delta = (uv - ghost_center) * vec2(aspect, 1.0);
        float distance = length(delta);
        float disc = muon_saturate(1.0 - distance / ghost_radius);
        disc *= disc;

        vec3 tint = mix(vec3(1.0, 0.55, 0.25), vec3(0.35, 0.65, 1.0), fract(float(i) * 0.61));
        flare += tint * disc * (0.25 / float(i));
    }

    /* Halo ring around the frame centre. */
    vec2 centered = (uv - vec2(0.5)) * vec2(aspect, 1.0);
    float halo_distance = length(centered);
    float halo = muon_saturate(1.0 - abs(halo_distance - 0.42) / 0.09);
    flare += vec3(1.0, 0.86, 0.68) * halo * halo * 0.10;

    return flare * sun.visible;
#endif
}

/* Bright, tight core around the sun itself. */
vec3 muon_sun_glow(MuonSunScreen sun, vec3 sun_color) {
    vec2 uv = gl_FragCoord.xy * muon_inv_viewport();
    vec2 delta = (uv - sun.uv) * vec2(muon_aspect_ratio(), 1.0);
    float distance = length(delta);

    float core = exp(-distance * 22.0);
    float bloom = exp(-distance * 3.2) * 0.35;

    return sun_color * ((core + bloom) * sun.visible);
}

vec3 muon_apply_lens_flare(vec3 color, MuonSunScreen sun, vec3 sun_color) {
#if !defined LENS_FLARE
    return color;
#else
    vec3 flare = (muon_lens_ghosts(sun) * 3.0 + muon_sun_glow(sun, sun_color)) * LENS_FLARE_STRENGTH;
    return color + flare;
#endif
}

#endif // MUON_COMMON_LENSFLARE_GLSL
