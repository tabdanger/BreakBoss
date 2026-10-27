#!/usr/bin/env python3
"""Realistic materials, stage 1: ONE knob (PITCH) and ONE pad (pad 1), Tyrone Oct 27 2026.

Every face uses the same knob and the same pad: one shape, one size, one hit area (measured off
the PLATINUM render, the master). Only the materials change per face (cap metal tint, skirt
plastic, pad rubber). For each part this writes, from physical maps:

  source maps (tools/faceplate_art/materials/maps/, for reference and the next stages)
    <part>_<face>_basecolor.png   albedo
    <part>_normal.png             tangent-space normal (shared shape)
    <part>_roughness.png          roughness (shared)

  app layers (BreakBoss.swiftpm/Resources/Assets.xcassets)
    MatKnob_<face>_{c,l,r,u,d}    knob body lit from the fixed light (c) and from the light swung
                                  left / right / up / down; the app cross-fades them as the iPad
                                  tilts (no shader work on the device, the GPU only blends pictures)
    MatKnobSheen_<face>           the spun cap's two bright wedges and its bevel glint, made for the
                                  fixed light; the app turns it with the light (never with the knob,
                                  a spun cap's highlight stays where the light is)
    MatKnobShadow                 the knob's soft shadow on the plate (moves away from the light)
    MatPad_<face>_{c,l,r,u,d}     rubber pad, same five lights
    MatPadShadow                  the pad's shadow in its well (shrinks when the pad goes down)
    MatDemoKnob_<face>            the render around PITCH with its own knob painted out (dots and
    MatDemoPad_<face>             label kept sharp) / the render's pad well with pad 1 painted out:
                                  the MATERIAL TEST page's backdrop

The pointer is not in any picture: the app draws it live from the PITCH value (KnobControl).

    python3 tools/faceplate_art/materials/build_materials.py BreakBoss.swiftpm
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).parent
pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
assets = pkg / "Resources" / "Assets.xcassets"
maps = HERE / "maps"
RENDERS = HERE.parent / "face1" / "v2"
FACES = {"platinum": "Face1v2_ModernPlatinum.png", "modern": "Face1v2_ModernBlack.png",
         "texture": "Face1v2_Texture.png", "vintage": "Face1v2_Vintage.png"}
rng = np.random.default_rng(2026_10_27)

# ---- the shared geometry, in the v2 renders' pixels (1448 x 1086), from PLATINUM -------------
KNOB_C = (768.0, 142.0)          # skirt centre (the dial's dots ring this point)
KNOB_R = 40.0                    # skirt radius at the plate
KNOB_BOX = 2.7                   # picture covers +-1.35 R
KNOB_PX = 288                    # picture size
CAP_DY, CAP_R, TOP_R = -0.30, 0.78, 0.86   # top face: centre offset, cap, shoulder (in R)
PAD = (101.0, 636.0, 296.0, 790.0)          # pad 1, outside edge
PAD_MARGIN = 14.0
PAD_SCALE = 2.0                  # picture pixels per render pixel
PAD_CORNER, PAD_BEVEL = 13.0, 12.0

# ---- light ---------------------------------------------------------------------------------
L0 = np.array([-0.30, -0.55, 0.78])    # the renders' light: above, a little left (y down = toward you)
SWING = 0.6                             # how far a full tilt swings it
LIGHTS = {"c": (0, 0), "l": (-1, 0), "r": (1, 0), "u": (0, -1), "d": (0, 1)}

# ---- materials per face (albedo 0..1, measured off each render's caps / skirts / pads) ------
MATERIAL = {
    "platinum": dict(cap=(0.80, 0.79, 0.78), skirt=(0.040, 0.037, 0.035), pad=(0.205, 0.225, 0.240)),
    "modern":   dict(cap=(0.82, 0.78, 0.75), skirt=(0.030, 0.030, 0.030), pad=(0.250, 0.255, 0.265)),
    "texture":  dict(cap=(0.80, 0.77, 0.74), skirt=(0.030, 0.042, 0.055), pad=(0.230, 0.252, 0.282)),
    "vintage":  dict(cap=(0.72, 0.74, 0.79), skirt=(0.045, 0.038, 0.030), pad=(0.325, 0.338, 0.362)),
}


def norm(v):
    return v / np.maximum(1e-9, np.linalg.norm(v, axis=-1, keepdims=True))


def light(key):
    sx, sy = LIGHTS[key]
    l = L0.copy()
    l[0] += SWING * sx
    l[1] += SWING * sy
    return l / np.linalg.norm(l)


def shade(albedo, n, rough, metal, l, ao=1.0, spec_scale=1.0):
    """Lambert + normalised Blinn-Phong (exponent from roughness), soft sky fill from above."""
    v = np.array([0.0, 0.0, 1.0])
    h = (l + v) / np.linalg.norm(l + v)
    ndl = np.clip((n * l).sum(-1), 0, 1)[..., None]
    ndh = np.clip((n * h).sum(-1), 0, 1)
    a = np.maximum(0.02, rough) ** 2
    p = 2 / (a * a) - 2
    spec = ((p + 8) / (8 * np.pi)) * ndh ** p * np.clip((n * l).sum(-1), 0, 1)
    sky = 0.5 + 0.5 * np.clip(-n[..., 1] * 0.6 + n[..., 2] * 0.8, 0, 1)
    f0 = albedo * metal[..., None] + 0.04 * (1 - metal[..., None])
    diffuse = albedo * (1 - metal[..., None]) * (0.85 * ndl + 0.30 * sky[..., None])
    s = spec[..., None] * f0 * spec_scale + f0 * 0.25 * sky[..., None] * metal[..., None]
    return (diffuse + s) * ao[..., None] if np.ndim(ao) else (diffuse + s) * ao


def to8(rgb, alpha=None):
    rgb = np.clip(rgb, 0, 1) ** (1 / 2.2) * 255
    if alpha is None:
        return np.round(rgb).astype(np.uint8)
    return np.dstack([np.round(rgb), np.round(np.clip(alpha, 0, 1) * 255)]).astype(np.uint8)


def write_asset(name, arr):
    d = assets / f"{name}.imageset"
    d.mkdir(exist_ok=True)
    for old in d.glob("*.png"):
        old.unlink()
    Image.fromarray(arr, "RGBA" if arr.shape[-1] == 4 else "RGB").save(d / f"{name}.png", optimize=True)
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def write_map(name, arr):
    maps.mkdir(exist_ok=True)
    Image.fromarray(arr).save(maps / f"{name}.png", optimize=True)


def normal_png(n):
    return np.round((n * 0.5 + 0.5) * 255).astype(np.uint8)


def supersampled(fn, h, w, ss=3):
    """fn(y, x) over a grid ss times finer, averaged back down (clean edges)."""
    out = fn(h * ss, w * ss)
    return [o.reshape(h, ss, w, ss, *o.shape[2:]).mean(axis=(1, 3)) for o in out]


# ================================ the knob ================================================

def knob_fields(H, W):
    """Coverage, normal, roughness, metalness, part ids, spun angle; units of the skirt radius."""
    ys, xs = np.mgrid[0:H, 0:W]
    x = (xs + 0.5) / W * KNOB_BOX - KNOB_BOX / 2
    y = (ys + 0.5) / H * KNOB_BOX - KNOB_BOX / 2
    n = np.zeros((H, W, 3)); n[..., 2] = 1
    rough = np.full((H, W), 0.4)
    metal = np.zeros((H, W))
    part = np.zeros((H, W), np.int8)          # 0 none, 1 skirt side, 2 shoulder, 3 bevel, 4 cap face
    knurl = 64
    # skirt side: a tapered cylinder seen from the front and above. Pixel at height h in [0, 1]:
    # centre (0, CAP_DY*h), radius 1 - (1-TOP_R)*h. Walk h upward; the last one that covers wins.
    for h in np.linspace(0, 1, 90):
        cy, r = CAP_DY * h, 1 - (1 - TOP_R) * h
        dx, dy = x, y - cy
        d = np.hypot(dx, dy)
        on = d <= r
        th = np.arctan2(dy, dx)
        ridge = np.sin(th * knurl)
        nn = np.stack([np.cos(th), np.sin(th) * 0.55, np.full_like(th, 0.45 + 0.25 * h)], -1)
        tang = np.stack([-np.sin(th), np.cos(th), np.zeros_like(th)], -1)
        nn = norm(nn + tang * ridge[..., None] * 0.22)
        n[on] = nn[on]
        part[on] = 1
        rough[on] = 0.40 + 0.15 * (1 - h)
    # top face
    dx, dy = x, y - CAP_DY
    d = np.hypot(dx, dy)
    th = np.arctan2(dy, dx)
    radial = np.stack([np.cos(th), np.sin(th), np.zeros_like(th)], -1)
    top = d <= TOP_R
    sh = top & (d > CAP_R)
    n[sh] = norm(radial * 0.45 + np.array([0, 0, 1.0]))[sh]
    part[sh] = 2; rough[sh] = 0.45
    bev = top & (d <= CAP_R) & (d > CAP_R - 0.06)
    n[bev] = norm(radial * 0.9 + np.array([0, 0, 1.0]))[bev]
    part[bev] = 3; rough[bev] = 0.18; metal[bev] = 1
    face = top & (d <= CAP_R - 0.06)
    dome = norm(radial * (d[..., None] * 0.18) + np.array([0, 0, 1.0]))
    n[face] = dome[face]
    part[face] = 4; rough[face] = 0.30; metal[face] = 1
    cover = (part > 0).astype(float)
    return cover, n, rough, metal, part.astype(float), d, th


def spun_rings(d):
    """The cap's lathe rings: fine concentric grain."""
    k = np.linspace(0, 1, 2400)
    ring = ndimage.gaussian_filter1d(rng.normal(0, 1, k.size), 1.2)
    ring = ring / ring.std()
    return np.interp(np.clip(d / CAP_R, 0, 1), k, ring)


