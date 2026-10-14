#!/usr/bin/env python3
"""Genre kits (Oct 14): two kits for every preset style, built from all of Tyrone's packs
(Vintage pack, Kicks 3, Snares + Claps 2, Percussive One Shots 2, the Archive, Danger Drums).

  python3 tools/build_genre_kits.py KitPack2.zip --package BreakBoss.swiftpm [--swift out.swift]

Each genre draws from the pools that suit it (acoustic/vintage, modern trap, electronic) and gets
its own processing (drive for boom bap, softer tops for jazz, tight kicks for house/techno, a short
tuned 808 "log drum" for amapiano...). Kit A and kit B of a genre use different sounds (seeded
picks, so reruns give the same kits). Files are shared between kits and pads when the source and
processing are identical. All Archive 808s are tuned to C1 and resampled to each kit's root.
"""
from __future__ import annotations
import argparse, hashlib, json, random, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prepare_stock_samples import Sources, decode, process, wav_bytes  # noqa: E402

C1 = 32.70
ROOTS = {"drumMastery": 43.65, "modernTrap": 41.20, "westBounce": 49.00, "baySlap": 46.25, "west90s": 55.00,
         "neoSoul": 36.71, "gospelChops": 43.65, "funkBreak": 41.20, "looseBreak": 49.00, "heavyBreak": 36.71}

def classify(entries):
    """Sound pools by pad role and family, from folder and file names."""
    P = {k: {"vintage": [], "modern": [], "electronic": []} for k in
         ("kick", "snare", "clap", "rim", "hat", "open", "808", "perc", "cym", "tom")}
    def add(role, fams, path):
        for f in fams: P[role][f].append(path)
    for path in sorted(entries):
        folder, name = path.rsplit("/", 1) if "/" in path else ("", path)
        low = name.lower()
        if folder == "Vintage/kicks": add("kick", ["vintage"], path)
        elif folder == "Vintage/snares":
            if "rimshot" in low: add("rim", ["vintage"], path)
            elif "clap" in low and "snare" not in low: add("clap", ["vintage"], path)
            else: add("snare", ["vintage"], path)
        elif folder == "Vintage/hats":
            if "ride" in low: add("cym", ["vintage"], path)
            elif "shaker" in low or "rev" in low: add("perc", ["vintage"], path)
            elif "open" in low: add("open", ["vintage"], path)
            else: add("hat", ["vintage"], path)
        elif folder == "Kicks 2.zip.zip": add("kick", ["vintage", "modern"], path)
        elif folder == "Snares + Claps 2":
            add("clap" if "clap" in low else "snare", ["vintage", "modern"], path)
        elif folder == "Percussive One Shots 2":
            add("perc", ["vintage", "electronic"], path)
            if any(w in low for w in ("beads", "clickety", "earthquake", "reverse kick")): add("tom", ["vintage", "modern", "electronic"], path)
        elif folder == "Danger Drums":
            role = ("open" if low.startswith("open hat") else "hat" if low.startswith("hihat") else "kick" if low.startswith("kick")
                    else "snare" if low.startswith("snare") else "clap" if low.startswith("clap") else "rim" if low.startswith("rim") else "perc")
            add(role, ["vintage", "modern", "electronic"], path)
            if "tom" in low or "blocked" in low or "light" in low: add("tom", ["vintage", "modern", "electronic"], path)
        else:
            role = {"Kicks 2": "kick", "Snares 2": "snare", "Claps 2": "clap", "Rims 2": "rim", "Snaps 2": "perc",
                    "Hi Hats 2": "hat", "Open Hats 2": "open", "808 2": "808", "Cymbals & Crashes 2": "cym"}.get(folder)
            if role: add(role, ["modern", "electronic"], path)
            if folder == "Snaps 2": add("clap", ["modern", "electronic"], path)
    return P

