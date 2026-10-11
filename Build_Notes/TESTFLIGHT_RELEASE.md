# BreakBoss universal update

The iPhone and iPad versions share the same controller, sound engine, stock kits, patterns,
presets, MIDI mapping and exports. The phone uses the supplied portrait faceplates; iPad
keeps its existing faceplates. Both app and AUv3 targets support device families 1 and 2.
iPhone supports portrait and both landscape orientations; iPad also supports upside-down
portrait. Minimum deployment remains iOS 16.

## Existing release route

Continue using the existing [tabdanger/BreakBoss repository](https://github.com/tabdanger/BreakBoss)
and its **Upload BreakBoss to App Store Connect** GitHub Actions workflow. The repository
already built and uploaded a signed release in
[run 37960504835](https://github.com/tabdanger/BreakBoss/actions/runs/37960504835).
This update preserves that app and its AUv3 extension:

| Item | Preserved identity |
| --- | --- |
| Standalone app | `com.tabdanger.BreakBoss` |
| AUv3 extension | `com.tabdanger.BreakBoss.AUv3` |
| Audio component | `aumu` / `Tdgr` / `brbs` |
| Xcode scheme | `BreakBoss` |

`BreakBoss.swiftpm` is the original source used by Swift Playgrounds. `xcode/generate.py`
stages its current source and resources for the app and extension; `xcode/project.yml`
generates their existing Xcode project. Generated `xcode/build` contents and the generated
project are build outputs. They must not become independent, manually edited source copies.

The release uses display version **0.3.1**. The local Swift Playgrounds build is **4**;
the upload workflow must choose a new build number after consulting the existing App Store
Connect builds. That number is passed into the generated app and extension together.

## Build and upload

1. Commit the universal source, phone artwork, complete stock resources, AUv3 fixes and
   Xcode generation updates to the existing repository.
2. Verify **Build BreakBoss** passes its Apple SDK app/AUv3 compilation and simulator
   checks for that commit.
3. Run **Upload BreakBoss to App Store Connect** for the same commit with mode `upload`.
   Keep the existing repository secrets; the successful pipeline already knows the team,
   App Store Connect key and signing route. Do not place those values in source files.
4. Check the workflow's upload response and App Store Connect processing result. A
   completed archive or IPA alone does not establish TestFlight availability. The
   existing workflow assigns a processed build to internal testers; external testing
   uses its existing Beta App Review flow.

The macOS workflow selects Xcode 26, builds a device archive with the app and embedded AUv3,
signs both using their existing identities, validates the IPA and uploads it to the same
App Store Connect app. Its existing cleanup keeps the uploaded build's signing certificate
valid while Apple processes it.

## Resource and metadata checks

Both targets receive the stock manifest and all WAVs, the iPad/phone layout JSONs, the
compiled asset catalog and the privacy manifest. The extension excludes the standalone
entry point, hardware audio host and standalone self-test. It does not receive the app
icon. Source staging retains background audio, Files sharing and encryption metadata.
No microphone permission or new entitlement is introduced by this UI update.

Linux validation can check source staging, metadata, resource hashes and package integrity.
Apple SDK compilation, simulator rendering, signing, upload and TestFlight processing are
verified through the existing GitHub macOS release workflow. Physical device testing is
still required to assess audio playback at the requested 128-frame buffer.
