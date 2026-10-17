#!/usr/bin/env python3
"""Names every stock sound after the folder and file it came from in Tyrone's packs (Oct 17).

  python3 tools/name_stock_sounds.py            # dry run: prints old name -> new name
  python3 tools/name_stock_sounds.py --apply    # writes tools/stock_sounds.json and tools/stock_sources.json

The original folder decides what a sound is: a sound from a kicks folder is a KICK, from a claps folder a
CLAP, and so on. The name keeps the sound's own name from the pack and ends in what it is:
"[Kick] Astronomy" -> "ASTRONOMY KICK", "Kick (Booked)" -> "BOOKED KICK", "[Tom] 3" -> "NO 3 TOM",
"Throne Open Hihat" -> "THRONE OPEN HIHAT". When the file's own name already says what it is more exactly
(a shaker in a percs folder, a rimshot in a snares folder, "Clap Snare" layers), that word wins.
The same source rendered twice (an 808 tuned to two keys, a kick with and without drive) gets the key or
V2, V3 before the last word. Then run tools/build_kits.py to rebuild the kits and the manifest.

Where each WAV came from: the files are matched by content to the bank before the Oct 17 rebuild
(git 4550d36), whose tools and Build_Notes/STOCK_SAMPLE_PROVENANCE.json name each source path.
The genre and artist kits (bb_g-, bb_s-) kept only the file's name; their folder is the pool the old
tools drew that pad from (tools/build_genre_kits.py classify, build_artist_kits.py new_pools).
"""
import collections, json, os, re, subprocess, sys, tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK_DIR = "BreakBoss.swiftpm/Resources/StockSamples"
CATALOG = os.path.join(ROOT, "tools", "stock_sounds.json")
SOURCES = os.path.join(ROOT, "tools", "stock_sources.json")
BEFORE = "4550d36"
ROLE_OF_PAD = ["kick", "snare", "clap", "rim", "hat", "open", "808", "perc", "perc", "tom", "tom", "cym"]

# The kind of sound each original folder holds (None: a mixed folder, the file name decides).
FOLDER_KIND = {
    "7-Kicks/Kicks": "KICK", "10-Snares/Snares": "SNARE", "8-Claps/Claps": "CLAP", "1-Rims/Rims": "RIM",
    "5-Snaps/Snaps": "SNAP", "4-Hi-Hats/Hi Hats": "HAT", "2-Open-Hats/Open Hats": "OPEN HAT", "11-808s/808s": "808",
    "6-Percs/Percs": "PERC",
    "Kicks 2": "KICK", "Kicks 2.zip.zip": "KICK", "Snares 2": "SNARE", "Claps 2": "CLAP", "Rims 2": "RIM",
    "Snaps 2": "SNAP", "Hi Hats 2": "HAT", "Open Hats 2": "OPEN HAT", "808 2": "808", "Cymbals & Crashes 2": "CYMBAL",
    "Textures 2": "TEXTURE", "Risers 2": "RISER", "Percussive One Shots 2": "PERC", "Snares + Claps 2": None,
    "Vintage/kicks": "KICK", "Vintage/snares": None, "Vintage/hats": None, "Danger Drums": None,
    "Danger Demon/Kicks": "KICK", "Danger Demon/Snares": "SNARE", "Danger Demon/Claps": "CLAP",
    "Danger Demon/HH": "HAT", "Danger Demon/OHH": "OPEN HAT", "Danger Demon/808": "808", "Danger Demon/Percs": "PERC",
    "Danger OG Trap/Kicks": "KICK", "Danger OG Trap/Snares": "SNARE", "Danger OG Trap/Claps": "CLAP",
    "Danger OG Trap/HH": "HAT", "Danger OG Trap/OHH": "OPEN HAT", "Danger OG Trap/808": "808",
    "Danger OG Trap/Percs": "PERC",
}
# Words a name can end in, and the library category each one sorts into.
KIND_WORDS = [  # longest first
    ("OPEN HIHAT", "OPEN HAT"), ("OPEN HAT", "OPEN HAT"), ("TRIANGLE RISER", "FX"), ("DJ SCRATCH", "FX"),
    ("KICK", "KICK"), ("SNARE", "SNARE"), ("CLAP", "CLAP"), ("RIMSHOT", "RIM"), ("RIM", "RIM"), ("SNAP", "RIM"),
    ("HIHAT", "HAT"), ("HAT", "HAT"), ("808", "808"), ("TOM", "TOM"), ("CYMBAL", "CYMBAL"), ("CRASH", "CYMBAL"),
    ("RIDE", "CYMBAL"), ("SHAKER", "PERC"), ("TAMB", "PERC"), ("TAMBOURINE", "PERC"), ("TRIANGLE", "PERC"),
    ("COWBELL", "PERC"), ("CLAVE", "PERC"), ("PERC", "PERC"), ("FX", "FX"), ("SFX", "FX"), ("LAZER", "FX"),
    ("RISER", "FX"), ("TEXTURE", "FX"),
]
CATEGORY_OF = dict(KIND_WORDS)
# Words in a file name that say what it is (kept, moved to the end), by the kind of folder it is in.
SAYS = {"PERCUSSION": "PERC", "PERCS": "PERC", "TOMS": "TOM", "HH": "HAT", "OHH": "OPEN HAT", "SHAK": "SHAKER"}


