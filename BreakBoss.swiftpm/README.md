# BreakBoss 0.3.2 · Source build 9

TestFlight release: **0.3.2 (build 13)**, available to the existing internal testers. Both iPhone and iPad passed 23,903 automated checks. The upload pipeline sets the native build number above the source package’s base number.

Universal iPhone and iPad app for iOS 16 and later. The existing Xcode pipeline also builds its AUv3 extension.

## Open

The app-only download `BreakBoss-v0.3.2.swiftpm.zip` contains `Package.swift` directly at the ZIP root. Unzip it in Files, open the resulting `BreakBoss-v0.3.2.swiftpm` in Swift Playgrounds on iPad, and press Run. Keep your previous project as a backup. If opening the older archive, open its inner `BreakBoss.swiftpm` folder; its outer folder contains documentation and is not the app. Install the compiled universal app through the existing TestFlight app on iPhone or iPad.

## Play

- iPad keeps its three original faceplates. iPhone uses the three supplied portrait faceplates with four columns and three rows. Both have 12 visible pads and the same controls.
- MENU → Open 4 × 4 performance pads opens all 16 pads. Bottom-left is pad 1; top-right is pad 16.
- ONE-SHOT plays individual sounds. LOOP on this new surface plays while a pad is held. Holding for 0.9 seconds opens the editor and releases its loop.
- The original faceplate retains tap-to-latch loops, including next-bar changes. Tap the same faceplate pad again to stop at the next bar.
- MIDI LOOP mode is gated: hold a note to play, release to stop. Last-held note wins; releasing it returns to another still-held note. MIDI note-on velocity zero also releases.
- Use Program pattern to edit any of the 16 patterns, including in one-shot mode. Play / Stop pattern previews that sequence. Clear removes all events so you can program from scratch.
- Use STOP or MENU → All notes and loops off as a panic control.

## MIDI compatibility

| MIDI notes | Meaning |
| --- | --- |
| 36–51 | Pads / loops 1–16, sequentially |
| 85–88 | Legacy alternate notes for pads / loops 13–16 |
| 52–84 | Chromatic 808; note 60 is the kit's bass tuning |

Configure a MIDI pad controller to send 36–51. These are sequential pad assignments. Legacy pad notes 85–88 remain supported. Notes 48–51 now play pads 13–16; old bass MIDI in that range needs transposition or editing. MIDI bass export clamps to 52–84 to avoid overlapping those pads. One-Shot note length never truncates a strike; velocity and per-pad decay still shape it. MIDI clock controls tempo with TEMPO SYNC; FOLLOW DAW follows MIDI start/stop in the standalone app. Numbered notes are authoritative because octave naming differs between DAWs.

## Sounds and effects

KITS groups 34 kits by their primary Modern, Vintage or Texture home, covering Atlanta/Memphis/Toronto Trap, Neo Soul, Boom Bap, Lo-fi, R&B, 80s/90s Pop, Amapiano, and world/experimental percussion. All 544 factory pad slots use processed audio from the uploaded Multiverse folders. The bank uses 42 selected source hits with tuning, shorter envelopes, tone filtering, restrained saturation, and faded edges. Each 808 is calibrated to the kit's bass tuning. The Amapiano bass is a short, pitched sample derivative with a log-drum-like envelope. Palm percussion and air cymbals are sample derivatives; the bank does not claim acoustic instrument recordings or measured hardware emulations.

Vintage is the primary browser home for Boom Bap, 70s Soul, Vintage R&B, dusty soul and live-feel break patterns. Any kit or imported acoustic WAV can run through any mode. The uploaded bank does not establish microphone-recorded acoustic drums, recorded live breaks, or real ride/crash cymbals; those need suitable source recordings.

PRESETS contains 61 authored factory snapshots: 20 Modern, 21 Vintage and 20 Texture. Each loads a matching kit and restores mode, FX, clipper and all 16 pad tuning, decay, filter, level and pan controls. Choosing a kit alone keeps the current global and per-pad processing controls while replacing the raw sample identities. INIT resets processing and pad controls while retaining your loaded samples.

The uploaded samples identify @prod.by.iiinfinite. Source archive entries, original/processed hashes, and exact processing settings are recorded in `Build_Notes/STOCK_SAMPLE_PROVENANCE.json`. The synthesis engine remains available only as a recovery path for unavailable audio. Imported pad audio takes priority over the bundled bank.

The faceplate processing remains available. MENU → Engine controls exposes:

- Modern: Boost, Punch, Analog EQ, Tighten, Grit, Shine, Noise.
- Vintage: Drive, Swing, Velocity, Grit, Shine, Tighten, Noise.
- Texture: Resample, Instability, Delay, Gated Reverb, Drive, Shine, Noise.

Texture controls are separately adjustable and saved in presets. Zero disables each effect's contribution. Delay uses a tempo-synced dotted eighth-note. Tighten shortens drum tails; it is not a separate modeled hardware circuit. Velocity adjusts response to incoming/programmed dynamics; it does not independently create random velocities. Existing humanized grooves carry their own timing/velocity variation.

DICE makes new generated grooves in LOOP mode; explicit edited patterns remain protected. In ONE-SHOT mode it changes tuning, pan, and decay of bundled or imported samples without changing their audio files.

The generated loops use original genre rules: half-time Trap backbeats, controlled hat rolls, recurring percussion motifs, independent Neo Soul timing, Boom Bap swing, sparse R&B, straight/syncopated Pop, and Amapiano shaker/bass interplay. Longer main patterns develop across the phrase instead of repeating one bar. Research references and the prior loop study are included beside the project in `Build_Notes`.

## Import, save, and share

Drop audio onto any pad or use Import in MENU / the pad editor. Supported files depend on iOS decoding, with a 30-second sample length limit and a decoded-frame memory bound.

SAVE stores the complete preset locally. MENU → Save these pads as a kit saves the kit. Old 12-pad states expand to 16 while preserving their original settings and edited loops.

MENU → Share / import a complete preset makes a `.bbpack` file containing the current state, imported audio, and the bundled sounds used by the kit. Share/save it, then import it on another BreakBoss installation. Embedded sample data is limited to 64 MB; unsupported/corrupt audio is rejected. After import, use SAVE to give the preset a local name. Only share samples you have rights to redistribute.

## Export

EXPORT renders MIDI, a stereo mix, and individual used-pad WAV stems. Drag a rendered file to a compatible destination or use Share to save it to Files for DAW import. Direct cross-app drops depend on the receiving iPad app and still require device testing.

The mix and each stem are processed independently. Nonlinear saturation and clipping mean processed stems will not necessarily sum exactly to the processed mix. MIDI contains events and timing rather than audio effects. Exports are in Files → On My iPhone / On My iPad → BreakBoss → Exports.

## Build boundaries

The audio session requests 48 kHz and a 128-frame buffer. iPadOS and the connected audio route choose the actual settings. Stock decoding and processing stay outside the audio callback, and only the selected kit is loaded. Source checks and PCM validation do not establish device CPU use or click-free playback; test the included device checklist at the actual route and buffer size.

The app-only ZIP contains the standalone `.swiftpm` project. The development archive and connected GitHub repository include the existing `AUv3` extension and `xcode` generator. The native build embeds the extension; the Swift Playgrounds project alone does not. Both native targets preserve their existing App Store Connect identities.

See `Build_Notes` next to the project for the change log, build rules, validation results, and device checklist.
