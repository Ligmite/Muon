/*
================================================================================

  Muon Shaders
  lib/encoding.glsl - g-buffer packing

  G-buffer layout (all full resolution):

    colortex1 (RGBA16)
      rgb = albedo, linear
      a   = material id / 255

    colortex2 (RGBA16)
      rg  = octahedral normal
      b   = roughness (perceptual)
      a   = metalness

    colortex3 (RGBA16)
      r = emission (Reinhard-compressed)
      g = subsurface / translucency
      b = vanilla ambient occlusion
      a = f0 (0 = dielectric default, 1 = full metal)

    colortex9 (RGBA16) - translucent extras
      rg  = octahedral normal
      b   = alpha
      a   = flags (water = 1, ice = 2, glass = 3)

    colortex10 (RGBA16F) - translucent layer colour (premultiplied)

================================================================================
*/

#if !defined MUON_ENCODING
#define MUON_ENCODING

#include "/lib/common.glsl"
#include "/lib/space.glsl"

// ---------------------
//   Octahedral normal
// ---------------------

vec2 encode_normal_octa(vec3 n) {
    n /= max(abs(n.x) + abs(n.y) + abs(n.z), eps);

    vec2 octa = n.z >= 0.0
        ? n.xy
        : (1.0 - abs(n.yx)) * vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);

    return octa * 0.5 + 0.5;
}

vec3 decode_normal_octa(vec2 e) {
    vec2 octa = e * 2.0 - 1.0;
    vec3 n = vec3(octa, 1.0 - abs(octa.x) - abs(octa.y));

    float t = max(-n.z, 0.0);
    n.x += n.x >= 0.0 ? -t : t;
    n.y += n.y >= 0.0 ? -t : t;

    return normalize(n);
}

// -----------------
//   2x8 packing
// -----------------

float pack_unorm_2x8(float a, float b) {
    return (floor(clamp01(a) * 255.0) + floor(clamp01(b) * 255.0) * 256.0) / 65535.0;
}

vec2 unpack_unorm_2x8(float packed) {
    float v = packed * 65535.0;
    return vec2(mod(v, 256.0), floor(v / 256.0)) / 255.0;
}

// -----------------
//   Range packing
// -----------------

// Bounded storage for unbounded (emissive) values
float pack_reinhard(float x) { return x / (1.0 + x); }
float unpack_reinhard(float x) { return x / max(1.0 - x, 1e-4); }

// ---------------
//   G-buffer IO
// ---------------

vec4 pack_gbuffer_0(vec3 albedo, uint material_id) {
    return vec4(clamp(albedo, 0.0, 1.0), float(material_id) / 255.0);
}

void unpack_gbuffer_0(vec4 data, out vec3 albedo, out uint material_id) {
    albedo = data.rgb;
    material_id = uint(data.a * 255.0 + 0.5);
}

vec4 pack_gbuffer_1(vec3 normal, float roughness, float metalness) {
    return vec4(
        encode_normal_octa(normal),
        clamp01(roughness),
        clamp01(metalness)
    );
}

void unpack_gbuffer_1(vec4 data, out vec3 normal, out float roughness, out float metalness) {
    normal = decode_normal_octa(data.xy);
    roughness = data.z;
    metalness = data.w;
}

vec4 pack_gbuffer_2(float emission, float sss, float ao, float f0) {
    return vec4(
        pack_reinhard(max0(emission)),
        clamp01(sss),
        clamp01(ao),
        clamp01(f0)
    );
}

void unpack_gbuffer_2(vec4 data, out float emission, out float sss, out float ao, out float f0) {
    emission = unpack_reinhard(clamp01(data.r));
    sss = data.g;
    ao = data.b;
    f0 = data.a;
}

// Translucent layer encoding
vec4 pack_translucent_extras(vec3 normal, float alpha, float flags) {
    return vec4(encode_normal_octa(normal), clamp01(alpha), clamp01(flags));
}

void unpack_translucent_extras(vec4 data, out vec3 normal, out float alpha, out float flags) {
    normal = decode_normal_octa(data.xy);
    alpha = data.z;
    flags = data.w;
}

// ---------------
//   Depth
// ---------------

// Combined depth: returns the nearest of the vanilla opaque depth and the LoD
// (Distant Horizons / Voxy) depth. Returns 1.0 when nothing was drawn.
float combined_depth(vec2 uv) {
    float depth = texture(depthtex1, uv).r;

#ifdef DISTANT_HORIZONS
    if (depth >= 1.0) {
        float dh_depth = texture(dhDepthTex0, uv).r;
        if (dh_depth < 1.0) return dh_depth;
    }
#endif

    return depth;
}

// True when the depth came from the LoD mod
bool is_lod_depth(vec2 uv, float depth) {
#ifdef DISTANT_HORIZONS
    return depth >= 1.0 && texture(dhDepthTex0, uv).r < 1.0;
#else
    return false;
#endif
}

#endif // MUON_ENCODING
