#!/usr/bin/env python3
"""Each mode's FX section on Face 1 (Tyrone, Oct 24 2026): the bottom row's printed knob names.

    VINTAGE  DRIVE · PUNCH · ANALOG EQ · GRIT · SHINE · TIGHTEN · NOISE
    TEXTURE  DRIVE · RESAMPLE · INSTABILITY · DELAY · SHINE · GATED REVERB · NOISE

Modern and Platinum keep BOOST · PUNCH · ANALOG EQ · GRIT · SHINE · TIGHTEN · NOISE.

The new words are set in the plate's own lettering: every letter (with its shadow or highlight) is
lifted off that plate's other knob labels as a coverage map against the plate behind it, and laid
on the plate, in the plate's ink, where the old word was taken off. Nothing is drawn from a font, so the type, size, ink and
shadow are the render's own. The old word comes off as a patch stretched between the clean plate
on its four sides, with the plate's own grain.

Writes the four Face 1 sources here and the matching Plate_<face> assets (the label rows of the
two are the same pixels), so build_face1.py gives the same plates afterwards.

    python3 tools/faceplate_art/face1/relabel_fx.py BreakBoss.swiftpm
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).parent
pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
assets = pkg / "Resources" / "Assets.xcassets"

# Every knob label on the plates: (left, right) of its ink and the top of its capitals. Measured on
# the four renders (they line up within a pixel); capitals are 13 px tall (top..top+12).
CAP = 13
LABELS = {
    "PITCH": (739, 792, 161), "TUNE": (905, 954, 161), "BOUNCE": (1056, 1135, 161), "VELOCITY": (1221, 1313, 161),
    "FILTER": (734, 794, 303), "CLIP DRIVE": (879, 980, 303), "OUTPUT": (1058, 1133, 303), "CLIPPER": (1215, 1303, 303),
    "BOOST": (210, 273, 578), "PUNCH": (372, 435, 578), "ANALOG EQ": (516, 620, 578), "GRIT": (710, 751, 578),
    "SHINE": (869, 924, 578), "TIGHTEN": (1024, 1102, 578), "NOISE": (1201, 1256, 578),
}
TEMPO = ("TEMPO SYNC", 373)      # the lamp label; only its M is borrowed (no knob label has one)
BOTTOM = ["BOOST", "PUNCH", "ANALOG EQ", "GRIT", "SHINE", "TIGHTEN", "NOISE"]
KNOB_X = [239, 402, 566, 729, 895, 1061, 1227]
NEW = {
    "vintage": ["DRIVE", "PUNCH", "ANALOG EQ", "GRIT", "SHINE", "TIGHTEN", "NOISE"],
    "texture": ["DRIVE", "RESAMPLE", "INSTABILITY", "DELAY", "SHINE", "GATED REVERB", "NOISE"],
}
FILES = {"vintage": "Face1_Vintage.png", "texture": "Face1_Texture.png"}
PAD_T, PAD_B, PAD_X = 3, 4, 4       # around the capitals: shadow below / highlight, and to the right


def plate_behind(img, x0, x1, y0, y1):
    """The plate without the lettering in [x0, x1) x [y0, y1): a Coons patch stretched between the
    clean plate on all four sides (so the knob's shading above and the plate's light carry
    through), plus the plate's own grain."""
    f = img.astype(np.float32)

    def smooth(v):      # along a border, so one grainy pixel doesn't streak
        p = np.concatenate([v[:1], v[:1], v, v[-1:], v[-1:]], 0)
        return (p[:-4] + p[1:-3] + p[2:-2] + p[3:-1] + p[4:]) / 5

    top = smooth(f[y0 - 2:y0, x0:x1].mean(0))
    bottom = smooth(f[y1:y1 + 2, x0:x1].mean(0))
    left = smooth(np.median(f[y0:y1, x0 - 4:x0], axis=1))
    right = smooth(np.median(f[y0:y1, x1:x1 + 4], axis=1))
    u = ((np.arange(x0, x1) - x0 + 0.5) / (x1 - x0))[None, :, None]
    v = ((np.arange(y0, y1) - y0 + 0.5) / (y1 - y0))[:, None, None]
    c00, c10 = f[y0 - 1, x0 - 1], f[y0 - 1, x1]
    c01, c11 = f[y1, x0 - 1], f[y1, x1]
    fill = ((1 - v) * top[None] + v * bottom[None] + (1 - u) * left[:, None] + u * right[:, None]
            - ((1 - u) * (1 - v) * c00 + u * (1 - v) * c10 + (1 - u) * v * c01 + u * v * c11))
    # the plate's grain: same strength as the clean plate beside the word
    ref = np.concatenate([f[y0:y1, x0 - 14:x0 - 2], f[y0:y1, x1 + 2:x1 + 14]], 1).mean(2)
    hp = ref[:, 1:-1] - 0.5 * (ref[:, :-2] + ref[:, 2:])
    sd = float(np.clip(np.median(np.abs(hp)) * 1.48 / 1.22, 0.2, 3.0))
    rng = np.random.default_rng(x0 * 31 + y0)
    fill += rng.normal(0, sd, fill.shape[:2])[..., None]
    return fill