def down(rgb, alpha, ss):
    """Shaded at ss times the size: average back down, colour weighted by coverage."""
    H, W = alpha.shape[0] // ss, alpha.shape[1] // ss
    al = alpha.reshape(H, ss, W, ss).mean(axis=(1, 3))
    pre = (rgb * alpha[..., None]).reshape(H, ss, W, ss, 3).mean(axis=(1, 3))
    return pre / np.maximum(1e-6, al[..., None]), al


KNOB_SS = 3


def build_knob(face):
    m = MATERIAL[face]
    S, ss = KNOB_PX, KNOB_SS
    cover, n, rough, metal, part, d, th = knob_fields(S * ss, S * ss)
    cap_col = np.array(m["cap"])
    grain = ndimage.gaussian_filter(spun_rings(d), 0.8)
    albedo = np.zeros(part.shape + (3,))
    albedo[part >= 1] = m["skirt"]
    cap = part >= 3
    albedo[cap] = cap_col[None] * (1 + 0.02 * grain[cap][:, None])
    yy = (np.mgrid[0:S * ss, 0:S * ss][0] + 0.5) / (S * ss) * KNOB_BOX - KNOB_BOX / 2
    # ambient occlusion: the skirt darkens toward the plate
    ao = np.where(part == 1, 1 - 0.35 * np.clip(yy, 0, 1), 1.0)
    for key in LIGHTS:
        l = light(key)
        rgb = shade(albedo, n, rough, metal, l, ao)
        # the spun face's diffuse here; its anisotropic wedges are the sheen layer
        ndl = np.clip((n * l).sum(-1), 0, 1)
        face_rgb = cap_col * (0.38 + 0.20 * ndl)[..., None] * (1 + 0.025 * grain[..., None])
        rgb = np.where((part == 4)[..., None], face_rgb, rgb)
        bevel = cap_col * (0.55 + 0.45 * ndl ** 2)[..., None]
        rgb = np.where((part == 3)[..., None], bevel, rgb)
        out, al = down(rgb, cover, ss)
        write_asset(f"MatKnob_{face}_{key}", to8(out, al))
    # sheen for the fixed light: the highlight of circular (lathe) brushing lies along the radius
    # that points at the light, on both sides of the centre
    hv = norm(L0 / np.linalg.norm(L0) + np.array([0, 0, 1.0]))
    phi = np.arctan2(hv[1], hv[0])
    lobe = np.cos(th - phi) ** 2
    wedge = lobe ** 2 * (0.45 + 0.6 * np.clip(d / CAP_R, 0, 1) ** 0.5) * (0.85 + 0.15 * grain)
    wedge = np.where(part == 4, wedge, 0)
    glint = np.where(part == 3, np.clip((n * hv).sum(-1), 0, 1) ** 10, 0)
    sheen_a = np.clip(wedge * 1.05 + glint * 0.9, 0, 1)
    sheen_rgb = np.ones(part.shape + (3,)) * (0.55 + 0.45 * cap_col)
    out, al = down(sheen_rgb, sheen_a, ss)
    write_asset(f"MatKnobSheen_{face}", to8(out, al))
    small = lambda f: f.reshape(S, ss, S, ss, *f.shape[2:]).mean(axis=(1, 3))
    _, cov = down(albedo, cover, ss)
    if face == "platinum":
        write_map("knob_normal", normal_png(norm(small(n))))
        write_map("knob_roughness", np.round(small(rough) * 255).astype(np.uint8))
        soft = ndimage.gaussian_filter(cov, S * 0.03)
        soft = ndimage.shift(soft, (S * 0.03, S * 0.008), order=1)
        contact = ndimage.gaussian_filter(cov, S * 0.008)
        write_asset("MatKnobShadow", to8(np.zeros((S, S, 3)), np.clip(soft * 0.7 + contact * 0.5, 0, 0.92)))
    alb, cov = down(albedo, cover, ss)
    write_map(f"knob_{face}_basecolor", to8(alb, cov))


