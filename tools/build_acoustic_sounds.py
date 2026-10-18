#!/usr/bin/env python3
"""Builds the multisampled acoustic drums (velocity layers + round robins) from Versilian Studios'
Virtuosity Drums (CC0 1.0, https://github.com/sfzinstruments/virtuosity_drums), mid stereo mic.

  python3 tools/build_acoustic_sounds.py SOURCE_DIR

SOURCE_DIR holds the kit's WAVs (24-bit 48 kHz, converted from the repo's FLACs) and map.json: one
entry per file with drum, articulation, layer, rr, lovel, hivel (parsed from the repo's .sfz maps).
The source is about 250 MB, so it is not kept in this repo; the LICENSE is (Build_Notes).

Writes into BreakBoss.swiftpm/Resources/StockSamples:
  ac_*.wav              each kept hit, 16-bit 48 kHz stereo, tail faded to fit the stock length limit
  acoustic_layers.json  for each acoustic sound, its velocity layers (top velocity 0...1) and the
                        round-robin files of each layer; the engine picks a layer by how hard the hit
                        is and steps through its round robins (KitBuffers.layers)
and tools/acoustic_sounds.json: the sounds for tools/build_kits.py (one per articulation, named
"VIRTUOSITY <WHAT> <KIND>", its file the loudest layer's first hit).

Loudness: each sound's loudest hit is levelled like every stock sound (tools/level_stock_sounds.py),
and its softer layers get the same gain, so a ghost note stays as quiet as the drummer played it.
tools/level_stock_sounds.py leaves the softer layers alone.
"""
import json, os, subprocess, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import level_stock_sounds as lv

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
RATE = 48_000

# name, short file name, category, character, (drum, articulation), seconds, layers kept (None = all), round robins
SOUNDS = [
    ("VIRTUOSITY KICK", "kick", "KICK", "ACOUSTIC", ("kick", "normal"), 1.0, None, 2),
    ("VIRTUOSITY SNARE", "snare", "SNARE", "ACOUSTIC", ("snare", "center"), 0.8, None, 2),
    ("VIRTUOSITY RIMSHOT SNARE", "rimshot", "SNARE", "ACOUSTIC", ("snare", "rimshot"), 0.9, None, 2),
    ("VIRTUOSITY OFF CENTER SNARE", "offctr", "SNARE", "ACOUSTIC", ("snare", "offcenter"), 0.8, [1, 2, 3, 4, 6, 8], 2),
    ("VIRTUOSITY CROSS STICK RIM", "xstick", "RIM", "ACOUSTIC", ("snare", "crossstick"), 0.4, [1, 3, 5, 6, 7, 8], 2),
    ("VIRTUOSITY HIHAT", "hat", "HAT", "ACOUSTIC", ("hihat", "closed"), 0.45, None, 3),
    ("VIRTUOSITY HALF OPEN HIHAT", "halfhat", "OPEN HAT", "ACOUSTIC", ("hihat", "half_open"), 1.0, None, 2),
    ("VIRTUOSITY OPEN HIHAT", "openhat", "OPEN HAT", "ACOUSTIC", ("hihat", "open"), 1.8, None, 2),
    ("VIRTUOSITY LOW TOM", "lotom", "TOM", "LOW", ("tom_low", "center"), 1.2, [2, 4, 6, 8], 2),
    ("VIRTUOSITY HIGH TOM", "hitom", "TOM", "HIGH", ("tom_high", "center"), 1.0, [2, 4, 6, 8], 2),
    ("VIRTUOSITY RIDE", "ride", "CYMBAL", "RIDE", ("ride", "bow"), 2.5, None, 2),
    ("VIRTUOSITY CRASH", "crash", "CYMBAL", "CRASH", ("crash", "normal"), 3.2, None, 2),
]


def load(path):
    """Any WAV as float stereo at 48 kHz (ffmpeg decodes the 24-bit source)."""
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(np.float64)


