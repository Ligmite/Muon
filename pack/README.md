# Muon 0.4.3

**Muon** is an independent WGSL shader for Horizon's shader API 0.1 (sky +
material + weather + post), made in the spirit of SixthSurge's Photon. Muon's
grade keeps the shape of Photon's `c19_color_grading` (Lottes default, 18% grey
log-contrast, hue-band saturation, split tone, vignette) and its HDR path keeps
the filmic toe with a soft shoulder at the display peak.

## What changed in 0.4.3

* **Waves you can see.** The normal is about twice as strong, the mirror and
  refraction are distorted much more, the sun glint is broader and crest foam
  adds a readable edge. Footprint fading still removes distant aliasing.
* **Clouds break vertically.** Per-column base offset is now up to ±95 blocks
  and thickness varies 55–145%, with a coarser billow/erosion pair so the
  surface is less noisy.
* **Lens flare only when the sun is near centre.** A centred/edge fade plus
  lower intensity and smaller ghosts stop the wide glare when the sun is just
  clipping the screen.

## What changed in 0.4.2

* **LUT sampling fixed and off by default.** The atlas was sampled on slice
  edges, so the red channel fell into the next blue slice; a white sun became
  teal and water/portal colours shifted pink. Sampling now uses texel centres.
  `Use LUT` defaults off until you install a real LUT.
* **Lens flare.** A toggleable screen-space flare with a sun halo, anamorphic
  streak and four lens ghosts, anchored to the sun's projected position.
  `Lens flare` + `Lens flare intensity`.
* **A larger sun disc** (about 2.5° across) and a wider sun-space halo.
* **Clouds vary in height.** Per-column base/height noise means the deck is no
  longer one perfectly level slab.
* **Water is noise-led now.** Two broad swells plus three scales of isotropic
  noise chop; the directional cross-grid is gone and the normal fades by pixel
  footprint at distance.
* **Less green push, steadier exposure.** Green saturation defaults slightly
  negative; auto exposure reads the eased camera light instead of a screen
  average, so it no longer pumps while walking.

## What changed in 0.4.1

* **Highlights-only bloom.** Bloom now has an HDR threshold (default 1.0), so
  only the sun disc and genuinely emissive surfaces bloom. A bright cloud
  drifting past no longer carries its own glow, which is what made the glare
  look detached from the sun while walking; a sun-space halo in the sky shader
  anchors the rest.

## What changed in 0.4.0

* **Photographic LUT support.** The pack ships a 33³ identity LUT as a
  display-referred 2D atlas (`lut.png`). Drop in a Lightroom/Resolve `.cube`
  converted with `tools/cube_to_lut_png.py`, repack, and the grade is
  `Use LUT` + `LUT strength`. The LUT runs after tonemapping, where a
  photographic LUT expects to be.
* **Smaller, separated clouds.** A higher-frequency coverage chart and a
  three-scale fBm now break the deck into individual cumulus with gaps instead
  of one connected mass; the billow erosion is finer and the top/bottom light
  march stronger.
* **Distant water stops aliasing.** The wave normal is faded by the world size
  of a pixel (`fwidth` of world XZ), so the high-frequency ripples disappear
  into a smooth sky reflection before they can form a crosshatch. Near water
  gets a stronger wave normal.
* **Readable shadows.** Ambient is lifted with a sqrt sky-light response, a
  sky/ground floor and a warm ground bounce, so trunks and shaded sides keep
  detail at distance instead of printing black.
* **No vanilla clouds, sun or stars.** The manifest sets
  `[sky] clouds = false`, `sun = false`, `stars = false`, and the sky stage
  draws the atmosphere, sun, stars and the volumetric cloud layer itself. This
  also fixes the sky sliding under the player: the clouds are ray-marched from
  the world camera position in the sky pass, not reconstructed in a post pass.
* **A real shadow map.** `[shadow]` (2048², 128 blocks, cutout leaves/plants
  solid) gives cast shadows from the sun by day and the moon by night, with
  3×3 PCF and translucent-colour tinting.
