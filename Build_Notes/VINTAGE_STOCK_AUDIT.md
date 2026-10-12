# Vintage stock audit

Audit date: 12 October 2026. This records the installed stock bank before the new mode and preset requirements are implemented. The audit does not alter samples or application code.

## Result

The existing Vintage processing already provides a useful analog and vinyl treatment, and imported acoustic audio can play through every mode. The uploaded Multiverse material can support drum-machine and sampled-hit Vintage kits. It does **not establish that the factory sounds are recordings of acoustic drums or live drum breaks**. Neither a kit name such as LIVE SOUL nor an audio editor's “Recorded in Edison” comment establishes that provenance.

There are currently 34 kits, 544 pad assignments, and 308 unique prepared WAV files. All use 42 source WAV files from the user's uploaded folder archives. All 42 local selected source files matched their recorded SHA-256 hashes during this audit. The complete original uploaded ZIPs are absent from the present attachment directory; this audit therefore covers the retained selections and provenance, not every unselected file in the original archives.

## Implemented offline refinement

After the initial audit, the kick, snare, and rim assignments in `boom-bap`, `live-soul`, `vintage-rnb`, `dirty-soul`, `funk-break`, and `loose-break` were refined using only retained uploaded hits. Every refined kick uses Spheres. The main snares now use Agency for live-soul/Vintage R&B/loose-break, and Gravity for Boom Bap/dirty-soul/funk-break. Their rim pads use Rim Flights instead of relabeled snaps. Subtle kit-specific tuning, low-pass filtering, decay, and mild drive are baked offline; the existing Vintage bus supplies further analog treatment at playback.

The refinement changed exactly **18 assignments**, generated 18 WAVs, and removed eight previous WAVs that no assignment still referenced. The resulting bank contains **318 unique WAVs totaling 14,004,926 bytes**, with the original 34 kits and 544 assignments. Every other pad assignment and all 34 bass files/calibration records remain byte-identical. No additional processing runs in the audio callback.

PCM format, coverage, peak, nonzero level, onset/end fades, output hashes, protected resource hashes, and per-kit decoded memory checks passed. Maximum decoded stock audio per kit is 1.831 MiB. Prior bass FFT results were reused only after verifying unchanged bass bytes and root metadata; their maximum previously measured error remains 0.5518 cents. This memory measurement is not a device CPU or glitch-free playback claim.

Reproduction and verification use `tools/refine_vintage_stock.py`, with `tools/prepare_stock_samples.py`, numpy, ffmpeg, ffprobe, and the retained source directory. The utility validates the current full selections/manifest/provenance before staging replacements, deduplicates identical audio, and preserves a backup until publication succeeds. `--check` passed; a second application reported `UNCHANGED`. A deliberately inconsistent selection/provenance pair was rejected without altering any bank file. The selected material still has unverified acoustic origin; this refinement does not claim real cymbals or a recorded live break.

```sh
python3 tools/refine_vintage_stock.py stock-source-selection \
  --package BreakBoss.swiftpm \
  --selections Build_Notes/STOCK_SELECTIONS.json \
  --provenance Build_Notes/STOCK_SAMPLE_PROVENANCE.json
```

The source table below is retained as the **pre-refinement** audit record. The updated selection and provenance JSON files describe the current assignments exactly.

## Evidence and provenance

- `Resources/StockSamples/manifest.json` identifies every installed kit/pad assignment.
- `Build_Notes/STOCK_SAMPLE_PROVENANCE.json` records each source, processing parameters, original and output hashes, duration, channel count, and original sample rate.
- `Build_Notes/STOCK_SOURCE_FILES.json` maps the selected local paths to the uploaded archive and exact archive entry.
- `/workspace/stock-source-selection` retains the 42 selected source WAVs.
- The selected WAVs' RIFF INFO tags identify Edison or FL Studio 21. Several say “Recorded on [date] in Edison.” They do not identify microphones, acoustic instruments, a recording session, or a source performance. No claim about real acoustic recording is justified by those tags alone.

