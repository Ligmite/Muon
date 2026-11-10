#version 400 compatibility
/*
================================================================================

  Muon Shaders
  composite3.fsh - bloom horizontal blur (half resolution)

  RENDERTARGETS: 7

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/post.glsl"

layout(location = 0) out vec4 out_bloom;

/* RENDERTARGETS: 7 */

uniform sampler2D colortex6;

void main() {
    vec2 resolution = vec2(textureSize(colortex6, 0));
    vec2 uv = gl_FragCoord.xy / resolution;
    vec2 texel = 1.0 / resolution;

    vec3 bloom = bloom_blur(colortex6, uv, texel * BLOOM_SPREAD, 2.0);

    out_bloom = vec4(bloom, 1.0);
}
