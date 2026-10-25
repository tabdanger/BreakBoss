#!/usr/bin/env python3
"""Renames every stock sound that came from a producer-tagged pack to a Break King name (Oct 25).

  python3 tools/bk_rename_tagged.py            # dry run: prints old name -> new name
  python3 tools/bk_rename_tagged.py --apply    # rewrites the names everywhere, then run tools/build_kits.py
  python3 tools/bk_rename_tagged.py --all [--apply]   # every other stock sound too (Danger, Vintage, acoustic...)

Tyrone, Oct 25: no sound in the app carries a producer's tag or its pack's names. The sounds whose
source file carried "(@prod.by.iiinfinite)" (tools/stock_sources.json), and the rest of that same
Archive (its "Kicks 2", "808 2"... folders), become "BK NO n KIND" like Tyrone's own BK sounds:
numbering goes on from the highest BK number of that kind, the 808's key and V2, V3 stay before the
kind word, and the kind word stays last (SoundType.forStockName reads it). Tyrone then wanted every other sound renamed the same way ("yes they should",
Oct 25): --all renames every stock sound that isn't "BK NO n" yet. Only names change: the
files, kits and pads stay the same. tools/bk_renamed.json keeps old -> new.
"""
import collections, json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
MANIFEST = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples", "manifest.json")
SOURCES = os.path.join(ROOT, "tools", "stock_sources.json")
OUT = os.path.join(ROOT, "tools", "bk_renamed.json")
TAG = re.compile(r"@prod\.by\.?iiinfinite", re.I)
# The Archive's own folders: the files there are "[Kind] Name - (@prod.by.iiinfinite)".
ARCHIVE_POOLS = {"808 2", "Claps 2", "Cymbals & Crashes 2", "Hi Hats 2", "Kicks 2", "Open Hats 2", "Rims 2",
                 "Snaps 2", "Snares 2"}
TWO_WORD_KINDS = ("OPEN HAT", "OPEN HIHAT", "DJ SCRATCH", "TRIANGLE RISER")
# The word Tyrone's BK sounds use for the same kind ("BK NO 3 HIHAT"), so the numbers run on from them.
BK_WORD = {"HAT": "HIHAT", "OPEN HIHAT": "OPEN HAT"}
# Every file whose JSON names a stock sound by its name.
NAMED_IN = ["BreakBoss.swiftpm/Resources/StockSamples/manifest.json", "tools/stock_sounds.json",
            "tools/learned_westcoast.json", "tools/learned_bayarea.json", "tools/acoustic_sounds.json"]


def tagged_files():
    out = set()
    for f, r in json.load(open(SOURCES)).items():
        if TAG.search(r.get("path", "")) or ("path" not in r and r.get("pool") in ARCHIVE_POOLS): out.add(f)
    return out


def split(name):
    """(the sound's own words, key / V tokens kept, kind) of a stock name."""
    words = name.split()
    n = 2 if " ".join(words[-2:]) in TWO_WORD_KINDS else 1
    kind, rest = " ".join(words[-n:]), words[:-n]
    keep = [w for w in rest if re.fullmatch(r"[A-G]#?\d|V\d+", w)]
    own = [w for w in rest if w not in keep]
    return " ".join(own), keep, kind


def renames(every=False):
    sounds = json.load(open(MANIFEST))["sounds"]
    tagged = tagged_files()
    if every: tagged = {s["file"] for s in sounds if not s["name"].startswith("BK NO ")}
    top = collections.defaultdict(int)
    for s in sounds:
        m = re.fullmatch(r"BK NO (\d+) (.+)", s["name"])
        if m: kind = split(m.group(2))[2]; top[kind] = max(top[kind], int(m.group(1)))
    groups = collections.defaultdict(list)
    for s in sounds:
        if s["file"] in tagged:
            own, keep, kind = split(s["name"])
            kind = BK_WORD.get(kind, kind)
            groups[(kind, own)].append((s["name"], keep))
    names = {}
    for (kind, own) in sorted(groups):
        top[kind] += 1
        for old, keep in groups[(kind, own)]:
            names[old] = " ".join(["BK NO", str(top[kind]), *keep, kind])
    everyone = [names.get(s["name"], s["name"]) for s in sounds]
    assert len(set(everyone)) == len(everyone), [n for n, c in collections.Counter(everyone).items() if c > 1]
    assert len(names) == len(tagged)
    return names


def rewrite(value, names):
    if isinstance(value, str): return names.get(value, value)
    if isinstance(value, list): return [rewrite(v, names) for v in value]
    if isinstance(value, dict): return {k: rewrite(v, names) for k, v in value.items()}
    return value


def main(apply, every):
    names = renames(every)
    for old, new in sorted(names.items(), key=lambda kv: kv[1]): print(f"{old:28} -> {new}")
    print(len(names), "sounds renamed")
    if not apply: return
    for rel in NAMED_IN:
        path = os.path.join(ROOT, rel)
        text = open(path).read()
        # Only whole JSON strings, so the files keep their own layout.
        new = re.sub(r'"((?:[^"\\]|\\.)*)"', lambda m: json.dumps(names[m.group(1)]) if m.group(1) in names else m.group(0), text)
        assert json.loads(new) == rewrite(json.loads(text), names), rel
        open(path, "w").write(new)
    old = json.load(open(OUT)) if os.path.exists(OUT) else {}
    old.update(names)
    with open(OUT, "w") as out:
        out.write("{\n" + ",\n".join(f"{json.dumps(k)}: {json.dumps(v)}" for k, v in sorted(old.items())) + "\n}\n")


if __name__ == "__main__":
    main("--apply" in sys.argv, "--all" in sys.argv)
