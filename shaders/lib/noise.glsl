/*
================================================================================

  Muon Shaders
  lib/noise.glsl - procedural noise

  Integer-hash based so results are stable across frames (no sin() precision
  drift). Every function is pure and WGSL-portable.

================================================================================
*/

#if !defined MUON_NOISE
#define MUON_NOISE

#include "/lib/random.glsl"

// ---------------------------------
//   Cheap integer hash primitives
// ---------------------------------

uint hash13u(ivec3 p) {
    uint h = uint(p.x) * 0x8DA6B343u
        ^ uint(p.y) * 0xD8163841u
        ^ uint(p.z) * 0xCB1AB31Fu;
    return pcg(h);
}

float hash13i(ivec3 p) {
    return u01(hash13u(p));
}

vec3 hash33i(ivec3 p) {
    uint h = hash13u(p);
    return vec3(u01(h), u01(pcg(h)), u01(pcg2(h)));
}

float hash12i(ivec2 p) {
    uint h = uint(p.x) * 0x8DA6B343u ^ uint(p.y) * 0xD8163841u;
    return u01(pcg(h));
}

// ---------------------
//   Value noise
// ---------------------

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = p - i;
    vec2 w = cubic_smooth(f);

    ivec2 c = ivec2(i);
    float a = hash12i(c);
    float b = hash12i(c + ivec2(1, 0));
    float d = hash12i(c + ivec2(0, 1));
    float e = hash12i(c + ivec2(1, 1));

    return mix(mix(a, b, w.x), mix(d, e, w.x), w.y);
}

float value_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = p - i;
    vec3 w = cubic_smooth(f);

    ivec3 c = ivec3(i);

    float n000 = hash13i(c);
    float n100 = hash13i(c + ivec3(1, 0, 0));
    float n010 = hash13i(c + ivec3(0, 1, 0));
    float n110 = hash13i(c + ivec3(1, 1, 0));
    float n001 = hash13i(c + ivec3(0, 0, 1));
    float n101 = hash13i(c + ivec3(1, 0, 1));
    float n011 = hash13i(c + ivec3(0, 1, 1));
    float n111 = hash13i(c + ivec3(1, 1, 1));

    float n00 = mix(n000, n100, w.x);
    float n10 = mix(n010, n110, w.x);
    float n01 = mix(n001, n101, w.x);
    float n11 = mix(n011, n111, w.x);

    return mix(mix(n00, n10, w.y), mix(n01, n11, w.y), w.z);
}

// ---------------------
//   Gradient noise
// ---------------------

const vec3 gradient_table[12] = vec3[12](
    vec3(1, 1, 0), vec3(-1, 1, 0), vec3(1, -1, 0), vec3(-1, -1, 0),
    vec3(1, 0, 1), vec3(-1, 0, 1), vec3(1, 0, -1), vec3(-1, 0, -1),
    vec3(0, 1, 1), vec3(0, -1, 1), vec3(0, 1, -1), vec3(0, -1, -1)
);

vec3 gradient_from_hash(uint h) {
    return gradient_table[h % 12u];
}

float gradient_noise(vec3 p) {
    vec3 i = floor(p);
    vec3 f = p - i;
    vec3 w = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);

    ivec3 c = ivec3(i);

    vec3 g000 = gradient_from_hash(hash13u(c));
    vec3 g100 = gradient_from_hash(hash13u(c + ivec3(1, 0, 0)));
    vec3 g010 = gradient_from_hash(hash13u(c + ivec3(0, 1, 0)));
    vec3 g110 = gradient_from_hash(hash13u(c + ivec3(1, 1, 0)));
    vec3 g001 = gradient_from_hash(hash13u(c + ivec3(0, 0, 1)));
    vec3 g101 = gradient_from_hash(hash13u(c + ivec3(1, 0, 1)));
    vec3 g011 = gradient_from_hash(hash13u(c + ivec3(0, 1, 1)));
    vec3 g111 = gradient_from_hash(hash13u(c + ivec3(1, 1, 1)));

    float n000 = dot(g000, f - vec3(0, 0, 0));
    float n100 = dot(g100, f - vec3(1, 0, 0));
    float n010 = dot(g010, f - vec3(0, 1, 0));
    float n110 = dot(g110, f - vec3(1, 1, 0));
    float n001 = dot(g001, f - vec3(0, 0, 1));
    float n101 = dot(g101, f - vec3(1, 0, 1));
    float n011 = dot(g011, f - vec3(0, 1, 1));
    float n111 = dot(g111, f - vec3(1, 1, 1));

    float n00 = mix(n000, n100, w.x);
    float n10 = mix(n010, n110, w.x);
    float n01 = mix(n001, n101, w.x);
    float n11 = mix(n011, n111, w.x);

    return mix(mix(n00, n10, w.y), mix(n01, n11, w.y), w.z) * 0.5 + 0.5;
}

// --------
//   FBM
// --------

float fbm(vec2 p, int octaves) {
    float sum = 0.0;
    float amplitude = 1.0;
    float normalisation = 0.0;

    for (int i = 0; i < octaves; i++) {
        sum += value_noise(p) * amplitude;
        normalisation += amplitude;
        p = p * 2.03 + vec2(17.3, 9.1);
        amplitude *= 0.5;
    }

    return sum / normalisation;
}

