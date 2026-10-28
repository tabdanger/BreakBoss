#!/usr/bin/env python3
"""Texture's GATED REVERB knob is printed just REVERB (Tyrone, Oct 28 2026: it's a plate now).

The new Texture plate already prints REVERB as the second word of GATED REVERB, so the label is
taken off (a patch stretched between the clean plate on its four sides, with the plate's grain)
and the plate's own REVERB lettering, as a difference from the plate behind it, is set back
centred where the whole label was. Nothing is drawn from a font. Runs once: skips a plate whose
label is already one word.

    python3 tools/faceplate_art/face1/rename_reverb.py BreakBoss.swiftpm
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).parent
pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
FILES = [HERE / "Face1_Texture.png", pkg / "Resources" / "Assets.xcassets" / "Plate_texture.imageset" / "Plate_texture.png"]
SEARCH = (960, 1180, 575, 615)      # x0, x1, y0, y1 around the label under the sixth knob


def plate_behind(f, x0, x1, y0, y1):
    """The plate without lettering in [x0, x1) x [y0, y1): Coons patch from its four sides plus grain."""
    def smooth(v):
        p = np.concatenate([v[:1], v[:1], v, v[-1:], v[-1:]], 0)
        return (p[:-4] + p[1:-3] + p[2:-2] + p[3:-1] + p[4:]) / 5
    top = smooth(f[y0 - 2:y0, x0:x1].mean(0))
    bottom = smooth(f[y1:y1 + 2, x0:x1].mean(0))
    left = smooth(np.median(f[y0:y1, x0 - 4:x0], axis=1))
    right = smooth(np.median(f[y0:y1, x1:x1 + 4], axis=1))
    u = ((np.arange(x0, x1) - x0 + 0.5) / (x1 - x0))[None, :, None]
    v = ((np.arange(y0, y1) - y0 + 0.5) / (y1 - y0))[:, None, None]
    c00, c10, c01, c11 = f[y0 - 1, x0 - 1], f[y0 - 1, x1], f[y1, x0 - 1], f[y1, x1]
    fill = ((1 - v) * top[None] + v * bottom[None] + (1 - u) * left[:, None] + u * right[:, None]
            - ((1 - u) * (1 - v) * c00 + u * (1 - v) * c10 + (1 - u) * v * c01 + u * v * c11))
    ref = np.concatenate([f[y0:y1, x0 - 14:x0 - 2], f[y0:y1, x1 + 2:x1 + 14]], 1).mean(2)
    hp = ref[:, 1:-1] - 0.5 * (ref[:, :-2] + ref[:, 2:])
    sd = float(np.clip(np.median(np.abs(hp)) * 1.48 / 1.22, 0.2, 3.0))
    fill += np.random.default_rng(x0 * 31 + y0).normal(0, sd, fill.shape[:2])[..., None]
    return fill


def rename(img):
    f = img.astype(np.float32)
    sx0, sx1, sy0, sy1 = SEARCH
    lum = f[sy0:sy1, sx0:sx1].mean(2)
    ink = lum > np.median(lum) + 0.45 * (lum.max() - np.median(lum))
    rows, cols = np.nonzero(ink.any(1))[0], np.nonzero(ink.any(0))[0]
    y0, y1 = sy0 + rows.min(), sy0 + rows.max() + 1
    x0, x1 = sx0 + cols.min(), sx0 + cols.max() + 1
    # the word gap: the widest run of empty columns inside the label
    on = ink.any(0)[cols.min():cols.max() + 1]
    gaps, run, start = [], 0, 0
    for i, c in enumerate(on):
        if not c:
            if run == 0: start = i
            run += 1
        else:
            if run: gaps.append((run, start, i))
            run = 0
    widest = max(gaps)
    letter_gap = int(np.median([g[0] for g in gaps if g is not widest] or [2]))
    if widest[0] < 2.2 * letter_gap:
        raise ValueError("the label is already one word")
    rx0 = x0 + widest[2]                       # REVERB's first column
    # the box: the letters plus their shadow / glow
    by0, by1, bx0, bx1 = y0 - 4, y1 + 5, x0 - 4, x1 + 5
    behind = plate_behind(f, bx0, bx1, by0, by1)
    word = f[by0:by1, rx0 - 2:bx1] - behind[:, rx0 - 2 - bx0:]
    out = f.copy()
    out[by0:by1, bx0:bx1] = behind
    centre = (x0 + x1) / 2
    w = x1 - rx0
    nx0 = int(round(centre - w / 2)) - 2
    out[by0:by1, nx0:nx0 + word.shape[1]] += word
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


def main():
    for path in FILES:
        rgb = np.asarray(Image.open(path).convert("RGB"))
        try:
            new = rename(rgb)
        except ValueError as e:
            print("skipped", path, "-", e)
            continue
        Image.fromarray(new).save(path)
        print("renamed", path)


if __name__ == "__main__":
    main()
