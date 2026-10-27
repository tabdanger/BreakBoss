#!/usr/bin/env python3
"""Tunes every stock 808 to C (Tyrone, Oct 27: "any sound in a key other than c needs to be removed").

  python3 tools/tune_808s_to_c.py           # measure, retune, rename (skips 808s already on a C)
  python3 tools/tune_808s_to_c.py --check   # only print each 808's measured note

The 808s were the only stock sounds with a key in their names (D1, D#1, E1, F1, F#1, G1, A1) and the
unnamed ones were cut in those keys too. Each one is pitched to its nearest C the way a sampler does
it (played faster or slower, so the tail gets a little longer going down, shorter going up):
D1 to F1 go down to C1, F#1 to A1 go up to C2. The file keeps its name (saved songs and kits find
it by file); its stock name says its new note: "BK NO 5 D1 808" -> "BK NO 5 C1 808", with V2, V3...
when one number holds several of the same note. Then run tools/build_kits.py.
"""
import json, math, os, re, subprocess, sys, wave
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
SOUNDS = os.path.join(ROOT, "tools", "stock_sounds.json")
C1, C2 = 24, 36     # MIDI notes


def read(path):
    with wave.open(path) as w:
        a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, w.getnchannels())
        return a.mean(axis=1) / 32768.0, w.getframerate()


def pitch(path):
    """The 808's note in Hz: the strongest low partial of its body (after the click and the pitch drop)."""
    x, sr = read(path)
    peak = int(np.argmax(np.abs(x)))
    a, b = peak + int(0.08 * sr), peak + int(0.6 * sr)
    seg = x[a:min(b, len(x))]
    seg = seg * np.hanning(len(seg))
    n = 1 << 21
    spec = np.abs(np.fft.rfft(seg, n))
    f = np.fft.rfftfreq(n, 1 / sr)
    band = (f > 25) & (f < 80)
    return float(f[band][np.argmax(spec[band])])


def midi(hz): return 69 + 12 * math.log2(hz / 440)
def note_name(m): return ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"][round(m) % 12] + str(round(m) // 12 - 1)


def main():
    sounds = json.load(open(SOUNDS))
    bass = [s for s in sounds if s["category"] == "808"]
    plan = []
    for s in bass:
        hz = pitch(os.path.join(STOCK, s["file"]))
        m = midi(hz)
        target = C1 if m < 29.5 else C2    # D1..F1 down to C1, F#1..A1 up to C2
        plan.append((s, hz, m, target))
        print(f"{s['file']:26} {s['name']:20} {hz:6.2f} Hz  {note_name(m):4} {m - round(m):+.2f}  -> {note_name(target)} ({target - m:+.2f} st)")
    if "--check" in sys.argv: return
    for s, hz, m, target in plan:
        if abs(m - target) < 0.15: continue
        ratio = 2 ** ((target - m) / 12)
        path = os.path.join(STOCK, s["file"])
        tmp = path + ".tmp.wav"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-af",
                        f"asetrate={48000 * ratio:.4f},aresample=48000:resampler=soxr:precision=28",
                        "-ar", "48000", "-c:a", "pcm_s16le", tmp], check=True)
        os.replace(tmp, path)
        s["feat"]["pitch"] = round(440 * 2 ** ((target - 69) / 12), 1)
    # names: "BK NO n <note> [Vk] 808", V2, V3... in file order within a number and note
    groups = {}
    for s, hz, m, target in plan:
        number = " ".join(s["name"].split()[:3])          # "BK NO 17"
        groups.setdefault((number, note_name(target)), []).append(s)
    for (number, note), group in groups.items():
        group.sort(key=lambda s: s["name"])
        for i, s in enumerate(group):
            s["name"] = f"{number} {note}{'' if i == 0 else f' V{i + 1}'} 808"
            s["character"] = re.sub(r"^[A-G]#?\d", note, s.get("character") or note)   # "D1 LONG" -> "C1 LONG"
    with open(SOUNDS, "w") as out:
        out.write("[\n" + ",\n".join(json.dumps(s, sort_keys=True) for s in sounds) + "\n]\n")


if __name__ == "__main__":
    main()
