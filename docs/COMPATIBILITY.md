# Compatibility

Muon targets Iris first. This page records exactly what is supported, what is
best-effort, and what is still unverified, so nobody has to guess.

---

## Iris

* **Required version: 1.7+.** Muon uses `gbufferPreviousModelView`,
  `gbufferPreviousProjection`, per-program blending, `layout(location)` outputs
  with `RENDERTARGETS`, and non-square buffer sizes.
* **OptiFine:** the pack loads, but the following will not behave correctly:
  history buffers (TAA, RT), per-program blending, and the `RENDERTARGETS`
  convention. Treat OptiFine as unsupported.

### Features Muon relies on

| Feature | Why |
| --- | --- |
| `RENDERTARGETS` + explicit locations | unambiguous for Iris, OptiFine and Vulkan backends |
| `size.buffer.colortexN` | half-resolution AO, fog and clouds |
| `blend.<program>` | premultiplied translucent layer |
| `const bool colortexNClear` in a comment block | keeps TAA and RT history alive |
| `alphaTestRef` | correct cutout behaviour across versions |
| `gbufferPrevious*` matrices | motion vectors for TAA, RT and motion blur |

---

## Distant Horizons

DH support is implemented through the standard Iris DH contract.

Programs provided:

* `dh_terrain` — LoD terrain
* `dh_water` — LoD water (shaded as an opaque surface; see below)
* `dh_generic` — any other DH geometry

What the pack does with DH:

* Grid-snaps LoD vertices relative to `fract(cameraPosition)` so terrain does not
  swim as the camera moves (`program/dh_terrain_vsh.glsl`).
* Reconstructs LoD positions with `dhProjectionInverse` / `dhProjection` in
  `lib/encoding.glsl`, `lib/ao.glsl`, `lib/ssr.glsl`, `lib/pathtracing.glsl` and
  the volumetric passes.
* Uses the nearest of the vanilla depth and `dhDepthTex0` as the scene depth
  (`combined_depth()`, `ao_scene_depth()`, `ssr_scene_depth()`).
* Shades LoD terrain into the same G-buffer, so it receives the same sun, sky,
  AO, fog and clouds as vanilla terrain.

Known limitations:

* DH terrain does not cast shadows into the shadow map.
* DH water is shaded as an opaque surface (blending for `dh_water` is `off`).
  This is deliberate: DH's water pass does not go through the vanilla
  translucent pipeline, and treating it as opaque avoids a second compositor.
* `dhMaterialId` is not used; LoD materials are inferred from the vertex colour.
  This avoids depending on an Iris-internal uniform name that has changed
  between versions.

Disable `DH_BLEND_DEPTH` if a DH version misbehaves with the combined depth.

---

## Voxy

Entry points:

* `voxy_opaque.glsl` — writes buffers `1, 2, 3, 14`
* `voxy_translucent.glsl` — writes buffers `9, 10`
* `voxy.json` — declares those draw buffers, blending, uniforms and samplers

`voxy.json` sets `excludeLodsFromVanillaDepth = true`, matching Iris' Voxy
integration.

**Status: experimental.** Voxy's `VoxyFragmentParameters` ABI is young; this
release reads only the fields that have been stable across Photon's and
Complementary's integrations (`sampledColour`, `tinting`, `face`,
`customId`, `lightMap`). If Voxy changes those, only `voxy_opaque.glsl` and
`voxy_translucent.glsl` need updating.

Water rendered by Voxy's translucent pass has no surface depth available, so it
is composited as glass rather than as refractive water. That is a Voxy
limitation, not a shader bug.

---

## Vitrail (Vulkan backend)

Vitrail is a new Vulkan-based renderer that aims to run Iris shader packs. Muon
is written to be as friendly to it as possible:

* no compute, geometry or tessellation shaders
* no image load/store, no SSBOs
* explicit `RENDERTARGETS` and `layout(location)` outputs
* no `gl_FragData` / `gl_FragColor`
* all buffers sized by ratio, never by absolute pixel count
* depth treated as `[0, 1]` (Vulkan convention) everywhere

**Status: not verified.** There is no Vitrail build available in the environment
this pack was developed in. The pack should be expected to work; if it does not,
the likely culprits are, in order:

1. fixed-function vertex state (`gl_ModelViewMatrix`, `gl_TextureMatrix[0]`,
   `gl_MultiTexCoord1`) not being emulated
2. `const bool colortexNClear` comment declarations not being parsed
3. per-program `blend.*` rules being ignored

Each of those is isolated: "fixed-function vertex state" lives only in the four
`*.vsh` shared stages, "clear flags" only in `lib/buffers.glsl`, "blending" only
in `shaders.properties`. Fixing them for Vitrail will not touch the rendering
code.

---

## rrtt217 HDR mod

Muon detects the mod through the two macros it defines:

```glsl
#if defined HDR_MOD_INSTALLED && defined HDR_ENABLED
uniform float HdrGamePeakBrightness;
uniform float HdrGamePaperWhiteBrightness;
uniform float HdrGameMinimumBrightness;
uniform float HdrUIBrightness;
```

When present, `display_eotf()` in `lib/color.glsl` switches from the fast sRGB
approximation to the accurate sRGB curve and multiplies by
`HdrGamePaperWhiteBrightness / max(HdrUIBrightness, 1.0)`. The mod then expands
the framebuffer to the display's peak brightness. This is the same contract used
by Photon's HDR fork.

Behaviour:

* 8-bit output keeps dithering; HDR output does not (it would be visible as
  noise in the highlights).
* Scene buffers stay `RGBA16F` with or without the mod (`HDR_USE_FP16` is kept
  as a forward-compatible switch).
* Paper-white changes propagate live because the ratio is read per frame.

---

## Mod interactions

| Mod | Effect |
| --- | --- |
| Sodium | recommended, no interaction |
| Indium / FRAPI | fine; translucent custom geometry uses the vanilla pipeline |
| Distant Horizons | see above |
| Voxy | see above |
| Photonics | not integrated; `PHOTONICS` macros are not defined |
| Iris `CUSTOM_IMAGES` | optional only, not required |
| `ENTITY_TRANSLUCENT` | optional only, not required |

---

## Resource packs

* **labPBR** is the recommended format (`RESOURCEPACK_SUPPORT = 2`).
* Legacy `_s` maps work with `RESOURCEPACK_SUPPORT = 1`.
* No resource pack is required: vanilla textures get hand-tuned material
  defaults from `lib/materials.glsl`.
* POM uses albedo luminance as its height field, so no height map is needed, but
  a pack with strong contrast gives better depth.

---

## Known limitations

* Screen-space effects (SSR, RT, contact shadows) cannot see geometry that is
  off-screen. This is inherent to the technique.
* The path tracer is screen-space, not hardware ray traced. It inherits the same
  limitation.
* The first-person hand is not included in TAA motion vectors; fast movement can
  ghost slightly on the hand.
* The End and Nether use simplified skies (no atmospheric integration, no
  volumetric cloud layers in the Nether).
* Shadow casting for DH/Voxy LoD geometry is not implemented.
