#!/usr/bin/env python3
"""Writes StockSamples/sample_names.json: how a file in your Samples folder gets its Break King name (Oct 26).

  python3 tools/sample_names.py        # needs the full git history (git fetch --unshallow)

Tyrone, Oct 26: the SAMPLES tab still showed old file names ("!Go2Spinz", "(clap) aspen",
"bb_2000s-rnb_p00"). Every library pick and import is copied into Samples under its file's own
name, so copies made by older builds keep stock file names that no longer exist, and the packs
he imports keep their makers' names. The app shows every one as "BK NO n KIND" (KnockFolders.soundName):

  stock    an old or current stock file name -> the stock file it is now (its manifest name is shown)
  sources  a pack file's name (as the stock sounds were made from) -> that stock file
  families a pack sound's own word ("GO2SPINZ") -> its kind -> "BK NO n", as tools/bk_rename_tagged.py numbered it
  kinds    an old stock file that's gone -> the kind its last name said

Keys are squashed the way KnockFolders.nameKey does it: lower case, maker tag cut, letters and digits only.
"""
import collections, json, os, re, subprocess

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = "BreakBoss.swiftpm/Resources/StockSamples"
OUT = os.path.join(ROOT, STOCK, "sample_names.json")
TWO_WORD_KINDS = ("OPEN HAT", "OPEN HIHAT", "DJ SCRATCH", "TRIANGLE RISER")
# The word the stock names use for the same kind ("BK NO 3 HIHAT").
BK_WORD = {"HAT": "HIHAT", "OPEN HIHAT": "OPEN HAT"}


def git(*a): return subprocess.run(["git", "-C", ROOT, *a], capture_output=True, text=True, check=True).stdout


def key(stem):
    """KnockFolders.nameKey: "[808] Vacuum - (@prod.by.iiinfinite)" -> "808vacuum"."""
    s = re.sub(r"@prod\.?by\.?[a-z0-9._]*", "", stem.lower())
    return re.sub(r"[^a-z0-9]", "", s)


def kind_of(name):
    words = name.split()
    n = 2 if " ".join(words[-2:]) in TWO_WORD_KINDS else 1
    return " ".join(words[-n:])


def history():
    """Every stock file name there has been -> the stock file it is now (renames and same audio followed),
    and each file's last name in a manifest."""
    commits = git("log", "--reverse", "--format=%H", "--", STOCK).split()
    parent = {}

    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x: parent[x] = parent[parent[x]]; x = parent[x]
        return x

    by_blob = collections.defaultdict(set)
    last_name = {}
    for c in commits:
        for line in git("ls-tree", c, STOCK + "/").splitlines():
            meta, path = line.split("\t"); f = path.rsplit("/", 1)[1]
            if f.endswith(".wav"): by_blob[meta.split()[2]].add(f); find(f)
        for line in git("show", "-M", "--name-status", "--format=", c, "--", STOCK).splitlines():
            p = line.split("\t")
            if p[0].startswith("R") and p[1].endswith(".wav"):
                parent[find(p[1].rsplit("/", 1)[1])] = find(p[2].rsplit("/", 1)[1])
        try: m = json.loads(git("show", f"{c}:{STOCK}/manifest.json"))
        except subprocess.CalledProcessError: continue
        for a in m.get("assignments", []): last_name[a["file"]] = a["displayName"]
        for s in m.get("sounds", []) or []: last_name[s["file"]] = s["name"]
    for names in by_blob.values():
        names = sorted(names)
        for n in names[1:]: parent[find(n)] = find(names[0])
    return find, list(parent), last_name


def main():
    manifest = json.load(open(os.path.join(ROOT, STOCK, "manifest.json")))
    current = {s["file"]: s["name"] for s in manifest["sounds"]}
    known = {kind_of(n) for n in current.values()}
    find, names, last_name = history()
    groups = collections.defaultdict(set)
    for n in names: groups[find(n)].add(n)
    stock, kinds = {}, {}
    for members in groups.values():
        now = sorted(members & current.keys())
        for n in members:
            stem = n[:-4]
            if len(now) == 1: stock[key(stem)] = now[0]
            elif not now and n in last_name:
                kind = BK_WORD.get(kind_of(last_name[n]), kind_of(last_name[n]))
                if kind in known: kinds[key(stem)] = kind
    for f in current: stock[key(f[:-4])] = f

    # The pack files the stock sounds were made from, by their own names.
    sources, clash = {}, set()
    def source(path, file):
        k = key(os.path.basename(path).rsplit(".", 1)[0])
        if k in sources and sources[k] != file: clash.add(k)
        sources[k] = file
    for f, r in json.load(open(os.path.join(ROOT, "tools", "stock_sources.json"))).items():
        if "path" in r and f in current: source(r["path"], f)
    prov = json.load(open(os.path.join(ROOT, "Build_Notes", "STOCK_SAMPLE_PROVENANCE.json")))
    for a in prov["assignments"]:
        f = stock.get(key(a["outputFile"][:-4]))
        if f and f in current: source(a["source"], f)
    for k in clash: sources.pop(k)

    # A pack sound's own word -> kind -> its BK number ("GO2SPINZ" 808 -> "BK NO 5").
    families = collections.defaultdict(dict)
    renamed = json.load(open(os.path.join(ROOT, "tools", "bk_renamed.json")))
    for old, new in renamed.items():
        kind = kind_of(old)
        own = [w for w in old[: -len(kind)].split() if not re.fullmatch(r"[A-G]#?\d|V\d+", w)]
        m = re.match(r"(BK NO \d+) ", new)
        if own and m: families[key(" ".join(own))].setdefault(kind_of(new), m.group(1))
    for f, r in json.load(open(os.path.join(ROOT, "tools", "stock_sources.json"))).items():
        m = re.match(r"(BK NO \d+) ", current.get(f, ""))
        if "name" in r and m: families[key(r["name"])].setdefault(kind_of(current[f]), m.group(1))

    out = {"version": 1, "stock": dict(sorted(stock.items())), "sources": dict(sorted(sources.items())),
           "families": {k: dict(sorted(v.items())) for k, v in sorted(families.items())}, "kinds": dict(sorted(kinds.items()))}
    with open(OUT, "w") as fh: json.dump(out, fh, indent=0, sort_keys=False); fh.write("\n")
    print(f"{len(stock)} stock names, {len(sources)} pack files, {len(families)} families, {len(kinds)} gone -> {OUT}")


if __name__ == "__main__":
    main()
