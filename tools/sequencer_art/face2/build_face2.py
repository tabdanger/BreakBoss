#!/usr/bin/env python3
"""Face 2 from Tyrone's approved renders (Oct 17 2026, locked design).

Tyrone's four Face 2 pictures (Face2_ModernPlatinum / ModernBlack / Vintage / Texture, 1672 x 941)
are the sequencer's plates from here on. For each finish this writes:

  SeqPlate_<face>   the picture with everything live cleared: button labels, the rack, the grid, the
                    bars pager text, the bottom rail (PATTERN / KIT move left, the FX knobs go right).
                    Cleared metal is filled row by row from the clean metal either side, carrying the
                    rail's own light across it plus a little brushed grain, so no patch shows.
  Seq*_<face>       every button / chip cut out of that finish's picture with its label taken off
                    (the app prints the live text), so each finish wears its own buttons.
  SeqRow_<face>     a track header (the CLAP row) with its name, knobs and arrow taken off.
  SeqHeader_<face>  the SOUNDS / GENERATE header plate without its words and chevron.

<face> is the app's faceKey: platinum, modern (black), vintage, texture. Rectangles are in rects.py
and in SequencerView.A (same picture pixels).

    python3 tools/sequencer_art/face2/build_face2.py BreakBoss.swiftpm
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
from rects import *  # noqa: E402,F403

pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
assets = pkg / "Resources" / "Assets.xcassets"
FACES = {"platinum": "Face2_ModernPlatinum.png", "modern": "Face2_ModernBlack.png",
         "vintage": "Face2_Vintage.png", "texture": "Face2_Texture.png"}

# The bottom rail, rearranged (Tyrone: PATTERN and KIT over to the left; the FX knobs on the right).
NEW_DIVIDERS_X = [292, 668, 1030]
NEW_PAT_LABEL_X, NEW_KIT_LABEL_X = 312, 690
NEW_PAT_ARROWS, NEW_PAT_CHIP = [312, 741, 410, 785], [411, 740, 641, 785]
NEW_KIT_ARROWS, NEW_KIT_CHIP = [690, 741, 787, 785], [789, 740, 1004, 785]


def write(name, arr):
    d = assets / f"{name}.imageset"
    d.mkdir(exist_ok=True)
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA" if arr.shape[2] == 4 else "RGB")
    img.save(d / f"{name}.png", optimize=True)
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def hblur(a, n):
    return ndimage.uniform_filter1d(a, n, axis=1, mode="reflect")


rng = np.random.default_rng(2026_10_17)


def grain(h, w, amount):
    """Brushed strokes running sideways, in levels."""
    g = hblur(rng.normal(0, 1, (h, w)).astype(np.float32), 41) * 1.6 + hblur(rng.normal(0, 1, (h, w)).astype(np.float32), 7) * 0.7
    return g / (g.std() + 1e-6) * amount


def col(a, x, y0, y1):
    """A clean column (3 px averaged) as one colour per row."""
    return a[y0:y1, x - 1:x + 2, :3].mean(axis=1)


def fill_rows(a, r, cl, cr, light=None, amount=None):
    """Paint a rectangle with the metal either side of it: each row runs from column cl's colour to
    column cr's. `light` (one value per x) carries the rail's sheen across; the grain matches the
    metal's own (measured off the clean columns)."""
    x0, y0, x1, y1 = r
    L, R = col(a, cl, y0, y1), col(a, cr, y0, y1)
    t = ((np.arange(x0, x1) - cl) / max(1, cr - cl))[None, :, None]
    f = L[:, None, :] * (1 - t) + R[:, None, :] * t
    if light is not None:
        base = light[cl] * (1 - t[0, :, 0]) + light[cr] * t[0, :, 0]
        f = f * (light[x0:x1] / np.maximum(1, base))[None, :, None]
    if amount is None:
        amount = max(0.6, min(4.0, float(np.std(np.diff(L[:, 1])) * 0.5)))
    f = f + grain(y1 - y0, x1 - x0, amount)[..., None] * (f.mean(axis=2, keepdims=True) / 200 + 0.2)
    a[y0:y1, x0:x1, :3] = f


