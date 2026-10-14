# Adds the pattern-editor (piano keys) button left of EXPORT on every cleaned plate.
# iPad: EXPORT and MENU shift right a few pixels first to make room (approved by Tyrone).
# Run after clean.py, from /home/claude/art2. Rewrites out/*_plate.png and both layout JSONs.
import json, os, numpy as np, cv2
from PIL import Image, ImageDraw

SHIFT = {"l_modern": (5, -2), "l_vintage": (3, -1), "l_texture": (6, -3), "l_platinum": (5, -2),
         "p_modern": (0, 0), "p_vintage": (0, 0), "p_texture": (0, 0), "p_platinum": (0, 0)}
lays = {"tablet": json.load(open("out/KnockLayout.json")), "phone": json.load(open("out/PhoneKnockLayout.json"))}

def feather(h, w, f):
    y = np.minimum(np.arange(h), np.arange(h)[::-1])[:, None]
    x = np.minimum(np.arange(w), np.arange(w)[::-1])[None, :]
    return np.clip(np.minimum(y, x) / f, 0, 1)

def paste(a, sprite, x0, y0, f=3):
    h, w = sprite.shape[:2]
    m = feather(h, w, f)[..., None]
    a[y0:y0+h, x0:x0+w] = a[y0:y0+h, x0:x0+w] * (1 - m) + sprite * m


# iPad caps measured by eye at 4x (outer dark rim included): export, menu.
CAPS = {"l_modern": ((1279, 31, 1324, 77), (1330, 31, 1374, 77)),
        "l_vintage": ((1285, 26, 1326, 75), (1330, 26, 1371, 74)),
        "l_texture": ((1270, 35, 1316, 79), (1324, 35, 1368, 78))}
ALIGN_TO_MODERN = os.path.exists("caps.json")
if ALIGN_TO_MODERN:   # plates aligned to Modern: caps moved with them
    CAPS = {k: tuple(tuple(c) for c in v) for k, v in json.load(open("caps.json")).items()}
    # Every plate's button row lands exactly where Modern's does.
    m = CAPS["l_modern"][0]
    for n in ("l_vintage", "l_texture"):
        e = CAPS[n][0]
        SHIFT[n] = (m[0] + SHIFT["l_modern"][0] - e[0], m[1] + SHIFT["l_modern"][1] - e[1])

def rounded(h, w, r):
    big = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=r * 4, fill=255)
    return np.asarray(big.resize((w, h), Image.LANCZOS)).astype(np.float32) / 255

def put_cap(a, cap, x0, y0):
    h, w = cap.shape[:2]
    al = rounded(h, w, 5)
    # Soft drop shadow first, then the cap itself.
    pad = 10
    sh = np.zeros((h + pad * 2, w + pad * 2), np.float32)
    sh[pad + 3:pad + 3 + h, pad:pad + w] = al
    sh = cv2.GaussianBlur(sh, (0, 0), 3) * 0.6
    ys, xs = y0 - pad, x0 - pad
    a[ys:ys + h + pad * 2, xs:xs + w + pad * 2] *= (1 - sh)[..., None]
    a[y0:y0 + h, x0:x0 + w] = a[y0:y0 + h, x0:x0 + w] * (1 - al[..., None]) + cap * al[..., None]

def piano_cap(cap):
    nb = cap.copy()
    lum = nb.mean(2)
    h, w = lum.shape
    inner = np.zeros_like(lum, bool)
    inner[6:h - 6, 6:w - 6] = True
    icon = inner & (lum > np.median(lum[inner]) + 45)
    ys, xs = np.nonzero(icon)
    color = np.percentile(nb[icon], 85, axis=0)
    cy, cx = (ys.min() + ys.max()) / 2, (xs.min() + xs.max()) / 2
    iw, ih = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    imask = cv2.dilate(icon.astype(np.uint8) * 255, np.ones((5, 5), np.uint8))
    nb = cv2.inpaint(np.clip(nb, 0, 255).astype(np.uint8), imask, 4, cv2.INPAINT_TELEA).astype(np.float32)
    return draw_piano(nb, cx, cy, iw, ih, color)

