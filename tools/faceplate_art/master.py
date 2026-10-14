# One master for every faceplate (Tyrone, Oct 14): Vintage, Texture and Platinum are rebuilt from
# Modern's own artwork, so every tray, panel, box, line, bevel and shadow is identical. Only the
# materials change (cream / blue / brushed silver, panel and pad colours). Modern's shading (bevels,
# edges, the shadows buttons cast) is carried onto each material, so shadows sit on each surface.
import json, numpy as np, cv2

A2 = "/home/claude/art2"
R2 = json.load(open(f"{A2}/rects.json"))
MOCK = "/root/.claude/uploads/494c8a0e-7abc-5336-889e-4695f430c624/"
MOCKS = {"modern": "5074bf40-image.png", "platinum": "a7ad3246-image.png", "vintage": "9219c3c8-image.png", "texture": "5b5b2c89-image.png"}

# Regions on Modern's iPad plate (x0, y0, x1, y1), measured on the art.
REG_L = {"upper": (605, 51, 1363, 353), "lower": (93, 456, 1366, 636), "well": (91, 652, 1366, 1016),
         "tray": (100, 52, 419, 141)}
REG_P = {"upper": (83, 365, 858, 654), "kits": (83, 758, 858, 828), "presets": (83, 830, 858, 908),
         "lower": (83, 910, 858, 1172), "well": (85, 1188, 858, 1600), "tray": (88, 38, 514, 112)}
LEVELS = {"l": {"base": 34.3, "upper": 40.7, "lower": 31.7, "well": 10.7, "tray": 27.0},
          "p": {"base": 18.0, "upper": 41.3, "lower": 28.3, "well": 10.0, "tray": 38.0, "kits": 25.0, "presets": 25.0}}
KEEP_L = ["scope", "oneShotButton", "loopButton", "mode_modern", "mode_vintage", "mode_texture", "playRect", "bpmBox",
          "diceRect", "kitBox", "presetBox", "saveRect", "clipperRect", "exportRect", "menuRect", "ledTempo", "ledFollow"]

# What each plate is made of: region -> "plate material" | "modern" (keep Modern's own dark finish)
LOOK = {"vintage": {"base": "vintage", "tray": "vintage", "kits": "vintage", "presets": "vintage", "upper": "modern", "lower": "vintage", "well": "modern", "pads": "white"},
        "texture": {"base": "texture", "tray": "texture", "kits": "texture", "presets": "texture", "upper": "texture", "lower": "texture", "well": "modern", "pads": "white"},
        "platinum": {"base": "platinum", "tray": "platinum", "kits": "platinum", "presets": "platinum", "upper": "platinum", "lower": "platinum", "well": "platinum", "pads": "modern"}}

