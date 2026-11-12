#!/usr/bin/env python3
"""Learns BK Editions Vol 5-8 from Tyrone's "mastery drums" iCloud folder (Nov 12): four drum suites (Trap, RnB,
Experimental, Vintage), each with drum loops (most with stems), drum fills, percussion / hat loops, live drum breaks
(Vintage) and drum MIDI (one part per file: kick, snare, hats, open hats or 808).

    python3 -I tools/learn_mastery.py SUITE_DIR [SUITE_DIR ...]      # -> tools/learned_mastery.json

SUITE_DIR is an unzipped suite folder; its name says which suite it is (Trap, RnB, Experimental or Vintage). Like every
learner here the packs are reference only: no audio, MIDI or name from them ships. Each file becomes one entry:

  loop    a drum loop. Its stems when it has them (tools/learn_from_loops.py: each stem's hits on the 16ths, its
          level, its feel); a stem named only "Track 3" is matched, hit by hit, to the suite's own one-shots (the
          Drum Kit folder) and the stock library. An 808 stem writes the 808 lane: each note's pitch against C,
          since every 808 in BreaKing is tuned to C. Vocal, riser, FX and reversed stems are left out. A loop with
          no stems is split from the full mix (tools/learn_fills.py).
  break   a live drum break (full mix, split like a loop with no stems against the acoustic sounds too).
  fill    a fill or snare roll, split from the mix (a roll's soft hits count: it swells from soft to hard); its length is its hits' span rounded up to a quarter bar
          (up to two bars) and it sits at the end of its bar so it lands on the next downbeat.
  perc    a percussion, hat or crash loop: only those sounds are listened for.
  midi    a drum MIDI file: its notes on the 16ths, levels from velocity (the 808's pitch against C, its length).
          Files of the same number and tempo in one suite (Kick MIDI 3 + Snare MIDI 3 at 148) are one entry.

Lengths: 1, 2, 4 or 8 bars (a 6-bar loop keeps its first 4, a 16-bar one its first 8). A loop in 3/4 can't loop
on the 16-step bars and is listed under "skipped". tools/make_patterns.py turns the entries into presets.
"""
import json, math, os, re, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import learn_from_loops as L, learn_fills as F  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
OUT = os.path.join(ROOT, "tools", "learned_mastery.json")
SUITES = ["Trap", "RnB", "Experimental", "Vintage"]
SKIP = r"(?i)vox|vocal|chant|scream|riser|laser|\bfx\b|revers|sweep|melod|impact|uplifter|downlifter"
STEM_LANES = [                                   # stem name -> lane, before learn_from_loops' own words
    (r"(?i)808|sub\b|bass", "b"), (r"(?i)open ?hat|openhat|\boh\b", "o"), (r"(?i)hi ?-?hat|hihat|\bhats?\b", "h"),
    (r"(?i)kick", "k"), (r"(?i)clap|snap", "c"), (r"(?i)rim|stick", "r"),
    (r"(?i)snare|drum roll", "s"), (r"(?i)crash|ride|cymbal", "cr"),
    (r"(?i)shaker|tamb|triangle|cowbell|clav|bell", "p1"), (r"(?i)perc|conga|bongo|tom|click", "p2"),
]
KIT_LANES = [                                    # Drum Kit folder (or file) words -> lane of its one-shots
    (r"(?i)808|bass|fx|vox", None), (r"(?i)open|\boh\b", "o"), (r"(?i)crash", "cr"), (r"(?i)hi-?hat|hihat|hats", "h"),
    (r"(?i)kick", "k"), (r"(?i)clap|snap", "c"), (r"(?i)rim", "r"), (r"(?i)snare", "s"),
    (r"(?i)high perc", "p1"), (r"(?i)perc", "p2"),
]
STOCK_KIND = {"KICK": "k", "SNARE": "s", "CLAP": "c", "RIM": "r", "HAT": "h", "OPEN HAT": "o", "CYMBAL": "cr",
              "TOM": "lt", "PERC": "p2"}
ALLOWED_BARS = (1, 2, 4, 8)


def bpm_of(name):
    m = re.search(r"(\d+(?:\.\d+)?)\s*-?\s*bpm", name, re.I)
    return float(m.group(1)) if m else None


def whole_bars(length, bpm):
    """The pack's names carry the real tempo; a stem or loop that rings past its last bar (an 808 tail) still
    counts the bars it plays."""
    bars = length * bpm / 240
    return max(1, int(round(bars)) if bars - int(bars) > 0.25 else int(bars))