def lettering(img, name, x0, x1, top, cap=CAP):
    """The word's own pixels as a difference from the plate behind it (from PAD_T above its
    capitals to PAD_B below), each letter's columns, and the capitals' top on this plate."""
    # the capitals' real top on this plate (the renders differ by a pixel)
    ys, ye = top - 3 - PAD_T, top + cap + 3 + PAD_B
    xs, xe = x0 - 1, x1 + PAD_X
    src = img[ys:ye, xs:xe].astype(np.float32)
    behind = plate_behind(img, xs, xe, ys, ye).mean(2)
    lum = src.mean(2) - behind
    sign = 1 if lum.max() > -lum.min() else -1
    ink = (lum * sign) > 0.35 * (lum * sign).max()
    rows = np.nonzero(ink.sum(1) > 1)[0]
    t = int(rows.min())
    # coverage: +1 is the ink, -1 the shadow (light letters) or highlight (dark ones), 0 the plate
    ink_l = float(np.percentile(src.mean(2)[ink], 90 if sign > 0 else 10))
    far = 0.0 if sign > 0 else 255.0
    toward = lum / np.where(np.abs(ink_l - behind) < 1, 1, ink_l - behind)
    away = -np.abs(lum) / np.maximum(np.abs(far - behind), 1)
    cover = np.where(lum * sign > 0, np.clip(toward, 0, 1), np.clip(away, -1, 0))
    cover[(np.abs(cover) < 0.05) | (np.abs(lum) < 9)] = 0     # the plate's own grain stays out of the letters
    # only the letters and what they throw: ink within a pixel of the strokes, shadow or highlight
    # within two pixels below / right of them (the rest is the plate behind, not the lettering)
    core = cover > 0.3
    near, cast = np.zeros_like(core), np.zeros_like(core)
    for dy in range(-1, 3):
        for dx in range(-1, 3):
            moved = np.roll(np.roll(core, dy, 0), dx, 1)
            if abs(dy) <= 1 and abs(dx) <= 1: near |= moved
            if dy >= 0 and dx >= 0: cast |= moved
    cover[(cover > 0) & ~near] = 0
    cover[(cover < 0) & ~(cast | near)] = 0
    delta = cover[t - PAD_T:t + cap + PAD_B]
    ink = ink[t:t + cap]
    cols = ink.any(0)
    starts, ends = [], []
    for i, c in enumerate(cols):
        if c and (i == 0 or not cols[i - 1]): starts.append(i)
        if c and (i == len(cols) - 1 or not cols[i + 1]): ends.append(i + 1)
    letters = [ch for ch in name if ch != " "]
    if len(starts) != len(letters):
        raise ValueError(f"{name}: found {len(starts)} letters, expected {len(letters)}")
    return delta, list(zip(letters, starts, ends)), ys + t


