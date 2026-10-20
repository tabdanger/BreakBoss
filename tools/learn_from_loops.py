#!/usr/bin/env python3
"""Learns drum patterns from drum loops and their stems (Tyrone's own packs, Oct 20).

The packs are reference material only: nothing from them is copied into the app or the repo. This
reads each stem, finds every hit, and writes what it heard as pattern entries in the same lane format
as tools/make_patterns.py (16 steps per bar, velocity codes . x X o g r q t), plus the feel the
loop was played with (each lane's own swing and its push or pull in ticks, 96 a beat).

    python3 -I tools/learn_from_loops.py STEMS_DIR [--loops LOOPS_DIR] [--out tools/learned_patterns.json]

STEMS_DIR holds one folder per loop (or a single-part loop as one WAV, "<Name> Hihat Loop - 120 BPM.wav"), named like "<Pack> - <Name> Drum Loop - 131 BPM", with one WAV
per sound, the sound named by the last words of the file name (Kick, Snare, Snare 2, Clap, Rim, Hihat,
Open Hat, Shaker, Percussion, Tom...). The BPM comes from the name and is checked: a loop that is not whole bars at that
tempo (or whose hits miss its grid) is measured instead and the tool says so. The loop is taken to start
on the downbeat. A loop without stems (LOOPS_DIR) is only measured (length, BPM), never split by guesswork.

How a stem becomes a lane:
  hits    an onset is where the 2 ms peak envelope jumps 9 dB over the quietest of the previous 10 ms
          and clears -36 dB of the stem's loudest hit; two onsets closer than 18 ms are one hit.
  sound   the file name says what it is; a Hihat stem's long hits (still ringing 140 ms later) and
          the high, noisy band decide hat vs open hat. A Kick stem whose hits ring under 120 Hz for
          more than 250 ms also writes the 808 lane (length in steps, pitch in semitones from the
          first note).
  grid    each hit is placed on the 16th it is nearest to; two hits in one 16th = r, four = q,
          three spread over two 16ths at triplet spacing = t.
  level   each hit's peak against the stem's loudest: X >= 0.91, x >= 0.72, o >= 0.5, g below.
  feel    a lane's hits on the beat grid give its push (-) or pull (+) in ticks (median, kept when
          2 ticks or more); its off-beat 16ths, late against the on-beat ones, give its own swing.
"""
import json, math, os, re, struct, sys
import numpy as np

TICKS = 96                                    # ticks a beat (PatternData)
LANE_ORDER = ["k", "s", "c", "r", "h", "o", "b", "p1", "p2", "lt", "ht", "cr"]
NAME_LANES = [                                # last words of the file name -> lane
    (r"open ?hat|ohh?$|open$", "o"), (r"hi ?hat|hats?$|hh$|closed", "h"), (r"kick|bd$", "k"),
    (r"808|bass$", "b"), (r"clap|cp$", "c"), (r"rim|snap|stick", "r"), (r"snare|sd$", "s"),
    (r"shaker|shake|tamb|cabasa", "p1"), (r"perc|percussion|conga|bongo|cowbell|block|bell", "p2"),
    (r"low ?tom|floor", "lt"), (r"tom", "ht"), (r"crash|ride|cymbal|cym$", "cr"),
]


