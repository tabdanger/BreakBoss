# One look on every faceplate (Tyrone, Oct 13): every control sits exactly where Modern's does,
# every plate wears Platinum's knobs, and every plate has Modern's wood frame.
#
#  1. Vintage and Texture (iPad + iPhone) are warped onto Modern with a straight-line grid warp
#     anchored on knobs, pads, every button and window (centre + edges) and the plate body edges.
#  2. Platinum's knobs (cut out one by one, with their own perspective) are pasted on Modern,
#     Vintage and Texture at Modern's knob positions; the old knobs are cleared first.
#  3. Modern's wood (iPad: the whole outer frame; iPhone: the side strips) goes on every plate.
# Run after platinum.py, before clean.py and buttons.py, from /home/claude/art3.
import json, numpy as np, cv2
from warp import grid_warp     # same straight-line warp as the Platinum plate
import textdraw
LABELS = json.load(open("labels_modern.json"))   # Modern's label boxes (labels.py measurement)
LABEL_TEXT = {"pitch": "PITCH", "tune": "TUNE", "bounce": "BOUNCE", "velocity": "VELOCITY", "filter": "FILTER",
              "clipDrive": "CLIP DRIVE", "output": "OUTPUT", "boost": "BOOST", "punch": "PUNCH", "analogEQ": "ANALOG EQ",
              "grit": "GRIT", "shine": "SHINE", "tighten": "TIGHTEN", "noise": "NOISE", "clipper": "CLIPPER"}

A2 = "/home/claude/art2"
K2 = json.load(open(f"{A2}/knobs.json")); R2 = json.load(open(f"{A2}/rects.json"))
K = json.load(open("knobs.json")); R = json.load(open("rects.json"))
ORDER = ["pitch","tune","bounce","velocity","filter","clipDrive","output","boost","punch","analogEQ","grit","shine","tighten","noise"]
BOXES = ['scope','kitBox','presetBox','playRect','oneShotButton','loopButton','clipperRect','saveRect','diceRect','bpmBox',
         'mode_modern','mode_vintage','mode_texture']
LEDS = ['ledTempo', 'ledFollow']
# iPad export / menu caps measured by eye at 4x on the original plates.
CAPS = {"l_modern": ((1279, 31, 1324, 77), (1330, 31, 1374, 77)),
        "l_vintage": ((1285, 26, 1326, 75), (1330, 26, 1371, 74)),
        "l_texture": ((1270, 35, 1316, 79), (1324, 35, 1368, 78))}
# Plate body edges (left, right, top, bottom) measured on the originals at 4x.
BODY = {"l_modern": (64, 1390, 8, 1046), "l_vintage": (64, 1389, 10, 1049), "l_texture": (67, 1387, 13, 1068),
        "p_modern": (62, 882, None, None), "p_vintage": (64, 879, None, None), "p_texture": (64, 877, None, None)}
BANDS = {"l": [0, 362, 452, 628, None], "p": [0, 118, 205, 365, 640, 757, 915, 1170, None]}
F5 = ((0.5, 0.5), (0.1, 0.5), (0.9, 0.5), (0.5, 0.15), (0.5, 0.85))

def anchors(n, Kn, Rn, H, W):
    P = [Kn[k][:2] for k in ORDER]
    for key in BOXES:
        x0, y0, x1, y1 = Rn[key]; P += [[x0 + fx * (x1 - x0), y0 + fy * (y1 - y0)] for fx, fy in F5]
    for key in LEDS:
        x0, y0, x1, y1 = Rn[key]; P.append([(x0 + x1) / 2, (y0 + y1) / 2])
    for x0, y0, x1, y1 in Rn["pads"]:
        P += [[x0 + fx * (x1 - x0), y0 + fy * (y1 - y0)] for fx, fy in F5]
    if n in CAPS:
        for x0, y0, x1, y1 in CAPS[n]: P.append([(x0 + x1) / 2, (y0 + y1) / 2])
    return np.array(P, float)