# ================================ the pad ================================================

def pebble(H, W, cell):
    """Rubber pebble grain: cells with soft grooves between them (Voronoi edges), plus fine tooth."""
    count = int(H * W / (cell * cell))
    pts = rng.uniform(0, 1, (count, 2)) * [H, W]
    ys, xs = np.mgrid[0:H, 0:W]
    from scipy.spatial import cKDTree
    dist, _ = cKDTree(pts).query(np.stack([ys.ravel(), xs.ravel()], 1), k=2)
    edge = (dist[:, 1] - dist[:, 0]).reshape(H, W)
    groove = np.exp(-(edge / (cell * 0.07)) ** 2)
    height = -groove * 0.5 + ndimage.gaussian_filter(rng.normal(0, 1, (H, W)), 0.8) * 0.06
    return ndimage.gaussian_filter(height, 0.7)


def build_pad_fields():
    x0, y0, x1, y1 = PAD
    W = int(round((x1 - x0 + 2 * PAD_MARGIN) * PAD_SCALE))
    H = int(round((y1 - y0 + 2 * PAD_MARGIN) * PAD_SCALE))
    ys, xs = np.mgrid[0:H, 0:W]
    px = (xs + 0.5) / PAD_SCALE - PAD_MARGIN          # render px from the pad's left edge
    py = (ys + 0.5) / PAD_SCALE - PAD_MARGIN
    w, h = x1 - x0, y1 - y0
    # signed distance to the rounded rectangle (negative inside)
    qx = np.abs(px - w / 2) - (w / 2 - PAD_CORNER)
    qy = np.abs(py - h / 2) - (h / 2 - PAD_CORNER)
    sd = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - PAD_CORNER
    cover = np.clip(0.5 - sd * PAD_SCALE, 0, 1)
    # height: a soft rubber shoulder (quarter round) over the bevel width, flat with a faint dome on top
    inside = np.clip(-sd / PAD_BEVEL, 0, 1)
    height = np.sqrt(1 - (1 - inside) ** 2) * PAD_BEVEL
    height += 0.6 * (1 - ((px - w / 2) / (w / 2)) ** 2 * 0.5 - ((py - h / 2) / (h / 2)) ** 2 * 0.5)
    tex = pebble(H, W, cell=6 * PAD_SCALE) * inside ** 0.5
    height = height + tex * 0.7
    gy, gx = np.gradient(height * PAD_SCALE)
    n = norm(np.stack([-gx / PAD_SCALE, -gy / PAD_SCALE, np.ones_like(gx) * 0.9], -1))
    rough = np.clip(0.62 + 0.18 * (-tex) - 0.30 * np.clip(1 - inside, 0, 1) * (inside > 0.05), 0.25, 1)
    return W, H, cover, n, rough, inside, sd


