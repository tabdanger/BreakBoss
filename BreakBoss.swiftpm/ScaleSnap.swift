// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - SNAP TO SCALE on the controller (the scale math is in Scales.swift)

extension KnockController {
    var scaleRoot: Int { state.scaleRoot ?? 0 }
    var scale: MusicScale { MusicScale.named(state.scaleName) }
    var snapToScale: Bool { state.snapToScale ?? false }

    /// The MIDI note a channel plays at 0 semitones: the 808 sits on the kit's bass note,
    /// other channels count from C4. The channel's TUNE (whole semitones) is included.
    func baseNote(pad: Int) -> Int {
        let tune = Int(state.pads.indices.contains(pad) ? state.pads[pad].tune.rounded() : 0)
        let root = pad == Pad.bass808.rawValue ? MusicScale.midiNote(hz: kitDefinition.bassHz) : 60
        return root + tune
    }

    /// The pitches a channel's notes can take, in semitones from its base note: C1 to C8 on the
    /// piano roll (Tyrone, Oct 18).
    func pitchLimits(pad: Int) -> ClosedRange<Int> {
        let base = baseNote(pad: pad)
        return (MusicScale.lowestNote - base)...(MusicScale.highestNote - base)
    }

    /// Snaps a pitch offset (semitones) to the chosen scale when SNAP TO SCALE is on.
    func scaleSnapped(_ semis: Float, pad: Int) -> Float {
        guard snapToScale else { return semis }
        let base = baseNote(pad: pad)
        return Float(scale.snap(base + Int(semis.rounded()), root: scaleRoot) - base)
    }
}