The current samples are derived from uploaded audio, not the old synthetic factory recipes. The preparation step resamples to 48 kHz PCM16, applies onset and end fades, and can tune, filter, shorten, saturate, and normalize a hit offline. These derivations have explicit provenance. Filtering or saturation cannot turn an electronic source into a verified acoustic recording.

## Current Vintage-style kit sources

Names below are shortened only for readability; the provenance JSON contains exact filenames and the `@prod.by.iiinfinite` attribution. This table describes current sample assignments, not an acoustic classification.

| Existing kit ID | Kick source | Snare source | Rim/snap source on pad 4 | Closed/open hat sources |
| --- | --- | --- | --- | --- |
| `boom-bap` | Kick Waves | Snare Lunar | Rim Flights | Hi Hat Tech / Open Hat Architecture |
| `funk-break` | Kick Waves | Snare Lunar | Rim Flights | Hi Hat Tech / Open Hat Architecture |
| `vintage-rnb` | Kick Waves | Snare Lunar | Snap Flights | Hi Hat Tech / Open Hat Architecture |
| `dirty-soul` | Kick Mechanics | Snare Gravity | Snap Elevate | Hi Hat Rocket / Open Hat Patterns |
| `live-soul` | Kick Spheres | Snare Cryo | Snap Galactic | Hi Hat Explorer / Open Hat Parallax |
| `neo-soul` | Kick Mechanics | Snare Gravity | Snap Elevate | Hi Hat Rocket / Open Hat Patterns |
| `loose-break` | Kick Astronomy | Snare Agency | Rim Laws | Hi Hat Control / Open Hat Heliosphere |
| `heavy-break` | Kick Mechanics | Snare Gravity | Rim Research | Hi Hat Rocket / Open Hat Patterns |
| `lo-fi` | Kick Spheres | Snare Cryo | Snap Galactic | Hi Hat Explorer / Open Hat Parallax |

Common limitations across these kits:

- The “AIR CYMBAL” assignment on pad 12 uses **Open Hat Heliosphere**, pitched down 1.5 semitones and faded with a short decay. It is not an independently sourced ride or crash recording. Its label does not prove a real cymbal.
- The “PALM TOM” assignment on pad 15 is **Tom 3**, pitched up 2.5 semitones, filtered, and shortened. It is not a verified conga/palm-drum recording.
- Pad 7 remains a processed 808 bass. Some soul kits still contain snaps, a clap, and a laser effect. These need not be removed from a hybrid kit, but they should not be represented as an entirely acoustic drum set.
- The “break” grooves are internally programmed arrangements of one-shot samples, not chops from a documented live drummer recording.
- The current browser groups kits as core, world/textures, and legacy. It does not yet designate six primary Vintage factory kits.

## Best available tone candidates

The following measurements are objective comparisons of the retained sources, decoded to 48 kHz with the existing sample-preparation decoder. Centroids use a Hann-windowed full-hit power spectrum. They support tone selection, **not** an acoustic-versus-synthetic diagnosis. These candidates have not been auditioned in this text-only audit.

| Role | Candidate | Relevant measurement | Suggested use |
| --- | --- | --- | --- |
| Kick | Kick Spheres | 238 ms; 6.2% spectral energy above 200 Hz | First candidate for a broader attack and drum-body impression; most of the other selected kicks put over 99% of spectral energy below 200 Hz. |
| Snare | Snare Agency | 167 ms; power centroid 2352 Hz | Fuller and longer candidate for 70s soul and restrained R&B; use velocity ghost notes rather than making every strike full level. |
| Snare | Snare Gravity | 110 ms; centroid 2779 Hz | Second body-focused candidate for Boom Bap and dirtier soul. |
| Snare | Snare Lunar | 95 ms; centroid 3812 Hz | Brighter backbeat alternative already used by Boom Bap. |
| Rim | Rim Flights | 88 ms; centroid 1306 Hz | Lower, woodier spectral balance candidate; use actual Rim source on rim-designated pads instead of relabeled snaps. |
| Closed hat | Hi Hat Explorer / Tech | 37 / 30 ms; centroids 7295 / 7373 Hz | Less bright alternatives to Control's 12213 Hz centroid. These are already very short hits, so avoid claiming a sustained live hi-hat performance. |
| Open hat | Open Hat Heliosphere | 479 ms; centroid 7664 Hz | Longest and lowest-centroid selected open hat. Keep its source identity clear if repurposed as an auxiliary metal hit. |
| Tom | Tom 1 | 846 ms; centroid 723 Hz; 17.5% energy above 200 Hz | Better candidate for a resonant fill than treating the near-pure low tone of Tom 3 as a natural hand drum. |
| Percussion | Shaker 1, Tamb 1, Triangle 3 | Retained source identities and processing are documented | Useful organic-role percussion, but recording origin remains unverified. Tamb 1 currently starts at 190 ms to isolate its selected hit. |

