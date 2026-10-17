"""The faceplates' metal, shared by build_finishes.py (Face 2) and ../faceplate_art/build_depth.py (Face 1).

Oct 17, Tyrone: Face 2 has to wear exactly Face 1's finish (Vintage cream, Texture blue, same colour,
texture and detail), the edges of the controls in that colour, and every plate "hyper realistic":
more depth and texture. Everything here works on float RGB arrays (0...255) and needs numpy + scipy.
"""
import numpy as np
from scipy import ndimage

# Face 1's plate colours, measured off Plate_vintage / Plate_texture (flat areas of the border).
CREAM = np.array([234, 222, 192], dtype=np.float32)
CREAM_HI = np.array([252, 247, 232], dtype=np.float32)
BLUE = np.array([12, 88, 166], dtype=np.float32)
BLUE_HI = np.array([125, 188, 246], dtype=np.float32)
REF_LUM = 188.0          # the platinum metal's usual brightness (Face 2's bottom rail)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def lum(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def sat(rgb):
    return rgb.max(axis=2) - rgb.min(axis=2)


def metal_weight(rgb):
    """How much a pixel of the platinum picture is bare metal (light and grey), 0...1."""
    return smoothstep(55, 115, lum(rgb)) * (1 - smoothstep(28, 70, sat(rgb)))


def recolor(rgb, kind):
    """Platinum metal in another finish, keeping its light and shade."""
    L = lum(rgb)
    if kind == "platinum":
        return rgb.copy()
    if kind == "modern":
        t = L * 0.17 + 6
        return np.stack([t, t, t + 1], axis=2)
    base, hi = (CREAM, CREAM_HI) if kind == "vintage" else (BLUE, BLUE_HI)
    k = (L / REF_LUM)[..., None]
    if kind == "texture":
        k = k ** 1.15
    target = base * k
    gl = smoothstep(212, 252, L)[..., None]                 # the bevel highlights catch the light
    return target * (1 - gl) + hi * gl


def finish(rgb, kind, w=None):
    """Recolour only the metal (w from the platinum picture); dark panels and coloured parts stay."""
    if w is None:
        w = metal_weight(rgb)
    return rgb * (1 - w[..., None]) + recolor(rgb, kind) * w[..., None]


# MARK: grain

def tolex(h, w, seed, wrap=False):
    """Face 1's Vintage / Texture surface: an embossed pebble grain with a faint wavy pattern, -1...1,
    lit from the top left."""
    rng = np.random.default_rng(seed)
    mode = "wrap" if wrap else "reflect"
    n = rng.normal(0, 1, (h, w)).astype(np.float32)
    fine = ndimage.gaussian_filter(n, 1.1, mode=mode)
    coarse = ndimage.gaussian_filter(rng.normal(0, 1, (h, w)).astype(np.float32), 3.2, mode=mode)
    # the wavy cells: ridges of a smooth field
    field = ndimage.gaussian_filter(rng.normal(0, 1, (h, w)).astype(np.float32), 7, mode=mode)
    field /= field.std() + 1e-6
    waves = np.abs(np.sin(field * 2.6))
    height = fine / (fine.std() + 1e-6) * 0.55 + coarse / (coarse.std() + 1e-6) * 0.3 - waves * 0.5
    gy, gx = np.gradient(ndimage.gaussian_filter(height, 0.6, mode=mode))
    e = gx + gy
    return np.clip(e / (3 * e.std() + 1e-6), -1, 1)


def brushed(h, w, seed):
    """Brushed grain (long sideways strokes and fine scratches), -1...1."""
    rng = np.random.default_rng(seed)
    long = ndimage.uniform_filter1d(rng.normal(0, 1, (h, w)).astype(np.float32), 61, axis=1, mode="reflect")
    fine = ndimage.uniform_filter1d(rng.normal(0, 1, (h, w)).astype(np.float32), 9, axis=1, mode="reflect")
    rows = rng.normal(0, 1, (h, 1)).astype(np.float32)
    g = long / (long.std() + 1e-6) * 0.5 + fine / (fine.std() + 1e-6) * 0.35 + rows * 0.25
    return np.clip(g / 3, -1, 1)


def grain(kind, h, w, seed):
    return tolex(h, w, seed) if kind in ("vintage", "texture") else brushed(h, w, seed)


GRAIN_AMOUNT = {"platinum": 0.07, "modern": 0.12, "vintage": 0.06, "texture": 0.17}


# MARK: depth

def light_field(h, w):
    """A soft light from the top left: brighter there, a sheen across the plate, darker at the far corner."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    u, v = x / w, y / h
    f = 1 + 0.07 * (0.5 - (0.6 * u + 0.4 * v))
    f += 0.05 * np.exp(-(((u * 0.8 + v * 0.55) - 0.42) / 0.16) ** 2)
    f -= 0.05 * (np.maximum(0, np.abs(u - 0.5) - 0.38) / 0.12) ** 2         # falls off at the ends
    return f


def relief(height, sigma=2.2, gain=26.0):
    """Shading of a height map lit from the top left (y down): + where a slope faces the light."""
    h = ndimage.gaussian_filter(height.astype(np.float32), sigma)
    gy, gx = np.gradient(h)
    return np.clip((gx + gy) * gain, -1, 1)


def contact_shadow(raised, dx=3, dy=5, sigma=4.0):
    """Where a raised part throws its shadow down and right onto what's under it, 0...1."""
    s = ndimage.shift(raised.astype(np.float32), (dy, dx), order=1, mode="nearest")
    return np.clip(ndimage.gaussian_filter(s, sigma) - raised, 0, 1)


def clarity(rgb, sigma=7.0):
    """Local contrast (the detail already in the picture), to add back scaled."""
    blur = np.stack([ndimage.gaussian_filter(rgb[..., c], sigma) for c in range(3)], axis=2)
    return rgb - blur
