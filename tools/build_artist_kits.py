#!/usr/bin/env python3
"""Artist-style kits (Oct 14): two kits for each of Tyrone's artist styles, built mostly from his two new
packs (renamed by Tyrone's OK: "Danger Demon" and "Danger OG Trap"), with his earlier packs for the soul
styles. Voice tags, chants, vocal shots and sounds named after other people's records are left out.

  python3 tools/build_artist_kits.py <folder with all packs> --package BreakBoss.swiftpm [--swift out.swift]

Style names describe the sound, not the artist (App Store rule on using real people's names):
  TORONTO NIGHTS (Drake) · LATE NIGHT RNB (PARTYNEXTDOOR) · ATL WAVE (Future) · ROCKSTAR BOUNCE (Lil Uzi Vert)
  VAMP RAGE (Playboi Carti) · CAROLINA SOUL (J. Cole) · LA LYRICIST (Kendrick Lamar) · SOFT SOUL (SZA)
  HOUSTON QUEEN (Beyonce)
Every 808 is measured (all ~C1 except two) and resampled to its kit's root so it plays in key.
"""
from __future__ import annotations
import argparse, hashlib, json, random, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prepare_stock_samples import Sources, decode, process, wav_bytes  # noqa: E402
from build_genre_kits import classify, ROOTS, DEFAULTS, BASE_EXTRA, ROLE_OF_PAD, slug  # noqa: E402

C1 = 32.70
ODD_ROOTS = {"Danger OG Trap/808/5_2.wav": 27.50, "Danger OG Trap/808/808 (10)_2.wav": 41.20}

def new_pools(entries):
    """Tyrone's two new packs by pad role."""
    P = {k: [] for k in ("kick", "snare", "clap", "rim", "hat", "open", "808", "perc", "cym", "tom")}
    for path in sorted(entries):
        if not (path.startswith("Danger Demon/") or path.startswith("Danger OG Trap/")): continue
        folder = path.split("/")[1]; low = path.lower()
        role = {"Kicks": "kick", "Snares": "snare", "Claps": "clap", "HH": "hat", "OHH": "open", "808": "808", "Percs": "perc"}[folder]
        if folder == "Percs":
            if "rim" in low: role = "rim"
            elif "toms" in low: role = "tom"
            elif "cymbal" in low: role = "cym"
            elif "hhs" in low: role = "hat"
        P[role].append(path)
    return P

#  name, groove, base kit (root), tempo, where each role comes from ("new" | "soul" | "mix"), processing
STYLES = [
    ("TORONTO NIGHTS", "trapToronto", "heavyBreak", 136, "new", {"hat": {"lowpassHz": 9000}, "open": {"lowpassHz": 9000},
                                                                  "snare": {"tuneSemitones": -1}, "808": {"tailSeconds": 3.0}}),
    ("LATE NIGHT RNB", "trapSoul", "neoSoul", 74, "new", {"hat": {"lowpassHz": 10000}, "snare": {"tuneSemitones": -2, "lowpassHz": 11000},
                                                           "clap": {"tuneSemitones": -1}, "808": {"tailSeconds": 3.0}}),
    ("ATL WAVE", "trapAtlanta", "modernTrap", 145, "new", {"kick": {"drive": 0.08}, "808": {"tailSeconds": 2.8}}),
    ("ROCKSTAR BOUNCE", "trapAtlanta", "westBounce", 155, "new", {"snare": {"tuneSemitones": 1}, "808": {"tailSeconds": 1.8}}),
    ("VAMP RAGE", "trapAtlanta", "modernTrap", 152, "new", {"kick": {"drive": 0.2}, "808": {"drive": 0.25, "tailSeconds": 1.6},
                                                             "snare": {"drive": 0.1}, "open": {"lowpassHz": 12000}}),
    ("CAROLINA SOUL", "boomBap", "funkBreak", 90, "soul", {"kick": {"drive": 0.12}, "snare": {"drive": 0.08}, "hat": {"lowpassHz": 9000}}),
    ("LA LYRICIST", "westBounce", "westBounce", 94, "mix", {"hat": {"lowpassHz": 11000}, "snare": {"drive": 0.06}}),
    ("SOFT SOUL", "neoSoul", "neoSoul", 82, "soul", {"hat": {"lowpassHz": 9500}, "snare": {"lowpassHz": 10000}, "kick": {"lowpassHz": 7000},
                                                      "808": {"tailSeconds": 2.4}}),
    ("HOUSTON QUEEN", "rnb", "gospelChops", 100, "mix", {"clap": {"tuneSemitones": 1}, "808": {"tailSeconds": 2.0}}),
]