def warp_onto_modern(dev, mode):
    n, m = f"{dev}_{mode}", f"{dev}_modern"
    img = cv2.imread(f"{A2}/src/{n}.png"); H, W = img.shape[:2]
    M = anchors(m, K2[m], R2[m], H, W); S = anchors(n, K2[n], R2[n], H, W)
    assert len(M) == len(S)
    Aff, _, _, _ = np.linalg.lstsq(np.hstack([S, np.ones((len(S), 1))]), M, rcond=None)
    bands = [b if b is not None else H for b in BANDS[dev]]
    (ml, mr, mt, mb), (sl, sr, st, sb) = BODY[m], BODY[n]
    out = grid_warp(img, M, S, Aff, bands, xo=[(ml, sl), (mr, sr)], yo=[(mt, st), (mb, sb)] if mt is not None else [])
    print(n, "anchors", len(M))
    return out

# ---------------------------------------------------------------- Platinum knobs
def knob_sprites(dev):
    """The BreakBoss knob (knobgen.py) for each knob position, at Modern's knob sizes."""
    from knobgen import knob, dot_ring
    sprites = {}
    for k in ORDER:
        R = K2[f"{dev}_modern"][k][2]
        rgb, a, sh, h = knob(R, seed=ORDER.index(k) + 1)
        sprites[k] = (rgb[..., ::-1].copy(), a, h, dot_ring(R, h), sh)
    return sprites