Snare Cryo is 65 ms with a 6402 Hz centroid; it is a more plausible candidate for a short bright accent than for the main body of a live-soul snare. All retained kick sources are dual-mono and strongly concentrated below 200 Hz. The available measurements and metadata cannot certify any of them as a microphone recording of a kick drum.

## Implementation recommendations within the existing pack

1. Give Vintage a primary six-kit section spanning Boom Bap, 70s Soul, Vintage R&B, dusty/lo-fi soul, funk breaks, and live-feel breaks. Stable existing kit IDs can be retained for session compatibility. “Live-feel” describes timing and dynamics without inventing a recording provenance.
2. Keep kits accessible from every mode. A kit's primary mode is a browser/category preference, not a ban on processing its samples through Modern or Texture.
3. Make the Vintage rim pads use the retained Rim sources, and favor Agency/Gravity snare and Spheres kick candidates where a rounder source tone is needed. Keep hybrid 808/clap/FX choices explicit. These are possible remaps, not changes made by this audit.
4. Use programmed ghost snares, differentiated hi-hat velocities, sparse syncopated kicks, fills, and small deterministic timing deviations to produce a live-feel groove. This costs less CPU than a runtime acoustic-modeling layer and does not require claiming a sampled live performance.
5. Preserve source and output hashes for any new derivations. Prefer light offline source shaping plus the existing Vintage bus chain, keeping kit selection separate from the preset's FX choices.
6. To state that a factory kit includes **real acoustic drums, real ride/crash cymbals, or recorded live breaks**, obtain source material with that established origin. An uploaded pack's marketing name, a source filename, an Edison timestamp, and spectral shape are not sufficient evidence. Do not silently fill that gap with synthetic generators or downloaded third-party samples.

## Existing signal path and cross-mode import behavior

`ModeProcessor.swift` applies an 80 Hz boost shelf, a fixed 95 Hz / +2.5 dB head bump, additional Vintage gain, biased tape-style saturation through a preallocated 2× oversampler, and a 12.5 kHz low-pass filter. The Analog EQ, Punch, Shine, and master processing remain controllable. Noise adds low-passed hiss and sparse crackle, gated by the drum envelope so silence remains silent. This is a practical analog/vinyl-inspired path; it is not evidence that the input is acoustic.

Wow/flutter, downsampling, ping-pong delay, and gated reverb are currently Texture processing. Vintage does not run these time-based effects. Document the actual chain rather than promising effects that Vintage does not apply.

`MenuView.swift` exposes file import and file-URL drag/drop for each pad. `KnockController.importSample` copies and decodes the sample off the main thread, assigns it to the pad, and republishes the kit without testing the selected mode. `selectMode` changes the processing parameter without reloading samples. The imported acoustic-WAV behavior requested by the user is therefore already structurally supported for Modern, Vintage, and Texture.

`selectKit` currently retains global mode and FX parameter values but resets all per-pad settings and edited loops. If “keep current knob settings” includes the pad editor's tuning/decay/filter settings, that behavior needs an explicit preservation policy in the kit/preset implementation.
