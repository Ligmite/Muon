# Muon

**Muon** is a filmic WGSL shader pack for [Horizon](https://github.com/horizon-rust/horizon),
the Rust rewrite of Minecraft. Its look is inspired by
[Photon](https://github.com/SixthSurge/Photon) by SixthSurge: a physical sky,
real sun/moon shadows, volumetric cumulus, an ocean-like water surface and a
warm, contrasty grade. The WGSL in this repository is Muon's own implementation.

Current release: **0.4.3** (shader API 0.1).

## Features

- **Sky** — analytic Rayleigh/Mie atmosphere, a larger sun disc with a
  sun-space halo, stars, moon halo and a dither before the 8-bit frame store to
  avoid colour banding.
- **Clouds** — volumetric cumulus with a 2D coverage chart (real gaps), 3D
  billow erosion, per-column base/height variation, a multi-scatter light march
  and a cloud-shadow chart projected onto the terrain.
- **Shadows** — a real 2048² sun/moon shadow map, 3×3 PCF, cutout leaves/plants
  treated as solid, coloured light through translucent surfaces.
- **Water** — domain-warped swell + isotropic chop, the engine water mirror,
  screen-space refraction, depth-based absorption, a GGX sun glint and Snell's
  window/total internal reflection from below. Normals fade by pixel footprint
  so distant water does not alias into a crosshatch.
- **Terrain** — LabPBR normal/specular maps, wrapped diffuse, coloured block
  light, emission, leaf translucency and an ambient floor that keeps shaded
  trunks readable.
- **Post** — GTAO, SSR, screen-space sun shafts and haze, thresholded bloom,
  toggleable lens flare, a photographic LUT, filmic tone mapping, HDR output,
  FXAA, CAS and dithering.
- **Weather** — lit rain/snow streaks, hidden while the camera is underwater.

## Requirements

- A Horizon build that serves shader API 0.1 with the shadow, reflection and
  weather stages (the current nightly does).
- No other dependencies for the shader itself. The Python tools need Python 3
  and Pillow.

## Install

1. Copy `dist/muon-0.4.3.hshader` (or the `pack/` folder) into your Horizon
   `shaderpacks/` directory:
   - Windows: `%APPDATA%\horizon\shaderpacks\`
   - The pack folder or the `.hshader` both work.
2. In game: **Options → Video Settings → Shader Packs**, select **Muon**.
3. If you install the folder, Horizon hot-reloads edits and a replaced
   `lut.png` within about half a second. The zip has to be replaced/reloaded.

`HORIZON_SHADER_PACK` can name the installed pack for development, as the
Horizon docs describe.

## LUTs

The API has no file I/O, so a LUT is baked into the pack as a PNG atlas. The
shipped `pack/lut.png` is a neutral identity atlas and `Use LUT` defaults off.

```sh
# from the repository root
python tools/cube_to_lut_png.py my_look.cube pack/lut.png
python tools/pack_muon.py pack muon-0.4.3.hshader
```

Then enable **Use LUT** and set **LUT strength** in the Shader Options page. If
red and blue look swapped, convert again with `--blue-fastest`. Full details,
including Resolve/Lightroom export notes, are in [docs/LUT.md](docs/LUT.md).

## Build

```sh
cd pack
python ../tools/make_identity_lut.py     # writes lut.png in this folder
cd ..
python tools/pack_muon.py pack muon-0.4.3.hshader
```

`tools/pack_muon.py` writes the `.hshader` as a zip with `pack/…` entries
rewritten to `/`, which Horizon requires.

## Repository layout

```
pack/                 shader source (horizon-shaders.toml, *.wgsl, lut.png)
tools/                .cube → PNG LUT converter, identity LUT, packer
docs/                 LUT guide
dist/                 built .hshader
```

## Options worth knowing

| Option | Default | Effect |
|---|---:|---|
| `Sunlight intensity` | 7.0 | Direct sun/moon multiplier |
| `Sun/moon shadows` | on | Toggles the shadow pass |
| `Ambient light` | 1.0 | Sky/ground ambient floor |
| `Water wave strength` | 1.0 | Surface normal strength |
| `Water absorption` | 1.0 | Water colour/thickness |
| `Use LUT` / `LUT strength` | off / 1.0 | Display-referred LUT |
| `Bloom threshold` | 1.0 | Highlights-only bloom |
| `Lens flare` / intensity | on / 0.6 | Sun-anchored flare |
| `HDR output` | off | Paper-white-relative HDR |
| `Auto exposure` | off | Eased camera-light exposure |

## Credits

- **SixthSurge (Benjamin Stott) — Photon**: the reference for the look, colour
  grade structure, atmosphere, water and cloud lighting.
  <https://github.com/SixthSurge/Photon>
- **Photon HDR fork**: reference for the HDR toe/shoulder approach.
- **Public techniques**: Lottes (2016), Hejl–Burgess, Narkowicz ACES fit,
  Uchimura and Reinhard tone curves; Cook–Torrance/GGX/Smith and Schlick
  Fresnel; Rayleigh/Mie scattering; Gerstner dispersion; Beer–Lambert and
  Beer–Powder extinction.
- **Horizon** for the shader API, prelude and stage system.

Muon is an independent implementation and does not include Photon's GLSL
source. Photon and Minecraft are the property of their respective authors; this
project is not affiliated with Mojang, Microsoft or the Horizon project.

## License

MIT — see [LICENSE](LICENSE).
