"""The rack's grab handle: two small metal studs on the left of each track's tab (Tyrone, Oct 19).

Each face gets its own pair, cut in that face's tab metal (sampled from its SeqRow_<face> sprite):
a drilled, countersunk hole with a domed stud sitting in it, lit from the top left like the rest of
Face 2. Writes SeqGrip_<face>.imageset (@3x) into the asset catalog. Run on its own; it touches
nothing else (build_face2.py doesn't make these).

    python3 tools/sequencer_art/face2/build_grip.py
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
ASSETS = ROOT / "BreakBoss.swiftpm/Resources/Assets.xcassets"

# the sprite in points (SequencerView draws it at x 3, y 17.5 of the 260 x 59 row)
W, H = 10, 24
CENTRES = [(5.0, 7.0), (5.0, 17.0)]
HOLE = 3.55      # the countersink's outer radius
STUD = 2.55      # the stud's radius
SCALE = 3        # @3x
SS = 4           # supersampling

# the stud's metal per face: Modern black chrome, Platinum polished chrome, Vintage brass, Texture
# blue anodised aluminium (each the colour of its own tab, deeper in the hole)
STUDS = {
    "modern": dict(base=(58, 58, 61), spec=0.95, shine=40),
    "platinum": dict(base=(196, 197, 200), spec=1.0, shine=60),
    "vintage": dict(base=(206, 168, 104), spec=0.85, shine=34),
    "texture": dict(base=(120, 160, 212), spec=0.8, shine=30),
}
LIGHT = np.array([-0.45, -0.6, 0.66])
LIGHT /= np.linalg.norm(LIGHT)


def tab_colour(face):
    a = np.asarray(Image.open(ASSETS / f"SeqRow_{face}.imageset/SeqRow_{face}.png").convert("RGB"), dtype=float)
    return a[18:42, 4:14].mean((0, 1))


def render(face):
    n = SCALE * SS
    ys, xs = np.mgrid[0:H * n, 0:W * n]
    x = (xs + 0.5) / n
    y = (ys + 0.5) / n
    rgb = np.zeros((H * n, W * n, 3))
    alpha = np.zeros((H * n, W * n))
    tab = tab_colour(face)
    st = STUDS[face]
    base = np.array(st["base"], dtype=float)
    for cx, cy in CENTRES:
        dx, dy = x - cx, y - cy
        r = np.hypot(dx, dy)
        # the countersink: a cone falling into the hole, so its top-left wall is in shadow and its
        # bottom-right wall catches the light
        ring = (r <= HOLE) & (r > STUD + 0.25)
        t = np.clip((r - STUD) / (HOLE - STUD), 0, 1)
        with np.errstate(invalid="ignore", divide="ignore"):
            nx, ny = -dx / np.maximum(r, 1e-6), -dy / np.maximum(r, 1e-6)
        nz = np.full_like(r, 0.75)
        norm = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
        lam = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) / norm
        wall = tab[None, None, :] * ((0.35 + 0.75 * np.clip(lam, 0, 1)) * (0.75 + 0.25 * t))[..., None]
        rgb[ring] = wall[ring]
        alpha[ring] = 1
        # the gap round the stud: a dark shadow line
        gap = (r <= STUD + 0.25) & (r > STUD)
        rgb[gap] = tab * 0.12
        alpha[gap] = 1
        # the stud: a low dome, diffuse + a tight specular dot at the top left + a rim light under it
        dome = r <= STUD
        z = np.sqrt(np.clip(1 - (r / STUD) ** 2, 0, 1))
        nx2, ny2, nz2 = dx / STUD * 0.8, dy / STUD * 0.8, z
        nn = np.sqrt(nx2 ** 2 + ny2 ** 2 + nz2 ** 2)
        nx2, ny2, nz2 = nx2 / nn, ny2 / nn, nz2 / nn
        diff = np.clip(nx2 * LIGHT[0] + ny2 * LIGHT[1] + nz2 * LIGHT[2], 0, 1)
        # Blinn half vector with the eye straight on
        hv = LIGHT + np.array([0, 0, 1.0]); hv /= np.linalg.norm(hv)
        spec = np.clip(nx2 * hv[0] + ny2 * hv[1] + nz2 * hv[2], 0, 1) ** st["shine"] * st["spec"]
        rim = np.clip(ny2, 0, 1) ** 3 * 0.35          # light bouncing off the countersink below
        # fine concentric turning marks on the stud's face, like machined metal
        turn = 1 + 0.035 * np.sin(r * 38)
        col = base[None, None, :] * (0.28 + 0.82 * diff[..., None]) * turn[..., None]
        col += 255 * (spec[..., None] + rim[..., None] * 0.5)
        rgb[dome] = col[dome]
        alpha[dome] = 1
    rgb = np.clip(rgb, 0, 255)
    # downsample (premultiplied)
    pre = np.dstack([rgb * alpha[..., None], alpha * 255])
    small = pre.reshape(H * SCALE, SS, W * SCALE, SS, 4).mean((1, 3))
    a = small[..., 3:4]
    out = np.where(a > 0, small[..., :3] / np.maximum(a / 255, 1e-6), 0)
    img = np.dstack([np.clip(out, 0, 255), a]).astype(np.uint8)
    return Image.fromarray(img, "RGBA")


def main():
    for face in STUDS:
        name = f"SeqGrip_{face}"
        d = ASSETS / f"{name}.imageset"
        d.mkdir(exist_ok=True)
        render(face).save(d / f"{name}.png")
        (d / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "3x"}],
            "info": {"author": "xcode", "version": 1},
        }, indent=2) + "\n")
        print("wrote", d)


if __name__ == "__main__":
    main()
