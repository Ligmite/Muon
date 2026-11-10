# Changelog

All notable changes to Muon are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the
project uses the iteration scheme described in `docs/ITERATIONS.md`.

## [1.0.0] - "Ion"

First complete release.

### Added

**Pipeline**
- Deferred renderer with 17 passes: shadow, gbuffers, 5 deferred passes,
  7 composite passes, final.
- Explicit `RENDERTARGETS` / `layout(location)` outputs on every pass, so the
  pack is portable to non-GL backends.
- Half-resolution AO, volumetric and cloud buffers with depth-aware upsampling.
- Persistent history buffers for TAA and the path tracer.

**Lighting**
- Physically based shading: GGX specular with height-correlated Smith
  visibility, multi-scatter energy compensation, split-sum environment BRDF.
- labPBR resource pack support (smoothness, F0 with conductor heuristic,
  emission, porosity/SSS), plus a legacy specular mode and a no-pack mode with
  hand-tuned vanilla materials.
- Normal mapping, and parallax occlusion mapping with self-shadowing and
  distance fade.
- PCSS soft shadows with blocker search, rotated Poisson PCF, normal-offset
  bias and a distortion that concentrates shadow resolution near the player.
- Screen-space contact shadows.
- Cloud shadows on terrain.
- GTAO (horizon based) and SSAO, with an ambient-only occlusion option.
- Subsurface scattering for foliage, flowers, cloth and snow; cloth sheen.
- Rain puddles and general wet-surface darkening driven by `wetness`.
- Handheld light.

**Sky and atmosphere**
- Rayleigh + Mie + ozone single-scattering atmosphere with multiple-scattering
  approximation.
- Sun disc with limb darkening; moon disc with eight phases and procedural
  craters.
- Stars with twinkle, Milky Way, aurora curtains, rainbows.
- Weather blending (overcast, desaturation, rain dimming).
- Separate Nether and End skies.

**Clouds**
- Four independent volumetric layers: cumulus, cumulus congestus,
  altocumulus, cirrus.
- Beer-Lambert + powder + three-octave multiple scattering lighting with
  configurable light steps.
- Shared coverage field driven by weather; wind direction and speed.
- Optional classic flat cloud layer.

**Volumetrics**
- Half-resolution raymarched fog with exponential height falloff, rain
  multiplier, cave fog and a border term.
- Shadow-map light shafts with dithered visibility and HG phase.
- Underwater medium switch.

**Water**
- Analytic wave normals and matching vertex displacement.
- Rain ripples, refraction, Beer-Lambert absorption, scattering, caustics,
  edge foam, SSR and sun specular.
- Underwater absorption for the camera.

**Ray tracing**
- Screen-space path tracer with three modes (reflections, reflections + GI,
  full path tracing).
- Next-event estimation to the sun with soft shadow cone, cosine/GGX lobe
  selection, Russian roulette.
- Temporal accumulation with motion vectors and disocclusion rejection.
- Edge-stopping bilateral denoiser.

**Post processing**
- TAA with Catmull-Rom history and neighbourhood clipping.
- FXAA and contrast-adaptive sharpening.
- 13-tap bloom with soft knee.
- Depth of field with foreground rejection; motion blur.
- Auto exposure from a fixed luminance grid, or manual.
- Five tonemappers, with Muon Filmic as the default.
- Warm vibrant grade: white balance, contrast, vibrance, hue-selective
  orange/teal/green boosts, split toning, clarity, black level, Purkinje shift.
- Vignette, chromatic aberration, film grain.

**Output**
- Fully linear Rec.709 working space with a single display transform.
- Native HDR output through rrtt217's HDR mod.

**Compatibility**
- Distant Horizons: `dh_terrain`, `dh_water`, `dh_generic`, combined depth,
  LoD position reconstruction everywhere it matters.
- Voxy: `voxy_opaque.glsl`, `voxy_translucent.glsl`, `voxy.json`
  (experimental).
- Designed for Vitrail's Vulkan backend (no compute, no image load/store,
  explicit render targets).

**Tooling**
- `tools/validate.py`: preprocessor, include resolution, undefined-function and
  argument-count checks, delimiter balance, entry-point checks, settings and
  translation consistency.
- `tools/gen_programs.py`, `tools/gen_lang.py`, `tools/generate_noise.py`.
- `tools/build.py`: release zip plus per-iteration archive with a manifest.
- GitHub Actions workflow that validates and builds on tag.

### Known issues
- In-game visual validation is still pending for this build.
- OptiFine is unsupported (history buffers and per-program blending need Iris).
- No coloured voxel lighting yet.
- DH/Voxy LoD geometry does not cast shadows.

[1.0.0]: https://github.com/example/muon/releases/tag/v1.0.0
