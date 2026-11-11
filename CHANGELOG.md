# Changelog

All notable changes to Muon are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) with a `0.x` series
that is expected to break compatibility between minor releases.

Every release is frozen into `archive/<version>/` beside the repository and is
never modified afterwards. Build output goes to `release/`, which is never
committed.

---

## [0.0.1] — 2026-11-11

First release. Not yet feature-complete against the long-term roadmap, but a
complete, coherent renderer.

### Added

**Pipeline**

- Deferred renderer with a single surface-lighting implementation
  (`lib/common/surface.glsl`) shared by opaque geometry, glass and water.
- Sixteen-colour-target g-buffer layout, documented in `docs/buffers.md`.
- Separate translucent g-buffer so the deferred stage can light the surface
  behind water before the water pass refracts it.
- `MuonFrame` runtime state block: one std140-shaped struct, shared definition
  for the Iris adapter path and the future native UBO path.
- `lib/uniforms/settings.glsl`: compile-time options exposed as `const` values,
  the specialisation-constant analogue for a SPIR-V backend.

**Atmosphere**

- Rayleigh + Mie + ozone single-scattering atmosphere with sunset extinction.
- Fast analytic sky-ambient path for surface lighting.
- Volumetric fog with per-sample shadow-map occlusion and rain/cave density.
- Screen-space god rays with depth-based occlusion.
- Multi-layer volumetric clouds (cumulus + cirrus) from a baked Perlin-Worley
  volume with Worley erosion and six-step self-shadowing.
- Weather coupling of cloud coverage, thickness, density and wind.
- Cloud shadows projected from the same density field.

**Lighting**

- Two-tier cascaded shadowing: hardware PCSS cascade plus a screen-space
  ray-marched cascade for distance coverage.
- GTAO with bent-normal output, and SSAO as a cheaper alternative.
- Subsurface scattering for foliage: analytic transmission plus a screen-space
  gather.
- Cloud shadowing, block-light falloff and a bounce-light approximation.

**Surfaces**

- LabPBR 1.3 decode: F0, perceptual smoothness, porosity, emissive, SSS flag.
- Parallax occlusion mapping with binary refinement and self-shadowing.
- Screen-space reflections with roughness jitter, hit refinement, thickness
  rejection and edge fade.
- Weather-driven wetness, puddles with animated ripple normals, and snow cover.

**Water**

- Gerstner vertex displacement with a higher-frequency analytic normal.
- Snell's-law refraction with a depth-aware offset clamp.
- Beer-Lambert extinction and scattering.
- Animated caustics with depth fading.
- Fresnel-weighted sky and screen-space reflections.

**Post**

- TAA with reprojected velocity buffers and YCoCg variance clipping.
- AgX, ACES and Reinhard tonemapping in linear colour.
- Dynamic exposure with separate brighten/darken time constants.
- Mip-pyramid bloom with a soft-knee bright pass.
- Thin-lens depth of field with autofocus.
- Depth-tested lens flare with ghosts and a halo.
- Grading, vignette, CAS-style sharpening, film grain, dithering.
- FXAA as an alternative to TAA.

**Mod integration**

- Distant Horizons `dh_terrain` / `dh_water` programs.
- Voxy `voxy.json`, `voxy_opaque.glsl`, `voxy_translucent.glsl`.

**Tooling**

- `tools/validate.py`: static pack validator (includes, preprocessing, ordering,
  stage pairing, uniform conflicts, RENDERTARGETS, options, presets, textures).
- `tools/gen_wrappers.py`: generates all 92 program entry points from a manifest.
- `tools/gen_noise.py`: generates the 2D noise texture and both 3D noise volumes.
- `tools/package.py`, `build.ps1`, `build.sh`: reproducible release packaging.

### Known limitations

- RTGI/PTGI are **screen-space** path tracing. Off-screen geometry is replaced by
  the analytic sky; there is no world-space voxel tracer yet.
- Iris exposes one hardware shadow map per frame, so the second shadow cascade is
  screen-space rather than a second hardware cascade.
- Translucent surfaces are single-layer: only the nearest translucent fragment
  per pixel is stored.
- Hardware-ray-tracing hooks and HDR display output are roadmap items, not
  present in this version.
