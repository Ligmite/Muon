/*
================================================================================

  Muon Shaders - lib/uniforms/frame.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  MuonFrame - the single runtime state block of the renderer.

  Every value that changes once per frame lives in this block. Feature
  libraries receive it as one parameter (or read the single grouped instance)
  and never touch a loose uniform. That discipline is what lets the same GLSL
  become a Vulkan descriptor set or a WGSL bind group with no refactoring:

    * On Iris/OptiFine the block is a plain struct, filled once per invocation
      by muon_frame_build() from the loader-injected uniforms. Iris cannot bind
      a shader-pack-authored UBO, so this adapter is the only portable route.
    * On a native backend (Vitrail's SPIR-V path, or Horizon) the same member
      list is declared as `layout(std140) uniform MuonFrameBlock`. Define
      MUON_NATIVE_UBO and the adapter disappears - no call site changes.

  std140 layout (identical in both modes, every member is 16-byte aligned):

    offset  size  member
    ------  ----  ------------------------------------------------------------
         0   64  view
        64   64  viewInverse
       128   64  projection
       192   64  projectionInverse
       256   64  previousView
       320   64  previousProjection
       384   64  shadowView
       448   64  shadowProjection
       512   16  cameraPositionTime      (xyz position, w frameTime)
       528   16  previousCameraPosition  (xyz position, w frameTimeCounter)
       544   16  viewport                (xy pixels, zw reciprocal)
       560   16  depthParams             (x near, y far, z 1/far, w unused)
       576   16  sunDirection            (xyz unit vector toward sun, w sunAngle)
       592   16  moonDirection           (xyz unit vector toward moon, w moonPhase)
       608   16  lightDirection          (xyz active light, w isEyeInWater)
       624   16  upDirection             (xyz up, w eyeAltitude)
       640   16  weather                 (rain, wetness, thunder, darkness)
       656   16  time                    (frameCounter, worldTime, worldDay, starAngle)
       672   16  climate                 (temperature, rainfall, category, precip)
       688   16  playerState             (skyLight, blockLight, nightVision, blindness)
       704   16  fogColor                (rgb fog colour, w screenBrightness)
       720   16  shadowParams            (texel size, near, far, fade)
       736   16  ambient                 (alphaTestRef, seaLevel, heldLight, unused)
       752   16  skyTint                 (rgb sky colour, w endFlashIntensity)
    ------  ----  ------------------------------------------------------------
    total  768 bytes

================================================================================
*/

#ifndef MUON_UNIFORMS_FRAME_GLSL
#define MUON_UNIFORMS_FRAME_GLSL

#include "/settings.glsl"
#include "/lib/uniforms/iris.glsl"

/*
 * The member list is written exactly once. Both the Iris adapter struct and the
 * native std140 block expand this same macro, which makes layout drift between
 * the two backends impossible.
 */
#define MUON_FRAME_FIELDS                                           \
    mat4 view;                                                      \
    mat4 viewInverse;                                               \
    mat4 projection;                                                \
    mat4 projectionInverse;                                         \
    mat4 previousView;                                              \
    mat4 previousProjection;                                        \
    mat4 shadowView;                                                \
    mat4 shadowProjection;                                          \
    vec4 cameraPositionTime;                                        \
    vec4 previousCameraPosition;                                    \
    vec4 viewport;                                                  \
    vec4 depthParams;                                               \
    vec4 sunDirection;                                              \
    vec4 moonDirection;                                             \
    vec4 lightDirection;                                            \
    vec4 upDirection;                                               \
    vec4 weather;                                                   \
    vec4 time;                                                      \
    vec4 climate;                                                   \
    vec4 playerState;                                               \
    vec4 fogColor;                                                  \
    vec4 shadowParams;                                              \
    vec4 ambient;                                                   \
    vec4 skyTint;

#if defined MUON_NATIVE_UBO

layout(std140) uniform MuonFrameBlock {
    MUON_FRAME_FIELDS
} muonFrame;

#define MUON_FRAME_INIT()

#else

struct MuonFrame {
    MUON_FRAME_FIELDS
};

