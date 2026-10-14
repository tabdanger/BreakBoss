# Platinum is the master (Tyrone, Oct 14). Run from /home/claude/art3 after plat_geom.py,
# before clean.py and buttons.py. iPad: Platinum's own layout (not warped). iPhone: Platinum's plate.
# Modern, Vintage and Texture are rebuilt from Platinum (master2.py); every plate gets the same knobs,
# the same Aldrich lettering and Modern's wood frame (left side mirrored from the right).
import json, numpy as np, cv2
import unify, master2
from PIL import Image, ImageDraw

A2 = "/home/claude/art2"
K2 = json.load(open(f"{A2}/knobs.json")); R2 = json.load(open(f"{A2}/rects.json"))
K = json.load(open("knobs.json")); R = json.load(open("rects.json"))
CAPS = json.load(open("caps.json"))
LABELS = json.load(open("labels_modern.json"))
ORDER = unify.ORDER

def rounded(h, w, r):
    big = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * 4 - 1, h * 4 - 1], radius=r * 4, fill=255)
    return np.asarray(big.resize((w, h), Image.LANCZOS)).astype(np.float32) / 255

def put_cap(a, cap, x0, y0):
    h, w = cap.shape[:2]; al = rounded(h, w, 5); pad = 10
    sh = np.zeros((h + pad * 2, w + pad * 2), np.float32); sh[pad + 3:pad + 3 + h, pad:pad + w] = al
    sh = cv2.GaussianBlur(sh, (0, 0), 3) * 0.5
    a[y0 - pad:y0 + h + pad, x0 - pad:x0 + w + pad] *= (1 - sh)[..., None]
    a[y0:y0 + h, x0:x0 + w] = a[y0:y0 + h, x0:x0 + w] * (1 - al[..., None]) + cap * al[..., None]

# iPad: Platinum's velocity knob sits where Modern's buttons were, so the piano / export / menu buttons
# sit in a row in the top-right corner, clear of the knob and its dots.
TOPCAPS = {"editorRect": (1270, 12, 1304, 46), "exportRect": (1308, 12, 1342, 46), "menuRect": (1346, 12, 1380, 46)}
_ns = {}
_b = open("buttons.py").read()
exec("import numpy as np, cv2\nfrom PIL import Image, ImageDraw\n" + _b[_b.index("def piano_cap"):_b.index("def tablet_buttons")], _ns)

def top_caps(img):
    modern = cv2.imread(f"{A2}/src/l_modern.png").astype(np.float32)
    e, m = CAPS["l_modern"]
    f = img.astype(np.float32)
    exp = modern[e[1]:e[3], e[0]:e[2]]; men = modern[m[1]:m[3], m[0]:m[2]]
    rgb = lambda c: c[..., ::-1].copy()
    piano = rgb(_ns["piano_cap"](rgb(exp)))
    for key, cap in (("editorRect", piano), ("exportRect", exp), ("menuRect", men)):
        x0, y0, x1, y1 = TOPCAPS[key]
        put_cap(f, cv2.resize(cap, (x1 - x0, y1 - y0), interpolation=cv2.INTER_AREA), x0, y0)
    return np.clip(f, 0, 255).astype(np.uint8)

def geometry(dev):
    if dev == "l":
        G = json.load(open("plat_geom_l.json"))
        G["rects"]["exportRect"], G["rects"]["menuRect"] = list(TOPCAPS["exportRect"]), list(TOPCAPS["menuRect"])
        G["rects"]["editorRect"] = list(TOPCAPS["editorRect"])
        G["rects"]["well"] = G["regions"]["well"]
        return G
    # iPhone: Tyrone's Platinum plate is already laid out like Modern (platinum.py lines it up)
    Rm = R2["p_modern"]
    G = {"knobs": {k: list(K2["p_modern"][k]) for k in ORDER}, "rects": json.loads(json.dumps(Rm)),
         "pads": Rm["pads"], "labels": LABELS["p"], "regions": {k: list(v) for k, v in __import__("master").REG_P.items()}}
    return G

