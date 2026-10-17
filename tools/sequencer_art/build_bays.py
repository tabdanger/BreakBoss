#!/usr/bin/env python3
"""Face 2's panel bays in brushed metal (Oct 17, Tyrone: no flat grey blocks, everything metal).

The picture had a flat grey slab under the SOUNDS / GENERATE panel, a flat light-grey slab under
the channel rack (the blank block above the first track was part of it) and a smeared patch where
the old Drum Track button was painted out of the bottom rail. This paints all three as brushed
steel in the plate's own grain: the bays sit a little lower than the rail (shadow under their top
and left edge, light on the bottom lip) and the rack bay gets a raised metal cap above its first
track. Run after build_controls.py and before build_finishes.py:

    python3 tools/sequencer_art/build_bays.py BreakBoss.swiftpm
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
path = pkg / "Resources" / "Assets.xcassets" / "SeqPlate.imageset" / "SeqPlate.png"
rng = np.random.default_rng(1714)


def hblur(a, n):
    """Box blur along each row (the brush strokes run sideways)."""
    k = np.ones(n) / n
    return np.apply_along_axis(lambda r: np.convolve(np.pad(r, n, mode="reflect"), k, mode="same")[n:-n], 1, a)


def brushed(w, h, level, spread=0.07):
    """Brushed steel, 0...1: a soft light falling from the top left, long sideways strokes and fine grain."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    v = level + spread * (0.5 - y / max(1, h - 1)) * 0.8
    v += 0.05 * np.exp(-(((x / w) * 0.7 + (y / h) * 0.6 - 0.45) / 0.22) ** 2)     # a sheen across it
    v += rng.normal(0, 0.012, (h, 1))                                                # row to row
    v += hblur(rng.normal(0, 0.06, (h, w)), 41)                                      # long strokes
    v += hblur(rng.normal(0, 0.03, (h, w)), 7)                                       # fine grain
    return np.clip(v, 0, 1)


def to_rgb(v):
    g = v * 255
    return np.stack([g - 1, g, g + 2], axis=2)


def bevel(v, top=0, left=0, bottom=0, right=0, light=False):
    """Shade an edge: recessed (dark top/left, lit bottom) or raised (lit top, dark bottom)."""
    h, w = v.shape
    for i in range(top):
        v[i, :] = v[i, :] * (0.55 + 0.45 * i / top) if not light else np.minimum(1, v[i, :] + 0.25 * (1 - i / top))
    for i in range(left):
        v[:, i] = v[:, i] * (0.6 + 0.4 * i / left)
    for i in range(right):
        v[:, w - 1 - i] = v[:, w - 1 - i] * (0.7 + 0.3 * i / right)
    for i in range(bottom):
        if light:
            v[h - 1 - i, :] = v[h - 1 - i, :] * (0.5 + 0.5 * i / bottom)
        else:
            v[h - 1 - i, :] = np.minimum(1, v[h - 1 - i, :] + 0.18 * (1 - i / bottom))
    return v


img = Image.open(path).convert("RGBA")
a = np.asarray(img).astype(np.float32)

# the SOUNDS / GENERATE bay (the panel's own metal plates cover most of it)
x0, y0, x1, y1 = 32, 300, 285, 693
v = bevel(brushed(x1 - x0, y1 - y0, 0.66), top=5, left=3, bottom=2)
a[y0:y1, x0:x1, :3] = to_rgb(v)

# the rack bay: the strip by the track grips, the rack, and the cap above the first track
x0, y0, x1, y1 = 285, 300, 537, 691
v = bevel(brushed(x1 - x0, y1 - y0, 0.70), top=5, left=3, bottom=2, right=2)
cap = 38                                          # down to just above the first track (rowsY0 341)
c = bevel(brushed(x1 - x0 - 10, cap, 0.80, spread=0.12), top=2, bottom=3, light=True)
v[4:4 + cap, 5:x1 - x0 - 5] = c
a[y0:y1, x0:x1, :3] = to_rgb(v)

# the bottom rail where the old Drum Track was painted out: carry the clean rail's rows across
x0, x1, y0, y1 = 37, 362, 701, 788
clean = a[y0:y1, 380:575, :3].copy()
fill = np.concatenate([clean, clean[:, ::-1]], axis=1)[:, -(x1 - x0):]   # mirrored, so the strokes run on
# blend into the rail at the right end so there's no seam
t = np.clip((np.arange(x1 - x0) - (x1 - x0 - 24)) / 24, 0, 1)[None, :, None]
a[y0:y1, x0:x1, :3] = fill * (1 - t) + a[y0:y1, x0:x1, :3] * t

Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").save(path)
print("bays painted")
