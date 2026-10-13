#!/usr/bin/env python3
"""Inventory and prepare explicitly selected, real stock samples for BreakBoss.

Requires Python 3, numpy, ffmpeg and ffprobe. Never extracts ZIP entries.

  python3 tools/prepare_stock_samples.py inventory pack.zip --output inventory.json
  python3 tools/prepare_stock_samples.py prepare pack.zip selections.json \
      --package BreakBoss.swiftpm --provenance stock-sample-provenance.json

Selections are a JSON list (or {"selections": [...]}) containing kitID, pad
(zero-based 0..15), source (exact relative source path), and name. Optional
processing: startSeconds (0..59, skip leading audio before pitch; default 0),
tuneSemitones (-3..3), tailSeconds (hard maximum, with 6 ms fade),
decaySeconds (exponential tail after the first 20 ms), lowpassHz (1000..23000),
drive (0..0.25, mild tanh saturation), peak (0.05..0.98; default 0.92).
Pitch shifts change duration, like a sampler. Sources may be at most 60 seconds;
prepared hits at most 12 seconds. Longer hits require explicit tailSeconds.
808 pad 6 requires sourceRootHz and targetRootHz, which must match the kit's
bassHz. These hits use that exact pitch ratio; tuneSemitones must be zero.
All processing parameters and source/output SHA256 hashes are recorded outside
the app. Inventory mode creates no stock assets or sample assignments.
--deduplicate optionally shares identical prepared WAVs between assignments;
it is off by default. Only unique files count toward the 64 MiB stock budget.
"""

from __future__ import annotations

import argparse
from collections import OrderedDict
import fnmatch
import hashlib
import io
import json
import math
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unicodedata
import wave
import zipfile

import numpy as np

RATE = 48_000
MAX_SOURCE_BYTES = 128 * 1024 * 1024
MAX_SOURCE_SECONDS = 60
MAX_OUTPUT_SECONDS = 12
MAX_TOTAL_OUTPUT_BYTES = 64 * 1024 * 1024
MAX_DECODE_CACHE_BYTES = 64 * 1024 * 1024
MAX_ENTRIES = 100_000
MAX_ASSIGNMENTS = 1024
FORMATS = {".wav": "wav", ".aif": "aiff", ".aiff": "aiff", ".caf": "caf",
           ".flac": "flac", ".mp3": "mp3", ".ogg": "ogg", ".m4a": "mov"}
FIELDS = {"kitID", "pad", "source", "name", "startSeconds", "tuneSemitones", "tailSeconds",
          "decaySeconds", "lowpassHz", "drive", "peak", "sourceRootHz", "targetRootHz"}


def fail(message: str):
    raise ValueError(message)


def safe_source_name(name: str) -> str:
    if not isinstance(name, str) or not name or "\\" in name or "\x00" in name:
        fail(f"Invalid source path: {name!r}")
    path = PurePosixPath(name)
    if path.is_absolute() or any(part in (".", "..", "") for part in name.split("/")):
        fail(f"Unsafe source path: {name!r}")
    if re.match(r"^[A-Za-z]:", name):
        fail(f"Unsafe source path: {name!r}")
    return name


def metadata_path(name: str) -> bool:
    return any(part == "__MACOSX" or part.startswith(".") for part in PurePosixPath(name).parts)


