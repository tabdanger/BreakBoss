#!/usr/bin/env python3
"""Stores the stock sounds as Apple Lossless (Tyrone, Nov 12: "can we compress the sounds?").

  python3 -I tools/compress_stock_sounds.py            # every StockSamples/*.wav -> <name>.caf (ALAC), the WAV removed
  python3 -I tools/compress_stock_sounds.py --expand   # every .caf back to a 16-bit WAV (for the older sound tools)
  python3 -I tools/compress_stock_sounds.py --check    # every sound the manifest or layers name is on disk and matches

Apple Lossless is lossless: the .caf decodes to exactly the samples the WAV held (checked here for every file,
and on the iPad by KnockSelfTest checkStockSamples against stock_pcm.json). About a third of the WAV size.

The manifest, acoustic_layers.json, sample_names.json, the kits, saved songs and sound ids keep naming every
sound "<name>.wav". The app reads a stock "<name>.wav" that isn't there from "<name>.caf" beside it
(SampleLoader.stockFile). So nothing that names a sound changes.

The sound tools (build_bk_sounds, build_vintage_acoustic, level/tune/sort_stock_sounds, match_loop_sounds...)
still write and read WAVs: run this with --expand first if a tool reads the stock sounds, the tool, then run
this again with no options to compress them all again.

stock_pcm.json: for each sound (by its .wav name) its length in frames and an FNV-1a 64 hash of its 16-bit
samples, interleaved (mono files: the one channel), so the self-test can prove the iPad decodes them exactly.
"""
import array, json, os, struct, subprocess, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
STOCK = os.path.join(ROOT, "BreakBoss.swiftpm", "Resources", "StockSamples")
PCM = os.path.join(STOCK, "stock_pcm.json")


def pcm(path):
    """The file's samples as 16-bit little endian, interleaved, and its channel count."""
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels,sample_rate",
                            "-of", "csv=p=0", path], check=True, capture_output=True, text=True).stdout.strip().split(",")
    rate, channels = int(probe[0]), int(probe[1])
    assert rate == 48000, f"{path}: {rate} Hz (every stock sound must be 48 kHz)"
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-c:a", "pcm_s16le", "-"],
                         check=True, capture_output=True).stdout
    return raw, channels


