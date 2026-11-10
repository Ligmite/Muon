/*
================================================================================

  Muon Shaders
  lib/common.glsl - constants, macros, small math helpers

  This file is the root of the include graph. Everything that is shared
  between stages lives here or includes it.

================================================================================
*/

#if !defined MUON_COMMON
#define MUON_COMMON

#include "/settings.glsl"

// ----------------
//   Capabilities
// ----------------

// Iris defines IS_IRIS. We use it to gate features that OptiFine cannot do.
#if defined IS_IRIS
#define MUON_IRIS
#endif

#if defined DISTANT_HORIZONS || defined VOXY
#define MUON_LOD_MOD
#endif

// Voxy ships its own DH emulation; prefer Voxy when both are present.
#if defined VOXY && defined DISTANT_HORIZONS
#undef DISTANT_HORIZONS
#endif

// MC_VERSION is provided by the loader. 1.17 renamed gtexture -> tex. Iris uses
// gtexture for every supported version, OptiFine swaps the name based on
// version, so only remap for very old OptiFine.
#if defined MC_VERSION && MC_VERSION < 11700 && !defined MUON_IRIS
#define gtexture tex
#endif

// -----------
//   Constants
// -----------

const float pi = 3.141592653589793;
const float tau = 6.283185307179586;
const float half_pi = 1.570796326794897;
const float rcp_pi = 0.318309886183791;
const float rcp_tau = 0.159154943091895;
const float e = 2.718281828459045;
const float golden_ratio = 1.618033988749895;
const float eps = 1e-6;
const float sqrt2 = 1.414213562373095;
const float sqrt3 = 1.732050807568877;

// Vanilla hand depth in screen space. Anything closer than this belongs to the
// hand and uses a different projection range.
const float hand_depth = 0.56;

// -------------------
//   Numeric helpers
// -------------------

#define rcp(x) (1.0 / (x))
#define clamp01(x) clamp(x, 0.0, 1.0)
#define max0(x) max(x, 0.0)
#define min1(x) min(x, 1.0)
#define saturate(x) clamp01(x)

float sqr(float x) { return x * x; }
vec2  sqr(vec2 x) { return x * x; }
vec3  sqr(vec3 x) { return x * x; }
vec4  sqr(vec4 x) { return x * x; }

float cube(float x) { return x * x * x; }
vec3  cube(vec3 x) { return x * x * x; }

float pow4(float x) { return sqr(sqr(x)); }
float pow5(float x) { return pow4(x) * x; }
vec3  pow5(vec3 x) { return pow4(x) * x; }

float max_of(vec2 v) { return max(v.x, v.y); }
float max_of(vec3 v) { return max(v.x, max(v.y, v.z)); }
float max_of(vec4 v) { return max(v.x, max(v.y, max(v.z, v.w))); }

float min_of(vec2 v) { return min(v.x, v.y); }
float min_of(vec3 v) { return min(v.x, min(v.y, v.z)); }
float min_of(vec4 v) { return min(v.x, min(v.y, min(v.z, v.w))); }

float length_squared(vec2 v) { return dot(v, v); }
float length_squared(vec3 v) { return dot(v, v); }
float length_squared(vec4 v) { return dot(v, v); }

vec2 normalize_safe(vec2 v) { return dot(v, v) < eps ? vec2(0.0) : normalize(v); }
vec3 normalize_safe(vec3 v) { return dot(v, v) < eps ? vec3(0.0) : normalize(v); }

// Division that returns 0 instead of NaN/Inf for a zero denominator
float safe_div(float a, float b) { return b > eps ? a / b : 0.0; }
vec3  safe_div(vec3 a, float b) { return b > eps ? a / b : vec3(0.0); }

// 1 for x >= 0, -1 otherwise
float sign_nonzero(float x) { return x < 0.0 ? -1.0 : 1.0; }
vec3 sign_nonzero(vec3 x) { return vec3(sign_nonzero(x.x), sign_nonzero(x.y), sign_nonzero(x.z)); }

// Luminance of a linear RGB triple (Rec. 709)
float luma(vec3 rgb) { return dot(rgb, vec3(0.2126, 0.7152, 0.0722)); }

// Perceptual luminance for tonemapping / eye adaptation
float luminance(vec3 rgb) { return luma(max(rgb, vec3(0.0))); }

// --------------
//   Remapping
// --------------

float linear_step(float edge0, float edge1, float x) {
    return clamp01((x - edge0) / (edge1 - edge0));
}

