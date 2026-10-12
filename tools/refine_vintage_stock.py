#!/usr/bin/env python3
"""Refine three source roles in the six primary Vintage kits, entirely offline.

Requires the retained source directory (or a ZIP with those relative paths),
numpy, ffmpeg, ffprobe, and prepare_stock_samples.py in the same directory.

  python3 tools/refine_vintage_stock.py stock-source-selection \
      --package BreakBoss.swiftpm --selections Build_Notes/STOCK_SELECTIONS.json \
      --provenance Build_Notes/STOCK_SAMPLE_PROVENANCE.json

The existing manifest and provenance are checked before changing anything.
Only changed kick/snare/rim assignments are decoded and rendered. Other pad
audio and all 808 calibration records remain byte-identical. Identical outputs
are shared, and only WAVs no longer referenced by the manifest are removed.
--check verifies the applied recipe and files without modifying the bank.

These are uploaded-hit tonal variations, not verified acoustic recordings.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile

import numpy as np

from prepare_stock_samples import (
    MAX_TOTAL_OUTPUT_BYTES, Sources, decode, fail, kit_roots, process,
    validate_selections, wav_bytes,
)


KICK = "7-Kicks/Kicks/[Kick] Spheres - (@prod.by.iiinfinite).wav"
AGENCY = "10-Snares/Snares/[Snare] Agency - (@prod.by.iiinfinite).wav"
GRAVITY = "10-Snares/Snares/[Snare] Gravity - (@prod.by.iiinfinite).wav"
RIM = "1-Rims/Rims/[Rim] Flights - (@prod.by.iiinfinite).wav"
REFINEMENT_ID = "vintage-body-2026-10-12"

# Each recipe is source, semitones, maximum tail, exponential decay, LP Hz,
# and mild offline drive. Existing pad peaks, all other pads, and bass roots
# are retained. Small differences distinguish the six kits before their FX.
RECIPES = {
    "boom-bap": {
        0: (KICK, -0.50, 0.24, 0.22, 5500, 0.060),
        1: (GRAVITY, -0.35, 0.18, 0.20, 10500, 0.060),
        3: (RIM, -0.50, 0.105, None, 10000, 0.025),
    },
    "live-soul": {
        0: (KICK, -0.25, 0.24, 0.26, 6500, 0.015),
        1: (AGENCY, -0.40, 0.20, 0.24, 11000, 0.012),
        3: (RIM, -0.25, 0.105, None, 11500, 0.004),
    },
    "vintage-rnb": {
        0: (KICK, -0.50, 0.24, 0.26, 6000, 0.020),
        1: (AGENCY, -0.75, 0.20, 0.22, 10000, 0.020),
        3: (RIM, -0.50, 0.105, None, 10500, 0.008),
    },
    "dirty-soul": {
        0: (KICK, -0.75, 0.23, 0.18, 5000, 0.085),
        1: (GRAVITY, -0.75, 0.18, 0.15, 7500, 0.080),
        3: (RIM, -0.75, 0.105, None, 8000, 0.032),
    },
    "funk-break": {
        0: (KICK, 0.25, 0.24, 0.27, 6800, 0.030),
        1: (GRAVITY, 0.25, 0.18, 0.24, 12500, 0.025),
        3: (RIM, 0.25, 0.105, None, 12000, 0.012),
    },
    "loose-break": {
        0: (KICK, 0.00, 0.24, 0.28, 6500, 0.022),
        1: (AGENCY, 0.00, 0.20, 0.27, 12000, 0.020),
        3: (RIM, 0.00, 0.105, None, 11000, 0.008),
    },
}


def json_bytes(value) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + "\n").encode()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def address(item: dict) -> tuple[str, int]:
    return item["kitID"], item["pad"]


def indexed(items: list[dict], label: str) -> dict:
    result = {}
    for item in items:
        key = address(item)
        if key in result:
            fail(f"Duplicate {label} assignment: {key}")
        result[key] = item
    return result


def atomic_write(path: Path, data: bytes):
    with tempfile.NamedTemporaryFile(prefix=".breakboss-refine-", dir=path.parent,
                                     delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(data)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def refine(source: Path, package: Path, selections_path: Path,
           provenance_path: Path, check: bool = False) -> dict:
    for path in (source, package, selections_path, provenance_path):
        if path.is_symlink():
            fail(f"Symlink input refused: {path}")
    package = package.resolve(strict=True)
    selections_path = selections_path.resolve(strict=True)
    provenance_path = provenance_path.resolve(strict=True)
    if selections_path == provenance_path:
        fail("Selections and provenance must use separate files")
    if selections_path.is_relative_to(package) or provenance_path.is_relative_to(package):
        fail("Selection/provenance reports must remain outside the application package")
    folder = package / "Resources" / "StockSamples"
    if folder.is_symlink() or folder.parent.is_symlink():
        fail("Stock output directory must not be a symlink")
    for path in folder.iterdir():
        if path.is_symlink() or not path.is_file() or (path.name != "manifest.json" and
                not re.fullmatch(r"bb_[A-Za-z0-9_.-]+_p[0-9]{2}\.wav", path.name)):
            fail(f"Unrecognized stock resource: {path.name}")

    old_selection_bytes = selections_path.read_bytes()
    old_provenance_bytes = provenance_path.read_bytes()
    selection_data = json.loads(old_selection_bytes)
    provenance = json.loads(old_provenance_bytes)
    manifest = json.loads((folder / "manifest.json").read_bytes())
    if not isinstance(selection_data, dict) or "selections" not in selection_data:
        fail("Expected an object containing the full selections list")
    roots = kit_roots(package)
    current = indexed(validate_selections(selection_data, roots), "selection")
    records = indexed(provenance["assignments"], "provenance")
    assignments = indexed(manifest["assignments"], "manifest")
    if manifest.get("version") != 1 or provenance.get("version") != 1:
        fail("Unsupported existing stock format")
    if not len(current) == len(roots) * 16 == 544 or len(roots) != 34:
        fail("Expected the complete 34-kit, 544-assignment stock bank")
    if set(current) != set(records) or set(current) != set(assignments):
        fail("Manifest, selections, and provenance addresses differ")
    if provenance.get("selectionsSHA256") != sha(old_selection_bytes):
        fail("Selection bytes differ from the recorded provenance")

    old_files = {}
    for key, record in records.items():
        original = current[key]
        if any(record[field] != original[field]
               for field in ("kitID", "pad", "source", "name", "processing")):
            fail(f"Selection/provenance content differs: {key}")
        assignment = assignments[key]
        name = record["outputFile"]
        if assignment["file"] != name or assignment["displayName"] != record["name"]:
            fail(f"Manifest/provenance content differs: {key}")
        if not re.fullmatch(r"bb_[A-Za-z0-9_.-]+_p[0-9]{2}\.wav", name):
            fail(f"Unsafe existing output filename: {name}")
        if name not in old_files:
            data = (folder / name).read_bytes()
            old_files[name] = {"hash": sha(data), "bytes": len(data)}
        if old_files[name]["hash"] != record["outputSHA256"] or \
                old_files[name]["bytes"] != record["outputBytes"]:
            fail(f"Existing WAV differs from provenance: {name}")
    if set(old_files) != {p.name for p in folder.glob("*.wav")}:
        fail("Existing stock folder contains unreferenced audio")

    updated_selection_data = copy.deepcopy(selection_data)
    for item in updated_selection_data["selections"]:
        recipe = RECIPES.get(item["kitID"], {}).get(item["pad"])
        if recipe is None:
            continue
        src, tune, tail, decay, cutoff, drive = recipe
        item.update(source=src, tuneSemitones=tune, tailSeconds=tail,
                    lowpassHz=cutoff, drive=drive, startSeconds=0)
        if decay is None:
            item.pop("decaySeconds", None)
        else:
            item["decaySeconds"] = decay
    updated = indexed(validate_selections(updated_selection_data, roots), "updated selection")
    changes = {key: item for key, item in updated.items() if item != current[key]}
    allowed = {(kit, pad) for kit, pads in RECIPES.items() for pad in pads}
    if not set(changes).issubset(allowed):
        fail("Refinement attempted to change an unrelated pad")
    if check:
        if changes:
            fail(f"Vintage recipe has not been applied to {len(changes)} assignments")
        return {"status": "PASS", "changedAssignments": 0, "uniqueWavs": len(old_files),
                "totalWavBytes": sum(v["bytes"] for v in old_files.values()),
                "bassCalibrationsUnchanged": 34}
    if not changes:
        return {"status": "UNCHANGED", "changedAssignments": 0,
                "uniqueWavs": len(old_files), "bassCalibrationsUnchanged": 34}

    new_provenance = copy.deepcopy(provenance)
    new_manifest = copy.deepcopy(manifest)
    new_records = indexed(new_provenance["assignments"], "new provenance")
    new_assignments = indexed(new_manifest["assignments"], "new manifest")
    generated = {}
    decoded = {}
    hashes = {}
    for name, info in sorted(old_files.items()):
        hashes.setdefault(info["hash"], []).append(name)
    sources = Sources(source)
    try:
        for key, item in sorted(changes.items()):
            src = item["source"]
            if src not in decoded:
                data = sources.read(src)
                audio, info = decode(data, src)
                decoded[src] = audio, info, sha(data)
                known_hashes = {r["sourceSHA256"] for r in records.values() if r["source"] == src}
                if known_hashes != {sha(data)}:
                    fail(f"Retained source hash differs from recorded source: {src}")
            audio, info, source_hash = decoded[src]
            output = wav_bytes(process(audio, item["processing"]))
            output_hash = sha(output)
            shared = next((name for name in hashes.get(output_hash, [])
                           if (generated.get(name) if name in generated else
                               (folder / name).read_bytes()) == output), None)
            name = shared or f"bb_vintage32-{item['kitID']}_p{item['pad']:02d}.wav"
            if shared is None:
                if name in old_files and old_files[name]["hash"] != output_hash:
                    fail(f"Reserved refined WAV filename already contains different audio: {name}")
                generated[name] = output
                hashes.setdefault(output_hash, []).append(name)
            new_records[key].clear()
            new_records[key].update(**item, sourceSHA256=source_hash, sourceInfo=info,
                                    outputFile=name, outputSHA256=output_hash,
                                    outputBytes=len(output))
            new_assignments[key].update(file=name, displayName=item["name"])
    finally:
        sources.close()

    for key in records:
        if key not in changes and (new_records[key] != records[key] or
                                   new_assignments[key] != assignments[key]):
            fail(f"An unrelated stock pad changed: {key}")
        if key[1] == 6 and new_records[key] != records[key]:
            fail(f"808 calibration changed: {key}")
    referenced = {a["file"] for a in new_manifest["assignments"]}
    removed = set(old_files) - referenced
    total_bytes = sum(len(generated[name]) if name in generated else old_files[name]["bytes"]
                      for name in referenced)
    if total_bytes > MAX_TOTAL_OUTPUT_BYTES:
        fail("Refined bank exceeds the 64 MiB stock budget")
    selection_bytes = json_bytes(updated_selection_data)
    new_provenance.update(uniqueOutputFiles=len(referenced), totalOutputBytes=total_bytes,
                          selectionsSHA256=sha(selection_bytes))
    refinements = new_provenance.setdefault("refinements", [])
    refinements.append({"id": REFINEMENT_ID, "tool": "refine_vintage_stock.py",
                        "numpyVersion": np.__version__,
                        "sourceScope": "Retained uploaded hits; acoustic origin unverified",
                        "changedAssignments": [{"kitID": k, "pad": p} for k, p in sorted(changes)],
                        "untouchedBassCalibrations": 34})

    # Prepare the complete coherent bank before replacing it. Unmodified WAVs
    # are copied byte-for-byte, and unused old outputs stay in the backup until
    # both external reports have also been published successfully.
    with tempfile.TemporaryDirectory(prefix="breakboss-vintage-", dir=package.parent) as temporary:
        staging = Path(temporary) / "StockSamples"
        backup = Path(temporary) / "previous-StockSamples"
        staging.mkdir()
        for name in sorted(referenced):
            if name in generated:
                (staging / name).write_bytes(generated[name])
            else:
                shutil.copy2(folder / name, staging / name)
        (staging / "manifest.json").write_bytes(json_bytes(new_manifest))
        try:
            folder.rename(backup)
            staging.rename(folder)
            atomic_write(selections_path, selection_bytes)
            atomic_write(provenance_path, json_bytes(new_provenance))
        except OSError:
            if not staging.exists() and folder.exists():
                folder.rename(staging)
            if backup.exists():
                backup.rename(folder)
            atomic_write(selections_path, old_selection_bytes)
            atomic_write(provenance_path, old_provenance_bytes)
            raise

    return {"status": "PASS", "changedAssignments": len(changes),
            "generatedWavs": len(generated), "removedUnreferencedWavs": len(removed),
            "uniqueWavs": len(referenced), "totalWavBytes": total_bytes,
            "bassCalibrationsUnchanged": 34,
            "changedPads": [{"kitID": k, "pad": p} for k, p in sorted(changes)]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--selections", type=Path, required=True)
    parser.add_argument("--provenance", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        if not args.check and (not shutil.which("ffmpeg") or not shutil.which("ffprobe")):
            fail("Install ffmpeg and ffprobe before refining the stock bank")
        result = refine(args.source, args.package, args.selections, args.provenance, args.check)
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, OSError, KeyError, TypeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