def fnv(raw):
    """FNV-1a 64 over the 16-bit samples, one sample (not one byte) at a time, as the self-test hashes them."""
    samples = array.array("H", raw)
    if sys.byteorder != "little": samples.byteswap()
    h = 0xcbf29ce484222325
    for s in samples:
        h = ((h ^ s) * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return f"{h:016x}"


def wav_frames(path):
    d = open(path, "rb").read()
    o, channels, frames = 12, 0, None
    while o + 8 <= len(d):
        cid, ln = d[o:o + 4], struct.unpack("<I", d[o + 4:o + 8])[0]
        if cid == b"fmt ": channels, bits = struct.unpack("<H", d[o + 10:o + 12])[0], struct.unpack("<H", d[o + 22:o + 24])[0]; assert bits == 16, path
        if cid == b"data": frames = ln // (2 * channels)
        o += 8 + ln + (ln & 1)
    return frames


def fix_packet_table(path, frames):
    """ffmpeg's CAF writer counts the last ALAC packet as full (up to 4095 frames of padding after the sound).
    Write the real length into the 'pakt' header (valid frames, and the rest as remainder), as afconvert does,
    so the iPad's reader gives back exactly the sound's frames."""
    d = bytearray(open(path, "rb").read())
    assert d[:4] == b"caff", path
    o, per_packet = 8, None
    while o + 12 <= len(d):
        cid, ln = bytes(d[o:o + 4]), struct.unpack(">q", d[o + 4:o + 12])[0]
        if cid == b"desc": per_packet = struct.unpack(">I", d[o + 12 + 20:o + 12 + 24])[0]
        if cid == b"pakt":
            packets, valid, priming, remainder = struct.unpack(">qqii", d[o + 12:o + 36])
            assert per_packet and priming == 0 and packets * per_packet >= frames > (packets - 1) * per_packet, (path, packets, frames)
            d[o + 12:o + 36] = struct.pack(">qqii", packets, frames, 0, packets * per_packet - frames)
            open(path, "wb").write(d)
            return
        if ln < 0: break
        o += 12 + ln
    raise SystemExit(f"{path}: no packet table")


def compress():
    table = json.load(open(PCM)) if os.path.exists(PCM) else {"version": 1, "sounds": {}}
    wavs = sorted(f for f in os.listdir(STOCK) if f.endswith(".wav"))
    before = after = 0
    for i, f in enumerate(wavs):
        src = os.path.join(STOCK, f)
        dst = src[:-4] + ".caf"
        raw, channels = pcm(src)
        frames = wav_frames(src)
        assert frames == len(raw) // (2 * channels), f
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, "-map_metadata", "-1", "-fflags", "+bitexact",
                        "-c:a", "alac", "-f", "caf", dst], check=True)
        fix_packet_table(dst, frames)
        back, back_channels = pcm(dst)
        if back != raw or back_channels != channels:
            os.remove(dst)
            raise SystemExit(f"{f}: the Apple Lossless copy doesn't decode to the same samples; WAV kept")
        table["sounds"][f] = {"frames": frames, "channels": channels, "fnv": fnv(raw)}
        before += os.path.getsize(src); after += os.path.getsize(dst)
        os.remove(src)
        if (i + 1) % 100 == 0: print(f"{i + 1}/{len(wavs)}", flush=True)
    present = {f[:-4] + ".wav" for f in os.listdir(STOCK) if f.endswith(".caf")}
    table["sounds"] = {k: table["sounds"][k] for k in sorted(table["sounds"]) if k in present}
    json.dump(table, open(PCM, "w"), indent=0, sort_keys=True)
    open(PCM, "a").write("\n")
    print(f"{len(wavs)} WAVs -> Apple Lossless: {before / 1e6:.1f} MB -> {after / 1e6:.1f} MB")
    check()


def expand():
    cafs = sorted(f for f in os.listdir(STOCK) if f.endswith(".caf"))
    for f in cafs:
        src = os.path.join(STOCK, f)
        dst = src[:-4] + ".wav"
        subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", src, "-map_metadata", "-1", "-fflags", "+bitexact",
                        "-c:a", "pcm_s16le", dst], check=True)
        assert pcm(dst)[0] == pcm(src)[0], f
        os.remove(src)
    print(f"{len(cafs)} sounds expanded to WAV; run this again with no options when done")


def check():
    manifest = json.load(open(os.path.join(STOCK, "manifest.json")))
    named = {a["file"] for a in manifest["assignments"]} | {s["file"] for s in manifest.get("sounds") or []}
    layers = os.path.join(STOCK, "acoustic_layers.json")
    if os.path.exists(layers):
        for entries in json.load(open(layers))["sounds"].values():
            for e in entries: named |= set(e["files"])
    table = json.load(open(PCM))["sounds"]
    problems = []
    for f in sorted(named):
        assert f.endswith(".wav"), f"{f}: sounds are named <name>.wav"
        caf = os.path.join(STOCK, f[:-4] + ".caf")
        if os.path.exists(os.path.join(STOCK, f)): problems.append(f"{f}: still a WAV")
        elif not os.path.exists(caf): problems.append(f"{f}: missing")
        elif f not in table: problems.append(f"{f}: not in stock_pcm.json")
    extra = sorted(f for f in os.listdir(STOCK) if f.endswith((".caf", ".wav")) and f[:-4] + ".wav" not in named)
    if extra: print(f"note: {len(extra)} sound files no manifest names: {extra[:5]}")
    if problems: raise SystemExit("\n".join(problems[:20]))
    print(f"{len(named)} stock sounds: all Apple Lossless, all in stock_pcm.json")


if __name__ == "__main__":
    {"--expand": expand, "--check": check}.get(sys.argv[1] if len(sys.argv) > 1 else "", compress)()
