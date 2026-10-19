#!/usr/bin/env python3
"""Face 1 from Tyrone's approved renders (Oct 19 2026, locked design).

Tyrone's four Face 1 pictures (Face1_ModernBlack / Texture / Vintage / ModernPlatinum, 1450 x 1085) are
the faceplates from here on, one per face, each with its own buttons, knobs, lamps and pads: nothing is
shared between faces. For each face this writes, cut from that face's own picture only:

  Plate_<face>          the picture with what the app draws live taken off: the knob pointers (the app
                        turns them), the scope trace, the BPM digits and the KITS / PRESETS names. Lit
                        states are left as drawn: LOOP and the face's mode lamp on, CLIPPER ON.
  oneshot_on_<face>     ONE-SHOT with LOOP's lit lamp, and loop_off_<face> LOOP with ONE-SHOT's dark one.
  clipper_off_<face>    the CLIPPER button with its light off.
  led_off_<face>        a TEMPO SYNC / FOLLOW DAW lamp dark; the plate wears them lit (the
                        picture shows one of the two; the other is that lamp's own glass relit or dimmed).
  play_on_<face>        PLAY with its triangle lit in the face's colour.
  rec_blank_<face>      the RECORD button without its dot (the count-in numbers sit on it).

and the layout (Resources/KnockLayout.json): knob centres and sizes fitted to each picture's caps, the
pointer size measured off the pictures, every pad, button and window as drawn on that face.

<face> is the app's faceKey: modern (black), texture, vintage, platinum.

    python3 tools/faceplate_art/face1/build_face1.py BreakBoss.swiftpm
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = Path(__file__).parent
pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
assets = pkg / "Resources" / "Assets.xcassets"
layout_path = pkg / "Resources" / "KnockLayout.json"
FACES = {"modern": "Face1_ModernBlack.png", "texture": "Face1_Texture.png",
         "vintage": "Face1_Vintage.png", "platinum": "Face1_ModernPlatinum.png"}
W, H = 1450, 1085

# Where things are in the pictures (the four line up within a pixel or two; pads and knobs are
# measured per face below).
KNOBS = {"pitch": (765, 94), "tune": (929, 94), "bounce": (1096, 92), "velocity": (1266, 93),
         "filter": (764, 235), "clipDrive": (929, 236), "output": (1095, 234),
         "boost": (239, 510), "punch": (402, 510), "analogEQ": (566, 510), "grit": (729, 510),
         "shine": (895, 510), "tighten": (1061, 510), "noise": (1227, 510)}
ONESHOT, LOOP = [131, 50, 288, 116], [301, 50, 449, 116]
ONESHOT_LAMP, LOOP_LAMP = [188, 92, 232, 116], [356, 92, 400, 116]       # lamp and its glow
MODES = {"modern": [494, 43, 630, 129], "vintage": [494, 141, 630, 231], "texture": [494, 242, 630, 332]}
SCOPE = [121, 159, 461, 320]
CLIPPER = [1215, 200, 1302, 289]
PLAY = [104, 362, 188, 435]
LEDS = {"tempoSync": [350, 364, 380, 394], "followDAW": [350, 398, 380, 428]}
BPM_BOX, BPM_LABEL_SEARCH = [199, 362, 326, 431], [236, 380, 270, 412]
KIT_BOX, KIT_TEXT_SEARCH = [632, 368, 918, 432], [645, 384, 875, 414]
PRESET_BOX, PRESET_TEXT_SEARCH = [1024, 367, 1288, 432], [1038, 384, 1243, 414]
DICE, SAVE = [510, 368, 576, 436], [1300, 368, 1366, 436]
RECORD, EDITOR, EXPORT, MENU = [1232, 12, 1268, 46], [1270, 12, 1306, 46], [1308, 12, 1344, 46], [1346, 12, 1382, 46]
REC_DOT = [1240, 19, 1260, 39]
PADS = {   # columns and rows of the pad tops, as drawn on each face
    "modern": ([(125, 309), (333, 513), (538, 719), (741, 924), (947, 1130), (1152, 1335)], [(647, 804), (822, 983)]),
    "texture": ([(125, 309), (333, 514), (538, 719), (741, 925), (947, 1131), (1153, 1336)], [(646, 804), (822, 983)]),
    "vintage": ([(122, 312), (330, 516), (534, 721), (738, 927), (944, 1132), (1150, 1339)], [(643, 807), (819, 986)]),
    "platinum": ([(121, 310), (329, 514), (533, 719), (737, 925), (943, 1130), (1148, 1337)], [(642, 806), (818, 985)]),
}
# Each face's light, from its own scope trace / lamps (lit core, glow).
ACCENT = {"modern": ((255, 198, 142), (232, 52, 24)), "texture": ((189, 236, 254), (24, 100, 220)),
          "vintage": ((255, 250, 185), (236, 186, 72)), "platinum": ((253, 159, 90), (214, 50, 22))}
# CLIPPER's glass with its light out.
UNLIT = {"modern": (150, 26, 16), "texture": (22, 58, 140), "vintage": (160, 112, 34), "platinum": (150, 26, 16)}
# The picture shows the TEMPO SYNC / FOLLOW DAW lamps lit on these faces, dark on the others.
LEDS_LIT_IN_PICTURE = {"texture", "vintage"}

rng = np.random.default_rng(2026_10_19)


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def write(name, arr):
    d = assets / f"{name}.imageset"
    d.mkdir(exist_ok=True)
    for old in d.glob("*.png"):
        old.unlink()
    Image.fromarray(np.clip(arr, 0, 255).round().astype(np.uint8), "RGB").save(d / f"{name}.png", optimize=True)
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def crop(a, r):
    return a[r[1]:r[3], r[0]:r[2], :3].copy()


def fill_rows(a, r, grain=0.0):
    """Paint a rectangle row by row from the clean columns just outside it (the glass's own shading
    carries across)."""
    x0, y0, x1, y1 = r
    L = a[y0:y1, x0 - 2:x0, :3].mean(axis=1)
    R = a[y0:y1, x1:x1 + 2, :3].mean(axis=1)
    t = ((np.arange(x0, x1) - (x0 - 1)) / (x1 - x0 + 1))[None, :, None]
    f = L[:, None, :] * (1 - t) + R[:, None, :] * t
    if grain:
        f = f + rng.normal(0, grain, f.shape[:2])[..., None]
    a[y0:y1, x0:x1, :3] = f


def fill_cols(a, r):
    """Paint a rectangle column by column from the clean rows just above and below it."""
    x0, y0, x1, y1 = r
    T = a[y0 - 2:y0, x0:x1, :3].mean(axis=0)
    B = a[y1:y1 + 2, x0:x1, :3].mean(axis=0)
    t = ((np.arange(y0, y1) - (y0 - 1)) / (y1 - y0 + 1))[:, None, None]
    a[y0:y1, x0:x1, :3] = T[None] * (1 - t) + B[None] * t


def text_box(a, r, thresh=90):
    """The bright printing inside a dark window."""
    x0, y0, x1, y1 = r
    m = lum(a[y0:y1, x0:x1]) > thresh
    m = ndimage.binary_opening(m, np.ones((1, 2)))
    ys, xs = np.nonzero(m)
    return [x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1]


def fit_cap(L, x0, y0):
    """Centre and radius of a knob cap: the circle that runs along its sharpest edge."""
    g = np.hypot(ndimage.sobel(L, 0), ndimage.sobel(L, 1))
    th = np.linspace(0, 2 * np.pi, 180, endpoint=False)
    best = (-1, x0, y0, 33)
    for r in np.arange(29, 36, 0.5):
        for cy in np.arange(y0 - 4, y0 + 4.01, 0.5):
            for cx in np.arange(x0 - 4, x0 + 4.01, 0.5):
                v = ndimage.map_coordinates(g, [cy + r * np.sin(th), cx + r * np.cos(th)], order=1).mean()
                if v > best[0]:
                    best = (v, cx, cy, r)
    return best[1:]


def pointer_mask(a, cx, cy, r):
    """The black notch printed on a cap."""
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.hypot(xx - cx, yy - cy)
    inside = d < r * 0.95
    m = inside & (lum(a) < 80)
    lab, n = ndimage.label(m)
    if n == 0:
        return None
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    m = lab == (1 + int(np.argmax(sizes)))
    return m


def remove_pointer(a, cx, cy, r, m):
    """Fill the notch from the cap on either side of it at the same distance from the centre (the
    brushed cone's light runs round the cap, so each ring carries on across the gap)."""
    grow = ndimage.binary_dilation(m, iterations=2)
    ys, xs = np.nonzero(grow)
    ang = np.arctan2(ys - cy, xs - cx)
    rad = np.hypot(xs - cx, ys - cy)
    out = a.copy()
    step = 0.5 / max(rad.min(), 4)
    for y, x, t, p in zip(ys, xs, ang, rad):
        vals, wts = [], []
        for sgn in (-1, 1):
            k = 1
            while k < 400:
                tt = t + sgn * k * step
                sx, sy = cx + p * np.cos(tt), cy + p * np.sin(tt)
                ix, iy = int(round(sx)), int(round(sy))
                if not grow[iy, ix]:
                    v = np.array([ndimage.map_coordinates(a[..., c], [[sy], [sx]], order=1)[0] for c in range(3)])
                    vals.append(v)
                    wts.append(1.0 / k)
                    break
                k += 1
        if vals:
            out[y, x, :3] = sum(v * w for v, w in zip(vals, wts)) / sum(wts)
    # soften the seam a touch along the ring direction only where we painted
    a[grow] = out[grow]


def pointer_geometry(m, cx, cy, r):
    ys, xs = np.nonzero(m)
    d = np.hypot(xs - cx, ys - cy)
    P = np.stack([xs, ys], 1).astype(float)
    c = P.mean(0)
    s = np.linalg.svd(P - c, compute_uv=False)
    width = s[1] / np.sqrt(len(xs)) * np.sqrt(12)
    return np.percentile(d, 2) / r, np.percentile(d, 98) / r, width / r


def lamp_layer(a, r):
    """A lamp with its glow, as the change it makes to the button face under it (the face itself
    is filled in from either side of the patch)."""
    clean = a.copy()
    fill_rows(clean, r)
    return crop(a, r) - crop(clean, r)


def move_lamp(dst, src, from_r, to_r):
    """Put one button's lamp (lit or dark) on its neighbour: the neighbour's own lamp comes off and
    the other lamp's light goes on the neighbour's own button face."""
    layer = lamp_layer(src, from_r)
    fill_rows(dst, to_r)
    dst[to_r[1]:to_r[3], to_r[0]:to_r[2], :3] += layer


def disc(shape, cx, cy, rad, soft=1.0):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    d = np.hypot(xx - cx, yy - cy)
    return np.clip((rad - d) / soft + 0.5, 0, 1)


layout = {}
pointer_stats = []

for face, fname in FACES.items():
    src = np.asarray(Image.open(HERE / fname).convert("RGB")).astype(np.float32)
    assert src.shape == (H, W, 3), (fname, src.shape)
    plate = src.copy()
    core, glow = (np.array(c, np.float32) for c in ACCENT[face])
    L = lum(src)

    # ---- knobs: fit each cap, measure and take off its pointer ----
    knobs = {}
    for k, (x0, y0) in KNOBS.items():
        cx, cy, r = fit_cap(L, x0, y0)
        m = pointer_mask(src, cx, cy, r)
        inner, outer, width = pointer_geometry(m, cx, cy, r)
        pointer_stats.append((inner, outer, width))
        remove_pointer(plate, cx, cy, r, m)
        knobs[k] = {"x": round(float(cx), 1), "y": round(float(cy), 1), "r": round(float(r), 1)}

    # ---- the scope trace (the app draws the live one) ----
    band = L[SCOPE[1] + 40:SCOPE[3] - 40, SCOPE[0] + 60:SCOPE[2] - 60].mean(axis=1)
    peak = SCOPE[1] + 40 + int(np.argmax(band))
    fill_cols(plate, [SCOPE[0] - 2, peak - 8, SCOPE[2] + 3, peak + 9])

    # ---- BPM digits, KITS and PRESETS names (live text) ----
    digits = text_box(src, BPM_LABEL_SEARCH)
    fill_rows(plate, [digits[0] - 2, digits[1] - 2, digits[2] + 1, digits[3] + 2])
    kit_t = text_box(src, KIT_TEXT_SEARCH)
    pre_t = text_box(src, PRESET_TEXT_SEARCH)
    fill_rows(plate, [kit_t[0] - 3, kit_t[1] - 3, kit_t[2] + 3, kit_t[3] + 3])
    fill_rows(plate, [pre_t[0] - 3, pre_t[1] - 3, pre_t[2] + 3, pre_t[3] + 3])
    bpm_label = text_box(src, [digits[2] + 1, BPM_LABEL_SEARCH[1], BPM_BOX[2] - 4, BPM_LABEL_SEARCH[3]])

    # ---- RECORD without its dot (count-in) ----
    rec = plate.copy()
    fill_rows(rec, REC_DOT)
    write(f"rec_blank_{face}", crop(rec, RECORD))

    # ---- ONE-SHOT lit / LOOP dark ----
    one = plate.copy()
    move_lamp(one, src, LOOP_LAMP, ONESHOT_LAMP)
    write(f"oneshot_on_{face}", crop(one, ONESHOT))
    lp = plate.copy()
    move_lamp(lp, src, ONESHOT_LAMP, LOOP_LAMP)
    write(f"loop_off_{face}", crop(lp, LOOP))

    # ---- CLIPPER off: the same cap with its light out ----
    off = plate.copy()
    x0, y0, x1, y1 = CLIPPER
    c = crop(off, CLIPPER)
    h, w = c.shape[:2]
    # the lit cap: its coloured glass inside the dark rim (the "ON" printing included)
    sat = c.max(axis=2) - c.min(axis=2)
    lab, n = ndimage.label(sat > 120)
    big = lab == (1 + int(np.argmax(ndimage.sum(sat > 120, lab, range(1, n + 1)))))
    ys, xs = np.nonzero(big)
    m = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(m).rounded_rectangle(((xs.min() - 1) * 4, (ys.min() - 1) * 4, (xs.max() + 2) * 4, (ys.max() + 2) * 4), 20, fill=255)
    capm = (np.asarray(m.resize((w, h), Image.LANCZOS)).astype(np.float32) / 255)[..., None]
    l = (lum(c) / 255.0)[..., None]
    dark = np.array(UNLIT[face], np.float32) * l ** 0.8 + 6        # the same glass with its light out
    c2 = c * (1 - capm) + dark * capm
    write(f"clipper_off_{face}", c2)

    # ---- TEMPO SYNC / FOLLOW DAW lamps: lit and dark ----
    lr = LEDS["tempoSync"]
    lamp = crop(src, lr)
    lh, lw = lamp.shape[:2]
    lc = lum(lamp)
    # the lamp glass: the round middle of the lamp
    gx, gy = lw / 2 - 0.5, lh / 2 - 0.5
    glass = disc(lamp.shape[:2], gx, gy, 7.2, 1.2)[..., None]
    ring = disc(lamp.shape[:2], gx, gy, 12.5, 2.0)[..., None]
    if face in LEDS_LIT_IN_PICTURE:
        lamp_on = lamp
        # dark: the glass dimmed to a deep tint of its own colour, its spill on the bezel taken back
        l = lum(lamp)[..., None]
        tint = lamp / np.maximum(1, lamp.max(axis=2, keepdims=True)) * 60
        lamp_off = lamp * (1 - glass) + (tint * 0.6 + l * 0.12) * glass
        spill = (ring - glass) * 0.35
        lamp_off = lamp_off * (1 - spill) + (lamp_off * 0.75) * spill
    else:
        lamp_off = lamp
        # lit: the dark glass brought up in the face's light, with the glass's own highlight kept
        l = lum(lamp)[..., None] / 255
        lit_glass = glow * (0.55 + 1.6 * l) + core * np.clip(l * 2.2 - 0.2, 0, 1)
        lamp_on = lamp * (1 - glass) + np.clip(lit_glass, 0, 255) * glass
        spill = np.clip(ring - glass, 0, 1) * 0.35
        lamp_on = lamp_on * (1 - spill) + np.clip(lamp_on + glow * 0.5, 0, 255) * spill
    write(f"led_off_{face}", lamp_off)
    # the plate wears the lit lamps (the app lays the dark one over a lamp that's off)
    for r in LEDS.values():
        plate[r[1]:r[3], r[0]:r[2], :3] = lamp_on if face not in LEDS_LIT_IN_PICTURE else src[r[1]:r[3], r[0]:r[2], :3]

    # ---- PLAY lit: the triangle in the face's light ----
    pl = crop(plate, PLAY)
    ph, pw = pl.shape[:2]
    pc = lum(pl)
    inner = np.zeros((ph, pw), bool)
    inner[18:ph - 18, 22:pw - 22] = True
    bg = np.median(pc[inner])
    tri = inner & (np.abs(pc - bg) > 45)
    tri = ndimage.binary_closing(tri, iterations=1)
    tri_f = ndimage.gaussian_filter(tri.astype(np.float32), 0.6)[..., None]
    halo = np.clip(ndimage.gaussian_filter(tri.astype(np.float32), 3.0) * 1.2, 0, 1)[..., None] * (1 - tri_f)
    shade = (pc / 255.0)[..., None]
    lit_tri = glow * 0.85 + core * 0.15 + (core - glow) * 0.25 * shade
    on = pl * (1 - tri_f) + lit_tri * tri_f
    on = on * (1 - halo * 0.45) + glow * halo * 0.45
    write(f"play_on_{face}", on)

    write(f"Plate_{face}", plate)

    cols, rows = PADS[face]
    pads = [[c0, r0, c1, r1] for (r0, r1) in rows for (c0, c1) in cols]
    layout[face] = {
        "size": [W, H], "device": "tablet", "knobs": knobs,
        "scope": SCOPE,
        "bpmDigits": [int(digits[0]), int(digits[1]), int(digits[2]), int(digits[3])],
        "bpmLabelX": int(bpm_label[0]), "bpmBox": BPM_BOX,
        "textColor": [int(v) for v in np.percentile(crop(src, kit_t).reshape(-1, 3), 99.5, axis=0)],
        "kitBox": KIT_BOX, "kitText": [int(v) for v in kit_t],
        "presetBox": PRESET_BOX, "presetText": [int(v) for v in pre_t],
        "leds": {"tempoSyncRect": LEDS["tempoSync"], "followDAWRect": LEDS["followDAW"]},
        "oneShotButton": ONESHOT, "loopButton": LOOP, "clipperRect": CLIPPER, "playRect": PLAY,
        "diceRect": DICE, "saveRect": SAVE, "recordRect": RECORD, "exportRect": EXPORT, "menuRect": MENU,
        "editorRect": EDITOR, "modeButtons": MODES, "pads": pads,
        "padOrder": [6, 7, 8, 9, 10, 11, 0, 1, 2, 3, 4, 5],
    }
    print(face, "kit", kit_t, "preset", pre_t, "digits", digits, "BPM at", bpm_label[0])

inner, outer, width = np.median(np.array(pointer_stats), axis=0)
print(f"pointer inner {inner:.2f} outer {outer:.2f} width {width:.3f}")
for face in layout:
    for k in layout[face]["knobs"].values():
        k.update({"bakedAngle": 0, "pointerInner": round(float(inner), 2), "pointerOuter": round(float(outer), 2),
                  "pointerWidth": round(float(width), 3)})
layout_path.write_text(json.dumps(layout, indent=1) + "\n")
