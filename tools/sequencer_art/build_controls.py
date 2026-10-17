#!/usr/bin/env python3
"""Every button and chip of the sequencer picture becomes its own control (Oct 16).

Input:  plate_base.png (the sequencer picture with the dynamic labels already cleared)
        mock.png       (Tyrone's original picture, for the sprites that keep their printing)
Output: Resources/Assets.xcassets/Seq*.imageset/*.png sprites, and SeqPlate.png with the buttons
        painted out (brushed metal filled in row by row between the nearest blank columns, so the
        metal's horizontal grain carries on), plus SeqSectionGenerate.png with its two buttons cut out.

    python3 tools/sequencer_art/build_controls.py BreakBoss.swiftpm
"""
import json, sys
from pathlib import Path
from PIL import Image

HERE = Path(__file__).parent
pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "BreakBoss.swiftpm")
assets = pkg / "Resources" / "Assets.xcassets"
base = Image.open(HERE / "plate_base.png").convert("RGBA")
mock = Image.open(HERE / "mock.png").convert("RGBA")
assert base.size == (1536, 1024) and mock.size == (1536, 1024)

# name: (source, rect)  —  the sprites are cut before anything is painted out
SPRITES = {
    "SeqBtnTool":      ("base", (305, 194, 393, 239)),
    "SeqBtnTransport": ("base", (792, 193, 845, 240)),
    "SeqChipBpm":      ("base", (983, 194, 1102, 239)),
    "SeqChipBars":     ("base", (1109, 194, 1222, 239)),
    "SeqChipMain":     ("base", (1230, 194, 1351, 239)),
    "SeqBtnGear":      ("base", (1356, 194, 1402, 239)),
    "SeqBtnCloud":     ("base", (1430, 193, 1484, 241)),
    "SeqChipSnap":     ("base", (877, 245, 1047, 279)),
    "SeqChipSwing":    ("base", (1059, 244, 1219, 279)),
    "SeqChipHumanize": ("base", (1230, 244, 1368, 279)),
    "SeqSwitchBox":    ("base", (38, 715, 147, 772)),
    "SeqBtnGrid":      ("base", (47, 727, 87, 760)),
    "SeqBtnPads":      ("base", (97, 725, 137, 760)),
    "SeqDrumTrack":    ("base", (158, 715, 348, 768)),
    "SeqArrowBack":    ("base", (602, 732, 640, 772)),
    "SeqArrowFwd":     ("base", (640, 732, 677, 772)),
    "SeqChipPattern":  ("base", (677, 732, 841, 772)),
    "SeqChipKit":      ("base", (964, 732, 1129, 772)),
    "SeqBtnGenerate":  ("mock", (55, 570, 180, 616)),
    "SeqBtnClear":     ("mock", (186, 570, 266, 616)),
}

# painted out of the plate: (rect, blank column left, blank column right)
PAINT = [
    ((300, 188, 764, 244), 297, 767),       # tools, undo, redo
    ((788, 188, 1406, 244), 785, 1410),     # transport, bpm, bars, main, gear
    ((1426, 188, 1489, 245), 1423, 1494),   # cloud
    ((394, 242, 580, 284), 391, 584),       # bars pager (chevrons + the label box)
    ((872, 241, 1374, 284), 868, 1380),     # snap, swing, humanize
    ((34, 711, 358, 780), 401, 401, 781),   # grid / pads switch + drum track pill: the metal to their right,
                                            # shaded left-to-right like the blank row just under them
    ((598, 729, 846, 776), 594, 852),       # pattern arrows + chip
    ((885, 729, 1134, 776), 881, 1141),     # kit arrows + chip
]

# rounded corners (radius per corner: TL, TR, BR, BL) so a pressed button scales without a metal halo
CORNERS = {"SeqSwitchBox": (10, 10, 10, 10), "SeqArrowBack": (8, 0, 0, 8), "SeqArrowFwd": (0, 0, 0, 0), "SeqChipPattern": (0, 8, 8, 0), "SeqChipKit": (0, 8, 8, 0),
           "SeqDrumTrack": (12, 12, 12, 12), "SeqBtnGrid": (6, 6, 6, 6), "SeqBtnPads": (6, 6, 6, 6), "SeqBtnCloud": (9, 9, 9, 9),
           "SeqBtnClear": (0, 0, 0, 0), "SeqBtnTransport": (8, 8, 8, 8)}