def draw_piano(nb, cx, cy, iw, ih, color):
    h, w = nb.shape[:2]
    S = 8
    stroke = max(1.5, iw * 0.09)
    kw, kh = iw * 1.15, ih * 0.82
    big = Image.new("L", (w * S, h * S), 0)
    d = ImageDraw.Draw(big)
    x0, y0 = (cx - kw / 2) * S, (cy - kh / 2) * S
    x1, y1 = (cx + kw / 2) * S, (cy + kh / 2) * S
    sw = stroke * S
    d.rounded_rectangle([x0, y0, x1, y1], radius=sw * 1.2, outline=255, width=int(round(sw)))
    for k in (1, 2):
        x = x0 + (x1 - x0) * k / 3
        d.line([x, y0 + kh * S * 0.55, x, y1], fill=255, width=int(round(sw * 0.85)))
    bw = (x1 - x0) * 0.17
    for k in (1, 2):
        x = x0 + (x1 - x0) * k / 3
        d.rounded_rectangle([x - bw / 2, y0, x + bw / 2, y0 + kh * S * 0.58], radius=sw * 0.4, fill=255)
    alpha = np.asarray(big.resize((w, h), Image.LANCZOS)).astype(np.float32)[..., None] / 255
    return nb * (1 - alpha) + color * alpha

def tablet_buttons(a, orig, n, dx, dy, L):
    (e, m) = CAPS[n]
    caps = [orig[r[1]:r[3], r[0]:r[2]].copy() for r in (e, m)]
    # Clear the old caps and their shadows, then rebuild the row.
    mask = np.zeros(a.shape[:2], np.uint8)
    for r in (e, m):
        mask[r[1] - 2:r[3] + 7, r[0] - 3:r[2] + 3] = 255
    a[:] = cv2.inpaint(np.clip(a, 0, 255).astype(np.uint8), mask, 5, cv2.INPAINT_TELEA).astype(np.float32)
    step = m[0] - e[0]
    ne = (e[0] + dx, e[1] + dy); nm = (m[0] + dx, m[1] + dy); nd = (ne[0] - step, ne[1])
    wE, hE = e[2] - e[0], e[3] - e[1]; wM, hM = m[2] - m[0], m[3] - m[1]
    if ALIGN_TO_MODERN and n != "l_modern":
        # Same boxes as Modern's buttons, so nothing moves when you switch modes.
        me, mm = CAPS["l_modern"]; mdx, mdy = SHIFT["l_modern"]
        wE, hE = me[2] - me[0], me[3] - me[1]; wM, hM = mm[2] - mm[0], mm[3] - mm[1]
        ne = (me[0] + mdx, me[1] + mdy); nm = (mm[0] + mdx, mm[1] + mdy); nd = (ne[0] - (mm[0] - me[0]), ne[1])
        caps = [cv2.resize(caps[0], (wE, hE), interpolation=cv2.INTER_AREA), cv2.resize(caps[1], (wM, hM), interpolation=cv2.INTER_AREA)]
    put_cap(a, piano_cap(caps[0]), *nd)
    put_cap(a, caps[0], *ne)
    put_cap(a, caps[1], *nm)
    L["editorRect"] = [nd[0] - 2, nd[1] - 2, nd[0] + wE + 2, nd[1] + hE + 2]
    L["exportRect"] = [ne[0] - 2, ne[1] - 2, ne[0] + wE + 2, ne[1] + hE + 2]
    L["menuRect"] = [nm[0] - 2, nm[1] - 2, nm[0] + wM + 2, nm[1] + hM + 2]

