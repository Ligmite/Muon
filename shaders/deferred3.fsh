#version 400 compatibility
/*
================================================================================

  Muon Shaders
  deferred3.fsh - ray tracing / path tracing accumulation

  Outputs rgb = accumulated radiance, a = normalised history length.
  RENDERTARGETS: 8

  Reads the previous frame's accumulated result from colortex12. deferred4
  copies colortex8 back into colortex12 so the history survives exactly one
  frame (Iris does not allow feedback in a single pass).

================================================================================
*/

#include "/lib/uniforms.glsl"
#include "/lib/space.glsl"
#include "/lib/random.glsl"
#include "/lib/encoding.glsl"
#include "/lib/gbuffer.glsl"
#include "/lib/pathtracing.glsl"
#include "/lib/denoise.glsl"

layout(location = 0) out vec4 out_rt;

/* RENDERTARGETS: 8 */

uniform sampler2D colortex12; // previous frame RT
// colortex8 is the render target of this pass and must not be bound as a sampler

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

#if RAY_TRACING == 0
    out_rt = vec4(0.0);
#else
    float depth;
    SurfaceData surface = load_surface(uv, depth);

    if (depth >= 1.0) {
        out_rt = vec4(0.0);
        return;
    }

    // A few samples per pixel per frame, jittered with blue noise
    vec3 radiance = vec3(0.0);
    float confidence = 0.0;

    const int samples = RT_SAMPLES_PER_PIXEL;

    for (int i = 0; i < RT_SAMPLES_PER_PIXEL; i++) {
        vec4 noise = blue_noise_sample(pixel, frameCounter * 8 + i);
        float dither = noise.x;

        PathResult path = trace_path(surface, dither, RAY_TRACING);
        radiance += path.radiance;
        confidence += path.confidence;
    }

    radiance /= float(samples);
    confidence /= float(samples);

    radiance = sanitize_color(radiance);

#ifdef RT_TEMPORAL_ACCUMULATION
    vec3 motion = motion_vector(surface.scene_pos);
    vec2 history_uv = uv - motion.xy;

    vec4 history = vec4(0.0);

    if (all(greaterThan(history_uv, vec2(0.0))) && all(lessThan(history_uv, vec2(1.0)))) {
        history = texture(colortex12, history_uv);
    }

    float history_depth = texture(depthtex1, clamp(history_uv, 0.0, 1.0)).r;
    vec3 history_normal = gbuffer_normal(clamp(history_uv, 0.0, 1.0));

    float history_length = history.a * float(RT_ACCUMULATION_LIMIT);

    TemporalResult temporal = temporal_filter(
        radiance,
        history.rgb,
        depth,
        history_depth,
        surface.normal,
        history_normal,
        history_length
    );

    out_rt = vec4(temporal.color, temporal.history_length / float(RT_ACCUMULATION_LIMIT));
#else
    out_rt = vec4(radiance, 1.0);
#endif
#endif
}
