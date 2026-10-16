# Platinum is the master (Tyrone, Oct 14): "KEEP Platinum layout and match every other faceplate around it".
# Measures Tyrone's iPad Platinum plate as it is (no warp), and prepares it:
#   - fixes from platinum.py (ONE-SHOT/LOOP dashes, FOLLOW DAW lamp, dice icon), already in src/l_platinum_raw.png
#   - grey dashes under VINTAGE / TEXTURE (like ONE-SHOT), MODERN's dash red
#   - the clipper: Modern's lit ON button inside Platinum's bezel
#   - BPM window reads "121 BPM" like the other plates (the app draws the digits)
#   - the tiny ghost word above the KITS box removed
# Then fits the plate body into Modern's wood frame (one straight scale, no warp) and writes
# src/l_platinum_P.png and plat_geom_l.json (every knob, pad, button, window, label and panel).
import json, numpy as np, cv2
import textdraw
A2 = "/home/claude/art2"
ORDER = ["pitch","tune","bounce","velocity","filter","clipDrive","output","boost","punch","analogEQ","grit","shine","tighten","noise"]
raw = cv2.imread("src/l_platinum_raw.png")
modern = cv2.imread(f"{A2}/src/l_modern.png")
R2 = json.load(open(f"{A2}/rects.json"))["l_modern"]
H, W = raw.shape[:2]

KN = json.load(open("l_plat_knobs.json")); PADS = json.load(open("l_plat_pads.json"))
BOX = {"oneShotButton": [98, 61, 263, 126], "loopButton": [276, 61, 432, 126], "mode_modern": [479, 54, 622, 139],
       "mode_vintage": [479, 151, 622, 240], "mode_texture": [479, 251, 622, 340], "scope": [77, 159, 455, 338],
       "playRect": [72, 373, 154, 439], "bpmBox": [169, 370, 303, 438], "diceRect": [499, 379, 560, 439],
       "kitBox": [625, 377, 923, 438], "presetBox": [1037, 375, 1312, 438], "saveRect": [1330, 379, 1392, 439],
       "clipperRect": [1240, 212, 1326, 296]}
LED = {"ledTempo": (343, 387), "ledFollow": (343, 421)}
REG = {"upper": [648, 46, 1393, 345], "lower": [57, 461, 1396, 616], "well": [60, 636, 1392, 1004], "tray": [74, 52, 456, 138]}
BODY = [25, 21, 1424, 1050]

def dash(img, cx, cy, w, h, color, glow):
    over = np.zeros(img.shape[:2], np.float32)
    cv2.rectangle(over, (int(cx - w / 2), int(cy - h / 2)), (int(cx + w / 2), int(cy + h / 2)), 1.0, -1)
    halo = cv2.GaussianBlur(over, (0, 0), 4)[..., None] * glow
    out = img.astype(np.float32)
    out = out * (1 - halo) + np.array(color[::-1], np.float32) * halo
    core = cv2.GaussianBlur(over, (0, 0), 0.7)[..., None]
    out = out * (1 - core) + np.array(color[::-1], np.float32) * core
    return np.clip(out, 0, 255).astype(np.uint8)

a = raw.copy()
# ---- MODERN's amber dash -> red (same brightness, hot core), like the other plates
x0, y0, x1, y1 = BOX["mode_modern"]
reg = a[y0:y1 + 12, x0:x1].astype(np.float32)
b, g, r = reg[..., 0], reg[..., 1], reg[..., 2]
amber = np.clip((r - b - 25) / 60, 0, 1) * np.clip((g - b - 10) / 40, 0, 1)
amber = cv2.GaussianBlur(amber, (0, 0), 0.8)[..., None]
lum = reg.max(2, keepdims=True)
red = np.concatenate([lum * 0.16, lum * 0.18, lum], 2)
red[..., 1:2][lum > 235] = 225; red[..., 0:1][lum > 235] = 225
a[y0:y1 + 12, x0:x1] = np.clip(reg * (1 - amber) + red * amber, 0, 255).astype(np.uint8)
# where MODERN's dash sits, relative to its cap -> grey dashes on VINTAGE and TEXTURE
ys, xs = np.nonzero(amber[..., 0] > 0.5)
dy = (ys.mean() + y0 - y0) / (y1 - y0); dw = xs.max() - xs.min() + 1
for key in ("mode_vintage", "mode_texture"):
    q = BOX[key]
    a = dash(a, (q[0] + q[2]) / 2, q[1] + dy * (q[3] - q[1]), dw, 3, (150, 150, 150), 0.0)

