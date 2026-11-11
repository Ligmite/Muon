#!/usr/bin/env python3
"""
Muon Shaders - tools/gen_noise.py

Generates the two noise assets the pack ships:

  shaders/image/noise.png          512x512 RGBA, spectrally shaped (blue) noise
                                   used for dithering, ray offsets and grain.
  shaders/image/cloud_noise_3d.dat 64^3 R8, tileable Perlin-Worley base volume.
  shaders/image/worley_3d.dat      32^3 R8, tileable Worley fBm detail volume.

Evaluating Perlin-Worley inside a 40-step cloud march would cost 27 Worley
cells per sample per octave. Baking it once here is the difference between a
cloud layer that runs at 60 fps and one that does not run at all.

All volumes are seamless: the lattice periods divide the texture size, so the
sampler's REPEAT wrap has no visible seam.

Usage:
    python tools/gen_noise.py
"""

from __future__ import annotations

import argparse
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
IMAGE_DIR = ROOT / "shaders" / "image"

RNG = np.random.default_rng(0x4D554F4E)  # "MUON"


# ------------------------------------------------------------------------------
#  2D noise texture
# ------------------------------------------------------------------------------

def gaussian_blur_2d(field: np.ndarray, sigma: float) -> np.ndarray:
    """Small separable Gaussian blur with wrap-around (tileable)."""
    radius = max(1, int(round(sigma * 3)))
    offsets = np.arange(-radius, radius + 1)
    kernel = np.exp(-(offsets**2) / (2.0 * sigma * sigma))
    kernel /= kernel.sum()

    height, width = field.shape
    padded = np.pad(field, radius, mode="wrap")

    tmp = np.zeros((height + 2 * radius, width))
    for i, _ in enumerate(offsets):
        tmp += padded[:, i : i + width] * kernel[i]

    out = np.zeros((height, width))
    for i, _ in enumerate(offsets):
        out += tmp[i : i + height, :] * kernel[i]

    return out


def rank_normalise(field: np.ndarray) -> np.ndarray:
    """Maps values onto a uniform [0,1) distribution by rank."""
    flat = field.ravel()
    order = flat.argsort()
    ranks = np.empty_like(order, dtype=np.float64)
    ranks[order] = np.arange(flat.size)
    return (ranks / (flat.size - 1.0)).reshape(field.shape)


def blue_noise(size: int, iterations: int = 4) -> np.ndarray:
    white = RNG.random((size, size))
    field = white
    # Repeated high-pass shaping pushes energy towards high frequencies, which
    # is what removes the low-frequency clumps that make dithering visible.
    for _ in range(iterations):
        field = field + 0.65 * (field - gaussian_blur_2d(field, 1.6))
        field = rank_normalise(field)
    return field


def bayer_matrix(size: int) -> np.ndarray:
    matrix = np.array([[0]], dtype=np.int64)
    while matrix.shape[0] < size:
        matrix = np.block(
            [
                [4 * matrix + 0, 4 * matrix + 2],
                [4 * matrix + 3, 4 * matrix + 1],
            ]
        )
    return matrix / float(matrix.size)


