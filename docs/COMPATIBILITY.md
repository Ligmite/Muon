# Compatibility notes

Muon is written against the Iris shader pack API and is designed to survive
translation to other backends. This document records exactly what that means, and
where the boundaries are.

## Target matrix

| Platform | Version | Status |
|---|---|---|
| Iris (OpenGL) | 1.11.7+mc26.3 | primary target, developed against |
| Minecraft | 26.3 | target |
| Sodium | 0.9.2+mc26.3 | supported |
| Distant Horizons | 3.3.4-26.3 | integrated (`dh_terrain`, `dh_water`) |
| Voxy | 0.2.x | integrated (`voxy.json`, `voxy_*.glsl`) |
| Vitrail (Vulkan) | 0.12.0-beta+mc26.3 | compatibility target |
| OptiFine | — | not targeted; Muon uses Iris-specific behaviour |

## What Muon uses from the API

Only documented, widely supported features:

- `layout(location = N) out` plus `/* RENDERTARGETS: ... */`
- `#include "/path"` with absolute paths from `shaders/`
- `size.buffer.colortexN`, `colortexNFormat`, `colortexNMipmapEnabled`
- `flip.<program>.<buffer>`
- `blend.<program>`
- `program.<name>.enabled`
- `texture.noise` and `texture.<program>.<sampler>` with `TEXTURE_3D`
- `screen`, `profile`, `sliders`

Deliberately **not** used:

| Feature | Why not |
|---|---|
| custom images / SSBOs (`image.`) | Vitrail support is not guaranteed; the pack must run everywhere |
| compute shaders (`*.csh`) | not universally available through the translation path |
| `#extension` / vendor extensions | breaks portability outright |
| `MC_GL_RENDERER_*` workarounds | Muon avoids whatever would need them |
| custom uniforms (`uniform.*` in `shaders.properties`) | derivable values are computed in `MuonFrame` instead, which also keeps the frame block authoritative |

Avoiding custom uniforms is a deliberate portability decision: if a backend
ignores that block of `shaders.properties`, a pack that depends on it renders
black. Muon's derived values (sun direction, light direction, viewport) are
computed from the canonical Iris uniforms inside `muon_frame_build()`, so the
pack degrades to "works" rather than "wrong".

## Distant Horizons

Muon ships `dh_terrain` and `dh_water`, so DH LOD chunks go through the same
geometry stages as vanilla terrain:

- LOD colour and tint become albedo;
- LOD lightmaps drive the block/sky light terms;
- a per-material default table supplies smoothness and F0, because LOD geometry
  has no LabPBR textures;
- optional noise break-up (`DH_NOISE`) prevents the LOD ring from reading as a
  different renderer;
- the shadow cascade and the volumetric fog treat LOD and vanilla geometry
  identically, so there is no visible seam at the render-distance boundary.

`dhDepthTex`, `dhProjection` and friends are declared in
`lib/uniforms/iris.glsl` under `#ifdef DISTANT_HORIZONS` and available for future
use. v0.0.1 does not need them because LOD geometry contributes real g-buffer
data rather than requiring a combined depth buffer.

## Voxy

Voxy generates its own programs around pack-supplied fragment emitters:

- `voxy.json` declares the draw buffers (`1,2,3,4` opaque, `9,10,11`
  translucent), the blending mode, and the uniforms and samplers the generated
  program may touch.
- `voxy_opaque.glsl` and `voxy_translucent.glsl` implement
  `voxy_emitFragment(VoxyFragmentParameters)`.
- `excludeLodsFromVanillaDepth` is enabled so Voxy's LODs do not pollute
  `depthtex0`.

If Voxy is absent, the files are inert.

## Vitrail (Vulkan)

Vitrail translates the pack to SPIR-V/WGSL. Three properties make that survivable:

1. **Explicit version.** Every entry point declares `#version 330 compatibility`
   rather than relying on a default.
2. **No implicit conversions.** The source is written for a translator that does
   not have GLSL's lenient int/float rules: `1.0` never appears as `1`, and
   `float(i)` is always explicit.
3. **One state block.** All runtime state is grouped into a single struct whose
   layout is documented and std140-compatible, which maps onto a descriptor set
   in one step.

The one legacy dependency is unavoidable: the vertex built-ins
(`gl_Vertex`, `gl_Normal`, `gl_ModelViewMatrix`, `gl_NormalMatrix`,
`gl_TextureMatrix[0..1]`, `gl_MultiTexCoord0..1`, `gl_Color`) are how the shader
pack format exposes Minecraft's vertex data. Vitrail supports these; any backend
that does not would need a shim providing the same names from its own vertex
format.

## OptiFine

Not a target. Muon relies on behaviour that Iris defines but OptiFine does not
guarantee — in particular the `flip.` mechanism, `size.buffer` with explicit
pixel dimensions, and `program.<name>.enabled`. It may or may not load.

## Known limits

- **Single hardware shadow cascade.** Iris provides one shadow map per frame, so
  Muon's second cascade is screen-space.
- **Single translucent layer.** The nearest translucent fragment per pixel is
  stored; stacked glass and water behind glass are approximated.
- **Screen-space GI.** Off-screen geometry falls back to the analytic sky.
- **Vanilla cloud renderer disabled.** Muon draws its own; the `clouds=off`
  property is intentional and not a bug.
- **No HDR output yet.** The final pass emits Rec.709 sRGB and lets Iris' colour
  space conversion adapt it. A PQ/HLG-aware path is roadmap.