# genre: (style key, base kit, family, tempo, processing per role)
HAT_T = {"tailSeconds": 0.4}
GENRES = [
    ("Trap", "trapAtlanta", "drumMastery", "modern", 140, {}),
    ("Dark Trap", "trapToronto", "heavyBreak", "modern", 135, {"kick": {"tuneSemitones": -1}, "snare": {"tuneSemitones": -2}, "hat": {"lowpassHz": 9000}}),
    ("Drill", "trapMemphis", "modernTrap", "modern", 142, {"snare": {"tuneSemitones": 1}}),
    ("Detroit", "trapAtlanta", "modernTrap", "modern", 160, {"kick": {"drive": 0.1}}),
    ("West Coast", "westBounce", "westBounce", "modern", 98, {"clap": {"tuneSemitones": -1}}),
    ("RnB", "trapSoul", "drumMastery", "modern", 118, {"hat": {"lowpassHz": 11000}, "snare": {"tuneSemitones": -1}}),
    ("90s RnB", "pop90s", "west90s", "vintage", 96, {"kick": {"drive": 0.05}}),
    ("80s RnB", "pop80s", "gospelChops", "vintage", 104, {"snare": {"tuneSemitones": -1}}),
    ("80s Pop", "pop80s", "funkBreak", "vintage", 116, {}),
    ("80s Funk", "funkBreak", "funkBreak", "vintage", 104, {"kick": {"drive": 0.08}}),
    ("Boom Bap", "boomBap", "heavyBreak", "vintage", 90, {"kick": {"drive": 0.15}, "snare": {"drive": 0.12}, "hat": {"lowpassHz": 10000}}),
    ("Jazz", "looseBreak", "looseBreak", "vintage", 120, {"kick": {"lowpassHz": 5000}, "snare": {"lowpassHz": 9000},
                                                         "hat": {"lowpassHz": 8000}, "cym": {"lowpassHz": 9000}}),
    ("Neo Soul", "neoSoul", "neoSoul", "vintage", 86, {"hat": {"lowpassHz": 10000}, "snare": {"lowpassHz": 11000}}),
    ("Soul RnB", "gospel", "gospelChops", "vintage", 94, {}),
    ("Amapiano", "amapiano", "baySlap", "electronic", 112, {"808": {"tailSeconds": 0.55}}),
    ("South African RnB", "amapiano", "looseBreak", "electronic", 110, {"808": {"tailSeconds": 0.7}, "hat": {"lowpassHz": 11000}}),
    ("EDM", "experimental", "drumMastery", "electronic", 128, {"kick": {"drive": 0.12}, "808": {"tailSeconds": 0.9}}),
    ("House", "afrobeats", "funkBreak", "electronic", 124, {"kick": {"tailSeconds": 0.45}, "808": {"tailSeconds": 0.6}}),
    ("Techno", "experimental", "heavyBreak", "electronic", 130, {"kick": {"tailSeconds": 0.5, "drive": 0.15}, "808": {"tailSeconds": 0.5}}),
]
ROLE_OF_PAD = ["kick", "snare", "clap", "rim", "hat", "open", "808", "perc", "perc", "tom", "tom", "cym"]
DEFAULTS = {"startSeconds": 0.0, "tuneSemitones": 0.0, "tailSeconds": 3.5, "decaySeconds": None,
            "lowpassHz": None, "drive": 0.0, "peak": 0.92}
BASE_EXTRA = {"hat": HAT_T, "open": {"tailSeconds": 1.2}, "cym": {"tailSeconds": 3.0, "decaySeconds": 1.4, "peak": 0.8},
              "808": {"tailSeconds": 2.6}, "tom": {"tailSeconds": 1.2}}

def slug(s): return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")

def pretty(path):
    stem = Path(path).stem
    stem = re.sub(r"\s*-\s*\(?@prod\.by\.?iiinfinite\)?", "", stem)
    stem = re.sub(r"^\[[^\]]+\]\s*", "", stem).replace(" (1)", "").replace("RImshot", "Rimshot")
    return stem.upper()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pack", type=Path)
    ap.add_argument("--package", type=Path, required=True)
    ap.add_argument("--swift", type=Path)
    a = ap.parse_args()
    folder = a.package / "Resources" / "StockSamples"
    mpath = folder / "manifest.json"
    manifest = json.loads(mpath.read_text())
    src = Sources(a.pack)
    pools = classify(src.entries)
    ids = {f"g-{slug(g[0])}-{s}" for g in GENRES for s in "ab"}
    manifest["assignments"] = [x for x in manifest["assignments"] if x["kitID"] not in ids]
    cache, swift = {}, []
    for gi, (genre, style, base, fam, tempo, proc) in enumerate(GENRES):
        root = ROOTS[base]
        rng = random.Random(f"breakboss-genre-{genre}")
        used_by_genre = set()
        for ki, suffix in enumerate("ab"):
            kit = f"g-{slug(genre)}-{suffix}"
            for pad, role in enumerate(ROLE_OF_PAD):
                pool = pools[role][fam] or pools[role]["modern"] or pools[role]["vintage"]
                fresh = [p for p in pool if p not in used_by_genre] or pool
                # perc A / perc B: different sounds
                path = rng.choice(fresh)
                used_by_genre.add(path)
                params = {**DEFAULTS, **BASE_EXTRA.get(role, {}), **proc.get(role, {})}
                if role == "808":
                    params["sourceRootHz"], params["targetRootHz"] = C1, root
                tag = hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:6]
                name = f"bb_g-{slug(pretty(path))[:40]}-{tag}_p00.wav"
                if not (folder / name).exists():
                    if path not in cache:
                        cache[path] = decode(src.read(path), path)[0]
                    (folder / name).write_bytes(wav_bytes(process(cache[path], params)))
                manifest["assignments"].append({"kitID": kit, "pad": pad, "file": name, "displayName": pretty(path)})
            title = f"{genre.upper()} {'A' if suffix == 'a' else 'B'}"
            swift.append(f'        variant("{kit}", "{title}", {base}, .{style}, {tempo}, {401 + gi * 2 + ki}, 0, 0.1),')
    mpath.write_text(json.dumps(manifest, indent=2) + "\n")
    used = {x["file"] for x in manifest["assignments"]}
    for f in folder.glob("bb_*.wav"):
        if f.name not in used: f.unlink()
    print(len(manifest["assignments"]), "assignments,", len(used), "WAVs")
    if a.swift: a.swift.write_text("\n".join(swift) + "\n")

if __name__ == "__main__":
    main()
