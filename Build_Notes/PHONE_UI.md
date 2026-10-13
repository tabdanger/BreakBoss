# Faceplates (0.4.0)

iPhone and iPad share the controller, audio engine, the 12 pads, kits, loops, MIDI, exports, presets and editors. The device idiom picks the artwork; a narrow iPad Split View keeps the iPad plate.

## Artwork

Six plates from Tyrone, 13 Oct 2026. The landscape ones replace the earlier iPad plates.

| Asset | Size | Used on |
|---|---|---|
| `Plate_modern/vintage/texture` | 1448 × 1086 | iPad |
| `PhonePlate_modern/vintage/texture` | 941 × 1672 | iPhone |

The plates in the app are cleaned copies of the originals. The knob pointers, the scope trace, the BPM digits and the kit/preset names are taken out, because the app draws those live. Every lit/unlit state is a small image cut from the same plate and placed on top:

- `oneshot_on_*` / `loop_off_*` (ONE-SHOT lit, LOOP dark)
- `led_off_*` (TEMPO SYNC / FOLLOW DAW off)
- `clipper_off_*`
- `play_on_*`

iPhone versions carry a `phone_` prefix (`phone_led_off_modern` and so on). `FaceplateLayout.overlayName` picks the right one, so the iPhone and iPad use the same code.

Positions are in each plate's own pixels: `Resources/KnockLayout.json` (iPad) and `Resources/PhoneKnockLayout.json` (iPhone).

## Pads

There are 12 pads on MIDI notes 36–47. The 808 plays chromatically on 48–84, with note 60 at the kit's tuning.

- iPhone: four columns by three rows. Pads 9–12 are on top and pads 1–4 on the bottom.
- iPad: six columns by two rows, with pads 1–6 on the bottom.

Saved presets from the 16-pad versions load their first 12 pads and loops.

## Still to check on a device

- All three modes, ONE-SHOT and LOOP, the clipper and both sync lights.
- Kit and preset menus, all 12 pads, the editors, import and export.
- Portrait and landscape on iPhone, and clearance for the notch and home indicator.