for n, (dx, dy) in SHIFT.items():
    dev = "phone" if n.startswith("p_") else "tablet"
    mode = n[2:]
    L = lays[dev][mode]
    e, m = list(L["exportRect"]), list(L["menuRect"])
    a = np.asarray(Image.open(f"out/{n}_plate.png").convert("RGB")).astype(np.float32)
    orig = a.copy()
    step = m[0] - e[0]
    pad = 3
    exp_sprite = orig[e[1]-pad:e[3]+pad, e[0]-pad:e[2]+pad].copy()
    men_sprite = orig[m[1]-pad:m[3]+pad, m[0]-pad:m[2]+pad].copy()

    if n.startswith("l_") and os.path.exists("plat_geom_l.json"):
        # Platinum master (Oct 14): the three buttons are already on the plate (plat_unify.py TOPCAPS)
        R_ = json.load(open("rects.json"))[n]
        L["editorRect"], L["exportRect"], L["menuRect"] = R_["editorRect"], R_["exportRect"], R_["menuRect"]
        print(n, "buttons from plat_unify", L["editorRect"], L["exportRect"], L["menuRect"])
        continue
    if n in CAPS:
        tablet_buttons(a, orig, n, dx, dy, L)
        Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(f"out/{n}_plate.png")
        print(n, "editor", L["editorRect"], "export", L["exportRect"], "menu", L["menuRect"])
        continue

    # New button: the EXPORT cap with its arrow removed and a piano-keys icon drawn on.
    nb = exp_sprite.copy()
    lum = nb.mean(2)
    h, w = lum.shape
    inner = np.zeros_like(lum, bool)
    inner[int(h*0.15):int(h*0.85), int(w*0.15):int(w*0.85)] = True
    capmed = np.median(lum[inner])
    icon = inner & (lum > capmed + 45)
    ys, xs = np.nonzero(icon)
    color = np.percentile(nb[icon], 85, axis=0)
    cy, cx = (ys.min() + ys.max()) / 2, (xs.min() + xs.max()) / 2
    iw, ih = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    stroke = max(1.5, iw * 0.09)
    imask = cv2.dilate(icon.astype(np.uint8) * 255, np.ones((5, 5), np.uint8))
    nb = cv2.inpaint(np.clip(nb, 0, 255).astype(np.uint8), imask, 4, cv2.INPAINT_TELEA).astype(np.float32)

    S = 8  # draw large, then shrink for clean anti-aliased lines
    kw, kh = iw * 1.15, ih * 0.82
    big = Image.new("L", (w * S, h * S), 0)
    d = ImageDraw.Draw(big)
    x0, y0 = (cx - kw / 2) * S, (cy - kh / 2) * S
    x1, y1 = (cx + kw / 2) * S, (cy + kh / 2) * S
    sw = stroke * S
    d.rounded_rectangle([x0, y0, x1, y1], radius=sw * 1.2, outline=255, width=int(round(sw)))
    for k in (1, 2):  # three white keys
        x = x0 + (x1 - x0) * k / 3
        d.line([x, y0 + kh * S * 0.55, x, y1], fill=255, width=int(round(sw * 0.85)))
    bw = (x1 - x0) * 0.17
    for k in (1, 2):  # two black keys, filled
        x = x0 + (x1 - x0) * k / 3
        d.rounded_rectangle([x - bw / 2, y0, x + bw / 2, y0 + kh * S * 0.58], radius=sw * 0.4, fill=255)
    alpha = np.asarray(big.resize((w, h), Image.LANCZOS)).astype(np.float32)[..., None] / 255
    nb = nb * (1 - alpha) + color * alpha

    ed = [e[0] - step, e[1], e[2] - step, e[3]]
    paste(a, nb, ed[0] - pad, ed[1] - pad)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(f"out/{n}_plate.png")
    L["exportRect"], L["menuRect"], L["editorRect"] = e, m, ed
    print(n, "editor", ed, "export", e, "menu", m)

# iPad Platinum has no top-right buttons: give it Modern's three, in Modern's exact spots.
if False and "platinum" in lays["tablet"]:   # Platinum now comes from the master like the others
    mod = np.asarray(Image.open("out/l_modern_plate.png").convert("RGB")).astype(np.float32)
    plat = np.asarray(Image.open("out/l_platinum_plate.png").convert("RGB")).astype(np.float32)
    Lm, Lp = lays["tablet"]["modern"], lays["tablet"]["platinum"]
    for key in ("editorRect", "exportRect", "menuRect"):
        x0, y0, x1, y1 = Lm[key]
        cap = mod[y0 + 2:y1 - 2, x0 + 2:x1 - 2].copy()
        put_cap(plat, cap, x0 + 2, y0 + 2)
        Lp[key] = list(Lm[key])
    Image.fromarray(np.clip(plat, 0, 255).astype(np.uint8)).save("out/l_platinum_plate.png")
    print("l_platinum buttons", Lp["editorRect"], Lp["exportRect"], Lp["menuRect"])

json.dump(lays["tablet"], open("out/KnockLayout.json", "w"), indent=1)
json.dump(lays["phone"], open("out/PhoneKnockLayout.json", "w"), indent=1)
