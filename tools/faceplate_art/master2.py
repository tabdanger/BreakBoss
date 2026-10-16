# Platinum is the master (Tyrone, Oct 14): Modern, Vintage and Texture are rebuilt from the Platinum
# plate, so every tray, panel, box, line, bevel and button is Platinum's. Only the materials change.
# Platinum's own shading (bevels, edges, the shadows buttons and pads cast) is carried onto each
# material as a local (high-pass) delta, so the brushing and sheen of the silver don't come along.
import json, numpy as np, cv2
import master as M0          # material(), rect_mask(), MOCKS

# Modern's own flat levels per region (from its original artwork), used to tint the dark finish
MODERN_LEVELS = {"l": {"base": 34.3, "upper": 40.7, "lower": 31.7, "well": 10.7, "tray": 27.0},
                 "p": {"base": 18.0, "upper": 41.3, "lower": 28.3, "well": 10.0, "tray": 38.0, "kits": 25.0, "presets": 25.0}}
LOOK = {"modern": {"base": "modern", "tray": "modern", "kits": "modern", "presets": "modern", "upper": "modern", "lower": "modern", "well": "modern", "pads": "dark"},
        "vintage": {"base": "vintage", "tray": "vintage", "kits": "vintage", "presets": "vintage", "upper": "modern", "lower": "vintage", "well": "modern", "pads": "white"},
        "texture": {"base": "texture", "tray": "texture", "kits": "texture", "presets": "texture", "upper": "texture", "lower": "texture", "well": "modern", "pads": "white"}}
KEEP = ["scope", "oneShotButton", "loopButton", "mode_modern", "mode_vintage", "mode_texture", "playRect", "bpmBox",
        "diceRect", "kitBox", "presetBox", "saveRect", "clipperRect", "exportRect", "menuRect"]
PAD_DARK = np.array([58, 58, 60], np.float32)       # Modern's pad colour (BGR)
PAD_WHITE = np.array([226, 229, 231], np.float32)

