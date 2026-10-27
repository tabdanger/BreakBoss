#!/usr/bin/env python3
"""Pictures of the stage-1 knob and pad, put together the way MaterialParts.swift does on the iPad
(same layers, same cross-fades, same sheen turn, same pointer, same press), for Tyrone to judge
before the materials go across the whole face.

    python3 tools/faceplate_art/materials/preview.py BreakBoss.swiftpm OUT_DIR
"""
import math, sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
import build_materials as B

pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
out = Path(sys.argv[2] if len(sys.argv) > 2 else ".")
assets = pkg / "Resources" / "Assets.xcassets"
Z = 4                                   # preview pixels per render pixel


def img(name):
    return Image.open(assets / f"{name}.imageset" / f"{name}.png").convert("RGBA")


def light_vec(tx, ty):
    l = B.L0 + B.SWING * np.array([tx, ty, 0.0])
    return l / np.linalg.norm(l)


def over(base, layer, opacity, box, angle=0.0, anchor=(0.5, 0.5)):
    """Draw `layer` scaled into box (render px, crop space) at `opacity`, turned `angle` degrees
    clockwise about `anchor` (fraction of the layer)."""
    x0, y0, x1, y1 = box
    w, h = int(round((x1 - x0) * Z)), int(round((y1 - y0) * Z))
    lay = layer.resize((w, h), Image.LANCZOS)
    if angle:
        ax, ay = anchor[0] * w, anchor[1] * h
        lay = lay.rotate(-angle, resample=Image.BICUBIC, center=(ax, ay))
    if opacity < 1:
        a = np.asarray(lay).astype(float)
        a[..., 3] *= opacity
        lay = Image.fromarray(a.astype(np.uint8))
    base.alpha_composite(lay, (int(round(x0 * Z)), int(round(y0 * Z))))


def crossfade(base, face, part, tx, ty, box):
    over(base, img(f"Mat{part}_{face}_c"), 1, box)
    if abs(tx) > 0.001:
        over(base, img(f"Mat{part}_{face}_{'r' if tx > 0 else 'l'}"), abs(tx), box)
    if abs(ty) > 0.001:
        over(base, img(f"Mat{part}_{face}_{'d' if ty > 0 else 'u'}"), abs(ty), box)


def knob(face, value=0.5, tx=0.0, ty=0.0):
    cx0, cy0, cx1, cy1 = B.KNOB_CROP
    base = img(f"MatDemoKnob_{face}").resize(((cx1 - cx0) * Z, (cy1 - cy0) * Z), Image.LANCZOS)
    kx, ky = B.KNOB_C[0] - cx0, B.KNOB_C[1] - cy0
    half = B.KNOB_BOX * B.KNOB_R / 2
    box = (kx - half, ky - half, kx + half, ky + half)
    l, l0 = light_vec(tx, ty), light_vec(0, 0)
    k = 3.0
    sx = -(l[0] / l[2] - l0[0] / l0[2]) * k
    sy = -(l[1] / l[2] - l0[1] / l0[2]) * k
    over(base, img("MatKnobShadow"), 1, (box[0] + sx, box[1] + sy, box[2] + sx, box[3] + sy))
    crossfade(base, face, "Knob", tx, ty, box)
    turn = math.degrees(math.atan2(l[1], l[0]) - math.atan2(l0[1], l0[0]))
    strength = min(1.0, max(0.35, math.hypot(l[0], l[1]) / math.hypot(l0[0], l0[1])))
    over(base, img(f"MatKnobSheen_{face}"), strength, box, turn, (0.5, 0.5 + B.CAP_DY / B.KNOB_BOX))
    # the pointer: KnobControl's KnobPointer at the PITCH value, about the cap's centre
    capx, capy, capr = kx, ky + B.CAP_DY * B.KNOB_R, B.CAP_R * B.KNOB_R
    ang = math.radians(-135 + 270 * value)
    inner, outer, width = 0.15, 0.92, 0.115
    d = ImageDraw.Draw(base)
    ux, uy = math.sin(ang), -math.cos(ang)
    px, py = math.cos(ang), math.sin(ang)
    hw = capr * width / 2
    pts = []
    for (r, s) in ((inner, -1), (outer, -1), (outer, 1), (inner, 1)):
        pts.append(((capx + ux * capr * r + px * hw * s) * Z, (capy + uy * capr * r + py * hw * s) * Z))
    d.polygon(pts, fill=(10, 10, 10, 255), outline=(255, 255, 255, 46))
    return base


