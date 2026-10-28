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

# Where things are in the pictures: Tyrone's NEW Face 1 renders (Oct 27-28 2026, tools/faceplate_art/
# face1/v2, scaled from 1448 x 1086 to 1450 x 1085). ONE shared layout, measured on PLATINUM (the
# master): every button, window, lamp and pad has the same rectangle on every face. Only the knob
# centres are fitted per face, so each live pointer sits on that face's own cap.
KNOBS = {"pitch": (768, 130), "tune": (925, 130), "bounce": (1084, 132), "velocity": (1243, 130),
         "filter": (767, 272), "clipDrive": (925, 272), "output": (1084, 272),
         "boost": (207, 518), "punch": (377, 518), "analogEQ": (551, 518), "grit": (724, 518),
         "shine": (896, 518), "tighten": (1068, 518), "noise": (1240, 518)}
ONESHOT, LOOP = [103, 70, 279, 147], [287, 70, 470, 147]
ONESHOT_LAMP, LOOP_LAMP = [156, 79, 218, 104], [344, 79, 406, 104]       # lamp and its glow
MODES = {"modern": [494, 68, 647, 156], "vintage": [494, 160, 647, 243], "texture": [494, 248, 647, 342]}
SCOPE = [106, 163, 466, 339]
CLIPPER = [1206, 241, 1290, 332]
PLAY = [95, 380, 160, 445]
LEDS = {"tempoSync": [327, 385, 351, 409], "followDAW": [327, 415, 351, 439]}
BPM_BOX, BPM_LABEL_SEARCH = [168, 383, 318, 440], [196, 394, 238, 424]
KIT_BOX, KIT_TEXT_SEARCH = [631, 384, 902, 440], [645, 392, 885, 432]
PRESET_BOX, PRESET_TEXT_SEARCH = [1010, 384, 1288, 440], [1024, 392, 1278, 432]
DICE, SAVE = [477, 380, 543, 445], [1295, 380, 1357, 445]
RECORD, EDITOR, EXPORT, MENU = [1121, 21, 1173, 68], [1181, 21, 1234, 68], [1243, 21, 1294, 68], [1303, 21, 1354, 68]
REC_DOT = [1135, 29, 1160, 54]
POWER, SLIDER, LOGO = [107, 968, 167, 1028], [185, 972, 329, 1022], [608, 975, 842, 1027]
# the pads, as drawn on PLATINUM (the other faces line up within a few pixels)
PAD_COLS = [(101, 297), (312, 506), (522, 716), (732, 927), (943, 1137), (1153, 1348)]
PAD_ROWS = [(634, 794), (800, 957)]
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
        for cy in np.arange(y0 - 7, y0 + 7.01, 0.5):
            for cx in np.arange(x0 - 7, x0 + 7.01, 0.5):
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
    off (rows stretched from the clean plate either side, with grain) and the render's own DRIVE,
    lifted from CLIP DRIVE as ink against its plate, goes on centred under the knob."""
    fill_rows(a, [175, 585, 241, 605], grain=1.5)
    word = a[338:357, 916:972, :3].copy()
    l = lum(word)
    bg, ink = np.percentile(l, 90), np.percentile(l, 2)
    alpha = np.clip((bg - l) / max(1, bg - ink), 0, 1)[..., None]
    x0, y0 = 207 - word.shape[1] // 2, 588 - (341 - 338)
    dst = a[y0:y0 + word.shape[0], x0:x0 + word.shape[1], :3]
    a[y0:y0 + word.shape[0], x0:x0 + word.shape[1], :3] = dst * (1 - alpha) + word * alpha


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
        inner, outer, width = pointer_geometry(m, cx, cy, r)
        pointer_stats.append((inner, outer, width))
        # the new renders' pointer carries light streaks either side of its ink: take off a band
        # straight up from the centre to the rim, as wide as the ink plus its glints
        yy, xx = np.mgrid[0:H, 0:W]
        band = (np.abs(xx - cx) < max(6.5, width * r * 0.5 + 4)) & (yy < cy - r * 0.08) & (np.hypot(xx - cx, yy - cy) < r * 1.02)
        remove_pointer(plate, cx, cy, r, m | band)
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
