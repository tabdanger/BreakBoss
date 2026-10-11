# BreakBoss 0.3.1

Universal iPhone/iPad drum machine and AUv3 instrument. Both use the same sound engine, stock kits, genre patterns, MIDI mapping, presets and exports. iPhone uses the supplied portrait faceplates; iPad retains its original artwork.

All 544 factory pad slots across 34 kits use processed audio from the uploaded Multiverse folders. The bank contains 308 WAVs derived from 42 selected hits; exact processing and hashes are in `Build_Notes/STOCK_SAMPLE_PROVENANCE.json`. Imported audio takes priority. Genre patterns cover Atlanta/Memphis/Toronto Trap, Neo Soul, Boom Bap, Lo-fi, R&B, 80s/90s Pop, Amapiano and experimental/world percussion.

The faceplate shows 12 pads. MENU opens the full 16-pad performance grid and all editors. MIDI notes 36–47 trigger pads 1–12, 85–88 trigger pads 13–16, 48–84 play chromatic bass, and 60 is the kit root.

## Source and builds

- `BreakBoss.swiftpm`: shared app source and complete stock resources; opens in Swift Playgrounds on iPad.
- `AUv3`: existing host adapter and UI wrapper.
- `xcode`: stages the shared source/resources and generates the app plus embedded extension.
- `.github/workflows`: Apple SDK build/self-tests on iPhone and iPad simulators; existing signing and TestFlight upload workflow.
- `Build_Notes`: research, provenance, validation boundaries and release/device checklists.

The existing identities remain `com.tabdanger.BreakBoss` and `com.tabdanger.BreakBoss.AUv3`. GitHub's macOS runner uses the existing repository signing secrets. Upload automatically chooses a build number above existing App Store Connect builds. Native targets support iPhone and iPad from iOS 16.

## Open the download

The corrected app-only `BreakBoss-v0.3.1.swiftpm.zip` puts `Package.swift` directly at the archive root. Unzip in Files and open the resulting `BreakBoss-v0.3.1.swiftpm` in Playgrounds. The old multi-folder archive has an inner `BreakBoss.swiftpm` app; its outer folder is not a Playgrounds app.

The audio session requests 48 kHz/128 frames. Preallocated voices and fades, indexed scheduling, off-callback sample loading and nonblocking host parameter exchange reduce callback work. Simulator tests do not establish physical-device CPU usage or guarantee click-free playback on every audio route; use the included device checklist at the actual buffer size.