def paste_knobs(img, dev, n, sprites):
    out = img.astype(np.float32)
    labels = []
    for k in ORDER:
        x, y, _ = K[f"{dev}_modern"][k]; x, y = int(round(x)), int(round(y))
        rgb, a, h, ring, shadow = sprites[k]
        y0, x0 = y - h, x - h; sl = (slice(y0, y0 + rgb.shape[0]), slice(x0, x0 + rgb.shape[1]))
        # clear the plate's own knob (cap + skirt) so nothing peeks out around the new one
        ro = (K2[f"{dev}_{n}"] if f"{dev}_{n}" in K2 else K[f"{dev}_platinum"])[k][2]
        reg = out[sl].astype(np.uint8)
        nn = reg.shape[0]; yy, xx = np.mgrid[0:nn, 0:nn]
        prho = np.hypot(xx - h, yy - h)
        # Clear the whole knob cell: old knob, shadow, tick marks and label (all redrawn below).
        lb = LABELS[dev][k]
        big = 2.15 if n == "platinum" else 1.95      # Platinum's old knobs threw wider highlights
        old = ((prho < ro * big) & (yy > h - ro * 1.6)).astype(np.uint8)
        lx0, lx1 = lb[0] - x0 - 10, lb[2] - x0 + 10
        old[max(0, lb[1] - y0 - 7):lb[3] - y0 + 16, max(0, min(lx0, h - int(ro * 1.6))):max(lx1, h + int(ro * 1.6))] = 1
        if old.any():
            # smooth plate colour from around the knob (normalised blur), no smearing
            f = reg.astype(np.float32)
            fl = f.mean(2); ref = float(np.median(fl[(prho > ro * 1.7) & (prho < ro * 2.2)]))
            # plate colour only: not the old knob, not labels or marks
            w = ((1 - cv2.dilate(old, np.ones((11, 11), np.uint8))) * (np.abs(fl - ref) < 35)).astype(np.float32)
            # Row by row: blend between the clean plate pixels left and right of the cleared area,
            # so brushed metal streaks and painted shading carry straight through.
            num = cv2.GaussianBlur(f * w[..., None], (0, 0), 12, borderType=cv2.BORDER_CONSTANT)
            den = cv2.GaussianBlur(w, (0, 0), 12, borderType=cv2.BORDER_CONSTANT)[..., None]
            fill = np.where(den > 1e-3, num / np.maximum(den, 1e-3), ref)   # fallback for rows with no clean ends
            okc = w > 0.5
            for yy_ in range(f.shape[0]):
                cols = np.nonzero(okc[yy_])[0]
                if len(cols) < 2 or cols.min() > f.shape[1] * 0.3 or cols.max() < f.shape[1] * 0.7: continue
                fill[yy_] = np.stack([np.interp(np.arange(f.shape[1]), cols, f[yy_, cols, ch]) for ch in range(3)], 1)
            fill = cv2.GaussianBlur(fill, (0, 0), sigmaX=0.6, sigmaY=1.6)
            # the plate's own grain: noise with the same strength as the plate around it
            # (stretched sideways, like brushed metal and painted panels)
            hp = fl - cv2.GaussianBlur(fl, (0, 0), 3)
            sd = float(np.median(np.abs(hp[w > 0.5]))) * 1.48 if (w > 0.5).sum() > 50 else 2.0
            sd = min(sd, 3.5)
            rng_ = np.random.default_rng(int(x * 7 + y))
            nz = cv2.GaussianBlur(rng_.normal(0, 1, fl.shape).astype(np.float32), (0, 0), sigmaX=6.0, sigmaY=0.5)
            nz *= sd / max(float(nz.std()), 1e-3)
            fill = fill + nz[..., None]
            o = np.clip(cv2.GaussianBlur(old.astype(np.float32), (0, 0), 4.0) * 1.6, 0, 1)
            o = np.maximum(o, old.astype(np.float32))[..., None]   # soft edge reaching outward
            reg = np.clip(f * (1 - o) + fill * o, 0, 255).astype(np.uint8)
        reg = reg.astype(np.float32)
        # Platinum's dot ring, dark on light plates and light on dark ones
        bgl = float(reg[(prho > ro * 1.3) & (prho < ro * 1.6)].mean())
        dot = np.array([38, 38, 40] if bgl > 120 else [214, 214, 216], np.float32)
        reg = reg * (1 - ring[..., None]) + dot * ring[..., None]
        # soft contact shadow, down and to the right like the Platinum art
        reg = reg * (1 - shadow[..., None])
        reg = reg * (1 - a[..., None]) + rgb * a[..., None]
        out[sl] = reg
        # the label, in Modern's place and size, in this plate's ink
        lb = LABELS[dev][k]
        ink = (44, 44, 46) if bgl > 120 else (224, 224, 226)
        labels.append((LABEL_TEXT[k], x, lb[1], lb[3] - lb[1], ink, lb[2] - lb[0]))
    # labels last, so clearing a neighbouring knob cell can't cut into them
    for text, cx, top, ch, ink, tw in labels:
        textdraw.draw(out, text, cx, top, ch, ink, target_w=tw)
    return np.clip(out, 0, 255).astype(np.uint8)

# ---------------------------------------------------------------- the rest of the lettering
TEXT_ITEMS = {"clipper": "CLIPPER", "ledTempo": "TEMPO SYNC", "ledFollow": "FOLLOW DAW", "kits": "KITS", "presets": "PRESETS",
              "oneShotButton": "ONE-SHOT", "loopButton": "LOOP", "mode_modern": "MODERN", "mode_vintage": "VINTAGE",
              "mode_texture": "TEXTURE"}
BUTTONS = ("oneShotButton", "loopButton", "mode_modern", "mode_vintage", "mode_texture")

def row_fill(f, mask):
    """Fills mask pixels of f (float HxWx3) row by row from the nearest clean pixels left and right."""
    out = f.copy()
    todo = mask.copy()
    for yy in range(f.shape[0]):
        cols = np.nonzero(~mask[yy])[0]
        bad = np.nonzero(mask[yy])[0]
        if len(cols) < 2 or len(bad) == 0: continue
        for ch in range(3):
            out[yy, bad, ch] = np.interp(bad, cols, f[yy, cols, ch])
        todo[yy] = False
    # rows with no clean pixels on either side: fill those columns from above and below
    for xx in range(f.shape[1]):
        bad = np.nonzero(todo[:, xx])[0]
        rows = np.nonzero(~mask[:, xx])[0]
        if len(bad) == 0 or len(rows) < 2: continue
        for ch in range(3):
            out[bad, xx, ch] = np.interp(bad, rows, f[rows, xx, ch])
    return cv2.GaussianBlur(out, (0, 0), sigmaX=0.5, sigmaY=1.0) * mask[..., None] + f * (~mask[..., None])

