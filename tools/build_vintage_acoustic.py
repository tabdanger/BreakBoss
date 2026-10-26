#!/usr/bin/env python3
"""Builds Tyrone's acoustic drums for the Vintage kits (Oct 26) from the zips he sent.

  python3 tools/build_vintage_acoustic.py SOURCE_DIR

SOURCE_DIR holds his acoustic one-shots unzipped (a folder per zip; the same file sent twice counts once):
a Yamaha 16x16 kick and an EQ'd kick, Custom Works 6x13 snares (center, off-center, rimshot, side stick,
flams, drags, rolls, riffs), Star Classic 10" / 12" / 13" toms, Sabian hats (closed, pedal, open, bell,
shaken, hat crash), 14" and 18" crashes, a 22" ride and a 6" splash. Each articulation comes as velocity
layers, V1 the softest.

Every articulation becomes one multisampled stock sound, like the Virtuosity drums
(tools/build_acoustic_sounds.py): up to five of its velocity layers (three for the sounds only in the sound menu), each reaching up to its own level, so a
ghost note in the sequencer or piano roll plays a soft hit and an accent a hard one. The loudest layer of
each sound gets the stock loudness with one plain gain (no limiter), the softer layers the same gain, so
the drum keeps the dynamics it was played with.

Writes into BreakBoss.swiftpm/Resources/StockSamples:
  va_*.wav              each kept hit, 16-bit 48 kHz stereo, tail faded to fit its length
  acoustic_layers.json  adds these sounds' layers next to the Virtuosity ones
and tools/vintage_acoustic_sounds.json: the sounds for tools/build_kits.py (the Vintage kits play them).
Names are "BK NO n KIND", numbered on from the highest of that kind (Tyrone, Oct 25).
"""
import glob, hashlib, json, os, re, subprocess, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import level_stock_sounds as lv

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
RATE = 48_000
MAX_LAYERS = 5      # kit sounds; the sound-menu-only ones keep 3

