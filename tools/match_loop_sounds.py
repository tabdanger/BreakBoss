#!/usr/bin/env python3
"""Picks, for each pad kind, the library sound that sounds most like the hits in a set of mixed loops (Oct 20).

    python3 -I tools/match_loop_sounds.py LOOPS_DIR --oneshots DIR [...] [--bk]   # --bk: only Tyrone's BK sounds

Every hit tools/learn_fills.py finds in the loops is measured the same way as every stock sound (spectrum over
the first 80 ms, how long it rings); each lane's middle (median) sound is matched to the nearest stock sound of
that kind. Prints the names to put in a kit_catalog.BK_KITS entry. Only stock sounds are picked: nothing from
the loops is kept.
"""
import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import learn_fills as F, learn_from_loops as L  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
KIND = {"k": "KICK", "s": "SNARE", "c": "CLAP", "r": "RIM", "h": "HAT", "o": "OPEN HAT"}


def main(argv):
    args, shots = argv[1:], []
    bk = "--bk" in args
    if bk: args.remove("--bk")
    while "--oneshots" in args:
        k = args.index("--oneshots"); shots.append(args[k + 1]); del args[k:k + 2]
    temps = F.templates(shots)
    feats = {}
    for f in sorted(os.listdir(args[0])):
        if not f.lower().endswith(".wav"): continue
        x, sr = L.read_wav(os.path.join(args[0], f))
        lanes, _ = F.split(os.path.join(args[0], f), temps)
        for lane, hs in lanes.items():
            for h in hs:
                if h["peak"] < 0.5 * max(g["peak"] for g in hs): continue     # the lane's main hits, not its ghosts
                feats.setdefault(lane, []).append(F.features(x, sr, int(h["t"] * sr), h["ring"]))
    rows = json.load(open(os.path.join(STOCK, "manifest.json")))["sounds"]
    if bk:   # the one-shot packs that came with the loops first; the Drum Kit's sounds only for kinds they lack
        packs = {r["file"] for r in json.load(open(os.path.join(ROOT, "tools", "bk_sounds.json"))) if "/" in r["source"]}
        kinds = {r["type"] for r in rows if r["file"] in packs}
        rows = [r for r in rows if r["file"] in packs or r["type"] not in kinds]
    picks = {}
    for lane, fs in feats.items():
        if lane not in KIND: continue
        target = np.median(np.array(fs), axis=0)
        best = None
        for r in rows:
            if r["type"] != KIND[lane] or r["file"].startswith("bk_") != bk or r["file"].startswith("ac_"): continue
            x, sr = L.read_wav(os.path.join(STOCK, r["file"]))
            hs = L.onsets(x, sr)
            if not hs: continue
            h = max(hs, key=lambda h: h["peak"])
            d = float(np.sum((F.features(x, sr, int(h["t"] * sr), h["ring"]) - target) ** 2))
            if best is None or d < best[0]: best = (d, r["name"])
        picks[lane] = best
        print(f"{lane:>2} {KIND[lane]:<9} {len(fs):4d} hits -> {best[1]}  (distance {best[0]:.2f})")


if __name__ == "__main__":
    main(sys.argv)
