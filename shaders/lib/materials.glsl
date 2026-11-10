/*
================================================================================

  Muon Shaders
  lib/materials.glsl - material ids and surface property assignment

  Material ids come from block.properties (mc_Entity.x) and from the entity /
  item id lists. Everything here is data driven and easy to extend.

================================================================================
*/

#if !defined MUON_MATERIALS
#define MUON_MATERIALS

#include "/lib/common.glsl"
#include "/lib/uniforms.glsl"
#include "/lib/noise.glsl"

// -----------------
//   Material ids
// -----------------

const uint MAT_GENERIC        = 0u;
const uint MAT_GRASS          = 1u;
const uint MAT_LEAVES         = 2u;
const uint MAT_WATER          = 3u;
const uint MAT_GLASS          = 4u;
const uint MAT_METAL          = 5u;
const uint MAT_STONE          = 6u;
const uint MAT_WOOD           = 7u;
const uint MAT_SAND           = 8u;
const uint MAT_DIRT           = 9u;
const uint MAT_SNOW           = 10u;
const uint MAT_ICE            = 11u;
const uint MAT_EMISSIVE       = 12u;
const uint MAT_LAVA           = 13u;
const uint MAT_UNDERWATER     = 14u;
const uint MAT_CLOTH          = 15u;
const uint MAT_FLOWER         = 16u;
const uint MAT_VINE           = 17u;
const uint MAT_NETHER         = 18u;
const uint MAT_END            = 19u;
const uint MAT_COPPER         = 20u;

// block.properties id -> Muon material id
uint material_from_block_id(int block_id) {
    switch (block_id) {
        case 1:  return MAT_GRASS;
        case 2:  return MAT_LEAVES;
        case 3:  return MAT_WATER;
        case 4:  return MAT_GLASS;
        case 5:  return MAT_METAL;
        case 6:  return MAT_STONE;
        case 7:  return MAT_WOOD;
        case 8:  return MAT_SAND;
        case 9:  return MAT_DIRT;
        case 10: return MAT_SNOW;
        case 11: return MAT_ICE;
        case 12: return MAT_EMISSIVE;
        case 13: return MAT_LAVA;
        case 14: return MAT_UNDERWATER;
        case 15: return MAT_CLOTH;
        case 16: return MAT_FLOWER;
        case 17: return MAT_VINE;
        case 18: return MAT_NETHER;
        case 19: return MAT_END;
        case 20: return MAT_COPPER;
        default: return MAT_GENERIC;
    }
}

bool is_foliage(uint id) {
    return id == MAT_GRASS || id == MAT_LEAVES || id == MAT_FLOWER
        || id == MAT_VINE || id == MAT_UNDERWATER;
}

bool is_plant(uint id) {
    return id == MAT_GRASS || id == MAT_FLOWER || id == MAT_VINE;
}

bool is_metal(uint id) {
    return id == MAT_METAL || id == MAT_COPPER;
}

bool is_water(uint id) {
    return id == MAT_WATER;
}

// ------------------
//   Material data
// ------------------

struct MaterialData {
    float roughness;   // perceptual roughness [0, 1]
    float f0;          // dielectric reflectance at normal incidence
    float metalness;   // 0 = dielectric, 1 = conductor
    float emission;    // scene-referred emission scale
    float sss;         // subsurface / translucency amount
    float wave;        // vertex wave strength
    float porosity;    // labPBR porosity, drives rain wetness
};

MaterialData default_material_data(uint id) {
    MaterialData m;
    m.roughness = 0.65;
    m.f0 = 0.04;
    m.metalness = 0.0;
    m.emission = 0.0;
    m.sss = 0.0;
    m.wave = 0.0;
    m.porosity = 0.5;

    if (id == MAT_GRASS) {
        m.roughness = 0.80;
        m.wave = 0.35;
        m.sss = 0.25;
        m.porosity = 0.8;
    } else if (id == MAT_LEAVES) {
        m.roughness = 0.60;
        m.wave = 0.55;
        m.sss = 0.65;
        m.porosity = 0.9;
    } else if (id == MAT_FLOWER) {
        m.roughness = 0.70;
        m.wave = 1.00;
        m.sss = 0.45;
        m.porosity = 0.9;
    } else if (id == MAT_VINE) {
        m.roughness = 0.65;
        m.wave = 0.70;
        m.sss = 0.55;
        m.porosity = 0.9;
    } else if (id == MAT_WOOD) {
        m.roughness = 0.75;
        m.porosity = 0.7;
    } else if (id == MAT_STONE) {
        m.roughness = 0.72;
        m.porosity = 0.2;
    } else if (id == MAT_SAND) {
        m.roughness = 0.85;
        m.porosity = 0.85;
    } else if (id == MAT_DIRT) {
        m.roughness = 0.90;
        m.porosity = 0.9;
    } else if (id == MAT_SNOW) {
        m.roughness = 0.55;
        m.sss = 0.5;
        m.porosity = 0.3;
    } else if (id == MAT_ICE) {
        m.roughness = 0.12;
        m.sss = 0.8;
        m.porosity = 0.0;
    } else if (id == MAT_GLASS) {
        m.roughness = 0.05;
        m.porosity = 0.0;
    } else if (id == MAT_WATER) {
        m.roughness = 0.02;
        m.f0 = 0.02;
        m.sss = 0.35;
        m.porosity = 0.0;
    } else if (id == MAT_METAL) {
        m.roughness = 0.25;
        m.f0 = 0.95;
        m.metalness = 1.0;
        m.porosity = 0.0;
    } else if (id == MAT_COPPER) {
        m.roughness = 0.35;
        m.f0 = 0.85;
        m.metalness = 1.0;
        m.porosity = 0.1;
    } else if (id == MAT_CLOTH) {
        m.roughness = 0.95;
        m.sss = 0.35;
        m.porosity = 0.8;
    } else if (id == MAT_EMISSIVE) {
        m.roughness = 0.40;
        m.emission = 4.0;
    } else if (id == MAT_LAVA) {
        m.roughness = 0.30;
        m.emission = 3.0;
    } else if (id == MAT_NETHER) {
        m.roughness = 0.80;
        m.porosity = 0.3;
    } else if (id == MAT_END) {
        m.roughness = 0.50;
        m.porosity = 0.2;
    } else if (id == MAT_UNDERWATER) {
        m.roughness = 0.40;
        m.sss = 0.7;
        m.wave = 0.6;
    }

    return m;
}

