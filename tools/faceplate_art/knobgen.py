# BreakBoss knob: one procedurally drawn analog knob used on every faceplate.
# Spun-aluminium top with concentric grain and a bevelled edge, a knurled dark-metal skirt that
# shows the knob's height, contact shadow and a soft drop shadow. Light comes from the top left.
# The top face is centred on the sprite centre (the app draws the live pointer around it).
import numpy as np, cv2

SS = 4   # supersampling

def knob(R, seed=1):
    """Returns (rgb float32 HxWx3 in 0..255, alpha HxW, shadow alpha HxW, half size h).
    R = radius of the top face in plate pixels."""
    h = int(np.ceil(R * 2.9))
    n = (2 * h + 1) * SS
    c = h * SS + SS / 2 - 0.5
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    Rs = R * SS
    depth = 0.24 * Rs                      # visible skirt height (knob seen from slightly in front)
    skirtR = 1.06 * Rs                     # skirt a touch wider than the top
    dx, dy = x - c, y - c
    top = np.hypot(dx, dy)                 # distance from the top face centre
    # silhouette: top disc swept down by `depth` with the skirt radius (a short cylinder)
    yc = np.clip(dy, 0, depth)
    side = np.hypot(dx, dy - yc)
    sil = side < skirtR
    face = top < Rs
    rng = np.random.default_rng(seed)

    rgb = np.zeros((n, n, 3), np.float32)
    # ---- skirt: knurled dark metal, cylindrical shading
    u = np.clip(dx / skirtR, -1, 1)
    phi = np.arcsin(u)                                  # angle around the cylinder
    ridges = 0.5 + 0.5 * np.cos(phi * 34)               # knurling
    cyl = 0.35 + 0.65 * np.clip(np.cos(phi + 0.45), 0, 1)   # lit from the left
    vert = np.clip((dy - (-0.2 * Rs)) / (depth + 0.9 * Rs), 0, 1)
    skirt_v = (30 + 78 * cyl * (0.35 + 0.65 * ridges)) * (1.0 - 0.35 * vert)
    rim = np.clip(1 - np.abs(side - skirtR) / (0.05 * Rs), 0, 1)   # thin bright edge on the outline
    skirt_v = skirt_v + 50 * rim * np.clip(np.cos(phi + 0.9), 0, 1)
    rgb[...] = skirt_v[..., None] * np.array([0.97, 0.99, 1.03], np.float32)

    # ---- top face
    ang = np.arctan2(dy, dx)
    r01 = top / Rs
    # spun aluminium: conical highlights + concentric grain
    grain_r = rng.normal(0, 1, int(Rs) + 4).astype(np.float32)
    grain_r = cv2.GaussianBlur(grain_r.reshape(-1, 1), (1, 5), 0.8).ravel()
    gidx = np.clip(top.astype(np.int32), 0, len(grain_r) - 1)
    spun = 168 + 46 * np.cos(2 * (ang + 0.78)) + 16 * np.cos(4 * (ang - 0.2)) + 7 * grain_r[gidx]
    # bevel: outer ring lit on the upper left, shaded lower right
    bev = np.clip((r01 - 0.84) / 0.16, 0, 1)
    light = np.cos(ang + 2.36)            # +1 toward upper left
    bevel_v = 150 + 95 * light
    face_v = spun * (1 - bev) + bevel_v * bev
    # soft dome falloff toward the edge and a small centre dimple
    face_v = face_v * (1 - 0.08 * r01 ** 2)
    face_v = face_v - 18 * np.exp(-(r01 / 0.06) ** 2)
    # darker hairline where the top meets the bevel and at the very edge
    face_v -= 30 * np.exp(-((r01 - 0.84) / 0.012) ** 2)
    face_v -= 60 * np.clip((r01 - 0.975) / 0.025, 0, 1)
    face_rgb = np.clip(face_v, 0, 255)[..., None] * np.array([0.985, 0.995, 1.01], np.float32)
    fa = np.clip((Rs - top) / SS, 0, 1)[..., None]       # anti-aliased face edge
    rgb = rgb * (1 - fa) + face_rgb * fa

    # skirt shading under the face lip (ambient occlusion)
    ao = np.clip(1 - (top - Rs) / (0.12 * Rs), 0, 1) * (~face)
    rgb *= (1 - 0.45 * ao)[..., None]

    alpha = np.clip((skirtR - side) / SS, 0, 1)
    # drop shadow + contact shadow (computed on the silhouette)
    sh_src = alpha.copy()
    M = np.float32([[1, 0, 0.10 * Rs], [0, 1, 0.20 * Rs]])
    drop = cv2.warpAffine(sh_src, M, (n, n))
    drop = cv2.GaussianBlur(drop, (0, 0), 0.22 * Rs) * 0.62
    contact = cv2.GaussianBlur(sh_src, (0, 0), 0.06 * Rs) * 0.5
    shadow = np.clip(np.maximum(drop, contact), 0, 1)

    small = lambda im: cv2.resize(im, (2 * h + 1, 2 * h + 1), interpolation=cv2.INTER_AREA)
    rgb_s = small(rgb * alpha[..., None]) / np.maximum(small(alpha)[..., None], 1e-4)
    return np.clip(rgb_s, 0, 255), small(alpha), small(shadow), h

def dot_ring(R, h, count=11, sweep=270):
    """Platinum-style scale dots around the knob, as an alpha (drawn in each plate's own ink)."""
    n = (2 * h + 1) * SS; c = h * SS + SS / 2 - 0.5
    a = np.zeros((n, n), np.float32)
    rr = 1.36 * R * SS
    for i in range(count):
        t = np.radians(-sweep / 2 + sweep * i / (count - 1)) - np.pi / 2
        big = i in (0, count // 2, count - 1)
        cv2.circle(a, (int(c + rr * np.cos(t)), int(c + rr * np.sin(t))), int((0.075 if big else 0.052) * R * SS), 1.0, -1, cv2.LINE_AA)
    return cv2.resize(a, (2 * h + 1, 2 * h + 1), interpolation=cv2.INTER_AREA)

if __name__ == "__main__":
    S = '/tmp/claude-0/-home-claude/494c8a0e-7abc-5336-889e-4695f430c624/scratchpad'
    tiles = []
    for bg in ((36, 36, 38), (222, 214, 196), (150, 90, 30), (190, 190, 192)):
        rgb, a, sh, h = knob(36)
        ring = dot_ring(36, h)
        base = np.full(rgb.shape, bg, np.float32)
        ink = np.array((40, 40, 42) if np.mean(bg) > 120 else (215, 215, 218), np.float32)
        base = base * (1 - ring[..., None]) + ink * ring[..., None]
        base = base * (1 - sh[..., None])
        out = base * (1 - a[..., None]) + rgb[..., ::-1] * a[..., None]
        tiles.append(cv2.resize(np.clip(out, 0, 255).astype(np.uint8), None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC))
    cv2.imwrite(f"{S}/knobgen.png", np.hstack(tiles))
