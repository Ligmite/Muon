# Options reference

Every option lives in `shaders/settings.glsl` and is surfaced by a screen in
`shaders/shaders.properties`. Boolean options are on when their `#define` is
uncommented; value options carry a `// [..]` enumeration that Iris renders as a
slider.

The tables below group the options the way the in-game menu does.

## World

| Option | Default | Effect |
|---|---|---|
| `WAVING_PLANTS` | on | wind animation for grass, ferns, flowers |
| `WAVING_LEAVES` | on | wind animation for leaves |
| `SWAY_STRENGTH` | 0.55 | global amplitude of foliage motion |
| `WETNESS` | on | rain darkens and polishes exposed surfaces |
| `RAIN_PUDDLES` | on | water film fills low noise minima on flat ground |
| `PUDDLE_STRENGTH` | 1.00 | puddle coverage |
| `SNOW_COVER` | on | snow accumulates on upward faces during snowfall |
| `SNOW_STRENGTH` | 0.85 | snow coverage |
| `RAIN_OPACITY` | 0.45 | visibility of precipitation |

## Lighting

| Option | Default | Effect |
|---|---|---|
| `SHADOW` | on | master shadow switch |
| `SHADOW_SAMPLES` | 16 | PCSS blocker + filter taps |
| `PCSS` | on | percentage-closer soft shadows instead of plain PCF |
| `PCSS_SOFTNESS` | 1.00 | penumbra radius multiplier |
| `SHADOW_SSRT` | on | screen-space shadow cascade past the hardware map |
| `SHADOW_SSRT_STEPS` | 12 | ray-march steps for the second cascade |
| `SHADOW_SSRT_DISTANCE` | 48.0 | reach of the screen-space cascade, metres |
| `CLOUD_SHADOWS` | on | clouds occlude the sun |
| `SUNLIGHT` / `MOONLIGHT` | 1.00 | direct light intensity |
| `AMBIENT_STRENGTH` | 1.00 | sky ambient irradiance |
| `BLOCKLIGHT_STRENGTH` | 1.00 | Minecraft block light |
| `MINIMUM_LIGHT` | 0.008 | floor that keeps caves from clipping to black |
| `BOUNCED_LIGHT` | on | cheap indirect term when the tracer is off |
| `GTAO` / `SSAO` | GTAO on | occlusion kernel selection |
| `GTAO_SLICES` / `GTAO_STEPS` | 3 / 6 | GTAO kernel size |
| `GTAO_RADIUS` | 1.30 | AO radius in metres |
| `SUBSURFACE_SCATTERING` | on | foliage transmission and gather |
| `SSS_STRENGTH` / `SSS_STEPS` / `SSS_RADIUS` | 1.00 / 3 / 0.55 | SSS tuning |

## Sky, atmosphere, clouds

| Option | Default | Effect |
|---|---|---|
| `ATMOSPHERE` | on | Rayleigh + Mie + ozone scattering |
| `ATMOSPHERE_HAZE` | 0.55 | overall aerial perspective; low by design |
| `ATMOSPHERE_MIE` | 0.65 | sun glow strength |
| `SKY_SATURATION` | 1.10 | sky chroma |
| `SKY_GROUND_TINT` | 0.35 | ground bounce colour in the ambient term |
| `SUN_DISC` / `MOON_DISC` / `STARS` | on | celestial elements |
| `SUN_ANGULAR_RADIUS` | 0.70 | apparent sun size |
| `STARS_INTENSITY` | 0.55 | star brightness |
| `CLOUDS` | on | volumetric clouds |
| `CLOUD_STEPS` | 40 | cumulus raymarch steps |
| `CLOUD_LIGHTING_STEPS` | 6 | light-march steps per sample |
| `CLOUD_ALTITUDE` / `CLOUD_THICKNESS` | 320 / 640 | layer geometry, metres |
| `CLOUD_COVERAGE` | 0.42 | sky fraction covered |
| `CLOUD_DENSITY` | 1.00 | optical density |
| `CLOUD_SCALE` | 1.00 | cloud cell size |
| `CLOUD_WIND_SPEED` / `CLOUD_WIND_ANGLE` | 1.00 / 30° | drift |
| `VOLUMETRIC_FOG` | on | volumetric medium |
| `FOG_STEPS` | 12 | fog march steps |
| `FOG_STRENGTH` | 1.00 | fog density |
| `CAVE_FOG` | on | extra density underground |
| `GOD_RAYS` | on | screen-space light shafts |

## Water