def pretty(path):
    stem = Path(path).stem
    stem = re.sub(r"_?\[tunedtoC\]", "", stem)
    stem = re.sub(r"(?i)_(akachiglo|zaytiggy|zay|trapboyz)", "", stem).replace("_noweirdtone", " clean")
    stem = re.sub(r"\s+", " ", stem.replace("_", " ").replace(" (1)", "")).strip()
    tag = "DEMON " if path.startswith("Danger Demon/") else "OG " if path.startswith("Danger OG Trap/") else ""
    return (tag + stem).upper()

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
    old = classify(src.entries)          # Tyrone's earlier packs (vintage / modern families)
    new = new_pools(src.entries)
    ids = {f"s-{slug(s[0])}-{x}" for s in STYLES for x in "ab"}
    manifest["assignments"] = [x for x in manifest["assignments"] if x["kitID"] not in ids]
    cache, swift = {}, []
    for si, (name, groove, base, tempo, fam, proc) in enumerate(STYLES):
        root = ROOTS[base]
        rng = random.Random(f"breakboss-style-{name}")
        used = set()
        for ki, suffix in enumerate("ab"):
            kit = f"s-{slug(name)}-{suffix}"
            for pad, role in enumerate(ROLE_OF_PAD):
                if fam == "new":
                    pool = new[role] or old[role]["modern"]
                elif fam == "soul":      # acoustic tops from the Vintage pack, his new kicks and 808s underneath
                    if role == "808": pool = new["808"]
                    elif role == "kick": pool = old["kick"]["vintage"] + new["kick"][:4]
                    else: pool = old[role]["vintage"]
                else:                    # mix: new pack and the vintage pack side by side
                    pool = new[role] + old[role]["vintage"] if role != "808" else new["808"]
                pool = pool or old[role]["modern"] or old[role]["vintage"]
                fresh = [p for p in pool if p not in used] or pool
                path = rng.choice(fresh); used.add(path)
                params = {**DEFAULTS, **BASE_EXTRA.get(role, {}), **proc.get(role, {})}
                if role == "808":
                    params["sourceRootHz"] = ODD_ROOTS.get(path, C1) if path.startswith("Danger") else C1
                    params["targetRootHz"] = root
                tag = hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:6]
                fname = f"bb_s-{slug(pretty(path))[:40]}-{tag}_p00.wav"
                if not (folder / fname).exists():
                    if path not in cache:
                        cache[path] = decode(src.read(path), path)[0]
                    (folder / fname).write_bytes(wav_bytes(process(cache[path], params)))
                manifest["assignments"].append({"kitID": kit, "pad": pad, "file": fname, "displayName": pretty(path)})
            title = f"{name} {'A' if suffix == 'a' else 'B'}"
            swift.append(f'        variant("{kit}", "{title}", {base}, .{groove}, {tempo}, {501 + si * 2 + ki}, 0, 0.1),')
    mpath.write_text(json.dumps(manifest, indent=2) + "\n")
    used_files = {x["file"] for x in manifest["assignments"]}
    for f in folder.glob("bb_*.wav"):
        if f.name not in used_files: f.unlink()
    print(len(manifest["assignments"]), "assignments,", len(used_files), "WAVs")
    if a.swift: a.swift.write_text("\n".join(swift) + "\n")

if __name__ == "__main__":
    main()
