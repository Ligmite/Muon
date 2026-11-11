/*
================================================================================

  Muon Shaders - lib/common/gbuffer_write.glsl
  Version 0.0.1

  Copyright (c) 2026 Keyon Fatemi ("Ligmite"). All rights reserved.
  Part of Muon, distributed under the Muon Proprietary Licence (LICENSE.txt).

--------------------------------------------------------------------------------

  G-buffer encoders. Included by the geometry stages only.

  The geometry stages run in two variants that write the same four targets in
  two different buffers, so the layout is symmetric and a single encoder pair
  serves both:

      opaque      albedo/1  normal/2  surface/3  lightmap/4
      translucent albedo/9  normal/10 surface/11 velocity/8

  No stage writes the scene colour: the deferred lighting pass is the only
  consumer of the g-buffer, which is what keeps lighting equations out of the
  geometry stage.

================================================================================
*/

#ifndef MUON_COMMON_GBUFFER_WRITE_GLSL
#define MUON_COMMON_GBUFFER_WRITE_GLSL

#include "/lib/common/material.glsl"
#include "/lib/common/encoding.glsl"

// -----------------------------------------------------------------------------
//  Lightmap decoding
//  Minecraft stores light levels in a 16x16 lightmap; the vertex attribute is
//  the texel centre, so (coord * 16 - 0.5) / 15 recovers the 0..15 level.
// -----------------------------------------------------------------------------

vec2 muon_decode_lightmap(vec2 lightmap_coord) {
    return muon_saturate((lightmap_coord * 16.0 - 0.5) / 15.0);
}

// -----------------------------------------------------------------------------
//  Opaque targets
// -----------------------------------------------------------------------------

vec4 muon_encode_albedo(MuonMaterial m) {
    return vec4(m.albedo, muon_saturate(muon_luminance(m.f0)));
}

vec4 muon_encode_normal(MuonMaterial m) {
    return vec4(normalize(m.normal), muon_saturate(m.smoothness));
}

vec4 muon_encode_surface(MuonMaterial m, float linear_depth) {
    return vec4(
        linear_depth,
        muon_encode_material(m.id),
        m.emission,
        muon_saturate(m.porosity)
    );
}

vec4 muon_encode_lightmap(MuonMaterial m) {
    return vec4(
        muon_saturate(m.blocklight),
        muon_saturate(m.skylight),
        muon_saturate(m.ao),
        m.flag
    );
}

// -----------------------------------------------------------------------------
//  Translucent targets
//  Normal and surface carry the same meaning; the lightmap target is replaced
//  by the velocity/opacity target because translucent surfaces are shaded
//  against the already-lit opaque image and do not need per-vertex AO.
// -----------------------------------------------------------------------------

vec4 muon_encode_translucent_albedo(MuonMaterial m) {
    return vec4(m.albedo, muon_saturate(muon_luminance(m.f0)));
}

vec4 muon_encode_translucent_normal(MuonMaterial m) {
    return vec4(normalize(m.normal), muon_saturate(m.smoothness));
}

vec4 muon_encode_translucent_surface(MuonMaterial m, float linear_depth) {
    return vec4(
        float(m.id) / 255.0,
        muon_saturate(m.alpha),
        m.emission,
        linear_depth
    );
}

#endif // MUON_COMMON_GBUFFER_WRITE_GLSL