float fbm(vec3 p, int octaves) {
    float sum = 0.0;
    float amplitude = 1.0;
    float normalisation = 0.0;

    for (int i = 0; i < octaves; i++) {
        sum += value_noise(p) * amplitude;
        normalisation += amplitude;
        p = p * 2.02 + vec3(17.3, 9.1, 3.7);
        amplitude *= 0.5;
    }

    return sum / normalisation;
}

float fbm_gradient(vec3 p, int octaves) {
    float sum = 0.0;
    float amplitude = 1.0;
    float normalisation = 0.0;

    for (int i = 0; i < octaves; i++) {
        sum += gradient_noise(p) * amplitude;
        normalisation += amplitude;
        p = p * 2.01 + vec3(11.7, 5.3, 7.9);
        amplitude *= 0.5;
    }

    return sum / normalisation;
}

// Ridged multifractal - used for cirrus streaks and cloud anvils
float ridged_fbm(vec3 p, int octaves) {
    float sum = 0.0;
    float amplitude = 1.0;
    float normalisation = 0.0;

    for (int i = 0; i < octaves; i++) {
        float n = 1.0 - abs(value_noise(p) * 2.0 - 1.0);
        sum += n * n * amplitude;
        normalisation += amplitude;
        p = p * 2.07 + vec3(5.1, 13.7, 21.3);
        amplitude *= 0.5;
    }

    return sum / normalisation;
}

float turbulence(vec3 p, int octaves) {
    float sum = 0.0;
    float amplitude = 1.0;
    float normalisation = 0.0;

    for (int i = 0; i < octaves; i++) {
        sum += abs(value_noise(p) * 2.0 - 1.0) * amplitude;
        normalisation += amplitude;
        p = p * 2.05 + vec3(3.3, 7.7, 1.9);
        amplitude *= 0.5;
    }

    return sum / normalisation;
}

// ------------
//   Worley
// ------------

// F1 distance to the nearest feature point, in [0, ~1]
float worley(vec3 p) {
    ivec3 i = ivec3(floor(p));
    vec3 f = p - vec3(i);

    float min_dist = 1e9;

    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec3 offset = vec3(x, y, z);
                vec3 feature = hash33i(i + ivec3(offset));
                vec3 d = offset + feature - f;
                min_dist = min(min_dist, dot(d, d));
            }
        }
    }

    return sqrt(min_dist);
}

// F2 - F1 gives nice cell edges
vec2 worley_f1_f2(vec3 p) {
    ivec3 i = ivec3(floor(p));
    vec3 f = p - vec3(i);

    float d1 = 1e9;
    float d2 = 1e9;

    for (int z = -1; z <= 1; z++) {
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec3 offset = vec3(x, y, z);
                vec3 feature = hash33i(i + ivec3(offset));
                vec3 d = offset + feature - f;
                float dist = dot(d, d);
                if (dist < d1) {
                    d2 = d1;
                    d1 = dist;
                } else if (dist < d2) {
                    d2 = dist;
                }
            }
        }
    }

    return sqrt(vec2(d1, d2));
}

// Animated Worley used for cloud erosion
float worley_fbm(vec3 p, int octaves) {
    float sum = 0.0;
    float amplitude = 1.0;
    float normalisation = 0.0;

    for (int i = 0; i < octaves; i++) {
        sum += worley(p) * amplitude;
        normalisation += amplitude;
        p = p * 2.11 + vec3(3.1, 8.3, 5.7);
        amplitude *= 0.5;
    }

    return sum / normalisation;
}

// ----------------------
//   Curl (for smoke)
// ----------------------

vec3 curl_noise(vec3 p) {
    const float e = 0.1;

    float n1 = value_noise(p + vec3(0.0, e, 0.0)) - value_noise(p - vec3(0.0, e, 0.0));
    float n2 = value_noise(p + vec3(0.0, 0.0, e)) - value_noise(p - vec3(0.0, 0.0, e));

    float n3 = value_noise(p + vec3(0.0, 0.0, e)) - value_noise(p - vec3(0.0, 0.0, e));
    float n4 = value_noise(p + vec3(e, 0.0, 0.0)) - value_noise(p - vec3(e, 0.0, 0.0));

    float n5 = value_noise(p + vec3(e, 0.0, 0.0)) - value_noise(p - vec3(e, 0.0, 0.0));
    float n6 = value_noise(p + vec3(0.0, e, 0.0)) - value_noise(p - vec3(0.0, e, 0.0));

    vec3 curl = vec3(n1 - n2, n3 - n4, n5 - n6) / (2.0 * e);
    return curl * 0.5 + 0.5;
}

// --------------------
//   Cellular water
// --------------------

// Value noise with a "caustic" style cell pattern, cheap approximation of
// refracted sunlight. Returns [0, 1].
float caustic_noise(vec2 p, float time) {
    vec2 i = floor(p);
    vec2 f = p - i;

    float min_dist = 8.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(x, y);
            vec2 feature = hash22(i + offset);
            feature = 0.5 + 0.5 * sin(time + tau * feature);
            vec2 d = offset + feature - f;
            min_dist = min(min_dist, dot(d, d));
        }
    }

    float c = 1.0 - clamp01(sqrt(min_dist) * 1.6);
    return c * c * c;
}

#endif // MUON_NOISE
