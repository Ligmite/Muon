#version 400 compatibility
/*
================================================================================

  Muon Shaders
  deferred1.fsh - volumetric lighting and fog

  Renders at half resolution into colortex6: rgb = in-scatter, a = transmittance.
  RENDERTARGETS: 6

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/encoding.glsl"
#include "/lib/random.glsl"
#include "/lib/volumetrics.glsl"
#include "/lib/lighting.glsl"

layout(location = 0) out vec4 out_volumetrics;

/* RENDERTARGETS: 6 */

void main() {
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * 0.5);

    float depth = texture(depthtex1, uv).r;
    float distance = depth >= 1.0 ? far : depth_to_distance(depth);

    // Keep the march bounded; beyond this the fog is opaque anyway
    distance = min(distance, 256.0);

    vec3 view_dir = screen_to_view_space(gbufferProjectionInverse, vec3(uv, 1.0));
    vec3 scene_dir = normalize(mat3(gbufferModelViewInverse) * normalize(view_dir));

    vec3 light_dir = shadow_light_dir_scene();
    vec3 light_color = direct_light_color(light_dir);

    float dither = interleaved_gradient_noise(gl_FragCoord.xy, float(frameCounter));

    out_volumetrics = volumetric_lighting(vec3(0.0), scene_dir, distance, light_dir, light_color, dither);
}