def shape(audio, seconds):
    """Starts 1 ms before the hit (the hit stays on the beat), fits in `seconds`, its last 35% faded out."""
    level = np.abs(audio).max(axis=1)
    onset = int(np.argmax(level > level.max() * 0.01))
    audio = audio[max(0, onset - RATE // 1000):]
    n = min(len(audio), int(seconds * RATE))
    audio = audio[:n].copy()
    fade = int(n * 0.35)
    audio[n - fade:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fade)))[:, None]
    audio[:16] *= np.linspace(0, 1, 16)[:, None] ** 0.5    # no click on the first sample
    return audio


def main():
    src = sys.argv[1]
    entries = json.load(open(os.path.join(src, "map.json")))
    layers_out, sounds_out = {}, []
    seed = 9000
    for name, short, cat, character, (drum, artic), seconds, keep, rrs in SOUNDS:
        mine = [e for e in entries if e["drum"] == drum and e["articulation"] == artic]
        assert mine, (drum, artic)
        all_layers = sorted({e["layer"] for e in mine})
        kept = keep or all_layers
        # Each kept layer reaches up to just under the next kept layer's lowest velocity.
        lows = {l: min(e["lovel"] for e in mine if e["layer"] == l) for l in all_layers}
        layers = []
        for i, l in enumerate(kept):
            hi = 127 if i == len(kept) - 1 else lows[kept[i + 1]] - 1
            hits = sorted((e for e in mine if e["layer"] == l), key=lambda e: e["rr"])[:rrs]
            layers.append((l, hi, hits))
        # The loudest hit sets the gain for the whole sound.
        top = layers[-1][2][0]
        main_file = f"ac_{short}_l{len(layers)}_r1.wav"
        main_audio = shape(load(os.path.join(src, top["file"])), seconds)
        gain_db = lv.TARGET - lv.loudness(main_audio, RATE)
        ceiling = 10 ** (lv.CEILING / 20)
        out_layers = []
        for n, (l, hi, hits) in enumerate(layers, start=1):
            files = []
            for r, e in enumerate(hits, start=1):
                f = f"ac_{short}_l{n}_r{r}.wav"
                audio = shape(load(os.path.join(src, e["file"])), seconds) * 10 ** (gain_db / 20)
                if f == main_file:
                    path = os.path.join(STOCK, f)
                    lv.write(path, audio * min(1.0, ceiling / np.abs(audio).max()), 2, seed)
                    _, audio, _, _ = lv.level(path)        # exactly like every stock sound
                peak = np.abs(audio).max()
                if peak > ceiling: audio = audio * (ceiling / peak)
                lv.write(os.path.join(STOCK, f), audio, 2, seed); seed += 1
                files.append(f)
            out_layers.append({"hi": round(hi / 127, 4), "files": files})
        layers_out[main_file] = out_layers
        a = lv.read(os.path.join(STOCK, main_file))[0]
        sounds_out.append({"category": cat, "character": character, "file": main_file, "name": name,
                           "folder": "VIRTUOSITY DRUMS", "tags": ["acoustic", "soul", "jazz", "funk", "boombap"],
                           "feat": {"dur": round(len(a) / RATE, 3)}})
        print(f"{name}: {len(out_layers)} layers, {sum(len(x['files']) for x in out_layers)} hits, "
              f"{lv.loudness(a, RATE):.1f} LUFS")
    json.dump({"version": 1, "sounds": layers_out}, open(os.path.join(STOCK, "acoustic_layers.json"), "w"),
              separators=(",", ":"))
    json.dump(sounds_out, open(os.path.join(ROOT, "tools", "acoustic_sounds.json"), "w"), indent=1)
    total = sum(os.path.getsize(os.path.join(STOCK, f)) for f in os.listdir(STOCK) if f.startswith("ac_"))
    print(f"{total / 1e6:.1f} MB of acoustic hits")


if __name__ == "__main__":
    main()
