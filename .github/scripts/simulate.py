#!/usr/bin/env python3
"""Run the real BreakBoss self-test and snapshot renderer on an iPad."""
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
    """Use the newest installed available iOS runtime with an iPad."""
    runtimes = []
    for runtime, devices in device_list.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        devices = [d for d in devices if d.get("isAvailable", True)]
        pads = [d for d in devices if d["name"].startswith("iPad")]
        if pads:
            version = tuple(int(x) for x in re.findall(r"\d+", runtime))
            runtimes.append((version, pads))
    if not runtimes:
        raise RuntimeError("No available iOS runtime contains an iPad simulator")
    _, pads = max(runtimes, key=lambda value: value[0])
    # Prefer the 11-inch tablet to exercise a realistic screen width.
    pad = next((d for d in pads if "11-inch" in d["name"]), pads[0])
    return [("ipad", pad)]


def result_state(text):
    # A failure is authoritative even if a stale success line was also logged.
    if "SELF-TEST FAILED" in text:
        return "failed"
    if "self-test passed" in text:
        return "passed"
    return None


def expected_layout_names(family):
    device = {"ipad": "tablet"}[family]
    return {f"layout-{device}-{mode}-{play}.png"
            for mode in ("modern", "vintage", "texture") for play in ("loop", "oneshot")}


def missing_layout_names(family, cache, started=None):
    expected_size = {"ipad": (1450, 1085)}[family]
    missing = []
    for name in sorted(expected_layout_names(family)):
        path = cache / name if cache else None
        if not path or not path.is_file() or (started is not None and path.stat().st_mtime < started):
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
        if set(info.get("UIDeviceFamily", [])) != {2}:
            raise RuntimeError(f"{bundle.name} must be iPad-only for now (UIDeviceFamily 2)")
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
    print("::notice title=iPad app::App and AUv3 are iPad-only for now", flush=True)


def local_data_container(udid, bundle_id):
    # The standard runner device set contains the installer's identifier metadata. Reading
    # it avoids a cold CoreSimulator/containermanagerd RPC blocking app launch altogether.
    containers = Path.home() / "Library/Developer/CoreSimulator/Devices" / udid / "data/Containers/Data/Application"
    for metadata in containers.glob("*/.com.apple.mobile_container_manager.metadata.plist"):
        try:
            with metadata.open("rb") as file:
                info = plistlib.load(file)
            if info.get("MCMMetadataIdentifier") == bundle_id:
                return metadata.parent
        except (OSError, ValueError, plistlib.InvalidFileException):
            continue
    return None