def fill_cols(a, r, yt, yb):
    """Paint a rectangle top to bottom from rows yt and yb (for the track tab's triangle)."""
    x0, y0, x1, y1 = r
    T, B = a[yt, x0:x1, :3], a[yb, x0:x1, :3]
    t = ((np.arange(y0, y1) - yt) / max(1, yb - yt))[:, None, None]
    a[y0:y1, x0:x1, :3] = T[None] * (1 - t) + B[None] * t


def label_box(a, r, inset=6, thresh=38):
    """The printing on a button face: pixels far from their row's median, inside the bevel."""
    x0, y0, x1, y1 = r
    sub = lum(a[y0 + inset:y1 - inset, x0 + inset:x1 - inset])
    med = np.median(sub, axis=1, keepdims=True)
    m = np.abs(sub - med) > thresh
    m = ndimage.binary_opening(m, iterations=1) | (ndimage.uniform_filter(m.astype(float), 3) > 0.6)
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return None
    return [x0 + inset + xs.min() - 3, y0 + inset + ys.min() - 2, x0 + inset + xs.max() + 4, y0 + inset + ys.max() + 3]


def union(boxes):
    boxes = [b for b in boxes if b]
    return [min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes)]


def rounded_alpha(w, h, radius):
    m = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * 4 - 1, h * 4 - 1), radius * 4, fill=255)
    return np.asarray(m.resize((w, h), Image.LANCZOS)).astype(np.float32)


def sprite(a, r, radius=7):
    x0, y0, x1, y1 = r
    out = np.zeros((y1 - y0, x1 - x0, 4), np.float32)
    out[..., :3] = a[y0:y1, x0:x1, :3]
    out[..., 3] = rounded_alpha(x1 - x0, y1 - y0, radius)
    return out


