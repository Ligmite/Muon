<div align="center">

# Muon Shaders

**v0.0.1 — warm, vibrant, clear, cinematic.**

A proprietary Minecraft shader pack for **Iris** (OpenGL), built to also run on
**Vitrail** (Vulkan), with first-class **Distant Horizons** and **Voxy** support.


</div>

---

## What Muon is

Muon is a deferred PBR renderer for Minecraft. The geometry stages write a
g-buffer and nothing else; a single shading pass owns every lighting equation in
the pack. That structure is what allows it to offer volumetric clouds, PCSS
shadows, screen-space reflections and a path tracer without the lighting model
drifting apart between passes.

The look is deliberately *not* hazy. Fog density is authored low by default, the
atmosphere model is tuned so that the horizon stays legible rather than milky,
and the grade adds warmth and separation without lifting the black point. The
intent is a photograph of a clear day, not a dream sequence.

| | |
|---|---|
| **Minecraft** | 26.3 |
| **Tested with** | Iris `1.11.7+mc26.3`, Sodium `0.9.2`, Distant Horizons `3.3.4-26.3` |
| **Also targets** | Vitrail `0.12.0-beta+mc26.3` (Iris shaders on Vulkan) |
| **Shader format** | Iris / OptiFine pack format, GLSL 3.30 compatibility profile |
| **Default preset** | **High** |

---

## Highlights of v0.0.1

### Atmosphere, clouds and volumetrics

- **Multi-layer volumetric clouds** raymarched through a baked Perlin-Worley
  volume, with a separate high-altitude cirrus layer, height-dependent coverage,
  Worley erosion of the edges, dual-lobe Henyey-Greenstein phase, and a six-step
  self-shadowing march.
- **Weather coupling**: coverage, thickness, density and wind all move with
  `rainStrength` and `thunderStrength`, so a clear cumulus field closes over into
  a storm deck without a second cloud model.
- **Rayleigh + Mie + ozone atmosphere** with correct horizon reddening, sunset
  extinction, night-side ambient, and a separate fast ambient path for surfaces
  so lighting does not pay for the sky.
- **Screen-space god rays** marched radially toward the sun using the depth
  buffer as an occluder test, so shafts bend around terrain instead of being
  painted over it.
- **Volumetric fog** with a height-exponential medium, per-sample shadow-map
  occlusion, rain and cave density terms, and a 12–32 step count driven by the
  quality preset.
- **Cloud shadows** projected from the same density field that draws the sky.

### Shadows and occlusion

- **Two-tier cascaded shadowing.** Tier 0 is the hardware shadow map with
  percentage-closer soft shadows — a real blocker search drives a penumbra radius
  with contact hardening. Tier 1 is a screen-space ray-marched cascade that
  extends shadows past the hardware map and fades in seamlessly, which is what
  keeps Distant Horizons geometry from popping out of shadow.
- **GTAO** (horizon-based, cosine-weighted, with a bent normal output) and
  **SSAO** as a lower-cost alternative, both at half resolution with a
  depth-aware upsample.
- **Subsurface scattering** for leaves and foliage: an analytic thin-surface
  transmission term plus a screen-space gather that softens dense canopy, both
  driven by LabPBR porosity.

### Post-processing

- **TAA with velocity buffers.** Velocities come from reprojection through the
  previous frame's matrices, with sub-pixel R2 jitter applied in every geometry
  vertex shader. History is validated by variance clipping in YCoCg space, which
  is what prevents ghosting on fast-moving entities — a pack never receives
  per-entity previous transforms, so clipping is the mechanism that actually
  solves the problem.
- **AgX and ACES tonemapping** in strictly linear colour, applied once, in the
  final pass, before the sRGB transfer function. Nothing is graded in display
  space until after the transfer function, and nothing is tonemapped twice.
- **Mip-pyramid bloom** with a soft-knee bright pass: two passes total, with a
  falloff wider than any fixed-tap blur.
- **Thin-lens depth of field** with autofocus, golden-angle gather and a
  depth-aware tap weight that stops sharp foreground objects from haloing.
- **Lens flare** with depth-tested sun visibility, a ghost train and a halo ring.

### Surfaces and water

- **Full LabPBR 1.3**: `_n` normal maps with a height channel, `_s` carrying F0,
  perceptual smoothness, porosity and emissive luminance, with the 255 = SSS
  convention.