# ---- clipper: Modern's lit ON face inside Platinum's bezel
cx0, cy0, cx1, cy1 = BOX["clipperRect"]
P = a[cy0:cy1, cx0:cx1].astype(np.float32)
redness = P[..., 2] - P[..., 1]
inner = (P.mean(2) < 70) | (redness > 40)
inner = cv2.morphologyEx(inner.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
n, lab, st, _ = cv2.connectedComponentsWithStats(inner)
k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])); x, y, w, h = st[k, :4]
m0 = R2["clipperRect"]; src = modern[m0[1]:m0[3], m0[0]:m0[2]].astype(np.float32)
lit = (src.max(2) > 90).astype(np.uint8); yy_, xx_ = np.nonzero(lit)
face = src[yy_.min():yy_.max() + 1, xx_.min():xx_.max() + 1]
face = cv2.resize(face, (w, h), interpolation=cv2.INTER_AREA)
mm = np.zeros((h, w), np.float32); mm[1:-1, 1:-1] = 1; mm = cv2.GaussianBlur(mm, (0, 0), 0.8)[..., None]
P[y:y + h, x:x + w] = P[y:y + h, x:x + w] * (1 - mm) + face * mm
glow = np.zeros(P.shape[:2], np.float32); glow[y:y + h, x:x + w] = 1
glow = np.clip(cv2.GaussianBlur(glow, (0, 0), 4) - glow, 0, 1)[..., None] * 0.3
P = P * (1 - glow) + np.array([40, 40, 255], np.float32) * glow
a[cy0:cy1, cx0:cx1] = np.clip(P, 0, 255).astype(np.uint8)

