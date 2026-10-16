#!/usr/bin/env python3
"""Put Tyrone's Vintage pack (kicks, snares/claps, hats) into the 16 Vintage kits.

  python3 tools/apply_vintage_pack.py VintagePack.zip --package BreakBoss.swiftpm

The pack holds kicks/, snares/ and hats/ (his three zips, duplicates removed). Only the
listed pads change: kick, snare, clap, rim, closed hat, open hat, perc A/B and cymbal. The
808 and toms keep their current audio. Uses prepare_stock_samples.py's decoder and processing
(trim, fades, optional low-pass/decay, peak) so the files match the rest of the stock bank.
"""
from __future__ import annotations
import argparse, hashlib, json, re, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from prepare_stock_samples import Sources, decode, process, wav_bytes  # noqa: E402

K, S, C, R, H, O, P1, P2, CY = 0, 1, 2, 3, 4, 5, 7, 8, 11
ROLE = {K: "KICK", S: "SNARE", C: "CLAP", R: "RIM", H: "HAT", O: "OPEN HAT", P1: "PERC A", P2: "PERC B", CY: "RIDE"}

def k(name): return "kicks/" + name + ".wav"
def s(name): return "snares/" + name + ".wav"
def h(name): return "hats/" + name + ".wav"

RIDE = {"tailSeconds": 3.0, "decaySeconds": 1.2, "peak": 0.8}
SHAKER = {"peak": 0.8}
CLOSED = {"tailSeconds": 0.35}            # the long closed hats are mostly silence