def material(name, H, W):
    """A seamless tile of the plate material (from Tyrone's drum-roll mock-ups), filling H x W."""
    a = cv2.imread(MOCK + MOCKS[name]).astype(np.float32)
    p = a[964:1030, 457:883]
    base = np.median(p.reshape(-1, 3), axis=0)
    detail = p - cv2.GaussianBlur(p, (0, 0), 6)          # grain only: no lighting gradients, so no bands
    t = np.vstack([np.hstack([detail, detail[:, ::-1]]), np.hstack([detail[::-1], detail[::-1, ::-1]])])
    reps = (H // t.shape[0] + 2, W // t.shape[1] + 2, 1)
    big = np.tile(t, reps)
    big = big[17:17 + H, 31:31 + W]
    if name == "platinum":                                 # brushed: stretch the grain sideways
        big = cv2.GaussianBlur(big, (0, 0), sigmaX=6, sigmaY=0.4) * 2.2
    # a gentle top-to-bottom sheen, the same on every plate
    yy = np.linspace(-1, 1, H)[:, None, None]
    sheen = 1 + 0.05 * (-yy)
    return np.clip((base + big) * sheen, 0, 255)

def rect_mask(H, W, r, feather=1.2, radius=0):
    m = np.zeros((H, W), np.float32)
    x0, y0, x1, y1 = [int(v) for v in r]
    if radius:
        cv2.rectangle(m, (x0 + radius, y0), (x1 - radius, y1), 1, -1); cv2.rectangle(m, (x0, y0 + radius), (x1, y1 - radius), 1, -1)
        for cx, cy in ((x0 + radius, y0 + radius), (x1 - radius, y0 + radius), (x0 + radius, y1 - radius), (x1 - radius, y1 - radius)):
            cv2.circle(m, (cx, cy), radius, 1, -1)
    else:
        m[y0:y1, x0:x1] = 1
    return cv2.GaussianBlur(m, (0, 0), feather) if feather else m

FLAT = None   # where the plate is plain (knob cells, printed words): set by build()

def recolor(modern, mat, region_mask, base_level):
    """Modern's shading (relative to its flat surface level) laid onto a material."""
    L = modern.mean(2)
    Ls = cv2.bilateralFilter(L, 9, 14, 3)                  # drop Modern's own brushing, keep bevels and edges
    d = Ls - base_level
    if FLAT is not None: d = d * (1 - FLAT)                # no old knob shadows, tick marks or letters
    mlum = mat.mean(2, keepdims=True)
    shade = np.where(d[..., None] < 0, 1 + d[..., None] / max(base_level, 1) * 0.75,   # shadows: relative darkening
                     1 + d[..., None] / 255 * 0.9)                                      # highlights: relative lift
    out = mat * np.clip(shade, 0.12, 2.0)
    return out * region_mask[..., None]

def build(dev, mode, modern):
    """The plate for `mode`, built from Modern's artwork (before knobs, lettering and wood)."""
    RR = R2[f"{dev}_modern"]
    REG = REG_L if dev == "l" else REG_P
    H, W = modern.shape[:2]
    m = modern.astype(np.float32)
    look = LOOK[mode]
    global FLAT
    K2 = json.load(open(f"{A2}/knobs.json")); LB = json.load(open("labels_modern.json"))[dev]
    flat = np.zeros((H, W), np.uint8)
    for k, (x, y, r) in K2[f"{dev}_modern"].items():
        cv2.circle(flat, (int(x), int(y)), int(r * 2.05), 1, -1)
    for k, b in LB.items():
        if b and not k.startswith("mode_") and k not in ("oneShotButton", "loopButton"):
            cv2.rectangle(flat, (b[0] - 14, b[1] - 8), (b[2] + 14, b[3] + 8), 1, -1)
    for lab, box in (("kits", "kitBox"), ("presets", "presetBox")):     # the small dividers by KITS / PRESETS
        if dev == "l": cv2.rectangle(flat, (int(LB[lab][0]) - 30, 378), (int(RR[box][0]) - 1, 442), 1, -1)
    for reg in ("upper", "lower", "kits", "presets"):             # panel insides are plain: only their edges carry bevels
        if reg in REG:
            x0, y0, x1, y1 = REG[reg]; inset = 14
            cv2.rectangle(flat, (x0 + inset, y0 + inset), (x1 - inset, y1 - inset), 1, -1)
    FLAT = cv2.GaussianBlur(flat.astype(np.float32), (0, 0), 4)
    mats = {k: material(k, H, W) for k in ("vintage", "texture", "platinum", "modern")}
    levels = LEVELS[dev]
    masks = {k: rect_mask(H, W, r, 1.0) for k, r in REG.items()}
    masks["base"] = np.clip(1 - sum(masks.values()), 0, 1)
    out = np.zeros_like(m)
    for reg, mk in masks.items():
        which = look[reg]
        out += recolor(m, mats[which], mk, levels[reg])          # "modern" = Modern's own black finish, cleaned
    # Pads: Modern's pad shapes in the plate's pad colour
    pads = np.zeros((H, W), np.float32)
    for r in RR["pads"]:
        pads = np.maximum(pads, rect_mask(H, W, r, 0.8, radius=7))
    if look["pads"] == "white":
        L = m.mean(2); Ls = cv2.bilateralFilter(L, 9, 14, 3)
        lvl = float(np.median(L[pads > 0.99]))
        white = np.full_like(m, (232, 232, 230))[..., ::-1] * 0 + np.array([226, 229, 231], np.float32)
        noise = cv2.GaussianBlur(np.random.default_rng(3).normal(0, 1, (H, W)).astype(np.float32), (0, 0), 0.8)[..., None] * 3
        pad_px = np.clip(white * (1 + (Ls - lvl)[..., None] / 255 * 1.6) + noise, 0, 255)
        out = out * (1 - pads[..., None]) + pad_px * pads[..., None]
    else:
        out = out * (1 - pads[..., None]) + m * pads[..., None]
    # Buttons, windows and the scope: Modern's own, identical on every plate
    caps_l = json.load(open("caps.json"))["l_modern"]
    for key in KEEP_L:
        x0, y0, x1, y1 = RR[key]
        if dev == "l" and key in ("exportRect", "menuRect"):          # the measured cap, not its old shadow box
            x0, y0, x1, y1 = caps_l[0 if key == "exportRect" else 1]
        k = rect_mask(H, W, (x0 - 1, y0 - 1, x1 + 1, y1 + 1), 0.8, radius=3)
        out = out * (1 - k[..., None]) + m * k[..., None]
    # LED lamps: Modern's lit lamp and its glow, added onto the plate
    for key in ("ledTempo", "ledFollow"):
        x0, y0, x1, y1 = RR[key]; cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        yy, xx = np.mgrid[0:H, 0:W]; rho = np.hypot(xx - cx, yy - cy)
        core = np.clip((10.5 - rho) / 1.5, 0, 1)[..., None]
        halo = (np.clip((22 - rho) / 12, 0, 1) * (1 - core[..., 0]))[..., None]
        glow = np.clip(m - np.array([34, 34, 34], np.float32), 0, 255)
        out = out * (1 - core) + m * core
        out = np.clip(out + glow * halo * 0.9, 0, 255)
    # The lit mode button for this plate
    caps = {k: RR[f"mode_{k}"] for k in ("modern", "vintage", "texture")}
    lit, unlit = caps["modern"], caps["vintage"]
    target = caps[mode if mode in caps else "modern"]
    if target != lit:
        def cut(r): return m[r[1]:r[3], r[0]:r[2]]
        h, w = target[3] - target[1], target[2] - target[0]
        out[target[1]:target[3], target[0]:target[2]] = cv2.resize(cut(lit), (w, h))
        h, w = lit[3] - lit[1], lit[2] - lit[0]
        out[lit[1]:lit[3], lit[0]:lit[2]] = cv2.resize(cut(unlit), (w, h))
    return np.clip(out, 0, 255).astype(np.uint8)

if __name__ == "__main__":
    S = "/tmp/claude-0/-home-claude/494c8a0e-7abc-5336-889e-4695f430c624/scratchpad"
    modern = cv2.imread(f"{A2}/src/l_modern.png")
    ims = [cv2.resize(build("l", k, modern), (724, 543)) for k in ("vintage", "texture", "platinum")]
    cv2.imwrite(f"{S}/master_prev.jpg", np.vstack([np.hstack([cv2.resize(modern, (724, 543)), ims[0]]), np.hstack(ims[1:])]))
