# Loop reference review

The public shared conversation was recovered through its public JSON endpoint:
https://chatgpt.com/backend-api/share/6ac9ce25-f908-83e8-a0e5-1b25a1438a25

It contains the requested Drum Loop Mode behavior, kit genres and compatibility
requirements. Searches for study/YouTube references did not find specific song or
loop links in that shared conversation. A reference in another conversation is
not silently treated as available. The current producer/artist list informed the
20 linked research references in PATTERN_RESEARCH.md.

## Uploaded 90 BPM rolls actually measured

All ten supplied roll WAVs were decoded and measured before stock preparation.
The saved analysis includes source hashes, spectral/envelope measures, active
endpoints and detected rises in 10 ms RMS cells. These are waveform observations,
not listening approval or an exact note-by-note transcription.

- EBK Roll 2.0 has repeated rises spaced about 55–60 ms in its active section.
  At 90 BPM this is approximately eight 96-PPQ ticks, consistent with a short
  32nd-triplet roll. Its 95% energy point is about 632 ms.
- EBK Roll 5.0 has repeated rises spaced about 80–90 ms, approximately twelve
  ticks at 90 BPM, consistent with straight 32nd-note motion. Despite a 2.667 s
  container, its active endpoint is about 1.40 s; file duration is not phrase
  duration.
- EBK Roll 4.0 mixes shorter and longer detected rise intervals rather than one
  uniform subdivision. Tradeoff has irregular rises with larger gaps. The
  generator therefore uses short changing subdivisions and rests.
- Some files yield no separate strong rises at the chosen threshold. This does
  not prove they have no hits; it limits the detector. No exact grid is guessed.

The generated trap roll helper uses bounded tempo-relative events with 6/8/12/16
96-PPQ tick subdivisions, velocity ramps and phrase-end limits. The source audio
phrases are not placed on normal hats at their fixed 90 BPM. This keeps rolls in
sync when the user changes tempo, without live time stretching or extra render
CPU. Original phrases and their variations remain generated material.

See UPLOADED_ROLL_MEASUREMENTS.json and audio-analysis/texture/inventory.json for
saved numerical evidence. Further song/tutorial study is documented separately;
YouTube playback was unavailable, while readable transcripts/articles were used.
