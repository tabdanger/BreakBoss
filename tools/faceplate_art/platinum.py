# Platinum (Modern's alternate face): prepares Tyrone's two Platinum plates so they go
# through the same cleaning as the other plates, then lines them up with Modern.
# Writes /home/claude/art3/src/{l,p}_platinum.png and adds their entries to knobs/rects.json.
import cv2, numpy as np, json, math
from scipy.interpolate import RBFInterpolator
A2 = "/home/claude/art2"; A3 = "/home/claude/art3"
K = json.load(open(f"{A3}/knobs.json")); R = json.load(open(f"{A3}/rects.json"))
ORDER = ["pitch","tune","bounce","velocity","filter","clipDrive","output","boost","punch","analogEQ","grit","shine","tighten","noise"]

def inpaint(img, mask, r=4):
    return cv2.inpaint(img, (mask > 0).astype(np.uint8) * 255, r, cv2.INPAINT_TELEA)

def glow_dash(img, cx, cy, w, h, color, glow):
    """A small indicator dash like Modern's (red = lit, grey = unlit)."""
    over = np.zeros(img.shape[:2], np.float32)
    cv2.rectangle(over, (int(cx - w / 2), int(cy - h / 2)), (int(cx + w / 2), int(cy + h / 2)), 1.0, -1)
    halo = cv2.GaussianBlur(over, (0, 0), 4) * glow
    out = img.astype(np.float32)
    out = out * (1 - halo[..., None]) + np.array(color[::-1], np.float32) * halo[..., None]
    core = cv2.GaussianBlur(over, (0, 0), 0.7)[..., None]
    out = out * (1 - core) + np.array(color[::-1], np.float32) * core
    return np.clip(out, 0, 255).astype(np.uint8)

# ------------------------------------------------------------------ iPad
l = cv2.imread(f"{A2}/src/l_platinum_v2.png")   # Tyrone's straight-on iPad plate (Oct 13)
# ONE-SHOT unlit (grey dash), LOOP lit (red dash), like Modern's plate.
l = glow_dash(l, 180, 114, 22, 3, (150, 150, 150), 0.0)
l = glow_dash(l, 357, 114, 22, 3, (255, 46, 32), 0.9)
# FOLLOW DAW lit like TEMPO SYNC (the app draws "off" over whichever is off).
src = l[387 - 13:387 + 14, 343 - 13:343 + 14].copy()
yy, xx = np.mgrid[0:27, 0:27]; m = (np.hypot(xx - 13, yy - 13) < 12.5).astype(np.float32)[..., None]
dst = l[421 - 13:421 + 14, 343 - 13:343 + 14].astype(np.float32)
l[421 - 13:421 + 14, 343 - 13:343 + 14] = (dst * (1 - m) + src * m).astype(np.uint8)
# Dice: the link icon becomes the dice (the dice is the randomize button).
Y0, Y1, X0, X1 = 380, 431, 504, 555
cap = l[Y0:Y1, X0:X1]
g = cap.astype(np.float32).mean(2)
icon = (g > np.median(g) + 60).astype(np.uint8)
icon[:6] = 0; icon[-6:] = 0; icon[:, :6] = 0; icon[:, -6:] = 0
cap = inpaint(cap, cv2.dilate(icon, np.ones((5, 5))), 5)
h, w = cap.shape[:2]; S = 8; big = np.zeros((h * S, w * S), np.uint8)
cx, cy, half = w * S // 2, h * S // 2, 11 * S
cv2.rectangle(big, (cx - half, cy - half), (cx + half, cy + half), 255, int(1.8 * S), lineType=cv2.LINE_AA)
for dx, dy in [(-5, -5), (5, -5), (0, 0), (-5, 5), (5, 5)]:
    cv2.circle(big, (cx + dx * S, cy + dy * S), int(1.7 * S), 255, -1, lineType=cv2.LINE_AA)
a = cv2.resize(big, (w, h), interpolation=cv2.INTER_AREA).astype(np.float32)[..., None] / 255
cap = (cap.astype(np.float32) * (1 - a) + np.array([228, 228, 228], np.float32) * a).astype(np.uint8)
l[Y0:Y1, X0:X1] = cap

