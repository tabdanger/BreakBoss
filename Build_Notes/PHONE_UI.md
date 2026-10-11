# Universal faceplate update

The iPhone and iPad presentations share `KnockController`, the audio engine, all 16 pad IDs, stock kits, generated loops, MIDI and exports, presets, pad editing, and the secondary 16-pad performance menu. Device selection follows `UIDevice.current.userInterfaceIdiom`; a narrow iPad Split View keeps the approved tablet artwork.

## Artwork and control placement

The user's three iPhone JPEGs are bundled unchanged as `PhonePlate_modern`, `PhonePlate_vintage`, and `PhonePlate_texture`. `Resources/PhoneKnockLayout.json` contains measurements in their native pixels (Modern/Texture 590 × 1280; Vintage 592 × 1280). Original iPad asset files and `Resources/KnockLayout.json` are unchanged.

The 12 visible phone pads are four columns and three rows. Top row: pad IDs 8–11; middle: 4–7; bottom: 0–3. This keeps pad 0 in the bottom-left corner and preserves all MIDI and preset identities. The original iPad remains six columns and two rows. Pads 12–15 remain available through MENU on both devices.

The phone photographs include pointer notches, a fixed BPM, fixed kit/preset names, and photographed indicator states. The phone presentation overlays live pointer graphics after masking each photographed notch with a clean neighboring sector from the same photographic knob cap. Live BPM and names cover their original photographed values. The scope, play/pause indicator, one-shot/loop lights, clipper, and sync indicators show controller state. The approved JPEGs are not regenerated or modified.

Portrait presentation fits the full phone plate proportionally within the system safe area. Landscape presentation scrolls the portrait instrument at a usable width, keeping all rows accessible without stretching. The phone safe area is supplied by the root content view. The tablet keeps its existing full-screen behavior. Knob drags, double-tap resets, pad taps, editor long presses, imports, kit and preset menus, exports, and save actions use the existing shared implementations.

## Validation performed

- Three phone layouts: all 32 control rectangles per layout lie inside the original artwork bounds.
- All 14 knob centers/radii per mode lie inside the plate.
- Each phone layout contains exactly 12 distinct visible pad IDs, covering 0–11 once.
- All three bundled JPEGs match the saved supplied originals byte for byte.
- All 39 original tablet asset files and original tablet layout JSON match the recovered prior baseline byte for byte.
- Swift tree-sitter grammar check: 25 source files, zero syntax errors at the time of this change.

Apple SDK compilation and real-device visual/touch verification are not available in this Linux workspace. Device verification must include all three modes, both play modes, clipping and sync lights on/off, preset and kit changes, all visible pads and the 16-pad menu, editor/import/export sheets, portrait and landscape rotation, iPhone notch/home-indicator clearance, and the unchanged iPad presentation. Audio buffer stability at 128 frames still requires real-device testing; this presentation change does not alter the audio callback.
