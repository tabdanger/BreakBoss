# BreakBoss

A drum machine for iPad, as an app and as an AUv3 instrument for Logic Pro, GarageBand,
Cubasis, AUM and other hosts. Every factory sound is synthesized by the app itself, so none of
it comes from anyone else's sample library.

## Folders

| Folder | What's in it |
|---|---|
| `BreakBoss.swiftpm` | The app. It opens in Swift Playgrounds on iPad, and it's the only copy of the code. |
| `AUv3` | The plug-in wrapper (audio unit and its window). GitHub builds it. Swift Playgrounds can't. |
| `xcode` | Builds the Xcode project (app + plug-in) on GitHub's Macs from `BreakBoss.swiftpm`. |
| `.github/workflows` | `build.yml` builds and self-tests every change. `upload.yml` signs and sends a build to TestFlight. |

## The faceplate

The three faceplates (Modern, Vintage, Texture) are the design. Pressing a mode button swaps
the whole plate and the sound.

- **Modern**: clean, hard-hitting and forward.
- **Vintage**: the same knobs with drive and boost added (tape saturation, low-end bump, rolled-off top).
- **Texture**: the same knobs with a downsampled, unstable sound, a tempo-synced delay and a gated reverb.

Bottom row: BOOST, PUNCH (transients), ANALOG EQ, GRIT, SHINE, TIGHTEN (shorter tails), NOISE.
Top panel: PITCH (±12 semitones), TUNE (±100 cents), BOUNCE (swing and loose feel), VELOCITY
(how much hit strength matters), FILTER (low-pass), CLIP DRIVE, OUTPUT and the CLIPPER (-0.3 dB ceiling).

- **ONE-SHOT**: the 12 pads play drums. Hold a pad to open its editor (your sample, level, pan, tune, decay, reverse).
- **LOOP**: the 12 pads play grooves generated from the kit's style. A new pick starts on the next bar, and tapping the same pad again stops at the end of the bar. Hold a pad for the step editor or to load a MIDI file.
- **Dice**: in LOOP, new grooves. In ONE-SHOT, new variations of the kit's sounds.
- **KITS**: 10 factory kits, plus your own saved kits.
  - Drum Mastery and Modern Trap: trap
  - West Bounce: modern West Coast, Mustard / Ty style
  - Bay Slap: Bay Area, Mozzy style
  - West 90s: G-funk
  - Neo Soul
  - Gospel Chops
  - Funk Break, Loose Break and Heavy Break: live breaks
- **PRESETS / Save**: factory presets, or save the whole faceplate.
- **BPM**: drag on the display. **TEMPO SYNC** uses the DAW's or MIDI clock's tempo. **FOLLOW DAW** starts and stops with the DAW, on its bar lines.
- **Export (arrow)**: MIDI, the stereo mix and one stem per drum. Drag them into a DAW or share them.
- **Menu (≡)**: put your samples on any of the 12 pads, save kits, see the MIDI map and a quick guide.

Your samples, kits, presets and exports are in Files › On My iPad › BreakBoss.

## MIDI

| Notes | Plays |
|---|---|
| C1–B1 (36–47) | Pads 1–12 (or loops 1–12 in LOOP mode) |
| C2–C5 (48–84) | The 808, chromatically. C3 (60) is the kit's tuning. |

## Building on GitHub

Secrets (Settings › Secrets and variables › Actions) are the same four as MS26:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.

1. Every push to `main` runs **Build BreakBoss**, which compiles the app and the plug-in. Then it runs the self-test on an iPad simulator and draws all three faceplates to the `ci-screenshots` branch.
2. The first time: run **Upload BreakBoss to App Store Connect** in **sign** mode. That registers `com.tabdanger.breakboss` and `com.tabdanger.breakboss.AUv3`. Then create the app in App Store Connect with that bundle ID.
3. After that, run it in **upload** mode for each TestFlight build.