def narrower(s, width, keep_right=48):
    """A chip made narrower by taking columns out of its flat middle (the chevron end stays whole)."""
    w = s.shape[1]
    cut = w - width
    mid = (w - keep_right) // 2
    return np.concatenate([s[:, :mid - cut // 2], s[:, mid - cut // 2 + cut:]], axis=1)


pics = {f: np.asarray(Image.open(HERE / n).convert("RGB")).astype(np.float32) for f, n in FACES.items()}
assert all(p.shape == (H, W, 3) for p in pics.values())


def clear_label(rect, region=None, thresh=38):
    """The label box of a control, found on every finish and joined (the renders line up)."""
    r = region or rect
    return union([label_box(p, r, thresh=thresh) for p in pics.values()])


# The printing to take off each control (found once, used for every finish)
TOOL_SRC = TOOLS[1]                                       # SELECT (DRAW is lit in the pictures)
LABELS = {
    "tool": clear_label(TOOL_SRC),
    "transport": clear_label(STOP),
    "host": clear_label(TEMPO_SYNC),
    "bpm": clear_label(BPM, [BPM[0], BPM[1], BPM[2] - 46, BPM[3]]),
    "bars": clear_label(BARS, [BARS[0], BARS[1], BARS[2] - 46, BARS[3]]),
    "snapIcon": [964, 166, 985, 199],
    "snapValue": clear_label(SNAP, [1036, SNAP[1], SNAP[2] - 40, SNAP[3]]),
    "swingValue": clear_label(SWING, [1255, SWING[1], 1318, SWING[3]]),
    "pattern": clear_label(PAT_CHIP, [PAT_CHIP[0], PAT_CHIP[1], PAT_CHIP[2] - 46, PAT_CHIP[3]]),
    "kit": clear_label(KIT_CHIP, [KIT_CHIP[0], KIT_CHIP[1], KIT_CHIP[2] - 46, KIT_CHIP[3]]),
    "rowBtn": [1588, 307, 1611, 331],
}
print({k: v for k, v in LABELS.items()})

ROW = [347, 414, 607, 473]               # the CLAP track header
ROW_BTN = [1584, 303, 1615, 335]         # a per-track button (its ✕ comes off)

for face, src in pics.items():
    a = src.copy()

    # ---- sprites (cut before the plate is cleared) ----
    def cut(r, clears=(), radius=7):
        b = src.copy()
        for c in clears:
            cl, cr = (c[4], c[5]) if len(c) > 4 else (c[0] - 1, c[2])
            fill_rows(b, c[:4], cl, cr, amount=0.8)
        return sprite(b, r, radius)

    write(f"SeqBtnTool_{face}", cut(TOOL_SRC, [LABELS["tool"]], 8))
    write(f"SeqBtnTransport_{face}", cut(STOP, [LABELS["transport"]], 8))
    write(f"SeqBtnHost_{face}", cut(TEMPO_SYNC, [LABELS["host"]], 8))
    write(f"SeqChipBpm_{face}", cut(BPM, [LABELS["bpm"]], 8))
    write(f"SeqChipBars_{face}", cut(BARS, [LABELS["bars"]], 8))
    write(f"SeqBtnGear_{face}", cut(GEAR, [], 8))
    write(f"SeqBtnCloud_{face}", cut(CLOUD, [], 9))
    # (the link icon comes off with the face's own colour from its left; the app's tuning fork goes there)
    write(f"SeqChipSnap_{face}", cut(SNAP, [LABELS["snapIcon"] + [963, 963], LABELS["snapValue"]], 8))
    # the swing / humanize knobs stay in the chips: the app's knob sits exactly over them
    write(f"SeqChipSwing_{face}", cut(SWING, [LABELS["swingValue"]], 8))
    write(f"SeqChipHumanize_{face}", cut(HUMANIZE, [], 8))
    split = (PAT_ARROWS[0] + PAT_ARROWS[2]) // 2
    write(f"SeqArrowBack_{face}", cut([PAT_ARROWS[0], PAT_ARROWS[1], split, PAT_ARROWS[3]], [], 7))
    write(f"SeqArrowFwd_{face}", cut([split, PAT_ARROWS[1], PAT_ARROWS[2], PAT_ARROWS[3]], [], 7))
    write(f"SeqChipPattern_{face}", narrower(cut(PAT_CHIP, [LABELS["pattern"]], 8), NEW_PAT_CHIP[2] - NEW_PAT_CHIP[0]))
    write(f"SeqChipKit_{face}", narrower(cut(KIT_CHIP, [LABELS["kit"]], 8), NEW_KIT_CHIP[2] - NEW_KIT_CHIP[0]))
    write(f"SeqRowBtn_{face}", cut(ROW_BTN, [LABELS["rowBtn"]], 6))
    hdr = [LEFT_PANEL[0], LEFT_PANEL[1], LEFT_PANEL[2], LEFT_PANEL[1] + HEADER_H]
    hb = src.copy()
    fill_rows(hb, [58, 229, 146, 258], 57, 146, amount=0.8)            # SOUNDS
    fill_rows(hb, [290, 231, 322, 257], 289, 322, amount=0.8)          # its chevron
    write(f"SeqHeader_{face}", sprite(hb, hdr, 9))

    # the track header: name and knobs off the body, the arrow off the tab (the app draws them live)
    rb = src.copy()
    fill_rows(rb, [384, 420, 573, 468], 383, 573, amount=0.6)
    fill_cols(rb, [352, 428, 378, 460], 427, 460)
    write(f"SeqRow_{face}", sprite(rb, ROW, 7))

    # ---- the plate ----
    # top rail: the buttons stay (the live ones sit on top of them); DRAW and PLAY are lit in the
    # pictures, so they get the unlit button and the glow round them goes
    def paste(dst_rect, src_rect, clears):
        b = src.copy()
        for c in clears:
            fill_rows(b, c, c[0] - 1, c[2], amount=0.8)
        x0, y0, x1, y1 = src_rect
        im = Image.fromarray(np.clip(b[y0:y1, x0:x1], 0, 255).astype(np.uint8))
        im = im.resize((dst_rect[2] - dst_rect[0], dst_rect[3] - dst_rect[1]), Image.LANCZOS)
        a[dst_rect[1]:dst_rect[3], dst_rect[0]:dst_rect[2], :3] = np.asarray(im).astype(np.float32)
    fill_rows(a, [317, 85, 838, 94], 316, 838)
    fill_rows(a, [317, 150, 838, 159], 316, 838)
    fill_rows(a, [314, 94, 325, 150], 313, 313)
    paste(TOOLS[0], TOOL_SRC, [LABELS["tool"]])
    fill_rows(a, [851, 85, 1074, 94], 850, 1075)
    fill_rows(a, [851, 150, 1074, 159], 850, 1075)
    paste(PLAY, STOP, [LABELS["transport"]])
    # the bars pager's text and arrows (printed live)
    fill_rows(a, [427, 160, 630, 205], 426, 631)
    # the rack: its metal bay, in the plate's own grain (the clean strip above the first track,
    # mirrored down the bay) with the light falling off a little towards the bottom
    bx0, by0, bx1, by1 = 338, 257, 609, 670
    strip = src[224:254, bx0:bx1, :3]
    tile = np.concatenate([strip, strip[::-1]], axis=0)
    reps = (by1 - by0) // tile.shape[0] + 1
    bay = np.concatenate([tile] * reps, axis=0)[:by1 - by0]
    bay = bay * (1 - 0.05 * np.linspace(0, 1, by1 - by0))[:, None, None]
    edge = np.clip(np.arange(by1 - by0) / 3, 0, 1)[:, None, None]          # blend into the strip above
    a[by0:by1, bx0:bx1, :3] = a[by0:by1, bx0:bx1, :3] * (1 - edge) + bay * edge
    # the grid well: its own black, a touch lighter in the middle, inside its rounded edge
    wx0, wy0, wx1, wy1 = GRID_WELL
    ix0, iy0, ix1, iy1 = wx0 + 4, wy0 + 5, wx1 - 4, wy1 - 4
    ref = np.concatenate([src[iy0 + 10:iy1 - 10, ix0:ix0 + 6, :3].reshape(-1, 3), src[iy0 + 10:iy1 - 10, ix1 - 6:ix1, :3].reshape(-1, 3)])
    black = np.median(ref, axis=0)
    yy, xx = np.mgrid[iy0:iy1, ix0:ix1].astype(np.float32)
    glow = 1 + 0.25 * np.exp(-(((xx - (ix0 + ix1) / 2) / ((ix1 - ix0) * 0.55)) ** 2 + ((yy - (iy0 + iy1) / 2) / ((iy1 - iy0) * 0.6)) ** 2))
    well = black[None, None, :] * glow[..., None] + rng.normal(0, 0.6, (iy1 - iy0, ix1 - ix0, 1))
    m = rounded_alpha(ix1 - ix0, iy1 - iy0, 13)[..., None] / 255
    a[iy0:iy1, ix0:ix1, :3] = a[iy0:iy1, ix0:ix1, :3] * (1 - m) + well * m
    # the bottom rail: the power button's glow, PATTERN, KIT, their labels and dividers
    light = lum(src[699:709, :, :3]).mean(axis=0)
    light[:345] = light[345]
    light = ndimage.uniform_filter1d(light, 25)
    fill_rows(a, [188, 704, 1601, 798], 187, 1601, light=light)
    cleared = a.copy()
    # ... then the labels and dividers go back at their new places, carried over as light and shade
    def carry(r, nx):
        x0, y0, x1, y1 = r
        s0 = src[y0:y1, x0:x1, :3]
        bg = np.median(src[y0:y1, x0 - 12:x1 + 12, :3], axis=1, keepdims=True)
        ratio = s0 / np.maximum(1, bg)
        dev = np.abs(lum(ratio) - 1)
        w = np.clip((dev - 0.05) / 0.08, 0, 1)
        w = np.maximum(w, ndimage.uniform_filter(w, 3) * 0.8)[..., None]
        ratio = 1 + (ratio - 1) * w
        a[y0:y1, nx:nx + (x1 - x0), :3] = cleared[y0:y1, nx:nx + (x1 - x0), :3] * ratio
    carry(PAT_LABEL, NEW_PAT_LABEL_X)
    carry(KIT_LABEL, NEW_KIT_LABEL_X)
    for nx in NEW_DIVIDERS_X:
        carry([DIVIDERS_X[0] - 3, DIVIDER_Y[0], DIVIDERS_X[0] + 4, DIVIDER_Y[1]], nx - 3)
    out = np.concatenate([a, np.full((H, W, 1), 255, np.float32)], axis=2)
    write(f"SeqPlate_{face}", out)
    print("face", face)

print("Face 2 built")