# Repaint the knob tops: one clean brushed-silver cap for every knob (the art draws each
# knob from a different angle with painted-on pointers; the app draws the live pointer).
lk = json.load(open(f"{A3}/l_plat_knobs.json"))
def silver_cap(rad):
    n = int(rad * 2 + 1); c = rad
    y, x = np.mgrid[0:n, 0:n].astype(np.float32); dx, dy = x - c, y - c
    rho = np.hypot(dx, dy); th = np.arctan2(dy, dx)
    base = 172 + 52 * np.cos(2 * (th + 0.75)) + 18 * np.cos(4 * (th + 0.2))
    base -= 30 * np.clip((rho / rad - 0.82) / 0.18, 0, 1)            # darker rim
    rng = np.random.default_rng(7)
    brushed = cv2.GaussianBlur(rng.normal(0, 1, (n, n)).astype(np.float32), (0, 0), 0.6) * 4
    v = np.clip(base + brushed, 60, 250)
    rgb = np.stack([v * 0.985, v * 0.995, v], -1)                      # cool silver
    alpha = np.clip((rad - rho) / 1.5, 0, 1)
    return rgb, alpha
for k in ORDER:
    x, y, r = lk[k]; rad = r - 2
    rgb, al = silver_cap(rad); n = rgb.shape[0]
    x0, y0 = int(round(x - rad)), int(round(y - rad))
    reg = l[y0:y0 + n, x0:x0 + n].astype(np.float32)
    l[y0:y0 + n, x0:x0 + n] = (reg * (1 - al[..., None]) + rgb[..., ::-1] * al[..., None]).astype(np.uint8)

# ------------------------------------------------------------------ iPhone
p = cv2.imread(f"{A2}/src/p_platinum.png")
# MODERN lit, TEXTURE unlit (the art shows TEXTURE selected).
def mode_box(img, x0, x1, y0=132, y1=198):
    return img[y0:y1, x0:x1].copy()
mod_r, tex_r = (92, 342), (604, 852)
mod = mode_box(p, *mod_r); tex = mode_box(p, *tex_r)
def glyph_alpha(btn, lit):
    """Soft coverage of the label letters (top part of the button)."""
    g = btn.astype(np.float32).mean(2); h, w = g.shape
    bg = cv2.medianBlur(btn, 11).astype(np.float32).mean(2)
    peak = 250.0 if lit else max(150.0, float(np.percentile(g[8:int(h * 0.62), 10:-10], 99.5)))
    al = np.clip((g - bg) / np.maximum(peak - bg, 20), 0, 1)
    al[al < (0.3 if lit else 0.18)] = 0
    al[int(h * 0.62):] = 0; al[:8] = 0; al[:, :12] = 0; al[:, -12:] = 0
    return al
am, at = glyph_alpha(mod, False), glyph_alpha(tex, True)
def clear(btn, al):
    return inpaint(btn, cv2.dilate((al > 0.05).astype(np.uint8), np.ones((7, 7))), 6)
lit_bg = cv2.resize(clear(tex, at), (mod.shape[1], mod.shape[0]), interpolation=cv2.INTER_AREA)
dark_bg = cv2.resize(clear(mod, am), (tex.shape[1], tex.shape[0]), interpolation=cv2.INTER_AREA)
def put_text(bg, al, color):
    a = al[..., None]
    return np.clip(bg.astype(np.float32) * (1 - a) + np.array(color[::-1], np.float32) * a, 0, 255).astype(np.uint8)
p[132:198, mod_r[0]:mod_r[1]] = put_text(lit_bg, am, (246, 246, 246))
p[132:198, tex_r[0]:tex_r[1]] = put_text(dark_bg, at, (214, 214, 214))

# ------------------------------------------------------------------ line both up with Modern
# Where the buttons and windows are on the new iPad plate (dark-cap boxes).
BOXES_L = {"oneShotButton": [98, 61, 263, 126], "loopButton": [276, 61, 432, 126], "mode_modern": [479, 54, 622, 139],
           "mode_vintage": [479, 151, 622, 240], "mode_texture": [479, 251, 622, 340], "scope": [77, 159, 455, 338],
           "playRect": [72, 373, 154, 439], "bpmBox": [169, 370, 303, 438], "diceRect": [499, 379, 560, 439],
           "kitBox": [625, 377, 923, 438], "presetBox": [1037, 375, 1312, 438], "saveRect": [1330, 379, 1392, 439],
           "clipperRect": [1240, 212, 1326, 296]}
LEDS_L = {"ledTempo": (343, 387), "ledFollow": (343, 421)}
from warp import grid_warp, mono_map