class Sources:
    """Bounded reads from directory or ZIP; no extraction and no symlink reads."""
    def __init__(self, path: Path):
        self.root = path.resolve(strict=True)
        self.archive = None
        self.entries = {}
        if self.root.is_dir():
            for count, file in enumerate(self.root.rglob("*"), 1):
                if count > MAX_ENTRIES:
                    fail("Source directory contains too many entries")
                name = file.relative_to(self.root).as_posix()
                if (file.suffix.lower() in FORMATS and file.is_file() and not file.is_symlink()
                        and not metadata_path(name)):
                    self.entries[safe_source_name(name)] = file
        elif zipfile.is_zipfile(self.root):
            self.archive = zipfile.ZipFile(self.root)
            infos = self.archive.infolist()
            if len(infos) > MAX_ENTRIES:
                fail("Archive contains too many entries")
            for entry in infos:
                if entry.is_dir() or PurePosixPath(entry.filename).suffix.lower() not in FORMATS:
                    continue
                name = safe_source_name(entry.filename)
                if metadata_path(name):
                    continue
                if name in self.entries:
                    fail(f"Duplicate archive entry: {name}")
                if stat.S_ISLNK(entry.external_attr >> 16):
                    fail(f"Archive symlink refused: {name}")
                if entry.flag_bits & 1:
                    fail(f"Encrypted archive entry refused: {name}")
                self.entries[name] = entry
        else:
            fail("Source must be a directory or a ZIP archive")

    def close(self):
        if self.archive:
            self.archive.close()

    def read(self, name: str) -> bytes:
        safe_source_name(name)
        if name not in self.entries:
            fail(f"Source does not exist in pack: {name}")
        entry = self.entries[name]
        if self.archive:
            if entry.file_size > MAX_SOURCE_BYTES:
                fail(f"Source exceeds 128 MiB: {name}")
            with self.archive.open(entry) as handle:
                data = handle.read(MAX_SOURCE_BYTES + 1)
        else:
            if entry.is_symlink() or not entry.resolve(strict=True).is_relative_to(self.root):
                fail(f"Source escapes directory: {name}")
            if entry.stat().st_size > MAX_SOURCE_BYTES:
                fail(f"Source exceeds 128 MiB: {name}")
            with entry.open("rb") as handle:
                data = handle.read(MAX_SOURCE_BYTES + 1)
        if len(data) > MAX_SOURCE_BYTES:
            fail(f"Source exceeds 128 MiB: {name}")
        return data


def report_path(sources: Sources, path: Path) -> Path:
    if path.is_symlink():
        fail("Report output must not be a symlink")
    path = path.resolve()
    if path == sources.root:
        fail("Report output must not replace the source pack")
    if sources.root.is_dir() and path.is_relative_to(sources.root):
        if path.relative_to(sources.root).as_posix() in sources.entries:
            fail("Report output must not replace a source sample")
    return path


def run_media(arguments: list[str], data: bytes | None = None) -> bytes:
    try:
        result = subprocess.run(arguments, input=data, capture_output=True, timeout=90, check=False)
    except subprocess.TimeoutExpired:
        fail("Audio decode timed out")
    if result.returncode:
        fail("Audio decode failed: " + result.stderr.decode("utf-8", "replace")[-600:].strip())
    return result.stdout


def decode(data: bytes, name: str) -> tuple[np.ndarray, dict]:
    """Force a supported container; keep mono/stereo, convert to 48 kHz floats."""
    container = FORMATS[PurePosixPath(name).suffix.lower()]
    with tempfile.TemporaryDirectory(prefix="breakboss-decode-") as temporary:
        file = Path(temporary) / ("source" + PurePosixPath(name).suffix.lower())
        file.write_bytes(data)
        probe = json.loads(run_media(["ffprobe", "-v", "error", "-f", container,
                                     "-i", str(file), "-show_entries",
                                     "stream=codec_type,sample_rate,channels", "-of", "json"]))
        audio = [stream for stream in probe.get("streams", []) if stream.get("codec_type") == "audio"]
        if len(audio) != 1:
            fail(f"Expected exactly one audio stream: {name}")
        channels = int(audio[0]["channels"])
        if not 1 <= channels <= 2:
            fail(f"Expected mono or stereo audio: {name}")
        raw = run_media(["ffmpeg", "-v", "error", "-nostdin", "-f", container, "-i", str(file),
                         "-map", "0:a:0", "-t", str(MAX_SOURCE_SECONDS + 0.001),
                         "-ar", str(RATE), "-ac", str(channels), "-f", "f32le", "pipe:1"])
    samples = np.frombuffer(raw, dtype="<f4").reshape(-1, channels).astype(np.float64)
    if len(samples) == 0 or len(samples) > MAX_SOURCE_SECONDS * RATE:
        fail(f"Source must contain 0..60 seconds of audio: {name}")
    if not np.isfinite(samples).all():
        fail(f"Source contains non-finite audio: {name}")
    return samples, {"durationSeconds": len(samples) / RATE, "channels": channels,
                     "sourceSampleRate": int(audio[0]["sample_rate"]),
                     "peak": float(np.max(np.abs(samples)))}


