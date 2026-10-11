# MS26 rules applied to BreakBoss

1. Lock approved design. Preserve supplied faceplate artwork, typography, spacing, control positions, and hardware character. Add requested capabilities in secondary views; make no unrelated redesigns.
2. Keep responsibilities separate. Audio/DSP, groove generation, controller state, MIDI, persistence, export, and UI remain separate modules. No duplicate competing implementations.
3. Make controls honest. A control must affect the named parameter; its display and stored value must agree. Distinguish synthesized genre kits from proprietary sample content and analog-inspired DSP from verified hardware modeling.
4. Protect compatibility. Preserve existing IDs, initial 12 pads, factory kit IDs, chromatic 808 MIDI notes, saved pad settings, and edited patterns. Append new parameter addresses and migrate arrays instead of clearing them.
5. Keep audio lightweight. Allocate buffers outside callbacks. Use nonblocking audio-side handoffs/snapshots. Keep file decoding, kit creation, saving, and export off the audio thread. Avoid unnecessary continuous effects work; preserve the idle-processing skip.
6. Verify and report limits. Inspect actual code, syntax-parse, type-check the portable engine, exercise DSP/MIDI/timing/state regression tests, benchmark without inventing iPad CPU numbers, compare resources, and validate the final ZIP. Explicitly distinguish Linux tests from Apple SDK builds, simulator checks, and physical iPad verification.

Scope-specific choices: the requested 16-pad grid is an additional performance view, preserving the original 12-pad faceplate; MS26 oscillator/patch-cable/sequencer requirements do not apply to this drum app.
