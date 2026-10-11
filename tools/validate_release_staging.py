#!/usr/bin/env python3
"""Check the actual app/AUv3 staging produced by xcode/generate.py.

Run the generator first. This verifies inputs/resources; it is not an Apple SDK build.
Uses only Python's standard library.
"""
import hashlib
import json
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "BreakBoss.swiftpm"
BUILD = ROOT / "xcode" / "build"
APP_ONLY = {"BreakBossApp.swift", "AppAudioHost.swift", "KnockSelfTest.swift"}
ACCENT = "Assets.xcassets/__PresetAccentColor.colorset/Contents.json"


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def files_at(directory):
    return {str(path.relative_to(directory)): path for path in directory.rglob("*") if path.is_file()}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    require(BUILD.is_dir(), "Run python3 xcode/generate.py before validating staging")
    source_files = {path.name: path for path in PACKAGE.glob("*.swift") if path.name != "Package.swift"}
    resource_files = files_at(PACKAGE / "Resources")
    report = {"validation": "source/resource staging; no Apple SDK compilation", "targets": {}}

    for target in ("app", "plugin"):
        expected_sources = {name: path for name, path in source_files.items() if target != "plugin" or name not in APP_ONLY}
        staged_sources = files_at(BUILD / target / "Sources")
        require(staged_sources.keys() == expected_sources.keys(), f"{target}: staged Swift source set differs")
        for name, original in expected_sources.items():
            require(digest(staged_sources[name]) == digest(original), f"{target}: Swift source differs: {name}")

        expected_resources = {
            name: path for name, path in resource_files.items()
            if target != "plugin" or not name.startswith("Assets.xcassets/AppIcon.appiconset/")
        }
        staged_resources = files_at(BUILD / target / "Resources")
        require(set(staged_resources) == set(expected_resources) | {ACCENT}, f"{target}: staged resource set differs")
        for name, original in expected_resources.items():
            require(digest(staged_resources[name]) == digest(original), f"{target}: resource differs: {name}")
        require("PrivacyInfo.xcprivacy" in staged_resources, f"{target}: privacy manifest missing")

        manifest_path = BUILD / target / "Resources" / "StockSamples" / "manifest.json"
        manifest = json.loads(manifest_path.read_text())
        assignments = manifest["assignments"]
        require(manifest["version"] == 1, f"{target}: unsupported stock manifest")
        require(len({(item["kitID"], item["pad"]) for item in assignments}) == len(assignments), f"{target}: duplicate stock pad")
        for item in assignments:
            require(0 <= item["pad"] < 16, f"{target}: invalid stock pad")
            require(Path(item["file"]).name == item["file"], f"{target}: non-flat stock filename")
            require(manifest_path.with_name(item["file"]).is_file(), f"{target}: missing stock WAV {item['file']}")

        report["targets"][target] = {
            "swiftFiles": len(staged_sources),
            "resourceFiles": len(staged_resources),
            "resourceBytes": sum(path.stat().st_size for path in staged_resources.values()),
            "stockAssignments": len(assignments),
            "stockKits": len({item["kitID"] for item in assignments}),
        }

    with (BUILD / "App-Info.plist").open("rb") as handle:
        app_info = plistlib.load(handle)
    with (BUILD / "AU-Info.plist").open("rb") as handle:
        plugin_info = plistlib.load(handle)
    with (PACKAGE / "Info.plist").open("rb") as handle:
        shared_info = plistlib.load(handle)
    require(all(app_info.get(key) == value for key, value in shared_info.items()), "App metadata differs from shared Info.plist")
    require(app_info["UISupportedInterfaceOrientations"] == [
        "UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"
    ], "Phone orientations changed")
    require(set(app_info["UISupportedInterfaceOrientations~ipad"]) == {
        "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"
    }, "iPad orientations changed")
    require(app_info["UIBackgroundModes"] == ["audio"], "Background audio metadata missing")
    require(app_info["UIFileSharingEnabled"] and app_info["LSSupportsOpeningDocumentsInPlace"], "Files metadata missing")
    require(app_info["UILaunchScreen"] == {}, "Launch-screen metadata invalid")
    for info in (app_info, plugin_info):
        require(info["CFBundleIdentifier"] == "$(PRODUCT_BUNDLE_IDENTIFIER)", "Bundle ID is not driven by target identity")
        require(info["CFBundleVersion"] == "$(CURRENT_PROJECT_VERSION)", "Build is not driven by common build setting")
        require(info["CFBundleShortVersionString"] == "$(MARKETING_VERSION)", "Version is not driven by common build setting")

    component = plugin_info["NSExtension"]["NSExtensionAttributes"]["AudioComponents"][0]
    require((component["type"], component["manufacturer"], component["subtype"]) == ("aumu", "Tdgr", "brbs"), "AUv3 component identity changed")
    config = (ROOT / "xcode" / "project.yml").read_text()
    require(len(re.findall(r'TARGETED_DEVICE_FAMILY:\s*"1,2"', config)) == 3, "Native target device families must be universal")
    require("PRODUCT_BUNDLE_IDENTIFIER: com.tabdanger.BreakBoss\n" in config, "App target identity changed")
    require("PRODUCT_BUNDLE_IDENTIFIER: com.tabdanger.BreakBoss.AUv3\n" in config, "AUv3 target identity changed")
    report["deviceFamilies"] = [1, 2]
    report["appOrientations"] = app_info["UISupportedInterfaceOrientations"]
    report["ipadOrientations"] = app_info["UISupportedInterfaceOrientations~ipad"]
    report["audioComponentVersion"] = component["version"]
    destination = ROOT / "Build_Notes" / "UNIVERSAL_RELEASE_STAGING.json"
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