def build_pad(face, fields):
    W, H, cover, n, rough, inside, sd = fields
    alb = np.array(MATERIAL[face]["pad"]) ** 2.2          # measured on screen: back to linear
    albedo = np.ones((H, W, 3)) * alb
    metal = np.zeros((H, W))
    ao = 0.45 + 0.55 * np.clip(inside * 1.6, 0, 1) ** 0.8
    for key in LIGHTS:
        rgb = shade(albedo, n, rough, metal, light(key), ao, spec_scale=1.4)
        write_asset(f"MatPad_{face}_{key}", to8(rgb, cover))
    write_map(f"pad_{face}_basecolor", to8(albedo, cover))
    if face == "platinum":
        write_map("pad_normal", normal_png(n))
        write_map("pad_roughness", np.round(rough * 255).astype(np.uint8))
        sh = ndimage.gaussian_filter(np.clip(0.5 - (sd + 1.5) * PAD_SCALE, 0, 1), 4 * PAD_SCALE)
        sh = ndimage.shift(sh, (4 * PAD_SCALE, 1 * PAD_SCALE), order=1)
        write_asset("MatPadShadow", to8(np.zeros((H, W, 3)), np.clip(sh * 1.1, 0, 0.95)))


# ============================ demo backdrops ==============================================

KNOB_CROP = (700, 78, 836, 216)        # PITCH with its dots and label
PAD_CROP = (84, 622, 312, 806)         # pad 1 in its well