def write_noise_png(size: int) -> None:
    blue = blue_noise(size)
    white = RNG.random((size, size))

    bayer = bayer_matrix(16)
    tiled = np.tile(bayer, (size // 16, size // 16))
    # Ordered pattern perturbed by blue noise: stable in screen space, no banding.
    ordered = rank_normalise(tiled + 0.35 * blue)

    wave = 0.5 + 0.5 * np.sin(np.arange(size) / size * 2.0 * np.pi * 7.0)
    worley_column = np.tile(wave.reshape(-1, 1), (1, size))

    rgba = np.dstack(
        [
            (blue * 255.0).astype(np.uint8),
            (white * 255.0).astype(np.uint8),
            (ordered * 255.0).astype(np.uint8),
            (worley_column * 255.0).astype(np.uint8),
        ]
    )
    Image.fromarray(rgba, mode="RGBA").save(IMAGE_DIR / "noise.png", optimize=True)


# ------------------------------------------------------------------------------
#  3D noise volumes
# ------------------------------------------------------------------------------

def smoothstep(t: np.ndarray) -> np.ndarray:
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)


def perlin_3d(size: int, period: int) -> np.ndarray:
    """Tileable gradient noise with a lattice period dividing `size`."""
    coords = np.arange(size) * (period / size)
    x, y, z = np.meshgrid(coords, coords, coords, indexing="ij")

    cell = np.floor([x, y, z])
    frac = np.array([x - cell[0], y - cell[1], z - cell[2]])
    ix = cell[0].astype(np.int64) % period
    iy = cell[1].astype(np.int64) % period
    iz = cell[2].astype(np.int64) % period

    def gradient(cx: np.ndarray, cy: np.ndarray, cz: np.ndarray) -> np.ndarray:
        # Deterministic pseudo-random unit gradients per lattice point.
        h = (cx * 374761393 + cy * 668265263 + cz * 2147483647) & 0xFFFFFFFF
        h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
        angle = (h & 0xFFFF) / 65535.0 * 2.0 * np.pi
        height = ((h >> 16) & 0xFF) / 255.0 * 2.0 - 1.0
        radius = np.sqrt(np.maximum(1.0 - height * height, 0.0))
        return np.array([np.cos(angle) * radius, np.sin(angle) * radius, height])

    total = np.zeros((size, size, size))
    u = smoothstep(frac[0])
    v = smoothstep(frac[1])
    w = smoothstep(frac[2])

    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                g = gradient(ix + dx, iy + dy, iz + dz)
                offset_x = frac[0] - dx
                offset_y = frac[1] - dy
                offset_z = frac[2] - dz
                dot = g[0] * offset_x + g[1] * offset_y + g[2] * offset_z
                wx = u if dx else 1.0 - u
                wy = v if dy else 1.0 - v
                wz = w if dz else 1.0 - w
                total += dot * wx * wy * wz

    return total


def worley_3d(size: int, cells: int, seed: int) -> np.ndarray:
    """Tileable Worley F1 distance, normalised to [0,1]."""
    rng = np.random.default_rng(seed)
    feature = rng.random((cells, cells, cells, 3))

    coords = (np.arange(size) + 0.5) * (cells / size)
    gx, gy, gz = np.meshgrid(coords, coords, coords, indexing="ij")
    base = np.floor([gx, gy, gz]).astype(np.int64)
    local = np.array([gx - base[0], gy - base[1], gz - base[2]])

    best = np.full((size, size, size), 1.0e9)
    for dz in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                cx = (base[0] + dx) % cells
                cy = (base[1] + dy) % cells
                cz = (base[2] + dz) % cells
                point = feature[cx, cy, cz]
                delta = point[..., 0] - (local[0] + dx)
                dy2 = point[..., 1] - (local[1] + dy)
                dz2 = point[..., 2] - (local[2] + dz)
                distance = delta * delta + dy2 * dy2 + dz2 * dz2
                np.minimum(best, distance, out=best)

    return np.sqrt(best)


def normalise_volume(volume: np.ndarray) -> np.ndarray:
    low = np.percentile(volume, 0.5)
    high = np.percentile(volume, 99.5)
    return np.clip((volume - low) / max(high - low, 1.0e-6), 0.0, 1.0)


def write_cloud_volume(size: int = 64) -> None:
    """Perlin-Worley base shape: Perlin modulated by an inverted Worley fBm."""
    perlin = normalise_volume(perlin_3d(size, 4))
    print("  perlin done")

    worley_low = normalise_volume(worley_3d(size, 4, 11))
    worley_mid = normalise_volume(worley_3d(size, 8, 12))
    worley_high = normalise_volume(worley_3d(size, 16, 13))
    print("  worley done")

    worley_fbm = worley_low * 0.625 + worley_mid * 0.25 + worley_high * 0.125
    worley_fbm = normalise_volume(worley_fbm)

    # Remap Perlin through the Worley fBm: the classic Perlin-Worley blend.
    perlin_worley = normalise_volume(perlin) * (1.0 - worley_fbm) + \
        (1.0 - worley_fbm) * 0.0
    perlin_worley = normalise_volume(perlin * 0.65 + (1.0 - worley_fbm) * 0.55)

    # Widen the histogram slightly so that the coverage remap in the shader has
    # headroom at both ends.
    shaped = np.clip(perlin_worley**1.15, 0.0, 1.0)
    data = (shaped * 255.0 + 0.5).astype(np.uint8)
    (IMAGE_DIR / "cloud_noise_3d.dat").write_bytes(data.tobytes())
    print(f"  cloud_noise_3d.dat: {data.size} bytes ({size}^3)")


def build_cloud_bytes(size: int = 64) -> bytes:
    perlin = normalise_volume(perlin_3d(size, 4))
    worley_low = normalise_volume(worley_3d(size, 4, 11))
    worley_mid = normalise_volume(worley_3d(size, 8, 12))
    worley_high = normalise_volume(worley_3d(size, 16, 13))
    worley_fbm = normalise_volume(worley_low * 0.625 + worley_mid * 0.25 + worley_high * 0.125)
    perlin_worley = normalise_volume(perlin * 0.65 + (1.0 - worley_fbm) * 0.55)
    shaped = np.clip(perlin_worley**1.15, 0.0, 1.0)
    return (shaped * 255.0 + 0.5).astype(np.uint8).tobytes()


def build_detail_bytes(size: int = 32) -> bytes:
    low = normalise_volume(worley_3d(size, 4, 23))
    mid = normalise_volume(worley_3d(size, 8, 24))
    high = normalise_volume(worley_3d(size, 16, 25))
    fbm = low * 0.55 + mid * 0.28 + high * 0.17
    detail = np.clip(1.0 - normalise_volume(fbm), 0.0, 1.0)
    return (detail * 255.0 + 0.5).astype(np.uint8).tobytes()


def write_detail_volume(size: int = 32) -> None:
    """Inverted Worley fBm used to erode cloud edges."""
    low = normalise_volume(worley_3d(size, 4, 23))
    mid = normalise_volume(worley_3d(size, 8, 24))
    high = normalise_volume(worley_3d(size, 16, 25))

    fbm = low * 0.55 + mid * 0.28 + high * 0.17
    detail = np.clip(1.0 - normalise_volume(fbm), 0.0, 1.0)
    data = (detail * 255.0 + 0.5).astype(np.uint8)
    (IMAGE_DIR / "worley_3d.dat").write_bytes(data.tobytes())
    print(f"  worley_3d.dat: {data.size} bytes ({size}^3)")


def build_noise_array(size: int) -> np.ndarray:
    """Same pipeline as write_noise_png, returned instead of written."""
    blue = blue_noise(size)
    white = RNG.random((size, size))

    bayer = bayer_matrix(16)
    tiled = np.tile(bayer, (size // 16, size // 16))
    ordered = rank_normalise(tiled + 0.35 * blue)

    wave = 0.5 + 0.5 * np.sin(np.arange(size) / size * 2.0 * np.pi * 7.0)
    worley_column = np.tile(wave.reshape(-1, 1), (1, size))

    return np.dstack(
        [
            (blue * 255.0).astype(np.uint8),
            (white * 255.0).astype(np.uint8),
            (ordered * 255.0).astype(np.uint8),
            (worley_column * 255.0).astype(np.uint8),
        ]
    )


def check() -> int:
    """Verifies the committed assets match what this generator produces."""
    failures = 0

    expected_png = build_noise_array(512)
    png_path = IMAGE_DIR / "noise.png"
    if not png_path.exists():
        print(f"  MISSING {png_path}")
        failures += 1
    else:
        actual = np.array(Image.open(png_path).convert("RGBA"))
        if actual.shape != expected_png.shape or not np.array_equal(actual, expected_png):
            print(f"  STALE {png_path}")
            failures += 1

    import io

    buffer = io.BytesIO()
    write_cloud_bytes = build_cloud_bytes(64)
    cloud_path = IMAGE_DIR / "cloud_noise_3d.dat"
    if not cloud_path.exists() or cloud_path.read_bytes() != write_cloud_bytes:
        print(f"  STALE {cloud_path}")
        failures += 1

    detail_bytes = build_detail_bytes(32)
    detail_path = IMAGE_DIR / "worley_3d.dat"
    if not detail_path.exists() or detail_path.read_bytes() != detail_bytes:
        print(f"  STALE {detail_path}")
        failures += 1

    if failures:
        print(f"{failures} noise asset(s) out of date; run tools/gen_noise.py")
        return 1
    print("noise assets are up to date")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify assets instead of writing them")
    args = parser.parse_args()

    if args.check:
        return check()

    IMAGE_DIR.mkdir(parents=True, exist_ok=True)

    print("generating 2D noise texture...")
    write_noise_png(512)

    print("generating 3D cloud volume (this takes a few seconds)...")
    write_cloud_volume(64)

    print("generating 3D detail volume...")
    write_detail_volume(32)

    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