- **Parallax occlusion mapping** with a coarse march, a binary refinement and
  self-shadowing inside the displaced height field.
- **Screen-space reflections** with roughness-jittered rays, binary hit
  refinement, thickness rejection, edge fade and an analytic sky fallback.
- **Gerstner water**, displaced in the vertex shader and analytically re-evaluated
  at higher frequency for the surface normal, with Snell's-law refraction,
  Beer-Lambert extinction, depth-faded caustics and Fresnel-weighted reflections.
- **Weather-driven wetness**: rain darkens and polishes exposed surfaces, fills
  puddles in low noise minima, and adds animated ripple normals; snow accumulates
  on upward faces with the biome's precipitation type.

### Ray tracing

- **Screen-space path tracer** for the `Raytraced`, `RTGI` and `PTGI` presets:
  cosine-weighted hemisphere rays traced against the depth buffer, sampling the
  lit image for the first bounce and the previous frame's indirect field for
  later bounces, with a bilateral denoiser and temporal accumulation through the
  normal TAA pipeline.

  > **Honest scope note.** This is a *screen-space* path tracer, not hardware ray
  > tracing and not a world-space voxel tracer. Rays that leave the screen fall
  > back to the analytic sky, which keeps the image stable instead of punching
  > holes in it. A world-space voxel/HRR tracer is on the roadmap for a later
  > version; `lib/common/raytrace.glsl` is written so that the gathering stage can
  > be swapped for a world-space hit test without touching the passes that call
  > it.

---

## Presets

Muon ships seven presets, in this order, defaulting to **High**:

| # | Preset | What it enables |
|---|---|---|
| 1 | **Low** | SSAO, PCF shadows at 1024/96 m, no clouds or volumetrics, FXAA, no reflections |
| 2 | **Medium** | GTAO, PCSS at 2048/128 m, volumetric clouds and fog, god rays, SSR, TAA, bloom |
| 3 | **High** *(default)* | Medium plus SSS, screen-space shadow cascade at 2048/160 m, no DoF |
| 4 | **Ultra** | High plus DoF, caustics, 4096 shadow map, 256 m shadows |
| 5 | **Raytraced** | Ultra plus 1-bounce screen-space GI and reflections |
| 6 | **RTGI** | 2-bounce GI, wider gather radius, higher sample count |
| 7 | **PTGI** | 3-bounce GI, 32-step rays, 320 m shadow distance |

Presets only set what differs from **High**, and `shaders/settings.glsl` is
authored so that its defaults *are* the High preset — a fresh install is already
on High without anything being applied.

---

## Repository layout

The repository is self-contained. Build artefacts are written **beside** it, so a
clone never carries generated files:

```
workspace/
├── Muon/                     ← the repository (this folder)
├── release/                  ← build output: Muon-v0.0.1.zip
└── archive/                  ← frozen past releases: v0.0.1/
```

Inside the repository:

```
Muon/
├── LICENSE.txt               authoritative proprietary licence
├── LICENSE.md                the same terms, with explanatory notes
├── README.md                 this file
├── CHANGELOG.md              release history
├── version.json              machine-readable version and target matrix
├── build.ps1 / build.sh      packaging scripts (produce ../release/Muon-v0.0.1.zip)
├── docs/                     architecture, buffers, options, compatibility
├── tools/
│   ├── validate.py           static pack validator (run it before every release)
│   ├── gen_wrappers.py       generates the per-program entry points
│   ├── gen_noise.py          generates the noise assets
│   └── package.py            shared packaging implementation
└── shaders/
    ├── shaders.properties    every menu option, profile and render target
    ├── settings.glsl         every user option (the single source of truth)
    ├── block.properties      material classification for the geometry stage
    ├── lang/                 menu translations
    ├── voxy.json             Voxy integration contract
    ├── voxy_opaque.glsl      Voxy LOD fragment emitters
    ├── voxy_translucent.glsl
    ├── image/                generated noise assets
    ├── lib/                  the renderer: math, BRDFs, features, UBOs
    └── program/              the passes
```

The `.vsh` / `.fsh` files in `shaders/` are five-line entry points generated by
`tools/gen_wrappers.py`; the implementations live in `shaders/program/`. That
split means one implementation can serve several Iris program slots (terrain,
entities, block entities and the hand all share `gbuffers_solid`).