# ---- BPM window: "121 BPM" (digits first, like every other plate)
bx0, by0, bx1, by1 = BOX["bpmBox"]
ins = 9
win = a[by0 + ins:by1 - ins, bx0 + ins:bx1 - ins].astype(np.float32)
lw = win.mean(2); ink = lw > np.median(lw) + 30
ink_col = np.percentile(win[ink], 90, axis=0)[::-1] if ink.any() else np.array([232, 222, 196])
ink_d = cv2.dilate(ink.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
bg = np.median(win[~ink_d], axis=0)
# the window's own dark glass: fill letters from the clean pixels in the same row
for yy in range(win.shape[0]):
    bad = ink_d[yy]
    if bad.any():
        good = np.nonzero(~bad)[0]
        for ch in range(3): win[yy, bad, ch] = np.interp(np.nonzero(bad)[0], good, win[yy, good, ch])
a[by0 + ins:by1 - ins, bx0 + ins:bx1 - ins] = np.clip(win, 0, 255).astype(np.uint8)
f = a.astype(np.float32)
cy_txt = (by0 + by1) / 2; cap = 15
col = tuple(float(v) for v in ink_col)
textdraw.draw(f, "121", bx0 + 52, cy_txt - cap / 2, cap, col)
textdraw.draw(f, "BPM", bx0 + 100, cy_txt - cap / 2, cap, col)
a = np.clip(f, 0, 255).astype(np.uint8)

# ---- ghost word above the KITS box, and the faint old KITS word (redrawn later like PRESETS)
for gx0, gy0, gx1, gy1 in ((745, 362, 790, 375), (592, 390, 617, 414)):
  if True:
    reg = a[gy0:gy1, gx0:gx1].astype(np.float32)
    for yy in range(reg.shape[0]):
        row = a[gy0 + yy].astype(np.float32)
        for ch in range(3):
            reg[yy, :, ch] = np.interp(np.arange(gx0, gx1), [gx0 - 3, gx1 + 2], [row[gx0 - 3, ch], row[gx1 + 2, ch]])
    a[gy0:gy1, gx0:gx1] = np.clip(reg, 0, 255).astype(np.uint8)

# ---------------------------------------------------------------- labels (measured on the art)
Lm = a.astype(np.float32).mean(2)
def ink_box(x0, y0, x1, y1, dark=True, th=45):
    sub = Lm[y0:y1, x0:x1]; med = float(np.median(sub))
    m = (sub < 60) if dark else (sub > med + th)
    rows = m.sum(1) >= 6
    runs = []; i = 0
    while i < len(rows):
        if rows[i]:
            j = i
            while j + 1 < len(rows) and rows[j + 1]: j += 1
            runs.append((i, j)); i = j + 1
        else: i += 1
    runs = [r for r in runs if 6 <= r[1] - r[0] + 1 <= 22] or runs
    r0, r1 = max(runs, key=lambda r: m[r[0]:r[1] + 1].sum())
    cols = np.nonzero(m[r0:r1 + 1].any(0))[0]
    # keep the word: the column clusters around the centre, gaps under 14 px
    cl = []; s0 = cols[0]; p = cols[0]
    for c in cols[1:]:
        if c - p > 14: cl.append((s0, p)); s0 = c
        p = c
    cl.append((s0, p))
    mid = (x1 - x0) / 2
    best = max(cl, key=lambda q: m[r0:r1 + 1, q[0]:q[1] + 1].sum() - 0.0 * abs((q[0] + q[1]) / 2 - mid))
    return [int(x0 + best[0]), int(y0 + r0), int(x0 + best[1] + 1), int(y0 + r1 + 1)]
LB = {}
for k in ORDER:
    x, y, r = KN[k]
    LB[k] = ink_box(int(x - 70), int(y + r + 18), int(x + 70), int(y + r + 52))
c = BOX["clipperRect"]; LB["clipper"] = ink_box(c[0] - 20, c[3] + 6, c[2] + 20, c[3] + 34)
for key, (x, y) in LED.items(): LB[key] = ink_box(x + 14, y - 11, x + 160, y + 11)
LB["presets"] = ink_box(955, 392, 1034, 420)
pr = LB["presets"]; LB["kits"] = [591, pr[1], 620, pr[3]]
for key in ("oneShotButton", "loopButton", "mode_modern", "mode_vintage", "mode_texture"):
    q = BOX[key]; hh = q[3] - q[1]
    LB[key] = ink_box(q[0] + 12, q[1] + 8, q[2] - 12, int(q[1] + hh * 0.62), dark=False, th=70)

# ---------------------------------------------------------------- clear Platinum's own knobs and lettering
# (every plate gets the same new knobs and Aldrich words afterwards). Row by row: the silver is brushed
# sideways, so a straight blend between the clean pixels either side of each row keeps the grain and light.
def row_clear(img, mask, seed):
    f = img.astype(np.float32); out = f.copy()
    for yy in np.nonzero(mask.any(1))[0]:
        xs = np.nonzero(mask[yy])[0]
        # contiguous runs on this row
        runs = np.split(xs, np.nonzero(np.diff(xs) > 1)[0] + 1)
        for run in runs:
            l, r = run[0] - 2, run[-1] + 2
            lv = f[yy, max(l - 3, 0):l + 1].mean(0); rv = f[yy, r:r + 4].mean(0)
            t = (np.arange(l + 1, r) - l) / (r - l)
            out[yy, l + 1:r] = lv[None] * (1 - t[:, None]) + rv[None] * t[:, None]
    lum = f.mean(2)
    hp = lum - cv2.GaussianBlur(lum, (0, 0), 3)
    sd = min(6.0, float(np.median(np.abs(hp[~mask]))) * 1.6)
    nz = cv2.GaussianBlur(np.random.default_rng(seed).normal(0, 1, lum.shape).astype(np.float32), (0, 0), sigmaX=14.0, sigmaY=0.5)
    nz *= sd / max(float(nz.std()), 1e-3)
    out = out + nz[..., None] * mask[..., None]
    soft = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), 0.7)[..., None]
    return np.clip(f * (1 - soft) + out * soft, 0, 255).astype(np.uint8)

