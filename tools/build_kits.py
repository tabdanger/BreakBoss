#!/usr/bin/env python3
"""Builds the factory KITS from the sorted stock sounds (tools/stock_sounds.json).

  python3 tools/build_kits.py

Writes BreakBoss.swiftpm/Resources/StockSamples/manifest.json (which sound plays on each pad of
each kit, and every sound's name) and BreakBoss.swiftpm/FactoryKits.swift (the kit list).

First the 42 A/B kits, unchanged since Oct 17: two kits per genre, A and B,
for the genres in the drum research (/mnt/project-files/research/realistic-drums-and-genres.md)
plus four texture genres. Every pad gets a sound of its own kind (kick pad: a KICK, and so on),
chosen by the genre of the old kits it came from and by how it sounds (dusty, roomy, bright,
long 808...). The same sound is never in both kits of a genre, and sounds already used elsewhere
are passed over when there is a close second, so the whole library gets played.

Then the named kits in tools/kit_catalog.py, so every mode bank holds at least 20 kits under every
genre tab, picked the same way with the mode bank's leanings added.
"""
import collections, json, math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sort_stock_sounds import TAGS_OF          # the genre each old kit was made for
import kit_catalog                             # the genre tabs and the named kits that fill them

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
SWIFT = os.path.join(ROOT, "BreakBoss.swiftpm", "FactoryKits.swift")
SOUNDS = json.load(open(os.path.join(ROOT, "tools", "stock_sounds.json")))
# The multisampled acoustic drums (tools/build_acoustic_sounds.py): only the ACOUSTIC_KITS play them.
ACOUSTIC = json.load(open(os.path.join(ROOT, "tools", "acoustic_sounds.json")))

# What each pad holds (KitLibrary.swift, Pad): category, and the character it leans to.
PADS = [("KICK", None), ("SNARE", None), ("CLAP", None), ("RIM", None), ("HAT", None), ("OPEN HAT", None),
        ("808", None), ("PERC", None), ("PERC", None), ("TOM", "LOW"), ("TOM", "HIGH"), ("CYMBAL", None)]

