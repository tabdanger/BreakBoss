# BreakBoss 0.3.2

**TestFlight: 0.3.2 (build 13), VALID and IN_BETA_TESTING.** Both devices passed 23,903 checks. [Verified release](https://github.com/tabdanger/BreakBoss/actions/runs/38289954939).

Universal iPhone/iPad drum machine and AUv3 instrument. Both use the same sound engine, stock kits, genre patterns, MIDI mapping, presets and exports. iPhone uses the supplied portrait faceplates; iPad retains its original artwork.

The 577 stock sounds are sorted by category and named for how they sound ("KICK BOOM 07", "808 F1 LONG 02", "SHAKER 03"). They make 42 factory kits, an A and a B for each of 21 genres (the genres in the drum research plus Afrobeats, Amapiano, World Perc and FX Lab). Imported audio takes priority.

There are 170 factory presets (patterns), 10 each in 17 styles from the drum research: Neo Soul, Dilla Time, Boom Bap, 90s Rap, 70s Soul, 80s Breaks, Rock, Trap, Alt Trap, Drill, UK Drill, NY Drill, Detroit 2026, Bay Area 2026, RnB, 90s RnB and UK RnB. A preset loads a pattern only, so any pattern plays through any kit. Imported acoustic WAVs work through every mode.

There are 12 pads, the same ones on the faceplate and in MENU. MIDI notes 36–47 play pads 1–12 in order, and notes 48–84 play the 808 chromatically, with 60 as the kit root. One-Shot ignores note length; Loop rhythms follow held notes.

## Source and builds

- `BreakBoss.swiftpm`: shared app source and complete stock resources; opens in Swift Playgrounds on iPad.
- `AUv3`: existing host adapter and UI wrapper.
- `xcode`: stages the shared source/resources and generates the app plus embedded extension.
- `.github/workflows`: Apple SDK build/self-tests on iPhone and iPad simulators; existing signing and TestFlight upload workflow.
- `Build_Notes`: research, provenance, validation boundaries and release/device checklists.

The existing identities remain `com.tabdanger.BreakBoss` and `com.tabdanger.BreakBoss.AUv3`. GitHub's macOS runner uses the existing repository signing secrets. Upload automatically chooses a build number above existing App Store Connect builds. Native targets support iPhone and iPad from iOS 16.

## Open the download

The corrected app-only `BreakBoss-v0.3.2.swiftpm.zip` puts `Package.swift` directly at the archive root. Unzip in Files and open the resulting `BreakBoss-v0.3.2.swiftpm` in Playgrounds. The old multi-folder archive has an inner `BreakBoss.swiftpm` app; its outer folder is not a Playgrounds app.

The audio session requests 48 kHz/128 frames. Preallocated voices and fades, indexed scheduling, off-callback sample loading and nonblocking host parameter exchange reduce callback work. Simulator tests do not establish physical-device CPU usage or guarantee click-free playback on every audio route; use the included device checklist at the actual buffer size.
