#!/usr/bin/env python3
"""Face 1 from Tyrone's approved renders (NEW faces Oct 28 2026; first set Oct 19).

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

# Where things are in the pictures: Tyrone's NEW Face 1 renders (the matte set of Oct 28 2026, tools/faceplate_art/
# face1/v2, scaled from 1448 x 1086 to 1450 x 1085). ONE shared layout, measured on PLATINUM (the
# master): every button, window, lamp and pad has the same rectangle on every face. Only the knob
# centres are fitted per face, so each live pointer sits on that face's own cap.
KNOBS = {"pitch": (774, 135), "tune": (931, 135), "bounce": (1089, 135), "velocity": (1248, 135),
         "filter": (774, 278), "clipDrive": (931, 278), "output": (1089, 278),
         "boost": (205, 524), "punch": (376, 524), "analogEQ": (552, 524), "grit": (724, 524),
         "shine": (896, 524), "tighten": (1068, 524), "noise": (1242, 524)}
ONESHOT, LOOP = [107, 73, 285, 150], [295, 73, 478, 150]
ONESHOT_LAMP, LOOP_LAMP = [166, 73, 226, 103], [354, 73, 414, 103]       # lamp and its glow (ONE-SHOT draws none)
MODES = {"modern": [501, 73, 657, 158], "vintage": [501, 165, 657, 243], "texture": [501, 250, 657, 345]}
SCOPE = [112, 166, 474, 338]
CLIPPER = [1208, 242, 1292, 332]
PLAY = [99, 382, 166, 447]
LEDS = {"tempoSync": [331, 384, 355, 408], "followDAW": [331, 413, 355, 437]}
BPM_BOX, BPM_LABEL_SEARCH = [173, 383, 325, 441], [198, 395, 240, 428]
KIT_BOX, KIT_TEXT_SEARCH = [636, 382, 908, 440], [650, 392, 892, 432]
PRESET_BOX, PRESET_TEXT_SEARCH = [1018, 382, 1291, 440], [1030, 392, 1280, 432]
DICE, SAVE = [485, 381, 551, 447], [1298, 381, 1360, 447]
RECORD, EDITOR, EXPORT, MENU = [1122, 24, 1177, 75], [1184, 24, 1238, 75], [1245, 24, 1299, 75], [1307, 24, 1360, 75]
REC_DOT = [1137, 33, 1161, 58]
POWER, SLIDER, LOGO = [112, 952, 174, 1014], [186, 954, 358, 1013], [600, 955, 850, 1010]
# the pads, as drawn on PLATINUM (the other faces line up within a few pixels)
PAD_COLS = [(107, 302), (317, 508), (524, 715), (732, 924), (940, 1132), (1148, 1341)]
PAD_ROWS = [(626, 780), (786, 940)]
# Each face's light, from its own scope trace / lamps (lit core, glow).
ACCENT = {"modern": ((255, 198, 142), (232, 52, 24)), "texture": ((189, 236, 254), (24, 100, 220)),
          "vintage": ((255, 250, 185), (236, 186, 72)), "platinum": ((253, 159, 90), (214, 50, 22))}
# CLIPPER's glass with its light out (red glass on every new face).
UNLIT = {"modern": (150, 26, 16), "texture": (150, 26, 16), "vintage": (150, 26, 16), "platinum": (150, 26, 16)}

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


def lit_ink(c):
    """The lit pixels of a window's printing, without the white cores the glow burns into them."""
    px = c.reshape(-1, 3)
    l = lum(px)
    sat = px.max(axis=1) - px.min(axis=1)
    keep = (l > 70) & (sat > np.percentile(sat[l > 70], 50))
    return px[keep]


def text_box(a, r, thresh=90):
    """The bright printing inside a dark window."""
    x0, y0, x1, y1 = r
    m = a[y0:y1, x0:x1, :3].max(axis=2) > thresh * 1.4    # its brightest channel (red ink is dim in lum)
    m = ndimage.binary_opening(m, np.ones((1, 2)))
    ys, xs = np.nonzero(m)
    return [x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1]


def fit_cap(L, x0, y0):
    """Centre and radius of a knob cap: the circle that runs along its sharpest edge."""
    g = np.hypot(ndimage.sobel(L, 0), ndimage.sobel(L, 1))
    th = np.linspace(0, 2 * np.pi, 180, endpoint=False)
    best = (-1, x0, y0, 33)
    for r in np.arange(29, 36, 0.5):
        for cy in np.arange(y0 - 7, y0 + 7.01, 0.5):
            for cx in np.arange(x0 - 7, x0 + 7.01, 0.5):
                v = ndimage.map_coordinates(g, [cy + r * np.sin(th), cx + r * np.cos(th)], order=1).mean()
                if v > best[0]:
                    best = (v, cx, cy, r)
    return best[1:]


def pointer_mask(a, cx, cy, r):
    """The black dot printed at the top of a cap (every new render has it at 12 o'clock)."""
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.hypot(xx - cx, yy - cy)
    inside = (d < r * 0.95) & (yy < cy - r * 0.45) & (np.abs(xx - cx) < r * 0.35)
    l = lum(a)
    m = inside & (l < min(80, 0.5 * np.median(l[inside])))
    lab, n = ndimage.label(m)
    if n == 0:
        return None
    sizes = ndimage.sum(m, lab, range(1, n + 1))
    m = lab == (1 + int(np.argmax(sizes)))
    return m


def remove_pointer(a, cx, cy, r, m):
    """Fill the notch from the cap on either side of it at the same distance from the centre (the
    brushed cone's light runs round the cap, so each ring carries on across the gap)."""
    grow = ndimage.binary_dilation(m, iterations=4)
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

