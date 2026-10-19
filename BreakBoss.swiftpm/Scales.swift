// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - SNAP TO SCALE (FL Studio's scale list)
//
// The piano roll can snap notes to a key and scale so the 808 (or any channel) stays in key.
// Pitches are worked out from the channel's real note: the kit's 808 root (bassHz) plus the
// channel's TUNE, so "C minor" means C minor on the speaker, not on the grid.

struct MusicScale: Equatable {
    let name: String
    /// Semitones above the root.
    let steps: [Int]

    /// FL Studio's piano roll scales, in its menu order.
    static let all: [MusicScale] = [
        MusicScale(name: "Major (Ionian)", steps: [0, 2, 4, 5, 7, 9, 11]),
        MusicScale(name: "Dorian", steps: [0, 2, 3, 5, 7, 9, 10]),
        MusicScale(name: "Phrygian", steps: [0, 1, 3, 5, 7, 8, 10]),
        MusicScale(name: "Lydian", steps: [0, 2, 4, 6, 7, 9, 11]),
        MusicScale(name: "Mixolydian", steps: [0, 2, 4, 5, 7, 9, 10]),
        MusicScale(name: "Minor (Aeolian)", steps: [0, 2, 3, 5, 7, 8, 10]),
        MusicScale(name: "Locrian", steps: [0, 1, 3, 5, 6, 8, 10]),
        MusicScale(name: "Harmonic minor", steps: [0, 2, 3, 5, 7, 8, 11]),
        MusicScale(name: "Melodic minor", steps: [0, 2, 3, 5, 7, 9, 11]),
        MusicScale(name: "Whole tone", steps: [0, 2, 4, 6, 8, 10]),
        MusicScale(name: "Diminished", steps: [0, 2, 3, 5, 6, 8, 9, 11]),
        MusicScale(name: "Major pentatonic", steps: [0, 2, 4, 7, 9]),
        MusicScale(name: "Minor pentatonic", steps: [0, 3, 5, 7, 10]),
        MusicScale(name: "Jap in sen", steps: [0, 1, 5, 7, 10]),
        MusicScale(name: "Major bebop", steps: [0, 2, 4, 5, 7, 8, 9, 11]),
        MusicScale(name: "Dominant bebop", steps: [0, 2, 4, 5, 7, 9, 10, 11]),
        MusicScale(name: "Blues", steps: [0, 3, 5, 6, 7, 10]),
        MusicScale(name: "Arabic", steps: [0, 1, 4, 5, 7, 8, 11]),
        MusicScale(name: "Enigmatic", steps: [0, 1, 4, 6, 8, 10, 11]),
        MusicScale(name: "Neapolitan", steps: [0, 1, 3, 5, 7, 9, 11]),
        MusicScale(name: "Neapolitan minor", steps: [0, 1, 3, 5, 7, 8, 11]),
        MusicScale(name: "Hungarian minor", steps: [0, 2, 3, 6, 7, 8, 11]),
        MusicScale(name: "Chromatic", steps: Array(0..<12)),
    ]

    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static func named(_ name: String?) -> MusicScale {
        all.first { $0.name == name } ?? all[5]
    }

    /// Whether a MIDI note is in this scale with the given root (0 = C … 11 = B).
    func contains(_ note: Int, root: Int) -> Bool {
        steps.contains((((note - root) % 12) + 12) % 12)
    }

    /// The nearest note in the scale (a tie goes down, like FL).
    func snap(_ note: Int, root: Int) -> Int {
        if contains(note, root: root) { return note }
        for d in 1...6 {
            if contains(note - d, root: root) { return note - d }
            if contains(note + d, root: root) { return note + d }
        }
        return note
    }

    /// The piano roll's keys: C1 (24) to C8 (108).
    static let lowestNote = 24, highestNote = 108

    static func noteName(_ note: Int) -> String {
        "\(noteNames[((note % 12) + 12) % 12])\(Int((Double(note) / 12).rounded(.down)) - 1)"
    }

    /// MIDI note of a frequency (nearest semitone).
    static func midiNote(hz: Float) -> Int {
        Int((69 + 12 * log2(Double(max(hz, 1)) / 440)).rounded())
    }
}

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
