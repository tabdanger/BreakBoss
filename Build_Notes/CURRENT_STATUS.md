# BreakBoss 0.3.1 · universal update

The iPhone and iPad app and existing AUv3 share the completed sound-bank and pattern updates. iPhone uses all three supplied faceplate JPEGs unchanged; original tablet artwork/layout resources remain unchanged. Shared controls, presets, MIDI and exports work through the same controller.

- 544 factory assignments, 34 kits, 308 processed WAVs from 42 uploaded source hits.
- Full 16-pad grid plus 12 visible faceplate pads on both devices; adaptive editors and menu actions.
- Existing App Store and AUv3 identities preserved; native targets support device families 1,2.
- Audio requests 48 kHz/128 frames with indexed scheduling, preallocated voice/onset fades and off-callback loading.
- AU MIDI offsets now survive the callback and loop gates use exact render boundaries. Host automation uses preallocated storage and bounded try-lock publication; ramp capability is not advertised.
- Corrected app-only archive puts Package.swift at its root, avoiding the invalid outer swiftpm folder in the earlier download.

Local checks pass: Swift grammar, complete stock manifest/PCM/provenance validation (544 assignments/308 WAVs), eight scheduler-model checks, eleven mocked release-helper checks, universal metadata and identical app/AUv3 source/resource staging. Maximum decoded kit estimate is 1.789 MiB and calibrated bass roots differ by at most 0.5518 cents. These figures are not measured whole-app CPU/memory.

Apple compilation and actual in-app self-tests on iPhone and iPad simulators are performed by the existing GitHub macOS workflow for the release commit. Its result and the upload/Apple processing result must be checked before claiming TestFlight availability. Physical device 128-frame CPU, MIDI hardware, DAW interactions and touch behavior require device testing.
