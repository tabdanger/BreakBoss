#!/usr/bin/env python3
"""Builds the six kits made from Tyrone's second round of packs (Oct 14): Kicks 3, Snares + Claps 2,
Percussive One Shots 2 and the 156-sound Archive (808s, claps, snares, rims, snaps, hats, open hats,
cymbals, risers, textures). The Cymatics pack is left out on purpose (its licence doesn't allow
shipping the raw samples in an app).

  python3 tools/apply_kit_pack.py KitPack2.zip --package BreakBoss.swiftpm

Adds (or replaces) the manifest assignments of these kits only. All Archive 808s are tuned to C1;
each kit's 808 is resampled to that kit's root (bassHz) so pad 7 and chromatic MIDI play in tune.
"""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prepare_stock_samples import Sources, decode, process, wav_bytes  # noqa: E402

C1, E1, F1, G1 = 32.70, 41.20, 43.65, 49.00
K, S, C, R, H, O, B, P1, P2, LT, HT, CY = range(12)

def ar(folder, name):          # the Archive's naming: "[Kind] Name - (@prod.by.iiinfinite).wav"
    tag = {"Kicks 2": "Kick", "Snares 2": "Snare", "Claps 2": "Clap", "Rims 2": "Rim", "Snaps 2": "Snap",
           "Hi Hats 2": "Hi Hat", "Open Hats 2": "Open Hat", "808 2": "808", "Textures 2": "Texture"}.get(folder)
    return f"{folder}/[{tag}] {name} - (@prod.by.iiinfinite).wav" if tag else f"{folder}/{name} - (@prod.by.iiinfinite).wav"
def kk(name): return f"Kicks 2.zip.zip/{name}.wav"
def sc(name): return f"Snares + Claps 2/{name}.wav"
def pc(name): return f"Percussive One Shots 2/{name}.wav"

HAT = {"tailSeconds": 0.4}
OPEN = {"tailSeconds": 1.2}
CYM = {"tailSeconds": 3.0, "decaySeconds": 1.4, "peak": 0.8}
LONG = {"tailSeconds": 3.0, "decaySeconds": 1.2, "peak": 0.8}
def b808(target, tail=2.6): return {"sourceRootHz": C1, "targetRootHz": target, "tailSeconds": tail}

