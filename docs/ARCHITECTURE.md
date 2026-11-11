# Architecture

This document explains how Muon is put together and, more importantly, *why* it
is put together that way. The design is driven by three constraints:

1. It has to be an Iris pack today, with the whole modern feature set.
2. It has to be translatable to a Vulkan/SPIR-V backend (Vitrail) and eventually
   to a WGSL/Rust renderer (Horizon) without a rewrite.
3. It has to be maintainable by one person, which means no lighting equation may
   exist in two places.

## Layers

```
shaders/*.vsh | *.fsh          generated entry points (46 programs, 92 files)
        │
        ├── shaders/program/   the passes themselves
        │
        └── shaders/lib/       the renderer
                ├── uniforms/  loader-facing declarations and the frame block
                └── common/    platform-agnostic algorithms
```

The dependency arrow only ever points downward. `lib/common/` never mentions a
program name, a render target, or an Iris directive. That layer is the part that
could be dropped into a different engine unchanged; the passes are the part that
knows about Minecraft.

### `lib/uniforms/`

| File | Responsibility |
|---|---|
| `iris.glsl` | every loader-injected uniform, declared exactly once |
| `frame.glsl` | `MuonFrame`: the per-frame state block and its adapter |
| `settings.glsl` | compile-time options as named constants |
| `samplers.glsl` | every sampler the pack creates itself |

### `lib/common/`

| File | Responsibility |
|---|---|
| `constants.glsl` | target indices, material ids, flags, physical constants |
| `math.glsl` | scalars, vectors, geometry, numerical hygiene |
| `encoding.glsl` | octahedral normals, unorm packing, depth conversion |
| `random.glsl` | integer hashes, PCG, Halton, R2, blue noise |
| `noise.glsl` | value/gradient/Worley noise, fBm, caustics, 3D volume sampling |
| `color.glsl` | transfer functions, luminance, hue rotation, blackbody |
| `tonemap.glsl` | AgX, ACES, Reinhard, soft knee |
| `sampling.glsl` | hemisphere, cone, GGX, Vogel, concentric disk |
| `brdf.glsl` | GGX distribution, Smith visibility, Fresnel, IBL, LabPBR mapping |
| `material.glsl` | the `MuonMaterial` struct and material rules (wetness, snow) |
| `texture.glsl` | LabPBR decode, normal maps, parallax occlusion mapping |
| `gbuffer_write.glsl` | g-buffer encoders (geometry stages only) |
| `gbuffer_read.glsl` | g-buffer decoders (shading stages only) |
| `shadow.glsl` | PCSS, PCF, screen-space cascade, combined visibility |
| `atmosphere.glsl` | sky radiance, sun/moon colour, aerial perspective |
| `clouds.glsl` | cloud density field, raymarch, cloud shadows |
| `volumetric.glsl` | fog medium, volumetric integration, god rays |
| `water.glsl` | Gerstner waves, Fresnel, refraction, Beer-Lambert, caustics |
| `gtao.glsl` | horizon search, GTAO integral, SSAO kernel |
| `ssr.glsl` | reflection march, hit refinement, composition |
| `taa.glsl` | jitter, velocity, YCoCg clipping, resolve |
| `sss.glsl` | foliage transmission and screen-space gather |
| `raytrace.glsl` | screen-space path tracer, multi-bounce iteration, denoiser |
| `wetness.glsl` | puddles, ripples, snow cover |
| `waving.glsl` | foliage and water vertex animation |
| `bloom.glsl`, `dof.glsl`, `lensflare.glsl`, `post.glsl` | post-processing |

## Pass graph

```
                     ┌──────────┐
                     │  shadow  │  hardware shadow map
                     └────┬─────┘
                          │
   ┌──────────────────────┴──────────────────────┐
   │                                            │
┌──▼─────────────┐                     ┌────────▼────────┐
│ gbuffers_*     │ 1,2,3,4             │ gbuffers_water  │ 9,10,11
│ opaque         │                     │ translucent     │
└──┬─────────────┘                     └────────┬────────┘
   │                                            │
┌──▼──────────┐  GTAO → 14 (half)                │
│ deferred    │                                 │
└──┬──────────┘                                 │
   │                                            │
┌──▼──────────┐  lighting + sky + clouds → 0    │
│ deferred1   │                                 │
└──┬──────────┘                                 │
   │                                            │
┌──▼──────────┐  water + volumetrics → 0 ◄──────┘  (flip)
│ deferred2   │
└──┬──────────┘
   │
┌──▼──────────┐  exposure → 12 (64×64, flip)
│ composite   │
└──┬──────────┘
   │
┌──▼──────────┐  SSR + GI → 13, 7 (flip)
│ composite1  │
└──┬──────────┘
   │
┌──▼──────────┐  indirect + god rays + velocity → 15, 8
│ composite2  │
└──┬──────────┘
   │
┌──▼──────────┐  TAA → 0, 5 (flip)
│ composite3  │
└──┬──────────┘
   │
┌──▼──────────┐  DoF → 15
│ composite4  │
└──┬──────────┘
   │
┌──▼──────────┐  bloom bright → 6 (mip chain)
│ composite5  │
└──┬──────────┘
   │
┌──▼──────────┐  bloom upsample → 0
│ composite6  │
└──┬──────────┘
   │
┌──▼──────────┐  tonemap + grade + sRGB → screen
│    final    │
└─────────────┘
```