MuonFrame muonFrame;

MuonFrame muon_frame_build();

#define MUON_FRAME_INIT() muonFrame = muon_frame_build()

#endif // MUON_NATIVE_UBO

// -----------------------------------------------------------------------------
//  Convenience accessors
//  These exist so that call sites read like intent rather than arithmetic.
// -----------------------------------------------------------------------------

vec3 muon_camera_position() {
    return muonFrame.cameraPositionTime.xyz;
}

vec3 muon_previous_camera_position() {
    return muonFrame.previousCameraPosition.xyz;
}

float muon_frame_time() {
    return muonFrame.cameraPositionTime.w;
}

float muon_time_counter() {
    return muonFrame.previousCameraPosition.w;
}

vec2 muon_viewport() {
    return muonFrame.viewport.xy;
}

vec2 muon_inv_viewport() {
    return muonFrame.viewport.zw;
}

float muon_aspect_ratio() {
    return muonFrame.viewport.x / max(muonFrame.viewport.y, 1.0);
}

float muon_near_plane() {
    return muonFrame.depthParams.x;
}

float muon_far_plane() {
    return muonFrame.depthParams.y;
}

vec3 muon_sun_direction() {
    return muonFrame.sunDirection.xyz;
}

vec3 muon_moon_direction() {
    return muonFrame.moonDirection.xyz;
}

vec3 muon_light_direction() {
    return muonFrame.lightDirection.xyz;
}

vec3 muon_up_direction() {
    return muonFrame.upDirection.xyz;
}

float muon_sun_angle() {
    return muonFrame.sunDirection.w;
}

float muon_rain_strength() {
    return muonFrame.weather.x;
}

float muon_wetness() {
    return muonFrame.weather.y;
}

float muon_thunder_strength() {
    return muonFrame.weather.z;
}

float muon_darkness_factor() {
    return muonFrame.weather.w;
}

float muon_world_time() {
    return muonFrame.time.y;
}

float muon_world_day() {
    return muonFrame.time.z;
}

float muon_star_angle() {
    return muonFrame.time.w;
}

float muon_frame_counter() {
    return muonFrame.time.x;
}

float muon_eye_sky_light() {
    return muonFrame.playerState.x;
}

float muon_eye_block_light() {
    return muonFrame.playerState.y;
}

float muon_night_vision() {
    return muonFrame.playerState.z;
}

float muon_blindness() {
    return muonFrame.playerState.w;
}

float muon_eye_altitude() {
    return muonFrame.upDirection.w;
}

float muon_eye_in_water() {
    return muonFrame.lightDirection.w;
}

vec3 muon_fog_color() {
    return muonFrame.fogColor.rgb;
}

float muon_shadow_texel() {
    return muonFrame.shadowParams.x;
}

float muon_shadow_fade() {
    return muonFrame.shadowParams.w;
}

float muon_alpha_test_ref() {
    return muonFrame.ambient.x;
}

float muon_sea_level() {
    return muonFrame.ambient.y;
}

float muon_held_light() {
    return muonFrame.ambient.z;
}

vec3 muon_sky_color() {
    return muonFrame.skyTint.rgb;
}

// -----------------------------------------------------------------------------
//  Space conversions
// -----------------------------------------------------------------------------

vec3 muon_view_to_world_dir(vec3 v) {
    return mat3(muonFrame.viewInverse) * v;
}

vec3 muon_world_to_view_dir(vec3 w) {
    return mat3(muonFrame.view) * w;
}

vec3 muon_world_to_view_pos(vec3 w) {
    return (muonFrame.view * vec4(w, 1.0)).xyz;
}

vec3 muon_view_to_world_pos(vec3 v) {
    return (muonFrame.viewInverse * vec4(v, 1.0)).xyz;
}

/*
 * View-space position from a screen UV and a depth-buffer sample in [0,1].
 * Uses the inverse projection so it stays correct for any projection matrix
 * Minecraft or a mod happens to install.
 */
vec3 muon_view_pos_from_depth(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = muonFrame.projectionInverse * ndc;
    return view.xyz / view.w;
}

