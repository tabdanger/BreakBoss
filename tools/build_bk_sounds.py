#!/usr/bin/env python3
"""Adds Tyrone's own Drum Kit (Oct 20) to the stock sounds as BK sounds, renamed for BreaKing.

  python3 -I tools/build_bk_sounds.py "DRUM_KIT_DIR"     # copies the WAVs, writes tools/bk_sounds.json
  python3 -I tools/build_bk_sounds.py --add DIR...       # appends more of his packs, the shipped rows stay as they are
  python3 tools/build_kits.py                            # then: manifest + the BK kits

Each file is converted to the stock format, 48 kHz 16-bit WAV (ffmpeg, SoX resampler, triangular dither),
with no level, trim or tone change, to StockSamples/bk_<kind>_NN.wav. The pack's files are 44.1 kHz at
16/24/32-bit float; every stock sound must decode at 48 kHz (KnockSelfTest checkStockSamples).
The pack names its files "<Pack> - Kind (Name).wav"; the kind decides the BreaKing name, numbered in the pack's
alphabetical order, the number before the last word like "NO 3 TOM": "Kick (Blaze)" -> "BK NO 1 KICK",
"Open Hat (Truth)" -> "BK NO 3 OPEN HAT", "Percussion (Tom)" -> "BK NO 1 TOM" (its own name says tom; it sits
with the PERCS, its folder).
The one-shot packs (Oct 20: Rims, Crashes, Closed Hats, Open Hats, Snares) name files "Kind (N).wav"; they number on
after the sounds already there, in N order: "Rim (1)" -> "BK NO 2 RIM", "Crash (1)" -> "BK NO 1 CRASH" (a cymbal).
Their tails are trimmed where they fall below -80 dBFS for good (silence padding; nothing audible is cut).
"""
import json, os, re, subprocess, sys
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
OUT = os.path.join(ROOT, "tools", "bk_sounds.json")
# the pack's kind word -> (name word, category, library section)
KINDS = {"kick": ("KICK", "KICK", "KICK"), "snare": ("SNARE", "SNARE", "SNARE"), "clap": ("CLAP", "CLAP", "CLAP"),
         "rim": ("RIM", "RIM", "RIM"), "hihat": ("HIHAT", "HAT", "HAT"), "open hat": ("OPEN HAT", "OPEN HAT", "OPEN HAT"),
         "cymbal": ("CYMBAL", "CYMBAL", "CYMBAL"), "percussion": ("PERC", "PERC", "PERC"),
         "crash": ("CRASH", "CYMBAL", "CYMBAL"), "closed hats": ("HIHAT", "HAT", "HAT"), "open hats": ("OPEN HAT", "OPEN HAT", "OPEN HAT")}
SILENT = 10 ** (-80 / 20)


def convert(src, file):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-map_metadata", "-1",
                    "-af", "aresample=48000:resampler=soxr:precision=28:dither_method=triangular",
                    "-c:a", "pcm_s16le", os.path.join(STOCK, file)], check=True)


def trim_tail(file):
    """Cuts the silence after the last sample above -80 dBFS (plus 10 ms); the pack pads some sounds for seconds."""
    path = os.path.join(STOCK, file)
    raw = open(path, "rb").read()
    at = raw.index(b"data") + 8
    ch = int.from_bytes(raw[22:24], "little")
    audio = np.frombuffer(raw[at:at + int.from_bytes(raw[at - 4:at], "little")], dtype="<i2").reshape(-1, ch)
    loud = np.nonzero(np.abs(audio).max(axis=1) > SILENT * 32768)[0]
    keep = min(len(audio), int(loud[-1]) + 480 + 1) if len(loud) else len(audio)
    if keep == len(audio): return
    body = audio[:keep].tobytes()
    head = bytearray(raw[:at])
    head[at - 4:at] = len(body).to_bytes(4, "little")
    head[4:8] = (len(head) - 8 + len(body)).to_bytes(4, "little")
    open(path, "wb").write(bytes(head) + body)


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
        convert(os.path.join(src, f), file)
        rows.append({"file": file, "name": name, "category": cat, "library": section, "source": f})
    json.dump(rows, open(OUT, "w"), indent=1)
    print(len(rows), "BK sounds:", count)


def add(folders):
    rows = json.load(open(OUT))
    count = {}
    for r in rows:
        word = re.match(r"BK NO (\d+) (.+)$", r["name"]).group(2)
        count[word] = max(count.get(word, 0), int(re.match(r"BK NO (\d+)", r["name"]).group(1)))
    done = {r["source"] for r in rows}
    added = {}
    for src in folders:
        files = [f for f in os.listdir(src) if re.match(r"(?i)^.+\(\d+\)\.wav$", f) and not f.startswith("._")]
        for f in sorted(files, key=lambda f: int(re.search(r"\((\d+)\)", f).group(1))):
            kind = re.sub(r"\s*\(\d+\)\.wav$", "", f, flags=re.I).strip().lower()
            word, cat, section = KINDS[kind]
            source = f"{os.path.basename(os.path.normpath(src))}/{f}"
            if source in done: continue
            count[word] = count.get(word, 0) + 1
            n = count[word]
            name, file = f"BK NO {n} {word}", f"bk_{word.lower().replace(' ', '')}_{n:02d}.wav"
            convert(os.path.join(src, f), file)
            trim_tail(file)
            rows.append({"file": file, "name": name, "category": cat, "library": section, "source": source})
            added[word] = added.get(word, 0) + 1
    json.dump(rows, open(OUT, "w"), indent=1)
    print(len(rows), "BK sounds, added:", added)


if __name__ == "__main__":
    if sys.argv[1] == "--add": add(sys.argv[2:])
    else: main(sys.argv[1])