def rounded(img, radii):
    from PIL import ImageDraw
    w, h = img.size
    mask = Image.new("L", (w * 4, h * 4), 0)
    d = ImageDraw.Draw(mask)
    d.rectangle((0, 0, w * 4 - 1, h * 4 - 1), fill=255)
    for i, (cx, cy) in enumerate([(0, 0), (w, 0), (w, h), (0, h)]):
        r = radii[i] * 4
        if r <= 0: continue
        x0 = 0 if cx == 0 else w * 4 - r; y0 = 0 if cy == 0 else h * 4 - r
        d.rectangle((x0, y0, x0 + r - 1, y0 + r - 1), fill=0)
        ex = x0 if cx == 0 else x0 - r; ey = y0 if cy == 0 else y0 - r
        d.pieslice((ex, ey, ex + 2 * r - 1, ey + 2 * r - 1), [180, 270, 0, 90][i], [270, 360, 90, 180][i], fill=255)
    out = img.copy()
    out.putalpha(mask.resize((w, h), Image.LANCZOS))
    return out

def write(name, img):
    d = assets / f"{name}.imageset"
    d.mkdir(exist_ok=True)
    img.save(d / f"{name}.png")
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

for name, (src, r) in SPRITES.items():
    write(name, rounded((base if src == "base" else mock).crop(r), CORNERS.get(name, (7, 7, 7, 7))))

plate = base.copy()
px = plate.load()
for entry in PAINT:
    (x0, y0, x1, y1), cl, cr = entry[:3]
    prof = entry[3] if len(entry) > 3 else None
    ref = base.getpixel((cr, prof))[0] if prof else 1
    for y in range(y0, y1):
        a = px[cl, y]; b = px[cr, y]
        for x in range(x0, x1):
            t = (x - x0) / max(1, x1 - x0 - 1)
            k = base.getpixel((x, prof))[0] / max(1, ref) if prof else 1
            px[x, y] = tuple(min(255, int(round((a[i] + (b[i] - a[i]) * t) * k))) for i in range(3)) + (255,)
write("SeqPlate", plate)

# GENERATE box: its two buttons come out (the box's own black fills the holes)
gen = Image.open(HERE / "gen_base.png").convert("RGBA") if (HERE / "gen_base.png").exists() \
    else Image.open(assets / "SeqSectionGenerate.imageset" / "SeqSectionGenerate.png").convert("RGBA")
if not (HERE / "gen_base.png").exists():
    gen.save(HERE / "gen_base.png")
gx0, gy0 = 41, 375
fill = gen.getpixel((150 - gx0, 560 - gy0))
for r in [(53, 568, 182, 618), (184, 568, 268, 618)]:
    hole = Image.new("RGBA", (r[2] - r[0], r[3] - r[1]), fill)
    gen.paste(hole, (r[0] - gx0, r[1] - gy0))
write("SeqSectionGenerate", gen)
print("sprites:", len(SPRITES), "painted:", len(PAINT))

# Section headers: their printed chevrons come off (the live chevron shows which section is open)
for name in ("SeqSectionGeneral", "SeqGenerateHeader", "SeqSectionMidi"):
    src = HERE / f"{name}_base.png"
    img = Image.open(src if src.exists() else assets / f"{name}.imageset" / f"{name}.png").convert("RGBA")
    if not src.exists(): img.save(src)
    w, h = img.size
    pxh = img.load()
    for y in range(6, h - 6):
        c = pxh[w - 62, y]
        for x in range(w - 54, w - 12):
            pxh[x, y] = c
    write(name, img)

# A blank metal header (SOUNDS / GENERATE get their names in code, in the finish's ink colour)
hdr = Image.open(HERE / "SeqSectionGeneral_base.png").convert("RGBA")
w, h = hdr.size
pxh = hdr.load()
for y in range(3, h - 3):
    c = pxh[190, y]
    for x in range(8, w - 8):
        pxh[x, y] = c
write("SeqHeader", hdr)