def pad(face, tx=0.0, ty=0.0, pressed=False):
    cx0, cy0, cx1, cy1 = B.PAD_CROP
    base = img(f"MatDemoPad_{face}").resize(((cx1 - cx0) * Z, (cy1 - cy0) * Z), Image.LANCZOS)
    x0, y0, x1, y1 = B.PAD
    m = B.PAD_MARGIN
    box = (x0 - m - cx0, y0 - m - cy0, x1 + m - cx0, y1 + m - cy0)
    l, l0 = light_vec(tx, ty), light_vec(0, 0)
    k = 4.0
    sx = -(l[0] / l[2] - l0[0] / l0[2]) * k
    sy = -(l[1] / l[2] - l0[1] / l0[2]) * k
    sbox = (box[0] + sx, box[1] + sy, box[2] + sx, box[3] + sy)
    if pressed:
        sbox = shrink(sbox, 0.97)
    over(base, img("MatPadShadow"), 0.35 if pressed else 1, sbox)
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    crossfade(layer, face, "Pad", tx, ty, box)
    if pressed:
        cx, cy = (box[0] + box[2]) / 2 * Z, (box[1] + box[3]) / 2 * Z
        w, h = layer.size
        s = 0.975
        layer = layer.resize((int(w * s), int(h * s)), Image.LANCZOS)
        shifted = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        shifted.alpha_composite(layer, (int(round(cx - cx * s)), int(round(cy - cy * s + 1.2 * Z))))
        layer = shifted
    base.alpha_composite(layer)
    return base


def shrink(b, s):
    cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
    return (cx + (b[0] - cx) * s, cy + (b[1] - cy) * s, cx + (b[2] - cx) * s, cy + (b[3] - cy) * s)


def render_crop(face, box):
    a = Image.open(B.RENDERS / B.FACES[face]).convert("RGBA")
    x0, y0, x1, y1 = box
    return a.crop(box).resize(((x1 - x0) * Z, (y1 - y0) * Z), Image.LANCZOS)


def label(im, text):
    d = ImageDraw.Draw(im)
    try:
        f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
    except OSError:
        f = ImageFont.load_default()
    d.rectangle([0, 0, im.width, 34], fill=(0, 0, 0, 170))
    d.text((10, 6), text, fill=(255, 255, 255, 255), font=f)
    return im


def sheet():
    faces = ["platinum", "modern", "texture", "vintage"]
    knob_cols = [("RENDER", None), ("FIXED LIGHT", dict()), ("TILT LEFT", dict(tx=-1)),
                 ("TILT RIGHT", dict(tx=1)), ("TILT TOWARD YOU", dict(ty=1)), ("PITCH 0%", dict(value=0)),
                 ("PITCH 100%", dict(value=1))]
    pad_cols = [("RENDER", None), ("FIXED LIGHT", dict()), ("TILT LEFT", dict(tx=-1)),
                ("TILT RIGHT", dict(tx=1)), ("PRESSED", dict(pressed=True))]
    kw, kh = (B.KNOB_CROP[2] - B.KNOB_CROP[0]) * Z, (B.KNOB_CROP[3] - B.KNOB_CROP[1]) * Z
    pw, ph = (B.PAD_CROP[2] - B.PAD_CROP[0]) * Z, (B.PAD_CROP[3] - B.PAD_CROP[1]) * Z
    for name, cols, w, h, make, crop in (("knob", knob_cols, kw, kh, knob, B.KNOB_CROP),
                                         ("pad", pad_cols, pw, ph, pad, B.PAD_CROP)):
        S = Image.new("RGBA", (w * len(cols), h * len(faces)), (0, 0, 0, 255))
        for r, face in enumerate(faces):
            for c, (title, kwargs) in enumerate(cols):
                tile = render_crop(face, crop) if kwargs is None else make(face, **kwargs)
                S.alpha_composite(label(tile, f"{face.upper()} {title}" if c == 0 else title), (c * w, r * h))
        S.convert("RGB").save(out / f"materials-{name}-sheet.jpg", quality=88)
    # a tilt sweep for the moving light (GIF), all four faces side by side
    frames = []
    for i in range(36):
        t = i / 36 * 2 * math.pi
        tx, ty = math.cos(t) * 0.9, math.sin(t) * 0.9
        pressed = 10 <= i % 18 <= 12
        row = Image.new("RGBA", (kw * 4 // 2 + pw * 4 // 2, max(kh, ph) // 2), (0, 0, 0, 255))
        x = 0
        for face in faces:
            k = knob(face, value=0.5 + 0.5 * math.sin(t), tx=tx, ty=ty)
            k = k.resize((kw // 2, kh // 2), Image.LANCZOS)
            row.alpha_composite(k, (x, 0)); x += kw // 2
        for face in faces:
            p = pad(face, tx=tx, ty=ty, pressed=pressed).resize((pw // 2, ph // 2), Image.LANCZOS)
            row.alpha_composite(p, (x, 0)); x += pw // 2
        frames.append(row.convert("RGB").resize((row.width // 2, row.height // 2), Image.LANCZOS))
    frames[0].save(out / "materials-tilt.gif", save_all=True, append_images=frames[1:], duration=70, loop=0)


if __name__ == "__main__":
    sheet()
    print("preview written to", out)
