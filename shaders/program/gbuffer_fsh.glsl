/*
================================================================================

  Muon Shaders
  program/gbuffer_fsh.glsl - shared opaque G-buffer fragment stage

  Writes:
    colortex1  albedo.rgb, material id
    colortex2  octahedral normal, roughness, metalness
    colortex3  emission, sss, vanilla ao, f0
    colortex14 skylight, blocklight, porosity, flags

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/color.glsl"
#include "/lib/materials.glsl"
#include "/lib/encoding.glsl"
#include "/lib/noise.glsl"

layout(location = 0) out vec4 out_albedo;
layout(location = 1) out vec4 out_normal;
layout(location = 2) out vec4 out_material;
layout(location = 3) out vec4 out_light;

/* RENDERTARGETS: 1,2,3,14 */

in vec2 uv;
in vec2 uv_local;
in vec2 light_levels;
in vec3 scene_pos;
in vec3 view_pos_out;
in vec3 normal;
in vec3 tint;
in float vanilla_ao;

flat in uint material_id;
flat in mat3 tbn;

// --------------
//   POM
// --------------

#if defined POM && defined PROGRAM_TERRAIN
const int pom_steps = POM_SAMPLES;

float height_at(vec2 coord) {
    vec4 tex = texture(gtexture, coord);
    // Dark pixels are "deep". This lets POM work without a dedicated heightmap.
    return 1.0 - clamp01(luma(srgb_eotf_inv(tex.rgb)));
}

// Returns the parallaxed texture coordinate
vec2 parallax_occlusion_mapping(vec2 coord, vec3 tangent_view_dir) {
    float distance_to_surface = length(scene_pos);

    if (distance_to_surface > POM_DISTANCE) {
        return coord;
    }

    float fade = 1.0 - smoothstep(POM_DISTANCE * 0.6, POM_DISTANCE, distance_to_surface);

    // The steeper the view, the more depth we offset
    float height_scale = POM_DEPTH * 0.05 * fade;
    vec2 step_dir = -tangent_view_dir.xy / max(abs(tangent_view_dir.z), 0.15) * height_scale;

    float layer_depth = 0.0;
    float step_size = 1.0 / float(pom_steps);

    vec2 current = coord;
    float current_height = height_at(current);

    for (int i = 0; i < pom_steps; i++) {
        layer_depth += step_size;
        current += step_dir * step_size;
        current_height = height_at(current);

        if (current_height < layer_depth) {
            break;
        }
    }

    // Binary refinement between the last two layers
    current -= step_dir * step_size * 0.5;
    return current;
}
#endif

// --------
//   Main
// --------

void main() {
    vec2 tex_uv = uv;

    // Parallax occlusion mapping for terrain
#if defined POM && defined PROGRAM_TERRAIN
    vec3 tangent_view_dir = transpose(tbn) * normalize(scene_pos);
    tex_uv = parallax_occlusion_mapping(uv, tangent_view_dir);
#endif

    vec4 texture_data = texture(gtexture, tex_uv);

    // Alpha test. Iris gives us the correctly scaled reference value.
    if (texture_data.a < alphaTestRef) {
        discard;
    }

    vec3 albedo = srgb_eotf_inv(texture_data.rgb) * tint;

#if defined PROGRAM_ENTITIES
    albedo = mix(albedo, entityColor.rgb * albedo, entityColor.a);
#endif

    if (all(lessThan(albedo, vec3(0.0)))) {
        albedo = vec3(0.0);
    }

    // Material properties
    MaterialData material = default_material_data(material_id);

    // Normal mapping
    vec3 N = normalize(normal);

#if defined NORMAL_MAPPING && RESOURCEPACK_SUPPORT > 0
    vec3 normal_data = texture(normals, tex_uv).rgb * 2.0 - 1.0;
    normal_data.xy *= 1.0;

    vec3 mapped = normalize(tbn * normalize(normal_data));
    // Only trust the normal map if it is not the flat default (128,128,255)
    float strength = clamp01(length(normal_data.xy) * 4.0);
    N = normalize(mix(N, mapped, strength));
#endif

    // Specular data
#ifdef SPECULAR_MAPPING
    vec4 specular_data = texture(specular, tex_uv);
    decode_specular(specular_data, material);
#endif

    apply_hardcoded_materials(material_id, albedo, N, material);

    // Rain wetness: porous, upward facing surfaces get darker and shinier
    float wetness_amount = 0.0;

#ifdef RAIN_PUDDLES
    if (wetness > 0.01 && normal.y > 0.5) {
        float puddle = clamp01((wetness - 0.4) * 2.0) * material.porosity;
        float noise_mask = smoothstep(0.3, 0.7, value_noise(vec3(scene_pos.xz * 0.35, 1.0)));

        puddle *= noise_mask * PUDDLE_STRENGTH;

        if (puddle > 0.0) {
            albedo *= 1.0 - puddle * 0.45;
            material.roughness = mix(material.roughness, 0.04, puddle);
            material.f0 = mix(material.f0, 0.02, puddle);
            wetness_amount = puddle;
        }
    }
#endif

    // General wet darkening
    if (wetness > 0.0) {
        albedo *= 1.0 - wetness * 0.12 * material.porosity;
    }

    sanitize_material(material, material_id);

    // Emission: emissive blocks plus resource pack emission
    float emission = material.emission;

    float skylight = pow(clamp01(light_levels.y), 2.2);
    float blocklight = pow(clamp01(light_levels.x), 2.2);

    // Write the G-buffer
    out_albedo = pack_gbuffer_0(albedo, material_id);
    out_normal = pack_gbuffer_1(N, material.roughness, material.metalness);
    out_material = pack_gbuffer_2(emission, material.sss, vanilla_ao, material.f0);
    out_light = vec4(skylight, blocklight, material.porosity, wetness_amount);
}