def data_container(udid, bundle_id):
    local = local_data_container(udid, bundle_id)
    if local:
        return local
    try:
        result = simctl("get_app_container", udid, bundle_id, "data", check=False,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5)
        return Path(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else None
    except subprocess.TimeoutExpired:
        # Container creation/indexing can lag behind installation on the first boot. The
        # console still reports the result, and subsequent polls retry finding PNGs/cache logs.
        return None


def capture_diagnostics(family, udid, output, started):
    predicate = 'process == "BreakBoss" OR ((process == "SpringBoard" OR process == "runningboardd" OR process == "containermanagerd") AND eventMessage CONTAINS[c] "com.tabdanger.BreakBoss")'
    path = output / f"simulator-diagnostics-{family}.log"
    try:
        result = simctl("spawn", udid, "log", "show", "--style", "compact", "--last", "10m",
                        "--predicate", predicate, check=False, timeout=20,
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        path.write_text(result.stdout)
        print(f"::group::{family} startup diagnostics (last 40 lines)", flush=True)
        print("\n".join(result.stdout.splitlines()[-40:]) or "No matching system log entries.", flush=True)
        print("::endgroup::", flush=True)
    except subprocess.TimeoutExpired:
        path.write_text("Simulator system-log query timed out after 20 seconds.\n")
    reports = output / "crash-reports"
    reports.mkdir(exist_ok=True)
    roots = [Path.home() / "Library/Logs/DiagnosticReports",
             Path.home() / "Library/Developer/CoreSimulator/Devices" / udid / "data/Library/Logs"]
    candidates = []
    for root in roots:
        if root.is_dir():
            candidates.extend(p for p in root.rglob("*.ips")
                              if ("BreakBoss" in p.name or "JetsamEvent" in p.name) and p.stat().st_mtime >= started)
    for source in sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True)[:3]:
        shutil.copy2(source, reports / f"{family}-{source.name}")
        try:
            raw = source.read_text(errors="replace")
            # Apple .ips files have a metadata JSON line followed by the report JSON.
            header, _, body = raw.partition("\n")
            report = json.loads(body or header)
            summary = {key: report.get(key) for key in ("procName", "exception", "termination", "faultingThread", "asi")}
            print(f"{family} crash summary: {json.dumps(summary, ensure_ascii=True)[:6000]}", flush=True)
        except (ValueError, OSError):
            print(f"{family} crash report retained: {source.name}", flush=True)


def combined_log(console, data, started=None):
    text = console.read_text(errors="replace") if console.exists() else ""
    if data:
        cached = data / "Library" / "Caches" / "BreakBoss-selftest.log"
        if cached.exists() and (started is None or cached.stat().st_mtime >= started):
            text += "\n" + cached.read_text(errors="replace")
    return text


def run_device(family, device, app, bundle_id, output, timeout):
    udid = device["udid"]
    print(f"::notice title=Simulator::{family}: {device['name']}", flush=True)
    console = output / f"console-{family}.log"
    selftest = output / f"selftest-{family}.log"
    environment = dict(os.environ, SIMCTL_CHILD_BREAKBOSS_SELFTEST="1",
                       SIMCTL_CHILD_BREAKBOSS_SNAPSHOTS="1")
    shots = output / "shots"
    shots.mkdir(parents=True, exist_ok=True)
    launch = None
    state = None
    failure = None
    data = None
    installed = False
    started = time.time()
    launch_started = started
    try:
        simctl("boot", udid, check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        simctl("bootstatus", udid, "-b")
        simctl("install", udid, str(app))
        installed = True
        # Read existing cache files locally when available. Do not issue a container-manager
        # RPC before launch: it stalled first-boot iPhone startup on the hosted Mac runner.
        data = local_data_container(udid, bundle_id)
        if data:
            for old in (data / "Library" / "Caches").glob("layout-*.png"):
                old.unlink()
            (data / "Library" / "Caches" / "BreakBoss-selftest.log").unlink(missing_ok=True)
        with console.open("w") as file:
            launch_started = time.time()
            launch = subprocess.Popen(
                ["xcrun", "simctl", "launch", "--console-pty", "--terminate-running-process", udid, bundle_id],
                stdout=file, stderr=subprocess.STDOUT, env=environment)
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                data = data or data_container(udid, bundle_id)
                text = combined_log(console, data, launch_started)
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
                    data = data or data_container(udid, bundle_id)
                    missing = missing_layout_names(family, data / "Library" / "Caches" if data else None, launch_started)
                    if not missing:
                        break
                    time.sleep(1)
                if missing:
                    failure = f"{family} self-test passed but required faceplate PNGs are missing or invalid: {', '.join(missing)}"
                else:
                    print(f"::notice title=Self-test::{family} self-test passed; all six device layouts rendered", flush=True)
            elif state == "failed":
                failure = f"{family} SELF-TEST FAILED; see selftest-{family}.log"
                try:
                    lines = [l for l in selftest.read_text(errors="replace").splitlines() if "SELF-TEST FAILED:" in l]
                    for line in lines[:25]:
                        print(f"::error title={family} check::{line.split('SELF-TEST FAILED:', 1)[1].strip()[:300]}", flush=True)
                except OSError:
                    pass
            elif failure is None:
                failure = f"{family} app produced no self-test result within {timeout} seconds"
    finally:
        if state != "passed" or failure:
            try:
                capture_diagnostics(family, udid, output, started)
            except (OSError, subprocess.SubprocessError) as error:
                print(f"::warning title=Simulator diagnostics::{family}: {error}", flush=True)
        if data:
            for source in (data / "Library" / "Caches").glob("layout-*.png"):
                if source.name in expected_layout_names(family) and source.stat().st_mtime >= launch_started:
                    shutil.copy2(source, shots / f"{source.stem}-{family}{source.suffix}")
        # This is the actual displayed app inside the simulated device, including its safe area,
        # home-indicator inset and the device's screen proportions; ImageRenderer PNGs are separate.
        screenshot = shots / f"simulator-{family}.png"
        if installed:
            # The live screenshot is a picture for review, not a test: retry once, then warn.
            captured = False
            for attempt in (1, 2):
                try:
                    result = simctl("io", udid, "screenshot", str(screenshot), check=False, timeout=60)
                    if result.returncode == 0 and screenshot.is_file():
                        captured = True
                        break
                except subprocess.TimeoutExpired:
                    pass
            if not captured:
                print(f"::warning title=Simulator screenshot::{family} live screenshot not captured "
                      "(self-test and faceplate renders are what count)", flush=True)
        # Copy a bounded tail to job stdout so result counts, phase timings and failures remain
        # inspectable through the GitHub logs connector even when artifact downloads are unavailable.
        text = combined_log(console, data, launch_started)
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
            selftest.write_text(combined_log(console, data, launch_started))
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
