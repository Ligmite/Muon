/*
================================================================================

  Muon Shaders
  voxy_opaque.glsl - Voxy opaque LoD entry point

  Voxy (by Cortex) calls voxy_emitFragment() once per LoD fragment. The
  parameters are provided by Voxy; we only read the fields that are stable
  across its versions.

  Draw buffers must match voxy.json's "opaqueDrawBuffers": [1, 2, 3, 14].

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/color.glsl"
#include "/lib/materials.glsl"
#include "/lib/encoding.glsl"

layout(location = 0) out vec4 gbuffer_0;
layout(location = 1) out vec4 gbuffer_1;
layout(location = 2) out vec4 gbuffer_2;
layout(location = 3) out vec4 gbuffer_3;

void voxy_emitFragment(VoxyFragmentParameters parameters) {
    vec3 base_color = parameters.sampledColour.rgb * parameters.tinting.rgb;
    vec3 albedo = srgb_eotf_inv(base_color);

    // Face index -> normal
    vec3 normal = vec3(
        float(int(parameters.face >> 1) == 2),
        float(int(parameters.face >> 1) == 0),
        float(int(parameters.face >> 1) == 1)
    ) * (float(int(parameters.face) & 1) * 2.0 - 1.0);

    // customId >= 10000 carries a Muon material id from Voxy's block mapping
    uint material_id = uint(max(int(parameters.customId) - 10000, 0));

    if (material_id > 32u) {
        material_id = 0u;
    }

    MaterialData material = default_material_data(material_id);
    apply_hardcoded_materials(material_id, albedo, normal, material);
    sanitize_material(material, material_id);

    vec2 light_levels = clamp01(parameters.lightMap);

    gbuffer_0 = pack_gbuffer_0(albedo, material_id);
    gbuffer_1 = pack_gbuffer_1(normal, material.roughness, material.metalness);
    gbuffer_2 = pack_gbuffer_2(material.emission, material.sss, 1.0, material.f0);
    gbuffer_3 = vec4(pow(light_levels.y, 2.2), pow(light_levels.x, 2.2), material.porosity, 0.0);
}
