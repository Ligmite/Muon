# Architecture

Muon is a deferred renderer with a screen-space path tracer bolted on. This
document describes the frame, the buffers, the coordinate spaces and where each
piece of maths lives, so that changes stay local and the code stays portable.

---

## The frame, in order

| # | Program | Reads | Writes | Resolution | Purpose |
| --- | --- | --- | --- | --- | --- |
| 1 | `shadow`, `shadow_*` | geometry | shadowtex0/1 | `shadowMapResolution` | Distorted orthographic shadow map |
| 2 | `gbuffers_*` | textures | 1, 2, 3, 14 | full | Surface data |
| 3 | `gbuffers_sky*` | — | 0 | full | Clears sky so `depth == 1` marks it |
| 4 | `gbuffers_water`, `*_translucent` | textures | 9, 10 | full | Premultiplied translucent layer |
| 5 | `deferred` | depth, 2 | 4 | ½ | GTAO / SSAO |
| 6 | `deferred1` | depth, shadow | 6 | ½ | Volumetric fog and light shafts |
| 7 | `deferred2` | depth, shadow | 7 | ½ | Volumetric clouds |
| 8 | `deferred3` | 1, 2, 3, 14, 12 | 8 | full | Path tracer, temporally accumulated |
| 9 | `deferred4` | 1, 2, 3, 4, 5, 8, 14, depth | 0, 12 | full | Opaque shading + sky |
| 10 | `composite` | 0, 4, 5, 6, 7, 9, 10 | 11 | full | Translucents, clouds, fog |
| 11 | `composite1` | 11, 5 | 0 | full | TAA |
| 12 | `composite2` | 0 | 6 | ½ | Bloom prefilter |
| 13 | `composite3` | 6 | 7 | ½ | Bloom blur H |
| 14 | `composite4` | 7 | 6 | ½ | Bloom blur V |
| 15 | `composite5` | 0, depth | 11, 5 | full | DOF + motion blur, history copy |
| 16 | `composite6` | 11, 6 | 13 | full | Exposure, grade, tonemap |
| 17 | `final` | 13, 6, 14 | screen | full | FXAA/CAS, dither, HDR encode |

No pass reads a buffer it writes. Where ping-pong is needed (TAA history, RT
history), the write goes to a different buffer and the copy happens in a later
pass:

* RT: `deferred3` reads `12`, writes `8`; `deferred4` copies `8` back into `12`.
* TAA: `composite1` reads `5`, writes `0`; `composite5` copies `0` into `5`.

---

## Buffers

| Buffer | Format | Size | Contents |
| --- | --- | --- | --- |
| 0 | RGBA16F | 1 | Scene colour, HDR, linear Rec.709 |
| 1 | RGBA16 | 1 | albedo.rgb, material id / 255 |
| 2 | RGBA16 | 1 | octahedral normal.xy, roughness, metalness |
| 3 | RGBA16 | 1 | emission (Reinhard compressed), subsurface, vanilla AO, F0 |
| 4 | RGBA16 | ½ | ambient occlusion |
| 5 | RGBA16F | 1 | TAA history **and** SSR source |
| 6 | RGBA16F | ½ | volumetric in-scatter.rgb, transmittance |
| 7 | RGBA16F | ½ | cloud in-scatter.rgb, transmittance |
| 8 | RGBA16F | 1 | ray tracing radiance + normalised history length |
| 9 | RGBA16 | 1 | translucent normal.xy, surface depth, flags |
| 10 | RGBA16F | 1 | translucent premultiplied colour + alpha |
| 11 | RGBA16F | 1 | composite scratch / DOF output |
| 12 | RGBA16F | 1 | ray tracing history |
| 13 | RGBA16F | 1 | tonemapped LDR image |
| 14 | RGBA16 | 1 | skylight, blocklight, porosity, wetness |
| 15 | RGBA16F | 1 | spare |

`5` and `12` are **not** cleared per frame (`lib/buffers.glsl`). Everything else
is either fully rewritten or needs clearing (`9`, `10` because they accumulate
translucent fragments).

---

## Coordinate spaces

* **screen** — `uv ∈ [0,1]`, depth `[0,1]`.
* **view** — camera at origin, `-Z` forward, axes follow the camera.
* **scene** — camera at origin, world-aligned axes. The sun direction is
  constant in this space, so it is what lighting, clouds and the atmosphere use.
* **world** — scene + `cameraPosition`.

G-buffer normals are stored in **scene space** (the vertex stage rotates them
once), which removes a matrix multiply from every deferred pixel.

