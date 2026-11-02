#!/usr/bin/env python3
"""Cuts Face 1's slider knob, the empty slot under it, and the power cap out of each plate
(Tyrone, Nov 2: "the slider needs to slide like it was before"). The app shows these only while
a finger moves them; at rest the plate is exactly his picture.

  slider_knob_<face>.png  the knob disc (soft alpha edge), drawn at KNOB_RECT and slid right
  slider_slot_<face>.png  the slot at SLOT_RECT with the knob taken out (each row filled from
                          the plain slot further right), shown under the moving knob
  power_cap_<face>.png    the power button disc at POWER_RECT, pressed in while touched

Run from the repo root: python3 tools/faceplate_art/face1/slider_parts.py
"""
import json, os
import numpy as np
from PIL import Image

ASSETS = "BreakBoss.swiftpm/Resources/Assets.xcassets"
FACES = ["platinum", "modern", "vintage", "texture"]
KNOB_C, KNOB_R = (214.5, 982.5), 26.0          # art px; the cap is ~24 px, +2 for its rim
KNOB_RECT = (188, 956, 241, 1009)
SLOT_RECT = (184, 950, 248, 1016)
SLOT_END_C, SLOT_IN_R = (214.0, 982.0), 26.0   # the slot's round left end, inside its rim
FILL_X = 285                                   # plain slot column (between the chevron and the play mark)
POWER_C, POWER_R = (142.5, 981.5), 31.5
POWER_RECT = (110, 949, 175, 1014)


def disc_alpha(rect, c, r, soft=1.5):
    x0, y0, x1, y1 = rect
    ys, xs = np.mgrid[y0:y1, x0:x1].astype(float)
    d = np.hypot(xs + 0.5 - c[0], ys + 0.5 - c[1])
    return np.clip((r - d) / soft + 0.5, 0, 1)


def save(img, name):
    folder = os.path.join(ASSETS, name + ".imageset")
    os.makedirs(folder, exist_ok=True)
    img.save(os.path.join(folder, name + ".png"))
    json.dump({"images": [{"filename": name + ".png", "idiom": "universal", "scale": "1x"}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(folder, "Contents.json"), "w"), indent=2)


for face in FACES:
    plate = np.asarray(Image.open(f"{ASSETS}/Plate_{face}.imageset/Plate_{face}.png").convert("RGBA")).astype(float)

    x0, y0, x1, y1 = KNOB_RECT
    knob = plate[y0:y1, x0:x1].copy()
    knob[..., 3] = 255 * disc_alpha(KNOB_RECT, KNOB_C, KNOB_R)
    save(Image.fromarray(knob.astype(np.uint8)), f"slider_knob_{face}")

    x0, y0, x1, y1 = SLOT_RECT
    slot = plate[y0:y1, x0:x1].copy()
    # the slot's inside (its round end and the straight run to the right), inset past its rim,
    # so the knob and its shadow go and the slot reads as one even channel
    ys, xs = np.mgrid[y0:y1, x0:x1].astype(float)
    cx, cy, r = SLOT_END_C[0], SLOT_END_C[1], SLOT_IN_R
    d = np.where(xs + 0.5 < cx, np.hypot(xs + 0.5 - cx, ys + 0.5 - cy), np.abs(ys + 0.5 - cy))
    a = np.clip((r - d) / 2.0 + 0.5, 0, 1)[..., None]
    fill = np.repeat(plate[y0:y1, FILL_X:FILL_X + 1], x1 - x0, axis=1)
    slot = slot * (1 - a) + fill * a
    slot[..., 3] = 255
    save(Image.fromarray(slot.astype(np.uint8)), f"slider_slot_{face}")

    x0, y0, x1, y1 = POWER_RECT
    cap = plate[y0:y1, x0:x1].copy()
    cap[..., 3] = 255 * disc_alpha(POWER_RECT, POWER_C, POWER_R)
    save(Image.fromarray(cap.astype(np.uint8)), f"power_cap_{face}")
    print(face, "done")
