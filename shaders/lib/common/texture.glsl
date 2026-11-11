/*
================================================================================

  Muon Shaders - lib/common/texture.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  Texture-space material decoding: LabPBR, normal mapping and parallax
  occlusion mapping.

  LabPBR 1.3 channel layout (see lib/common/material.glsl for the shading side):

      _n  normal map, OpenGL convention (+Y up), alpha optionally carries a
          height field that POM can use when the resource pack provides one
      _s  R = F0, G = perceptual smoothness, B = porosity,
          A = 0..254 emissive luminance, 255 = subsurface-scattering material

  Tangent frames are built from screen-space derivatives rather than from a
  vertex attribute. That costs a few instructions but it means every geometry
  source - vanilla terrain, entities, Distant Horizons, Voxy - gets correct
  normal mapping without each of them having to supply tangents.

================================================================================
*/

#ifndef MUON_COMMON_TEXTURE_GLSL
#define MUON_COMMON_TEXTURE_GLSL

#include "/lib/uniforms/settings.glsl"
#include "/lib/common/math.glsl"
#include "/lib/common/color.glsl"
#include "/lib/common/material.glsl"


// -----------------------------------------------------------------------------
//  Tangent frame from derivatives (Schüler's cotangent frame)
// -----------------------------------------------------------------------------

mat3 muon_cotangent_frame(vec3 normal, vec3 position, vec2 uv) {
    vec3 dp1 = dFdx(position);
    vec3 dp2 = dFdy(position);
    vec2 duv1 = dFdx(uv);
    vec2 duv2 = dFdy(uv);

    vec3 dp2perp = cross(dp2, normal);
    vec3 dp1perp = cross(normal, dp1);

    vec3 tangent = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 bitangent = dp2perp * duv1.y + dp1perp * duv2.y;

    float determinant = max(dot(tangent, tangent), dot(bitangent, bitangent));
    if (determinant < 1.0e-12) {
        return muon_tangent_frame(normal);
    }

    float inv_scale = inversesqrt(determinant);
    return mat3(tangent * inv_scale, bitangent * inv_scale, normal);
}

// -----------------------------------------------------------------------------
//  Normal mapping
// -----------------------------------------------------------------------------

vec3 muon_sample_normal_map(vec2 uv) {
    vec3 encoded = texture(normals, uv).xyz * 2.0 - 1.0;
    encoded.xy *= 1.0 - abs(encoded.z);
    return normalize(encoded);
}

vec3 muon_apply_normal_map(vec3 geometric_normal, vec2 uv, vec3 position) {
#if !defined NORMAL_MAPPING
    return geometric_normal;
#else
    /* The tangent frame comes from screen-space derivatives, so it must be
       built in uniform control flow - before any branch that depends on the
       fragment's own texture data. */
    mat3 tbn = muon_cotangent_frame(geometric_normal, position, uv);
    vec3 tangent_normal = muon_sample_normal_map(uv);
    if (dot(tangent_normal, vec3(0.0, 0.0, 1.0)) > 0.9995) {
        return geometric_normal;
    }
    return normalize(tbn * tangent_normal);
#endif
}

// -----------------------------------------------------------------------------
//  LabPBR specular decode
// -----------------------------------------------------------------------------

struct MuonSpecular {
    vec3 f0;
    float smoothness;
    float porosity;
    float emission;
    bool is_sss;
};

MuonSpecular muon_decode_specular(vec2 uv) {
    MuonSpecular result;
    result.f0 = vec3(MUON_HARDCODED_F0);
    result.smoothness = 0.35;
    result.porosity = 0.0;
    result.emission = 0.0;
    result.is_sss = false;

#if defined SPECULAR_MAPPING
    vec4 texel = texture(specular, uv);

    /* An all-zero specular map means "no LabPBR data for this texture": fall
       back to the hardcoded defaults instead of making the block a perfect
       absorber. */
    if (texel.r + texel.g + texel.b + texel.a > 0.002) {
        result.f0 = muon_f0_from_labpbr(texel.r);
        result.smoothness = muon_saturate(texel.g);
        result.porosity = muon_saturate(texel.b);

        float alpha = texel.a * 255.0;
        if (alpha >= 254.5) {
            result.is_sss = true;
        } else {
            result.emission = muon_saturate(alpha / 254.0);
        }
    }
#endif

    return result;
}