---

## Building and installing

There is nothing to compile: a shader pack is a zip of the `shaders/` directory.

```powershell
# Windows
./build.ps1                # -> ../release/Muon-v0.0.1.zip
./build.ps1 -Archive       # also freeze a copy into ../archive/v0.0.1/

# Linux / macOS
./build.sh
./build.sh --archive
```

The output root defaults to the directory containing the repository. Override it
with the `MUON_OUTPUT_ROOT` environment variable if you want the artefacts
somewhere else (CI points it at the checkout).

Then copy `release/Muon-v0.0.1.zip` into `.minecraft/shaderpacks/` and select it
in **Options → Video Settings → Shader Packs**.

Manual install: copy the whole `shaders/` folder into a zip named
`Muon-v0.0.1.zip`. Do **not** zip the repository root — the zip must contain
`shaders/` at its top level.

### Verifying a checkout

```bash
python tools/validate.py        # static analysis of all 92 shader files
python tools/gen_wrappers.py --check
```

`validate.py` is not a GLSL compiler. It resolves every `#include`, runs the
preprocessor, and then checks the failure modes a shader pack actually has:
functions used before declaration, undeclared calls, unbalanced braces, fragment
inputs with no matching vertex output, uniforms declared twice with different
types, passes with outputs but no `RENDERTARGETS`, options referenced by the menu
that do not exist, missing presets, wrong preset order, placeholder markers, and
textures whose dimensions do not match their declared byte size. It also
evaluates the `#if` graph under the default preset, so a block of code that only
compiles in a preset nobody selected still gets checked.

---

## Compatibility

### Iris (OpenGL) — native target

Tested against Iris `1.11.7+mc26.3`. Muon uses only the standard shader pack API:
`layout(location)` outputs with `RENDERTARGETS`, `#include`, `size.buffer`,
`flip.*`, `colortexNFormat` and the per-program blend overrides. No custom images,
no SSBOs, no compute shaders — so it runs on any Iris build that supports the
modern pack format.

### Vitrail (Vulkan)

Vitrail runs Iris shader packs through a SPIR-V/WGSL translation. Muon is written
to survive that translation:

- every program declares `#version 330 compatibility` explicitly;
- legacy built-ins (`gl_Vertex`, `gl_NormalMatrix`, `gl_TextureMatrix`,
  `gl_MultiTexCoord*`) are used exactly where the API requires them and nowhere
  else;
- no vendor extensions, no `#extension` directives, no compute shaders;
- all user options are compile-time constants, so a backend that translates once
  per configuration gets identical results;
- the runtime state block is a single std140-shaped struct, which maps one-to-one
  onto a Vulkan descriptor set (see below).

### Distant Horizons

Muon ships `dh_terrain` and `dh_water` programs, so LOD terrain writes the same
g-buffer as vanilla chunks and is lit, shadowed, fogged and temporally filtered
identically. `dhDepthTex`/`dhProjection` are available to the pack if a future
version needs a combined depth buffer; v0.0.1 does not need them because LOD
geometry contributes real g-buffer data.

### Voxy

`shaders/voxy.json` declares the draw buffers, blending, uniforms and samplers
Voxy's generated programs may use, and `voxy_opaque.glsl` /
`voxy_translucent.glsl` implement `voxy_emitFragment()`. Voxy LODs therefore enter
the same deferred chain as everything else, including the water model.

---

## Architecture

Full detail in [docs/architecture.md](docs/architecture.md); the short version:

```
shadow              hardware shadow map (depth, alpha-tested foliage)
gbuffers_*          opaque g-buffer        -> 1,2,3,4
gbuffers_water      translucent g-buffer   -> 9,10,11
deferred            GTAO                   -> 14 (half res)
deferred1           lighting, sky, clouds  -> 0
deferred2           water, volumetrics     -> 0   (flip)
composite           exposure               -> 12  (64x64, flip)
composite1          SSR + path-traced GI   -> 13, 7 (flip)
composite2          indirect + god rays, velocity -> 15, 8
composite3          TAA                    -> 0, 5 (flip)
composite4          depth of field         -> 15
composite5          bloom bright pass      -> 6   (mip chain)
composite6          bloom upsample         -> 0
final               tonemap, grade, sRGB   -> screen
```

Four design rules make it hold together:

