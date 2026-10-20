#!/usr/bin/env python3
"""Learns drum parts from MIXED loops (no stems), such as drum fills (Oct 20).

    python3 -I tools/learn_fills.py FILLS_DIR --oneshots DIR [--oneshots DIR ...]            # -> tools/learned_fills.json
    python3 -I tools/learn_fills.py --loops LOOPS_DIR [DIR ...] --oneshots DIR [...]          # -> tools/learned_mixed.json
    python3 -I tools/learn_fills.py --check STEMS_DIR LOOPS_DIR --oneshots DIR   # score it against loops that have stems

Like tools/learn_from_loops.py, the audio is reference only: nothing from it ships. The tempo is the number
in the file name ("Aloe [82].wav" or "... - 82 BPM.wav"); a name without one is measured (measure_tempo).

How a mixed loop is split:
  bands   the loop is split by FFT into low (< 150 Hz), mid (200 Hz - 4 kHz) and high (> 6 kHz); each band
          gets its own hits (the same onset test as the stems), so a kick and a hat on the same step are
          both heard.
  sound   each hit is matched to the nearest one-shot (one-shot packs, named by kind: "(kick) x.wav",
          "Kick (Name).wav", or a KICK folder) by its spectrum over the first 80 ms and how long it rings,
          among the kinds that live in that band: low = kick, mid = snare, clap, rim, high = hat, open hat
          (toms, percs and shakers too when the loop's name says so). A mid hit that is a kick's click, or a high hit that is a
          snare's noise, is dropped.
  grid    as the stems: nearest 16th, rolls, levels per lane.
A fill shorter than a bar sits at the end of its bar (a half-bar fill fills steps 9-16).
"""
import json, os, re, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import learn_from_loops as L  # noqa: E402

BANDS = [20, 60, 120, 250, 500, 1000, 2000, 4000, 8000, 14000, 22000]
ONE_SHOT_KINDS = [  # words in a one-shot's name or folder -> lane
    (r"open", "o"), (r"roll", "h"), (r"hi ?hat|\bhats?\b|\bhh\b", "h"), (r"shaker|shake|tamb", "p1"),
    (r"kick|bass drum|\bbd\b", "k"), (r"clap", "c"), (r"rim|snap|stick", "r"), (r"snare", "s"),
    (r"low tom|floor", "lt"), (r"tom", "ht"), (r"cymbal|crash|ride", "cr"), (r"perc", "p2"),
]
IN_BAND = {"low": {"k"}, "mid": {"s", "c", "r"}, "high": {"h", "o"}}
# a band's hit must reach this share of the band's loud hits (bleed from the other drums sits lower)
FLOOR = {"low": 0.3, "mid": 0.35, "high": 0.12}
# a loop whose name says toms or percs can also have them
NAMED = [(r"(?i)\btoms?\b", {"low": {"lt"}, "mid": {"lt", "ht"}}), (r"(?i)perc|shaker|conga|bongo", {"mid": {"p2"}, "high": {"p1"}})]