# Genre: (name, id, mode list style, tempo, synth voice, tags, likes)
# likes: feature leanings, + more / - less, in standard deviations of that kind of sound:
#   dusty (less top end), room (longer snare / clap), dark (lower brightness on kick / snare / hat),
#   bright (snare and hat brightness), long808, wide (clap stereo width), punch (short kick)
#   perc: the PERC characters wanted on pads 8 and 9, cym: CRASH or RIDE on pad 12, fx: FX on the perc pads
GENRES = [
    ("TRAP", "trap", "trapAtlanta", 140, "modernTrap", ["trap", "rage", "dark"], {"bright": 0.6, "long808": 0.8, "perc": ["HIT", "WOOD", "CLICK"]}),
    ("ALT TRAP", "alt-trap", "trapAtlanta", 155, "modernTrap", ["rage", "trap", "electronic"], {"bright": 0.4, "long808": 1.0, "perc": ["HIT", "METAL", "CLICK"]}),
    ("DRILL", "drill", "trapMemphis", 140, "drumMastery", ["drill", "trap", "dark"], {"long808": -0.6, "bright": 0.4, "perc": ["BELL", "METAL", "HIT"]}),
    ("UK DRILL", "uk-drill", "trapMemphis", 142, "drumMastery", ["drill", "dark", "trap"], {"long808": 0.8, "bright": 0.8, "perc": ["WOOD", "CLICK", "HIT"]}),
    ("NY DRILL", "ny-drill", "trapMemphis", 144, "modernTrap", ["drill", "trap", "rage"], {"long808": 1.0, "punch": 0.6, "perc": ["HIT", "WOOD"]}),
    ("DETROIT 2026", "detroit-2026", "trapAtlanta", 96, "modernTrap", ["detroit", "trap", "west"], {"bright": 0.8, "perc": ["WOOD", "HIT", "CLICK"]}),
    ("BAY AREA 2026", "bay-area-2026", "baySlap", 100, "baySlap", ["west", "trap", "detroit"], {"wide": 0.8, "punch": 0.4, "perc": ["HIT", "WOOD", "SHAKER"]}),
    ("RNB", "rnb", "rnb", 76, "westBounce", ["rnb", "dark", "soul"], {"dark": 0.6, "long808": 0.8, "perc": ["SHAKER", "WOOD", "HIT"]}),
    ("UK RNB", "uk-rnb", "rnb", 100, "westBounce", ["rnb", "world", "soul"], {"dark": 0.3, "perc": ["SHAKER", "TAMB", "WOOD"]}),
    ("NEO SOUL", "neo-soul", "neoSoul", 86, "neoSoul", ["soul", "jazz", "boombap"], {"dusty": 0.6, "dark": 0.5, "perc": ["SHAKER", "TAMB", "WOOD"], "cym": "RIDE"}),
    ("DILLA TIME", "dilla-time", "neoSoul", 90, "neoSoul", ["soul", "boombap", "jazz"], {"dusty": 1.0, "perc": ["SHAKER", "TAMB", "CLAVE", "WOOD"], "cym": "RIDE"}),
    ("BOOM BAP", "boom-bap", "boomBap", 92, "funkBreak", ["boombap", "soul", "funk"], {"dusty": 0.8, "bright": 0.3, "perc": ["TAMB", "SHAKER", "WOOD"]}),
    ("90S RAP", "90s-rap", "boomBap", 94, "funkBreak", ["boombap", "west", "funk"], {"dusty": 0.5, "punch": 0.4, "perc": ["SHAKER", "TAMB", "HIT"]}),
    ("70S SOUL", "70s-soul", "funkBreak", 100, "gospelChops", ["funk", "soul", "90srnb"], {"room": 0.8, "dusty": 0.4, "perc": ["TAMB", "SHAKER", "CONGA"]}),
    ("80S BREAKS", "80s-breaks", "heavyBreak", 100, "heavyBreak", ["funk", "boombap", "soul"], {"room": 1.0, "dusty": 0.6, "perc": ["BONGO", "CONGA", "TAMB", "SHAKER"]}),
    ("90S RNB", "90s-rnb", "pop90s", 104, "west90s", ["90srnb", "pop80", "rnb"], {"wide": 0.6, "bright": 0.5, "perc": ["SHAKER", "TAMB", "HIT"]}),
    ("ROCK", "rock", "heavyBreak", 120, "heavyBreak", ["funk", "pop80", "boombap"], {"room": 1.4, "punch": -0.4, "perc": ["TAMB", "BELL", "SHAKER"]}),
    ("AFROBEATS", "afrobeats", "afrobeats", 106, "baySlap", ["world", "amapiano"], {"perc": ["CONGA", "BONGO", "SHAKER", "WOOD"]}),
    ("AMAPIANO", "amapiano", "amapiano", 112, "modernTrap", ["amapiano", "world"], {"perc": ["WOOD", "SHAKER", "CLICK"]}),
    ("WORLD PERC", "world-perc", "latin", 112, "neoSoul", ["world", "amapiano", "soul"], {"perc": ["CONGA", "BONGO", "CLAVE", "TAMB", "BEADS"]}),
    ("FX LAB", "fx-lab", "experimental", 100, "looseBreak", ["electronic", "rage", "dark"], {"fx": True, "perc": ["METAL", "HIT"]}),
]

