/*
================================================================================

  Muon Shaders
  lib/shadow.glsl - shadow map projection, bias and filtering

  The shadow map is distorted towards the camera so that a 2048x2048 map stays
  usable over a 160 block radius. Sampling is PCSS: a blocker search estimates
  the penumbra size, then a rotated Poisson PCF resolves the shadow.

================================================================================
*/

#if !defined MUON_SHADOW
#define MUON_SHADOW

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"

const float shadow_map_res = float(shadowMapResolution);
const vec2 shadow_map_texel = vec2(1.0 / shadow_map_res);

// World size of one shadow map texel. The orthographic shadow camera spans
// 2 * shadowDistance blocks.
const float shadow_texel_world = 2.0 * shadowDistance / shadow_map_res;

// ---------------------------------
//   Distortion (camera focus)
// ---------------------------------

// Maps [-1,1] NDC to [0,1] uv while compressing the centre and expanding the
// edges. The same warp is applied when writing and reading, so no inverse is
// needed.
vec2 distort_shadow(vec2 ndc) {
    vec2 p = ndc;
    p += p * abs(p) * 0.32;
    p = clamp(p, -0.999, 0.999);
    return p * 0.5 + 0.5;
}

vec2 undistort_shadow(vec2 uv) {
    // One Newton step is plenty: the warp is monotonic and smooth.
    vec2 p = uv * 2.0 - 1.0;
    for (int i = 0; i < 2; i++) {
        vec2 f = p + p * abs(p) * 0.32 - (uv * 2.0 - 1.0);
        vec2 df = 1.0 + 0.64 * abs(p);
        p -= f / df;
    }
    return p * 0.5 + 0.5;
}

// ---------------------------------
//   Projection into shadow space
// ---------------------------------

vec3 shadow_screen_pos(vec3 scene_pos) {
    vec3 shadow_view = transform(shadowModelView, scene_pos);
    vec3 clip = project_and_divide(shadowProjection, shadow_view);
    return vec3(distort_shadow(clip.xy), clip.z * 0.5 + 0.5);
}

// Normal-offset bias. Pushing along the normal in world space removes almost
// all acne without the peter-panning of a pure depth bias.
vec3 shadow_offset_position(vec3 scene_pos, vec3 normal, float NoL) {
    float slope = sqrt(max0(1.0 - NoL * NoL)) / max(NoL, 0.15);
    float offset = shadow_texel_world * SHADOW_BIAS * (0.35 + 0.65 * slope);
    return scene_pos + normal * offset;
}

// -----------------
//   Raw sampling
// -----------------

float shadow_depth_at(vec2 uv) {
    ivec2 texel = ivec2(clamp(uv, 0.0, 1.0) * shadow_map_res);
    return texelFetch(shadowtex1, texel, 0).r;
}

// Returns 1.0 when lit, 0.0 when fully shadowed
float shadow_hard(vec3 shadow_pos, float bias) {
    return step(shadow_pos.z - bias, shadow_depth_at(shadow_pos.xy));
}

// 2x2 bilinear PCF, cheap and smooth enough for contact shadows
float shadow_bilinear(vec3 shadow_pos, float bias) {
    vec2 uv = shadow_pos.xy * shadow_map_res - 0.5;
    vec2 f = fract(uv);
    vec2 base = (floor(uv) + 0.5) * shadow_map_texel;

    float s00 = step(shadow_pos.z - bias, shadow_depth_at(base));
    float s10 = step(shadow_pos.z - bias, shadow_depth_at(base + vec2(shadow_map_texel.x, 0.0)));
    float s01 = step(shadow_pos.z - bias, shadow_depth_at(base + vec2(0.0, shadow_map_texel.y)));
    float s11 = step(shadow_pos.z - bias, shadow_depth_at(base + shadow_map_texel));

    return mix(mix(s00, s10, f.x), mix(s01, s11, f.x), f.y);
}

// -----------------
//   Poisson disk
// -----------------

vec2 disk_tap(int index, int count, float rotation) {
    float r = sqrt((float(index) + 0.5) / float(count));
    float theta = float(index) * golden_angle + rotation;
    return vec2(cos(theta), sin(theta)) * r;
}

// -----------------
//   PCSS
// -----------------

// Screen-space radius of the penumbra in shadow map texels
float shadow_penumbra_radius(vec3 shadow_pos, float NoL, float dither) {
    float bias = 0.00002 * SHADOW_BIAS;
    float rotation = dither * tau;

    // Blocker search: find the average occluder distance around this texel
    float search_radius = 6.0 * shadow_map_texel.x;
    float blocker_sum = 0.0;
    float blocker_count = 0.0;

    for (int i = 0; i < SHADOW_BLOCKER_SAMPLES; i++) {
        vec2 offset = disk_tap(i, SHADOW_BLOCKER_SAMPLES, rotation) * search_radius;
        float depth = shadow_depth_at(shadow_pos.xy + offset);

        if (depth < shadow_pos.z - bias) {
            blocker_sum += depth;
            blocker_count += 1.0;
        }
    }

    if (blocker_count < 0.5) {
        return 0.0; // fully lit, no penumbra
    }

    float blocker_depth = blocker_sum / blocker_count;
    float distance_to_blocker = max(shadow_pos.z - blocker_depth, 0.0);

    // Sun angular radius ~0.27 degrees -> penumbra grows linearly with occluder
    // distance. The constant converts shadow space depth into world units.
    float penumbra_world = distance_to_blocker * 2.0 * shadowDistance * 0.0125;

    return max(penumbra_world / shadow_texel_world * SHADOW_PENUMBRA_SCALE, 0.5);
}

