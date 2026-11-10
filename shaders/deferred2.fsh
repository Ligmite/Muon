#version 400 compatibility
/*
================================================================================

  Muon Shaders
  deferred2.fsh - volumetric clouds

  Renders at half resolution into colortex7: rgb = premultiplied scatter,
  a = transmittance.
  RENDERTARGETS: 7

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/encoding.glsl"
#include "/lib/random.glsl"
#include "/lib/clouds.glsl"
#include "/lib/lighting.glsl"

layout(location = 0) out vec4 out_clouds;

/* RENDERTARGETS: 7 */

void main() {
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * 0.5);

    vec3 view_dir = screen_to_view_space(gbufferProjectionInverse, vec3(uv, 1.0));
    vec3 scene_dir = normalize(mat3(gbufferModelViewInverse) * normalize(view_dir));

    float depth = texture(depthtex1, uv).r;
    float max_distance = depth >= 1.0 ? 24000.0 : depth_to_distance(depth) * 1.02;

    vec3 light_dir = shadow_light_dir_scene();
    vec3 light_color = direct_light_color(light_dir);

    float dither = blue_noise(uv, frameCounter);

    vec4 result;

#ifdef CLOUDS
    CloudResult clouds = march_clouds(vec3(0.0), scene_dir, max_distance, light_dir, light_color, dither);
    result = vec4(clouds.scatter, clouds.transmittance);
#else
    result = vec4(0.0, 0.0, 0.0, 1.0);
#endif

    // Optional classic flat layer in front of the volumetric ones
    vec4 flat_layer = flat_cloud_layer(vec3(0.0), scene_dir, max_distance);
    result.rgb = result.rgb * flat_layer.a + flat_layer.rgb;
    result.a *= flat_layer.a;

    out_clouds = result;
}