# Old kit identifiers (saved projects, user kits) open the nearest new kit.
OLD_TO_GENRE = [
    ("drill", "drill"), ("detroit", "detroit-2026"), ("rage", "alt-trap"), ("dark", "trap"), ("trap", "trap"),
    ("west", "bay-area-2026"), ("90srnb", "90s-rnb"), ("rnb", "rnb"), ("jazz", "dilla-time"), ("boombap", "boom-bap"),
    ("soul", "neo-soul"), ("funk", "70s-soul"), ("pop80", "90s-rnb"), ("amapiano", "amapiano"), ("world", "afrobeats"),
    ("electronic", "fx-lab"),
]
OLD_IDS = """2000s-rnb 80s-pop 90s-pop afrobeats amapiano analog-funk atl-trap bay-slap boom-bap cole-world danger-drums
danger-drums-2 dark-experimental detroit dirty-soul drill-nights drum-mastery funk-break g-80s-funk-a g-80s-funk-b
g-80s-pop-a g-80s-pop-b g-80s-rnb-a g-80s-rnb-b g-90s-rnb-a g-90s-rnb-b g-amapiano-a g-amapiano-b g-boom-bap-a
g-boom-bap-b g-dark-trap-a g-dark-trap-b g-detroit-a g-detroit-b g-drill-a g-drill-b g-edm-a g-edm-b g-house-a
g-house-b g-jazz-a g-jazz-b g-neo-soul-a g-neo-soul-b g-rnb-a g-rnb-b g-soul-rnb-a g-soul-rnb-b
g-south-african-rnb-a g-south-african-rnb-b g-techno-a g-techno-b g-trap-a g-trap-b g-west-coast-a g-west-coast-b
gospel-chops heavy-break knock-gang live-pop live-soul lo-fi loose-break memphis-trap modern-rnb modern-trap
neo-soul perc-loops rage resampled-textures s-atl-wave-a s-atl-wave-b s-carolina-soul-a s-carolina-soul-b
s-houston-queen-a s-houston-queen-b s-la-lyricist-a s-la-lyricist-b s-late-night-rnb-a s-late-night-rnb-b
s-rockstar-bounce-a s-rockstar-bounce-b s-soft-soul-a s-soft-soul-b s-toronto-nights-a s-toronto-nights-b
s-vamp-rage-a s-vamp-rage-b shakers six-side sky-textures toronto-weird trap-soul vintage-rnb west-90s west-bounce
west-end world-latin""".split()


def zscores():
    """Each feature as standard deviations from the middle of its own category."""
    z = {}
    for cat in {s["category"] for s in SOUNDS}:
        g = [s for s in SOUNDS if s["category"] == cat]
        for k in ("bright", "top", "decay", "dur", "width"):
            vals = [math.log(1 + s["feat"][k]) for s in g]
            m = sum(vals) / len(vals); sd = (sum((v - m) ** 2 for v in vals) / len(vals)) ** 0.5 or 1
            for s, v in zip(g, vals): z.setdefault(s["file"], {})[k] = (v - m) / sd
    return z
Z = zscores()


def score(s, pad, tags, likes):
    cat, want = PADS[pad]
    z = Z[s["file"]]
    sc = sum((3, 2, 1)[i] for i, t in enumerate(tags) if t in s["tags"])
    if want and s["character"] == want: sc += 3
    if cat in ("KICK", "SNARE", "CLAP", "HAT"):
        sc -= likes.get("dusty", 0) * z["top"]
        sc -= likes.get("dark", 0) * z["bright"]
    if cat in ("SNARE", "HAT", "OPEN HAT"): sc += likes.get("bright", 0) * z["bright"]
    if cat in ("SNARE", "CLAP"): sc += likes.get("room", 0) * z["decay"]
    if cat == "CLAP": sc += likes.get("wide", 0) * z["width"]
    if cat == "KICK": sc -= likes.get("punch", 0) * z["decay"]
    if cat == "808": sc += likes.get("long808", 0) * z["dur"]
    if cat == "PERC" or (cat == "FX" and likes.get("fx")):
        perc = likes.get("perc", [])
        if s["character"] in perc: sc += 4 - perc.index(s["character"]) * 0.6
    if cat == "CYMBAL":
        sc += 3 if s["character"] == likes.get("cym", "CRASH") else 0
    return sc


def pool(pad, likes):
    cat = PADS[pad][0]
    out = [s for s in SOUNDS if s["category"] == cat]
    if cat == "PERC" and likes.get("fx"): out += [s for s in SOUNDS if s["category"] == "FX" and s["feat"]["dur"] < 2.5]
    if cat == "RIM": out += [s for s in SOUNDS if s["category"] == "SNARE" and s["feat"]["dur"] < 0.15]
    return out


