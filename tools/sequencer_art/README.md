# Sequencer art (Oct 16)
Tyrone's approved DRUM SEQUENCER picture (mock.png, 1536x1024) is the plate of the sequencer screen,
like the faceplates. `plate_base.png` is the picture with the live areas cleared (tool labels, transport
icons, chip texts, the rack, the grid, the left panel); the first clearing pass was done by hand in this
session, so plate_base.png is the source from here on.

`build_controls.py` cuts every button, chip and switch out of the picture as its own sprite
(`SeqBtn*`, `SeqChip*`, `SeqArrow*`, `SeqDrumTrack`, `SeqSwitchBox`) with rounded transparent corners,
paints those spots out of the plate (brushed metal filled row by row so the grain carries on) and writes
`SeqPlate`. The sprites are real controls in `SeqControls.swift` (SeqButton / SeqChip / SeqGlyph, pressed
look from SeqPress): they go in while pressed and light up when on. Earlier sprites: `SeqCell` (one step
button), `SeqRow` (a rack row with the name blanked), `SeqKnob`, the left panel's section headers
(printed chevrons removed; the live chevron shows what's open) and the GENERATE box.
The rectangles the controls sit on are in `SequencerView.A` (picture pixels).

    python3 tools/sequencer_art/build_controls.py BreakBoss.swiftpm

Oct 17: `build_bays.py` paints the flat grey slabs under the SOUNDS / GENERATE panel and the
channel rack (and the smear left where the Drum Track button was painted out) as brushed metal.
The SOUNDS / GENERATE headers are no longer sprites: they're `PlatinumPlate` (SwiftUI, the slider
knob's metal) and slide over their wells. Order: build_controls.py, build_bays.py, build_finishes.py.

    python3 tools/sequencer_art/build_bays.py BreakBoss.swiftpm
    python3 tools/sequencer_art/build_finishes.py BreakBoss.swiftpm