vec3 muon_world_pos_from_depth(vec2 uv, float depth) {
    return muon_view_to_world_pos(muon_view_pos_from_depth(uv, depth));
}

/* Positive distance in metres along the view ray. */
float muon_linear_depth(float depth) {
    float n = muonFrame.depthParams.x;
    float f = muonFrame.depthParams.y;
    float ndc = depth * 2.0 - 1.0;
    return (2.0 * n * f) / max(f + n - ndc * (f - n), 1.0e-6);
}

/* True when the sample belongs to the far plane (i.e. no geometry). */
bool muon_is_far_depth(float depth) {
    return depth >= 1.0;
}

/* A cheap sky test that tolerates LOD mods that leave sub-1.0 far depths. */
bool muon_is_sky(vec2 uv, float depth, float linearDistance) {
    return depth >= 1.0 || linearDistance > muonFrame.depthParams.y * 0.999;
}

// -----------------------------------------------------------------------------
//  Iris adapter
// -----------------------------------------------------------------------------

#if !defined MUON_NATIVE_UBO

MuonFrame muon_frame_build() {
    MuonFrame f;

    f.view = gbufferModelView;
    f.viewInverse = gbufferModelViewInverse;
    f.projection = gbufferProjection;
    f.projectionInverse = gbufferProjectionInverse;
    f.previousView = gbufferPreviousModelView;
    f.previousProjection = gbufferPreviousProjection;
    f.shadowView = shadowModelView;
    f.shadowProjection = shadowProjection;

    f.cameraPositionTime = vec4(cameraPosition, frameTime);
    f.previousCameraPosition = vec4(previousCameraPosition, frameTimeCounter);

    float viewW = max(viewWidth, 1.0);
    float viewH = max(viewHeight, 1.0);
    f.viewport = vec4(viewW, viewH, 1.0 / viewW, 1.0 / viewH);

    f.depthParams = vec4(near, far, 1.0 / max(far, 1.0), 0.0);

    vec3 sunView = length(sunPosition) > 1.0e-5
        ? normalize(sunPosition)
        : vec3(0.0, 1.0, 0.0);
    vec3 moonView = length(moonPosition) > 1.0e-5
        ? normalize(moonPosition)
        : vec3(0.0, -1.0, 0.0);

    vec3 sunWorld = normalize(muon_view_to_world_dir(sunView));
    vec3 moonWorld = normalize(muon_view_to_world_dir(moonView));
    vec3 upWorld = normalize(muon_view_to_world_dir(upPosition));

    bool sunlit = sunAngle < 0.5;
    vec3 lightWorld = sunlit ? sunWorld : moonWorld;

    f.sunDirection = vec4(sunWorld, sunAngle);
    f.moonDirection = vec4(moonWorld, float(moonPhase));
    f.lightDirection = vec4(lightWorld, float(isEyeInWater));
    f.upDirection = vec4(upWorld, eyeAltitude);

    f.weather = vec4(rainStrength, wetness, thunderStrength, darknessFactor);
    f.time = vec4(
        float(frameCounter),
        float(worldTime),
        float(worldDay),
        starAngle
    );
    f.climate = vec4(
        temperature,
        rainfall,
        float(biome_category),
        float(biome_precipitation)
    );
    f.playerState = vec4(
        clamp(float(eyeBrightnessSmooth.y) / 240.0, 0.0, 1.0),
        clamp(float(eyeBrightnessSmooth.x) / 240.0, 0.0, 1.0),
        nightVision,
        blindness
    );
    f.fogColor = vec4(fogColor, screenBrightness);

    f.shadowParams = vec4(
        1.0 / float(shadowMapResolution),
        0.0,
        shadowDistance,
        1.0
    );

    f.ambient = vec4(alphaTestRef, float(seaLevel), float(heldBlockLightValue), 0.0);
    f.skyTint = vec4(skyColor, endFlashIntensity);

    return f;
}

#endif // !MUON_NATIVE_UBO

#endif // MUON_UNIFORMS_FRAME_GLSL