def kit_roots(package: Path) -> dict[str, float]:
    """Read current factory IDs/tunings from the supplied package's Swift source."""
    source = (package / "KitLibrary.swift").read_text()
    constants = {key: float(value) for key, value in re.findall(r"\b([A-Z][A-Za-z0-9]*)\s*(?::\s*Float)?\s*=\s*([0-9]+\.[0-9]+)", source)}
    bases, roots = {}, {}
    for name, identifier, frequency in re.findall(
            r"static let (\w+)\s*=\s*KitDefinition\(\s*id:\s*\"([^\"]+)\".*?bassHz:\s*([\w.]+)", source, re.S):
        frequency = constants.get(frequency, frequency)
        bases[name] = roots[identifier] = float(frequency)
    for identifier, base in re.findall(r'variant\(\s*"([^"\n]+)"\s*,\s*"[^"\n]+"\s*,\s*(\w+)', source):
        if base not in bases:
            fail(f"Cannot resolve bass tuning for kit {identifier}")
        roots[identifier] = bases[base]
    if not roots:
        fail("No factory kit IDs found in KitLibrary.swift")
    return roots


def number(item: dict, key: str, lower: float, upper: float, default=None):
    value = item.get(key, default)
    if value is None:
        if default is not None:
            fail(f"{key} must be a finite number in {lower}..{upper}")
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not lower <= value <= upper or not math.isfinite(value):
        fail(f"{key} must be a finite number in {lower}..{upper}")
    return float(value)


def validate_selections(raw, roots: dict[str, float]) -> list[dict]:
    selections = raw.get("selections") if isinstance(raw, dict) else raw
    if not isinstance(selections, list) or not 1 <= len(selections) <= min(MAX_ASSIGNMENTS, len(roots) * 12):
        fail("Selections must be a nonempty list within the factory assignment limit")
    seen, result = set(), []
    for item in selections:
        if not isinstance(item, dict) or set(item) - FIELDS:
            fail("Selection must be an object using only documented fields")
        kit = item.get("kitID")
        pad = item.get("pad")
        if not isinstance(kit, str) or kit not in roots:
            fail(f"Unknown factory kitID: {kit!r}")
        if isinstance(pad, bool) or not isinstance(pad, int) or not 0 <= pad < 12:
            fail("pad must be an integer in 0..15")
        if (kit, pad) in seen:
            fail(f"Duplicate kit/pad assignment: {kit}, {pad}")
        seen.add((kit, pad))
        name = item.get("name")
        if not isinstance(name, str) or not name.strip() or len(name.strip()) > 80 or any(unicodedata.category(c) in {"Cc", "Cf"} for c in name):
            fail("name must contain 1..80 printable characters")
        params = {"startSeconds": number(item, "startSeconds", 0, 59, 0),
                  "tuneSemitones": number(item, "tuneSemitones", -3, 3, 0),
                  "tailSeconds": number(item, "tailSeconds", 0.01, MAX_OUTPUT_SECONDS),
                  "decaySeconds": number(item, "decaySeconds", 0.02, MAX_OUTPUT_SECONDS),
                  "lowpassHz": number(item, "lowpassHz", 1000, 23000),
                  "drive": number(item, "drive", 0, 0.25, 0),
                  "peak": number(item, "peak", 0.05, 0.98, 0.92)}
        if pad == 6:
            source_hz = number(item, "sourceRootHz", 20, 200)
            target_hz = number(item, "targetRootHz", 20, 200)
            if source_hz is None or target_hz is None:
                fail("808 pad 6 requires explicit sourceRootHz and targetRootHz")
            if not math.isclose(target_hz, roots[kit], abs_tol=0.01):
                fail(f"808 targetRootHz must match {kit} bassHz ({roots[kit]})")
            if params["tuneSemitones"] != 0:
                fail("808 tuneSemitones must be zero; tune using sourceRootHz/targetRootHz")
            params.update(sourceRootHz=source_hz, targetRootHz=target_hz)
        elif "sourceRootHz" in item or "targetRootHz" in item:
            fail("Root frequency fields apply only to 808 pad 6")
        result.append({"kitID": kit, "pad": pad, "source": safe_source_name(item.get("source")),
                       "name": name.strip(), "processing": params})
    return sorted(result, key=lambda entry: (entry["kitID"], entry["pad"]))


