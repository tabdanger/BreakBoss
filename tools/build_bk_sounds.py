#!/usr/bin/env python3
"""Adds Tyrone's own Drum Kit (Oct 20) to the stock sounds as BK sounds, renamed for BreaKing.

  python3 -I tools/build_bk_sounds.py "DRUM_KIT_DIR"     # copies the WAVs, writes tools/bk_sounds.json
  python3 tools/build_kits.py                            # then: manifest + the BK DRUM KIT kit

Each file is copied byte for byte (no resampling, no level change) to StockSamples/bk_<kind>_NN.wav.
The pack names its files "<Pack> - Kind (Name).wav"; the kind decides the BreaKing name, numbered in the pack's
alphabetical order, the number before the last word like "NO 3 TOM": "Kick (Blaze)" -> "BK NO 1 KICK",
"Open Hat (Truth)" -> "BK NO 3 OPEN HAT", "Percussion (Tom)" -> "BK NO 1 TOM" (its own name says tom; it sits
with the PERCS, its folder).
"""
import json, os, re, shutil, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
OUT = os.path.join(ROOT, "tools", "bk_sounds.json")
# the pack's kind word -> (name word, category, library section)
KINDS = {"kick": ("KICK", "KICK", "KICK"), "snare": ("SNARE", "SNARE", "SNARE"), "clap": ("CLAP", "CLAP", "CLAP"),
         "rim": ("RIM", "RIM", "RIM"), "hihat": ("HIHAT", "HAT", "HAT"), "open hat": ("OPEN HAT", "OPEN HAT", "OPEN HAT"),
         "cymbal": ("CYMBAL", "CYMBAL", "CYMBAL"), "percussion": ("PERC", "PERC", "PERC")}


def main(src):
    rows, count = [], {}
    for f in sorted(os.listdir(src), key=str.lower):
        m = re.match(r"(?i)^(.+?)\s*\((.+)\)\.wav$", f)
        if not m or f.startswith("._"): continue
        kind, own = re.sub(r"^.* - ", "", m.group(1)).strip().lower(), m.group(2).strip()   # drop the pack prefix
        word, cat, section = KINDS[kind]
        if kind == "percussion" and own.lower() == "tom": word, cat = "TOM", "TOM"
        count[word] = count.get(word, 0) + 1
        n = count[word]
        name = f"BK NO {n} {word}"                # the last word says what it is (SoundType.forStockName)
        file = f"bk_{word.lower().replace(' ', '')}_{n:02d}.wav"
        shutil.copyfile(os.path.join(src, f), os.path.join(STOCK, file))
        rows.append({"file": file, "name": name, "category": cat, "library": section, "source": f})
    json.dump(rows, open(OUT, "w"), indent=1)
    print(len(rows), "BK sounds:", count)


if __name__ == "__main__":
    main(sys.argv[1])