# kit: {pad: (source, params)}
KITS = {
    "boom-bap":    {K: (k("Alchemy Kick"), {}), S: (s("British Snare"), {}), C: (s("Engulfed Clap"), {}), R: (s("Pierce Snare"), {}),
                    H: (h("Throne Hihat"), {}), O: (h("Throne Open Hihat"), {}), P1: (h("Finesse Shaker"), SHAKER),
                    P2: (h("Tripped Rev Hihat"), {}), CY: (h("Compressed Ride"), RIDE)},
    "funk-break":  {K: (k("Timeless Kick"), {}), S: (s("Arriba Snare"), {}), C: (s("Sorcerer Clap"), {}), R: (s("Bell RImshot"), {}),
                    H: (h("Golden Hihat"), {}), O: (h("Tripped Open Hihat"), {}), P1: (h("Finesse Shaker 2"), SHAKER),
                    P2: (h("Clicked Rev Hihat"), {}), CY: (h("Trippy Ride"), RIDE)},
    "heavy-break": {K: (k("WAYY MORE THUMPIER Kick"), {}), S: (s("Cahones Snare 3"), {"drive": 0.1}), C: (s("Trap Clap Snare"), {}),
                    R: (s("ForShitsandGiggles Snare"), {}), H: (h("Tripped Hihat"), {}), O: (h("Clicked Open Hihat"), {}),
                    P1: (h("Pop Rev Hihat"), {}), P2: (h("Tripped Rev Hihat"), {}), CY: (h("Compressed Ride"), RIDE)},
    "loose-break": {K: (k("Beads Kick"), {}), S: (s("TrapKnock Snare"), {}), C: (s("Hush Clap"), {}), R: (s("Pierce Snare"), {}),
                    H: (h("Clicked Hihat"), {}), O: (h("Pop Open Hihat"), {}), P1: (h("Finesse Shaker"), SHAKER),
                    P2: (h("Clicked Rev Hihat"), {}), CY: (h("Trippy Ride"), RIDE)},
    "west-90s":    {K: (k("Cheat Code Kick"), {}), S: (s("TrapKnock Snare 2"), {}), C: (s("Sorcerer Clap"), {}), R: (s("Bell RImshot"), {}),
                    H: (h("Prism Hihat"), CLOSED), O: (h("Throne Open Hihat"), {}), P1: (h("Finesse Shaker 2"), SHAKER),
                    P2: (h("Pop Rev Hihat"), {}), CY: (h("Compressed Ride"), RIDE)},
    "west-end":    {K: (k("Fist to Face Kick"), {}), S: (s("Alchemy Snare"), {}), C: (s("Engulfed Clap"), {}), R: (s("Pierce Snare"), {}),
                    H: (h("Shifted Hihat"), CLOSED), O: (h("Tripped Open Hihat"), {}), P1: (h("Finesse Shaker"), SHAKER),
                    P2: (h("Tripped Rev Hihat"), {}), CY: (h("Compressed Ride"), RIDE)},
    "neo-soul":    {K: (k("Quiet Power Kick"), {}), S: (s("Depth Snare"), {}), C: (s("Spiri Clap Snare"), {}), R: (s("Bell RImshot"), {}),
                    H: (h("Lowpitch Hihat"), CLOSED), O: (h("Smither Open Hihat"), {"tailSeconds": 1.5}), P1: (h("Finesse Shaker"), SHAKER),
                    P2: (h("Clicked Rev Hihat"), {}), CY: (h("Trippy Ride"), RIDE)},
    "cole-world":  {K: (k("Shaped Kick"), {}), S: (s("idk Snare 4"), {}), C: (s("Hush Clap"), {}), R: (s("ForShitsandGiggles Snare"), {}),
                    H: (h("Smither Hihat 2"), {}), O: (h("Pop Open Hihat"), {}), P1: (h("Finesse Shaker 2"), SHAKER),
                    P2: (h("Tripped Rev Hihat"), {}), CY: (h("Compressed Ride"), RIDE)},
    "vintage-rnb": {K: (k("Pop Kick"), {}), S: (s("WavEs Snare"), {}), C: (s("Soft Metal Clap"), {"tailSeconds": 1.4}), R: (s("Bell RImshot"), {}),
                    H: (h("Golden Hihat"), {}), O: (h("Throne Open Hihat"), {}), P1: (h("Finesse Shaker"), SHAKER),
                    P2: (h("Pop Rev Hihat"), {}), CY: (h("Trippy Ride"), RIDE)},
    "dirty-soul":  {K: (k("Heavyweight Kick"), {"lowpassHz": 6000}), S: (s("British Snare 2"), {}), C: (s("Sorcerer Clap"), {}),
                    R: (s("Pierce Snare"), {}), H: (h("Lowpitch Hihat"), CLOSED), O: (h("Smither Open Hihat"), {"tailSeconds": 1.5}),
                    P1: (h("Finesse Shaker 2"), SHAKER), P2: (h("Clicked Rev Hihat"), {}),
                    CY: (h("Compressed Ride"), dict(RIDE, lowpassHz=9000))},
    "live-soul":   {K: (k("Mega Kick 2"), {}), S: (s("Depth Snare"), {"tuneSemitones": -1}), C: (s("Spiri Clap Snare"), {}),
                    R: (s("Bell RImshot"), {}), H: (h("Throne Hihat"), {}), O: (h("Tripped Open Hihat"), {}), P1: (h("Finesse Shaker"), SHAKER),
                    P2: (h("Tripped Rev Hihat"), {}), CY: (h("Trippy Ride"), RIDE)},
    "gospel-chops":{K: (k("Whole Club Thump Kick"), {}), S: (s("Primary Snare w Verb"), {}), C: (s("Sorcerer Clap 3"), {"tailSeconds": 1.5}),
                    R: (s("Bell RImshot"), {}), H: (h("Clicked Hihat"), {}), O: (h("Clicked Open Hihat"), {}), P1: (h("Finesse Shaker 2"), SHAKER),
                    P2: (h("Pop Rev Hihat"), {}), CY: (h("Compressed Ride"), RIDE)},
    "80s-pop":     {K: (k("Fist to Face Kick"), {}), S: (s("Primary Snare w Verb"), {}), C: (s("Sorcerer Clap 3"), {"tailSeconds": 1.5}),
                    R: (s("ForShitsandGiggles Snare"), {}), H: (h("Shifted Hihat"), CLOSED), O: (h("Pop Open Hihat"), {}),
                    P1: (h("Finesse Shaker"), SHAKER), P2: (h("Clicked Rev Hihat"), {}), CY: (h("Compressed Ride"), RIDE)},
    "90s-pop":     {K: (k("Whole Club Thump Kick"), {}), S: (s("Fun Snare w Verb"), {}), C: (s("Engulfed Clap"), {}), R: (s("Pierce Snare"), {}),
                    H: (h("Prism Hihat"), CLOSED), O: (h("Throne Open Hihat"), {}), P1: (h("Finesse Shaker 2"), SHAKER),
                    P2: (h("Tripped Rev Hihat"), {}), CY: (h("Trippy Ride"), RIDE)},
    "live-pop":    {K: (k("Shaped Kick B"), {}), S: (s("British Snare"), {}), C: (s("Hush Clap"), {}), R: (s("Bell RImshot"), {}),
                    H: (h("Golden Hihat"), {}), O: (h("Tripped Open Hihat"), {}), P1: (h("Finesse Shaker"), SHAKER),
                    P2: (h("Pop Rev Hihat"), {}), CY: (h("Compressed Ride"), RIDE)},
    "lo-fi":       {K: (k("Heavyweight Kick"), {"lowpassHz": 4000, "drive": 0.1}), S: (s("Depth Snare"), {"lowpassHz": 5000}),
                    C: (s("Sorcerer Clap"), {"lowpassHz": 5000}), R: (s("ForShitsandGiggles Snare"), {"lowpassHz": 5000}),
                    H: (h("Lowpitch Hihat"), dict(CLOSED, lowpassHz=7000)), O: (h("Smither Open Hihat"), {"tailSeconds": 1.2, "lowpassHz": 6000}),
                    P1: (h("Finesse Shaker"), dict(SHAKER, lowpassHz=7000)), P2: (h("Clicked Rev Hihat"), {"lowpassHz": 7000}),
                    CY: (h("Trippy Ride"), dict(RIDE, lowpassHz=6000))},
}