// ---------------------------------
//   Resource pack (labPBR / oldPBR)
// ---------------------------------

// Decodes the specular texture into (roughness, f0, emission, sss/porosity).
// labPBR 1.3:
//   r = perceptual smoothness     -> roughness = 1 - r
//   g = F0, linear = (g/255)^2    -> > 0.9 is treated as a conductor
//   b = emission (scaled)
//   a = porosity / subsurface
void decode_specular(
    vec4 texture_data,
    inout MaterialData material
) {
#if RESOURCEPACK_SUPPORT == 2
    float smoothness = texture_data.r;
    float f0_raw = texture_data.g;
    float emission_raw = texture_data.b;
    float porosity = texture_data.a;

    material.roughness = 1.0 - smoothness;
    material.f0 = sqr(f0_raw);

    // labPBR defines F0 >= 0.9 (229/255) as "hardcoded metal" territory
    float metal_mask = smoothstep(0.80, 0.95, f0_raw);
    material.metalness = max(material.metalness, metal_mask);

    material.emission = emission_raw > 0.001
        ? pow(emission_raw, 2.2) * 12.0
        : 0.0;

    material.porosity = porosity;
    material.sss = max(material.sss, porosity * 0.5);
#elif RESOURCEPACK_SUPPORT == 1
    // Legacy specular map: r = roughness, g = metalness
    material.roughness = texture_data.r;
    material.metalness = texture_data.g > 0.5 ? 1.0 : 0.0;
    material.f0 = mix(0.04, 0.9, material.metalness);
#endif
}

// Nudges dielectrics towards physically plausible values
void sanitize_material(inout MaterialData material, uint id) {
    material.roughness = clamp(material.roughness, 0.02, 1.0);
    material.f0 = clamp(material.f0, 0.0, 1.0);

    if (material.metalness < 0.5 && material.f0 > 0.16) {
        // A dielectric can't reflect 30% at normal incidence. Anything higher
        // is either a metal or a very shiny gem.
        material.f0 = 0.16;
    }

    if (id == MAT_METAL || id == MAT_COPPER) {
        material.metalness = 1.0;
    }
}

// ---------------------------------
//   Hardcoded material overrides
// ---------------------------------

// Vanilla textures have no specular map. These give the important blocks a
// hand-tuned look so the pack is usable without a PBR resource pack.
void apply_hardcoded_materials(
    uint id,
    vec3 albedo,
    vec3 world_normal,
    inout MaterialData material
) {
#ifdef HARDCODED_SPECULAR
    if (is_metal(id)) {
        material.metalness = 1.0;
        material.f0 = id == MAT_COPPER ? 0.82 : 0.95;
        material.roughness = min(material.roughness, 0.32);
    }

    if (id == MAT_WATER) {
        material.f0 = 0.02;
        material.roughness = 0.02;
    }

    if (id == MAT_SNOW) {
        material.roughness = min(material.roughness, 0.45);
    }

    if (id == MAT_GLASS || id == MAT_ICE) {
        material.roughness = min(material.roughness, 0.10);
    }
#endif

#ifdef HARDCODED_EMISSION
    if (id == MAT_EMISSIVE) {
        material.emission = max(material.emission, 3.5);
    }

    if (id == MAT_LAVA) {
        material.emission = max(material.emission, 2.5);
    }

    // Glowing berries / amethyst / sculk get a slight emission from their colour
    float glow = clamp01((albedo.r + albedo.b) * 0.5 - albedo.g * 0.5 - 0.25);
    material.emission = max(material.emission, glow * 0.4);
#endif

#ifdef HARDCODED_SSS
    if (is_foliage(id)) {
        material.sss = max(material.sss, 0.5);
    }
#endif
}

// ---------------------------------
//   Vertex waving
// --------------------------------

// Wind displacement for plants and leaves. `pos` is scene space, `top` is true
// for the top vertices of a cross-model plant.
vec3 apply_wave(
    vec3 scene_pos,
    vec3 world_pos,
    float top_vertex,
    float block_light,
    uint material_id
) {
#if defined WAVING_PLANTS || defined WAVING_LEAVES
    MaterialData material = default_material_data(material_id);
    float wave = material.wave;

    // Vanilla light level suppress wind in still air? No - but it lets us
    // cheaply vary the phase per block so a field of grass is not in lockstep.
    float phase = dot(world_pos.xz, vec2(0.37, 0.29));

    float wind = sin(frameTimeCounter * 1.7 + phase) * 0.5
        + sin(frameTimeCounter * 2.9 + phase * 1.7) * 0.25
        + sin(frameTimeCounter * 0.7 + phase * 0.4) * 0.25;

    float strength = wave * top_vertex * WIND_STRENGTH;
    strength *= (0.35 + 0.65 * rainStrength);

    vec3 offset = vec3(
        wind * strength,
        -abs(wind) * strength * 0.25,
        cos(frameTimeCounter * 1.3 + phase * 2.1) * strength * 0.6
    );

    return scene_pos + offset;
#else
    return scene_pos;
#endif
}

#endif // MUON_MATERIALS