clr = np.zeros((H, W), np.uint8)
for k in ORDER:
    x, y, r = KN[k]
    cv2.circle(clr, (int(round(x - 2)), int(round(y + 4))), int(round(r * 1.85)), 1, -1)
for k, b in LB.items():
    if k.startswith("mode_") or k in ("oneShotButton", "loopButton", "kits"): continue
    cv2.rectangle(clr, (b[0] - 3, b[1] - 3), (b[2] + 3, b[3] + 3), 1, -1)
a = row_clear(a, clr.astype(bool), 11)

# ---------------------------------------------------------------- fit into Modern's wood frame
TGT = [64 - 2, 8 + 2, 1390 + 2, 1046 + 2]          # Modern's body edges (wood starts just outside)
sx = (TGT[2] - TGT[0]) / (BODY[2] - BODY[0]); sy = (TGT[3] - TGT[1]) / (BODY[3] - BODY[1])
tx = TGT[0] - BODY[0] * sx; ty = TGT[1] - BODY[1] * sy
M = np.float32([[sx, 0, tx], [0, sy, ty]])
out = cv2.warpAffine(a, M, (W, H), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
# the plate's rounded corners sit on Modern's dark case, not on the grey backdrop
body = np.zeros((H, W), np.uint8)
rad = 24
bx = [int(round(v)) for v in (TGT[0], TGT[1], TGT[2], TGT[3])]
cv2.rectangle(body, (bx[0] + rad, bx[1]), (bx[2] - rad, bx[3]), 255, -1); cv2.rectangle(body, (bx[0], bx[1] + rad), (bx[2], bx[3] - rad), 255, -1)
for cx_, cy_ in ((bx[0] + rad, bx[1] + rad), (bx[2] - rad, bx[1] + rad), (bx[0] + rad, bx[3] - rad), (bx[2] - rad, bx[3] - rad)):
    cv2.circle(body, (cx_, cy_), rad, 255, -1)
bm = cv2.GaussianBlur(body.astype(np.float32) / 255, (0, 0), 1.0)[..., None]
case = np.full_like(out, (18, 18, 19)).astype(np.float32)
out = np.clip(out.astype(np.float32) * bm + case * (1 - bm), 0, 255).astype(np.uint8)
cv2.imwrite("src/l_platinum_P.png", out)

T = lambda x, y: (x * sx + tx, y * sy + ty)
def TR(q): p0 = T(q[0], q[1]); p1 = T(q[2], q[3]); return [int(round(p0[0])), int(round(p0[1])), int(round(p1[0])), int(round(p1[1]))]
geom = {"knobs": {k: [round(T(*KN[k][:2])[0], 1), round(T(*KN[k][:2])[1], 1), round((KN[k][2] - 2) * (sx + sy) / 2, 1)] for k in ORDER},
        "plat_knob_r": {k: round(KN[k][2] * (sx + sy) / 2, 1) for k in ORDER},
        "rects": {k: TR(v) for k, v in BOX.items()},
        "pads": [TR(q) for q in PADS],
        "labels": {k: TR(v) for k, v in LB.items()},
        "regions": {k: TR(v) for k, v in REG.items()},
        "scale": [sx, sy, tx, ty]}
for key, (x, y) in LED.items():
    cx, cy = T(x, y); geom["rects"][key] = [int(round(cx - 14)), int(round(cy - 14)), int(round(cx + 14)), int(round(cy + 14))]
geom["rects"]["pads"] = geom["pads"]
json.dump(geom, open("plat_geom_l.json", "w"), indent=1)
print("scale", sx, sy); print(json.dumps(geom["labels"]))