def harvest(img):
    """Every letter on the plate: its pixels (difference from the plate, with its shadow or
    highlight) and the width of its ink; the usual gap between letters and a word space."""
    glyphs, gaps, spaces = {}, [], []
    for name, (x0, x1, top) in LABELS.items():
        try:
            delta, found, _ = lettering(img, name, x0, x1, top)
        except ValueError:
            continue        # letters that touch (FILTER's L and T): not a source
        words = name.split(" ")
        last_of_word = list(np.cumsum([len(w) for w in words]) - 1)
        for i, (ch, s, e) in enumerate(found):
            last = i + 1 == len(found)
            stop = e + PAD_X if last else found[i + 1][1]
            # a last letter brings its whole shadow; prefer that copy
            if ch not in glyphs or last:
                glyphs[ch] = (delta[:, s:stop].copy(), e - s)
            if not last:
                (spaces if i in last_of_word else gaps).append(found[i + 1][1] - e)
    # M: only on the TEMPO SYNC lamp label, whose capitals are 11 px; brought up to the knob labels' 13
    name, top = TEMPO
    delta, found, _ = lettering(img, name, 386, 480, top, cap=11)
    for i, (ch, s, e) in enumerate(found):
        if ch == "M":
            d = delta[:, s:found[i + 1][1]]
            k = CAP / 11
            h, w = int(round(d.shape[0] * k)), int(round(d.shape[1] * k))
            up = np.clip(np.asarray(Image.fromarray(d.astype(np.float32)).resize((w, h), Image.LANCZOS)), -1, 1)
            # same rows as the other letters: PAD_T above, PAD_B below the capitals
            t = int(round(PAD_T * k)) - PAD_T
            glyphs["M"] = (up[t:t + PAD_T + CAP + PAD_B], int(round((e - s) * k)))
    # the ink: the plate's own lettering at full coverage
    x0, x1, top = LABELS["NOISE"]
    patch = img[top:top + CAP, x0:x1].astype(np.float32)
    lum = patch.mean(2)
    sign = 1 if lum.max() - np.median(lum) > np.median(lum) - lum.min() else -1     # light letters or dark
    pick = lum >= np.percentile(lum, 95) if sign > 0 else lum <= np.percentile(lum, 5)
    ink = np.median(patch[pick], axis=0)
    return glyphs, int(round(np.median(gaps))), int(round(np.median(spaces))), ink, (0.0 if sign > 0 else 255.0)


def set_word(glyphs, gap, space, word):
    """The word's coverage (see lettering), and the width of its capitals."""
    pieces, x = [], 0
    for ch in word:
        if ch == " ":
            x += space - gap
            continue
        d, w = glyphs[ch]
        pieces.append((x, d))
        x += w + gap
    width = x - gap
    h = pieces[0][1].shape[0]
    out = np.zeros((h, width + PAD_X), np.float32)
    for px, d in pieces:
        d = d[:, :min(d.shape[1], out.shape[1] - px)]
        region = out[:, px:px + d.shape[1]]
        # a letter's ink wins over the shadow of the one before it
        out[:, px:px + d.shape[1]] = np.where(np.abs(d) > np.abs(region), d, region)
    return out, width


def relabel(img, face):
    glyphs, gap, space, ink, far = harvest(img)
    out = img.astype(np.float32)
    for old, new, cx in zip(BOTTOM, NEW[face], KNOB_X):
        if old == new:
            continue
        x0, x1, top = LABELS[old]
        _, _, top = lettering(img, old, x0, x1, top)
        ys, ye = top - PAD_T, top + CAP + PAD_B
        xs, xe = x0 - 3, x1 + PAD_X + 2
        out[ys:ye, xs:xe] = plate_behind(img, xs, xe, ys, ye)
        word, width = set_word(glyphs, gap, space, new)
        wx = int(round(cx + 1 - width / 2))
        bx0, bx1 = wx - 1, wx - 1 + word.shape[1]
        base = out[ys:ye, bx0:bx1]
        a = np.clip(word, 0, 1)[..., None]
        sh = np.clip(-word, 0, 1)[..., None]
        out[ys:ye, bx0:bx1] = (base * (1 - sh) + far * sh) * (1 - a) + ink * a
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


def main():
    for face, src in FILES.items():
        for path in (HERE / src, assets / f"Plate_{face}.imageset" / f"Plate_{face}.png"):
            im = Image.open(path)
            mode = im.mode
            rgb = np.asarray(im.convert("RGB"))
            try:
                new = relabel(rgb, face)
            except ValueError as e:      # the old words are gone: done before (it runs once)
                print("skipped", path, "-", e)
                continue
            if mode == "RGBA":
                a = np.asarray(im)[..., 3:]
                Image.fromarray(np.concatenate([new, a], 2), "RGBA").save(path)
            else:
                Image.fromarray(new).save(path)
            print("relabelled", path)


if __name__ == "__main__":
    main()
