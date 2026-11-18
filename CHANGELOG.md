# Changelog

All notable changes to Muon are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) with a `0.x` series
that is expected to break compatibility between minor releases.

Every release is frozen into `archive/<version>/` beside the repository and is
never modified afterwards. Build output goes to `release/`, which is never
committed.

---

## [0.1.2] — 2026-11-12

### Fixed

- **Water did not render on a coast.** The translucent test required the
  front-most depth to be nearer than the far plane, added to screen out stale
  data at sky pixels. Over deep ocean the seabed is past render distance, so the
  opaque depth is the far plane and every water pixel failed the test. The marker
  is now written by the sky pass as well as the opaque pass, so it is current
  everywhere and the depth test could be removed entirely.
- Debug view 9 now shows translucent opacity rather than the opaque material
  channel. The old view displayed the terrain behind the water, which is correct
  behaviour and therefore useless for diagnosing water.

## [0.1.1] — 2026-11-12

### Fixed

- **Clouds are disabled by default.** Their density field is sampled too coarsely
  at Minecraft view distances, which produced speckle in the sky; the cloud
  shadow march projects the same field onto the ground, which produced the
  diagonal banding across sand and stone. Both symptoms were one feature that is
  not yet good enough to ship enabled.
- **Shadow bias was below one shadow-map texel.** At 160 m over 2048 texels a
  texel is 0.078 m, while the normal offset was 0.055 m - so flat ground
  self-shadowed in bands. Normal bias is now 0.20 m, depth bias 0.0015, and the
  penumbra cap dropped from 22 to 10 texels so the blocker search stops reaching
  surfaces that are not occluded.

## [0.1.0] — 2026-11-12

Stability release. The previous builds traded correctness for features; this one
makes the image calm first.

### Changed

- **Sub-pixel jitter is now opt-in** (`TAA_JITTER`, off by default). A jitter the
  resolve cannot average away is not anti-aliasing, it is a visible camera
  shake. TAA still blends, so stochastic noise is still reduced.
- **Sampling patterns no longer vary with time.** The interleaved gradient noise
  carried a frame-counter term, so PCSS taps, GTAO slices, cloud dither and SSR
  rays all re-rolled every frame. That was the flicker. Static patterns are
  slightly structured and completely stable.
- **Clouds are analytic.** A 64-cubed volume sampled without filtering renders as
  scattered cubes, which is what appeared in the sky. The baked volumes remain in
  the pack but are no longer sampled.
- **Auto exposure is off by default.** A camera that re-exposes while the player
  looks around reads as "the lighting keeps changing". Fixed exposure is
  predictable; adaptation remains available as an option.
- Water carries a share of its body colour on top of the extinction model, so a
  shallow pond reads as water rather than as bare ground.

## [0.0.2] — 2026-11-11

First build that renders a complete frame. Everything below was found by loading
the pack in Minecraft 26.3 with Iris 1.11.7 and is fixed in this release.

### Fixed

- Forward reference: the cloud density accessor called `muon_value_noise_3d`
  before it was declared, which failed to compile.
- Translucent detection no longer depends on depth. Minecraft's translucent
  layer does not write depth, so the depth comparison could never fire and water
  was never shaded. Opaque geometry now clears a marker in `colortex11.g` and
  translucent geometry sets it, so the flag is always current for the frame.
- Cloud shape falls back to analytic noise when the 3D volume reads as a
  constant. An unbound volume sampler returns a constant, and a constant density
  field renders as a solid disc across the sky rather than as no clouds.
- The sun flare requires the sun to be near the centre of the screen instead of
  merely on screen.
- Auto exposure is much stiffer: range halved to +/-0.5 stops, speed reduced, and
  a couple of degrees of view tilt no longer re-exposes the frame.

### Tooling

- The validator no longer reads `return foo(...)` as a declaration of `foo`. That
  hole is what let the forward reference above reach the game with a clean
  report; `tools/validate.py` now fails on it, verified by removing the fix and
  re-running.

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

### Fixed during pre-release testing

- **The depth buffers were used the wrong way round.** `depthtex0` contains all
  geometry and `depthtex1` contains opaque geometry only; Muon had them swapped,
  so the "is there a translucent surface here" test could never be true and water
  was never shaded at all. Every pass now samples `depthtex1` for the opaque
  surface and `deferred2` uses both correctly.
