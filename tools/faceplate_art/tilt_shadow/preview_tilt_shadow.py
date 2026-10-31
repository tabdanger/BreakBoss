#!/usr/bin/env python3
"""Preview of Face 1's shadow tilt (TiltShadows.swift), composited like the app does it.

Same maths and shapes as the Swift: knob = cylinder shadow (core + soft edge + contact),
pad = block shadow into the well, everything cut away over knob bodies and pad tops.
Writes preview/tilt-shadow-platinum.gif and preview/tilt-shadow-four-faces.jpg.
"""
import json, math, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
RES = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources")
OUT = os.path.join(HERE, "preview")

REST_DOWN, HINGE = 0.55, 0.45
KNOB_BODY, KNOB_REACH, PAD_REACH, PAD_CORNER = 1.32, 1.25, 16, 6
SS = 2  # supersample


def lean(gx, gy):
    x = max(-1, min(1, gx * 1.4))
    y = max(-1, min(1, (gy - REST_DOWN) / HINGE))
    return x, (y if y > 0 else y * 0.3)


def blurred(size, draw_fn, blur):
    m = Image.new("L", (size[0] * SS, size[1] * SS), 0)
    draw_fn(ImageDraw.Draw(m))
    if blur > 0:
        m = m.filter(ImageFilter.GaussianBlur(blur * SS / 2))
    return m


def capsule(d, c, r, length, ang, wide=1.0, long=1.0):
    # foot circle swept `length` along `ang`; `wide` across, `long` along (about the foot)
    pts = []
    ca, sa = math.cos(ang), math.sin(ang)
    for i in range(64):
        t = i / 64 * 2 * math.pi
        lx, ly = math.cos(t) * r, math.sin(t) * r
        if lx > 0:
            lx += length
        lx *= long
        ly *= wide
        pts.append(((c[0] + lx * ca - ly * sa) * SS, (c[1] + lx * sa + ly * ca) * SS))
    d.polygon(pts, fill=255)


def shadow_alpha(L, lx, ly):
    W, H = L["size"]
    size = (int(W), int(H))
    S = min(1, math.hypot(lx, ly) * 2)
    n = math.hypot(lx, ly)
    ang = math.atan2(ly, lx)
    dx, dy = (lx / n, ly / n) if n > 1e-4 else (0, 0)
    total = Image.new("F", (size[0] * SS, size[1] * SS), 0.0)  # accumulated light let through (log)
    keep = Image.new("L", total.size, 255)
    layers = []
    for k in L["knobs"].values():
        c, b = (k["x"], k["y"]), k["r"] * KNOB_BODY
        t = n * b * KNOB_REACH
        layers.append((blurred(size, lambda d: capsule(d, c, b, t * 1.35, ang, 1.08 + 0.10 * S), b * 0.42), 0.34 * S))
        layers.append((blurred(size, lambda d: capsule(d, c, b, t, ang), b * 0.14), 0.62 * S))
        cc = (c[0] + dx * t * 0.08, c[1] + dy * t * 0.08)
        layers.append((blurred(size, lambda d: capsule(d, cc, b, 0, ang, 1.07, 1.07), b * 0.10), 0.5 * S))
    for p in L["pads"]:
        for mul, blur, op in ((1.4, 9, 0.38), (1.0, 3, 0.66)):
            vx, vy = lx * PAD_REACH * mul, ly * PAD_REACH * mul
            x0, y0 = min(p[0], p[0] + vx), min(p[1], p[1] + vy)
            x1, y1 = max(p[2], p[2] + vx), max(p[3], p[3] + vy)
            layers.append((blurred(size, lambda d: d.rounded_rectangle([x0 * SS, y0 * SS, x1 * SS, y1 * SS], PAD_CORNER * SS, fill=255), blur), op))
    # cut-out: knob bodies and pad tops
    cd = ImageDraw.Draw(keep)
    for k in L["knobs"].values():
        b = k["r"] * KNOB_BODY
        cd.ellipse([(k["x"] - b) * SS, (k["y"] - b) * SS, (k["x"] + b) * SS, (k["y"] + b) * SS], fill=0)
    for p in L["pads"]:
        cd.rounded_rectangle([p[0] * SS, p[1] * SS, p[2] * SS, p[3] * SS], PAD_CORNER * SS, fill=0)
    # 1 - prod(1 - a_i): composite the layers "over" each other
    through = Image.new("L", total.size, 255)
    for m, op in layers:
        a = m.point(lambda v, op=op: int(255 - v * op))
        through = ImageChops.multiply(through, a)
    dark = ImageChops.invert(through)
    dark = ImageChops.multiply(dark, keep)
    return dark.resize(size, Image.LANCZOS)