* **Foliage and lighting.** LabPBR normals/specular, wrapped diffuse, a
  foliage up-normal bias, leaf translucency, coloured block light and emission
  replace the flat "sky light gates the sun" model.
* **Weather.** Rain and snow are lit and hidden while the camera is underwater.

## What maps 1:1 and what is approximated

| Reference feature | Here |
|---|---|
| Tonemap, grading, vignette, bloom mix | Similar grade, written for Muon (bloom is a 3-ring blur, not the mip chain) |
| HDR (filmic toe, soft shoulder) | Muon's own shoulder, `HDR output` option |
| Atmosphere / sky | Single-scattering analytic model (no sky LUT) |
| Sun/moon shadows | Real 2048² shadow map, 3×3 PCF |
| GTAO | Depth-only GTAO, 4 slices × 5 steps, bilateral denoise |
| SSR | Depth march, water (and optional wet ground) |
| Volumetric light | Screen-space sun shafts + haze (no shadow-map raymarch) |
| Water | Domain-warped height field, engine mirror, refraction, absorption, Snell's window from below |
| Clouds | Volumetric cumulus in the sky stage, cloud-shadow chart on terrain |
| LUT | 33³ display-referred atlas, `.cube` converter included |
| Aurora, SSS, LPV coloured light, DOF, motion blur, TAA, rain puddles | Not in this pack |

The API still gives no G-buffer for entities, no compute and no motion vectors,
so those features remain approximations or are absent.

## Using a LUT

The shader API has no file I/O, so a LUT is baked into the pack as a PNG atlas:
33 blue slices laid out horizontally, width 33×33, height 33. The pack ships an
identity atlas, so nothing changes until you replace it.

1. Convert a 3D `.cube` (Lightroom, Resolve, Affinity, etc.):

   ```sh
   python tools/cube_to_lut_png.py my_look.cube pack/lut.png
   ```

   If red and blue look swapped in game, repeat with `--blue-fastest`.

2. Repack the folder:

   ```sh
   python tools/pack_muon.py pack muon-0.4.2.hshader
   ```

3. In game, enable `Use LUT` and set `LUT strength` to taste. The LUT is
   applied after tonemapping and before dithering, so it behaves like a display
   LUT in a grading app rather than a scene-linear transform. It is off by
   default so an identity atlas cannot alter the picture until you opt in.

## Things to check first in game

1. If water looks too dark or too clear, use `Water absorption` (0 = clear,
   3 = murky).
2. If the sun is too strong, lower `Sunlight intensity`; the reference default
   is 7.
3. `Sun/moon shadows` off measures the lighting without the shadow pass.
4. `Horizon haze` controls the fog band at the horizon; 0 leaves the atmosphere
   untouched.
5. `Output linear` is a debugging switch; leave it off.

Muon is MIT licensed; see `LICENSE`.

## Credits

Muon is an independent WGSL shader. Its look is inspired by the work below; the
WGSL in this pack is Muon's own implementation.

- **SixthSurge (Benjamin Stott) — Photon.** The reference for Muon's colour
  grade, atmosphere, water and cloud lighting. Muon keeps the spirit of
  Photon's `c19_color_grading` (Lottes default, log-contrast, hue-band
  saturation, split tone). <https://github.com/SixthSurge/Photon>
- **Photon HDR fork.** The reference for an HDR path that keeps a filmic toe
  and puts a soft shoulder at the display peak. Muon implements that idea in
  `mu_tonemap_hdr`.
- **Public techniques:** Lottes (2016), Hejl–Burgess, Narkowicz ACES fit,
  Uchimura and Reinhard tone curves; Cook–Torrance/GGX/Smith BRDF and Schlick
  Fresnel; Rayleigh/Mie single scattering; deep-water Gerstner dispersion;
  Beer–Lambert and Beer–Powder extinction.
- **Horizon.** Shader API, prelude and stage system:
  <https://github.com/horizon-rust/horizon>

Keep this file and `LICENSE` with any redistribution.