def process(samples: np.ndarray, params: dict) -> np.ndarray:
    start = round(params["startSeconds"] * RATE)
    if start >= len(samples):
        fail("startSeconds must leave nonempty source audio")
    samples = samples[start:]
    ratio = 2 ** (params["tuneSemitones"] / 12)
    if "sourceRootHz" in params:
        ratio *= params["targetRootHz"] / params["sourceRootHz"]
    if params["tailSeconds"] is None and len(samples) / (RATE * ratio) > MAX_OUTPUT_SECONDS:
        fail("Prepared sample exceeds 12 seconds; set an explicit tailSeconds")
    # Pitch resampling uses ffmpeg's anti-aliasing filter. Subsequent DSP is
    # deterministic numpy work; no noise, random dither, or hidden normalization.
    if not math.isclose(ratio, 1, abs_tol=1e-12):
        raw = run_media(["ffmpeg", "-v", "error", "-nostdin", "-f", "f32le", "-ar", str(RATE),
                         "-ac", str(samples.shape[1]), "-i", "pipe:0", "-af",
                         f"asetrate={RATE * ratio:.9f},aresample={RATE}",
                         "-t", str(params["tailSeconds"] or MAX_OUTPUT_SECONDS),
                         "-f", "f32le", "pipe:1"],
                        samples.astype("<f4").tobytes())
        samples = np.frombuffer(raw, dtype="<f4").reshape(-1, samples.shape[1]).astype(np.float64)
    if params["tailSeconds"] is not None:
        samples = samples[:round(params["tailSeconds"] * RATE)].copy()
    else:
        samples = samples.copy()
    if len(samples) > MAX_OUTPUT_SECONDS * RATE:
        fail("Prepared sample exceeds 12 seconds; set an explicit tailSeconds")
    if params["lowpassHz"] is not None:
        # Stable one-pole tone filter; starts at zero to preserve hit attack.
        coefficient = 1 - math.exp(-2 * math.pi * params["lowpassHz"] / RATE)
        previous = np.zeros(samples.shape[1])
        for frame in samples:
            previous += coefficient * (frame - previous)
            frame[:] = previous
    if params["decaySeconds"] is not None:
        time = np.maximum(np.arange(len(samples)) / RATE - 0.020, 0)
        samples *= np.exp(-time / params["decaySeconds"])[:, None]
    if params["drive"]:
        amount = 1 + 3 * params["drive"]
        samples = np.tanh(samples * amount) / math.tanh(amount)
    # Short edge fades remove clipping clicks while retaining transient body.
    attack = min(24, len(samples))
    release = min(round(0.006 * RATE), len(samples))
    samples[:attack] *= np.linspace(0, 1, attack)[:, None]
    samples[-release:] *= np.linspace(1, 0, release)[:, None]
    peak = float(np.max(np.abs(samples)))
    if peak <= 1e-8:
        fail("Selected source is silent after processing")
    return samples * (params["peak"] / peak)