# file pattern (on the path inside the zip), short file name, kind word, category, character, seconds, in kits
# Kits leave out the flams, drags, rolls, riffs and the pedal hats (a backbeat that flams on every hit isn't one); they're in
# the sound menu for any pad.
SOUNDS = [
    (r"Kick-1/Kick-V\d+-Yamaha", "kick16", "KICK", "KICK", "ROUND", 1.0, True),
    (r"YMH-kick-drum/V\d+-EQ-KD", "kickeq", "KICK", "KICK", "PUNCH", 1.0, True),
    (r"Snare hits/V\d+-EQ-SD", "snareeq", "SNARE", "SNARE", "CRACK", 0.9, True),
    (r"SNARE-V\d+-CustomWorks", "snare", "SNARE", "SNARE", "ROOM", 0.9, True),
    (r"SNR-OFF-V\d+-CustomWorks", "snareoff", "SNARE", "SNARE", "OFF CENTER", 0.9, True),
    (r"RIMSHOTS-V\d+-CW", "rimshot", "SNARE", "SNARE", "RIMSHOT", 1.0, True),
    (r"Snare Rim Shot/V\d+-Rim-SD", "rimshoteq", "SNARE", "SNARE", "RIMSHOT", 1.0, True),
    (r"Snare Side Stick/V\d+-SStick", "sstickeq", "RIM", "RIM", "CROSS STICK", 0.5, True),
    (r"SSTICK-V\d+-CW", "sstick", "RIM", "RIM", "CROSS STICK", 0.5, True),
    (r"FLAMS-V\d+-CW", "flam", "SNARE", "SNARE", "FLAM", 1.0, False),
    (r"Sanre Flams/V\d+-Flams-SD", "flameq", "SNARE", "SNARE", "FLAM", 1.0, False),
    (r"Snare Drags/V\d+-Drag-SD", "drag", "SNARE", "SNARE", "DRAG", 1.0, False),
    (r"SD-riff-1", "riff1", "SNARE", "SNARE", "RIFF", 1.7, False),
    (r"SD-riff-2", "riff2", "SNARE", "SNARE", "RIFF", 1.7, False),
    (r"SD-riff-3", "riff3", "SNARE", "SNARE", "RIFF", 1.7, False),
    (r"SD-Roll-1", "roll1", "SNARE", "SNARE", "ROLL", 3.9, False),
    (r"SD-Roll-2", "roll2", "SNARE", "SNARE", "ROLL", 3.6, False),
    (r"ROLL-01-CW", "roll3", "SNARE", "SNARE", "ROLL", 3.9, False),
    (r"Hats-1/HHats-CL-V\d+-SABIAN", "hat", "HIHAT", "HAT", "TIGHT", 0.45, True),
    (r"Hats-CLD/V\d+-Hats-CLD", "hatcld", "HIHAT", "HAT", "CRISP", 0.45, True),
    (r"Shack-HHats-CL-V\d+", "hatshake", "HIHAT", "HAT", "LOOSE", 0.5, True),
    (r"BELL-HHats-CL-V\d+", "hatbell", "HIHAT", "HAT", "BELL", 0.8, False),
    (r"HHats-PDL-V\d+-SABIAN", "hatpedal", "HIHAT", "HAT", "PEDAL", 0.4, False),
    (r"Hats-PDL/V\d+-Hats-PDL", "hatpedal2", "HIHAT", "HAT", "PEDAL", 0.4, False),
    (r"HHats-OP-V\d+-SABIAN", "openhat", "OPEN HAT", "OPEN HAT", "OPEN", 1.8, True),
    (r"Hats-OP/V\d+-Hats-OP", "openhat2", "OPEN HAT", "OPEN HAT", "OPEN", 1.8, True),
    (r"HHats-Crash-V\d+", "hatcrash", "OPEN HAT", "OPEN HAT", "WASH", 2.5, False),
    (r"TOM10-V\d+-StarClassic", "tom10", "TOM", "TOM", "HIGH", 1.4, True),
    (r"TTom-12", "tom12", "TOM", "TOM", "MID", 1.4, True),
    (r"TOM13-V\d+-StarClassic", "tom13", "TOM", "TOM", "LOW", 1.6, True),
    (r"FLAM10-V\d+", "tomflam10", "TOM", "TOM", "FLAM", 1.4, False),
    (r"TFlam-12", "tomflam12", "TOM", "TOM", "FLAM", 1.4, False),
    (r"FLAM13-V\d+", "tomflam13", "TOM", "TOM", "FLAM", 1.6, False),
    (r"14-Crash-V\d+", "crash14", "CRASH", "CYMBAL", "CRASH", 3.2, True),
    (r"18-Crash-V\d+", "crash18", "CRASH", "CYMBAL", "CRASH", 3.6, True),
    (r"18-CrshCHOKE-V\d+", "choke18", "CRASH", "CYMBAL", "CHOKE", 1.8, True),
    (r"14-CrshBELL-V\d+", "crashbell14", "CRASH", "CYMBAL", "BELL", 2.5, False),
    (r"18-CrshBELL-V\d+", "crashbell18", "CRASH", "CYMBAL", "BELL", 2.5, False),
    (r"Ride-V\d+-ROBMOR", "ride", "RIDE", "CYMBAL", "RIDE", 2.8, True),
    (r"BELL-V\d+-ROBMOR", "ridebell", "RIDE", "CYMBAL", "BELL", 2.8, True),
    (r"6-Splash-V\d+", "splash", "CYMBAL", "CYMBAL", "SPLASH", 2.5, True),
    (r"6-SplashCHOKE-V\d+", "splashchoke", "CYMBAL", "CYMBAL", "CHOKE", 1.0, False),
]
TAGS = ["acoustic", "soul", "jazz", "funk", "boombap"]