def root_hz(s):
    """The kit's 808 tuning from its 808 sound, on the nearest note between D1 and A#1 (the 808 lane plays from it)."""
    hz = s["feat"]["pitch"] or 43.65
    while hz > 60: hz /= 2
    while hz < 36: hz *= 2
    m = round(69 + 12 * math.log2(hz / 440))
    return round(440 * 2 ** ((m - 69) / 12), 2)


def old_mode(style):
    """The bank each A/B kit has lived in (KitDefinition.preferredMode before the genre tabs)."""
    if style in ("afrobeats", "latin", "experimental", "amapiano"): return "texture"
    if style in ("neoSoul", "gospel", "funkBreak", "looseBreak", "heavyBreak", "west90s", "boomBap", "loFi",
                 "pop80s", "pop90s", "pop"): return "vintage"
    return "modern"


def slug(name):
    return "".join(c if c.isalnum() else "-" for c in name.lower().replace("&", "and")).strip("-").replace("--", "-").replace("--", "-")


def build():
    uses = collections.Counter()
    kits, assignments = [], []
    by_file = {s["file"]: s for s in SOUNDS}
    taken = collections.defaultdict(set)     # genre -> sounds its kits already play (kits of a genre share none)
    seed = 601
    for name, gid, style, tempo, voice, tags, likes in GENRES:
        for side in ("A", "B"):
            files = []
            for pad in range(12):
                cands = [s for s in pool(pad, likes) if s["file"] not in taken[name] and s["file"] not in files]
                best = max(cands, key=lambda s: (score(s, pad, tags, likes) - 1.2 * uses[s["file"]], s["file"]))
                files.append(best["file"]); taken[name].add(best["file"]); uses[best["file"]] += 1
            kid = f"{gid}-{side.lower()}"
            for pad, f in enumerate(files):
                assignments.append({"kitID": kid, "pad": pad, "file": f, "displayName": by_file[f]["name"]})
            kits.append((kid, f"{name} {side}", voice, style, tempo, seed, root_hz(by_file[files[6]]),
                         old_mode(style), kit_catalog.OLD_FAMILY[name], name))
            seed += 1
    # The named kits: each mode bank, each genre tab, each genre in it.
    seen_sets = {frozenset(a["file"] for a in assignments if a["kitID"] == k[0]) for k in kits}
    seed = 1001
    for (mode, family), genres in kit_catalog.KITS.items():
        for genre, style, tempo, voice, tags, likes, names in genres:
            leans = dict(likes)
            for k, v in kit_catalog.MODE_LIKES[mode].items(): leans[k] = leans.get(k, 0) + v
            leans.setdefault("perc", kit_catalog.FAMILY_PERC[family])
            for name in names:
                rng = random.Random(seed)
                jitter = collections.defaultdict(lambda: rng.random() * 0.8)   # a little of each kit's own taste
                files = []
                for pad in range(12):
                    cands = [s for s in pool(pad, leans) if s["file"] not in taken[genre] and s["file"] not in files]
                    best = max(cands, key=lambda s: (score(s, pad, tags, leans) - 1.2 * uses[s["file"]] + jitter[(pad, s["file"])], s["file"]))
                    files.append(best["file"]); taken[genre].add(best["file"]); uses[best["file"]] += 1
                assert frozenset(files) not in seen_sets, name
                seen_sets.add(frozenset(files))
                kid = slug(name)
                for pad, f in enumerate(files):
                    assignments.append({"kitID": kid, "pad": pad, "file": f, "displayName": by_file[f]["name"]})
                kits.append((kid, name, voice, style, tempo, seed, root_hz(by_file[files[6]]), mode, family, genre))
                seed += 1
    # The live acoustic kits, last, so every kit above keeps its sounds.
    acoustic = {s["name"]: s for s in ACOUSTIC}
    for name, mode, family, genre, style, tempo, voice, tags, likes, picks in kit_catalog.ACOUSTIC_KITS:
        leans = dict(likes)
        for k, v in kit_catalog.MODE_LIKES[mode].items(): leans[k] = leans.get(k, 0) + v
        files, names = [], []
        for pad in range(12):
            if pad in picks:
                a = acoustic[picks[pad]]
                assert a["category"] == PADS[pad][0] or (pad == 3 and a["category"] == "SNARE"), (name, pad)
                files.append(a["file"]); names.append(a["name"])
                continue
            cands = [s for s in pool(pad, leans) if s["file"] not in taken[genre] and s["file"] not in files]
            best = max(cands, key=lambda s: (score(s, pad, tags, leans) - 1.2 * uses[s["file"]], s["file"]))
            files.append(best["file"]); names.append(best["name"]); uses[best["file"]] += 1
            taken[genre].add(best["file"])
        kid = slug(name)
        for pad, f in enumerate(files):
            assignments.append({"kitID": kid, "pad": pad, "file": f, "displayName": names[pad]})
        kits.append((kid, name, voice, style, tempo, seed, root_hz(by_file[files[6]]), mode, family, genre))
        seed += 1
    return kits, assignments, uses


