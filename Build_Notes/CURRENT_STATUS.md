# BreakBoss 0.3.2 · preset, Vintage and MIDI update

The preceding universal release 0.3.1 (build 8) passed 22,072 in-app checks on both iPhone and iPad and is VALID / IN_BETA_TESTING in the existing TestFlight app. Run: https://github.com/tabdanger/BreakBoss/actions/runs/38177989008

This revision adds:

- 61 distinct authored factory presets: 20 Modern, 21 Vintage, 20 Texture. Each restores its matching kit, active mode, FX, clipper and all 16 pad control snapshots.
- Kit-only changes preserve global FX and per-pad tune/decay/filter/level/pan controls while replacing raw sample identities. Factory presets fully restore settings even when their kit is already selected.
- Per-pad low-pass filters have coefficients prepared outside rendering and bypass when open. Older states default to open filters. INIT resets processing while retaining loaded sample files.
- Six leading Vintage kits cover Boom Bap, 70s Soul, Vintage R&B, dusty soul and break grooves. Eighteen offline kick/snare/rim source refinements use fuller body hits and actual rim-role source samples from the uploaded pack.
- 544 stock pad assignments, 34 kits, 318 processed WAVs from 42 retained uploaded hits. All bass assets/calibrations remain unchanged. Microphone-recorded acoustic drums, real ride/crash cymbals and recorded live breaks are not established by these source files.
- MIDI notes 36–51 map sequentially to all 16 pads/loops; 85–88 remain legacy pad aliases. Chromatic bass uses 52–84, with root 60. One-Shot note-offs preserve the full strike; Loop notes gate rhythms. MIDI bass export is bounded to its non-overlapping range.
- Phone knob cap overlays use the matching clean photographic tablet caps, retaining the original artwork bytes and live pointers.

Local grammar, actual stock PCM/hashes/fades, universal metadata and identical app/AUv3 staging pass. Maximum decoded stock kit estimate is 1.831 MiB; calibrated bass-root error is at most 0.5518 cents. Fifteen mocked release-helper checks pass. All three Apple builds passed, and both iPhone and iPad passed 23,903 in-app checks with six valid faceplate renders each. The 128-frame, MIDI, preset and per-pad filter regressions passed; these local figures do not measure whole-app CPU or certify physical-device click-free audio at 128 frames.

The four supplied KXVI tutorial videos have verified titles, but playback/transcripts and exact demonstrated drum grids are inaccessible. Tutorial-specific loop transcription remains pending user-provided transcripts and/or readable piano-roll/BPM evidence. No existing pattern is represented as a transcription of an inaccessible video. See TUTORIAL_STUDY_2026-10-12.md.

## Completed TestFlight release

BreakBoss 0.3.2 (build 13) was cloud-signed and uploaded with no altool errors. Apple marked build 13 VALID at 18:45:50 UTC and IN_BETA_TESTING at 18:46:11 UTC on 12 October 2026. The existing internal tester group receives the update. App ID 6821062027, com.tabdanger.BreakBoss and com.tabdanger.BreakBoss.AUv3 are preserved.

Release commit: f868b6881df7f7df814049363d9762920276f701.
Successful verify/upload: https://github.com/tabdanger/BreakBoss/actions/runs/38289954939

iPhone: 23,903 checks in 4.1 s. iPad: 23,903 checks in 5.5 s. The shipped-bank decoding phase passed 1,820 checks per device. Factory presets/kit independence passed 1,658 checks; host MIDI/automation passed 20; One-Shot MIDI and pad filters passed 89; 128-frame/voice-stealing checks passed 12.

Actual simulator screenshots and Modern/Vintage/Texture phone renders were inspected. Phone caps have single live pointer markings with the prior rectangular seams removed; iPad retains its approved layout. Physical-device touch, hardware MIDI/DAW integration and route-specific 128-frame CPU/click behavior remain device checks.

The source package retains base bundleVersion 9; the existing upload pipeline selected native build 13 monotonically from App Store Connect. The app-only archive has Package.swift at the ZIP root.
