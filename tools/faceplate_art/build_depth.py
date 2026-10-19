#!/usr/bin/env python3
"""Face 1's plates with more depth and texture (Oct 17, Tyrone: "add MORE depth and texture to the
faceplates, want them to look hyper realistic").

Works on the finished plates (Plate_<face>.png) and the state overlays cut from them
(oneshot_on, loop_off, clipper_off, play_on, led_off). The untouched art is kept in depth_base/ (copied
there the first time this runs), so running it again starts from the same pictures:
  - a soft light from the top left with a sheen across the plate (everything, overlays included,
    so they still sit seamlessly on the plate)
  - on the bare plate only: the plate's own detail brought up, its grain deepened (Vintage / Texture
    pebble, Platinum / Modern brushed), the panels and pad well sunk into it (shadowed top wall, lit
    bottom lip) and the raised buttons throwing a soft shadow down and right.
The controls' rectangles (and so every overlay) are left out of the plate-only steps, so no overlay
shows a patch. Uses tools/sequencer_art/metal.py.

    python3 tools/faceplate_art/build_depth.py BreakBoss.swiftpm [--only=modern]
"""
import json, shutil, sys
from pathlib import Path
import numpy as np
from PIL import Image
from scipy import ndimage

here = Path(__file__).resolve().parent
sys.path.insert(0, str(here.parent / "sequencer_art"))
import metal as M

