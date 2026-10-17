#!/usr/bin/env python3
"""Face 2 (the sequencer) in the same finish as Face 1 (Oct 16, Tyrone: "the Mode should always match").

Reads SeqPlate.png and SeqRow.png (platinum, from build_controls.py) and writes
  SeqPlate_modern / SeqRow_modern    black (charcoal metal, white logo and labels)
  SeqPlate_vintage / SeqRow_vintage  cream
  SeqPlate_texture / SeqRow_texture  royal blue
Only the metal is recoloured (light, unsaturated pixels); the dark panels, the step grid and the
coloured bits keep their colours. Run after build_controls.py:

    python3 tools/sequencer_art/build_finishes.py BreakBoss.swiftpm
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image

pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
assets = pkg / "Resources" / "Assets.xcassets"

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

def finish(img, kind):
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    rgb = a[..., :3]
    lum = rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    w = smoothstep(55, 115, lum) * (1 - smoothstep(28, 70, sat))      # metal only
    n = lum / 255.0
    if kind == "modern":
        t = lum * 0.17 + 6
        target = np.stack([t, t, t + 1], axis=2)
    elif kind == "vintage":
        t = np.minimum(255, lum * 1.08)
        target = np.stack([t * 0.985, t * 0.93, t * 0.80], axis=2)
    elif kind == "texture":
        lo = np.array([4, 40, 100], dtype=np.float32); hi = np.array([40, 120, 200], dtype=np.float32)
        target = lo + (hi - lo) * n[..., None]
        gl = smoothstep(225, 255, lum)[..., None]                      # the bevel highlights stay bright
        target = target * (1 - gl) + np.array([120, 180, 240], dtype=np.float32) * gl
    out = rgb * (1 - w[..., None]) + target * w[..., None]
    a[..., :3] = np.clip(out, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")

def lighten_print(img, original, rects):
    """Black printing on the metal (the logo, PATTERN / KIT) turns white on the black finish.
    How black a pixel is comes from the original (platinum) picture."""
    a = np.asarray(img).astype(np.float32)
    o = np.asarray(original.convert("RGBA")).astype(np.float32)
    for x0, y0, x1, y1 in rects:
        part = a[y0:y1, x0:x1, :3]
        src = o[y0:y1, x0:x1, :3]
        lum = src[..., 0] * 0.299 + src[..., 1] * 0.587 + src[..., 2] * 0.114
        k = (1 - smoothstep(40, 120, lum))[..., None]                    # how black the printing is
        part[:] = part * (1 - k) + np.array([232, 232, 234], dtype=np.float32) * k
        a[y0:y1, x0:x1, :3] = part
    return Image.fromarray(a.astype(np.uint8), "RGBA")

def write(name, img):
    d = assets / f"{name}.imageset"
    d.mkdir(exist_ok=True)
    img.save(d / f"{name}.png")
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

plate = Image.open(assets / "SeqPlate.imageset" / "SeqPlate.png").convert("RGBA")
row = Image.open(assets / "SeqRow.imageset" / "SeqRow.png").convert("RGBA")
header = Image.open(assets / "SeqHeader.imageset" / "SeqHeader.png").convert("RGBA")
PRINT = [(55, 175, 280, 293), (596, 706, 692, 730), (884, 706, 934, 730)]
for kind in ("modern", "vintage", "texture"):
    p = finish(plate, kind)
    if kind == "modern":
        p = lighten_print(p, plate, PRINT)
    write(f"SeqPlate_{kind}", p)
    write(f"SeqRow_{kind}", finish(row, kind))
    write(f"SeqHeader_{kind}", finish(header, kind))
print("finishes written")