def fit_bars(bars):
    return max(b for b in ALLOWED_BARS if b <= max(1, bars))


def templates(suite_dir, acoustic):
    """(lane, features) of the suite's own one-shots and the stock library (acoustic sounds only for Vintage)."""
    out = []
    kit = next((os.path.join(suite_dir, d) for d in os.listdir(suite_dir) if "drum kit" in d.lower()), None)
    for root, _, files in os.walk(kit or "/nonexistent"):
        for f in files:
            if not f.lower().endswith(".wav") or f.startswith("._"): continue
            rel = os.path.relpath(os.path.join(root, f), kit)
            lane = next((ln for pat, ln in KIT_LANES if re.search(pat, rel)), "skip")
            if lane in (None, "skip"): continue
            out.append((lane, os.path.join(root, f)))
    for r in json.load(open(os.path.join(STOCK, "manifest.json")))["sounds"]:
        lane = STOCK_KIND.get(r["type"])
        if not lane: continue
        if r["file"].startswith(("ac_", "va_")) and not acoustic: continue
        if r["type"] == "TOM" and "HIGH" in r["name"].upper(): lane = "ht"
        out.append((lane, os.path.join(STOCK, r["file"])))
    temps = []
    for lane, path in out:
        try: x, sr = L.read_wav(path)
        except Exception: continue
        hs = L.onsets(x, sr)
        if not hs: continue
        h = max(hs, key=lambda h: h["peak"])
        temps.append((lane, F.features(x, sr, int(h["t"] * sr), h["ring"])))
    return temps


def clip(lanes, steps):
    return {k: v[:steps] for k, v in lanes.items() if v[:steps].strip(".-")}


def pitch(x, sr, t, ring):
    """An 808 note's pitch in Hz: autocorrelation over the body of the note (30 ms in, up to 400 ms)."""
    a = int(sr * (t + 0.03)); b = int(sr * (t + max(0.12, min(0.4, ring))))
    seg = x[a:b]
    if len(seg) < sr * 0.06: return 0.0
    seg = F.band(seg, sr, 20, 400)
    seg = seg - seg.mean()
    ac = np.correlate(seg, seg, mode="full")[len(seg) - 1:]
    lo, hi = int(sr / 250), int(sr / 25)
    if hi >= len(ac): return 0.0
    k = lo + int(np.argmax(ac[lo:hi]))
    if ac[k] <= 0: return 0.0
    return sr / k


def semis_code(s):
    s = max(-12, min(12, s))
    return "0123456789abc"[s] if s >= 0 else "ABCDEFGHIJKL"[-s - 1]


