#!/usr/bin/env python3
"""Writes the Info.plists and source copies for the Xcode build (app + AUv3 plug-in) from
BreakBoss.swiftpm, the only original (the same files Swift Playgrounds runs).

Run from the repository root on the build machine, then `xcodegen generate --spec xcode/project.yml`.
Prints the version and build numbers for xcodebuild.
"""
import json
import os
import plistlib
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACKAGE_DIR = os.path.join(ROOT, "BreakBoss.swiftpm")
PACKAGE = os.path.join(PACKAGE_DIR, "Package.swift")
EXTRA = os.path.join(PACKAGE_DIR, "Info.plist")
OUT = os.path.join(ROOT, "xcode", "build")

# Files only the standalone app uses (its entry point, audio / MIDI hardware, the self-test).
APP_ONLY = {"BreakBossApp.swift", "AppAudioHost.swift", "KnockSelfTest.swift"}


def package_value(name):
    text = open(PACKAGE).read()
    match = re.search(name + r':\s*"([^"]*)"', text)
    if not match:
        sys.exit(f"Package.swift has no {name}")
    return match.group(1)


def main():
    version = package_value("displayVersion")
    build = os.environ.get("BREAKBOSS_BUILD") or package_value("bundleVersion")
    os.makedirs(OUT, exist_ok=True)

    orientations = [
        "UIInterfaceOrientationLandscapeRight",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
    ]
    app = {
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "LSApplicationCategoryType": "public.app-category.music",
        "LSRequiresIPhoneOS": True,
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": True, "UISceneConfigurations": {}},
        "UIApplicationSupportsIndirectInputEvents": True,
        "UILaunchScreen": {"UILaunchScreen": {}},
        "UISupportedInterfaceOrientations~ipad": orientations,
    }
    with open(EXTRA, "rb") as handle:
        app.update(plistlib.load(handle))

    parts = [int(p) for p in (version.split(".") + ["0", "0"])[:3]]
    component_version = (parts[0] << 16) | (parts[1] << 8) | parts[2]
    plugin = {
        "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
        "CFBundleDisplayName": "BreakBoss",
        "CFBundleExecutable": "$(EXECUTABLE_NAME)",
        "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "$(PRODUCT_NAME)",
        "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
        "CFBundleShortVersionString": "$(MARKETING_VERSION)",
        "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
        "NSExtension": {
            "NSExtensionAttributes": {
                "AudioComponents": [{
                    "description": "BreakBoss drum machine",
                    "manufacturer": "Tdgr",
                    "name": "Tabdanger: BreakBoss",
                    "sandboxSafe": True,
                    "subtype": "brbs",
                    "tags": ["Drums", "Sampler"],
                    "type": "aumu",
                    "version": component_version,
                }],
            },
            "NSExtensionPointIdentifier": "com.apple.AudioUnit-UI",
            "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).BreakBossAUViewController",
        },
    }

    for target, skip in (("app", set()), ("plugin", APP_ONLY)):
        sources = os.path.join(OUT, target, "Sources")
        resources = os.path.join(OUT, target, "Resources")
        shutil.rmtree(sources, ignore_errors=True)
        shutil.rmtree(resources, ignore_errors=True)
        os.makedirs(sources)
        for name in sorted(os.listdir(PACKAGE_DIR)):
            if name.endswith(".swift") and name != "Package.swift" and name not in skip:
                shutil.copyfile(os.path.join(PACKAGE_DIR, name), os.path.join(sources, name))
        shutil.copytree(os.path.join(PACKAGE_DIR, "Resources"), resources)
        # Package.swift's `accentColor: .presetColor(.red)`, as Swift Playgrounds adds it.
        accent = os.path.join(resources, "Assets.xcassets", "__PresetAccentColor.colorset")
        os.makedirs(accent)
        with open(os.path.join(accent, "Contents.json"), "w") as handle:
            json.dump({
                "colors": [{"color": {"platform": "universal", "reference": "systemRedColor"}, "idiom": "universal"}],
                "info": {"author": "xcode", "version": 1},
            }, handle, indent=2)
        if target == "plugin":
            # The plug-in doesn't need the app icon.
            shutil.rmtree(os.path.join(resources, "Assets.xcassets", "AppIcon.appiconset"), ignore_errors=True)

    with open(os.path.join(OUT, "App-Info.plist"), "wb") as handle:
        plistlib.dump(app, handle)
    with open(os.path.join(OUT, "AU-Info.plist"), "wb") as handle:
        plistlib.dump(plugin, handle)
    print(f"MARKETING_VERSION={version}")
    print(f"CURRENT_PROJECT_VERSION={build}")
    print(f"AU_COMPONENT_VERSION={component_version}")


if __name__ == "__main__":
    main()
