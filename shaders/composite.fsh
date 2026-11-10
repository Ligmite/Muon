#version 400 compatibility
/*
================================================================================

  Muon Shaders
  composite.fsh - translucents, clouds and fog

  Shades the translucent layer (water, glass, ice, weather) against the already
  shaded opaque scene, then composites clouds and volumetric fog.

  RENDERTARGETS: 11

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/color.glsl"
#include "/lib/encoding.glsl"
#include "/lib/water.glsl"
#include "/lib/ssr.glsl"
#include "/lib/volumetrics.glsl"
#include "/lib/lighting.glsl"

layout(location = 0) out vec4 out_color;

/* RENDERTARGETS: 11 */

uniform sampler2D colortex0;  // opaque scene
uniform sampler2D colortex4;  // ambient occlusion
uniform sampler2D colortex5;  // previous frame (SSR source)
uniform sampler2D colortex6;  // volumetrics
uniform sampler2D colortex7;  // clouds
uniform sampler2D colortex9;  // translucent extras
uniform sampler2D colortex10; // translucent colour

vec3 shade_water(
    vec3 scene_pos,
    vec3 normal,
    vec3 albedo,
    float alpha,
    vec3 background,
    float background_depth,
    float dither
) {
    vec3 V = normalize(-scene_pos);
    float NoV = max0(dot(normal, V));

    vec3 light_dir = shadow_light_dir_scene();

    // Reflection
    vec3 reflection = sky_reflection(reflect(-V, normal), light_dir);

#if REFLECTIONS == 2
    vec3 view_pos = scene_to_view_space(scene_pos);
    vec3 view_normal = normalize(mat3(gbufferModelView) * normal);

    SSRResult ssr = ssr_trace(view_pos, view_normal, 0.05, dither, colortex5);
    reflection = mix(reflection, ssr.color, ssr.confidence);
#endif

    // Sun specular highlight
    vec3 sun_color = direct_light_color(light_dir);
    float sun_dot = max0(dot(reflect(-V, normal), light_dir));
    float highlight = pow(sun_dot, 900.0) * 60.0 + pow(sun_dot, 80.0) * 0.6;
    reflection += sun_color * highlight;

    // Refraction
    float water_distance = length(scene_pos);
    float background_distance = depth_to_distance(background_depth);

    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    vec2 refraction_offset = water_refraction_offset(normal, 1.0, max(background_distance - water_distance, 0.0));

    vec2 refracted_uv = clamp(uv + refraction_offset, vec2(0.001), vec2(0.999));
    vec3 refracted = texture(colortex0, refracted_uv).rgb;

    // Beer-Lambert absorption through the water column
    float thickness = max(background_distance - water_distance, 0.0);
    refracted = water_absorbtion(refracted, thickness);

    // Scattering in the water body
    vec3 scattering = water_scattering_color(sun_color, sky_gradient(normal, light_dir), albedo);
    vec3 transmission = exp(-vec3(
        WATER_ABSORPTION_R,
        WATER_ABSORPTION_G,
        WATER_ABSORPTION_B
    ) * 0.08 * thickness);

    refracted = refracted * transmission + scattering * (1.0 - transmission);

    // Caustic highlights on the bottom
#ifdef WATER_CAUSTICS
    float caustics = water_caustics(scene_pos + vec3(0.0, -thickness, 0.0), frameTimeCounter);
    refracted += sun_color * caustics * 0.15 * smoothstep(0.0, 1.0, thickness);
#endif

    // Fresnel mix between refracted and reflected light
    vec3 fresnel = fresnel_schlick(vec3(0.02), NoV);
    vec3 color = mix(refracted, reflection, fresnel);

    // Edge foam
    float foam = water_edge_foam(scene_pos, normal, thickness);
    color += vec3(0.9, 0.95, 1.0) * foam * 0.2;

    return mix(background, color, alpha);
}

vec3 shade_generic_translucent(
    vec3 scene_pos,
    vec3 normal,
    vec3 albedo,
    float alpha,
    vec3 background,
    float dither
) {
    vec3 V = normalize(-scene_pos);
    vec3 light_dir = shadow_light_dir_scene();

    float NoL = max0(dot(normal, light_dir));
    float NoV = max0(dot(normal, V));

    float shadow = direct_light_visibility(scene_pos, normal, light_dir + vec3(0.0), dither);

    vec3 light_color = direct_light_color(light_dir);
    vec3 ambient = ambient_light_color(normal, light_dir);

    vec3 diffuse = albedo * (light_color * shadow * NoL * rcp_pi + ambient * 0.8);
    vec3 specular = light_color * pow(max0(dot(reflect(-V, normal), light_dir)), 64.0) * 0.2;

    // Glass still transmits the background
    vec3 color = diffuse + specular + background * albedo * 0.35;

    return mix(background, color, alpha);
}

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float dither = interleaved_gradient_noise(gl_FragCoord.xy, float(frameCounter));

    vec3 color = texture(colortex0, uv).rgb;

    float opaque_depth = texture(depthtex1, uv).r;

    // ----- clouds (behind everything translucent) -----
    vec4 clouds = texture(colortex7, uv);
    color = color * clouds.a + clouds.rgb;

    // ----- translucent layer -----
    vec4 extras = texture(colortex9, uv);
    vec4 layer = texture(colortex10, uv);

    if (layer.a > 0.002) {
        float surface_depth = extras.z;
        float flags = extras.w;

        // Only composite when the translucent surface is in front of the
        // opaque depth
        if (surface_depth < opaque_depth) {
            vec3 scene_pos = screen_to_scene_space(vec3(uv, surface_depth));
            vec3 normal = decode_normal_octa(extras.xy);

            // Reject normals that point away from the camera
            if (dot(normal, normalize(-scene_pos)) < 0.0) {
                normal = -normal;
            }

            vec3 albedo = layer.rgb / max(layer.a, 1e-3);
            float alpha = clamp01(layer.a);

            if (flags > 0.5 && flags < 1.5) {
                color = shade_water(scene_pos, normal, albedo, alpha, color, opaque_depth, dither);
            } else if (flags > 3.5) {
                // Weather: just alpha blend the sampled colour
                color = mix(color, albedo, alpha);
            } else {
                color = shade_generic_translucent(scene_pos, normal, albedo, alpha, color, dither);
            }
        }
    }

    // ----- volumetric fog (nearest to the camera) -----
    vec4 fog = texture(colortex6, uv);
    color = color * fog.a + fog.rgb;

    if (isEyeInWater == 1) {
        float distance = depth_to_distance(texture(depthtex0, uv).r);
        color = apply_underwater_absorption(color, distance);
    }

    out_color = vec4(sanitize_color(color), 1.0);
}
