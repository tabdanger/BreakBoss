# Channel rack rebuild

Baseline: the saved rebuild started from build 41 (b7dbc6e); build 42 (0dc14bb) was checked for compatibility before release. Only the step-sequencer surface is replaced. The original standalone/AUv3 instrument faceplate and per-channel piano roll remain available.

The reference layout has a brushed-metal chassis, left General/Generate/MIDI panel, pill-shaped channel headers and step buttons, a right sound browser, and bottom pattern/kit navigation. The textual request places the browser on the right; the second cropped image shows the left Generate panel, so both regions are included.

Library drops add independent persisted channels, including duplicate samples. Each row has a UUID and stable audio slot, so reorder never remaps notes. Insertion springs the header from a circle into its full-width oval; reduced-motion users receive a static insertion. The rack holds at most 12 sounds. A full rack offers removal and an explicit New empty rack action; Restore kit channels repopulates it. Audio slots, MIDI queues and meters stay preallocated; loading and preview decoding remain off the audio render thread.

KITS replaces sounds while retaining patterns, tempo and FX. Pattern PRESETS replace patterns, tempo and swing while retaining the loaded sounds and remaining processing. Old saved projects migrate without changing the 12-pad MIDI map or loop identities. Build 42 workspace channel identities, sound categories and intentionally empty racks migrate to the new model. Empty racks only gate the sequencer; the original instrument retains its 12 playable pads.

Feature preservation includes draw/paint/move/stretch; selection/move/duplicate/trim; erase; undo/redo; snap, triplets, zoom, page and follow; velocity/pitch lanes; swing/humanize; recording and metronome; channel controls/mute/solo; import and microphone recording; scales and per-channel piano roll; MIDI in/out and saved routing; kit/preset browsing; MIDI, mix and stem export; complete portable presets; performance pads and global FX.

Verification and Apple release results will be recorded after the completed source passes the checks. Physical-device touch/drop behavior and route-specific 128-frame CPU/click behavior require hardware testing.