def read_wav(path):
    """Mono float32 samples and the sample rate. PCM 16/24/32 and float 32/64, plain or extensible."""
    data = open(path, "rb").read()
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE", path
    i, fmt, raw = 12, None, None
    while i + 8 <= len(data):
        cid, size = data[i:i + 4], struct.unpack("<I", data[i + 4:i + 8])[0]
        body = data[i + 8:i + 8 + size]
        if cid == b"fmt ":
            tag, ch, sr, _, _, bits = struct.unpack("<HHIIHH", body[:16])
            if tag == 0xFFFE: tag = struct.unpack("<H", body[24:26])[0]
            fmt = (tag, ch, sr, bits)
        elif cid == b"data":
            raw = body
        i += 8 + size + (size & 1)
    tag, ch, sr, bits = fmt
    if tag == 3:
        x = np.frombuffer(raw, dtype="<f4" if bits == 32 else "<f8").astype(np.float32)
    elif bits == 24:
        b = np.frombuffer(raw[:len(raw) // 3 * 3], dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        x = (np.where(v >= 1 << 23, v - (1 << 24), v) / float(1 << 23)).astype(np.float32)
    else:
        x = np.frombuffer(raw, dtype={16: "<i2", 32: "<i4"}[bits]).astype(np.float32) / float(1 << (bits - 1))
    x = x[:len(x) // ch * ch].reshape(-1, ch).mean(axis=1)
    return x, sr


def lane_for(sound):
    s = sound.lower().strip()
    s = re.sub(r"\s*\d+$", "", s)             # "Snare 2" -> "snare"
    for pat, lane in NAME_LANES:
        if re.search(pat, s): return lane
    return "p2"


def onsets(x, sr):
    """(time s, peak, ring s, low share) for every hit in a stem."""
    hop = max(1, int(sr * 0.002))
    n = len(x) // hop
    env = np.abs(x[:n * hop]).reshape(n, hop).max(axis=1) + 1e-9
    db = 20 * np.log10(env)
    top = db.max()
    look = 5                                   # 10 ms back: the quietest frame there is the floor
    pad = np.concatenate([np.full(look, -200.0), db])     # silence before the file, so a hit on sample 0 counts
    floor = np.min(np.stack([pad[k:k + n] for k in range(look)]), axis=0)
    cand = np.where((db - floor >= 9) & (db > top - 36))[0]
    hits, last = [], -10 ** 9
    for f in cand:
        if (f - last) * hop / sr < 0.018: continue
        last = f
        a = f * hop
        # the hit starts where it first crosses half of the frame's rise; its peak is in the next 15 ms
        seg = np.abs(x[max(0, a - hop):a + hop])
        start = max(0, a - hop) + int(np.argmax(seg > 0.5 * seg.max()))
        win = x[start:start + int(sr * 0.015)]
        peak = float(np.abs(win).max())
        # a ringing kick or 808 wobbles its envelope: a new hit has to jump 6 dB over the last 30 ms
        before = x[max(0, start - int(sr * 0.03)):max(0, start - int(sr * 0.001))]
        if len(before) and np.abs(before).max() * 2 > peak and np.abs(before).max() > 10 ** (top / 20) * 0.01: continue
        hits.append([start / sr, peak, start])
    # how long each hit rings (to -30 dB of its peak, stopped by the next hit) and how much of it is low
    out = []
    for j, (t, peak, start) in enumerate(hits):
        end = hits[j + 1][2] if j + 1 < len(hits) else len(x)
        body = np.abs(x[start:end])
        if len(body) < 4: continue
        m = int(sr * 0.005)
        smooth = np.convolve(body, np.ones(m) / m, mode="same") if len(body) > m else body
        quiet = np.where(smooth < peak * 0.0316)[0]
        ring = (quiet[0] if len(quiet) else len(body)) / sr
        clip = x[start:start + min(len(body), int(sr * 0.3))]
        spec = np.abs(np.fft.rfft(clip * np.hanning(len(clip)))) if len(clip) > 64 else np.ones(2)
        freqs = np.fft.rfftfreq(len(clip), 1 / sr) if len(clip) > 64 else np.array([0, 1])
        low = float(spec[freqs < 120].sum() / max(1e-9, spec.sum()))
        high = float(spec[freqs > 6000].sum() / max(1e-9, spec.sum()))
        f0 = float(freqs[1:][np.argmax(spec[1:][freqs[1:] < 200])]) if (freqs < 200).sum() > 2 else 0
        out.append({"t": t, "peak": peak, "ring": ring, "low": low, "high": high, "f0": f0})
    return out


def level(v):
    """v = the hit's peak against the stem's loud hits (95th percentile), so an even hat line reads x, not g."""
    return "X" if v >= 0.91 else "x" if v >= 0.72 else "o" if v >= 0.5 else "g"


def to_lane(hits, bpm, steps):
    """Step string plus each hit's offset from its 16th in ticks."""
    ref = float(np.percentile([h["peak"] for h in hits], 95)) if hits else 1
    hits = [dict(h, peak=min(1.0, h["peak"] / ref)) for h in hits]
    step_s = 60 / bpm / 4
    cells = [[] for _ in range(steps)]
    for h in hits:
        pos = h["t"] / step_s
        i = int(round(pos)) % steps
        off = (pos - round(pos)) * TICKS / 4
        cells[i].append((off, h))
    lane, offsets = ["."] * steps, []
    i = 0
    while i < steps:
        c = cells[i]
        if not c: i += 1; continue
        if len(c) == 1:
            lane[i] = level(c[0][1]["peak"])
            offsets.append((i, c[0][0]))
        else:
            span = max(o for o, _ in c) - min(o for o, _ in c)
            lane[i] = "q" if len(c) >= 4 else "t" if len(c) == 3 and i + 1 < steps and span > 10 else "r"
            offsets.append((i, min(o for o, _ in c)))
        i += 1
    return "".join(lane), offsets


def fix_triplets(lane, hits, bpm, steps):
    """Rewrites runs where hits land a 16th triplet apart (1/6 beat) as t over two steps."""
    step_s = 60 / bpm / 4
    times = [h["t"] / step_s for h in hits]
    l = list(lane)
    for a in range(len(times) - 2):
        p, q, r = times[a], times[a + 1], times[a + 2]
        if abs((q - p) - 2 / 3) < 0.12 and abs((r - q) - 2 / 3) < 0.12:
            i = int(round(p)) % steps
            if abs(p - round(p)) < 0.2 and i + 1 < steps:
                l[i], l[i + 1] = "t", "."
    return "".join(l)


def bass_lane(hits, bpm, steps):
    step_s = 60 / bpm / 4
    notes = [h for h in hits if h["ring"] > 0.25 and h["low"] > 0.35 and h["f0"] > 20]
    if not notes: return None
    ref = notes[0]["f0"]
    l = ["."] * steps
    for h in notes:
        i = int(round(h["t"] / step_s)) % steps
        semis = int(round(12 * math.log2(h["f0"] / ref)))
        semis = max(-12, min(12, semis))
        l[i] = "0123456789abc"[semis] if semis >= 0 else "ABCDEFGHIJKL"[-semis - 1]
        for j in range(i + 1, min(steps, i + int(round(h["ring"] / step_s)))):
            if l[j] != ".": break
            l[j] = "-"
    return "".join(l)


def feel(offsets, steps):
    on = [o for i, o in offsets if i % 2 == 0]
    off = [o for i, o in offsets if i % 2 == 1]
    shift = float(np.median(on)) if on else 0.0
    swing = None
    if len(off) >= 2 and on:
        late = float(np.median(off)) - shift   # ticks the off-beat 16ths sit behind the straight grid
        if late >= 1.5: swing = round(min(1.0, late / 12), 2)   # 12 ticks late = full SWING knob
    return round(shift), swing


def grid_error(times, bpm):
    """Mean distance of the hits from the 16th grid, in 16ths."""
    pos = np.array(times) / (60 / bpm / 4)
    return float(np.abs(pos - np.round(pos)).mean()) if len(pos) else 0.0


def check_tempo(bpm, length, times):
    """The name's BPM when the loop is a whole number of bars at it; otherwise the tempo (60-180, half-BPM steps) that makes it whole bars with the hits closest to the grid."""
    bars = length * bpm / 240
    if abs(bars - round(bars)) < 0.03: return bpm
    best = None
    for n in range(1, 17):
        t = 240 * n / length
        if not 60 <= t <= 180: continue
        for cand in (round(t * 2) / 2, round(t, 2)):
            e = grid_error(times, cand)
            if best is None or e < best[0] - 1e-6: best = (e, cand)
    return best[1] if best else bpm


def merge(a, b):
    """Two stems on one lane (Snare 1 + Snare 2): keep the busier code on each step."""
    rank = {".": 0, "g": 1, "o": 2, "x": 3, "X": 4, "r": 5, "t": 6, "q": 7}
    return "".join(p if rank.get(p, 0) >= rank.get(q, 0) else q for p, q in zip(a, b))


def learn(folder):
    """One loop: a folder of stems, or one WAV that is a single part ("... Hihat Loop - 120 BPM.wav")."""
    files = None
    if os.path.isfile(folder):
        folder, files = os.path.dirname(folder), [os.path.basename(folder)]
        name = re.sub(r"(?i)\.wav$", "", files[0])
    else:
        name = os.path.basename(folder.rstrip("/"))
    m = re.search(r"(\d+(?:\.\d+)?)\s*BPM", name, re.I)
    assert m, f"no BPM in {name}"
    bpm = float(m.group(1))
    title = re.sub(r"\s*-\s*\d+(\.\d+)?\s*BPM.*", "", name, flags=re.I)
    title = re.sub(r"^[^-]+-\s*", "", title)
    title = re.sub(r"\s*(drum|hi ?hat|kick|snare|perc\w*|808|top)s?\s+loop\s*$", "", title, flags=re.I).strip()
    stems, length, skipped = {}, 0, []
    for f in files or sorted(os.listdir(folder)):
        if not f.lower().endswith(".wav") or f.startswith("._"): continue
        sound = re.sub(r"(?i)\.wav$", "", f)
        if files:                              # a single part: its kind is the word before "Loop"
            m2 = re.search(r"(?i)\b(open hat|hi ?hat|kick|snare|clap|rim|perc\w*|shaker|tom|808|cymbal|ride|crash)s?\s+loop", sound)
            sound = m2.group(1) if m2 else "Perc"
        else:
            sound = re.sub(r".*BPM\s*", "", sound).strip() or "Perc"
        if re.search(r"(?i)revers", sound):   # a reversed swell is not a hit on any pad
            skipped.append(sound); continue
        x, sr = read_wav(os.path.join(folder, f))
        length = max(length, len(x) / sr)
        stems[sound] = onsets(x, sr)
    named = bpm
    bpm = check_tempo(bpm, length, [h["t"] for hits in stems.values() for h in hits])
    bars = max(1, int(round(length * bpm / 240)))
    steps = bars * 16
    lanes, report, offs = {}, {}, {}
    for sound, hits in stems.items():
        lane = lane_for(sound)
        if lane == "h":                        # a hat stem's long, ringing hits are open hats
            open_ = [h for h in hits if h["ring"] > 0.14]
            closed = [h for h in hits if h["ring"] <= 0.14]
            if open_ and closed and len(open_) < len(closed):
                s_o, o_o = to_lane(open_, bpm, steps)
                lanes["o"] = merge(lanes.get("o", "." * steps), s_o)
                offs.setdefault("o", []).extend(o_o)
                hits = closed
        if lane == "k":
            b = bass_lane(hits, bpm, steps)
            if b: lanes["b"] = b
        s, o = to_lane(hits, bpm, steps)
        s = fix_triplets(s, hits, bpm, steps)
        if lane in lanes and lane != "s": lane = next(l for l in ("p1", "p2", "r", "c") if l not in lanes)
        lanes[lane] = merge(lanes[lane], s) if lane in lanes else s
        offs.setdefault(lane, []).extend(o)
        report[sound] = {"lane": lane, "hits": len(hits)}
    shift, swing_lanes = {}, {}
    for lane, o in offs.items():
        sh, sw = feel(o, steps)
        if abs(sh) >= 2: shift[lane] = max(-24, min(24, sh))
        if sw: swing_lanes[lane] = sw
    lanes = {k: lanes[k] for k in LANE_ORDER if k in lanes}
    if bpm != named: print(f"  {title}: the name says {named:g} BPM, the loop is {bpm:g} BPM ({bars} bars)")
    p = {"source": name, "title": title.upper(), "bpm": bpm, "bars": bars, "lanes": lanes, "stems": report}
    fit = grid_error([h["t"] for hits in stems.values() for h in hits], bpm)
    p["gridFit"] = round(fit, 3)               # 0 = every hit on a 16th; above ~0.12 the loop is played off the 16ths (triplets, loose)
    if skipped: p["skipped"] = skipped
    if shift: p["shift"] = shift
    if swing_lanes: p["swingLanes"] = swing_lanes
    return p


def grid(p):
    """The pattern as text, one row per lane and a bar line every 16 steps."""
    rows = []
    for k, v in p["lanes"].items():
        rows.append(f"  {k:>2} " + "|".join(v[i:i + 16] for i in range(0, len(v), 16)))
    return "\n".join(rows)


def main(argv):
    args = argv[1:]
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "learned_patterns.json")
    if "--out" in args:
        k = args.index("--out"); out = args[k + 1]; del args[k:k + 2]
    if "--loops" in args:
        k = args.index("--loops"); del args[k:k + 2]
    root = args[0]
    folders = sorted(os.path.join(root, d) for d in os.listdir(root)
                     if os.path.isdir(os.path.join(root, d)) or (d.lower().endswith(".wav") and not d.startswith("._")))
    learned = []
    for f in folders:
        p = learn(f)
        learned.append(p)
        feel_txt = " ".join(f"{k}={v}" for k, v in (("shift", p.get("shift")), ("swing", p.get("swingLanes"))) if v)
        print(f"{p['title']}  {p['bpm']:g} BPM  {p['bars']} bars  grid fit {p['gridFit']}  {feel_txt}")
        print(grid(p))
    json.dump({"version": 1, "learned": learned}, open(out, "w"), indent=1)
    print(len(learned), "loops ->", out)


if __name__ == "__main__":
    main(sys.argv)