def git(*a): return subprocess.check_output(["git", "-C", ROOT, *a])


def old_tools():
    d = tempfile.mkdtemp()
    for t in ("apply_kit_pack", "apply_vintage_pack", "build_genre_kits", "build_artist_kits", "prepare_stock_samples"):
        open(os.path.join(d, t + ".py"), "wb").write(git("show", f"{BEFORE}:tools/{t}.py"))
    sys.path.insert(0, d)
    import apply_kit_pack, apply_vintage_pack  # noqa: E402
    return apply_kit_pack, apply_vintage_pack


def blobs(ref):
    out = {}
    for line in git("ls-tree", ref, STOCK_DIR + "/").decode().splitlines():
        meta, path = line.split("\t")
        if path.endswith(".wav"): out[path.rsplit("/", 1)[1]] = meta.split()[2]
    return out


def sources():
    """Every current WAV -> its original folder and file name (or the pool's folder and the name kept)."""
    akp, avp = old_tools()
    old = json.loads(git("show", f"{BEFORE}:{STOCK_DIR}/manifest.json"))["assignments"]
    prov = json.load(open(os.path.join(ROOT, "Build_Notes", "STOCK_SAMPLE_PROVENANCE.json")))
    out_src = {a["outputFile"]: a["source"] for a in prov["assignments"]}
    by_blob = collections.defaultdict(list)
    for f, b in blobs(BEFORE).items(): by_blob[b].append(f)
    by_old = collections.defaultdict(list)
    for a in old: by_old[a["file"]].append(a)
    result = {}
    for f, b in sorted(blobs("HEAD").items()):
        uses, path = [], None
        for o in by_old_files(by_blob[b]):
            for a in by_old[o]:
                uses.append({"kit": a["kitID"], "pad": a["pad"], "name": a["displayName"]})
                if o.startswith("bb_kp2-"):
                    e = akp.KITS[a["kitID"]][1][a["pad"]]; path = e[0] if isinstance(e, tuple) else e
                elif o.startswith("bb_vtg-"):
                    path = "Vintage/" + avp.KITS[a["kitID"]][a["pad"]][0]
                elif not o.startswith(("bb_g-", "bb_s-")):
                    path = out_src[o]
        result[f] = {"path": path, "uses": uses} if path else {"name": uses[0]["name"], "uses": uses}
    # A genre / artist kit sound the other kits also used: the same file, so the same folder.
    known = collections.defaultdict(set)
    for r in result.values():
        if "path" in r: known[pretty(r["path"])].add(r["path"])
    for r in result.values():
        if "path" in r: continue
        paths = known.get(r["name"])
        if paths: r["path"] = sorted(paths)[0]
        else: r["pool"] = pool_folder(r["uses"])
    return result


def pretty(path):
    """The display name the old genre kits gave a source file (tools/build_genre_kits.py at 4550d36)."""
    stem = path.rsplit("/", 1)[1][:-4]
    stem = re.sub(r"\s*-\s*\(?@prod\.by\.?iiinfinite\)?", "", stem)
    stem = re.sub(r"^\[[^\]]+\]\s*", "", stem).replace(" (1)", "").replace("RImshot", "Rimshot")
    if path.startswith("Vintage/"): stem = stem.replace(" B", "")
    return stem.upper()


def by_old_files(files): return sorted(files)


