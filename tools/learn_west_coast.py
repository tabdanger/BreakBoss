#!/usr/bin/env python3
"""Learns the West Coast presets and kits from Tyrone's West Coast drum loops (Oct 20).

    python3 -I tools/learn_west_coast.py LOOPS_DIR [...]          # -> tools/learned_westcoast.json

The loops are full mixes (no stems, no one-shots) and reference only: nothing from them ships. Each loop is
split like tools/learn_fills.py --loops (bands, nearest one-shot kind, 16th grid), the one-shots being the
whole stock library. The tempo is in the file name, as learn_fills reads it ("Name [92].wav"); a loop with a half-bar pickup
is trimmed to start on its downbeat before it is given here.

For the kits, each lane's main hits (half the lane's loudest and up) are measured the same way as every
stock sound (tools/match_loop_sounds.py: spectrum over the first 80 ms, how long it rings) and the stock
sounds of that kind are ranked by how close they are to the lane's middle (median) hit: "sounds" lists the
nearest twenty. tools/build_kits.py gives each West Coast kit the nearest ones its loop heard.

A loop with no low end (a tops loop: the low band's loudest hits under 5% of full scale) has no kick lane.
"""
import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import learn_fills as F, learn_from_loops as L  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
OUT = os.path.join(ROOT, "tools", "learned_westcoast.json")
KIND = {"k": "KICK", "s": "SNARE", "c": "CLAP", "r": "RIM", "h": "HAT", "o": "OPEN HAT", "cr": "CYMBAL"}
LANE = {v: k for k, v in KIND.items()}


def library():
    """(lane, features, name) of every stock one-shot the loops can be split against."""
    out = []
    for r in json.load(open(os.path.join(STOCK, "manifest.json")))["sounds"]:
        lane = LANE.get(r["type"])
        if not lane or r["file"].startswith("ac_"): continue
        x, sr = L.read_wav(os.path.join(STOCK, r["file"]))
        hs = L.onsets(x, sr)
        if not hs: continue
        h = max(hs, key=lambda h: h["peak"])
        out.append((lane, F.features(x, sr, int(h["t"] * sr), h["ring"]), r["name"]))
    return out


def learn(path, lib):
    temps = [(lane, f) for lane, f, _ in lib]
    p = F.learn_mix(path, temps)
    x, sr = L.read_wav(path)
    hits, _ = F.split(path, temps)
    lows = L.onsets(F.band(x, sr, 20, 150), sr)
    if not lows or float(np.percentile([h["peak"] for h in lows], 95)) < 0.05:
        p["lanes"].pop("k", None); hits.pop("k", None)
        p["tops"] = True
    p["sounds"] = {}
    for lane, hs in hits.items():
        if lane not in KIND: continue
        top = max(h["peak"] for h in hs)
        fs = [F.features(x, sr, int(h["t"] * sr), h["ring"]) for h in hs if h["peak"] >= 0.5 * top]
        target = np.median(np.array(fs), axis=0)
        ranked = sorted((float(np.sum((f - target) ** 2)), n) for l, f, n in lib if l == lane)
        p["sounds"][lane] = [n for _, n in ranked[:20]]
    return p


def main(argv):
    lib = library()
    done, seen = [], set()
    for d in argv[1:]:
        for f in sorted(os.listdir(d)):
            if not f.lower().endswith(".wav") or f.startswith((".", "._")) or f in seen: continue
            seen.add(f)
            p = learn(os.path.join(d, f), lib)
            done.append(p)
            print(f"{p['title']}  {p['bpm']:g} BPM  {p['bars']} bars  grid fit {p['gridFit']}{'  (tops, no kick)' if p.get('tops') else ''}")
            print("\n".join(f"  {k:>2} " + "|".join(v[i:i + 16] for i in range(0, len(v), 16)) for k, v in p["lanes"].items()))
            print("\n".join(f"     {k:>2} -> {', '.join(v[:3])}" for k, v in p["sounds"].items()))
    json.dump({"version": 1, "learned": done}, open(OUT, "w"), indent=1)
    print(len(done), "loops ->", OUT)


if __name__ == "__main__":
    main(sys.argv)