def against_c(notes):
    """MIDI note numbers -> semitones from the C that keeps the line inside the 808 lane's +-12."""
    if not notes: return []
    common = max(set(notes), key=notes.count)
    ref = 12 * (common // 12)                     # the C at or below the line's home note
    return [n - ref for n in notes]


def bass_lane(events, bpm, steps):
    """[(t s, midi note, length s)] -> 808 lane."""
    step_s = 60 / bpm / 4
    l = ["."] * steps
    semis = against_c([n for _, n, _ in events])
    for (t, _, length), s in zip(events, semis):
        i = int(round(t / step_s))
        if i >= steps or l[i] not in ".-": continue
        l[i] = semis_code(s)
        for j in range(i + 1, min(steps, i + max(1, int(round(length / step_s))))):
            if l[j] != ".": break
            l[j] = "-"
    return "".join(l)


def stem_808(x, sr, bpm, steps):
    hits = [h for h in L.onsets(x, sr) if h["peak"] > 0.05]
    ev = []
    for j, h in enumerate(hits):
        f0 = pitch(x, sr, h["t"], h["ring"])
        if f0 <= 0: continue
        note = int(round(69 + 12 * math.log2(f0 / 440)))
        nxt = hits[j + 1]["t"] if j + 1 < len(hits) else h["t"] + h["ring"]
        ev.append((h["t"], note, min(h["ring"], nxt - h["t"])))
    return bass_lane(ev, bpm, steps) if ev else None


def stem_lane(name, x, sr, temps):
    base = re.sub(r"(?i)\.wav$", "", name)
    if re.search(SKIP, base): return None
    for pat, lane in STEM_LANES:
        if re.search(pat, base): return lane
    hs = L.onsets(x, sr)                          # "Track 3": each hit votes for the one-shot it sounds like
    if not hs: return None
    loud = float(np.percentile([h["peak"] for h in hs], 90))
    votes = {}
    for h in hs:
        if h["peak"] < 0.5 * loud: continue
        f = F.features(x, sr, int(h["t"] * sr), h["ring"])
        lane = F.classify(f, temps, {"k", "s", "c", "r", "h", "o", "cr", "p1", "p2", "lt", "ht"})
        if lane: votes[lane] = votes.get(lane, 0) + 1
    if not votes: return None
    lane = max(votes, key=votes.get)
    if lane == "k" and np.median([h["ring"] for h in hs]) > 0.35 and np.median([h["low"] for h in hs]) > 0.5: return "b"
    return lane


def learn_stems(folder, bpm, temps):
    files = []
    for root, _, fs in os.walk(folder):
        files += [os.path.join(root, f) for f in fs if f.lower().endswith(".wav") and not f.startswith("._")]
    stems, length = [], 0
    for p in sorted(files):
        x, sr = L.read_wav(p)
        lane = stem_lane(os.path.basename(p), x, sr, temps)
        length = max(length, len(x) / sr)
        if lane: stems.append((lane, os.path.basename(p), x, sr))
    if not stems: return None
    times = [h["t"] for lane, _, x, sr in stems if lane != "b" for h in L.onsets(x, sr)]
    bars = whole_bars(length, bpm)
    steps = bars * 16
    lanes, offs, used = {}, {}, {}
    for lane, name, x, sr in stems:
        if lane == "b":
            b = stem_808(x, sr, bpm, steps)
            if b and "b" not in lanes: lanes["b"] = b; used[name] = "b"
            continue
        hits = [h for h in L.onsets(x, sr) if h["peak"] > 1e-4]      # a silent stem has no hits
        if not hits: continue
        if lane == "h":                           # a hat stem's long, ringing hits are open hats
            open_ = [h for h in hits if h["ring"] > 0.14]
            closed = [h for h in hits if h["ring"] <= 0.14]
            if open_ and closed and len(open_) < len(closed):
                s_o, o_o = L.to_lane(open_, bpm, steps)
                lanes["o"] = L.merge(lanes.get("o", "." * steps), s_o)
                offs.setdefault("o", []).extend(o_o)
                hits = closed
        s, o = L.to_lane(hits, bpm, steps)
        s = L.fix_triplets(s, hits, bpm, steps)
        if lane in lanes and lane not in ("s", "h", "o"):
            lane = next((l for l in ("p1", "p2", "r", "c") if l not in lanes), lane)
        lanes[lane] = L.merge(lanes[lane], s) if lane in lanes else s
        offs.setdefault(lane, []).extend(o)
        used[name] = lane
    keep = fit_bars(bars) * 16
    out = {"bpm": bpm, "bars": keep // 16, "lanes": order(clip(lanes, keep)), "stems": used}
    shift, swing = {}, {}
    for lane, o in offs.items():
        sh, sw = L.feel([(i, v) for i, v in o if i < keep], keep)
        if abs(sh) >= 2 and lane in out["lanes"]: shift[lane] = max(-24, min(24, sh))
        if sw and lane in out["lanes"]: swing[lane] = sw
    if shift: out["shift"] = shift
    if swing: out["swingLanes"] = swing
    out["gridFit"] = round(L.grid_error(times, bpm), 3)
    return out


def order(lanes):
    return {k: lanes[k] for k in L.LANE_ORDER if k in lanes}


def learn_mix(path, temps):
    p = F.learn_mix(path, temps)
    keep = fit_bars(p["bars"]) * 16
    p["lanes"] = order(clip(p["lanes"], keep))
    p["bars"] = keep // 16
    for key in ("shift", "swingLanes"):
        if key in p:
            p[key] = {k: v for k, v in p[key].items() if k in p["lanes"]}
            if not p[key]: p.pop(key)
    return p


def learn_fill(path, temps, bpm):
    floor = dict(F.FLOOR)
    if re.search(r"(?i)snare roll", os.path.basename(path)):
        F.FLOOR.update(mid=0.1, high=0.08)       # a roll swells from soft to hard: its soft hits are the roll
    try: hits, length = F.split(path, temps)
    finally: F.FLOOR.clear(); F.FLOOR.update(floor)
    if not hits: return None
    last = max(h["t"] for hs in hits.values() for h in hs)
    beats = min(8.0, max(1.0, math.ceil((last * bpm / 60 + 0.25) - 0.15)))    # whole beats, up to two bars
    bars = 1 if beats <= 4 else 2
    steps = bars * 16
    offset = steps - int(beats * 4)
    lanes = {}
    for lane, hs in hits.items():
        hs = [dict(h, t=h["t"] + offset * 60 / bpm / 4) for h in hs if h["t"] * bpm / 15 < beats * 4 - 0.5]
        if not hs: continue
        s, _ = L.to_lane(hs, bpm, steps)
        s = L.fix_triplets(s, hs, bpm, steps)
        if lane == "k": s = s.replace("r", "x").replace("q", "x")
        lanes[lane] = s
    if "c" in lanes and "s" not in lanes: lanes["s"] = lanes.pop("c")
    return {"bpm": bpm, "bars": bars, "beats": beats, "lanes": order(clip(lanes, steps))}


def learn_part(path, temps, allowed):
    """A percussion / hat / crash loop: only the given lanes are listened for, in every band."""
    x, sr = L.read_wav(path)
    bpm = bpm_of(os.path.basename(path))
    hs = [h for h in L.onsets(x, sr) if h["peak"] > 1e-4]
    if not hs: return None
    length = len(x) / sr
    bars = whole_bars(length, bpm)
    steps = bars * 16
    loud = float(np.percentile([h["peak"] for h in hs], 95))
    by = {}
    for h in hs:
        if h["peak"] < 0.12 * loud: continue
        if allowed == {"p1", "p2"}: lane = "p1" if h["high"] > 0.2 else "p2"     # shaker, hat-like and bright percs on 1
        else: lane = F.classify(F.features(x, sr, int(h["t"] * sr), h["ring"]), temps, allowed) or sorted(allowed)[0]
        by.setdefault(lane, []).append(h)
    lanes, offs = {}, {}
    for lane, hits in by.items():
        s, o = L.to_lane(hits, bpm, steps)
        lanes[lane] = L.fix_triplets(s, hits, bpm, steps)
        offs[lane] = o
    keep = fit_bars(bars) * 16
    out = {"bpm": bpm, "bars": keep // 16, "lanes": order(clip(lanes, keep))}
    shift, swing = {}, {}
    for lane, o in offs.items():
        sh, sw = L.feel([(i, v) for i, v in o if i < keep], keep)
        if abs(sh) >= 2 and lane in out["lanes"]: shift[lane] = max(-24, min(24, sh))
        if sw and lane in out["lanes"]: swing[lane] = sw
    if shift: out["shift"] = shift
    if swing: out["swingLanes"] = swing
    out["gridFit"] = round(L.grid_error([h["t"] for h in hs], bpm), 3)
    return out


MIDI_LANE = [(r"(?i)open", "o"), (r"(?i)hi ?hat", "h"), (r"(?i)kick", "k"), (r"(?i)snare", "s"), (r"(?i)808", "b")]


def read_midi(path):
    """[(tick, note, velocity, length ticks)], ticks per beat, end tick."""
    import mido
    m = mido.MidiFile(path)
    notes, on, t = [], {}, 0
    for msg in mido.merge_tracks(m.tracks):
        t += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            on.setdefault(msg.note, []).append(len(notes))
            notes.append([t, msg.note, msg.velocity, 0])
        elif msg.type in ("note_off", "note_on") and on.get(msg.note):
            i = on[msg.note].pop(0)
            notes[i][3] = t - notes[i][0]
    return [tuple(n) for n in notes], m.ticks_per_beat, t


def learn_midi(path, lane, bpm):
    notes, tpb, end = read_midi(path)
    if not notes: return None
    beat_s = 60 / bpm
    last = max(n[0] + max(n[3], 1) for n in notes)
    bars = max(1, math.ceil(last / tpb / 4 - 1e-6))
    steps = fit_bars(bars) * 16
    if lane == "b":
        ev = [(t / tpb * beat_s, n, max(l, 1) / tpb * beat_s) for t, n, _, l in notes]
        return {"bars": steps // 16, "lanes": {"b": bass_lane(ev, bpm, steps)}}
    vmax = max(v for _, _, v, _ in notes)
    hits = [{"t": t / tpb * beat_s, "peak": v / vmax} for t, _, v, _ in notes if t / tpb < steps / 4 - 0.01]
    s, o = L.to_lane(hits, bpm, steps)
    s = L.fix_triplets(s, hits, bpm, steps)
    out = {"bars": steps // 16, "lanes": {lane: s}}
    sh, sw = L.feel(o, steps)
    if abs(sh) >= 2: out["shift"] = {lane: max(-24, min(24, sh))}
    if sw: out["swingLanes"] = {lane: sw}
    return out


def title_of(name):
    t = re.sub(r"(?i)\.(wav|mid)$", "", name)
    t = re.sub(r"\s*\[.*?\]\s*", " ", t)
    t = re.sub(r"\(@[^)]*\)|@\S+", "", t)
    t = re.sub(r"(?i)\s*-?\s*\d+(\.\d+)?\s*bpm.*", "", t)
    return re.sub(r"\s+", " ", t).strip(" -").upper()


def learn_suite(suite_dir):
    suite = next(s for s in SUITES if s.lower() in os.path.basename(suite_dir.rstrip("/")).lower())
    print(f"== {suite}")
    temps = templates(suite_dir, acoustic=suite == "Vintage")
    print(f"   {len(temps)} one-shots to match against")
    out, skipped = [], []
    dirs = {d.lower(): os.path.join(suite_dir, d) for d in os.listdir(suite_dir)}
    def sub(word): return [p for d, p in sorted(dirs.items()) if word in d]

    # loops (stems when they have them)
    for loops in sub("drum loops"):
        stem_root = next((os.path.join(loops, d) for d in os.listdir(loops) if "stems" in d.lower()), None)
        stem_dirs = {}
        if stem_root:
            for d in os.listdir(stem_root):
                if os.path.isdir(os.path.join(stem_root, d)): stem_dirs[title_of(d).split(" ")[0].lower() + "|" + str(bpm_of(d))] = os.path.join(stem_root, d)
        for f in sorted(os.listdir(loops)):
            if not f.lower().endswith(".wav") or f.startswith("._"): continue
            path, bpm, title = os.path.join(loops, f), bpm_of(f), title_of(f)
            if re.search(r"3-4|3/4", f): skipped.append({"file": f, "why": "3/4 time"}); continue
            key = re.sub(r"(?i)\s*(trap|rnb|r&b|experimental|vintage)?\s*drum loop.*", "", title).split(" ")[0].lower() + "|" + str(bpm)
            p = learn_stems(stem_dirs[key], bpm, temps) if key in stem_dirs else None
            src = "stems"
            if not p or "k" not in p["lanes"] and not ("b" in p["lanes"]):
                p, src = learn_mix(path, temps), "mix"
            out.append(dict(p, kind="loop", suite=suite, title=title, source=src, file=f))
            print(f"   loop  {title[:40]:40} {p['bpm']:>6g} {p['bars']} bars {src:5} {' '.join(p['lanes'])}")
        for d in stem_dirs.values():                     # stems whose loop has no full mix
            name = os.path.basename(d)
            if not any(title_of(o["file"]).split(" ")[0].lower() == title_of(name).split(" ")[0].lower() and o["bpm"] == bpm_of(name) for o in out):
                if re.search(r"3-4|3/4", name): skipped.append({"file": name, "why": "3/4 time"}); continue
                p = learn_stems(d, bpm_of(name), temps)
                if p: out.append(dict(p, kind="loop", suite=suite, title=title_of(name), source="stems", file=name))

    # live drum breaks, hat and percussion loops
    for breaks in sub("drum breaks"):
        for root, _, fs in sorted(os.walk(breaks)):
            for f in sorted(fs):
                if not f.lower().endswith(".wav") or f.startswith("._"): continue
                part(os.path.join(root, f), f, temps, suite, out, skipped)
    for perc in sub("perc loops"):
        for f in sorted(os.listdir(perc)):
            if f.lower().endswith(".wav") and not f.startswith("._"): part(os.path.join(perc, f), f, temps, suite, out, skipped)

    # fills
    for fills in sub("fills"):
        for f in sorted(os.listdir(fills)):
            if not f.lower().endswith(".wav") or f.startswith("._"): continue
            bpm = bpm_of(f)
            p = learn_fill(os.path.join(fills, f), temps, bpm)
            if not p or not p["lanes"]: skipped.append({"file": f, "why": "no hits heard"}); continue
            what = "SNARE ROLL" if re.search(r"(?i)snare roll", f) else "TOM FILL" if "lt" in p["lanes"] or "ht" in p["lanes"] or re.search(r"(?i)tom", f) else "FILL"
            out.append(dict(p, kind="fill", suite=suite, title=title_of(f), what=what, file=f))
            print(f"   fill  {title_of(f)[:40]:40} {bpm:>6g} {p['beats']:g} beats {' '.join(p['lanes'])}")

    # MIDI: one entry per number + tempo
    groups = {}
    for midi in sub("drum midi"):
        for root, _, fs in os.walk(midi):
            for f in fs:
                if not f.lower().endswith(".mid"): continue
                rel = os.path.relpath(os.path.join(root, f), midi)
                if re.search(SKIP, rel): skipped.append({"file": f, "why": "vocal MIDI"}); continue
                lane = next((ln for pat, ln in MIDI_LANE if re.search(pat, rel)), None)
                if not lane: skipped.append({"file": f, "why": "not a drum part"}); continue
                num = re.search(r"(?i)midi\s*(\d+)", f)
                bpm = bpm_of(f)
                feel = re.sub(r"(?i)\s*(kick|snare|hi ?hat|open hat|808)?\s*midi.*", "", title_of(f)).strip()
                key = (feel, num.group(1) if num else f, bpm)
                groups.setdefault(key, []).append((lane, os.path.join(root, f)))
    for (feel, num, bpm), parts in sorted(groups.items(), key=lambda kv: (kv[0][2], kv[0][0], str(kv[0][1]).zfill(4))):
        lanes, shift, swing, bars, files = {}, {}, {}, 0, []
        for lane, path in sorted(parts):
            p = learn_midi(path, lane, bpm)
            if not p: continue
            bars = max(bars, p["bars"])
            for k, v in p["lanes"].items(): lanes[k] = v
            shift.update(p.get("shift", {})); swing.update(p.get("swingLanes", {}))
            files.append(os.path.basename(path))
        if not lanes: continue
        steps = bars * 16
        lanes = {k: (v * (steps // len(v)))[:steps] for k, v in lanes.items()}
        e = {"kind": "midi", "suite": suite, "title": feel, "bpm": bpm, "bars": bars, "lanes": order(lanes), "parts": sorted(lanes), "file": " + ".join(files)}
        if shift: e["shift"] = shift
        if swing: e["swingLanes"] = swing
        out.append(e)
        print(f"   midi  {(feel + ' ' + str(num))[:40]:40} {bpm:>6g} {bars} bars {' '.join(lanes)}")
    return out, skipped


def part(path, f, temps, suite, out, skipped):
    bpm = bpm_of(f)
    if bpm is None: skipped.append({"file": f, "why": "no tempo in the name"}); return
    if re.search(r"(?i)drum break", f) and not re.search(r"(?i)hi ?hat", f):
        p = learn_mix(path, temps); kind = "break"
    else:
        if re.search(r"(?i)crash", f): allowed = {"cr", "h", "o"} if re.search(r"(?i)hat", f) else {"cr", "p1", "p2"}
        elif re.search(r"(?i)hat", f): allowed = {"h", "o"}
        elif re.search(r"(?i)clap", f): allowed = {"c", "p1", "p2"}
        else: allowed = {"p1", "p2"}
        p = learn_part(path, temps, allowed); kind = "perc"
    if not p or not p["lanes"]: skipped.append({"file": f, "why": "no hits heard"}); return
    out.append(dict(p, kind=kind, suite=suite, title=title_of(f), file=f))
    print(f"   {kind:5} {title_of(f)[:40]:40} {p['bpm']:>6g} {p['bars']} bars {' '.join(p['lanes'])}")


def main(argv):
    L.check_tempo = lambda bpm, length, times: bpm      # the pack's names carry the real tempo
    to_lane = L.to_lane                                  # a silent stem or band (every peak 0) has no hits
    L.to_lane = lambda hits, bpm, steps: to_lane([h for h in hits if h["peak"] > 1e-6], bpm, steps)
    entries, skipped = [], []
    for d in argv:
        e, s = learn_suite(d)
        entries += e; skipped += s
    for e in entries:
        e.pop("file", None); e.pop("stems", None)
        if e.get("source") not in ("stems", "mix"): e.pop("source", None)     # no file names (producer tags) kept
    skipped = [{"title": title_of(s["file"]), "why": s["why"]} for s in skipped]
    json.dump({"learned": entries, "skipped": skipped}, open(OUT, "w"), indent=1)
    from collections import Counter
    print(len(entries), "entries", dict(Counter((e["suite"], e["kind"]) for e in entries)), len(skipped), "skipped:", skipped)


if __name__ == "__main__":
    main(sys.argv[1:])