def ctrl(knobs, pads):
    P = [knobs[k][:2] for k in ORDER]
    P += [[(q[0] + q[2]) / 2, (q[1] + q[3]) / 2] for q in pads]
    return np.array(P, float)
for dev, img in (("l", l), ("p", p)):
    kn = json.load(open(f"{A3}/{dev}_plat_knobs.json")); pads = json.load(open(f"{A3}/{dev}_plat_pads.json"))
    M = ctrl({k: K[f"{dev}_modern"][k] for k in ORDER}, R[f"{dev}_modern"]["pads"])
    Sp = ctrl(kn, pads)
    if dev == "l":
        # Buttons and windows line up too, not just knobs and pads (center + left/right edges).
        Rm = R["l_modern"]; ex_m, ex_s = [], []
        for key, b in BOXES_L.items():
            t = Rm[key]
            for fx, fy in ((0.5, 0.5), (0.1, 0.5), (0.9, 0.5), (0.5, 0.15), (0.5, 0.85)):
                ex_m.append([t[0] + fx * (t[2] - t[0]), t[1] + fy * (t[3] - t[1])])
                ex_s.append([b[0] + fx * (b[2] - b[0]), b[1] + fy * (b[3] - b[1])])
        for t, b in zip(R["l_modern"]["pads"], pads):      # pad edges too, so the pads match Modern's size
            for fx, fy in ((0.08, 0.5), (0.92, 0.5), (0.5, 0.1), (0.5, 0.9)):
                ex_m.append([t[0] + fx * (t[2] - t[0]), t[1] + fy * (t[3] - t[1])])
                ex_s.append([b[0] + fx * (b[2] - b[0]), b[1] + fy * (b[3] - b[1])])
        for key, (x, y) in LEDS_L.items():
            t = Rm[key]; ex_m.append([(t[0] + t[2]) / 2, (t[1] + t[3]) / 2]); ex_s.append([x, y])
        M = np.vstack([M, ex_m]); Sp = np.vstack([Sp, ex_s])
    H, W = img.shape[:2]
    Aff, _, _, _ = np.linalg.lstsq(np.hstack([Sp, np.ones((len(Sp), 1))]), M, rcond=None)
    if dev == "l":
        # Plate body edges onto Modern's (one axis each), so Modern's wood frame fits around it.
        out = grid_warp(img, M, Sp, Aff, bands=[0, 362, 452, 628, H], xo=[(64, 20), (1390, 1423)], yo=[(8, 18), (1046, 1052)])
    else:
        border = []
        for t in np.linspace(0, 1, 9):
            border += [[t * (W - 1), 0], [t * (W - 1), H - 1], [0, t * (H - 1)], [W - 1, t * (H - 1)]]
        border = np.array(border)
        inv = np.linalg.inv(np.vstack([Aff.T, [0, 0, 1]]))
        bsrc = (np.hstack([border, np.ones((len(border), 1))]) @ inv.T)[:, :2]
        back = RBFInterpolator(np.vstack([M, border]), np.vstack([Sp, bsrc]), kernel="thin_plate_spline", smoothing=400)
        gy, gx = np.mgrid[0:H:8, 0:W:8]
        g = back(np.stack([gx.ravel(), gy.ravel()], 1)).reshape(gy.shape + (2,)).astype(np.float32)
        mx = cv2.resize(g[..., 0], (W, H), interpolation=cv2.INTER_CUBIC); my = cv2.resize(g[..., 1], (W, H), interpolation=cv2.INTER_CUBIC)
        out = cv2.remap(img, mx, my, cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    cv2.imwrite(f"{A3}/src/{dev}_platinum.png", out)
    # Same positions as Modern; knob sizes from Platinum's own caps.
    n = f"{dev}_platinum"
    K[n] = {k: [K[f"{dev}_modern"][k][0], K[f"{dev}_modern"][k][1], float(kn[k][2] - 2)] for k in ORDER}
    R[n] = json.loads(json.dumps(R[f"{dev}_modern"]))
    print(n, "fit residual before warp: %.1f px" % np.abs(np.hstack([Sp, np.ones((len(Sp), 1))]) @ Aff - M).mean())
json.dump(K, open(f"{A3}/knobs.json", "w"), indent=1); json.dump(R, open(f"{A3}/rects.json", "w"), indent=1)
