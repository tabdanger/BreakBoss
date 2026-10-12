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

Local grammar, actual stock PCM/hashes/fades, universal metadata and identical app/AUv3 staging pass. Maximum decoded stock kit estimate is 1.831 MiB; calibrated bass-root error is at most 0.5518 cents. Fifteen mocked release-helper checks pass. Apple compilation and updated in-app runtime checks are pending for this revision; these local figures do not measure whole-app CPU or certify physical-device click-free audio at 128 frames.

The four supplied KXVI tutorial videos have verified titles, but playback/transcripts and exact demonstrated drum grids are inaccessible. Tutorial-specific loop transcription remains pending user-provided transcripts and/or readable piano-roll/BPM evidence. No existing pattern is represented as a transcription of an inaccessible video. See TUTORIAL_STUDY_2026-10-12.md.
