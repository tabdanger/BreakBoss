# Required Apple-device checks

These have not been performed in this session.

1. Open .swiftpm and compile/run on iPad. Report any compiler error with file and line.
2. Compare Modern/Vintage/Texture faceplates to approved images at full screen and Split View. Check knobs, hit regions, labels, dialogs, and accessible controls.
3. Open MENU → 4×4 pads. Trigger all 16 by touch, pointer, and external MIDI. Test quick release, overlapping holds, multiple channels, mode changes, editor opening, STOP, and controller disconnect.
4. Test one-shot pattern programming, clear/regenerate behavior, and latched faceplate transitions at multiple tempos. Confirm clock synchronization with real hardware.
5. Import WAV/AIFF/MP3/M4A and representative FLAC files through Files, drag/drop, and the pad editor. Try unsupported files and samples over 30 seconds. Change kits rapidly during loading.
6. Save/reopen old and new presets. Share a custom-sample .bbpack to another device, import, save, relaunch, and confirm the samples/settings remain. Test corrupt packages without losing the current state.
7. Export MIDI, stereo WAV, and all used-pad stems. Check exact duration/tempo, pitch, both channels, filenames, and drag/share into Logic Pro for iPad. Expect processed stems to differ from a summed master mix.
8. Listen to all modes and extreme control settings for pops, harsh aliasing, clicks, and tail behavior. Compare enabled/disabled Texture effects and clipper. Measure CPU/memory on the actual target iPad; Linux ratios are not iPad CPU readings.
9. Test headphones, speakers, USB interfaces, changing sample rates, background audio, interruptions, and relaunch. Confirm recovery without stuck notes or silent audio.
10. AUv3 hosting requires a separate Xcode extension integration and its own host automation, scheduling, state, and multi-instance tests. No AUv3 target is supplied.

## Stock bank and 128-frame checks for build 3

- Select every factory kit, including Lo-fi and Amapiano, and trigger all 16
  pads. Confirm stock names appear and no unavailable-sample notice appears.
- Check note 60 and octave/fifth 808 intervals against the kit tuning. Listen
  to the derived palm percussion, air cymbal, and short Amapiano bass in context.
- Confirm generated Main A/B/C/D develop over 2/4/8/4 bars. Try DICE; verify
  explicitly edited patterns remain protected.
- Inspect the active route's actual sample rate and IO duration with Apple
  audio diagnostics. At 48 kHz, 128 frames is about 2.67 ms per callback.
  Test speakers/headphones and the intended USB interface separately.
- Run the densest roll/fill, fast chromatic bass, reverse samples, kit switches,
  loop transitions, and extreme effect settings for several minutes. Record
  underruns, audible clicks/pops, CPU, and thermal state. Preferences alone do
  not verify 128-frame reliability.
- Stress repeated simultaneous triggers. The engine bounds work to 40 normal
  voices and eight short steal tails; triggers beyond that saturation limit
  can be dropped. Check ordinary musical use stays within that limit.
- Share a factory-only `.bbpack`, import on another device, and verify its
  embedded stock audio. During a kit load, audio export should report loading.