vec2 linear_step(vec2 edge0, vec2 edge1, vec2 x) {
    return clamp01((x - edge0) / (edge1 - edge0));
}

vec3 linear_step(vec3 edge0, vec3 edge1, vec3 x) {
    return clamp01((x - edge0) / (edge1 - edge0));
}

float linear_step_unclamped(float edge0, float edge1, float x) {
    return (x - edge0) / (edge1 - edge0);
}

float remap(float x, float in_min, float in_max, float out_min, float out_max) {
    return out_min + (x - in_min) * (out_max - out_min) / (in_max - in_min);
}

// Cubic Hermite with zero derivative at 0 and 1 (same curve as smoothstep)
float cubic_smooth(float x) { return sqr(x) * (3.0 - 2.0 * x); }
vec2  cubic_smooth(vec2 x) { return sqr(x) * (3.0 - 2.0 * x); }
vec3  cubic_smooth(vec3 x) { return sqr(x) * (3.0 - 2.0 * x); }

// Zero first AND second derivative at the endpoints
float quintic_smooth(float x) { return cube(x) * (x * (x * 6.0 - 15.0) + 10.0); }

// Signal shaping on [0, 1] similar to sqrt()
float dampen(float x) { x = clamp01(x); return x * (2.0 - x); }

// amount > 0 lifts, amount < 0 increases contrast
float lift(float x, float amount) { return (x + x * amount) / (1.0 + x * amount); }
vec3  lift(vec3 x, float amount) { return (x + x * amount) / (1.0 + x * amount); }

// 1 inside center +/- 0.5 * width, smoothly falling to 0 at the edges
float pulse(float x, float center, float width) {
    x = abs(x - center) / width;
    return x > 1.0 ? 0.0 : 1.0 - cubic_smooth(x);
}

// Same, but periodic (hue wheels, angles)
float pulse(float x, float center, float width, const float period) {
    x = (x - center + 0.5 * period) / period;
    x = fract(x) * period - 0.5 * period;
    return pulse(x, 0.0, width);
}

// Exponential impulse, rises quickly then decays
float impulse(float x, float peak) {
    float h = peak * x;
    return h * exp(1.0 - h);
}

// --------------
//   Matrices
// --------------

vec3 transform(mat4 m, vec3 pos) { return mat3(m) * pos + m[3].xyz; }

vec4 project(mat4 m, vec3 pos) {
    return vec4(m[0].x, m[1].y, m[2].zw) * pos.xyzz + m[3];
}

vec3 project_and_divide(mat4 m, vec3 pos) {
    vec4 h = project(m, pos);
    return h.xyz / h.w;
}

vec3 project_ortho(mat4 m, vec3 pos) {
    return vec3(m[0].x, m[1].y, m[2].z) * pos + m[3].xyz;
}

vec2 diagonal(mat2 m) { return vec2(m[0].x, m[1].y); }
vec3 diagonal(mat3 m) { return vec3(m[0].x, m[1].y, m[2].z); }
vec4 diagonal(mat4 m) { return vec4(m[0].x, m[1].y, m[2].z, m[3].w); }

// Orthonormal basis around n (Duff et al. 2017)
void build_basis(vec3 n, out vec3 t, out vec3 b) {
    float s = n.z >= 0.0 ? 1.0 : -1.0;
    float a = -1.0 / (s + n.z);
    float c = n.x * n.y * a;
    t = vec3(1.0 + s * n.x * n.x * a, s * c, -s * n.x);
    b = vec3(c, s + n.y * n.y * a, -n.y);
}

// -----------------
//   Radians/deg
// -----------------

#define radians_f(x) ((x) * (pi / 180.0))
#define degrees_f(x) ((x) * (180.0 / pi))

// -----------------
//   HDR output
// -----------------

// The HDR mod (rrtt217) injects these macros/uniforms. When HDR is active the
// final color is encoded into the display transfer function scaled by the
// paper-white/UI brightness ratio; the mod expands the framebuffer to the real
// peak brightness. This matches the convention used by Photon's HDR fork.
#if defined HDR_MOD_INSTALLED && defined HDR_ENABLED
uniform float HdrGamePeakBrightness;
uniform float HdrGamePaperWhiteBrightness;
uniform float HdrGameMinimumBrightness;
uniform float HdrUIBrightness;

#define MUON_HDR_OUTPUT
#endif

#endif // MUON_COMMON
