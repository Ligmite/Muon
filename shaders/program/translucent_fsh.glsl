/*
================================================================================

  Muon Shaders
  program/translucent_fsh.glsl - shared translucent fragment stage

  Writes:
    colortex9   octahedral normal, surface depth, flags
    colortex10  premultiplied colour, alpha

  The surfaces are shaded later, in composite.fsh, once the opaque scene is
  available for refraction and screen space reflections.

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/color.glsl"
#include "/lib/materials.glsl"
#include "/lib/encoding.glsl"
#include "/lib/water.glsl"

layout(location = 0) out vec4 out_extras;
layout(location = 1) out vec4 out_color;

/* RENDERTARGETS: 9,10 */

in vec2 uv;
in vec2 light_levels;
in vec3 scene_pos;
in vec3 normal;
in vec3 tint;
in float surface_depth;

flat in uint material_id;

void main() {
    vec4 texture_data = texture(gtexture, uv);

    if (texture_data.a < 0.02) {
        discard;
    }

    vec3 albedo = srgb_eotf_inv(texture_data.rgb) * tint;

    vec3 N = normalize(normal);
    float alpha = texture_data.a;
    float flags = 0.0;

#if defined PROGRAM_WATER
    // Procedural wave normal replaces the flat surface normal
    vec3 world_pos = scene_pos + cameraPosition;
    N = water_normal(world_pos, rainStrength);

    // Blend towards the wave normal but keep the flat face as a fallback
    N = normalize(mix(normalize(normal), N, clamp01(length(N))));

    alpha = clamp(texture_data.a * 0.9, 0.25, 0.94);
    flags = 1.0;
#elif defined PROGRAM_TERRAIN
    if (material_id == MAT_GLASS || material_id == MAT_ICE) {
        flags = 2.0;
    }
#elif defined PROGRAM_WEATHER
    alpha *= RAIN_OPACITY;
    flags = 4.0;
#endif

    // Wet surfaces are slightly darker
    albedo *= 1.0 - rainStrength * 0.05;

    out_extras = vec4(encode_normal_octa(N), surface_depth, flags);
    out_color = vec4(albedo * alpha, alpha);
}