def composite(face, L, gx, gy):
    plate = Image.open(os.path.join(RES, "Assets.xcassets", f"Plate_{face}.imageset", f"Plate_{face}.png")).convert("RGB")
    lx, ly = lean(gx, gy)
    dark = shadow_alpha(L, lx, ly)
    black = Image.new("RGB", plate.size, (0, 0, 0))
    return Image.composite(black, plate, dark)


def label(img, text):
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, img.width, 34], fill=(0, 0, 0))
    d.text((12, 8), text, fill=(255, 255, 255))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    layout = json.load(open(os.path.join(RES, "KnockLayout.json")))
    # GIF: Platinum, rest -> tip right -> stand up -> tip left -> rest
    path = []
    for i in range(10): path.append((0.45 * math.sin(i / 10 * math.pi / 2), REST_DOWN))
    for i in range(10): path.append((0.45 * math.cos(i / 10 * math.pi / 2), REST_DOWN + 0.45 * math.sin(i / 10 * math.pi / 2)))
    for i in range(10): path.append((-0.45 * math.sin(i / 10 * math.pi / 2), 1.0 - 0.45 * math.sin(i / 10 * math.pi / 2)))
    for i in range(10): path.append((-0.45 * math.cos(i / 10 * math.pi / 2), REST_DOWN))
    frames = []
    for gx, gy in path:
        f = composite("platinum", layout["platinum"], gx, gy).resize((725, 542), Image.LANCZOS)
        frames.append(f.convert("P", palette=Image.ADAPTIVE, colors=200))
    frames[0].save(os.path.join(OUT, "tilt-shadow-platinum.gif"), save_all=True, append_images=frames[1:], duration=90, loop=0)
    # four faces: at rest (exactly the plate) vs tipped right and stood up
    tiles = []
    for face in ["platinum", "modern", "vintage", "texture"]:
        L = layout[face]
        a = label(composite(face, L, 0, REST_DOWN).resize((725, 542), Image.LANCZOS), f"{face.upper()}  usual angle (plate unchanged)")
        b = label(composite(face, L, 0.35, 0.95).resize((725, 542), Image.LANCZOS), f"{face.upper()}  tipped right + stood up")
        row = Image.new("RGB", (1450, 542))
        row.paste(a, (0, 0)); row.paste(b, (725, 0))
        tiles.append(row)
    sheet = Image.new("RGB", (1450, 542 * 4))
    for i, t in enumerate(tiles): sheet.paste(t, (0, 542 * i))
    sheet.save(os.path.join(OUT, "tilt-shadow-four-faces.jpg"), quality=85)
    # close-up at full size
    z = composite("platinum", layout["platinum"], 0.35, 0.95).crop((80, 440, 760, 960))
    z0 = Image.open(os.path.join(RES, "Assets.xcassets", "Plate_platinum.imageset", "Plate_platinum.png")).convert("RGB").crop((80, 440, 760, 960))
    pair = Image.new("RGB", (1360, 520)); pair.paste(label(z0, "before"), (0, 0)); pair.paste(label(z, "tilted"), (680, 0))
    pair.save(os.path.join(OUT, "tilt-shadow-closeup.jpg"), quality=88)


if __name__ == "__main__":
    main()
