#version 400 compatibility
/*
================================================================================

  Muon Shaders
  composite2.fsh - bloom prefilter (half resolution)

  RENDERTARGETS: 6

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/post.glsl"

layout(location = 0) out vec4 out_bloom;

/* RENDERTARGETS: 6 */

uniform sampler2D colortex0;

void main() {
    // colortex6 is half resolution
    vec2 resolution = vec2(viewWidth, viewHeight) * 0.5;
    vec2 uv = gl_FragCoord.xy / resolution;
    vec2 texel = 1.0 / resolution;

    vec3 bloom = bloom_prefilter(colortex0, uv, texel * 2.0, BLOOM_THRESHOLD);

    out_bloom = vec4(bloom, 1.0);
}
