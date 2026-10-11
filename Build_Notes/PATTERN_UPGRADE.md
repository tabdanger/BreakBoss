# BreakBoss pattern upgrade

The factory library now has 34 kits and 16 generated loop slots per kit. Existing kit IDs,
pad roles, MIDI mappings, saved edits and the original faceplate remain compatible. Two
additional kits provide explicit Lo-fi and Amapiano coverage. Lo-fi uses the existing
Neo Soul root, D1 / 36.71 Hz; Amapiano uses the Modern Trap root, E1 / 41.20 Hz.

## Phrase structure

Main A is a two-bar call and response. Main B develops a four-bar phrase. Main C is an
eight-bar busier phrase with a final turnaround. Main D is a four-bar restrained phrase.
The half-time variation stretches Main D into eight bars; Alternate supplies another
eight-bar phrase. Intro, Breakdown, Tops, Percussion and Shakers use four-bar material.
Main A's No 808 and Kick + 808 variations retain its two-bar length. Dedicated fills and
the two-bar Roll Up remain available. Existing edited/imported loops are not regenerated.

Longer patterns keep a recognizable two-bar motif, add percussion answers and a bass
pitch response at phrase ends, alter emphasis, and leave a gap in the timekeeping lane
at the midpoint of an eight-bar phrase. Busy phrases add a final fill. Pattern generation
is deterministic for a seed; DICE changes the seed instead of generating during playback.

## Genre differences

| Family | Implemented musical behavior |
| --- | --- |
| Atlanta trap | Beat-3 backbeat, sixteenth hats, sparse syncopated kick/808 motifs, recurring percussion answers and short hat ornaments. |
| Memphis trap | Beat-3 backbeat, eighth hats, tighter gated bass, recurring dry tonal percussion and occasional triplet/32nd ornaments. |
| Toronto / trap soul | Fewer kicks, quieter hats with deliberate rests, subdued backbeat layers and sparse percussion; the bass does not retrigger on every kick. Trap Soul uses rim/snap as the primary backbeat. |
| Boom bap | Strong 2-and-4 snare, repeating syncopated kick motif, independent hat swing, low snare ghosts and restrained bass anchors. |
| Lo-fi | Reduced boom-bap pocket, softer eighth hats with delayed offbeats, bounded late kick/snare lanes and lower bass density. |
| Neo soul | Existing mixed-timing pocket retained: late kicks, early snare/rim lane, quintuplet/septuplet-inspired hat spacing and low ghosts. The same small timing relationships recur with the motif. |
| Contemporary R&B | Rim/snap and soft clap on 2 and 4, simple hats, short bass gates and an extra understated snare layer in the answering bar. |
| 80s pop | Regular drum-machine backbeat, straight eighth hats, repeating kick/percussion motif, tambourine accents and short bass pulses. |
| 90s pop | Strong 2-and-4 backbeat, shuffled sixteenth hats, syncopated kick/percussion and short bass notes. |
| Amapiano | 112 BPM starting tempo, soft quarter-note kick pulse, alternating shaker accents, conga replies and short pitched bass call/response. The 808-derived prepared voice is log-drum-inspired; no authentic log-drum recording is claimed. |
| Experimental / world | Existing complementary percussion and cross-rhythms gain four-/eight-bar answers, midpoint rests and phrase-end variation. |
| West Coast, breaks and gospel | Existing genre-specific backbeats, swing, ghost notes and linear fills are retained and developed into longer phrases. |

These are original generated patterns informed by production technique. They are not
transcriptions or replicas of individual records, and producer/artist names are not used
to promise an exact signature. The accompanying research document records the sources
and distinguishes articles/transcripts read from videos that could only be located.

Useful technique references include [Neo Soul Drums](https://www.ujam.com/tutorials/how-to-make-neo-soul-drums/),
[90s Boom Bap](https://www.attackmagazine.com/technique/beat-dissected/90s-boom-bap-hip-hop/),
[Drunk Drummer Grooves](https://www.attackmagazine.com/technique/beat-dissected/drunk-drummer-style-grooves/),
and [Kooldrink's Amapiano guide](https://splice.com/blog/what-is-amapiano-music/).
Producer interviews and readable breakdown transcripts informed recurring percussion,
hat character, vocal space and second-half growth; exact event positions remain our design.

## CPU and continuity limits

All pattern generation, motif development, sorting, human timing and event budgeting run
before the engine receives a read-only PatternSet. No new synthesis, time stretching,
pattern generation, sorting or array allocation is introduced into the audio callback.
Hat rolls are events derived from the current tempo; the supplied fixed-90-BPM hat-roll
recordings are not substituted for regular hat hits.

Generated material is bounded to 64 events per bar and 512 per phrase, with valid sorted
ticks, deduplicated pad/tick pairs, finite velocities and pitches, and bass gates within
the loop. Ordinary bass notes stop before the next attack. A short intentional overlap
is allowed for a flagged slide only when the preceding note can support it. An open hat
and closed hat do not share an identical event tick. Roll helpers stop at phrase boundaries.
These bounds apply to generated loops; saved user MIDI and edits keep their original data.

The low-buffer target still requires measurement on the intended iPad. At 128 frames and
48 kHz each block has approximately 2.67 ms. No guarantee of click-free hardware operation
is made without that device run. Current Linux validation can inspect Swift grammar and
resource contracts; it cannot type-check or build Apple frameworks. The in-app groove
checks exercise deterministic phrases, bounds, genre backbeats and note lengths when
run in Swift Playgrounds or an Apple build.