KITS = {
    # Detroit: punchy kick, dry Flint snare, Kenzo clap, Flint rim, tight hats, bouncy open hat, long 808
    "detroit": (E1, {K: kk("KNOCKGANG Kick (1)"), S: ar("Snares 2", "Flint"), C: ar("Claps 2", "Kenzo"), R: ar("Rims 2", "Flint"),
                     H: (ar("Hi Hats 2", "Flicker"), HAT), O: (ar("Open Hats 2", "Bounce"), OPEN), B: (ar("808 2", "Grounded"), b808(E1)),
                     P1: ar("Snaps 2", "Action"), P2: ar("Rims 2", "Deals"), LT: pc("Reverse Kick Madness (1)"),
                     HT: pc("Beads Hit"), CY: (ar("Cymbals & Crashes 2", "[Crash] Planes"), CYM)}),
    "knock-gang": (F1, {K: kk("Game Time Kick"), S: sc("Pure Knock Snare (1)"), C: sc("Issa Bounce Clap Snare"), R: ar("Rims 2", "Hunger"),
                        H: (ar("Hi Hats 2", "Based"), HAT), O: (ar("Open Hats 2", "Groove"), OPEN), B: (ar("808 2", "Made"), b808(F1)),
                        P1: ar("Snaps 2", "Encore"), P2: ar("Rims 2", "Tech"), LT: pc("Earthquake"),
                        HT: pc("Clickety Engine"), CY: (ar("Cymbals & Crashes 2", "[Cymbal] Classics"), CYM)}),
    "rage": (E1, {K: ar("Kicks 2", "Clipped"), S: ar("Snares 2", "Rage"), C: ar("Claps 2", "Tank"), R: ar("Rims 2", "Metals"),
                  H: (ar("Hi Hats 2", "Radiant"), HAT), O: (ar("Open Hats 2", "Distort"), OPEN), B: (ar("808 2", "Sukuna"), b808(E1)),
                  P1: ar("Snaps 2", "Ultimate"), P2: ar("Rims 2", "Ninja"), LT: ar("Kicks 2", "Nether"),
                  HT: pc("Whoopish Layer"), CY: (ar("Cymbals & Crashes 2", "[Crash] Marching"), CYM)}),
    "drill-nights": (F1, {K: ar("Kicks 2", "Brick"), S: ar("Snares 2", "K9"), C: ar("Claps 2", "Goto"), R: ar("Rims 2", "Pressing"),
                          H: (ar("Hi Hats 2", "Mirage"), HAT), O: (ar("Open Hats 2", "Kunai"), OPEN), B: (ar("808 2", "Toji"), b808(F1)),
                          P1: ar("Snaps 2", "Hellsing"), P2: ar("Rims 2", "Rooms"), LT: ar("Kicks 2", "Softer"),
                          HT: pc("Tamb Cha Ching (1)"), CY: (ar("Cymbals & Crashes 2", "[Cymbal] News"), CYM)}),
    # Vintage: the analog / funk / lo-fi kicks and warm snares
    "analog-funk": (E1, {K: kk("Str8 Up Analog Kick"), S: sc("Funk Snare (1)"), C: sc("Dramatic Clap Snare"), R: sc("Quick Knock Snare"),
                         H: (ar("Hi Hats 2", "Velvet"), HAT), O: (ar("Open Hats 2", "Body"), OPEN), B: (ar("808 2", "Hands"), b808(E1, 2.0)),
                         P1: pc("Tambourine Double Hit"), P2: pc("Small Tambourine Double Hit 2 (1)"), LT: kk("Tube Kick"),
                         HT: kk("LoFi 1 Kick (1)"), CY: (ar("Cymbals & Crashes 2", "[Cymbal] Organic"), CYM)}),
    # Texture: risers, textures, found sounds
    "sky-textures": (G1, {K: kk("Reason Analog Kick (1)"), S: sc("LoFi Warm Snare (1)"), C: sc("Rift Clap Snare"), R: ar("Rims 2", "Casper"),
                          H: (ar("Hi Hats 2", "Twilight"), HAT), O: (ar("Open Hats 2", "White Noise"), OPEN), B: (ar("808 2", "Jogo"), b808(G1)),
                          P1: pc("Oyster Layer"), P2: pc("Groaning Wild Animal (1)"), LT: (ar("Textures 2", "Cold Winter"), LONG),
                          HT: (ar("Risers 2", "[Triangle Riser] Ghosts"), LONG), CY: (ar("Textures 2", "Bird Ambience"), LONG)}),
}
ROLE = ["KICK", "SNARE", "CLAP", "RIM", "HAT", "OPEN HAT", "808", "PERC A", "PERC B", "LOW TOM", "HIGH TOM", "CYMBAL"]
DEFAULTS = {"startSeconds": 0.0, "tuneSemitones": 0.0, "tailSeconds": 3.5, "decaySeconds": None,
            "lowpassHz": None, "drive": 0.0, "peak": 0.92}

def pretty(path):
    stem = Path(path).stem
    stem = re.sub(r"\s*-\s*\(@prod\.by\.?iiinfinite\)", "", stem)
    stem = re.sub(r"^\[[^\]]+\]\s*", "", stem).replace(" (1)", "")
    return stem.upper()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pack", type=Path)
    ap.add_argument("--package", type=Path, required=True)
    a = ap.parse_args()
    folder = a.package / "Resources" / "StockSamples"
    mpath = folder / "manifest.json"
    manifest = json.loads(mpath.read_text())
    manifest["assignments"] = [x for x in manifest["assignments"] if x["kitID"] not in KITS]
    src = Sources(a.pack)
    cache = {}
    for kit, (root, pads) in KITS.items():
        assert len(pads) == 12, kit
        for pad in range(12):
            entry = pads[pad]
            path, extra = (entry if isinstance(entry, tuple) else (entry, {}))
            if path not in src.entries:
                raise SystemExit(f"missing in pack: {path}")
            params = dict(DEFAULTS, **extra)
            slug = re.sub(r"[^a-z0-9]+", "-", pretty(path).lower()).strip("-")
            tag = hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:6]
            name = f"bb_kp2-{slug}-{tag}_p{pad:02d}.wav"
            if not (folder / name).exists():
                if path not in cache:
                    cache[path] = decode(src.read(path), path)[0]
                (folder / name).write_bytes(wav_bytes(process(cache[path], params)))
            manifest["assignments"].append({"kitID": kit, "pad": pad, "file": name, "displayName": pretty(path)})
    mpath.write_text(json.dumps(manifest, indent=2) + "\n")
    used = {x["file"] for x in manifest["assignments"]}
    for f in folder.glob("bb_*.wav"):
        if f.name not in used: f.unlink()
    print(len(manifest["assignments"]), "assignments,", len(used), "WAVs")

if __name__ == "__main__":
    main()