// -----------------------------------------------------------------------------
//  Parallax occlusion mapping
// -----------------------------------------------------------------------------

/*
 * Height field lookup. LabPBR does not specify a height channel, so Muon reads
 * the normal map's alpha when it carries data and falls back to the albedo's
 * luminance otherwise. Resource packs that ship a proper height map get sharper
 * depth; packs that do not still get a plausible surface.
 */
float muon_height_sample(vec2 uv, float albedo_luminance) {
    vec4 normal_texel = texture(normals, uv);
    if (normal_texel.a > 0.004 && normal_texel.a < 0.996) {
        return normal_texel.a;
    }
    return albedo_luminance;
}

/*
 * March the view ray through the height field. Returns the offset UV and the
 * number of steps taken, which the self-shadow pass reuses.
 */
vec2 muon_parallax_offset(
    vec2 uv,
    vec3 view_dir_tangent,
    float albedo_luminance,
    float depth_scale,
    out float height
) {
    height = 0.0;
#if !defined PARALLAX
    return uv;
#else
    /* View direction in tangent space, scaled so that grazing angles travel
       further for the same height. */
    vec2 direction = view_dir_tangent.xy / max(abs(view_dir_tangent.z), 0.15);
    float scale = depth_scale * MUON_POM_DEPTH;

    float layer_step = 1.0 / float(MUON_POM_SAMPLES);
    float current_layer = 0.0;
    float current_depth = 1.0;
    vec2 current_uv = uv;

    /* Coarse search. */
    for (int i = 0; i < MUON_POM_SAMPLES; i++) {
        current_depth -= layer_step;
        current_uv = uv - direction * (current_depth * scale);
        float sampled = muon_height_sample(current_uv, albedo_luminance);
        if (sampled >= current_depth) {
            break;
        }
        current_layer = current_depth;
    }

    /* Refine between the last two layers. */
    float previous_depth = current_layer + layer_step;
    float previous_uv_depth = previous_depth;
    for (int i = 0; i < MUON_POM_REFINE_STEPS; i++) {
        float mid = 0.5 * (previous_uv_depth + current_depth);
        vec2 mid_uv = uv - direction * (mid * scale);
        float sampled = muon_height_sample(mid_uv, albedo_luminance);
        if (sampled >= mid) {
            current_depth = mid;
            current_uv = mid_uv;
        } else {
            previous_uv_depth = mid;
        }
    }

    height = current_depth;
    return current_uv;
#endif
}

/*
 * Self-shadowing inside the depth range the parallax march covered. A height
 * sample that rises above the ray towards the light occludes the fragment.
 */
float muon_parallax_shadow(vec2 uv, vec3 light_dir_tangent, float albedo_luminance, float depth_scale, float height) {
#if !defined PARALLAX || !defined POM_SELF_SHADOW
    return 1.0;
#else
    vec2 direction = light_dir_tangent.xy / max(abs(light_dir_tangent.z), 0.15);
    float scale = depth_scale * MUON_POM_DEPTH;

    float occlusion = 0.0;
    float step_size = height / float(MUON_POM_SHADOW_SAMPLES);
    for (int i = 1; i <= MUON_POM_SHADOW_SAMPLES; i++) {
        float sample_height = height - step_size * float(i);
        if (sample_height <= 0.0) {
            break;
        }
        vec2 sample_uv = uv + direction * (sample_height * scale);
        float sampled = muon_height_sample(sample_uv, albedo_luminance);
        if (sampled > sample_height + 0.002) {
            occlusion += 1.0;
        }
    }

    return muon_saturate(1.0 - occlusion / float(MUON_POM_SHADOW_SAMPLES));
#endif
}

#endif // MUON_COMMON_TEXTURE_GLSL