def pool_folder(uses):
    """The folder a genre / artist kit sound was drawn from: its pad's pool, read the way the old tools filled it."""
    name = uses[0]["name"]; roles = {ROLE_OF_PAD[u["pad"]] for u in uses}
    m = re.match(r"(DEMON|OG) ", name)
    if m:
        pack = "Danger Demon" if m.group(1) == "DEMON" else "Danger OG Trap"
        low = name.lower()
        if any(w in low for w in ("rim", "toms", "cymbal", "percs", "fx", "triangle", "shak", "hardddd")) or roles <= {"perc", "tom", "cym"}:
            return pack + "/Percs"
        role = sorted(roles)[0]
        return pack + "/" + {"kick": "Kicks", "snare": "Snares", "clap": "Claps", "hat": "HH", "open": "OHH", "808": "808"}[role]
    if re.match(r"(KICK|SNARE|CLAP|RIM|HIHAT|OPEN HAT|PERCUSSION) \(", name): return "Danger Drums"
    words = name.split()
    if words[-1] in ("HIHAT", "RIDE", "SHAKER") or "HIHAT" in words or words[:1] == ["FINESSE"]: return "Vintage/hats"
    if words[-1] == "RIMSHOT": return "Vintage/snares"
    if words[-1] in ("KICK",): return "Kicks 2.zip.zip" if len(words) > 1 else "Kicks 2"
    if "SNARE" in words or "CLAP" in words: return "Snares + Claps 2"
    if name.startswith("TAMB"): return "Percussive One Shots 2"
    # One- or two-word names with no kind word are the Archive's ("[Kind] Name"): the pad's pool folder.
    if roles == {"clap", "perc"} or roles == {"perc"}: return "Snaps 2"
    return {"kick": "Kicks 2", "snare": "Snares 2", "clap": "Claps 2", "rim": "Rims 2", "hat": "Hi Hats 2",
            "open": "Open Hats 2", "808": "808 2", "cym": "Cymbals & Crashes 2", "tom": "Percussive One Shots 2"}[sorted(roles)[0]]


def base_name(src):
    """The sound's own name, upper case, and the kind its brackets or folder give it."""
    if "path" in src:
        folder, stem = src["path"].rsplit("/", 1)
        stem = stem[:-4]
        stem = re.sub(r"\s*-\s*\(?@prod\.by\.?iiinfinite\)?", "", stem)
        tag = re.match(r"\[([^\]]+)\]\s*", stem)
        if tag: stem = stem[tag.end():]
        tag = tag.group(1).upper().replace("HI HAT", "HAT") if tag else None
        if folder == "Cymbals & Crashes 2":
            t2 = re.match(r"\[([^\]]+)\]\s*", stem)
            if t2: tag, stem = t2.group(1).upper(), stem[t2.end():]
        stem = stem.replace(" (1)", "").replace("RImshot", "Rimshot")
        if folder.startswith("Vintage/"): stem = stem.replace(" B", "")
    else:
        folder, stem, tag = src["pool"], src["name"], None
        stem = re.sub(r"^(DEMON|OG) ", "", stem)
    stem = re.sub(r"[^A-Z0-9# ]", " ", stem.upper())
    stem = stem.replace("WEIRDTRIANGLE", "WEIRD TRIANGLE").replace(" - ", " ")
    stem = re.sub(r"\b(TOMS?|CLAP|SNARE|KICK|SPSHAK|HH|OHH)(\d+)\b", r"\1 \2", stem)
    stem = re.sub(r"\bSPSHAK\b", "SP SHAK", stem)
    words = stem.split()
    pack = {"Danger Demon": "DEMON", "Danger OG Trap": "OG", "Danger Drums": "DANGER"}.get(folder.split("/")[0])
    return folder, words, tag, pack


def kind_of(folder, words, tag):
    """What the sound is: the bracket tag, else a kind word in its name, else its folder."""
    if tag: return {"SFX": "SFX", "DJ SCRATCH": "DJ SCRATCH"}.get(tag, tag)
    text = " ".join(SAYS.get(w, w) for w in words)
    fk = FOLDER_KIND.get(folder)
    # The last kind word in the name ("ISSA BOUNCE CLAP SNARE" is a snare layer, "FINESSE SHAKER" a shaker);
    # a longer phrase wins over the word inside it ("CLICKED OPEN HIHAT" is an open hat, not a hat).
    taken, found = [], None
    for w, _ in KIND_WORDS:
        for m in re.finditer(r"\b" + re.escape(w) + r"\b", text):
            if any(a <= m.start() < b for a, b in taken): continue
            taken.append((m.start(), m.end()))
            if found is None or m.start() > found[0]: found = (m.start(), w)
    if found:
        w = found[1]
        # A folder that names one kind wins over a kind word that isn't it (a "Reverse Kick" in the percs folder).
        if fk and CATEGORY_OF[w] != CATEGORY_OF.get(fk) and fk != "PERC": return fk
        if fk == "PERC" and CATEGORY_OF[w] in ("KICK", "SNARE", "CLAP", "HAT", "OPEN HAT", "808"): return fk
        return w
    return fk or "PERC"


def strip_kind(words, kind):
    same = {"HAT": "HIHAT HAT HH", "HIHAT": "HIHAT HAT HH", "OPEN HAT": "OPEN HIHAT HAT OHH",
            "OPEN HIHAT": "OPEN HIHAT HAT OHH", "PERC": "PERC PERCUSSION PERCS", "TAMB": "TAMB TAMBOURINE",
            "TOM": "TOM TOMS", "SHAKER": "SHAKER SHAK"}
    drop = set(same.get(kind, kind).split())
    if CATEGORY_OF.get(kind) in ("PERC", "TOM", "FX"): drop |= {"PERCUSSION", "PERCS"}
    return [w for w in words if w not in drop]