def wav_bytes(samples: np.ndarray) -> bytes:
    handle = io.BytesIO()
    with wave.open(handle, "wb") as writer:
        writer.setnchannels(samples.shape[1])
        writer.setsampwidth(2)
        writer.setframerate(RATE)
        writer.writeframes(np.round(np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())
    return handle.getvalue()


def write_json(path: Path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False, allow_nan=False) + "\n")


def prepare(sources: Sources, selection_path: Path, package: Path, provenance: Path, replace: bool,
            deduplicate: bool = False):
    package = package.resolve(strict=True)
    provenance = report_path(sources, provenance)
    if provenance.is_relative_to(package):
        fail("Provenance must be outside the app package")
    if provenance == selection_path.resolve():
        fail("Provenance must not replace the selections file")
    roots = kit_roots(package)
    selection_data = selection_path.read_bytes()
    selections = validate_selections(json.loads(selection_data), roots)
    destination = package / "Resources" / "StockSamples"
    if destination.is_symlink() or (package / "Resources").is_symlink():
        fail("Stock sample output directory must not be a symlink")
    if destination.exists() and any(destination.iterdir()) and not replace:
        fail("StockSamples already contains files; use --replace to replace the prepared set")
    if provenance.exists() and not replace:
        fail("Provenance already exists; use --replace to replace it")
    assignments, records = [], []
    total_output_bytes = 0
    decoded = OrderedDict()
    cache_bytes = 0
    unique_files = {}
    # Stage all decodes before publishing, so bad input preserves existing assets.
    with tempfile.TemporaryDirectory(prefix="breakboss-stock-", dir=package.parent) as temporary:
        staging = Path(temporary) / "StockSamples"
        staging.mkdir()
        for item in selections:
            name = item["source"]
            if name in decoded:
                samples, info, source_hash = decoded[name]
                decoded.move_to_end(name)
            else:
                data = sources.read(name)
                samples, info = decode(data, name)
                source_hash = hashlib.sha256(data).hexdigest()
                del data
                if samples.nbytes <= MAX_DECODE_CACHE_BYTES:
                    while decoded and cache_bytes + samples.nbytes > MAX_DECODE_CACHE_BYTES:
                        _, (removed, _, _) = decoded.popitem(last=False)
                        cache_bytes -= removed.nbytes
                    decoded[name] = (samples, info, source_hash)
                    cache_bytes += samples.nbytes
            output = wav_bytes(process(samples, item["processing"]))
            output_hash = hashlib.sha256(output).hexdigest()
            basename = f"bb_{item['kitID']}_p{item['pad']:02d}.wav"
            if not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}", basename):
                fail(f"Kit ID cannot form a safe asset filename: {item['kitID']}")
            shared = None
            if deduplicate:
                shared = next((file for file in unique_files.get(output_hash, [])
                               if (staging / file).read_bytes() == output), None)
            if shared is not None:
                basename = shared
            else:
                total_output_bytes += len(output)
                if total_output_bytes > MAX_TOTAL_OUTPUT_BYTES:
                    fail("Prepared stock samples exceed the 64 MiB app resource budget")
                (staging / basename).write_bytes(output)
                unique_files.setdefault(output_hash, []).append(basename)
            assignments.append({"kitID": item["kitID"], "pad": item["pad"],
                                "file": basename, "displayName": item["name"]})
            records.append({**item, "sourceSHA256": source_hash,
                            "sourceInfo": info, "outputFile": basename,
                            "outputSHA256": output_hash, "outputBytes": len(output)})
        manifest = {"version": 1, "assignments": assignments}
        write_json(staging / "manifest.json", manifest)
        provenance.parent.mkdir(parents=True, exist_ok=True)
        record = {"version": 1, "tool": "prepare_stock_samples.py",
                                "deduplicate": deduplicate,
                                "uniqueOutputFiles": sum(len(files) for files in unique_files.values()),
                                "totalOutputBytes": total_output_bytes,
                                "numpyVersion": np.__version__,
                                "ffmpeg": run_media(["ffmpeg", "-version"]).decode().splitlines()[0],
                                "sampleRate": RATE, "sampleFormat": "PCM signed 16-bit",
                                "edgeFadeMilliseconds": {"attack": 0.5, "release": 6},
                                "selectionsSHA256": hashlib.sha256(selection_data).hexdigest(),
                                "assignments": records}
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if any((path.name != "manifest.json" and not re.fullmatch(r"bb_[A-Za-z0-9_.-]+_p[0-9]{2}\.wav", path.name))
                   or path.is_dir() or path.is_symlink()
                   for path in destination.iterdir()):
                fail("Refusing to replace StockSamples with unrecognized files")
        # Publish provenance from its filesystem and retain old assets until
        # both writes succeed, so disk/path failures cannot destroy a prior set.
        with tempfile.NamedTemporaryFile(prefix=".breakboss-provenance-", dir=provenance.parent,
                                         delete=False) as handle:
            record_path = Path(handle.name)
        backup = Path(temporary) / "previous-StockSamples"
        try:
            write_json(record_path, record)
            if destination.exists():
                destination.rename(backup)
            staging.rename(destination)
            record_path.replace(provenance)
        except OSError:
            if not staging.exists() and destination.exists():
                destination.rename(staging)
            if backup.exists():
                backup.rename(destination)
            raise
        finally:
            record_path.unlink(missing_ok=True)
    return manifest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    inventory = commands.add_parser("inventory", help="Report real source paths, duration, channels and peak")
    inventory.add_argument("source", type=Path)
    inventory.add_argument("--output", type=Path)
    inventory.add_argument("--match", default="*", help="Case-insensitive source path glob, e.g. '*kick*'")
    inventory.add_argument("--limit", type=int, help="Inspect only this many matching sources")
    inventory.add_argument("--paths-only", action="store_true", help="List paths without audio decoding")
    build = commands.add_parser("prepare", help="Prepare explicit real selections and the loader manifest")
    build.add_argument("source", type=Path)
    build.add_argument("selections", type=Path)
    build.add_argument("--package", type=Path, required=True)
    build.add_argument("--provenance", type=Path, required=True)
    build.add_argument("--replace", action="store_true")
    build.add_argument("--deduplicate", action="store_true", help="Share identical prepared WAVs between assignments")
    args = parser.parse_args(argv)
    sources = None
    try:
        if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
            fail("Install ffmpeg and ffprobe before running this tool")
        sources = Sources(args.source)
        if args.command == "inventory":
            if args.output:
                args.output = report_path(sources, args.output)
            if args.limit is not None and not 1 <= args.limit <= MAX_ENTRIES:
                fail(f"Inventory limit must be in 1..{MAX_ENTRIES}")
            matches = [name for name in sorted(sources.entries)
                       if fnmatch.fnmatchcase(name.lower(), args.match.lower())]
            rows = []
            for name in matches[:args.limit]:
                if args.paths_only:
                    rows.append({"source": name})
                    continue
                try:
                    data = sources.read(name)
                    _, info = decode(data, name)
                    rows.append({"source": name, "sourceSHA256": hashlib.sha256(data).hexdigest(), **info})
                except ValueError as error:
                    rows.append({"source": name, "error": str(error)})
            report = {"version": 1, "matchingSources": len(matches),
                      "truncated": len(rows) < len(matches), "samples": rows}
            if args.output:
                write_json(args.output, report)
            else:
                print(json.dumps(report, indent=2, ensure_ascii=False, allow_nan=False))
        else:
            manifest = prepare(sources, args.selections, args.package, args.provenance, args.replace, args.deduplicate)
            print(f"Prepared {len(manifest['assignments'])} real samples in {args.package / 'Resources/StockSamples'}")
        return 0
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    finally:
        if sources:
            sources.close()


if __name__ == "__main__":
    sys.exit(main())
