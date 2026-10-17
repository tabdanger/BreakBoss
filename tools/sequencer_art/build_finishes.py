#!/usr/bin/env python3
"""Face 2 (the sequencer) in the same finish as Face 1 (Oct 16, Tyrone: "the Mode should always match").

Reads SeqPlate.png and SeqRow.png (platinum, from build_controls.py / build_bays.py) and writes
  SeqPlate_platinum / SeqRow_platinum  platinum
  SeqPlate_modern / SeqRow_modern      black (charcoal metal, white logo and labels)
  SeqPlate_vintage / SeqRow_vintage    Face 1's cream
  SeqPlate_texture / SeqRow_texture    Face 1's blue
Only the metal is recoloured (light, unsaturated pixels); the dark panels, the step grid and the
coloured bits keep their colours.

Oct 17 (Tyrone: Face 2 the same colour, texture and detail as Face 1, control edges in the plate's
colour, plates hyper realistic):
  - Vintage / Texture take Face 1's exact cream and blue and its embossed pebble grain; Platinum and
    Modern get a deeper brushed grain.
  - Every plate gets depth: light from the top left with a sheen across it, the dark wells sunk into
    the metal (shadowed top wall, lit bottom lip, a contact shadow and a little occlusion round them)
    and the metal's own detail brought up.
  - Each button / chip sprite gets a copy per finish (`SeqBtnTool_vintage`…) whose edges, where the
    platinum plate showed round the cut-out, are in the finish's metal. The knob caps stay silver.
  - `PlateGrain` is a tile of the same pebble grain for the SwiftUI plates (SOUNDS / GENERATE headers).
Run after build_bays.py:

    python3 tools/sequencer_art/build_finishes.py BreakBoss.swiftpm
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))
import metal as M

pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
assets = pkg / "Resources" / "Assets.xcassets"
KINDS = ("platinum", "modern", "vintage", "texture")
SEED = {"platinum": 11, "modern": 12, "vintage": 13, "texture": 14}


def load(name):
    return np.asarray(Image.open(assets / f"{name}.imageset" / f"{name}.png").convert("RGBA")).astype(np.float32)


def write(name, a):
    d = assets / f"{name}.imageset"
    d.mkdir(exist_ok=True)
    mode = "RGBA" if a.shape[2] == 4 else "RGB"
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), mode).save(d / f"{name}.png", optimize=True)
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def lighten_print(rgb, original, rects):
    """Black printing on the metal (PATTERN / KIT) turns white on the black finish.
    How black a pixel is comes from the original (platinum) picture."""
    for x0, y0, x1, y1 in rects:
        k = (1 - M.smoothstep(40, 120, M.lum(original[y0:y1, x0:x1])))[..., None]
        rgb[y0:y1, x0:x1] = rgb[y0:y1, x0:x1] * (1 - k) + np.array([232, 232, 234], dtype=np.float32) * k
    return rgb


def deepen(rgb, kind, w, wells, seed, lit=True):
    """Depth and texture on the metal (w); the wells (dark panels) read as sunk into it."""
    h, wd = w.shape
    W = w[..., None]
    if lit:
        f = M.light_field(h, wd)[..., None]
        rgb = rgb * (1 + (f - 1) * (0.4 + 0.6 * W))
    # the wells' walls: top wall in shadow, bottom lip catching the light
    r = M.relief(1 - wells, sigma=2.0, gain=24)[..., None]
    rgb = rgb * (1 + 0.42 * r * W) + 34 * np.maximum(r, 0) * W
    # occlusion: metal right round a well is a touch darker, and the well's top edge takes a shadow
    ao = ndimage.gaussian_filter(wells, 5)[..., None]
    rgb = rgb * (1 - 0.16 * ao * W)
    sh = M.contact_shadow(1 - wells, dx=2, dy=4, sigma=3)[..., None]
    rgb = rgb * (1 - 0.55 * sh * wells[..., None])
    # the metal's own detail, then the finish's grain
    rgb = rgb + 0.45 * M.clarity(rgb) * W
    g = M.grain(kind, h, wd, seed)[..., None]
    rgb = rgb * (1 + M.GRAIN_AMOUNT[kind] * g * W)
    return np.clip(rgb, 0, 255)


def wells_of(rgb, alpha):
    dark = (1 - M.smoothstep(30, 62, M.lum(rgb))) * (1 - M.smoothstep(40, 90, M.sat(rgb)))
    # only real wells: printing and hairlines (thinner than ~9 px) aren't sunk into the metal
    return ndimage.grey_opening(dark * (alpha / 255.0), size=(9, 9))


# MARK: the plate and the rack row

plate = load("SeqPlate")
row = load("SeqRow")
PRINT = [(596, 706, 692, 730), (884, 706, 934, 730)]
for kind in KINDS:
    for name, src, lit in (("SeqPlate", plate, True), ("SeqRow", row, False)):
        rgb, alpha = src[..., :3], src[..., 3]
        w = M.metal_weight(rgb) * (alpha / 255.0)
        out = M.finish(rgb, kind, w)
        if kind == "modern" and name == "SeqPlate":
            out = lighten_print(out, rgb, PRINT)
        out = deepen(out, kind, w, wells_of(rgb, alpha), SEED[kind] + (0 if lit else 100), lit=lit)
        write(f"{name}_{kind}", np.concatenate([out, alpha[..., None]], axis=2))


# MARK: the buttons' and chips' edges

SPRITES = ["SeqArrowBack", "SeqArrowFwd", "SeqBtnClear", "SeqBtnCloud", "SeqBtnGear", "SeqBtnGenerate",
           "SeqBtnGrid", "SeqBtnPads", "SeqBtnTool", "SeqBtnTransport", "SeqChipBars", "SeqChipBpm",
           "SeqChipHumanize", "SeqChipKit", "SeqChipMain", "SeqChipPattern", "SeqChipSnap", "SeqChipSwing"]


def edge_metal(a):
    """The platinum metal that reaches the sprite's edge (plate showing round the cut-out, a metal
    button's body), 0...1. Metal walled off by a dark ring (a knob cap) isn't touched."""
    rgb, alpha = a[..., :3], a[..., 3]
    w = M.metal_weight(rgb) * (alpha > 8)
    light = w > 0.25
    outside = alpha < 128
    touching = light & ndimage.binary_dilation(outside, iterations=2)
    lab, n = ndimage.label(light)
    keep = np.unique(lab[touching])
    region = np.isin(lab, keep[keep > 0])
    region = ndimage.binary_dilation(region, iterations=1) & (alpha > 0)
    return np.clip(ndimage.gaussian_filter(region.astype(np.float32), 0.6) * 1.4, 0, 1) * w


for name in SPRITES:
    a = load(name)
    rgb, alpha = a[..., :3], a[..., 3]
    region = edge_metal(a)
    for kind in KINDS[1:]:
        out = rgb * (1 - region[..., None]) + M.recolor(rgb, kind) * region[..., None]
        if kind != "platinum":
            g = M.grain(kind, *region.shape, SEED[kind] + 200)[..., None]
            out = out * (1 + M.GRAIN_AMOUNT[kind] * 0.7 * g * region[..., None])
        if kind == "modern" and name == "SeqBtnCloud":
            # the cloud's dark outline would vanish on charcoal: print it white
            hh, ww = alpha.shape
            inside = np.zeros_like(alpha, dtype=bool)
            inside[int(hh * 0.2):int(hh * 0.8), int(ww * 0.15):int(ww * 0.85)] = True   # the glyph, not the rim
            k = ((1 - M.smoothstep(50, 110, M.lum(rgb))) * inside)[..., None]
            out = out * (1 - k) + np.array([232, 232, 234], dtype=np.float32) * k
        write(f"{name}_{kind}", np.concatenate([np.clip(out, 0, 255), alpha[..., None]], axis=2))


# MARK: the grain tile for the SwiftUI plates (mid grey = no change; drawn with an overlay blend)

t = M.tolex(256, 256, 7, wrap=True)
g = 128 + t * 70
write("PlateGrain", np.stack([g, g, g], axis=2))
print("finishes written")
