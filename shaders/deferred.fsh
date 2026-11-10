#version 400 compatibility
/*
================================================================================

  Muon Shaders
  deferred.fsh - ambient occlusion

  Renders at half resolution into colortex4.
  RENDERTARGETS: 4

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/encoding.glsl"
#include "/lib/random.glsl"
#include "/lib/ao.glsl"

layout(location = 0) out vec4 out_ao;

/* RENDERTARGETS: 4 */

uniform sampler2D colortex2; // normals

void main() {
    // colortex4 is exactly half resolution, so derive uv from the screen size
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * 0.5);

    float depth = texture(depthtex1, uv).r;

    float ao = 1.0;

    if (depth < 1.0) {
        vec3 normal = decode_normal_octa(texture(colortex2, uv).xy);
        vec3 view_pos = screen_to_view_space(gbufferProjectionInverse, vec3(uv, depth));
        vec3 view_normal = normalize(mat3(gbufferModelView) * normal);

        float dither = interleaved_gradient_noise(gl_FragCoord.xy, float(frameCounter));

        ao = compute_ao(view_pos, view_normal, dither);
    }

    out_ao = vec4(ao, ao, 0.0, 1.0);
}
