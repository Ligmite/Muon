# Muon

**Muon** is a filmic WGSL shader pack for [Horizon](https://github.com/horizon-rust/horizon),
the Rust rewrite of Minecraft. It rebuilds the sky, clouds, shadows, water and
terrain response in one native pipeline, then finishes with a Photon-inspired
grade, HDR output and a photographic LUT slot.

The look is inspired by [Photon](https://github.com/SixthSurge/Photon) by
SixthSurge. The WGSL in this repository is Muon's own implementation; the design
notes below explain the choices rather than hiding them behind a preset.

Current release: **0.4.5** · shader API **0.1** · MIT

## At a glance

| | |
|---|---|
| **Sky** | analytic Rayleigh/Mie atmosphere, ozone tint, 2.5° sun disc, sun-space halo, stars, moon halo, 8-bit dither |
| **Clouds** | depth-aware post-pass cumulus, 2D chart + 3D coverage, 3D billow erosion, ±140-block base variation, multi-scatter light march, cloud shadows |
| **Shadows** | 2048² sun/moon map, 128-block range, 3×3 PCF, solid leaf/plant cutouts, translucent colour tinting |
| **Water** | Photon-style three-octave waves with a tiling noise phase, engine mirror, depth-rejected refraction, Beer–Lambert absorption, Snell's window/TIR, crest foam |
| **Terrain** | LabPBR normal/specular, GGX/Smith specular, wrapped diffuse, coloured block light, emission, foliage translucency |
| **Post** | GTAO + denoise, SSR, screen-space sun shafts/haze, HDR-threshold bloom, sun-anchored lens flare, LUT, filmic tonemap, HDR, FXAA, CAS, dither |
| **Weather** | lit rain/snow streaks, suppressed while underwater |
| **UI** | Photon-style option pages: General · World · Lighting · Sky · Fog · Materials · Water · Post-Processing · Misc · HDR |

## How a frame is built

```
sky stage ────────────────┐
material stage (opaque) ──┼─► GTAO ─► AO denoise ─► SSR ─► volumetrics
material stage (water) ───┘                                      │
                                                                 ▼
                                                              clouds
                                                                 │
                    final ◄─ FXAA ◄─ grade/bloom/LUT ◄───────────┘
```

The world is still culled, batched and meshed by Horizon. Muon only replaces
what the stages mean: sky radiance, terrain response, water response and the
post chain.

---

# Under the hood

## Sky: a physical dome, not a gradient

The sky is a single-scattering atmosphere evaluated per ray:

- Rayleigh and Mie scattering with realistic scale heights
- an ozone term that pulls the zenith blue and warms the horizon at sunset
- separate sun and moon contributions
- a clear-day blue lift so a straight Rayleigh integral does not read grey on a
  display
- sun and moon halos in **direction space**, so they stay glued to the bodies
  while the camera moves

The sun disc is about **2.5°** across with a soft limb, and the whole dome is
dithered before the 8-bit frame store. Smooth sky gradients are exactly where
banding shows, and a full-screen dither costs almost nothing.

`MU_HEADROOM = 4.0` in the inter-pass encode is deliberate: sky radiance is
several times brighter than sunlit terrain. Clamping at 1.0 was what made early
versions read as a white dome.

## Clouds: coverage in 2D, shape in 3D, depth in post

The cloud deck is built from three separate ideas:

1. **Coverage chart** — a 2D fBm sampled on the cloud base, perturbed at each
   sample by a 3D noise field with a height-dependent threshold. The chart
   decides whether a column exists; the 3D term decides whether it survives at
   this altitude, so the silhouette is not simply an extruded 2D mask.
2. **Billow erosion** — two 3D billow octaves erode the column into cauliflower
   tops and torn edges. `abs(noise * 2 - 1)` folded around the midpoint is what
   gives cumulus their shape; plain fBm gives soft blobs.
3. **Per-column height** — each column shifts its base by up to ±140 blocks and
   scales its thickness from 50% to 150%. An egg-shaped altitude profile thins
   the base and top. The deck is not one flat sheet.

For context, Photon draws several spherical-shell layers (cumulus, altocumulus,
congestus, cirrus), each with a precomputed coverage map, 3D Worley detail,
multi-scatter and aerial perspective. Muon currently uses one slab with one
coverage chart and a simpler light march. That is the main remaining visual gap;
the 3D coverage perturbation and per-column height are the first steps toward
closing it.

Lighting is a short march toward the sun through the same density field, with:

- Beer–Lambert transmittance
- a multi-scatter term so thick cores do not go black
- Beer–Powder for silver linings
- a height term so shaded bases are cooler than lit tops

The march is a **depth-aware post pass**, not a sky-stage effect. It rays from
the world camera, stops at scene depth, and composites in front of terrain. That
is what lets you fly **above** the deck and still see it; a sky dome cannot draw
clouds below the horizon. A cloud-shadow chart is projected onto the terrain
from the same coverage map.

## Shadows: a real map, not a sky-light proxy

`[shadow]` builds a 2048² depth map from the sun by day and the moon by night.

- 128-block shadow distance
- 3×3 PCF with a texel-scaled radius
- leaves and plants are treated as solid so canopies cast whole shadows instead
  of punching cutout holes
- `shadow_map_translucent` and `shadow_color` tint sunlight that passes through
  water or stained glass
- a normal-offset bias plus a slope-aware comparison bias keep acne off

The terrain shader evaluates direct sun/moon, wrapped diffuse, a sky/ground
ambient floor, coloured block light and emission. Foliage gets a larger wrap and
a backlit translucency term; plants are lit with an upward-biased normal because
flat quads otherwise go black on one side.

## Water: Photon's wave stack, Muon's shading

The wave field follows the logic Photon uses:

- **three octaves** of a squared-sine Gerstner profile
- **deep-water dispersion**, `ω = √(gk)`, so long waves outrun short ones
- **golden-angle rotation** each octave so the wave trains do not line up
- a **tiling noise texture** added inside the phase, so individual crests wander
- a low-frequency height-variation noise that makes some patches choppier

The normal is a finite difference of that height field. It is deliberately
**small** — Photon-style, around 0.01–0.04 plus rain — because the visibility
comes from the reflection and specular pipeline, not from huge normals.

Muon then adds:

- the engine's half-resolution **water mirror**, distorted by the wave normal
- **screen-space refraction** with depth rejection, so seabed steps do not smear
- **Beer–Lambert absorption** by the thickness of water behind the surface
- a **GGX sun glint** with a broad lobe
- **crest foam** on the highest wave samples
- a minimum low-frequency normal at distance, so the far lake is not a perfect
  mirror
- **Snell's window and total internal reflection** from below, so the underside
  is a real water-air interface instead of the vanilla animated texture

## Terrain: LabPBR and a readable ambient

The material stage reads the current API's surface data directly:

- LabPBR normal and specular maps (smoothness, F0/metal, porosity, emission)
- tangent-space normal mapping
- GGX/Smith specular with Schlick Fresnel
- wrapped diffuse for a softer terminator
- coloured block light from the engine's light volume
- emission from both the block kind and the LabPBR map
- a small sky/ground ambient floor plus a warm bounce, so trunks and shaded
  sides keep detail at distance

## Post: effects with a reason

| Pass | What it does | Why |
|---|---|---|
| GTAO | depth-only horizon occlusion | contact shading without a G-buffer |
| AO denoise | bilateral blur | removes the GTAO noise pattern |
| SSR | depth march with thickness rejection | reflections on water and smooth ground |
| Volumetrics | screen-space sun shafts + distance haze | crepuscular light and aerial perspective |
| Clouds | depth-aware raymarch | clouds above and below the camera |
| Grade | bloom + exposure + filmic grade + tonemap | the look |
| FXAA | spatial edge filter | the pack replaces Horizon's AA resolve |
| Final | CAS, LUT, dither, output encode | sharpness, look, clean 8-bit output |

**Bloom** is thresholded at HDR luminance 1.0 by default. A bright cloud drifting
past used to carry its own glow; now only the sun disc and genuinely emissive
surfaces bloom. **Lens flare** is gated by sun centring and screen edge, with a
sun-space halo, an anamorphic streak and four lens ghosts.

**LUTs** are display-referred and applied after tone mapping. Because the API has
no file I/O, a 3D LUT is baked into a 33³ PNG atlas; `tools/cube_to_lut_png.py`
converts Resolve/Lightroom/Affinity `.cube` files.

## HDR and the grade

The SDR path is a Lottes curve by default, with Hejl–Burgess, Uncharted 2, Tech
and Reinhard Jodie available. The grade is a filmic chain:

- log-contrast around 18% grey
- hue-band saturation (orange/teal/green)
- a cool-shadow / warm-highlight split tone
- a small S-curve
- Rec.2020 working space, converted back to Rec.709 for output

The HDR path keeps the filmic toe and hands the highlights to a soft exponential
shoulder at the display peak, relative to paper white. Peak and paper-white nits
are options, not hard-coded.

## Design notes

- **Clouds after volumetrics.** Clouds should not be darkened by GTAO or
  reflected by SSR using the terrain's depth. They composite after those passes
  and before grading.
- **Small water normals.** Large normals look like rubber. Small normals plus
  strong reflection/refraction distortion look like water.
- **Dither before storage.** A smooth sky gradient in 8 bits will band; dithering
  the sky and the final image is cheaper than a 16-bit frame.
- **No sky-light shadow proxy.** The shadow map is the real thing; terrain
  direct light is not gated by a smoothstep on sky light.
- **Per-column cloud height.** A single cloud layer with one base reads as a
  painted ceiling. Varying base and thickness per column gives the deck depth.

## Performance

The pack targets a modern discrete GPU. The manifest declares a `gpu_ms` budget
of 10 ms; the biggest costs are the cloud raymarch, GTAO/SSR and the shadow map.
Useful knobs:

- `Sun/moon shadows` off removes the shadow pass
- `Cloud coverage`/`Cloud density` reduce cloud work
- `GTAO strength` 0 skips the AO contribution
- `Screen-space reflections` Off removes the SSR march
- `Volumetric light intensity` 0 removes the shaft march
- `HDR output` off uses the SDR path

## Not in this pack

The API still has no entity G-buffer, no compute, no persistent history and no
motion vectors, so these are absent or approximated:

- entity/particle shading beyond Horizon's own
- FFT ocean spectrum and displacement
- volumetric cloud shadow maps
- TAA, motion blur, depth of field
- rain puddles/wetness simulation
- aurora and LPV coloured light

They are good candidates for later stages, not things the current pass chain
pretends to do.

---

## Requirements

- A Horizon build that serves shader API 0.1 with the shadow, reflection and
  weather stages (the current nightly does).
- No dependencies for the shader itself. The Python tools need Python 3 and
  Pillow.

## Install

1. Copy `dist/muon-0.4.5.hshader` (or the `pack/` folder) into your Horizon
   `shaderpacks/` directory:
   - Windows: `%APPDATA%\horizon\shaderpacks\`
   - The folder or the `.hshader` both work.
2. In game: **Options → Video Settings → Shader Packs**, select **Muon**.
3. A folder install lets Horizon hot-reload edits and a replaced `lut.png`
   within about half a second.

## LUTs

```sh
python tools/cube_to_lut_png.py my_look.cube pack/lut.png
python tools/pack_muon.py pack muon-0.4.5.hshader
```

Enable **Use LUT** and set **LUT strength**. Full details, including the `.cube`
data order and Lightroom/Resolve export notes, are in [docs/LUT.md](docs/LUT.md).

## Build

```sh
cd pack
python ../tools/make_identity_lut.py
cd ..
python tools/pack_muon.py pack muon-0.4.5.hshader
```

## Repository layout

```
pack/                 shader source, lut.png, water_noise.png
tools/                LUT converter, identity LUT, noise generator, packer
docs/                 LUT guide
dist/                 built .hshader
```

## Credits

- **SixthSurge (Benjamin Stott) — Photon**: reference for the look, grade
  structure, atmosphere, water and cloud lighting.
  <https://github.com/SixthSurge/Photon>
- **Photon HDR fork**: reference for the HDR toe/shoulder approach.
- **Public techniques**: Lottes (2016), Hejl–Burgess, Narkowicz ACES fit,
  Uchimura and Reinhard tone curves; Cook–Torrance/GGX/Smith and Schlick
  Fresnel; Rayleigh/Mie scattering; Gerstner dispersion; Beer–Lambert and
  Beer–Powder extinction.
- **Horizon** for the shader API, prelude and stage system.

Muon is an independent implementation and does not include Photon's GLSL
source. Not affiliated with Mojang, Microsoft or the Horizon project.

## License

MIT — see [LICENSE](LICENSE).