def build(dev, mode, src, G, caps=None):
    """G: {"knobs": {k: [x, y, r]}, "rects": {...}, "pads": [...], "labels": {...}, "regions": {...}}"""
    H, W = src.shape[:2]
    s = src.astype(np.float32); Ls = s.mean(2)
    look = LOOK[mode]; RR = G["rects"]; REG = G["regions"]
    # objects that are not plate surface: pads, buttons, windows, knob cells, lamps
    obj = np.zeros((H, W), np.uint8)
    for q in G["pads"]: cv2.rectangle(obj, (q[0] - 6, q[1] - 6), (q[2] + 6, q[3] + 6), 1, -1)
    for k in KEEP + ["ledTempo", "ledFollow"]:
        if k in RR: q = RR[k]; cv2.rectangle(obj, (q[0] - 4, q[1] - 4), (q[2] + 4, q[3] + 4), 1, -1)
    for k, (x, y, r) in G["knobs"].items(): cv2.circle(obj, (int(x), int(y)), int(r * 2.05), 1, -1)
    # plain areas: knob cells, label boxes, panel insides (only edges carry bevels)
    flat = np.zeros((H, W), np.uint8)
    for k, (x, y, r) in G["knobs"].items(): cv2.circle(flat, (int(x), int(y)), int(r * 2.05), 1, -1)
    for k, b in G["labels"].items():
        if b and not k.startswith("mode_") and k not in ("oneShotButton", "loopButton"):
            m = 2 if k in ("kits", "presets") else 10
            cv2.rectangle(flat, (b[0] - m, b[1] - 6), (b[2] + m, b[3] + 6), 1, -1)
    for reg in ("upper", "lower", "kits", "presets"):
        if reg in REG:
            x0, y0, x1, y1 = REG[reg]; cv2.rectangle(flat, (x0 + 14, y0 + 14), (x1 - 14, y1 - 14), 1, -1)
    FLAT = cv2.GaussianBlur(flat.astype(np.float32), (0, 0), 4)
    masks = {k: M0.rect_mask(H, W, r, 1.0) for k, r in REG.items()}
    masks["base"] = np.clip(1 - sum(masks.values()), 0, 1)
    surf = (1 - obj).astype(np.float32)
    Lsm = cv2.bilateralFilter(Ls, 9, 14, 3)
    mats = {k: M0.material(k, H, W) for k in ("vintage", "texture", "modern")}
    out = np.zeros_like(s)
    for reg, mk in masks.items():
        hard = (mk > 0.5).astype(np.float32)
        w = hard * surf
        num = cv2.GaussianBlur(Lsm * w, (0, 0), 22); den = cv2.GaussianBlur(w, (0, 0), 22)
        local = np.where(den > 1e-3, num / np.maximum(den, 1e-3), float(np.median(Ls[hard > 0])))
        level = float(np.median(Ls[(hard * surf) > 0])) if (hard * surf).sum() > 100 else 128.0
        d = Lsm - local
        d = np.sign(d) * np.maximum(np.abs(d) - 7, 0)          # drop the brushing grain
        d = d * (1 - FLAT)
        d = np.minimum(d, 18 if look[reg] == "modern" else 40)     # silver highlights stay subtle on every material
        mat = mats[look[reg]]
        if look[reg] == "modern":
            mat = mat * (MODERN_LEVELS[dev].get(reg, 30.0) / max(float(mat.mean()), 1))
        shade = np.where(d < 0, 1 + d / max(level, 1) * 0.9, 1 + d / 255 * 0.9)
        out += mat * np.clip(shade, 0.12, 2.0)[..., None] * mk[..., None]
    # pads: Platinum's pad shapes in this plate's pad colour, with Platinum's pad shading
    pads = np.zeros((H, W), np.float32)
    for r in G["pads"]: pads = np.maximum(pads, M0.rect_mask(H, W, r, 0.8, radius=7))
    lvl = float(np.median(Ls[pads > 0.99]))
    col = PAD_WHITE if look["pads"] == "white" else PAD_DARK
    k = 1.6 if look["pads"] == "white" else 0.9
    noise = cv2.GaussianBlur(np.random.default_rng(3).normal(0, 1, (H, W)).astype(np.float32), (0, 0), 0.8)[..., None] * 2.5
    pad_px = np.clip(col * (1 + (Lsm - lvl)[..., None] / 255 * k) * (1 if look["pads"] == "white" else 1) + noise, 0, 255)
    if look["pads"] == "dark":       # dark pads keep the source's own relative shading
        pad_px = np.clip(col * np.clip(1 + (Lsm - lvl)[..., None] / max(lvl, 1) * 0.6, 0.3, 1.25) + noise, 0, 255)
    if look["pads"] == "source": pad_px = s
    out = out * (1 - pads[..., None]) + pad_px * pads[..., None]
    # the lit mode button for this plate: swap the caps in a copy of the source first, so the cut below
    # takes only the cap itself (no silver from around it)
    s2 = s.copy()
    capsm = {k: RR[f"mode_{k}"] for k in ("modern", "vintage", "texture")}
    lit, unlit = capsm["modern"], capsm["vintage"]
    target = capsm[mode]
    if target != lit:
        def cut(r): return s[r[1]:r[3], r[0]:r[2]]
        h, w = target[3] - target[1], target[2] - target[0]
        s2[target[1]:target[3], target[0]:target[2]] = cv2.resize(cut(lit), (w, h))
        h, w = lit[3] - lit[1], lit[2] - lit[0]
        s2[lit[1]:lit[3], lit[0]:lit[2]] = cv2.resize(cut(unlit), (w, h))
    L2 = s2.mean(2)
    # buttons, windows, the scope, the clipper lamp: Platinum's own, identical on every plate. Only the
    # dark cap / window / lamp is taken; Platinum's silver bevels and highlights around them are left
    # out, so each plate draws those edges in its own material.
    for key in KEEP:
        if key in ("exportRect", "menuRect"):
            if dev == "l": continue          # iPad: the three small buttons are added after the knobs
            x0, y0, x1, y1 = caps[0 if key == "exportRect" else 1] if caps else RR[key]
        else:
            x0, y0, x1, y1 = RR[key]
        X0, Y0, X1, Y1 = max(x0 - 6, 0), max(y0 - 6, 0), min(x1 + 6, W), min(y1 + 6, H)
        sub = s2[Y0:Y1, X0:X1]; Lsub = L2[Y0:Y1, X0:X1]
        dark = (Lsub < 105)
        if key == "clipperRect": dark |= (sub[..., 2] - sub[..., 1] > 40)
        dark = cv2.morphologyEx(dark.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
        n_, lab = cv2.connectedComponents(dark)
        if n_ <= 1: continue
        big = 1 + int(np.argmax([(lab == i).sum() for i in range(1, n_)]))
        cap = (lab == big).astype(np.uint8)
        inv = (1 - cap).astype(np.uint8); fm = np.zeros((inv.shape[0] + 2, inv.shape[1] + 2), np.uint8)
        cv2.floodFill(inv, fm, (0, 0), 0)                  # holes (letters, icons, lit dashes) belong to the cap
        cap = np.clip(cap + inv, 0, 1).astype(np.uint8)
        # no light rim: bright pixels within 4 px of the cap's outline go
        dist = cv2.distanceTransform(cap, cv2.DIST_L2, 3)
        cap[(dist <= 4) & (Lsub > 120)] = 0
        cap = cv2.morphologyEx(cap, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        kk = cv2.GaussianBlur(cap.astype(np.float32), (0, 0), 0.7)[..., None]
        out[Y0:Y1, X0:X1] = out[Y0:Y1, X0:X1] * (1 - kk) + sub * kk
    # lamps: Platinum's lamp, no bezel
    for key in ("ledTempo", "ledFollow"):
        x0, y0, x1, y1 = RR[key]; cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        yy, xx = np.mgrid[0:H, 0:W]; rho = np.hypot(xx - cx, yy - cy)
        core = np.clip(((10.0 if dev == "l" else 14.0) - rho) / 1.5, 0, 1)[..., None]
        out = out * (1 - core) + s * core
    return np.clip(out, 0, 255).astype(np.uint8)