Hand pixels use a compressed depth range; `fix_hand_depth()` in `lib/space.glsl`
expands them. Anything that reconstructs positions from `depthtex1` must go
through `screen_to_view_space()`, which does this automatically when asked.

---

## Library map

| File | Responsibility | Portable to WGSL |
| --- | --- | --- |
| `lib/common.glsl` | constants, macros, small maths, HDR macro plumbing | trivially |
| `lib/uniforms.glsl` | the loader uniform block | becomes a WGSL uniform struct |
| `lib/space.glsl` | space transforms, motion vectors, depth | trivially |
| `lib/random.glsl` | integer hashing, R2/Halton, blue noise, sampling | trivially (uint ops map 1:1) |
| `lib/noise.glsl` | value/gradient noise, FBM, Worley, curl, caustics | trivially |
| `lib/color.glsl` | transfer functions, colour spaces, tonemappers, grade | trivially |
| `lib/brdf.glsl` | GGX, Smith, Fresnel, multi-scatter, phases | trivially |
| `lib/materials.glsl` | material ids, labPBR decode, waving, hardcoded overrides | trivially |
| `lib/encoding.glsl` | octahedral normals, G-buffer pack/unpack, combined depth | trivially |
| `lib/shadow.glsl` | shadow projection, bias, PCSS, contact shadows | trivially |
| `lib/atmosphere.glsl` | single-scattering sky, sun/moon discs, stars, galaxy, aurora | trivially |
| `lib/clouds.glsl` | four cloud layers, cloud lighting, cloud shadows | trivially |
| `lib/ao.glsl` | GTAO and SSAO | trivially |
| `lib/ssr.glsl` | SSR ray march and environment fallback | trivially |
| `lib/volumetrics.glsl` | fog medium, raymarch, upsampling | trivially |
| `lib/water.glsl` | wave normals, caustics, absorption, refraction | trivially |
| `lib/lighting.glsl` | `SurfaceData`, `shade_surface`, light colours, shadow composition | trivially |
| `lib/gbuffer.glsl` | reads the G-buffer back into `SurfaceData` | trivially |
| `lib/pathtracing.glsl` | screen-space path tracer, NEE, MIS-lite | needs care (loops, structs) |
| `lib/denoise.glsl` | temporal accumulation, bilateral filter | trivially |
| `lib/post.glsl` | TAA, bloom, DOF, motion blur, FXAA, CAS, grade operators | trivially |
| `lib/buffers.glsl` | Iris clear flags (comment block) | not portable (loader config) |

The rule: **no file outside `lib/` and `program/` may contain maths.** Program
files are thin wrappers; that is what makes a future WGSL port mechanical.

---

## Data flow for a shaded pixel

```
gbuffer_fsh
  albedo      <- sRGB decode of gtexture * tint
  material    <- mc_Entity.x -> block.properties id -> MAT_*
  normal      <- TBN * normal map, rotated to scene space
  roughness   <- labPBR / material default / hardcoded
  f0, metal   <- labPBR F0 heuristic or material
  emission    <- material + labPBR emission channel
  ao          <- vanilla AO in gl_Color.a
  light levels<- multi-tex-coord-1 / 240
        |
        v
deferred4
  depth       -> scene position, view direction
  AO          <- colortex4, blurred into vanilla AO
  shadow      <- PCSS + contact shadows + cloud shadows
  reflection  <- SSR (colortex5) mixed with analytic sky
  indirect    <- RAY_TRACING: colortex8 (temporal + bilateral) mixed with raster
  colour      <- shade_surface(SurfaceData, light_dir, reflection)
        |
        v
composite
  cloudy      <- colour * cloudT + cloudScatter
  water       <- refraction (Beer-Lambert) + SSR + sun highlight + foam
  fog         <- colour * fogT + fogScatter
        |
        v
TAA -> DOF/motion blur -> exposure -> grade -> tonemap -> AA -> HDR encode
```

---

## Design rules

1. **One place for the display transform.** Only `final.fsh` calls
   `display_eotf()`. Only `composite6.fsh` tonemaps.
2. **One place for the sun colour.** `direct_light_color()` in `lib/lighting.glsl`
   combines the blackbody spectrum with atmospheric extinction; nothing else
   invents a sun colour.
3. **Static loops.** Loops use settings constants so drivers can unroll them and
   so the code maps cleanly onto WGSL.
4. **No compute shaders.** Everything is a fragment pass, which keeps OptiFine,
   Iris, Vulkan-style backends and a future Rust renderer on the same path.
5. **No `gl_FragData`.** Explicit `layout(location = N) out` plus
   `/* RENDERTARGETS: ... */` is unambiguous for every backend.