def erase_letters(reg, box):
    """Removes only the letter pixels inside box (x0, y0, x1, y1 in reg), filling each from the
    plate right around it, so the background keeps its own shading and no patch shows."""
    f = reg.astype(np.float32)
    lum = f.mean(2)
    bg = cv2.medianBlur(np.clip(lum, 0, 255).astype(np.uint8), 21).astype(np.float32)
    ink = np.abs(lum - bg) > 16
    x0, y0, x1, y1 = [int(v) for v in box]
    lim = np.zeros(ink.shape, bool); lim[max(0, y0):y1, max(0, x0):x1] = True
    m = cv2.dilate((ink & lim).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=2).astype(bool) & lim
    if not m.any(): return f
    w = (~cv2.dilate(m.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)).astype(np.float32)
    fill = f.copy()
    for sig in (2.0, 4.0, 8.0):          # small first, wider where the letters were thick
        num = cv2.GaussianBlur(f * w[..., None], (0, 0), sig); den = cv2.GaussianBlur(w, (0, 0), sig)[..., None]
        est = num / np.maximum(den, 1e-4)
        ok = (den[..., 0] > 0.15) & m & (fill == f).all(2)
        fill[ok] = est[ok]
    rest = m & (fill == f).all(2)
    if rest.any():
        num = cv2.GaussianBlur(f * w[..., None], (0, 0), 14); den = cv2.GaussianBlur(w, (0, 0), 14)[..., None]
        fill[rest] = (num / np.maximum(den, 1e-4))[rest]
    # the plate's own fine grain on the filled pixels
    hp = lum - cv2.GaussianBlur(lum, (0, 0), 2)
    sd = min(3.0, float(np.median(np.abs(hp[w > 0.5]))) * 1.48) if (w > 0.5).sum() > 20 else 1.0
    nz = cv2.GaussianBlur(np.random.default_rng(int(lum.sum()) % 99991).normal(0, 1, lum.shape).astype(np.float32), (0, 0), 0.7)
    nz *= sd / max(float(nz.std()), 1e-3)
    fill = fill + (nz[..., None] * m[..., None])
    o = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 0.8)[..., None]
    return np.clip(f * (1 - o) + fill * o, 0, 255)

def redraw_text(img, dev):
    """Every printed word in Modern's place and size, in Aldrich, in this plate's own ink."""
    out = img.astype(np.float32)
    L = LABELS[dev]; Rm = R2[f"{dev}_modern"]
    jobs = []
    for key, text in TEXT_ITEMS.items():
        if key == "clipper" or key not in L or L[key] is None: continue
        bx0, by0, bx1, by1 = L[key]
        px, py = (10, 5) if key in BUTTONS else (14, 6)
        X0, Y0, X1, Y1 = bx0 - px - 12, by0 - py - 6, bx1 + px + 12, by1 + py + 6
        if key in ("ledTempo", "ledFollow"):   # never touch the lamp
            X0 = max(X0, Rm[key][2] + 3)
        if key in BUTTONS:   # stay inside the button cap
            b = Rm[key]; X0, Y0, X1, Y1 = max(X0, b[0] + 5), max(Y0, b[1] + 4), min(X1, b[2] - 5), min(Y1, b[3] - 4)
        reg = out[Y0:Y1, X0:X1]
        lum = reg.mean(2); med = float(np.median(lum))
        ink_mask = np.abs(lum - med) > 35
        if ink_mask.sum() > 8:
            sign = np.sign(float(np.mean(lum[ink_mask]) - med))
            strong = ink_mask & ((lum - med) * sign > np.percentile((lum[ink_mask] - med) * sign, 60))
            ink = tuple(float(v) for v in reg[strong].mean(0))
        else:
            ink = (44, 44, 46) if med > 120 else (224, 224, 226)
        if key not in BUTTONS:       # printed on the plate: the same ink as the knob labels
            ink = (44, 44, 46) if med > 120 else (224, 224, 226)
        ex = 6 if key in BUTTONS else 16
        out[Y0:Y1, X0:X1] = erase_letters(reg, (bx0 - X0 - ex, by0 - Y0 - 5, bx1 - X0 + ex, by1 - Y0 + 5))
        jobs.append((text, (bx0 + bx1) / 2, by0, by1 - by0, ink, bx1 - bx0))
    for text, cx, top, ch, ink, tw in jobs:
        textdraw.draw(out, text, cx, top, ch, ink, target_w=tw)
    return np.clip(out, 0, 255).astype(np.uint8)