def main():
    kits, assignments, uses = build()
    with open(os.path.join(STOCK, "manifest.json"), "w") as out:
        # "sounds": the whole library (the sound menu lists them all, even those in no kit)
        sounds = [{"file": x["file"], "name": x["name"]} for x in SOUNDS + ACOUSTIC]
        json.dump({"version": 1, "assignments": assignments, "sounds": sounds}, out, separators=(",", ":"))
    ids = [k[0] for k in kits]
    assert len(set(ids)) == len(ids) and len({k[1] for k in kits}) == len(kits), "kit ids and names are unique"
    for mode in kit_catalog.MODE_LIKES:
        for fam in kit_catalog.FAMILIES:
            n = sum(1 for k in kits if k[7] == mode and k[8] == fam)
            assert n >= 20, (mode, fam, n)
    retired = {}
    for old in OLD_IDS:
        tags = TAGS_OF[old]
        genre = next((g for t, g in OLD_TO_GENRE if t in tags), "trap")
        retired[old] = f"{genre}-a"
    assert all(v in ids for v in retired.values()) and not set(retired) & set(ids)
    lines = ["// Copyright © 2026 Tyrone Dangerfield. All rights reserved.",
             "// Made by tools/build_kits.py from the sorted stock sounds (tools/stock_sounds.json): edit that, not this.",
             "import Foundation", "", "extension KitLibrary {",
             "    /// The A/B kits of the research genres, then the named kits that give every mode bank",
             "    /// at least 20 kits under each genre tab (tools/kit_catalog.py).",
             "    static let factory: [KitDefinition] = table(factoryTable)",
             "",
             "    /// One kit a line: id | name | synth voice | groove style | tempo | seed | 808 Hz | mode bank | genre tab | genre.",
             "    /// Text, not Swift calls, so the Release build stays quick with hundreds of kits.",
             '    private static let factoryTable = """']
    for k, n, v, st, t, sd, hz, m, f, g in kits:
        assert "|" not in n + g + f
        lines.append(f"{k}|{n}|{v}|{st}|{t}|{sd}|{hz}|{m}|{f}|{g}")
    lines += ['"""', "", "    /// The kits before Oct 17: saved projects and your kits that used one open the nearest new kit.",
              "    static let retired: [String: String] = ["]
    lines += [f'        "{o}": "{n}",' for o, n in sorted(retired.items())]
    lines[-1] = lines[-1].rstrip(",")
    lines += ["    ]", "}", ""]
    open(SWIFT, "w").write("\n".join(lines))
    used = len(uses); print(len(kits), "kits,", len(assignments), "pads,", used, "of", len(SOUNDS), "sounds used")
    by = collections.Counter(s["category"] for s in SOUNDS if s["file"] in uses)
    print("used by category:", dict(by))


if __name__ == "__main__":
    main()
