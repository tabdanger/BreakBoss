#!/usr/bin/env python3
"""Run the real BreakBoss self-test and snapshot renderer on iPhone and iPad."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import time


def simctl(*arguments, check=True, timeout=180, **kwargs):
    return subprocess.run(["xcrun", "simctl", *arguments], check=check,
                          timeout=timeout, text=True, **kwargs)


def select_devices(device_list):
    """Use the newest installed available iOS runtime with both device families."""
    runtimes = []
    for runtime, devices in device_list.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        devices = [d for d in devices if d.get("isAvailable", True)]
        phones = [d for d in devices if d["name"].startswith("iPhone")]
        pads = [d for d in devices if d["name"].startswith("iPad")]
        if phones and pads:
            version = tuple(int(x) for x in re.findall(r"\d+", runtime))
            runtimes.append((version, phones, pads))
    if not runtimes:
        raise RuntimeError("No available iOS runtime contains both iPhone and iPad simulators")
    _, phones, pads = max(runtimes, key=lambda value: value[0])
    # Prefer the regular Pro phone and 11-inch tablet to exercise realistic screen widths.
    phone = next((d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]), phones[0])
    pad = next((d for d in pads if "11-inch" in d["name"]), pads[0])
    return [("iphone", phone), ("ipad", pad)]


def result_state(text):
    # A failure is authoritative even if a stale success line was also logged.
    if "SELF-TEST FAILED" in text:
        return "failed"
    if "self-test passed" in text:
        return "passed"
    return None


def expected_layout_names(family):
    device = {"iphone": "phone", "ipad": "tablet"}[family]
    return {f"layout-{device}-{mode}-{play}.png"
            for mode in ("modern", "vintage", "texture") for play in ("loop", "oneshot")}


def missing_layout_names(family, cache):
    expected_size = {"iphone": (590, 1280), "ipad": (1448, 1086)}[family]
    missing = []
    for name in sorted(expected_layout_names(family)):
        path = cache / name if cache else None
        if not path or not path.is_file():
            missing.append(name)
            continue
        with path.open("rb") as file:
            header = file.read(24)
            if path.stat().st_size >= 12:
                file.seek(-12, 2)
            trailer = file.read(12)
        if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
            missing.append(name)
        elif struct.unpack(">II", header[16:24]) != expected_size:
            missing.append(name)
        elif trailer != b"\0\0\0\0IEND\xaeB`\x82":
            missing.append(name)
    return missing


def verify_bundle(app):
    for bundle in (app, app / "PlugIns" / "BreakBossAU.appex"):
        with (bundle / "Info.plist").open("rb") as file:
            info = plistlib.load(file)
        if set(info.get("UIDeviceFamily", [])) != {1, 2}:
            raise RuntimeError(f"{bundle.name} must support both iPhone and iPad (UIDeviceFamily 1,2)")
        manifests = [path for path in bundle.rglob("manifest.json")
                     if "PlugIns" not in path.relative_to(bundle).parts]
        if len(manifests) != 1:
            raise RuntimeError(f"{bundle.name} must contain one stock sample manifest")
        manifest = manifests[0]
        assignments = json.loads(manifest.read_text())["assignments"]
        if not assignments:
            raise RuntimeError(f"{bundle.name} has an empty stock sample manifest")
        for assignment in assignments:
            filename = assignment["file"]
            if Path(filename).name != filename or not (manifest.parent / filename).is_file():
                raise RuntimeError(f"{bundle.name} is missing stock sample {filename}")
        print(f"::notice title=Stock sounds::{bundle.name}: {len(assignments)} pad assignments resolve", flush=True)
    print("::notice title=Universal app::App and AUv3 support iPhone and iPad", flush=True)


def data_container(udid, bundle_id):
    result = simctl("get_app_container", udid, bundle_id, "data", check=False,
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    return Path(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else None


def combined_log(console, data):
    text = console.read_text(errors="replace") if console.exists() else ""
    if data:
        cached = data / "Library" / "Caches" / "BreakBoss-selftest.log"
        if cached.exists():
            text += "\n" + cached.read_text(errors="replace")
    return text


def run_device(family, device, app, bundle_id, output, timeout):
    udid = device["udid"]
    print(f"::notice title=Simulator::{family}: {device['name']}", flush=True)
    simctl("boot", udid, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    simctl("bootstatus", udid, "-b")
    simctl("install", udid, str(app))
    # A clean install/data container prevents prior successful self-test logs from masking a crash.
    data = data_container(udid, bundle_id)
    if data:
        for old in (data / "Library" / "Caches").glob("layout-*.png"):
            old.unlink()
        (data / "Library" / "Caches" / "BreakBoss-selftest.log").unlink(missing_ok=True)
    console = output / f"console-{family}.log"
    selftest = output / f"selftest-{family}.log"
    environment = dict(os.environ, SIMCTL_CHILD_BREAKBOSS_SELFTEST="1",
                       SIMCTL_CHILD_BREAKBOSS_SNAPSHOTS="1")
    shots = output / "shots"
    shots.mkdir(parents=True, exist_ok=True)
    launch = None
    state = None
    failure = None
    try:
        with console.open("w") as file:
            launch = subprocess.Popen(
                ["xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", udid, bundle_id],
                stdout=file, stderr=subprocess.STDOUT, env=environment)
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                data = data or data_container(udid, bundle_id)
                text = combined_log(console, data)
                selftest.write_text(text)
                state = result_state(text)
                if state:
                    break
                if launch.poll() is not None:
                    failure = f"{family} app exited before producing a self-test result"
                    break
                time.sleep(2)
            if state == "passed":
                # Require six complete images for this actual simulator's device family.
                # Other-device override renders cannot stand in for a missing phone/tablet render.
                deadline = time.monotonic() + 30
                missing = sorted(expected_layout_names(family))
                while time.monotonic() < deadline:
                    missing = missing_layout_names(family, data / "Library" / "Caches" if data else None)
                    if not missing:
                        break
                    time.sleep(1)
                if missing:
                    failure = f"{family} self-test passed but required faceplate PNGs are missing or invalid: {', '.join(missing)}"
                else:
                    print(f"::notice title=Self-test::{family} self-test passed; all six device layouts rendered", flush=True)
            elif state == "failed":
                failure = f"{family} SELF-TEST FAILED; see selftest-{family}.log"
            elif failure is None:
                failure = f"{family} app produced no self-test result within {timeout} seconds"
    finally:
        if data:
            for source in (data / "Library" / "Caches").glob("layout-*.png"):
                if source.name in expected_layout_names(family):
                    shutil.copy2(source, shots / f"{source.stem}-{family}{source.suffix}")
        # This is the actual displayed app inside the simulated device, including its safe area,
        # home-indicator inset and the device's screen proportions; ImageRenderer PNGs are separate.
        screenshot = shots / f"simulator-{family}.png"
        try:
            result = simctl("io", udid, "screenshot", str(screenshot), check=False, timeout=30)
            if result.returncode != 0 or not screenshot.is_file():
                failure = failure or f"{family} actual simulator screenshot could not be captured"
        except subprocess.TimeoutExpired:
            failure = failure or f"{family} simulator screenshot timed out after 30 seconds"
        # Copy a bounded tail to job stdout so result counts, phase timings and failures remain
        # inspectable through the GitHub logs connector even when artifact downloads are unavailable.
        text = combined_log(console, data)
        selftest.write_text(text)
        print(f"::group::{family} self-test log (last 40 lines)", flush=True)
        print("\n".join(text.splitlines()[-40:]) or "No self-test output was captured.", flush=True)
        print("::endgroup::", flush=True)
        try:
            simctl("terminate", udid, bundle_id, check=False, stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, timeout=30)
        except subprocess.TimeoutExpired:
            print(f"::warning title=Simulator cleanup::{family} termination timed out", flush=True)
        if launch and launch.poll() is None:
            launch.terminate()
            try:
                launch.wait(timeout=10)
            except subprocess.TimeoutExpired:
                launch.kill()
        if data:
            selftest.write_text(combined_log(console, data))
        # Shut down between families to reduce simulator memory/CPU use on the runner.
        try:
            simctl("shutdown", udid, check=False, stdout=subprocess.PIPE,
                   stderr=subprocess.PIPE, timeout=30)
        except subprocess.TimeoutExpired:
            print(f"::warning title=Simulator cleanup::{family} shutdown timed out", flush=True)
    if failure:
        raise RuntimeError(failure)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--products", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("--verify-bundle", type=Path)
    arguments = parser.parse_args()
    if arguments.verify_bundle:
        verify_bundle(arguments.verify_bundle)
        return
    if not arguments.products or not arguments.output:
        parser.error("--products and --output are required to run simulators")
    apps = sorted(arguments.products.glob("*iphonesimulator/BreakBoss.app"))
    if len(apps) != 1:
        raise RuntimeError(f"Expected one simulator BreakBoss.app; found {len(apps)}")
    app = apps[0]
    with (app / "Info.plist").open("rb") as file:
        bundle_id = plistlib.load(file)["CFBundleIdentifier"]
    listing = simctl("list", "devices", "available", "-j", stdout=subprocess.PIPE)
    arguments.output.mkdir(parents=True, exist_ok=True)
    failures = []
    for family, device in select_devices(json.loads(listing.stdout)):
        try:
            run_device(family, device, app, bundle_id, arguments.output, arguments.timeout)
        except Exception as error:
            failures.append(str(error))
            print(f"::error title=Simulator self-test::{error}", flush=True)
    if failures:
        raise RuntimeError("; ".join(failures))


if __name__ == "__main__":
    main()