def redraw_clipper_label(img, dev):
    out = img.astype(np.float32)
    bx0, by0, bx1, by1 = LABELS[dev]["clipper"]
    X0, Y0, X1, Y1 = bx0 - 30, by0 - 8, bx1 + 30, by1 + 10
    reg = out[Y0:Y1, X0:X1]; med = float(np.median(reg.mean(2)))
    out[Y0:Y1, X0:X1] = erase_letters(reg, (8, 2, reg.shape[1] - 8, reg.shape[0] - 2))
    ink = (44, 44, 46) if med > 120 else (224, 224, 226)
    textdraw.draw(out, "CLIPPER", (bx0 + bx1) / 2, by0, by1 - by0, ink, target_w=bx1 - bx0)
    return np.clip(out, 0, 255).astype(np.uint8)

# ---------------------------------------------------------------- Platinum's lights (iPad art)
def platinum_lights(img, modern):
    """The Platinum iPad art has an amber dash under MODERN and its own dark clipper lamp.
    Both become Modern's: a red dash, and Modern's lit ON button inside Platinum's silver frame."""
    out = img.astype(np.float32); mod = modern.astype(np.float32)
    # MODERN dash: amber -> Modern's red, same brightness and glow shape
    x0, y0, x1, y1 = R2["l_modern"]["mode_modern"]
    reg = out[y0:y1 + 12, x0:x1]
    b, g, r = reg[..., 0], reg[..., 1], reg[..., 2]
    amber = np.clip((r - b - 25) / 60, 0, 1) * np.clip((g - b - 10) / 40, 0, 1)
    amber = cv2.GaussianBlur(amber, (0, 0), 0.8)[..., None]
    lum = reg.max(2, keepdims=True)
    red = np.concatenate([lum * 0.16, lum * 0.18, lum], 2)
    red[..., 1:2][lum > 235] = 225; red[..., 0:1][lum > 235] = 225          # hot white core like Modern's
    out[y0:y1 + 12, x0:x1] = reg * (1 - amber) + red * amber
    # Clipper: Modern's lit button in Platinum's bezel
    cx0, cy0, cx1, cy1 = R2["l_modern"]["clipperRect"]
    pad = 12
    P = out[cy0 - pad:cy1 + pad, cx0 - pad:cx1 + pad]
    lumP = P.mean(2)
    dark = (lumP < 70).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(dark)
    k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    x, y, w, h = st[k, :4]                       # Platinum's dark well inside the silver bezel
    src = mod[cy0:cy1, cx0:cx1]
    lit = (src.max(2) > 90).astype(np.uint8)     # Modern's lit face (red + glow + ON)
    ys, xs = np.nonzero(lit)
    face = src[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    inset = 3
    face = cv2.resize(face, (w - 2 * inset, h - 2 * inset), interpolation=cv2.INTER_AREA)
    m = np.zeros((h - 2 * inset, w - 2 * inset), np.float32); m[2:-2, 2:-2] = 1
    m = cv2.GaussianBlur(m, (0, 0), 1.2)[..., None]
    tgt = P[y + inset:y + h - inset, x + inset:x + w - inset]
    P[y + inset:y + h - inset, x + inset:x + w - inset] = tgt * (1 - m) + face * m
    # a little red spill on the bezel, like the lamp on the other plates
    glow = np.zeros(lumP.shape, np.float32); glow[y:y + h, x:x + w] = 1
    glow = np.clip(cv2.GaussianBlur(glow, (0, 0), 5) - glow, 0, 1)[..., None] * 0.35
    P[:] = P * (1 - glow) + np.array([40, 40, 255], np.float32) * glow
    return np.clip(out, 0, 255).astype(np.uint8)

# ---------------------------------------------------------------- wood
def wood_mask(dev, H, W):
    m = np.zeros((H, W), np.float32)
    if dev == "l":
        L, Rr, T, B = BODY["l_modern"]
        m[:, :L - 3] = 1; m[:, Rr + 3:] = 1; m[:T, :] = 1; m[B + 2:, :] = 1
    else:
        L, Rr, _, _ = BODY["p_modern"]
        m[:, :L - 2] = 1; m[:, Rr + 2:] = 1
    return cv2.GaussianBlur(m, (0, 0), 1.2)[..., None]

if __name__ == "__main__":
    for dev in "lp":
        modern = cv2.imread(f"{A2}/src/{dev}_modern.png"); H, W = modern.shape[:2]
        wm = wood_mask(dev, H, W)
        # The frame every plate gets: Modern's, with the left wood an exact mirror of the right.
        frame = modern.copy()
        Rr = BODY[f"{dev}_modern"][1]
        side = W - (Rr + 2)                      # width of the right-hand wood strip
        frame[:, :side] = modern[:, ::-1][:, :side]
        lm = np.zeros((H, W), np.float32); lm[:, :side] = 1
        lm = cv2.GaussianBlur(lm, (0, 0), 1.0)[..., None]
        sprites = knob_sprites(dev)
        plates = {"modern": modern, "vintage": warp_onto_modern(dev, "vintage"), "texture": warp_onto_modern(dev, "texture"),
                  "platinum": cv2.imread(f"src/{dev}_platinum.png")}
        if dev == "l":
            plates["platinum"] = platinum_lights(plates["platinum"], modern)
        for mode, img in plates.items():
            img = paste_knobs(img, dev, mode, sprites)
            img = redraw_clipper_label(img, dev)
            img = redraw_text(img, dev)
            if mode == "platinum" and dev == "l":
                # same BPM display as the other plates ("121 BPM", digits first)
                bx0, by0, bx1, by1 = R2["l_modern"]["bpmBox"]
                img[by0 + 3:by1 - 3, bx0 + 3:bx1 - 3] = modern[by0 + 3:by1 - 3, bx0 + 3:bx1 - 3]
            if mode != "modern":
                img = (img.astype(np.float32) * (1 - wm) + frame.astype(np.float32) * wm).astype(np.uint8)
            img = (img.astype(np.float32) * (1 - lm) + frame.astype(np.float32) * lm).astype(np.uint8)
            cv2.imwrite(f"src/{dev}_{mode}.png", img)
        # Every plate: Modern's boxes, Platinum's knob sizes at Modern's positions.
        for mode in ("modern", "vintage", "texture", "platinum"):
            n = f"{dev}_{mode}"
            K[n] = {k: [K2[f"{dev}_modern"][k][0], K2[f"{dev}_modern"][k][1], K2[f"{dev}_modern"][k][2]] for k in ORDER}
            if mode != "modern":
                keep = {key: R[n][key] for key in R[n] if key.endswith("_score")} if n in R else {}
                R[n] = json.loads(json.dumps(R[f"{dev}_modern"])); R[n].update(keep)
    json.dump(K, open("knobs.json", "w"), indent=1); json.dump(R, open("rects.json", "w"), indent=1)
    caps = json.load(open("caps.json"))
    for n in ("l_vintage", "l_texture"): caps[n] = caps["l_modern"]
    json.dump(caps, open("caps.json", "w"))
    print("done")