def band(x, sr, lo, hi):
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    spec[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(spec, len(x)).astype(np.float32)


def features(x, sr, start, ring):
    clip = x[start:start + int(sr * 0.08)]
    if len(clip) < 256: clip = np.pad(clip, (0, 256 - len(clip)))
    spec = np.abs(np.fft.rfft(clip * np.hanning(len(clip)))) ** 2
    f = np.fft.rfftfreq(len(clip), 1 / sr)
    e = np.array([spec[(f >= a) & (f < b)].sum() for a, b in zip(BANDS, BANDS[1:])]) + 1e-12
    e = np.log10(e / e.sum())
    return np.concatenate([e, [2 * np.log10(max(ring, 0.005))]])


def kind_of(path):
    s = path.lower()
    for pat, lane in ONE_SHOT_KINDS:
        if re.search(pat, os.path.basename(s)): return lane
    for pat, lane in ONE_SHOT_KINDS:
        if re.search(pat, s): return lane
    return None


def templates(dirs):
    out = []
    for d in dirs:
        for root, _, files in os.walk(d):
            for f in files:
                if not f.lower().endswith(".wav") or f.startswith("._"): continue
                p = os.path.join(root, f)
                lane = kind_of(p)
                if not lane or re.search(r"(?i)revers", f): continue
                x, sr = L.read_wav(p)
                hits = L.onsets(x, sr)
                if not hits: continue
                h = max(hits, key=lambda h: h["peak"])
                out.append((lane, features(x, sr, int(h["t"] * sr), h["ring"])))
    return out


def classify(feat, temps, allowed):
    best = sorted(((float(np.sum((feat - t) ** 2)), lane) for lane, t in temps if lane in allowed))[:3]
    if not best: return None
    votes = {}
    for d, lane in best: votes[lane] = votes.get(lane, 0) + 1 / (d + 1e-3)
    return max(votes, key=votes.get)


def split(path, temps):
    """{lane: [hits]} for a mixed loop."""
    x, sr = L.read_wav(path)
    allowed = {b: set(v) for b, v in IN_BAND.items()}
    for pat, more in NAMED:
        if re.search(pat, os.path.basename(path)):
            for b, v in more.items(): allowed[b] |= v
    parts = {"low": band(x, sr, 20, 150), "mid": band(x, sr, 200, 4000), "high": band(x, sr, 6000, 20000)}
    found = {}
    top = float(np.abs(x).max()) + 1e-9
    for name, sig in parts.items():
        # a loop with no kick (a tops loop) still has a little low end; a kick reaches a quarter of the loop's peak
        if name == "low" and float(np.abs(sig).max()) < 0.25 * top: continue
        hs = L.onsets(sig, sr)
        if not hs: continue
        loud = float(np.percentile([h["peak"] for h in hs], 95))
        for h in hs:
            if h["peak"] < FLOOR[name] * loud: continue    # in a mix a band also hears the other drums, softer
            start = int(h["t"] * sr)
            lane = classify(features(x, sr, start, h["ring"]), temps, allowed[name])
            if lane: found.setdefault(name, []).append((h["t"], lane, h))
    low_t = [t for t, _, _ in found.get("low", [])]
    mid = found.get("mid", [])
    near = lambda t, ts: any(abs(t - u) < 0.015 for u in ts)
    # a kick's click in the mid band, a snare's noise in the high band
    # (on a kick, the mid hit stays only if it sounds more like a snare, clap or rim than like the kick)
    def kick_body(t, h):
        f = features(x, sr, int(t * sr), h["ring"])
        return classify(f, temps, allowed["mid"] | {"k"}) == "k"
    mid = [m for m in mid if not (near(m[0], low_t) and kick_body(m[0], m[2]))]
    snare_t = [t for t, lane, _ in mid if lane in ("s", "c")]
    high = [m for m in found.get("high", []) if not near(m[0], snare_t)]
    lanes = {}
    for t, lane, h in found.get("low", []) + mid + high:
        lanes.setdefault(lane, []).append(h)
    return lanes, len(x) / sr


def measure_tempo(length, times):
    """A loop with no tempo in its name: the tempo (60-180) at which it is 1, 2, 4, 8 or 16 whole bars and its hits
    sit on the 16ths. Half a tempo puts 16ths on 32nds, so the slowest tempo that fits about as well as the best wins,
    from 80 BPM up when one fits: a 65 BPM reading of a 130 BPM half-time loop sounds the same, but its hat rolls
    fall between the 16ths (the Oct 20 Drum Loops are FL exports at 120-150)."""
    cands = [240 * n / length for n in (1, 2, 4, 8, 16) if 60 <= 240 * n / length <= 180]
    if not cands: return 120.0
    err = {c: L.grid_error(times, c) * 15 / c for c in cands}    # in seconds: a 16th at 140 is half one at 70
    best = min(err.values())
    fits = [c for c in cands if err[c] <= best + 0.004]
    return round(min([c for c in fits if c >= 80] or fits), 1)


def learn_mix(path, temps, fill=False):
    name = re.sub(r"(?i)(\.wav)+$", "", os.path.basename(path))
    m = re.search(r"\[(\d+(?:\.\d+)?)\]", name) or re.search(r"(\d+(?:\.\d+)?)\s*BPM", name, re.I)
    hits, length = split(path, temps)
    bpm = float(m.group(1)) if m else measure_tempo(length, [h["t"] for hs in hits.values() for h in hs])
    bars_f = length * bpm / 240
    if fill:
        # a fill rings past its last hit: its length is the hits' span, rounded up to a quarter bar
        last = max((h["t"] for hs in hits.values() for h in hs), default=0)
        span = min(1.0, max(0.25, np.ceil((last * bpm / 240 + 1 / 16) * 4 - 0.15) / 4))
        steps, offset = 16, int(round(16 * (1 - span)))
    else:
        times = [h["t"] for hs in hits.values() for h in hs]
        named, bpm = bpm, L.check_tempo(bpm, length, times)
        if bpm != named: print(f"  {name}: the name says {named:g} BPM, the loop is {bpm:g} BPM")
        steps, offset = max(1, int(round(length * bpm / 240))) * 16, 0
    lanes, feel = {}, {}
    for lane, hs in hits.items():
        hs = [dict(h, t=h["t"] + offset * 60 / bpm / 4) for h in hs]
        s, offs = L.to_lane(hs, bpm, steps)
        if not fill: feel[lane] = L.feel(offs, steps)     # how far behind the grid the lane sits, its swing
        if lane == "k": s = s.replace("r", "x").replace("q", "x")   # in a mix, a kick "double" is its 808 or tail
        lanes[lane] = s
    if "c" in lanes and "s" not in lanes:      # a mix's lone backbeat sound plays on the snare
        lanes["s"] = lanes.pop("c")
        if "c" in feel: feel["s"] = feel.pop("c")
    lanes = {k: lanes[k] for k in L.LANE_ORDER if k in lanes}
    title = re.sub(r"\s*\[.*$", "", name).strip().upper()
    out = {"source": os.path.basename(path), "title": title, "bpm": bpm, "lanes": lanes}
    if fill: out["beats"] = round((16 - offset) / 4, 2)
    else:
        out["bars"] = steps // 16
        out["gridFit"] = round(L.grid_error([h["t"] for hs in hits.values() for h in hs], bpm), 3)
        out["mixed"] = True                    # split from a full mix, not from stems
        shift = {k: max(-24, min(24, sh)) for k, (sh, _) in feel.items() if abs(sh) >= 2 and k in lanes}
        swing = {k: sw for k, (_, sw) in feel.items() if sw and k in lanes}
        if shift: out["shift"] = shift
        if swing: out["swingLanes"] = swing
    return out


def check(stems_dir, loops_dir, temps):
    """Hits found in each full mix against the same loop's stems, per lane: found / missed / extra."""
    total = {}
    def grouped(lanes):                        # snare, clap and rim play the same part: scored as one (s+c+r)
        out = dict(lanes)
        parts = [lanes[k] for k in ("s", "c", "r") if k in lanes]
        if parts: out["s+c+r"] = "".join(next((p[i] for p in parts if p[i] != "."), ".") for i in range(len(parts[0])))
        return out
    for d in sorted(os.listdir(stems_dir)):
        mix = os.path.join(loops_dir, d + ".wav")
        if not os.path.exists(mix): continue
        truth = grouped(L.learn(os.path.join(stems_dir, d))["lanes"])
        got = grouped(learn_mix(mix, temps)["lanes"])
        for lane in set(truth) | set(got):
            a, b = truth.get(lane, ""), got.get(lane, "")
            n = max(len(a), len(b)); a, b = a.ljust(n, "."), b.ljust(n, ".")
            hit = sum(1 for x, y in zip(a, b) if x != "." and y != ".")
            t = total.setdefault(lane, [0, 0, 0])
            t[0] += hit; t[1] += sum(1 for x in a if x != ".") - hit; t[2] += sum(1 for y in b if y != ".") - hit
    for lane, (h, m, e) in sorted(total.items()):
        print(f"  {lane:>2}: found {h}, missed {m}, extra {e}  ({100 * h / max(1, h + m):.0f}% of the stems' hits)")


def main(argv):
    args, shots, out, chk = argv[1:], [], os.path.join(os.path.dirname(os.path.abspath(__file__)), "learned_fills.json"), None
    while "--oneshots" in args:
        k = args.index("--oneshots"); shots.append(args[k + 1]); del args[k:k + 2]
    if "--out" in args:
        k = args.index("--out"); out = args[k + 1]; del args[k:k + 2]
    if "--check" in args:
        args.remove("--check"); chk = args
    temps = templates(shots)
    print(len(temps), "one-shots:", {l: sum(1 for x, _ in temps if x == l) for l in L.LANE_ORDER if any(x == l for x, _ in temps)})
    if chk:
        check(chk[0], chk[1], temps); return
    fill = "--loops" not in args
    if not fill:
        args.remove("--loops")
        if out.endswith("learned_fills.json"): out = out.replace("learned_fills.json", "learned_mixed.json")
    done, seen = [], set()
    for d in args:
        for f in sorted(os.listdir(d)):
            if not f.lower().endswith(".wav") or f.startswith("._") or f in seen: continue
            seen.add(f)                        # the same loop in two packs is learned once
            p = learn_mix(os.path.join(d, f), temps, fill=fill)
            done.append(p)
            size = f"{p['beats']} beats" if fill else f"{p['bars']} bars  grid fit {p['gridFit']}"
            print(f"{p['title']}  {p['bpm']:g} BPM  {size}")
            print("\n".join(f"  {k:>2} " + "|".join(v[i:i + 16] for i in range(0, len(v), 16)) for k, v in p["lanes"].items()))
    key = "fills" if fill else "learned"
    json.dump({"version": 1, key: done}, open(out, "w"), indent=1)
    print(len(done), key, "->", out)


if __name__ == "__main__":
    main(sys.argv)
