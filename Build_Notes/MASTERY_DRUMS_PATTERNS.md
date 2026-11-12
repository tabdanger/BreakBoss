# BK Editions Vol 5-8: patterns from the mastery drums folder (for DAW Breaker too)

Tyrone, 2026-11-12: "EVERY loop/drum fill in the icloud folder ... should be studied and turned into a pattern on the
sequencer", "ALSO STUDY THE MIDI", and "push patterns and kits to Dawbreaker". This note is what DAW Breaker needs to
carry the same patterns. Sound organization rules stay as in `Build_Notes/SOUND_ORGANIZATION.md`.

## Update, later on 2026-11-12: the old trap styles are gone
Tyrone: "remove all the old Trap patterns, they suck, use what we just created" / "no remove them completely" (all 4
Trap folders). **Trap, Alt Trap, Dark Trap and ATL Trap (200 presets) are deleted from the bank. BK Editions Vol 5 Trap
is the trap bank now.** DAW Breaker should delete those four styles too.
- PatternBank.json now holds 2063 presets. Each one carries `"number"`, its AUv3 factory preset number from before the
  removal, so no other preset's number moved (the removed numbers are simply missing).
- `"retired"` lists the 200 removed presets: `number`, `name` and `replacement` (the Vol 5 Trap preset nearest its
  tempo). A saved song that used one still opens with its own notes, since the song stores the notes. Its dice roll from
  Vol 5 Trap, and a host that recalls the old factory number gets the replacement.
- Trapsoul, Phonk, Memphis, Drill, UK Drill, NY Drill and Detroit 2026 stay.

## What was added
459 presets in four new PATTERNS styles, appended after every older preset (AUv3 numbers 1804-2262), so no older
factory preset number moves:

| Style | Presets | Shown in |
|---|---|---|
| BK Editions Vol 5 Trap | 134 | Modern, Platinum, Texture |
| BK Editions Vol 6 RnB | 89 | Modern, Platinum, Texture |
| BK Editions Vol 7 Experimental | 93 | Modern, Platinum, Texture |
| BK Editions Vol 8 Vintage | 143 | Vintage, Texture (live breaks, boom bap loops, acoustic fills) |

Per suite the order is: drum loops, live breaks, perc / hat / crash loops, fills, drum MIDI; each group by tempo.
Names are `BK V5 n BPM WHAT` (WHAT = HAT ROLLS, OPEN HATS, HALF TIME, BREAK, PERC LOOP, HAT LOOP, FILL, SNARE ROLL,
TOM FILL, HAT MIDI, SNARE MIDI, 808 MIDI, KICK SNARE MIDI...). No pack, producer or song name is shown.

No kits, sounds or audio were added: the loops, fills and MIDI are learn-only. The patterns play through any kit.

## How each file became a pattern (tools/learn_mastery.py, then tools/make_patterns.py)
- **Loop**: from its stems when it has them (each stem's hits on the 16ths, level, push/pull and swing); otherwise
  split from the full mix. 808 stems write the 808 lane with every note's pitch against C (all 808s are tuned to C).
  A tops loop with no kick plays its kick on its 808 notes, or takes the kick of the nearest-tempo loop.
- **Live break**: split from the full mix against the acoustic sounds too.
- **Perc / hat / crash loop**: its part over the rest of the same suite's loop nearest its tempo.
- **Drum MIDI** (kick, snare, hats, open hats, 808; one part per file): files with the same number and tempo are one
  preset. The part replaces the nearest loop's part bar by bar (a snare MIDI that is a roll in bar 8 keeps the
  groove's snare in bars 1-7).
- **Fill / snare roll**: 4 bars of the nearest loop, the fill at the end of bar 4 so it lands on the next downbeat.
- Lengths 1, 2, 4 or 8 bars. Over 180 BPM is written at half tempo.
- Not turned into patterns: 2 RnB loops in 3/4 time (they can't loop on 16-step bars), 1 fill that is noise only,
  3 vocal MIDI files. The folder's "International" suite had only its info file, no zip.

## For DAW Breaker
- The data: `BreakBoss.swiftpm/Resources/PatternBank.json` on BreakBoss main. Each preset has `style`, `name`, `bpm`,
  `swing`, `lanes` and optional `shift` / `swingLanes` (ticks at 96 per beat; swing 0-1).
- Lane keys and pads: k kick, s snare, c clap, r rim, h hat, o open hat, b 808, p1 perc 1, p2 perc 2, lt low tom,
  ht high tom, cr crash. Notes 36-47 as in BreaKing.
- Step codes (16 per bar): `.` rest, `X` 1.0, `x` 0.82, `o` 0.62, `g` 0.38, `r` two 32nds, `q` four 64ths,
  `t` a 16th triplet over this step and the next. 808 lane: `0-9 a b c` = 0-12 semitones up from C, `A-L` = 1-12 down,
  `-` holds the note.
- Keep Vol 8 Vintage-only, and append any new styles at the end so preset numbers never shift.
- Sound compression (Apple Lossless) is its own BreakBoss change; DAW Breaker should follow it once it lands on main.
