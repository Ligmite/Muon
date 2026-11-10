/*
================================================================================

  Muon Shaders
  voxy_translucent.glsl - Voxy translucent LoD entry point

  Draw buffers must match voxy.json's "translucentDrawBuffers": [9, 10].

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/color.glsl"
#include "/lib/materials.glsl"
#include "/lib/encoding.glsl"

layout(location = 0) out vec4 translucent_extras;
layout(location = 1) out vec4 translucent_color;

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec3 base_color = parameters.sampledColour.rgb * parameters.tinting.rgb;
    vec3 albedo = srgb_eotf_inv(base_color);

    vec3 normal = vec3(
        float(int(parameters.face >> 1) == 2),
        float(int(parameters.face >> 1) == 0),
        float(int(parameters.face >> 1) == 1)
    ) * (float(int(parameters.face) & 1) * 2.0 - 1.0);

    float alpha = clamp(parameters.sampledColour.a, 0.05, 1.0);
    float flags = 1.0; // water

    // The surface depth is not available here; Voxy translucent LoD water is
    // far away, so use the far plane. The composite pass treats it as opaque
    // glass in that case.
    translucent_extras = vec4(encode_normal_octa(normal), 1.0, flags);
    translucent_color = vec4(albedo * alpha, alpha);
}