float shadow_pcss(vec3 scene_pos, vec3 normal, float NoL, float dither) {
    vec3 offset_pos = shadow_offset_position(scene_pos, normal, NoL);
    vec3 shadow_pos = shadow_screen_pos(offset_pos);

    if (shadow_pos.z <= 0.0 || shadow_pos.z >= 1.0) return 1.0;

    // Outside the shadow map: fade to lit
    vec2 edge = abs(shadow_pos.xy * 2.0 - 1.0);
    float edge_fade = 1.0 - smoothstep(0.90, 1.0, max_of(edge));
    if (edge_fade <= 0.0) return 1.0;

    float bias = 0.00003 * SHADOW_BIAS + 0.00002 * NoL;

#ifdef SHADOW_SOFT
    float radius = shadow_penumbra_radius(shadow_pos, NoL, dither);
#else
    float radius = 0.0;
#endif

    float visibility;
    if (radius < 0.75) {
        visibility = shadow_bilinear(shadow_pos, bias);
    } else {
        float rotation = fract(dither * 7.0) * tau;
        float r = min(radius, 24.0);

        float sum = 0.0;
        for (int i = 0; i < SHADOW_SAMPLES; i++) {
            vec2 offset = disk_tap(i, SHADOW_SAMPLES, rotation) * r * shadow_map_texel;
            sum += step(shadow_pos.z - bias, shadow_depth_at(shadow_pos.xy + offset));
        }
        visibility = sum / float(SHADOW_SAMPLES);

        // Blend back to a cheap sample for tiny penumbrae to avoid noise
        float blend = clamp01(radius / 3.0);
        visibility = mix(shadow_bilinear(shadow_pos, bias), visibility, blend);
    }

    return mix(1.0, visibility, edge_fade);
}

// Simple hard shadow for secondary rays and volumetrics
float shadow_sample_fast(vec3 scene_pos, float NoL) {
    vec3 shadow_pos = shadow_screen_pos(scene_pos);

    if (shadow_pos.z <= 0.0 || shadow_pos.z >= 1.0) return 1.0;

    vec2 edge = abs(shadow_pos.xy * 2.0 - 1.0);
    float edge_fade = 1.0 - smoothstep(0.92, 1.0, max_of(edge));
    if (edge_fade <= 0.0) return 1.0;

    float bias = 0.00005 + 0.00008 * (1.0 - NoL);

    return mix(1.0, shadow_hard(shadow_pos, bias), edge_fade);
}

// Sky-light visibility: how open is the sky above this point. Sampled along
// the up vector, cheap and only 3 taps.
float shadow_skylight_visibility(vec3 scene_pos, vec3 normal) {
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 dir = normalize(up + normal * 0.4);

    float sum = 0.0;
    for (int i = 0; i < 3; i++) {
        vec3 offset = scene_pos + dir * (0.4 + float(i) * 0.6);
        sum += shadow_sample_fast(offset, max0(dot(normal, dir)));
    }
    return sum / 3.0;
}

// --------------------------------
//   Screen-space contact shadows
// --------------------------------

// Marches the depth buffer towards the light to catch contact shadows that the
// shadow map is too coarse to resolve.
float contact_shadow(vec3 scene_pos, vec3 light_dir_scene, float dither) {
#if defined SHADOW_SSRT && defined SHADOW
    if (dot(light_dir_scene, vec3(0.0, 1.0, 0.0)) < 0.0) return 1.0;

    const float max_distance = 1.2;
    const float steps = float(SHADOW_SSRT_STEPS);

    float occlusion = 0.0;
    float step_size = max_distance / steps;

    for (int i = 1; i <= SHADOW_SSRT_STEPS; i++) {
        float t = (float(i) + dither) * step_size;
        vec3 pos = scene_pos + light_dir_scene * t;

        vec3 screen = scene_to_screen_space(pos);
        if (any(lessThan(screen.xy, vec2(0.0))) || any(greaterThan(screen.xy, vec2(1.0)))) {
            break;
        }

        float scene_depth = texture(depthtex1, screen.xy).r;
        float sample_depth = screen.z;

        // Behind opaque geometry relative to the ray => occluded
        float diff = scene_depth - sample_depth;
        if (diff > 0.0 && diff < 0.2) {
            float fade = 1.0 - t / max_distance;
            occlusion = max(occlusion, fade);
        }
    }

    return 1.0 - occlusion;
#else
    return 1.0;
#endif
}

#endif // MUON_SHADOW