1. **One lighting implementation.** `lib/common/surface.glsl` is the only place a
   BRDF is evaluated for a surface. Opaque geometry, glass and water all call it.
2. **The opaque g-buffer is never overwritten.** Translucents write their own
   targets, which is what lets the deferred stage light the surface *behind*
   water so the water pass can refract an already-lit image.
3. **Physics lives in libraries, not passes.** Gerstner waves, the cloud density
   field, GTAO's horizon search, the PCSS penumbra model, the tonemap curves and
   the noise functions are each defined once, in `lib/`, and are free of any
   loader-specific boilerplate.
4. **Strict type discipline.** No implicit int/float mixing, no `vec3(0)`
   shortcuts, explicit casts everywhere. The same source is intended to survive
   a WGSL translation, where implicit conversions do not exist.

### The uniform discipline

Iris cannot bind a shader-pack-authored uniform buffer — it injects individual
uniforms. Muon therefore does the next best thing, and the thing that is actually
portable:

```glsl
// lib/uniforms/frame.glsl
#define MUON_FRAME_FIELDS \
    mat4 view;            \
    mat4 viewInverse;     \
    ...                   \
    vec4 weather;         \
    vec4 time;

#if defined MUON_NATIVE_UBO
layout(std140) uniform MuonFrameBlock { MUON_FRAME_FIELDS } muonFrame;
#else
struct MuonFrame { MUON_FRAME_FIELDS };
MuonFrame muonFrame;
#endif
```

The member list is written once and shared by both paths. On Iris it becomes a
struct filled by `muon_frame_build()`; on a native backend the same text becomes
a real `layout(std140)` block. The byte offsets are documented in the header and
in [docs/buffers.md](docs/buffers.md) (768 bytes, every member 16-byte aligned),
so a descriptor set can be built against it without re-deriving anything.

Compile-time user options take the other half of the same idea: they are `const`
values in `lib/uniforms/settings.glsl`, which is the GLSL analogue of a SPIR-V
specialisation constant, not of a UBO. Toggling an option recompiles the pack on
Iris; on a native backend it re-specialises the pipeline.

---

## Usage terms (summary)

- ✅ Use Muon, including in monetised videos and streams, **with credit**.
- ✅ Modify it for personal use.
- ✅ Read and learn from the source.
- ✅ Include it in a modpack, commercial or not, **with the notice preserved**.
- ❌ Redistribute Muon or derivatives on creator-monetised platforms (Modrinth,
  CurseForge) without written permission.
- ❌ Sell copies of Muon or of derivative works.

The full terms are in [LICENSE.txt](LICENSE.txt). Where these bullets and the
licence disagree, the licence governs.

---

## Roadmap

| Version | Focus |
|---|---|
| **0.0.1** | The pack described above. Iris-native, Vitrail-compatible, DH + Voxy integrated. |
| 0.0.x | Bug fixes from in-game testing; performance passes on the shadow and volumetric chains. |
| 0.1.0 | HDR output path (Iris colour-space pathway, PQ/HLG aware final pass), expanded debug views. |
| 0.2.0 | World-space voxel/HRR tracer behind the existing RTGI interface; hardware-ray-tracing hooks where a backend exposes them. |
| later | Horizon (WGSL / Rust) backend: the `lib/` layer is already free of OpenGL. |

---

## Credits and references

Muon is an independent implementation. Its techniques were studied from
published material and from the following packs, **without copying code**:

- **Photon** by SixthSurge — studied for volumetric cloud structure, atmosphere
  parameterisation and the Iris program conventions used by modern packs.
- **SEUS PTGI HRR 3** by Sonic Ether — studied for the structure of a screen-space
  path tracer (ray generation, bounce accumulation, hit validation).
- The **LabPBR 1.3** specification for the material channel layout.
- Activision's **GTAO** paper for the horizon-based occlusion integral.
- Heitz (2018) for GGX visible-normal sampling; Karis (2013) for the split-sum
  environment BRDF; Hill's ACES fit and the AgX reference for the tonemap curves.

Thanks to the Iris, Sodium, Distant Horizons, Voxy and Vitrail authors for the
APIs this pack depends on.

---

<div align="center">

**Muon v0.0.1** — Copyright © 2026 Keyon Fatemi ("Ligmite").
See [LICENSE.txt](LICENSE.txt).

</div>