args = [a for a in sys.argv[1:] if not a.startswith("--only=")]
only = {a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--only=")}
pkg = Path(args[0] if args else "BreakBoss.swiftpm")
assets = pkg / "Resources" / "Assets.xcassets"
layouts = json.loads((pkg / "Resources" / "KnockLayout.json").read_text())
base = here / "depth_base"
base.mkdir(exist_ok=True)
OVERLAYS = {"oneshot_on": "oneShotButton", "loop_off": "loopButton", "clipper_off": "clipperRect",
            "play_on": "playRect", "led_off": None}
SEED = {"platinum": 21, "modern": 22, "vintage": 23, "texture": 24}
# Modern is smooth black metal (Tyrone, Oct 19: the added grain, detail and relief made it look rough): its
# plate keeps the light and the buttons' shadows only.
SMOOTH = {"modern"}


def source(name):
    """The untouched picture (copied to depth_base/ the first time)."""
    keep = base / f"{name}.png"
    if not keep.exists():
        shutil.copy(assets / f"{name}.imageset" / f"{name}.png", keep)
    im = Image.open(keep)
    return np.asarray(im.convert("RGBA")).astype(np.float32), im.mode


def save(name, a, mode):
    out = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    out.convert(mode).save(assets / f"{name}.imageset" / f"{name}.png", optimize=True)


def rect_mask(shape, rects, pad=0):
    m = np.zeros(shape, dtype=bool)
    for x0, y0, x1, y1 in rects:
        m[max(0, int(y0) - pad):int(y1) + pad, max(0, int(x0) - pad):int(x1) + pad] = True
    return m


def surface(rgb, kind):
    """How much a pixel is the bare plate (its finish colour, any shade of it), 0...1."""
    L, S = M.lum(rgb), M.sat(rgb)
    if kind == "vintage":
        c = rgb / np.maximum(L, 1)[..., None]
        d = np.linalg.norm(c - M.CREAM / M.lum(M.CREAM[None, None])[..., None], axis=2)
        return (1 - M.smoothstep(0.06, 0.16, d)) * M.smoothstep(110, 150, L)
    if kind == "texture":
        c = rgb / np.maximum(rgb.sum(axis=2), 1)[..., None]
        d = np.linalg.norm(c - M.BLUE / M.BLUE.sum(), axis=2)
        return (1 - M.smoothstep(0.05, 0.13, d)) * M.smoothstep(25, 50, L)
    if kind == "platinum":
        return (1 - M.smoothstep(14, 30, S)) * M.smoothstep(100, 135, L) * (1 - M.smoothstep(222, 240, L))
    return (1 - M.smoothstep(8, 16, S)) * M.smoothstep(16, 24, L) * (1 - M.smoothstep(52, 64, L))


for kind, L in layouts.items():
    if L.get("device", "tablet") != "tablet" or (only and kind not in only):
        continue
    plate, mode = source(f"Plate_{kind}")
    rgb = plate[..., :3]
    h, w = rgb.shape[:2]
    raised = [L["oneShotButton"], L["loopButton"], L["clipperRect"], L["playRect"], L["diceRect"], L["saveRect"],
              L["exportRect"], L["menuRect"]] + list(L["modeButtons"].values())
    if L.get("editorRect"):
        raised.append(L["editorRect"])
    leds = list(L["leds"].values())
    # left out of the plate-only steps: the pads, the knob caps (round, so no square shows round a
    # knob) and, on Modern where the buttons are the plate's own black, the buttons
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    controls = rect_mask((h, w), L["pads"]).astype(np.float32)
    for k in L["knobs"].values():
        controls = np.maximum(controls, 1 - M.smoothstep(k["r"] * 1.0, k["r"] * 1.12, np.hypot(xx - k["x"], yy - k["y"])))
    if kind == "modern":
        displays = [L["scope"], L["bpmBox"], L["kitBox"], L["presetBox"]]
        controls = np.maximum(controls, ndimage.gaussian_filter(rect_mask((h, w), raised + displays, pad=2).astype(np.float32), 2))
    W = (ndimage.gaussian_filter(surface(rgb, kind), 0.8) * (1 - controls))[..., None]

    # light over everything (the same for the overlays)
    f = M.light_field(h, w)[..., None]
    lightk = (f - 1) * (0.35 + 0.65 * W)

    # sunk panels: dark areas of the plate that aren't raised controls
    dark = (1 - M.smoothstep(28, 60, M.lum(rgb))) * (1 - M.smoothstep(40, 90, M.sat(rgb)))
    dark = ndimage.grey_opening(dark * ~rect_mask((h, w), raised, pad=6), size=(9, 9))
    r = M.relief(1 - dark, sigma=2.0, gain=20)[..., None]
    ao = ndimage.gaussian_filter(dark, 5)[..., None]
    sh = M.contact_shadow(rect_mask((h, w), raised).astype(np.float32), dx=3, dy=5, sigma=5)[..., None]

    out = rgb * (1 + lightk)
    if kind not in SMOOTH:
        # (on the black plate the whole surface reads as "dark", so this relief turned its fine noise into dents)
        out = out * (1 + 0.32 * r * W) + 22 * np.maximum(r, 0) * W
        out = out * (1 - 0.14 * ao * W)
    out = out * (1 - 0.32 * sh * W)
    if kind not in SMOOTH:
        out = out + 0.4 * M.clarity(out) * W
        g = M.grain(kind, h, w, SEED[kind])[..., None]
        out = out * (1 + M.GRAIN_AMOUNT[kind] * 0.6 * g * W)
    save(f"Plate_{kind}", np.concatenate([out, plate[..., 3:]], axis=2), mode)

    # the overlays: where they show the plate, exactly the new plate (so they sit on it seamlessly);
    # where they differ (a lit lamp, a pressed button), their own pixels under the same light
    for ov, key in OVERLAYS.items():
        rects = [L[key]] if key else leds
        a, omode = source(f"{ov}_{kind}")
        x0, y0 = int(rects[0][0]), int(rects[0][1])
        sl = (slice(y0, y0 + a.shape[0]), slice(x0, x0 + a.shape[1]))
        same = 1 - M.smoothstep(6, 18, np.abs(a[..., :3] - rgb[sl]).max(axis=2))
        same = ndimage.grey_erosion(same, size=(3, 3))[..., None]
        o = out[sl] * same + a[..., :3] * (1 + lightk[sl]) * (1 - same)
        save(f"{ov}_{kind}", np.concatenate([o, a[..., 3:]], axis=2), omode)
print("faceplate depth written")