if __name__ == "__main__":
    for dev in "lp":
        G = geometry(dev)
        src = cv2.imread(f"src/{dev}_platinum_P.png")
        H, W = src.shape[:2]
        caps = CAPS["l_modern"] if dev == "l" else None
        if dev == "l":
            # Modern's export / menu caps on Platinum (top right, same spot as every plate)
            modern = cv2.imread(f"{A2}/src/l_modern.png")
            def with_caps(im):
                f = im.astype(np.float32)
                for x0, y0, x1, y1 in caps:
                    put_cap(f, modern[y0:y1, x0:x1].astype(np.float32), x0, y0)
                return np.clip(f, 0, 255).astype(np.uint8)
            # (caps go on after the knobs, see TOPCAPS)
        # unify's helpers read Modern's measurements: point them at Platinum's
        unify.K2 = dict(K2); unify.K2[f"{dev}_modern"] = G["knobs"]
        unify.K2[f"{dev}_platinum"] = ({k: [0, 0, v] for k, v in G["plat_knob_r"].items()} if dev == "l"
                                        else {k: [0, 0, K2["p_modern"][k][2] + 2] for k in ORDER})
        unify.K = dict(K); unify.K[f"{dev}_modern"] = G["knobs"]
        unify.LABELS = dict(LABELS); unify.LABELS[dev] = G["labels"]
        unify.R2 = dict(R2); unify.R2[f"{dev}_modern"] = G["rects"]
        master2.LOOK["modern"]["pads"] = "dark"
        plates = {"platinum": src, **{k: master2.build(dev, k, src, G, caps) for k in ("modern", "vintage", "texture")}}
        # wood: Modern's frame, left side mirrored from the right
        mod = cv2.imread(f"{A2}/src/{dev}_modern.png")
        wm = unify.wood_mask(dev, H, W)
        frame = mod.copy(); Rr = unify.BODY[f"{dev}_modern"][1]; side = W - (Rr + 2)
        frame[:, :side] = mod[:, ::-1][:, :side]
        sprites = unify.knob_sprites(dev)
        for mode, img in plates.items():
            # knobs near the top edge: work on a padded copy so the sprites fit
            PADN = 130
            big = cv2.copyMakeBorder(img, PADN, PADN, PADN, PADN, cv2.BORDER_REFLECT)
            kk, ll = unify.K, unify.LABELS
            unify.K = dict(kk); unify.K[f"{dev}_modern"] = {k: [v[0] + PADN, v[1] + PADN, v[2]] for k, v in kk[f"{dev}_modern"].items()}
            unify.LABELS = dict(ll); unify.LABELS[dev] = {k: ([v[0] + PADN, v[1] + PADN, v[2] + PADN, v[3] + PADN] if v else v) for k, v in ll[dev].items()}
            big = unify.paste_knobs(big, dev, "platinum" if mode == "platinum" else "modern", sprites, clear=False)
            unify.K, unify.LABELS = kk, ll
            img = big[PADN:PADN + H, PADN:PADN + W]
            if dev == "l": img = top_caps(img)
            fresh = mode != "platinum" or dev == "l"
            img = unify.redraw_clipper_label(img, dev, erase=not fresh)
            img = unify.redraw_text(img, dev, erase=not fresh)
            img = (img.astype(np.float32) * (1 - wm) + frame.astype(np.float32) * wm).astype(np.uint8)
            cv2.imwrite(f"src/{dev}_{mode}.png", img)
        # every plate: Platinum's measurements
        for mode in ("modern", "vintage", "texture", "platinum"):
            n = f"{dev}_{mode}"
            K[n] = {k: list(G["knobs"][k]) for k in ORDER}
            keep = {key: R[n][key] for key in R.get(n, {}) if key.endswith("_score")}
            rr = {k: v for k, v in G["rects"].items()}
            rr["pads"] = G["pads"]
            if dev == "l":
                rr["ledTempo"], rr["ledFollow"] = G["rects"]["ledTempo"], G["rects"]["ledFollow"]
            R[n] = rr; R[n].update(keep)
        if dev == "l":
            LABELS["l"] = G["labels"]
        print(dev, "done")
    json.dump(K, open("knobs.json", "w"), indent=1); json.dump(R, open("rects.json", "w"), indent=1)
    json.dump(LABELS, open("labels_platinum.json", "w"), indent=1)
    for n in ("l_vintage", "l_texture", "l_platinum"): CAPS[n] = CAPS["l_modern"]
    json.dump(CAPS, open("caps.json", "w"))