DEFAULTS = {"startSeconds": 0.0, "tuneSemitones": 0.0, "tailSeconds": None, "decaySeconds": None,
            "lowpassHz": None, "drive": 0.0, "peak": 0.92}

def pretty(path: str) -> str:
    name = Path(path).stem.replace(" B", "").replace("RImshot", "Rimshot")
    return name.upper()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pack", type=Path)
    ap.add_argument("--package", type=Path, required=True)
    a = ap.parse_args()
    folder = a.package / "Resources" / "StockSamples"
    manifest_path = folder / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    src = Sources(a.pack)
    cache = {}
    by_key = {(x["kitID"], x["pad"]): x for x in manifest["assignments"]}
    changed = 0
    for kit, pads in KITS.items():
        for pad, (path, extra) in pads.items():
            if (kit, pad) not in by_key:
                raise SystemExit(f"{kit} pad {pad} isn't in the stock manifest")
            params = dict(DEFAULTS, **extra)
            # identical sound + processing = one shared file
            slug = re.sub(r"[^a-z0-9]+", "-", Path(path).stem.lower()).strip("-")
            tag = hashlib.sha1(json.dumps(params, sort_keys=True).encode()).hexdigest()[:6]
            name = f"bb_vtg-{slug}-{tag}_p{pad:02d}.wav"
            if not (folder / name).exists():
                if path not in cache:
                    cache[path] = decode(src.read(path), path)[0]
                (folder / name).write_bytes(wav_bytes(process(cache[path], params)))
            entry = by_key[(kit, pad)]
            entry["file"] = name
            entry["displayName"] = pretty(path)
            changed += 1
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    used = {x["file"] for x in manifest["assignments"]}
    removed = 0
    for f in folder.glob("bb_*.wav"):
        if f.name not in used:
            f.unlink(); removed += 1
    print(f"{changed} Vintage pads updated, {removed} unused WAVs removed, {len(used)} WAVs in the bank, "
          f"{len(manifest['assignments'])} assignments")

if __name__ == "__main__":
    main()