def demo_knob(face, a):
    x0, y0, x1, y1 = KNOB_CROP
    c = a[y0:y1, x0:x1].copy()
    # paint the render's knob out with clean plate from between PITCH and TUNE (same rows)
    strip = a[:, 822:872].astype(float)
    cx, cy = KNOB_C
    ys, xs = np.mgrid[y0:y1, x0:x1]
    r = np.hypot(xs - cx, ys - cy)
    hole = ((np.hypot(xs - cx, ys - cy - 2) < 44.5) | (np.hypot(xs - cx, ys - (cy + CAP_DY * KNOB_R)) < 37.5)) & (ys < 190)
    c = c.astype(float)
    for yy in range(y0, y1):
        m = hole[yy - y0]
        if not m.any():
            continue
        row = strip[yy]
        tiled = np.concatenate([row, row[::-1]] * 6)[: x1 - x0]
        # match the plate's own brightness on this row, just outside the knob (dots left out)
        ring = (r[yy - y0] > 52) & (r[yy - y0] < 64)
        if ring.any():
            here = np.median(c[yy - y0][ring], axis=0)
            tiled = tiled * (here / np.maximum(1, np.median(row, axis=0)))
        c[yy - y0][m] = tiled[m]
    c = np.clip(c, 0, 255).round().astype(np.uint8)
    write_asset(f"MatDemoKnob_{face}", c.astype(np.uint8))


def demo_pad(face, a):
    x0, y0, x1, y1 = PAD_CROP
    c = a[y0:y1, x0:x1].astype(float).copy()
    gap = np.median(a[y0:y1, 299:306].astype(float), axis=1)  # the well between pads 1 and 2
    px0, py0, px1, py1 = PAD
    fx0, fy0, fx1, fy1 = int(px0 - 7), int(py0 - 7), x1, int(min(y1, py1 + 12))
    for yy in range(fy0, fy1):
        c[yy - y0, fx0 - x0:fx1 - x0] = gap[yy - y0] + rng.normal(0, 1.2, (fx1 - fx0, 1))
    c = np.clip(c, 0, 255)
    soft = ndimage.gaussian_filter(c, (1.2, 1.2, 0))
    m = np.zeros(c.shape[:2], bool)
    m[fy0 - y0:fy1 - y0, fx0 - x0:fx1 - x0] = True
    c[m] = soft[m]
    write_asset(f"MatDemoPad_{face}", np.round(c).astype(np.uint8))


def main():
    pad_fields = build_pad_fields()
    for face, name in FACES.items():
        a = np.asarray(Image.open(RENDERS / name).convert("RGB"))
        build_knob(face)
        build_pad(face, pad_fields)
        demo_knob(face, a)
        demo_pad(face, a)
    geometry = {"knobCenter": KNOB_C, "knobRadius": KNOB_R, "knobBox": KNOB_BOX, "capOffset": CAP_DY,
                "capRadius": CAP_R, "pad": PAD, "padMargin": PAD_MARGIN, "padCorner": PAD_CORNER,
                "knobCrop": KNOB_CROP, "padCrop": PAD_CROP, "light": L0.tolist(), "swing": SWING}
    (maps / "geometry.json").write_text(json.dumps(geometry, indent=2) + "\n")
    print("materials written")


if __name__ == "__main__":
    main()
