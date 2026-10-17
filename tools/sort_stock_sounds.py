#!/usr/bin/env python3
"""Sorts every stock sound by category and gives it a new name (Oct 17, run once).

Ran once on Oct 17 (it reads the manifest from before then, now in git history).

  python3 tools/sort_stock_sounds.py            # dry run: prints the new names
  python3 tools/sort_stock_sounds.py --apply    # renames the WAVs (git mv), drops exact duplicates

Reads the old Resources/StockSamples/manifest.json, listens to each sound (length, decay, brightness,
low end, stereo width, pitch), puts it in a category (KICK, SNARE, CLAP, RIM/SNAP, HAT, OPEN HAT, 808,
PERC, TOM, CYMBAL, FX), and names it CATEGORY + CHARACTER + NUMBER, e.g. "KICK BOOM 07",
"808 F#1 LONG 02", "SHAKER 03". Files become bb_<name>.wav. Identical audio is kept once.

Writes tools/stock_sounds.json, the sound catalog tools/build_kits.py builds the kits from. Each
entry keeps the genres of the old kits it came from ("tags"), so the new kits can still pick
sounds made for their genre.
"""
import collections, hashlib, json, os, re, subprocess, sys, wave
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
CATALOG = os.path.join(ROOT, "tools", "stock_sounds.json")

# The genre each old kit was made for (the new kits look for these).
OLD_KIT_TAGS = {
    "trap": "memphis-trap atl-trap knock-gang danger-drums danger-drums-2 g-trap-a g-trap-b s-atl-wave-a s-atl-wave-b "
            "drum-mastery modern-trap",
    "dark": "six-side toronto-weird g-dark-trap-a g-dark-trap-b s-toronto-nights-a s-toronto-nights-b",
    "rage": "rage s-vamp-rage-a s-vamp-rage-b s-rockstar-bounce-a s-rockstar-bounce-b",
    "drill": "drill-nights g-drill-a g-drill-b",
    "detroit": "detroit g-detroit-a g-detroit-b",
    "west": "west-end west-bounce bay-slap west-90s g-west-coast-a g-west-coast-b s-la-lyricist-a s-la-lyricist-b",
    "rnb": "trap-soul modern-rnb 2000s-rnb g-rnb-a g-rnb-b s-late-night-rnb-a s-late-night-rnb-b s-houston-queen-a "
           "s-houston-queen-b s-soft-soul-a s-soft-soul-b",
    "90srnb": "g-90s-rnb-a g-90s-rnb-b 90s-pop g-80s-rnb-a g-80s-rnb-b",
    "soul": "cole-world vintage-rnb dirty-soul live-soul neo-soul gospel-chops g-neo-soul-a g-neo-soul-b g-soul-rnb-a "
            "g-soul-rnb-b lo-fi s-carolina-soul-a s-carolina-soul-b",
    "boombap": "boom-bap g-boom-bap-a g-boom-bap-b s-carolina-soul-a s-carolina-soul-b loose-break",
    "funk": "analog-funk funk-break g-80s-funk-a g-80s-funk-b heavy-break loose-break",
    "pop80": "80s-pop g-80s-pop-a g-80s-pop-b live-pop",
    "jazz": "g-jazz-a g-jazz-b",
    "world": "afrobeats world-latin shakers perc-loops g-house-a g-house-b",
    "amapiano": "amapiano g-amapiano-a g-amapiano-b g-south-african-rnb-a g-south-african-rnb-b",
    "electronic": "g-edm-a g-edm-b g-techno-a g-techno-b dark-experimental resampled-textures sky-textures",
}
TAGS_OF = collections.defaultdict(set)
for tag, ids in OLD_KIT_TAGS.items():
    for k in ids.split(): TAGS_OF[k].add(tag)

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def load(path):
    w = wave.open(path)
    a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    return a.reshape(-1, w.getnchannels()), w.getframerate()


