# iPhone interaction and layout review

The iPhone uses the same `KnockController`, factory kits, sample library, 16-pad MIDI mapping, groove generator, pad settings, loop editing, importers, and exporters as iPad. This review changes secondary views only; supplied faceplate artwork and faceplate hit regions belong to the separate faceplate implementation.

## Changes

- The 16-pad performance view stacks its toolbars below 600 points of available width. In compact landscape height it places a scrolling control column beside the pad grid, so all actions remain reachable without placing the immediate pad gestures inside a ScrollView.
- The performance grid keeps four rows and four columns, the existing reversed row order, and the same `PadView` callbacks. Its minimum cell size is 44 × 44 points. Compact cells use a shorter MIDI label and a single-line sound title when less than 70 points tall.
- The loop editor scrolls vertically as a whole, while the step grid scrolls horizontally. Its heading and actions use `ViewThatFits` to wrap into vertical arrangements when their full intrinsic horizontal layout does not fit.
- Menu sample rows separate the sample description from the action row when the single-line layout does not fit. Play and restore have spoken accessibility labels and a minimum 44-point height.
- Sample/import/export instructions now refer to “Files › BreakBoss” on the current device instead of “On My iPad.” Persistence and portable-preset changes are comments only; there is no state-format migration.

## Reviewed containment

All secondary presentations use stack navigation, an inline title where applicable, and a Done button. Pad editor, menu, engine controls, export, and portable presets already use scrolling Forms. Export uses system `ShareLink`, including a Share / save everything action; portable presets provide their own Share / save action. Both audio and MIDI import use the same system file importer on either device.

For the performance grid, a 320-point portrait container has 288 points after padding: four 64.5-point cells plus three 10-point gaps exactly occupy the width. A 480 × 255-point compact-landscape container allocates 200 points to controls, 12 points between columns, and 32 points to outer padding; its 236 × 223-point grid contains 51.5 × 48.25-point cells. A 620 × 274-point compact-landscape container contains a 376 × 242-point grid with 86.5 × 53-point cells. These are source-level arithmetic checks of available geometry, not rendered simulator measurements.

The pad grid remains outside all scrolling regions. The existing zero-distance pad drag, long hold to edit, release-to-stop loop gate, drag/drop handling, generation of audio, and note mapping are unchanged.

## Verification and remaining device checks

The available Swift grammar parser checked all 25 Swift files with zero errors after these changes. No Apple SDK, SwiftUI type checker, iPhone simulator, or physical device is available in this workspace; grammar parsing does not establish a successful Apple build or rendered fit.

Before releasing the TestFlight build, check on a small iPhone and a large iPhone in portrait and landscape:

1. Open Menu → 4 × 4 performance pads. Confirm all 16 pads and both toolbars fit, and the landscape control column scrolls without triggering pad notes.
2. Exercise press/release on every pad, hold to open each editor, DICE, STOP, pattern selection, and the Play / Stop action. Confirm the lowest grid row remains visible above the home indicator.
3. Open a long or edited loop. Reach the last step horizontally, all 16 rows vertically, Import MIDI, Clear, and Back to generated. Confirm Done remains available.
4. In Menu, confirm a long sound name and an imported sound still leave Play, Edit, Import, and Restore reachable.
5. Import audio from local Files and iCloud Drive. Render MIDI/mix/stems, save with the share sheet, and import/share a portable preset. Reopen saved pad settings and patterns.
6. Repeat with larger text and after rotating an open editor. Check secondary navigation sheets on iPad as well.

Apple compilation, device interaction, and the physical 128-frame audio stress test are still separate release checks.