- The sun glow used a falloff broad enough to add several units of radiance
  across the whole frame, which read as glare even with the sun off screen. The
  core is now tight and the halo small; the flare and god-ray strengths are
  lower and the god-ray phase term is scaled as a distribution rather than a
  radiance.
- Auto exposure: centre-weighted metering, a lower metering ceiling, slower
  adaptation and a narrower usable range. Looking at the sky no longer swings
  the exposure of the whole frame.
- TAA did not account for the change in sub-pixel jitter between frames when it
  reprojected the history, so it averaged two different alignments. That is the
  distant-texture shimmer that survived after the flips were removed.
- Screen-space reflections are gated on roughness; tracing sharp reflections for
  grass produced bright streaks.
- **The chain no longer uses buffer flipping.** `composite3` read and wrote the
  TAA history in the same pass, which requires a flip; with the flip in place the
  history came back unreliable, so the temporal filter never converged and the
  image both jittered and flickered. Every pass now reads and writes different
  targets: the scene ping-pongs between `colortex0` and `colortex15`, the
  history is written by a dedicated copy pass (`composite4`), and the exposure
  state travels in the alpha channel of the velocity target.
- The AgX minimum fit lifts midtones hard at Muon's exposure key and read as
  washed out; ACES is now the default tonemap (AgX remains selectable).
- The Mie phase was limited with a hard `min()`, which flattened the glow into a
  disc with a sharp edge - the "huge white circle" seen when looking at the sun.
  It now saturates smoothly, and the sun disc itself is dimmer.
- Parallax occlusion mapping invented a height field from the albedo when the
  resource pack supplied none. On vanilla textures that erupted into the
  speckle artifacts across grass and sand. POM now requires a real height
  channel and is skipped entirely otherwise; its self-shadow term is wired in.
- **Every derived direction in `MuonFrame` was computed from uninitialised
  memory.** `muon_frame_build()` converted the sun, moon and up vectors with
  `muon_view_to_world_dir()`, a helper that reads the global `muonFrame` — the
  very struct the builder was still constructing. `sunDirection` therefore came
  out as a zero vector, the sun transmittance integrated along a zero-length
  direction returned zero, and with it went the sky, all direct sunlight, the
  clouds, the moon, the stars and every water reflection. Only `muon_sky_ambient`
  survived, because it passes an explicit world-up direction rather than the sun
  vector. That is why the world rendered ambient-lit and the sky and water were
  pure black.
- Duplicate `colortex*` sampler declarations rejected by the NVIDIA front end
  (C1038). Every sampler is now declared exactly once, centrally.
- `seaLevel` and `heldBlockLightValue` declared as `float` while Iris supplies
  integers, which made Iris silently disable them.
- `dhMaterialId` declared by the pack although Iris' Distant Horizons
  integration injects it into every `dh_*` program.
- The depth-of-field pass was gated on `DEPTH_OF_FIELD`, but it also carries the
  TAA result from `colortex0` to `colortex15`. With DoF off — the High default —
  the bloom passes read the pre-TAA image and overwrote the resolve, which is
  what produced constant jitter and flicker.
- Exposure metering sampled a few pixels near the centre of the screen instead of
  each texel's whole screen tile, and had no upper bound. The sun disc and its
  Mie glow (radiance in the hundreds) then set the exposure for the frame and
  crushed everything else to black.
- The Mie phase function and the god-ray term are now bounded; a physical phase
  diverges at the solar limb and is not a usable HDR quantity.
- Cloud shadows marched upward from the top of the cloud layer instead of
  through it, so they never produced a shadow.
- TAA reprojection omitted the camera translation delta, so motion vectors were
  only correct while the player stood still.

### Known limitations

- RTGI/PTGI are **screen-space** path tracing. Off-screen geometry is replaced by
  the analytic sky; there is no world-space voxel tracer yet.
- Iris exposes one hardware shadow map per frame, so the second shadow cascade is
  screen-space rather than a second hardware cascade.
- Translucent surfaces are single-layer: only the nearest translucent fragment
  per pixel is stored.
- Hardware-ray-tracing hooks and HDR display output are roadmap items, not
  present in this version.
