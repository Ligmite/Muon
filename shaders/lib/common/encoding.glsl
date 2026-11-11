/*
================================================================================

  Muon Shaders - lib/common/encoding.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Render-target packing. Data written by the geometry stages and read back by
  the deferred stages goes through exactly these functions, so the g-buffer
  layout is defined in one place and can be mirrored by a native backend.

================================================================================
*/

#ifndef MUON_COMMON_ENCODING_GLSL
#define MUON_COMMON_ENCODING_GLSL

#include "/lib/common/math.glsl"

// -----------------------------------------------------------------------------
//  8-bit pair packing (used by the Voxy g-buffer path and RGBA8 targets)
// -----------------------------------------------------------------------------

float muon_pack_unorm_2x8(float a, float b) {
    return floor(muon_saturate(a) * 255.0 + 0.5) + floor(muon_saturate(b) * 255.0 + 0.5) * 256.0;
}

vec2 muon_unpack_unorm_2x8(float packed) {
    float v = floor(packed * 255.0 + 0.5);
    return vec2(mod(v, 256.0), floor(v / 256.0)) / 255.0;
}

// -----------------------------------------------------------------------------
//  Octahedral normal encoding
//  Two channels instead of three, with an error below 0.4 degrees. Used for
//  velocity / reflection targets where a full RGBA16F normal would be wasteful.
// -----------------------------------------------------------------------------

vec2 muon_octahedral_encode(vec3 n) {
    vec3 a = abs(n);
    float l1 = a.x + a.y + a.z;
    vec3 p = n / max(l1, MUON_EPSILON);
    vec2 octa = p.xy;
    if (p.z < 0.0) {
        vec2 sign_v = vec2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
        octa = (1.0 - abs(p.yx)) * sign_v;
    }
    return octa * 0.5 + 0.5;
}

vec3 muon_octahedral_decode(vec2 e) {
    vec2 f = e * 2.0 - 1.0;
    vec3 n = vec3(f, 1.0 - abs(f.x) - abs(f.y));
    float t = muon_saturate(-n.z);
    n.x += n.x >= 0.0 ? -t : t;
    n.y += n.y >= 0.0 ? -t : t;
    return normalize(n);
}

// -----------------------------------------------------------------------------
//  Quantisation helpers used by the surface target
// -----------------------------------------------------------------------------

/* Material identifiers travel as an 8-bit channel. */
float muon_encode_material(int material) {
    return float(clamp(material, 0, 255)) / 255.0;
}

int muon_decode_material(float encoded) {
    return int(clamp(encoded * 255.0 + 0.5, 0.0, 255.0));
}

/* 8-bit smoothness, which is the precision LabPBR stores in the first place. */
float muon_encode_smoothness(float smoothness) {
    return floor(muon_saturate(smoothness) * 255.0 + 0.5) / 255.0;
}

// -----------------------------------------------------------------------------
//  Depth helpers
// -----------------------------------------------------------------------------

float muon_depth_to_view(float depth, float near_plane, float far_plane) {
    float ndc = depth * 2.0 - 1.0;
    return (2.0 * near_plane * far_plane) / max(far_plane + near_plane - ndc * (far_plane - near_plane), MUON_EPSILON);
}

/*
 * Compares two depth-buffer samples with a tolerance expressed in view-space
 * metres. Working in metres rather than raw depth makes every threshold in the
 * pack independent of the near/far planes.
 */
bool muon_depth_matches(float depth_a, float depth_b, float tolerance_meters, float near_plane, float far_plane) {
    float za = muon_depth_to_view(depth_a, near_plane, far_plane);
    float zb = muon_depth_to_view(depth_b, near_plane, far_plane);
    return abs(za - zb) <= tolerance_meters;
}

float muon_view_to_depth(float view_distance, float near_plane, float far_plane) {
    float ndc = (far_plane + near_plane - (2.0 * near_plane * far_plane) / max(view_distance, MUON_EPSILON))
        / (far_plane - near_plane);
    return ndc * 0.5 + 0.5;
}

// -----------------------------------------------------------------------------
//  Colour target packing
//  The scene colour is HDR and stays linear. Only values that leave the pack
//  (the final pass) are converted to a display transfer function.
// -----------------------------------------------------------------------------

vec4 muon_encode_scene(vec3 color) {
    return vec4(color, 1.0);
}

vec3 muon_decode_scene(vec4 texel) {
    return max(texel.rgb, vec3(0.0));
}

#endif // MUON_COMMON_ENCODING_GLSL
