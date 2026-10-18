#!/usr/bin/env python3
"""Levels every stock sound to the same loudness, so no kit has a pad that jumps out or hides.

NOT RUN on the stock sounds any more (Tyrone, Oct 18 2026): the levelling and its transient limiter
made them sound altered, so the 570 pack sounds are back to their original files. Leave them as they
are; tools/build_acoustic_sounds.py still uses the measuring helpers here.

  python3 tools/level_stock_sounds.py          # level the WAVs in place
  python3 tools/level_stock_sounds.py --check  # only report, exit 1 if any sound is off target

Loudness is the loudest 100 ms of the sound, K-weighted (the ITU-R BS.1770 / EBU short-term
measure, so a hat and an 808 are judged the way an ear hears them, not by their peak).
Every sound gets one gain to land on TARGET. A sound whose peak would pass CEILING on the way up
(a spiky rim, a clicky perc) has only its first few milliseconds held down by a look-ahead peak
limiter, at most MAX_SHAVE dB; the body of the sound gets the full gain. Kicks, 808s and snares
start loud, so they only ever come down and are never limited.

A few very short clicks (an 808 rim, a 10 ms perc) still read under TARGET after that: they are
as loud as they can go without shaving them into a different sound, so they sit at CEILING.

Running it again is a no-op: a levelled sound already measures TARGET, or is one of those clicks.
KnockSelfTest.checkStockSamples measures the decoded audio the same way and holds every sound to
TARGET +/- TOLERANCE, or to the ceiling for the clicks.
"""
import glob, json, os, sys, wave
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")

TARGET = -10.0      # LUFS, loudest 100 ms (KnockSelfTest.stockLoudnessTarget)
TOLERANCE = 1.0     # dB either side (KnockSelfTest.stockLoudnessTolerance)
CEILING = -0.5      # dBFS sample peak
MAX_SHAVE = 9.0     # dB, most the limiter may take off a transient
LOOKAHEAD = 0.0015  # s, the limiter sees a peak coming this early
RELEASE = 0.008     # s, then lets go this fast
NEVER_LIMIT = ("bb_kick_", "bb_808_", "bb_snare_")

# BS.1770 K-weighting at 48 kHz: high shelf, then the RLB high-pass.
SHELF = ([1.53512485958697, -2.69169618940638, 1.19839281085285], [1.0, -1.69065929318241, 0.73248077421585])
RLB = ([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621])


def biquad(x, coeffs):
    (b0, b1, b2), (_, a1, a2) = coeffs
    y = np.empty_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x.tolist()):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def loudness(audio, rate):
    """LUFS of the loudest 100 ms window (the whole sound if it is shorter, padded with silence).
    A mono file plays on both sides of the pad (SampleLoader), so it is measured that way."""
    power = sum(biquad(biquad(audio[:, c], SHELF), RLB) ** 2 for c in range(audio.shape[1]))
    if audio.shape[1] == 1:
        power = power * 2
    window = int(0.1 * rate)
    sums = np.concatenate([[0.0], np.cumsum(power)])
    mean = sums[-1] / window if len(power) <= window else ((sums[window:] - sums[:-window]) / window).max()
    return -0.691 + 10 * np.log10(max(mean, 1e-12))


def read(path):
    with wave.open(path) as w:
        assert w.getsampwidth() == 2 and w.getframerate() == 48_000, path
        channels = w.getnchannels()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")
    return data.reshape(-1, channels).astype(np.float64) / 32768, channels


def write(path, audio, channels, seed):
    rng = np.random.default_rng(seed)
    dither = (rng.random(audio.shape) - rng.random(audio.shape))       # TPDF, 1 LSB
    pcm = np.clip(np.round(audio * 32768 + dither), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(48_000)
        w.writeframes(pcm.tobytes())


def limit(audio, rate, ceiling):
    """Look-ahead peak limiter: gain never above what keeps every sample under the ceiling."""
    peak = np.abs(audio).max(axis=1)
    need = np.minimum(1.0, ceiling / np.maximum(peak, 1e-12))
    ahead = max(1, int(LOOKAHEAD * rate))
    padded = np.concatenate([need, np.ones(ahead)])
    held = np.lib.stride_tricks.sliding_window_view(padded, ahead + 1).min(axis=1)  # sees each peak `ahead` early
    release = np.exp(-1.0 / (RELEASE * rate))
    gain = np.empty_like(held)
    g = 1.0
    for i, h in enumerate(held.tolist()):
        g = h if h < g else h + (g - h) * release
        gain[i] = g
    return audio * gain[:, None]


def settled(audio, now):
    """On target, or under it only because the peak is already at the ceiling."""
    peak = 20 * np.log10(np.abs(audio).max())
    return peak <= CEILING + 0.01 and (abs(now - TARGET) <= TOLERANCE or (now < TARGET and peak >= CEILING - 0.05))


def level(path):
    audio, channels = read(path)
    before = loudness(audio, 48_000)
    ceiling = 10 ** (CEILING / 20)
    limitable = not os.path.basename(path).startswith(NEVER_LIMIT)
    gain = TARGET - before
    for _ in range(4):                     # limiting takes a little loudness back; close in on TARGET
        out = audio * 10 ** (gain / 20)
        if np.abs(out).max() > ceiling and limitable:
            floor = np.abs(out).max() * 10 ** (-MAX_SHAVE / 20)
            out = limit(out, 48_000, max(ceiling, floor))
        out = out * min(1.0, ceiling / np.abs(out).max())
        now = loudness(out, 48_000)
        if abs(now - TARGET) < 0.05:
            break
        gain += TARGET - now
    return audio, out, channels, before


def main():
    check = "--check" in sys.argv
    paths = sorted(glob.glob(os.path.join(STOCK, "*.wav")))
    # An acoustic drum's softer layers keep the gain of its loudest hit (tools/build_acoustic_sounds.py):
    # only that loudest hit, the one the sound menu names, is levelled here.
    layers_path = os.path.join(STOCK, "acoustic_layers.json")
    if os.path.exists(layers_path):
        layers = json.load(open(layers_path))["sounds"]
        quiet = {f for main, ls in layers.items() for l in ls for f in l["files"] if f != main}
        paths = [p for p in paths if os.path.basename(p) not in quiet]
    off = []
    for n, path in enumerate(paths):
        audio, out, channels, before = level(path)
        name = os.path.basename(path)
        if check:
            if not settled(audio, before):
                off.append(f"{name}: {before:.1f} LUFS, peak {20 * np.log10(np.abs(audio).max()):.1f} dBFS")
            continue
        at_ceiling = 20 * np.log10(np.abs(audio).max()) >= CEILING - 0.05
        if abs(before - TARGET) < 0.05 or (before < TARGET and at_ceiling):
            continue
        write(path, out, channels, seed=n)
        written = read(path)[0]
        after = loudness(written, 48_000)
        print(f"{name}: {before:6.1f} -> {after:6.1f} LUFS")
        if not settled(written, after):
            off.append(f"{name}: {after:.1f} LUFS")
    for line in off:
        print("OFF TARGET", line)
    print(f"{len(paths)} sounds, {len(off)} off target ({TARGET} LUFS +/- {TOLERANCE} dB)")
    sys.exit(1 if off else 0)


if __name__ == "__main__":
    main()
