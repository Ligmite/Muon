#version 400 compatibility
/*
================================================================================

  Muon Shaders
  final.fsh - anti-aliasing, dithering, HDR encoding and debug views

  This is the only pass that writes to the screen, and the only one that knows
  about the display transfer function.

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/color.glsl"
#include "/lib/random.glsl"
#include "/lib/encoding.glsl"
#include "/lib/shadow.glsl"
#include "/lib/post.glsl"
#include "/lib/buffers.glsl"

layout(location = 0) out vec4 fragment_color;

uniform sampler2D colortex2;  // normals (debug)
uniform sampler2D colortex13; // tonemapped image
uniform sampler2D colortex6;  // bloom
uniform sampler2D colortex14; // light levels

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    ivec2 texel = ivec2(gl_FragCoord.xy);

    vec3 color = texture(colortex13, uv).rgb;

#if DEBUG_VIEW == 4
    // Shadow visibility debug
    {
        float depth = texture(depthtex1, uv).r;
        if (depth < 1.0) {
            vec3 scene_pos = screen_to_scene_space(vec3(uv, depth));
            vec3 normal = decode_normal_octa(texture(colortex2, uv).xy);
            color = vec3(shadow_sample_fast(scene_pos + normal * 0.05, 1.0));
        } else {
            color = vec3(0.05);
        }
    }
#elif DEBUG_VIEW == 5
    color = texture(colortex6, uv).rgb * 20.0;
#elif DEBUG_VIEW == 9
    color = vec3(pow(texture(colortex14, uv).r, 1.0), texture(colortex14, uv).g, 0.0);
#endif

#if DEBUG_VIEW != 0
    fragment_color = vec4(display_eotf(color), 1.0);
    return;
#endif

    // ---- anti-aliasing ----
#if defined FXAA
    color = fxaa(colortex13, uv, 1.0 / vec2(viewWidth, viewHeight));
#elif defined CAS
    {
        vec3 a = texelFetch(colortex13, texel + ivec2(-1, -1), 0).rgb;
        vec3 b = texelFetch(colortex13, texel + ivec2(0, -1), 0).rgb;
        vec3 c = texelFetch(colortex13, texel + ivec2(1, -1), 0).rgb;
        vec3 d = texelFetch(colortex13, texel + ivec2(-1, 0), 0).rgb;
        vec3 e = texelFetch(colortex13, texel, 0).rgb;
        vec3 f = texelFetch(colortex13, texel + ivec2(1, 0), 0).rgb;
        vec3 g = texelFetch(colortex13, texel + ivec2(-1, 1), 0).rgb;
        vec3 h = texelFetch(colortex13, texel + ivec2(0, 1), 0).rgb;
        vec3 i = texelFetch(colortex13, texel + ivec2(1, 1), 0).rgb;

        color = cas_sharpen(a, b, c, d, e, f, g, h, i, CAS_INTENSITY);
    }
#endif

    // ---- display encoding / HDR ----
    vec3 output_color = display_eotf(color);

#ifndef MUON_HDR_OUTPUT
    // 8 bit output needs dithering to avoid banding in the sky
    output_color = dither_8bit(output_color, bayer16(vec2(texel)));
#endif

    fragment_color = vec4(clamp01(output_color), 1.0);
}
