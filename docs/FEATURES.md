# Feature reference

Every feature below is implemented in this release unless explicitly marked
otherwise. Option names are the `#define`s in `settings.glsl`.

---

## Lighting

### Direct light
* Sun and moon are treated as one "active shadow light" (`shadowLightPosition`
  is Iris' own selection), so sunsets and moonlit nights use the same code path.
* Sun colour is a blackbody spectrum (`SUN_TEMPERATURE`, default 5800 K)
  multiplied by the atmospheric transmittance for the current sun altitude.
  That is why sunrise is orange and noon is white — it is the same integral
  that colours the sky.
* Weather attenuates and desaturates direct light.
* Handheld light adds a camera-centred point light (`HANDHELD_LIGHTING`).

### Shadows
* Distorted shadow map: a radial warp concentrates resolution near the player.
  The same warp is applied when writing and sampling, so no inverse is needed.
* Normal-offset bias with slope scaling (`SHADOW_BIAS`), which removes most
  acne without peter-panning.
* PCSS (`SHADOW_SOFT`): a blocker search estimates the penumbra from the
  occluder distance and the sun's angular size, then a rotated Poisson PCF
  (`SHADOW_SAMPLES`) resolves it. Falls back to bilinear PCF when the penumbra
  is small, which keeps contact detail.
* Screen-space contact shadows (`SHADOW_SSRT`) catch sub-shadow-map detail.
* Cloud shadows (`CLOUD_SHADOWS`) sample the cumulus density along the sun ray.
* Shadowed areas fade to lit near the shadow map edge instead of popping.

### Ambient occlusion
* `SHADER_AO = 2` — GTAO: horizon-based, sliced, with a multi-bounce lift so
  crevices never go completely black.
* `SHADER_AO = 1` — SSAO: cosine-weighted kernel.
* `AO_IN_SUNLIGHT` applies occlusion to the ambient term only by default; that
  avoids the classic "dirty sun" look.
* Half resolution, bilinear upsample in the shading pass.

### Ambient
* `ambient_light_color()` = sky irradiance + ground bounce tinted by a dirt
  albedo and the current sun colour.
* Sky irradiance comes from the analytic atmosphere evaluated at the surface
  normal, so a wall facing the sunset is warm and a wall facing away is blue.

### Materials
* labPBR (`RESOURCEPACK_SUPPORT = 2`): smoothness, F0 with the >0.9 conductor
  heuristic, emission, porosity/SSS.
* Legacy specular (`1`), or fully off (`0`).
* Normal mapping with a TBN built in the vertex stage.
* POM (`POM`): parallax occlusion mapping with binary refinement, height taken
  from the albedo luminance so it works with vanilla textures, distance fade
  (`POM_DISTANCE`) and a parallax self-shadow pass (`POM_SHADOW`).
* Hardcoded fallbacks (`HARDCODED_SPECULAR`, `HARDCODED_EMISSION`,
  `HARDCODED_SSS`) give vanilla blocks plausible reflectance.
* Rain puddles (`RAIN_PUDDLES`): porous up-facing surfaces darken and become
  glossy as `wetness` rises, with a noise mask so puddles are patchy.
* Subsurface scattering for foliage, flowers, cloth and snow, with a
  two-lobe wrapped diffuse.
* Cloth sheen for wool.

---

## Sky and atmosphere

* Single-scattering Rayleigh + Mie + ozone atmosphere integrated along the view
  ray, with a Kasten–Young air mass for the sun ray. 12 steps, quadratic
  distribution, only evaluated for sky pixels.
* Multiple-scattering approximation so twilight keeps a soft glow.
* Sun disc with limb darkening and a hot core; radius from `SUN_ANGULAR_RADIUS`.
* Moon disc with terminator, eight phases, procedural craters and earthshine.
* Procedural star field with per-star colour and twinkle, rotated with the day.
* Milky Way band with dust lanes (`GALAXY`).
* Aurora curtains with three ribbons and activity that varies over time
  (`AURORA`, `AURORA_CONDITIONS`).
* Overcast blending and desaturation driven by `rainStrength`.
* Nether and End skies are handled separately (no atmosphere integration).

---

## Clouds

Four layers, each independently raymarched inside its own altitude slab and
composited back-to-front:

| Layer | Shape | Lighting |
| --- | --- | --- |
| Cumulus | coverage-thresholded FBM with value-noise erosion, vertical profile | Beer–Lambert + powder + 3-octave multiple scattering, 5 light steps |
| Cumulus congestus | larger scale, anvil widening near the top | same, with reduced light steps at distance |
| Altocumulus | Worley cell edges + value noise | shortened light march |
| Cirrus | ridged FBM stretched into streaks, curl warp | no self-shadowing, ambient + forward phase |

* Cloud shadows on terrain (`CLOUD_SHADOWS`).
* Coverage field is shared and driven by `rainStrength`, so storms are overcast.
* Wind direction and speed are global (`CLOUDS_WIND_ANGLE`, `CLOUDS_WIND_SPEED`).
* Optional classic flat layer (`VANILLA_CLOUDS_LAYER`).
* Half resolution with interleaved-gradient / blue-noise dithering.

---

## Water

* Analytic wave normals from `WATER_WAVE_ITERATIONS` directional sine waves with
  lacunarity and persistence; the same function drives vertex displacement.
* Rain ripples expand across the surface proportional to `rainStrength`.
* Refraction offset from the wave normal and the water thickness.
* Beer–Lambert absorption per channel with scattering colour.
* Caustics projected on the bottom from an animated Worley-like field.
* Screen-space reflections with sky fallback.
* Sun specular with a very tight lobe plus a wider sheen.
* Edge foam on shallow angles.
* Full underwater absorption and scattering when the camera is submerged.

---

## Reflections

* `REFLECTIONS = 0` off, `1` analytic sky/environment only, `2` SSR + sky.
* SSR marches the depth buffer with geometrically growing steps, a thickness
  test, and binary refinement. A per-pixel jitter makes it stochastic and TAA
  resolves it.
* Misses fade to the analytic sky, so water never goes black.
* Environment specular uses the split-sum BRDF with roughness-aware Fresnel and
  specular occlusion.

---

## Ray tracing / path tracing

`RAY_TRACING`:

| Value | Behaviour |
| --- | --- |
| `0` | Off, pure raster |
| `1` | Ray traced reflections replace SSR |
| `2` | Adds ray traced indirect diffuse + specular on top of raster direct light |
| `3` | Full path tracing: every bounce is traced, direct included |

Implementation details:

* Screen-space BVH-free traversal: the depth buffer is the acceleration
  structure, the G-buffer the surface database, the shadow map handles
  next-event estimation. Off-screen geometry cannot be hit — this is the same
  trade-off PTGI-class packs make.
* Cosine-weighted diffuse and GGX specular lobe selection with Fresnel-weighted
  probabilities.
* Russian roulette after two bounces.
* Sun NEE with a 4-tap cone for soft shadows.
* Sky radiance at ray misses, with the sun disc only for specular chains so it
  is not double counted.
* Temporal accumulation with motion-vector reprojection and a depth/normal
  disocclusion test (`RT_ACCUMULATION_LIMIT`).
* Edge-stopping bilateral spatial filter (`RT_DENOISE`), applied in the shading
  pass so it has access to the full-resolution normals.
* Confidence blending: freshly disoccluded pixels lean on raster lighting until
  the history rebuilds, which prevents the characteristic RT "smear".

---

## Volumetrics

* Half-resolution raymarch with a quadratic sample distribution.
* Exponential height fog, rain multiplier, cave fog based on eye brightness, and
  a border term that hides LOD transitions.
* Shadow map visibility per step, dithered along the ray, with a multiple
  scattering floor.
* Henyey–Greenstein phase with `VL_MIE_G`.
* Depth-aware 4-tap upsample in the shading pass.
* Underwater mode shortens the march and switches the medium.

---

## Post processing

* **TAA**: Catmull-Rom history, 3×3 neighbourhood AABB clipping, velocity and
  depth weighting, jitter-aware reprojection.
* **FXAA** or **CAS** (mutually exclusive in `final.fsh`; FXAA wins if both are on).
* **Bloom**: 13-tap prefilter with soft knee, separable tent blur at half res.
* **DOF**: hexagonal gather with a focus plane taken from the screen centre and
  a foreground rejection weight.
* **Motion blur**: camera-velocity reconstruction, clamped and dithered.
* **Exposure**: log-average over a fixed 6×6 grid, auto or manual.
* **Tonemap**: Muon Filmic (hue preserving + controlled highlight
  desaturation), ACES, Khronos Neutral, Uncharted 2, Reinhard.
* **Grade**: white balance, contrast at 0.18 pivot, saturation, vibrance,
  hue-selective orange/teal/green boosts, split toning, black level, clarity,
  Purkinje shift.
* **Lens**: vignette, chromatic aberration, film grain.

---

## HDR

When the HDR mod defines `HDR_MOD_INSTALLED` and `HDR_ENABLED`:

* `display_eotf()` switches to the accurate sRGB curve and scales by
  `HdrGamePaperWhiteBrightness / HdrUIBrightness`.
* Dithering is disabled (the display has the precision).
* Scene buffers stay `RGBA16F`, so the grade and tonemap operate on real HDR
  values all the way to the final encode.

If the mod is absent, nothing changes: the same code path produces an 8-bit
sRGB image.

---

## Deliberately not in 1.0.0

These are real features of the packs Muon is compared to; they are on the
roadmap rather than silently missing:

* Voxel-based coloured lighting (LPV) — needs compute and a voxel volume.
* Distant Horizons shadow casting for LoD terrain.
* Cloud temporal upscaling (clouds currently render at half resolution every frame).
* Aurora ground lighting and cloud lighting interactions.
* Nether/End-specific weather and fog systems.
* Hand/depth-of-field-aware TAA for the first-person hand.