def new_name(src):
    folder, words, tag, pack = base_name(src)
    kind = kind_of(folder, words, tag)
    if kind in ("TAMBOURINE",): kind = "TAMB"
    rest = strip_kind(words, kind)
    # The pack's name only where the file's own name is just a number ("Danger Demon/Kicks/Kick 8" -> "DEMON 8 KICK").
    if not rest or all(w.isdigit() for w in rest): rest = [pack or "NO"] + rest
    return " ".join(rest), kind, folder


def main(apply):
    src = sources()
    catalog = {s["file"]: s for s in json.load(open(CATALOG))}
    rows = []
    for f, s in src.items():
        base, kind, folder = new_name(s)
        rows.append([f, base, kind, folder])
    # Same source twice: the 808's key, else V2, V3 ..., before the kind word.
    groups = collections.defaultdict(list)
    for r in rows: groups[(r[1], r[2])].append(r)
    names = {}
    for (base, kind), g in groups.items():
        g.sort(key=lambda r: r[0])
        if len(g) == 1:
            names[g[0][0]] = f"{base} {kind}"; continue
        if kind == "808":
            keys = collections.Counter(catalog[r[0]]["character"].split()[0] for r in g)
            seen = collections.Counter()
            for r in g:
                k = catalog[r[0]]["character"].split()[0]; seen[k] += 1
                names[r[0]] = f"{base} {k}" + (f" V{seen[k]}" if keys[k] > 1 and seen[k] > 1 else "") + f" {kind}"
        else:
            for i, r in enumerate(g):
                names[r[0]] = f"{base}" + (f" V{i + 1}" if i else "") + f" {kind}"
    assert len(set(names.values())) == len(names), [n for n, c in collections.Counter(names.values()).items() if c > 1]
    changed = collections.Counter()
    for f, base, kind, folder in rows:
        s = catalog[f]; cat = CATEGORY_OF[kind.split()[-1] if kind not in CATEGORY_OF else kind]
        if s["category"] != cat: changed[(s["category"], cat)] += 1
        print(f"{folder:28} {s['name']:20} -> {names[f]:32} {cat}")
        s["new"] = (names[f], cat, kind, folder)
    print(len(rows), "sounds;", sum(changed.values()), "change category:", dict(changed))
    if not apply: return
    tom_pitch = sorted(s["feat"]["pitch"] or 0 for s in catalog.values() if s["new"][1] == "TOM")
    mid = tom_pitch[len(tom_pitch) // 2] if tom_pitch else 0
    for s in catalog.values():
        name, cat, kind, folder = s.pop("new")
        if cat != s["category"] or cat in ("PERC", "CYMBAL", "TOM"):
            s["character"] = character(cat, kind, name, s, mid)
        s["name"], s["category"], s["folder"] = name, cat, folder
    rows = sorted(catalog.values(), key=lambda s: (s["category"], s["name"]))
    with open(CATALOG, "w") as out:
        out.write("[\n" + ",\n".join(json.dumps(c, sort_keys=True) for c in rows) + "\n]\n")
    # Where each file came from: its original path, or (genre / artist kit sounds) the pool folder and kept name.
    with open(SOURCES, "w") as out:
        out.write("{\n" + ",\n".join(f"{json.dumps(f)}: {json.dumps({k: v for k, v in r.items() if k != 'uses'}, sort_keys=True)}"
                                      for f, r in sorted(src.items())) + "\n}\n")


def character(cat, kind, name, s, tom_mid):
    """The character tools/build_kits.py picks pads by, for sounds whose category or name says it."""
    words = name.split()
    if cat == "PERC":
        for w in ("SHAKER", "TAMB", "TRIANGLE", "CLAVE", "BEADS"):
            if w in words: return w
        if "COWBELL" in words or "BELL" in words: return "METAL"
        return s["character"] if s["category"] == "PERC" and s["character"] not in ("SHAKER", "TAMB", "TRIANGLE", "CLAVE", "BEADS") else "HIT"
    if cat == "CYMBAL":
        if kind == "RIDE" or "RIDE" in words: return "RIDE"
        if kind == "CRASH": return "CRASH"
        return s["character"] if s["category"] == "CYMBAL" else "CRASH"
    if cat == "TOM": return "LOW" if (s["feat"]["pitch"] or 0) <= tom_mid else "HIGH"
    if cat == "808": return s["character"]
    if cat == "RIM": return "SNAP" if kind == "SNAP" else ""
    if s["category"] == cat: return s["character"]
    return ""


if __name__ == "__main__":
    main("--apply" in sys.argv)
