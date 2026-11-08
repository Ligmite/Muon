# Changelog

## 0.4.3

- Stronger water normals, much stronger mirror/refraction distortion, a broader
  sun glint and subtle crest foam so waves read at a glance.
- Cloud columns vary in base (±95 blocks) and thickness (55–145%), with coarser
  billow/erosion to remove the noisy surface.
- Lens flare is faded by sun centring and screen edge, and is weaker by default.

## 0.4.2

- Fixed the LUT atlas sampling: red is now sampled at texel centres instead of
  slice edges, so white no longer turns teal and blue water no longer turns
  pink. `Use LUT` defaults off until a real LUT is installed.
- Added a toggleable lens flare (sun halo, anamorphic streak, four ghosts).
- Enlarged the sun disc to about 2.5° and widened its halo.
- Cloud columns now vary in base/thickness; the deck is no longer a level slab.
- Water is noise-led (two swells + three chop scales); the directional
  cross-grid is gone, and normals fade by pixel footprint at distance.
- Reduced green saturation; auto exposure now uses the eased camera light, not a
  screen average, so it does not pump while walking.

## 0.4.1

- Bloom is thresholded to HDR highlights, so a bright cloud no longer carries
  its own moving glow; added a sun-space halo.

## 0.4.0

- Added display-referred LUT support (identity atlas, `.cube` converter).
- Smaller, separated cumulus; stronger cloud shadowing.
- Pixel-footprint fade for distant water.
- Ambient floor for shaded trunks.

## 0.3.0

- Cloud coverage chart with real gaps, 3D billow erosion and a light march.
- Brighter clear-day sky with dithering.
- Warmer, higher-contrast grade.
- Cloud-shadow chart on terrain.

## 0.2.0

- First public Muon build: real shadow map, water/cloud rework, rewritten grade
  and Muon namespace.

## 0.1.0

- Initial port of the look to Horizon's WGSL API.