def load(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-"],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(np.float64)


def shape(audio, seconds):
    """Starts 1 ms before the hit, fits in `seconds`, its last 35% faded out (as the Virtuosity drums)."""
    level = np.abs(audio).max(axis=1)
    onset = int(np.argmax(level > level.max() * 0.01))
    audio = audio[max(0, onset - RATE // 1000):]
    n = min(len(audio), int(seconds * RATE))
    audio = audio[:n].copy()
    fade = int(n * 0.35)
    audio[n - fade:] *= (0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fade)))[:, None]
    audio[:16] *= np.linspace(0, 1, 16)[:, None] ** 0.5
    return audio


def numbers():
    """The highest BK number of each kind word so far."""
    top = {}
    for f in ("stock_sounds", "acoustic_sounds", "bk_sounds"):
        for s in json.load(open(os.path.join(ROOT, "tools", f + ".json"))):
            m = re.match(r"BK NO (\d+) (.+)$", s["name"])
            if not m: continue
            words = s["name"].split()
            kind = "OPEN HAT" if words[-2:] == ["OPEN", "HAT"] else words[-1]
            top[kind] = max(top.get(kind, 0), int(m.group(1)))
    return top


def main():
    src = sys.argv[1]
    unique = {}
    for f in sorted(glob.glob(os.path.join(src, "**", "*.wav"), recursive=True)):
        if "__MACOSX" in f: continue
        unique.setdefault(hashlib.md5(open(f, "rb").read()).hexdigest(), f)
    files = sorted(unique.values())
    for f in glob.glob(os.path.join(STOCK, "va_*.wav")): os.remove(f)
    top = numbers()
    layers_path = os.path.join(STOCK, "acoustic_layers.json")
    layers_all = json.load(open(layers_path))
    layers_all["sounds"] = {k: v for k, v in layers_all["sounds"].items() if not k.startswith("va_")}
    used, sounds_out, seed = set(), [], 9500
    ceiling = 10 ** (lv.CEILING / 20)
    for pattern, short, kind, cat, character, seconds, in_kits in SOUNDS:
        mine = [f for f in files if re.search(pattern, f) and f not in used]
        assert mine, pattern
        used.update(mine)
        audio = {f: shape(load(f), seconds) for f in mine}
        peak = {f: np.abs(a).max() for f, a in audio.items()}
        by_level = sorted(mine, key=lambda f: peak[f])
        # Up to five layers spread from the softest to the loudest hit.
        n = min(MAX_LAYERS if in_kits else 3, len(by_level))
        # Spread by level, not by count: a pack with ten full-volume takes still gets its soft layers.
        lo, hi_db = np.log(peak[by_level[0]]), np.log(peak[by_level[-1]])
        chosen = []
        for t in np.linspace(lo, hi_db, n):
            f = min((f for f in by_level if f not in chosen), key=lambda f: abs(np.log(peak[f]) - t))
            chosen.append(f)
        chosen = sorted(set(chosen), key=lambda f: peak[f])
        chosen[-1] = by_level[-1] if by_level[-1] not in chosen[:-1] else chosen[-1]
        loud = chosen[-1]
        gain = 10 ** ((lv.TARGET - lv.loudness(audio[loud], RATE)) / 20)
        gain = min(gain, ceiling / peak[loud])          # plain volume: never pushed into a limiter
        top[kind] = top.get(kind, 0) + 1
        name = f"BK NO {top[kind]} {kind}"
        main_file = f"va_{short}_l{len(chosen)}_r1.wav"
        out_layers, pmax = [], peak[loud]
        for i, f in enumerate(chosen):
            hi = 1.0 if i == len(chosen) - 1 else np.sqrt(peak[f] * peak[chosen[i + 1]]) / pmax
            out = f"va_{short}_l{i + 1}_r1.wav"
            a = audio[f] * gain
            a *= min(1.0, ceiling / max(np.abs(a).max(), 1e-9))
            lv.write(os.path.join(STOCK, out), a, 2, seed); seed += 1
            out_layers.append({"hi": round(float(hi), 4), "files": [out]})
        # Velocity tops must rise: a layer no louder than the one under it is dropped.
        tidy = []
        for l in out_layers:
            if tidy and l["hi"] <= tidy[-1]["hi"] + 0.01 and l is not out_layers[-1]:
                os.remove(os.path.join(STOCK, l["files"][0])); continue
            if tidy and l is out_layers[-1] and tidy[-1]["hi"] >= 0.99: tidy[-1]["hi"] = 0.98
            tidy.append(l)
        if len(tidy) > 1:
            layers_all["sounds"][main_file] = tidy
        a = lv.read(os.path.join(STOCK, main_file))[0]
        sounds_out.append({"category": cat, "character": character, "file": main_file, "name": name,
                           "folder": "BK ACOUSTIC", "tags": TAGS, "kits": in_kits,
                           "feat": {"dur": round(len(a) / RATE, 3)}})
        print(f"{name:20s} {character:12s} {len(tidy)} layers  {'kits' if in_kits else 'menu'}")
    left = [f for f in files if f not in used]
    assert not left, left
    json.dump(layers_all, open(layers_path, "w"), separators=(",", ":"))
    json.dump(sounds_out, open(os.path.join(ROOT, "tools", "vintage_acoustic_sounds.json"), "w"), indent=1)
    total = sum(os.path.getsize(os.path.join(STOCK, f)) for f in os.listdir(STOCK) if f.startswith("va_"))
    print(f"{len(sounds_out)} sounds, {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