def pitch_of(seg, sr, lo=28, hi=500):
    """Strongest partial in lo..hi Hz, dropped an octave when the octave below is also strong (808s)."""
    if len(seg) < 2048: return 0.0
    n = 1 << 17
    sp = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n=n)); fq = np.fft.rfftfreq(n, 1 / sr)
    band = (fq > lo) & (fq < hi)
    f = float(fq[band][np.argmax(sp[band])]); top = sp[band].max()
    while f / 2 > lo:
        near = (fq > f / 2 * 0.94) & (fq < f / 2 * 1.06)
        if sp[near].max() >= 0.35 * top: f = float(fq[near][np.argmax(sp[near])])
        else: break
    return f


def features(path):
    a, sr = load(path)
    mono = a.mean(1)
    peak = float(np.abs(mono).max()) + 1e-9
    above = np.nonzero(np.abs(mono) > peak * 0.003)[0]                    # -50 dB from the peak
    start, end = (above[0], above[-1]) if len(above) else (0, len(mono) - 1)
    x = mono[start:end + 1]
    fr = int(sr * 0.01); nf = max(1, len(x) // fr)
    rms = np.sqrt(np.mean(x[:nf * fr].reshape(nf, fr) ** 2, axis=1) + 1e-12) if len(x) >= fr else np.array([peak])
    pk = int(np.argmax(rms))
    decay = (np.nonzero(rms > rms.max() * 0.1)[0][-1] - pk) * 0.01         # time to -20 dB
    n = 1 << 16
    p = np.abs(np.fft.rfft(x * np.hanning(len(x)) if len(x) > 8 else x, n=n)) ** 2
    fq = np.fft.rfftfreq(n, 1 / sr); tot = p.sum() + 1e-12
    s0 = start + int(np.argmax(np.abs(x))) + int(0.03 * sr)
    side = (a[:, 0] - a[:, -1]) / 2; mid = (a[:, 0] + a[:, -1]) / 2
    return {
        "dur": round(len(x) / sr, 3), "decay": round(float(decay), 3),
        "attack": round(pk / max(1, nf), 3),                                 # where the loudest part sits (0 = start)
        "bright": int((fq * p).sum() / tot),                                 # spectral centroid, Hz
        "top": int(fq[np.searchsorted(np.cumsum(p), 0.95 * tot)]),           # 95% of the energy is below this
        "low": round(float(p[fq < 150].sum() / tot), 3),
        "width": round(float(np.sqrt((side ** 2).mean() / ((mid ** 2).mean() + 1e-12))), 3),
        "pitch": round(pitch_of(mono[s0:s0 + int(0.4 * sr)], sr), 1),
    }


def has(text, *words):
    t = " " + re.sub(r"[^a-z0-9]+", " ", text.lower()) + " "
    return any((" " + w) in t for w in words)


def category(names, pad, f):
    """The kind of sound: from its old names first, then the pad it was made for, then how it sounds."""
    n = " ".join(names)
    if has(n, "rev", "reverse"): return "FX"
    if has(n, "sr fx", "fx", "ambience", "animal", "earthquake", "engine", "winter", "ghosts", "harddd", "paint"): return "FX"
    if pad == 6: return "808"
    if has(n, "open hat", "openhat", "ohh", "open hihat", "open hi"): return "OPEN HAT"
    if has(n, "shaker", "spshak", "tamb", "clave", "triangle", "weirdtriangle", "beads", "conga", "bongo", "cowbell"): return "PERC"
    if f["attack"] > 0.55 and f["dur"] > 0.3: return "FX"                  # swells up: a reverse
    if has(n, "ride", "cymbal", "crash"): return "CYMBAL"
    if has(n, "tom"): return "TOM"
    if has(n, "kick"): return "KICK"
    if has(n, "snap"): return "RIM"
    if pad == 2 or has(n, "clap"): return "CLAP"
    if has(n, "snare"): return "SNARE"
    if has(n, "rim"): return "RIM"
    if has(n, "hihat", "hi hat", "hat", "hh"): return "HAT"
    if has(n, "perc"): return "PERC"
    by_pad = {0: "KICK", 1: "SNARE", 2: "CLAP", 3: "RIM", 4: "HAT", 5: "OPEN HAT", 7: "PERC", 8: "PERC", 9: "TOM", 10: "TOM", 11: "CYMBAL"}
    c = by_pad[pad]
    if c == "CYMBAL" and f["bright"] < 2500: return "FX"                    # pads of birds and rooms
    if c in ("PERC", "TOM") and f["dur"] > 1.2: return "FX"
    return c


def note(hz):
    if hz <= 0: return None, 0
    m = int(round(69 + 12 * np.log2(hz / 440)))
    return NOTE_NAMES[m % 12] + str(m // 12 - 1), m


def character(cat, names, f, cut):
    """One word for how it sounds, against the middle of its own category (cut = medians)."""
    n = " ".join(names)
    dusty = f["top"] < cut["top"] * 0.5                                    # little top end for its kind (SP-1200 / tape)
    if cat == "KICK":
        if f["decay"] >= cut["decay"]: return "BOOM" if f["bright"] < cut["bright"] else "THUMP"
        return "PUNCH" if f["bright"] < cut["bright"] else "KNOCK"
    if cat == "SNARE":
        if dusty: return "DUSTY"
        if f["decay"] >= cut["decay"] * 1.6: return "ROOM"
        return "CRACK" if f["bright"] >= cut["bright"] else "FAT"
    if cat == "CLAP":
        if f["width"] >= max(0.35, cut["width"]): return "WIDE"
        if f["decay"] >= cut["decay"] * 1.5: return "ROOM"
        return "DUSTY" if dusty else "TIGHT"
    if cat == "RIM":
        return "SNAP" if has(n, "snap") else ""
    if cat == "HAT":
        if dusty: return "DUSTY"
        return "CRISP" if f["bright"] >= cut["bright"] else "DARK"
    if cat == "OPEN HAT":
        return "LONG" if f["dur"] >= cut["dur"] else "SHORT"
    if cat == "808":
        nm, _ = note(f["pitch"])
        size = "LONG" if f["dur"] >= 1.5 else "SHORT" if f["dur"] < 0.8 else ""
        return " ".join(x for x in (nm, size) if x)
    if cat == "TOM":
        if has(n, "low tom"): return "LOW"
        if has(n, "high tom"): return "HIGH"
        return "LOW" if f["pitch"] < cut["pitch"] * 0.85 else "HIGH" if f["pitch"] > cut["pitch"] * 1.2 else "MID"
    if cat == "CYMBAL":
        if has(n, "ride"): return "RIDE"
        return "CRASH" if f["dur"] >= 1.0 else "SHORT"
    if cat == "PERC":
        for word, kind in (("shaker", "SHAKER"), ("spshak", "SHAKER"), ("tamb", "TAMB"), ("clave", "CLAVE"),
                           ("triangle", "TRIANGLE"), ("weirdtriangle", "TRIANGLE"), ("conga", "CONGA"),
                           ("bongo", "BONGO"), ("cowbell", "BELL"), ("beads", "BEADS")):
            if has(n, word): return kind
        if f["bright"] < 2200: return "WOOD"
        return "METAL" if f["bright"] > 6500 else "CLICK" if f["dur"] < 0.07 else "HIT"
    if cat == "FX":
        if f["attack"] > 0.55 or has(n, "rev", "reverse"): return "REVERSE"
        return "ATMOS" if f["dur"] > 2 else "HIT"
    return ""


# The first word of a name says its category (SoundType.forStockName in SoundLibraryView.swift).
PERC_WORDS = {"SHAKER", "TAMB", "CLAVE", "TRIANGLE", "CONGA", "BONGO", "BELL", "BEADS"}
def display(cat, char):
    if cat == "PERC" and char in PERC_WORDS: return char
    if cat == "RIM" and char == "SNAP": return "SNAP"
    return " ".join(x for x in (cat, char) if x)


def main(apply):
    manifest = json.load(open(os.path.join(STOCK, "manifest.json")))
    by_hash, file_hash = {}, {}
    for a in manifest["assignments"]:
        f = a["file"]
        if f not in file_hash: file_hash[f] = hashlib.md5(open(os.path.join(STOCK, f), "rb").read()).hexdigest()
        d = by_hash.setdefault(file_hash[f], {"files": [], "names": [], "pads": collections.Counter(), "kits": []})
        if f not in d["files"]: d["files"].append(f)
        if a["displayName"] not in d["names"]: d["names"].append(a["displayName"])
        d["pads"][a["pad"]] += 1
        if a["kitID"] not in d["kits"]: d["kits"].append(a["kitID"])
    sounds = []
    for h, d in by_hash.items():
        keep = sorted(d["files"])[0]
        f = features(os.path.join(STOCK, keep))
        pad = d["pads"].most_common(1)[0][0]
        tags = sorted(set().union(*(TAGS_OF[k] for k in d["kits"])))
        sounds.append({"hash": h, "old": d["files"], "oldNames": d["names"], "pad": pad, "kits": d["kits"], "tags": tags,
                       "category": category(d["names"], pad, f), "feat": f})
    cuts = {}
    for cat in {s["category"] for s in sounds}:
        g = [s["feat"] for s in sounds if s["category"] == cat]
        cuts[cat] = {k: float(np.median([x[k] for x in g])) for k in ("decay", "bright", "width", "dur", "top", "pitch")}
    for s in sounds:
        s["character"] = character(s["category"], s["oldNames"], s["feat"], cuts[s["category"]])
        s["base"] = display(s["category"], s["character"])
    # Number each group from darkest to brightest (808s from low to high).
    order = ["KICK", "SNARE", "CLAP", "RIM", "HAT", "OPEN HAT", "808", "PERC", "TOM", "CYMBAL", "FX"]
    groups = collections.defaultdict(list)
    for s in sounds: groups[s["base"]].append(s)
    for base, g in groups.items():
        g.sort(key=lambda s: (s["feat"]["pitch"] if s["category"] in ("808", "TOM") else s["feat"]["bright"], s["hash"]))
        for i, s in enumerate(g, 1):
            s["name"] = f"{base} {i:02d}"
            s["file"] = "bb_" + re.sub(r"[^a-z0-9]+", "_", s["name"].lower().replace("#", "s")).strip("_") + ".wav"
    sounds.sort(key=lambda s: (order.index(s["category"]), s["name"]))
    assert len({s["name"] for s in sounds}) == len(sounds) and len({s["file"] for s in sounds}) == len(sounds)
    counts = collections.Counter(s["category"] for s in sounds)
    print(len(sounds), "sounds;", {c: counts[c] for c in order})
    for s in sounds: print(f'{s["name"]:22} <- {", ".join(s["oldNames"])[:70]}')
    if not apply: return
    for s in sounds:
        first, *dupes = sorted(s["old"])
        subprocess.run(["git", "mv", "-f", os.path.join(STOCK, first), os.path.join(STOCK, s["file"])], check=True)
        for d in dupes: subprocess.run(["git", "rm", "-q", os.path.join(STOCK, d)], check=True)
    leftovers = [f for f in os.listdir(STOCK) if f.endswith(".wav") and f not in {s["file"] for s in sounds}]
    for f in leftovers: subprocess.run(["git", "rm", "-q", os.path.join(STOCK, f)], check=True)   # in no kit
    catalog = [{k: s[k] for k in ("file", "name", "category", "character", "tags", "feat")} for s in sounds]
    with open(CATALOG, "w") as out:
        out.write("[\n" + ",\n".join(json.dumps(c, sort_keys=True) for c in catalog) + "\n]\n")
    print("wrote", CATALOG, "and renamed", len(sounds), "files;", len(leftovers), "unused files removed")


if __name__ == "__main__":
    main("--apply" in sys.argv)