def vintage_drive(a):
    """Vintage's FX section starts with DRIVE, not the render's BOOST (Tyrone, Oct 24): BOOST comes
    off (rows stretched from the clean plate either side, with grain) and DRIVE goes on in its
    place: the very DRIVE Texture prints under the same knob (same size, same spot), its light
    lettering used as the shape and inked in Vintage's own print colour (PUNCH's)."""
    fill_rows(a, [170, 579, 243, 607], grain=1.5)
    tex = np.asarray(Image.open(HERE / FACES["texture"]).convert("RGB")).astype(np.float32)
    r = [168, 579, 242, 606]
    l = lum(tex[r[1]:r[3], r[0]:r[2]])
    bg, hi = np.median(l), np.percentile(l, 99.5)
    alpha = np.clip((l - bg - 15) / max(1, hi - bg - 15), 0, 1)[..., None]
    punch = lum(a[580:606, 340:412])
    ink = a[580:606, 340:412, :3][punch <= np.percentile(punch, 3)].mean(axis=0)
    dst = a[r[1]:r[3], r[0]:r[2], :3]
    a[r[1]:r[3], r[0]:r[2], :3] = dst * (1 - alpha) + ink * alpha


for face, fname in FACES.items():
    src = np.asarray(Image.open(HERE / fname).convert("RGB")).astype(np.float32)
    assert src.shape == (H, W, 3), (fname, src.shape)
    if face == "vintage":
        vintage_drive(src)
    plate = src.copy()
    core, glow = (np.array(c, np.float32) for c in ACCENT[face])
    L = lum(src)

    # ---- knobs: fit each cap, measure and take off its pointer ----
    knobs = {}
    for k, (x0, y0) in KNOBS.items():
        cx, cy, r = fit_cap(L, x0, y0)
        m = pointer_mask(src, cx, cy, r)
        if m is not None:              # (two of Vintage's caps are drawn without their dot)
            pointer_stats.append(pointer_geometry(m, cx, cy, r))
            remove_pointer(plate, cx, cy, r, m)
        knobs[k] = {"x": round(float(cx), 1), "y": round(float(cy), 1), "r": round(float(r), 1)}

    # ---- the scope trace (the app draws the live one) ----
    band = L[SCOPE[1] + 40:SCOPE[3] - 40, SCOPE[0] + 60:SCOPE[2] - 60].mean(axis=1)
    if band.max() > np.median(band) + 40:      # (the Oct 28 renders show the glass empty)
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
    # the lamp's coloured spill just under it, back to the button face's own colour
    sx0, sy0, sx1, sy1 = LOOP_LAMP[0] - 12, LOOP_LAMP[3], LOOP_LAMP[2] + 12, LOOP_LAMP[3] + 9
    ref = np.median(lp[118:140, LOOP[0] + 12:LOOP[0] + 50, :3].reshape(-1, 3), axis=0)
    spill = lp[sy0:sy1, sx0:sx1, :3]
    w = np.clip(1 - np.abs(lum(spill) - lum(ref)) / 40, 0, 1)[..., None]      # the face, not the lettering
    lp[sy0:sy1, sx0:sx1, :3] = spill * (1 - w) + lum(spill)[..., None] * (ref / max(1, lum(ref))) * w
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

    # ---- TEMPO SYNC / FOLLOW DAW lamps: every new render shows TEMPO SYNC lit and FOLLOW DAW
    # dark, so each face gives its own lit and dark lamp ----
    lamp_on = crop(src, LEDS["tempoSync"])
    write(f"led_off_{face}", crop(src, LEDS["followDAW"]))
    # the plate wears the lit lamps (the app lays the dark one over a lamp that's off)
    for r in LEDS.values():
        plate[r[1]:r[3], r[0]:r[2], :3] = lamp_on

    # ---- PLAY lit: the triangle in the face's light ----
    pl = crop(plate, PLAY)
    ph, pw = pl.shape[:2]
    pc = lum(pl)
    inner = np.zeros((ph, pw), bool)
    inner[14:ph - 14, 16:pw - 16] = True
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

    pads = [[c0, r0, c1, r1] for (r0, r1) in PAD_ROWS for (c0, c1) in PAD_COLS]
    layout[face] = {
        "size": [W, H], "device": "tablet", "knobs": knobs,
        "scope": SCOPE,
        "bpmDigits": [int(digits[0]), int(digits[1]), int(digits[2]), int(digits[3])],
        "bpmLabelX": int(bpm_label[0]), "bpmBox": BPM_BOX,
        # the printing's colour: the lit strokes' own (their white-hot cores left out)
        "textColor": [int(v) for v in np.percentile(lit_ink(crop(src, kit_t)), 88, axis=0)],
        # the names sit centred across their whole window, as the renders print them
        "kitBox": KIT_BOX, "kitText": [KIT_BOX[0] + 16, int(kit_t[1]), KIT_BOX[2] - 16, int(kit_t[3])],
        "presetBox": PRESET_BOX, "presetText": [PRESET_BOX[0] + 16, int(pre_t[1]), PRESET_BOX[2] - 16, int(pre_t[3])],
        "leds": {"tempoSyncRect": LEDS["tempoSync"], "followDAWRect": LEDS["followDAW"]},
        "oneShotButton": ONESHOT, "loopButton": LOOP, "clipperRect": CLIPPER, "playRect": PLAY,
        "diceRect": DICE, "saveRect": SAVE, "recordRect": RECORD, "exportRect": EXPORT, "menuRect": MENU,
        "editorRect": EDITOR, "modeButtons": MODES, "pads": pads,
        "powerRect": POWER, "sliderRect": SLIDER, "logoRect": LOGO,
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
