# Testing

Muon is developed against a real instance, not a mock. This document records the
test bench, the procedure, and what "passing" means for each stage.

## Test bench

| Component | Version |
|---|---|
| Launcher | ATLauncher |
| Instance | `test263 iris` (`test263iris`) |
| Minecraft | 26.3 (Fabric) |
| Iris | `iris-fabric-1.11.7+mc26.3.jar` |
| Sodium | `sodium-fabric-0.9.2+mc26.3.jar` |
| Sodium Extra | `sodium-extra-fabric-0.9.5+mc26.3.jar` |
| Reese's Sodium Options | `reeses-sodium-options-fabric-2.2.5+mc26.3.jar` |
| Distant Horizons | `DistantHorizons-3.3.4-26.3-fabric-neoforge.jar` |
| Fabric API | `fabric-api-0.166.0-26.3.jar` |

A second instance (`vulkanshadersbigglobegpuacceleratedchunkbuildingtest`) carries
**Vitrail `0.12.0-beta+mc26.3`** and is the Vulkan compatibility bench.

## Procedure

1. `./build.ps1` (or `build.sh`) to produce `release/Muon-v0.0.1.zip` beside the
   repository (use `-Archive` / `--archive` to freeze a copy into `archive/`).
2. Copy it into the instance's `shaderpacks/` directory.
3. Launch, select **Muon** in *Options → Video Settings → Shader Packs*.
4. Watch the log for shader compilation errors before looking at the image:

   ```
   grep -iE "shader|error|warning" logs/latest.log
   ```

   A pack that compiles cleanly but renders wrong is a logic bug; a pack that
   fails to compile is a syntax bug. The validator catches most of the second
   category before the game is launched, but not all of it — driver-specific
   strictness still exists.

## Acceptance criteria

### Stage 1 — it renders

The first milestone is boring on purpose: the world must appear with correct
geometry, no z-fighting, a sky, and no black or magenta pixels.

- [ ] No shader compilation errors in `latest.log` for any program.
- [ ] Terrain, entities, block entities, the hand and particles all visible.
- [ ] Sky present in all directions, no banding at the horizon.
- [ ] Water visible, displaced, and refracting the bottom.
- [ ] No `NaN` splatter (single-frame white/black flashes).
- [ ] Switching presets Low → PTGI compiles each configuration.

### Stage 2 — it is correct

- [ ] Shadows align with their casters at 12:00, 18:00 and during rain.
- [ ] Foliage shadows sway with the foliage itself.
- [ ] Cloud shadows drift across the ground and match the cloud layer.
- [ ] GTAO only darkens contact regions — no halos on flat ground.
- [ ] SSR only appears on reflective surfaces and fades at the screen edge.
- [ ] Water reflection is consistent with the sky above the horizon.
- [ ] A moving camera produces no ghosting; a sprinting mob leaves no trail.
- [ ] Exposure adapts when walking from a cave into daylight and back.
- [ ] Rain leaves the ground progressively wet, and dries out afterwards.
- [ ] No visible seam between vanilla chunks and Distant Horizons LODs.

### Stage 3 — it is fast

Measured at 1920×1080 with the default High preset:

- [ ] Desktop GPU with the render distance at 12 chunks: interactive.
- [ ] Low preset at 32 chunks with DH: interactive.
- [ ] No single pass dominating frame time beyond the shadow and volumetric
      chains, which are the intended cost centres.

## Known regressions to watch for

| Symptom | Likely cause |
|---|---|
| Sky is black but terrain is lit | `deferred1` rejected the far-depth test |
| Water shows the sky colour everywhere | refraction offset clamping to zero |
| Everything is washed out | exposure target inverted in `composite` |
| Shadows crawl when standing still | TAA jitter not applied in the shadow pass |
| Cloud layer is flat grey | 3D noise not bound for `deferred1` |
| Distant terrain is unlit | `dh_terrain` missing or its material table wrong |
| Flicker on the second shadow tier | `SHADOW_SSRT_DISTANCE` overlapping the map fade |

## Static validation

Run before every commit:

```bash
python tools/validate.py
python tools/gen_wrappers.py --check
python tools/gen_noise.py --check   # verifies the assets match the generator
```

`validate.py` exits non-zero on any error, which is what the CI workflow gates on.
