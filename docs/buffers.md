# Render targets and buffer layout

Muon uses all sixteen colortex targets. This document is the contract between the
passes, `shaders.properties` and any future native backend: a render target is
allocated once, written by exactly one stage, and read by the stages that name it.

## Colour targets

| Target | Format | Size | Written by | Contents |
|---|---|---|---|---|
| `colortex0` | RGBA16F | full | `deferred1`, `deferred2`, `composite3`, `composite6` | HDR scene colour |
| `colortex1` | RGBA16F | full | geometry | opaque albedo `.rgb`, F0 `.a` |
| `colortex2` | RGBA16F | full | geometry | view-space normal `.xyz`, smoothness `.a` |
| `colortex3` | RGBA16F | full | geometry | linear depth `.r`, material id `.g`, emission `.b`, porosity `.a` |
| `colortex4` | RGBA8 | full | geometry | block light `.r`, sky light `.g`, vertex AO `.b`, flags `.a` |
| `colortex5` | RGBA16F | full | `composite3` | TAA history |
| `colortex6` | RGBA16F | full + mips | `composite5` | bloom pyramid base |
| `colortex7` | RGBA16F | full | `composite1` | screen-space GI radiance |
| `colortex8` | RGBA16F | full | `composite2` | velocity `.rg`, linear depth `.b`, material `.a` |
| `colortex9` | RGBA16F | full | translucent geometry | albedo `.rgb`, F0 `.a` |
| `colortex10` | RGBA16F | full | translucent geometry | normal `.xyz`, smoothness `.a` |
| `colortex11` | RGBA16F | full | translucent geometry | material `.r`, opacity `.g`, emission `.b`, depth `.a` |
| `colortex12` | RGBA16F | 64×64 | `composite` | adapted exposure `.r`, average luminance `.g` |
| `colortex13` | RGBA16F | full | `composite1` | reflection radiance `.rgb`, confidence `.a` |
| `colortex14` | RGBA16F | half | `deferred` | occlusion `.r`, octahedral bent normal `.gb` |
| `colortex15` | RGBA16F | full | `composite2`, `composite4` | combined scene |

`colortex6` enables mipmapping. `colortex12` is a fixed 64×64 reduction target.
`colortex14` is half resolution; the deferred stage upsamples it with a
depth-aware tap pattern.

### Why translucent geometry has its own targets

If water wrote into `colortex1..4` it would erase the surface behind it, and the
deferred stage would have no lit background to refract. Keeping the two layers
separate is what makes refraction, Beer-Lambert extinction and depth-based colour
physically meaningful at all.

### Buffer flips

Four passes read the target they write. Iris cannot bind one texture as both a
sampler and a draw attachment, so each of these is flipped:

```
flip.deferred2.colortex0  = true
flip.composite.colortex12 = true
flip.composite1.colortex7 = true
flip.composite3.colortex5 = true
```

## Depth textures

| Sampler | Contents |
|---|---|
| `depthtex0` | opaque geometry only |
| `depthtex1` | opaque + translucent |
| `depthtex2` | opaque + translucent + hand |

Translucent presence is detected by comparing `depthtex1` against `depthtex0` in
metric units, not in raw depth, so the test is independent of the near/far planes.

Geometry stages store *linear* depth in `colortex3.r` (distance along the camera
axis). Every shading pass reconstructs positions from that value rather than from
the depth buffer, so the reconstruction can never disagree with the material in
the g-buffer.

## `MuonFrame` — runtime state block

768 bytes, std140 layout, every member 16-byte aligned. Declared once in
`lib/uniforms/frame.glsl` and shared by the Iris adapter path and the native UBO
path.

| Offset | Size | Member | Contents |
|---|---|---|---|
| 0 | 64 | `view` | model-view matrix |
| 64 | 64 | `viewInverse` | inverse model-view |
| 128 | 64 | `projection` | projection matrix |
| 192 | 64 | `projectionInverse` | inverse projection |
| 256 | 64 | `previousView` | previous frame model-view |
| 320 | 64 | `previousProjection` | previous frame projection |
| 384 | 64 | `shadowView` | shadow model-view |
| 448 | 64 | `shadowProjection` | shadow projection |
| 512 | 16 | `cameraPositionTime` | `xyz` position, `w` frame time |
| 528 | 16 | `previousCameraPosition` | `xyz` position, `w` frame time counter |
| 544 | 16 | `viewport` | `xy` pixels, `zw` reciprocal |
| 560 | 16 | `depthParams` | `x` near, `y` far, `z` 1/far |
| 576 | 16 | `sunDirection` | unit vector toward the sun, `w` sun angle |
| 592 | 16 | `moonDirection` | unit vector toward the moon, `w` moon phase |
| 608 | 16 | `lightDirection` | active light, `w` eye-in-water |
| 624 | 16 | `upDirection` | `xyz` up, `w` eye altitude |
| 640 | 16 | `weather` | rain, wetness, thunder, darkness |
| 656 | 16 | `time` | frame counter, world time, world day, star angle |
| 672 | 16 | `climate` | temperature, rainfall, biome category, precipitation |
| 688 | 16 | `playerState` | sky light, block light, night vision, blindness |
| 704 | 16 | `fogColor` | fog colour, `w` screen brightness |
| 720 | 16 | `shadowParams` | texel size, near, far (shadow distance), fade |
| 736 | 16 | `ambient` | alpha test ref, sea level, held light value |
| 752 | 16 | `skyTint` | sky colour, `w` end flash intensity |

Directions are stored in **world space**; the adapter converts Iris' view-space
`sunPosition` / `moonPosition` / `upPosition` through `gbufferModelViewInverse`.

## `MuonSettings` — compile-time block

User options are compile-time constants, not uniforms, because toggling one
recompiles the pack. In SPIR-V terms they are specialisation constants, so they
live in `lib/uniforms/settings.glsl` as `const` values with a documented mapping:

```glsl
const int MUON_GTAO_STEPS = 6;      // -> @id(3) override gtao_steps: i32 = 6;
const float MUON_CLOUD_ALTITUDE = 320.0;
```

A backend port rewrites that one file instead of hunting magic numbers across
every pass.

## Adding a target

1. Add the format, size and any flip to `shaders/shaders.properties`.
2. Add the sampler declaration to `lib/uniforms/samplers.glsl`.
3. Document it in the table above.
4. Reference the index through the `MUON_TARGET_*` constants in
   `lib/common/constants.glsl` rather than a bare number.
