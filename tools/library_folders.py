#!/usr/bin/env python3
"""Puts every stock sound in the sound library section of the folder it came from (Tyrone, Oct 19).

  python3 tools/library_folders.py            # dry run: prints the sounds that change section
  python3 tools/library_folders.py --apply    # writes "library" into tools/stock_sounds.json and
                                              # "type" into the manifest's sounds (build_kits.py keeps it)

A sound from a percs folder is a PERC in the library even when its name says TOM, a clap from a snares
folder sits with the SNARES, a ride from a hats folder with the HI HATS. Names stay as they are (they say
what the sound is); only the section changes. Folders that hold two kinds keep the name's kind between
them: "Vintage/hats" (hi hats and open hats), "Snares + Claps 2"; a kit folder ("Danger Drums") and the
acoustic kit keep the name's kind.
"""
import json, os, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CATALOG = os.path.join(ROOT, "tools", "stock_sounds.json")
ACOUSTIC = os.path.join(ROOT, "tools", "acoustic_sounds.json")
MANIFEST = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples", "manifest.json")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from name_stock_sounds import FOLDER_KIND, CATEGORY_OF  # noqa: E402

# Folders holding two kinds: the kinds they hold (a sound of another kind goes to the first).
TWO_KINDS = {"Vintage/hats": ["HAT", "OPEN HAT"], "Vintage/snares": ["SNARE"], "Snares + Claps 2": ["SNARE", "CLAP"]}


def section(entry):
    kind = FOLDER_KIND.get(entry.get("folder"))
    if kind:
        return CATEGORY_OF.get(kind, kind)
    kinds = TWO_KINDS.get(entry.get("folder"))
    if kinds:
        return entry["category"] if entry["category"] in kinds else kinds[0]
    return entry["category"]


def main():
    rows = json.load(open(CATALOG))
    acoustic = json.load(open(ACOUSTIC))
    of = {}
    for r in rows:
        r["library"] = section(r)
        of[r["file"]] = r["library"]
        if r["library"] != r["category"]:
            print(f'{r["name"]:28s} {r["folder"]:22s} {r["category"]:9s} -> {r["library"]}')
    for a in acoustic:
        of[a["file"]] = a["category"]
    if "--apply" not in sys.argv:
        return
    with open(CATALOG, "w") as out:
        out.write("[\n" + ",\n".join(json.dumps(c, sort_keys=True) for c in rows) + "\n]\n")
    m = json.load(open(MANIFEST))
    for s in m["sounds"]:
        s["type"] = of[s["file"]]
    with open(MANIFEST, "w") as out:
        json.dump(m, out, separators=(",", ":"))


if __name__ == "__main__":
    main()