The chain is a strict alternation of full-resolution RGBA16F buffers, with three
half/quarter-resolution exceptions (AO, exposure) and one mip pyramid (bloom).
Every pass reads only what an earlier pass wrote, except the four flipped passes
which read and write the same target.

## Decisions worth explaining

### Why a fully deferred pipeline

Forward lighting in the geometry stage would need the sun, the moon, PCSS, cloud
shadows, block light, sky ambient, GTAO and SSS inside `gbuffers_terrain`,
`gbuffers_entities`, `gbuffers_hand`, `gbuffers_water`, `dh_terrain` and the Voxy
emitters — six copies of the same equations. Deferring means one copy, and it
means a single place to fix a bias or change a BRDF.

The cost is that translucents cannot be forward-blended into the colour target.
Muon handles that with the separate translucent g-buffer rather than by giving up
and duplicating the shader.

### Why the sun's shadow term is computed in the lighting pass, not on geometry

PCSS needs a blocker search over the shadow map, which needs the depth map, which
does not exist during the geometry pass. It also cannot be baked per vertex
because the penumbra is a per-fragment property.

### Why the sky is not `gbuffers_skybasic`

The atmosphere model that draws the sky is the same model that produces the sun
colour, the ambient irradiance and the aerial perspective. Drawing the sky in a
geometry stage would mean a second copy of that model, and the two would drift.
Instead the vanilla sky, sun, moon, stars and clouds are disabled and `deferred1`
writes sky pixels, identified by the far depth.

### Why fog is applied in `deferred2`

Fog is a medium between the eye and everything else, so it has to cover the water
surface too. Applying it in the lighting pass would leave water hovering in front
of the fog instead of inside it.

### Why the path tracer is screen-space

A world-space tracer needs either hardware ray tracing or a persistent voxel
volume. Iris can provide a storage buffer (`image.` custom images), but Vitrail's
support for custom images is not something this version wants to bet on, and a
voxel volume would need its own building pass, its own memory budget and its own
denoiser. The screen-space tracer is implemented so that the *gathering* step
(`muon_trace_gi_ray`) can be replaced by a world-space hit test without changing
`muon_trace_gi`, the bounce iteration, the denoiser or the passes that consume
the result.

## Quality knobs

`QUALITY` (0–3) is the master switch, set by the presets. Everything else derives
from it in the "derived constants" block of `settings.glsl`:

| Quality | Volumetric steps | Cloud steps | Shadow taps | AO slices × steps | Reflection taps |
|---|---|---|---|---|---|
| 0 (Low) | FOG/2 | CLOUD/2 | SHADOW/2 | 1 × 3 | 0 |
| 1 (Medium) | FOG | CLOUD | SHADOW | 2 × GTAO_STEPS | 1 |
| 2 (High) | FOG+4 | CLOUD | SHADOW | GTAO_SLICES × GTAO_STEPS | 2 |
| 3 (Ultra) | FOG×2 | CLOUD+16 | SHADOW | GTAO_SLICES × (GTAO_STEPS+2) | 3 |

`SHADOW_SAMPLES`, `FOG_STEPS` and `CLOUD_STEPS` are themselves user options, so a
preset can move the base value and the quality multiplier still applies.

## Where to change things

| Task | File |
|---|---|
| add a user option | `shaders/settings.glsl`, then a screen in `shaders/shaders.properties`, then `lib/uniforms/settings.glsl` if a `const` alias helps |
| change the look of the grade | `lib/common/post.glsl` |
| change the tonemap | `lib/common/tonemap.glsl` |
| tune the water optics | `lib/common/water.glsl`, constants at the top |
| add a material | `lib/common/constants.glsl`, `block.properties`, `muon_classify_block` in `program/gbuffers_solid.vsh` |
| add a pass | a file in `program/`, an entry in `tools/gen_wrappers.py`, a target in `shaders.properties`, then `python tools/gen_wrappers.py` |
