#!/usr/bin/env python3
"""Build and validate BreakBoss Playgrounds and universal source archives.

The Playgrounds ZIP has Package.swift at its root so Files extracts directly
to a valid .swiftpm package. The source ZIP uses an ordinary BreakBoss-Universal
parent directory. Version and local build number come from Package.swift.
Generated builds, Git data, caches, temporary files and signing material are
excluded. This tool packages existing source files; it does not retrieve keys,
copy credentials, build the application, or update release notes.

  python3 tools/package_release.py --app BreakBoss.swiftpm --repo . --output output
  python3 tools/package_release.py --app BreakBoss.swiftpm --repo . --output output --app-only

Re-running overwrites the selected archives atomically after validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
import zipfile


SOURCE_DIRECTORIES = {"BreakBoss.swiftpm", "AUv3", "xcode", ".github", "Build_Notes", "tools"}
SOURCE_FILES = {"README.md", ".gitignore"}
EXCLUDED_DIRECTORIES = {
    ".git", ".build", ".swiftpm", "__pycache__", "node_modules", ".pytest_cache",
    ".aws", ".codex", ".agents", ".venv", "venv",
}
EXCLUDED_SUFFIXES = {
    ".pyc", ".pyo", ".tmp", ".log", ".p8", ".p12", ".pfx", ".mobileprovision",
    ".cer", ".key", ".pem", ".ipa", ".zip",
}


def include(path: Path, base: Path) -> bool:
    relative = path.relative_to(base)
    if any(part in EXCLUDED_DIRECTORIES or part.endswith((".xcodeproj", ".xcworkspace"))
           for part in relative.parts):
        return False
    if relative.parts[:2] == ("xcode", "build"):
        return False
    if path.name in {".DS_Store", ".env"} or path.name.startswith((".breakboss-", ".codex-", "AuthKey_")):
        return False
    return path.suffix.lower() not in EXCLUDED_SUFFIXES and path.is_file() and not path.is_symlink()


def collect(base: Path) -> dict[str, Path]:
    return {path.relative_to(base).as_posix(): path
            for path in base.rglob("*") if include(path, base)}


def identity(package: Path) -> tuple[str, str, int]:
    manifest = (package / "Package.swift").read_text()
    version = re.search(r'displayVersion:\s*"([0-9]+\.[0-9]+\.[0-9]+)"', manifest)
    build = re.search(r'bundleVersion:\s*"([0-9]+)"', manifest)
    count = re.search(r"static let count\s*=\s*([0-9]+)", (package / "KitLibrary.swift").read_text())
    if not version or not build or not count:
        raise ValueError("Cannot read release version, build number, or pad count")
    if not re.search(r"supportedDeviceFamilies:\s*\[\.phone,\s*\.pad\]", manifest):
        raise ValueError("Package is missing universal iPhone/iPad support")
    return version.group(1), build.group(1), int(count.group(1))


def validate(path: Path, package_prefix: str, version: str, build: str, pad_count: int) -> dict:
    with zipfile.ZipFile(path) as archive:
        failed = archive.testzip()
        if failed is not None:
            raise ValueError(f"ZIP CRC verification failed: {failed}")
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise ValueError("Archive contains duplicate paths")
        for name in names:
            parts = PurePosixPath(name)
            if parts.is_absolute() or ".." in parts.parts or "\\" in name:
                raise ValueError(f"Unsafe archive path: {name}")
        packages = [name for name in names if PurePosixPath(name).name == "Package.swift"]
        expected_package = package_prefix + "Package.swift"
        if packages != [expected_package]:
            raise ValueError(f"Unexpected Package.swift location: {packages}")
        if package_prefix:
            if {name.split("/")[0] for name in names} != {"BreakBoss-Universal"}:
                raise ValueError("Source archive must have one ordinary parent directory")
        elif any(name.startswith(("BreakBoss.swiftpm/", "BreakBoss-Universal/")) for name in names):
            raise ValueError("Playgrounds package files must be at the ZIP root")
        package = archive.read(expected_package).decode()
        if f'displayVersion: "{version}"' not in package or f'bundleVersion: "{build}"' not in package:
            raise ValueError("Archive identity differs from the supplied package")

        stock_prefix = package_prefix + "Resources/StockSamples/"
        manifest = json.loads(archive.read(stock_prefix + "manifest.json"))
        assignments = manifest.get("assignments", [])
        if manifest.get("version") != 1 or not assignments:
            raise ValueError("Missing or unsupported stock manifest")
        kit_ids = {assignment["kitID"] for assignment in assignments}
        addresses = {(assignment["kitID"], assignment["pad"]) for assignment in assignments}
        expected_addresses = {(kit, pad) for kit in kit_ids for pad in range(pad_count)}
        if len(addresses) != len(assignments) or addresses != expected_addresses:
            raise ValueError("Stock manifest does not cover every kit/pad exactly once")
        wavs = set()
        for assignment in assignments:
            filename = assignment["file"]
            if not re.fullmatch(r"[A-Za-z0-9_.-]{1,128}\.wav", filename):
                raise ValueError(f"Unsafe stock filename: {filename}")
            wavs.add(stock_prefix + filename)
        actual_wavs = {name for name in names if name.startswith(stock_prefix) and name.endswith(".wav")}
        if actual_wavs != wavs:
            raise ValueError("Manifest paths and packaged stock WAVs differ")
        if not wavs.issubset(set(names)):
            raise ValueError("A stock sample is missing from the archive")
        return {
            "archive": str(path), "bytes": path.stat().st_size, "files": len(names),
            "packageManifest": expected_package, "version": version, "localBuild": build,
            "stockWavs": len(wavs), "assignments": len(assignments), "kits": len(kit_ids),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        }


def create_archive(path: Path, members: dict[str, Path], prefix: str,
                   version: str, build: str, pad_count: int) -> dict:
    with tempfile.NamedTemporaryFile(prefix=".breakboss-package-", suffix=".zip",
                                     dir=path.parent, delete=False) as temporary:
        staging = Path(temporary.name)
    try:
        with zipfile.ZipFile(staging, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for name, source in sorted(members.items()):
                archive.write(source, arcname=name)
        result = validate(staging, prefix, version, build, pad_count)
        staging.replace(path)
        result["archive"] = str(path)
        return result
    finally:
        staging.unlink(missing_ok=True)


def package_release(app: Path, repo: Path, output: Path, app_only: bool, source_only: bool) -> list[dict]:
    app, repo = app.resolve(strict=True), repo.resolve(strict=True)
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    version, build, pad_count = identity(app)
    app_files = collect(app)
    repo_app_files = collect(repo / "BreakBoss.swiftpm")
    if app_files.keys() != repo_app_files.keys() or any(
            app_files[name].read_bytes() != repo_app_files[name].read_bytes() for name in app_files):
        raise ValueError("Local application and release checkout sources differ")
    results = []
    if not source_only:
        results.append(create_archive(output / f"BreakBoss-v{version}.swiftpm.zip", app_files,
                                      "", version, build, pad_count))
    if not app_only:
        members = {"BreakBoss-Universal/" + name: path for name, path in collect(repo).items()
                   if name.split("/")[0] in SOURCE_DIRECTORIES or name in SOURCE_FILES}
        results.append(create_archive(output / f"BreakBoss-v{version}-Universal-Source.zip", members,
                                      "BreakBoss-Universal/BreakBoss.swiftpm/", version, build, pad_count))
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    kind = parser.add_mutually_exclusive_group()
    kind.add_argument("--app-only", action="store_true")
    kind.add_argument("--source-only", action="store_true")
    args = parser.parse_args()
    try:
        results = package_release(args.app, args.repo, args.output, args.app_only, args.source_only)
        print(json.dumps(results, indent=2))
        return 0
    except (ValueError, OSError, KeyError, TypeError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