| Option | Default | Effect |
|---|---|---|
| `WATER_WAVES` | on | Gerstner wave sum |
| `WATER_EXTRUDE` | on | vertex displacement (off = normal-only waves) |
| `WATER_WAVE_STRENGTH` / `WATER_WAVE_HEIGHT` | 1.00 / 1.00 | amplitude |
| `WATER_WAVE_ITERATIONS` | 3 | wave count (1–5) |
| `WATER_REFRACTION` | on | Snell's-law refraction |
| `WATER_CAUSTICS` | on | animated caustics on the bottom |
| `WATER_FOG` | on | Beer-Lambert extinction and scattering |
| `WATER_ABSORPTION_R/G/B` | 0.320 / 0.060 / 0.045 | extinction coefficients |
| `WATER_SCATTERING` | 0.090 | in-scattering |
| `WATER_REFLECTION_STRENGTH` | 1.00 | reflection weight |

## Materials and reflections

| Option | Default | Effect |
|---|---|---|
| `NORMAL_MAPPING` | on | `_n` normal maps |
| `SPECULAR_MAPPING` | on | LabPBR `_s` decode |
| `EMISSION_STRENGTH` | 1.00 | LabPBR emission |
| `HARDCODED_F0` | on | fallback F0 when a pack ships no `_s` |
| `PARALLAX` | on | parallax occlusion mapping |
| `POM_DEPTH` / `POM_SAMPLES` | 0.16 / 24 | displacement depth and steps |
| `POM_SELF_SHADOW` | on | height-field self-shadowing |
| `SCREENSPACE_REFLECTIONS` | on | SSR for opaque surfaces |
| `SSR_STEPS` / `SSR_REFINE_STEPS` | 24 / 4 | march and refinement |
| `SSR_MAX_DISTANCE` | 96.0 | ray reach, metres |
| `RTGI` | off | screen-space path tracer |
| `RTGI_BOUNCES` | 1 | bounce count (1–3) |
| `RTGI_SAMPLES` / `RTGI_STEPS` | 4 / 16 | rays per pixel and march steps |
| `RTGI_RADIUS` | 6.00 | gather radius, metres |
| `RTGI_DENOISE` | on | bilateral denoiser |

## Post-processing

| Option | Default | Effect |
|---|---|---|
| `TAA` | on | temporal anti-aliasing |
| `TAA_STRENGTH` | 0.90 | history weight |
| `TAA_CLIPPING` | 1.00 | variance clip width |
| `FXAA` | on | used only when TAA is off |
| `TONEMAP_MODE` | 0 (AgX) | 0 AgX, 1 ACES, 2 Reinhard |
| `TONEMAP_EXPOSURE_PRESCALE` | 1.00 | pre-curve exposure |
| `TONEMAP_WHITE_POINT` | 6.00 | Reinhard white point |
| `AUTO_EXPOSURE` | on | eye adaptation |
| `EXPOSURE_BIAS` / `EXPOSURE_SPEED` | 0.00 / 1.00 | adaptation tuning |
| `MANUAL_EXPOSURE` | 0.00 | used when auto exposure is off |
| `BLOOM` | on | mip-pyramid bloom |
| `BLOOM_STRENGTH` / `BLOOM_THRESHOLD` | 0.060 / 1.00 | bloom response |
| `DEPTH_OF_FIELD` | off | thin-lens DoF |
| `DOF_APERTURE` / `DOF_FOCUS` | 1.50 / 0.55 | lens and focus |
| `DOF_AUTOFOCUS` | on | focus from screen centre |
| `LENS_FLARE` | on | ghosts, halo and sun glow |
| `COLOR_GRADING` | on | the warm/vibrant grade |
| `GRADE_SATURATION` / `GRADE_CONTRAST` / `GRADE_TEMPERATURE` | 1.06 / 1.04 / 0.55 | grade primaries |
| `SHARPEN` | on | contrast-adaptive sharpening |
| `VIGNETTE` | on | optical vignette |
| `DITHER` | on | blue-noise dithering before 8-bit output |

## Developer

| Option | Default | Effect |
|---|---|---|
| `DEBUG_VIEW` | 0 | 0 = off; 1 albedo, 2 world normal, 3 depth, 4 AO, 5 reflections, 6 GI, 7 velocity, 8 lightmap, 9 material, 10 exposure, 11 bloom |

## Adding an option

1. Add the `#define` to `shaders/settings.glsl`, with a `// [..]` enumeration for
   value options.
2. Reference it from a screen (or a sub-screen) in `shaders/shaders.properties`.
3. Add it to the `sliders` list if it is numeric.
4. Add a `const` alias in `lib/uniforms/settings.glsl` if the pass should not
   embed the macro directly.
5. Add translations to `shaders/lang/en_us.lang`.
6. Run `python tools/validate.py` — it fails if a screen mentions an option that
   does not exist.
