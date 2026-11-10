#!/usr/bin/env python3
"""
Muon Shaders - blue noise texture generator.

Generates shaders/textures/noise.png, the tiled blue noise volume sampled by
`noisetex`. The algorithm is void-and-cluster (Ulichney 1993) on a small
toroidal tile which is then tiled up to the requested resolution. Tiling keeps
the spectrum blue and, because the Gaussian filter is periodic, the seams are
not visible.

Channels:
    R  blue noise, used for dithering and ray jitter
    G  decorrelated blue noise (separate ranking)
    B  decorrelated blue noise
    A  white noise (for effects that want no structure)

Run: python tools/generate_noise.py [size]
"""

from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image


def periodic_gaussian(size: int, sigma: float) -> np.ndarray:
    coords = np.arange(size)
    dx = np.minimum(coords, size - coords)
    xx, yy = np.meshgrid(dx, dx, indexing="ij")
    kernel = np.exp(-(xx * xx + yy * yy) / (2.0 * sigma * sigma))
    return kernel


def blue_noise_tile(size: int, sigma: float, iterations: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    kernel = periodic_gaussian(size, sigma / (size / 64.0))

    # Start from a random half-filled pattern
    pattern = np.zeros((size, size), dtype=np.float64)
    flat_indices = rng.permutation(size * size)[: size * size // 2]
    pattern.flat[flat_indices] = 1.0

    def energy(p: np.ndarray) -> np.ndarray:
        # Periodic convolution via FFT
        kf = np.fft.rfft2(kernel)
        pf = np.fft.rfft2(p)
        return np.fft.irfft2(kf * pf, s=p.shape)

    for _ in range(iterations):
        e = energy(pattern)

        cluster = np.argmax(np.where(pattern > 0.5, e, -np.inf))
        pattern.flat[cluster] = 0.0

        e = energy(pattern)
        void = np.argmin(np.where(pattern < 0.5, e, np.inf))
        pattern.flat[void] = 1.0

    # Rank all pixels by their converged energy to produce a uniform histogram
    e = energy(pattern)
    order = np.argsort(e.ravel())
    ranks = np.empty(size * size, dtype=np.float64)
    ranks[order] = np.arange(size * size) / float(size * size - 1)
    return ranks.reshape(size, size)


def tile_up(tile: np.ndarray, size: int) -> np.ndarray:
    reps = size // tile.shape[0]
    out = np.zeros((size, size), dtype=np.float64)

    for y in range(reps):
        for x in range(reps):
            block = tile
            if (x + y) % 2 == 1:
                block = np.rot90(block, 1)
            if (x * 3 + y) % 3 == 1:
                block = np.fliplr(block)
            out[y * tile.shape[0] : (y + 1) * tile.shape[0],
                x * tile.shape[1] : (x + 1) * tile.shape[1]] = block

    return out


def main() -> int:
    size = int(sys.argv[1]) if len(sys.argv) > 1 else 256
    tile_size = 64

    print(f"generating {size}x{size} blue noise (tile {tile_size})")

    red = tile_up(blue_noise_tile(tile_size, 1.6, 600, 1), size)
    green = tile_up(blue_noise_tile(tile_size, 1.6, 600, 2), size)
    blue = tile_up(blue_noise_tile(tile_size, 1.6, 600, 3), size)

    rng = np.random.default_rng(7)
    alpha = rng.random((size, size))

    data = np.stack([red, green, blue, alpha], axis=-1)
    data = np.clip(data * 255.0 + 0.5, 0, 255).astype(np.uint8)

    root = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "shaders", "textures")
    os.makedirs(root, exist_ok=True)
    path = os.path.join(root, "noise.png")

    Image.fromarray(data, mode="RGBA").save(path, optimize=True)
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
