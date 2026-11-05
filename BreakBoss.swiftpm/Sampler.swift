// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - The channel sampler (Tyrone, Oct 18: FL Studio's Channel Sampler, one per track)
//
// Every track can open a SAMPLER window with two pages. SAMPLE edits the sound itself: declicking,
// the tools, SMP START / LENGTH / IN / OUT / CROSSFADE / TRIM and time stretching are computed once
// and the new sound is swapped in (like FL's precomputed effects, they act when you let go of a
// control). ENVELOPE shapes every hit while it plays: an envelope and an LFO for pan, volume,
// MOD X (the filter's cutoff), MOD Y (its resonance) and pitch, the filter, and the root note.
//
// Loaded samples play as one-shots: the whole sound, whatever the note's length, unless the
// Volume envelope is on (then the note's end starts its release) or the sample loops.

enum SamplerDeclick: Int, Codable, CaseIterable {
    case outOnly, transient, transientBleed, generic, smooth, crossfade, off

    var title: String {
        switch self {
        case .outOnly: return "Out only (no bleeding)"
        case .transient: return "Transient (no bleeding)"
        case .transientBleed: return "Transient (bleeding)"
        case .generic: return "Generic (bleeding)"
        case .smooth: return "Smooth (bleeding)"
        case .crossfade: return "Crossfade (bleeding)"
        case .off: return "No declicking (sharp)"
        }
    }

    /// Fade in, seconds: the transient modes ramp only the first few samples, keeping the attack.
    var fadeIn: Double {
        switch self {
        case .outOnly, .off: return 0
        case .transient, .transientBleed: return 0.0006
        case .generic: return 0.02
        case .smooth: return 0.1
        case .crossfade: return 0.2
        }
    }

    /// Fade out, seconds (cosine S-shaped; Transient's no-bleeding fade also closes a low-pass).
    var fadeOut: Double {
        switch self {
        case .outOnly, .transient: return 0.01
        case .transientBleed, .generic: return 0.02
        case .smooth: return 0.1
        case .crossfade: return 0.2
        case .off: return 0
        }
    }

    /// Bleeding: the fades use the audio just outside the cut, so everything inside it plays whole.
    var bleeds: Bool { self == .transientBleed || self == .generic || self == .smooth || self == .crossfade }
}

/// Mode (stretch method): Resample changes pitch with speed, like tape; Stretch keeps pitch while
/// the length changes (and keeps the length while PITCH changes); Stretch pro uses longer grains for
/// smoother tonal sounds. Realtime does what Stretch does while the sound plays (grains read live),
/// so tempo changes and every note's pitch keep the length with nothing computed first.
enum SamplerStretch: Int, Codable, CaseIterable {
    case resample, stretch, stretchPro, realtime
    var title: String { ["Resample", "Stretch", "Stretch pro", "Realtime"][rawValue] }
    /// Computed into the sound before it plays (the other two act while it plays).
    var precomputed: Bool { self == .stretch || self == .stretchPro }
}

/// TIME: how long the sample lasts from start to end.
enum SamplerTime: Codable, Equatable, Hashable {
    case none
    case seconds(Double)
    case autodetect
    /// Locked to the project's tempo: the tempo it was locked at.
    case projectTempo(Double)
    case beats(Double)

    var title: String {
        switch self {
        case .none: return "(none)"
        case .seconds(let s): return s < 1 ? "\(Int((s * 1000).rounded())) ms" : String(format: "%.2f s", s)
        case .autodetect: return "Autodetect"
        case .projectTempo: return "Project tempo"
        case .beats(let b): return b >= 4 && Int(b) % 4 == 0 ? "\(Int(b) / 4) bar\(b == 4 ? "" : "s")" : (b == 1 ? "1 beat" : "\(Int(b)) beats")
        }
    }

    /// Changes with the project's tempo.
    var followsTempo: Bool {
        switch self {
        case .none, .seconds: return false
        default: return true
        }
    }

    /// How much longer the sample becomes (1 = as it is).
    func factor(sourceSeconds: Double, bpm: Double) -> Double {
        let secs = max(sourceSeconds, 0.001), tempo = max(bpm, 1)
        switch self {
        case .none: return 1
        case .seconds(let d): return max(0.01, d) / secs
        case .beats(let b): return max(0.25, b) * 60 / tempo / secs
        case .projectTempo(let locked): return max(locked, 1) / tempo
        case .autodetect:
            // the sample's tempo: the whole number of beats (1…64) that puts it nearest 120 BPM
            var best = 0.0, distance = Double.infinity
            var beats = 1.0
            while beats <= 64 {
                let t = beats * 60 / secs
                if t >= 70 && t <= 180 && abs(t - 120) < distance { distance = abs(t - 120); best = t }
                beats *= 2
            }
            return distance.isFinite ? best / tempo : 1
        }
    }
}

/// What an envelope or LFO moves (the ENVELOPE page's tabs).
enum SamplerTarget: Int, CaseIterable {
    case pan, volume, modX, modY, pitch
    var title: String { ["Panning", "Volume", "Mod X", "Mod Y", "Pitch"][rawValue] }
}

/// The filter's type (MOD X is its cutoff, MOD Y its resonance). Fast LP is a light one-pole low-pass
/// (fully open with MOD Y at 0 it's bypassed, the default); MOD Y turns it into a resonant one. LP and
/// LPx2 are resonant biquads (LPx2 two in a row, steeper); BP, HP, BS and the SVF ones are a
/// state-variable filter (SVF LPx2 two in a row).
enum SamplerFilterType: Int, Codable, CaseIterable {
    case fastLP, lp, bp, hp, bs, lp2, svfLP, svfLP2
    var title: String { ["Fast LP", "LP", "BP", "HP", "BS", "LPx2", "SVF LP", "SVF LPx2"][rawValue] }
}

/// DELAY, ATT, HOLD, DEC, SUS, REL and the three TENSIONs. Knob values 0…1.
/// The defaults leave the sound as it is (Tyrone, Oct 19: nothing on the ENVELOPE page changes a
/// sound until it's changed): no attack, full sustain, no release, and AMT 0 on the targets other
/// than Volume, so turning one knob switches the envelope on with only that knob heard.
struct SamplerEnvelope: Codable, Equatable, Hashable {
    var on = false
    var delay: Float = 0
    var attack: Float = 0
    var hold: Float = 0
    var decay: Float = 0
    var sustain: Float = 1
    var release: Float = 0
    /// −1…1: negative bends the curve so it moves fast first, positive slow first.
    var attackTension: Float = 0
    var decayTension: Float = 0
    var releaseTension: Float = 0
    /// −1…1, how far it moves its target (the volume envelope is the volume itself).
    var amount: Float = 0
    /// Times in beats instead of seconds.
    var tempo = false
    /// Points added on the graph (FL style). Empty = the shape the knobs make; once you add, move
    /// or delete a point the envelope follows these instead, until a knob is turned again.
    var points: [SamplerEnvPoint] = []
    /// The point the envelope waits on while the note is held (−1 = it runs straight through).
    var sustainPoint = -1

    var usesPoints: Bool { !points.isEmpty }

    /// The Volume envelope: the note's end matters (its release) only once SUS is turned down or REL
    /// up, or it has graph points; at full sustain with no release a one-shot plays out whole.
    var gates: Bool { usesPoints || sustain < 0.999 || release > 0.001 }

    /// A shape to add a stage back with (the envelope points menu's "Add a … point").
    static let shaped = SamplerEnvelope(on: false, delay: 0, attack: 0.12, hold: 0.18, decay: 0.45, sustain: 0.5, release: 0.3,
                                        attackTension: 0, decayTension: 0, releaseTension: 0, amount: 0.5)

    /// How long the knobs' shape runs before it waits on its sustain (seconds, or beats with Tempo on).
    var runUnits: Double { Self.units(delay, tempo: tempo) + Self.units(attack, tempo: tempo) + Self.units(hold, tempo: tempo) + Self.units(decay, tempo: tempo) }

    /// The knob setting for a time in seconds (Tempo off).
    static func knob(seconds: Double) -> Float { Float(min(1, cbrt(max(0, seconds) / 8))) }

    /// The Volume envelope as the sound already is (Tyrone, Oct 19: the envelope knows the sound before
    /// it changes it). HOLD is the sound's own length, to where it has died away (−60 dB), so switched on
    /// as it comes it plays the sound exactly as it was; then DEC fades it out, SUS 0, and REL is the 30 ms
    /// every note ends with anyway. Turning HOLD down shortens the sound from there, ATT fades its start
    /// in, SUS keeps it going while the note is held.
    /// `pitchedNotes`: the track plays notes below its root (the 808), which make the sound longer.
    static func measured(_ sample: SampleBuffer, reversed: Bool = false, pitchedNotes: Bool = false) -> SamplerEnvelope {
        var e = SamplerSettings.defaultEnvelopes[SamplerTarget.volume.rawValue]
        var peak: Float = 0
        for i in 0..<sample.length { peak = max(peak, abs(sample.left[i]), abs(sample.right[i])) }
        var end = sample.length
        if peak > 0, !reversed {
            let floor = peak * 0.001
            end = 1
            for i in stride(from: sample.length - 1, through: 0, by: -1) where max(abs(sample.left[i]), abs(sample.right[i])) > floor { end = i + 1; break }
        }
        let seconds = Double(end) / max(1, sample.sampleRate)
        e.hold = knob(seconds: seconds * (pitchedNotes ? 2 : 1.1) + 0.005)
        e.decay = knob(seconds: 0.02)
        e.sustain = 0
        e.release = knob(seconds: 0.03)
        return e
    }

    /// The knobs' shape as graph points: delay, peak, hold, sustain (where it waits) and release.
    func knobPoints() -> (points: [SamplerEnvPoint], sustain: Int) {
        func u(_ v: Float) -> Float { Float(Self.units(v, tempo: tempo)) }
        var p: [SamplerEnvPoint] = []
        if delay > 0.001 { p.append(SamplerEnvPoint(time: u(delay), level: 0)) }
        p.append(SamplerEnvPoint(time: u(attack), level: 1, tension: attackTension))
        p.append(SamplerEnvPoint(time: u(hold), level: 1))
        p.append(SamplerEnvPoint(time: u(decay), level: sustain.clamped(0, 1), tension: decayTension))
        let sus = p.count - 1
        p.append(SamplerEnvPoint(time: u(release), level: 0, tension: releaseTension))
        return (p, sus)
    }

    /// The same envelope drawn as points, ready to add to, move or delete from.
    func withPoints() -> SamplerEnvelope {
        guard !usesPoints else { return self }
        var e = self
        (e.points, e.sustainPoint) = knobPoints()
        return e
    }

    /// The longest a point can sit after the one before it (seconds, or beats with Tempo).
    var maxPointTime: Float { tempo ? 16 : 8 }

    /// A time knob in seconds (or beats with Tempo): cubic, so short times are easy to set.
    static func units(_ v: Float, tempo: Bool) -> Double {
        let x = Double(v.clamped(0, 1))
        return x * x * x * (tempo ? 16 : 8)
    }

    /// The knob setting for a length in beats (Tempo on); `scale` is 0.5 for the LFO's knobs.
    static func knob(beats: Double, scale: Double = 1) -> Float {
        Float(min(1, cbrt(max(0, beats / scale) / 16)))
    }

    /// The tempo lengths a time knob's Set menu offers, in beats.
    static let tempoLengths: [(String, Double)] = [("1/64", 1.0 / 16), ("1/32", 0.125), ("1/16T", 1.0 / 6), ("1/16", 0.25), ("1/8T", 1.0 / 3),
                                                   ("1/8", 0.5), ("1/4T", 2.0 / 3), ("1/4 (beat)", 1), ("1/2", 2), ("1 bar", 4),
                                                   ("2 bars", 8), ("4 bars", 16)]
}

/// A region drawn on the waveform: from `start` to `end`, parts of the sound (0…1).
struct SamplerRegion: Codable, Equatable, Hashable {
    var start: Float
    var end: Float
}

/// One point on the envelope graph: how long after the point before it (seconds, or beats with
/// Tempo), its level 0…1, and the bend of the line into it (−1…1, like the TENSION knobs).
struct SamplerEnvPoint: Codable, Equatable, Hashable {
    var time: Float
    var level: Float
    var tension: Float = 0
}

extension SamplerEnvelope {
    // older saves have no points: every field falls back to its default (an extension keeps the memberwise init)
    enum CodingKeys: String, CodingKey {
        case on, delay, attack, hold, decay, sustain, release, attackTension, decayTension, releaseTension, amount, tempo, points, sustainPoint
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        let d = SamplerEnvelope()
        self.init(on: v(.on, d.on), delay: v(.delay, d.delay), attack: v(.attack, d.attack), hold: v(.hold, d.hold), decay: v(.decay, d.decay),
                  sustain: v(.sustain, d.sustain), release: v(.release, d.release), attackTension: v(.attackTension, d.attackTension),
                  decayTension: v(.decayTension, d.decayTension), releaseTension: v(.releaseTension, d.releaseTension),
                  amount: v(.amount, d.amount), tempo: v(.tempo, d.tempo), points: v(.points, d.points), sustainPoint: v(.sustainPoint, d.sustainPoint))
        // saved before Oct 19: an envelope never switched on still has the old shape (ATT 12%, HOLD 18%,
        // DEC 45%, SUS 50%, REL 30%, AMT +50%); it takes the new defaults, so turning one knob later
        // changes only that knob
        var old = SamplerEnvelope.shaped
        old.amount = amount == 1 ? 1 : 0.5
        if self == old { self = d; amount = old.amount == 1 ? 1 : 0 }
    }
}

/// Up to 16 graph points in fixed storage, so a voice starts on the audio thread without touching an array.
struct SamplerEnvPoints {
    static let capacity = 16
    typealias Row = (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float)
    private static let zeros: Row = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var count = 0
    var sustain = -1
    private var times = SamplerEnvPoints.zeros, levels = SamplerEnvPoints.zeros, curves = SamplerEnvPoints.zeros

    init() {}

    init(_ e: SamplerEnvelope) {
        count = min(Self.capacity, e.points.count)
        sustain = e.sustainPoint < count ? e.sustainPoint : -1
        for i in 0..<count {
            let p = e.points[i]
            Self.put(&times, i, max(0, p.time))
            Self.put(&levels, i, p.level.clamped(0, 1))
            Self.put(&curves, i, powf(4, p.tension.clamped(-1, 1)))
        }
    }

    private static func put(_ r: inout Row, _ i: Int, _ v: Float) {
        withUnsafeMutableBytes(of: &r) { $0.storeBytes(of: v, toByteOffset: i * 4, as: Float.self) }
    }
    @inline(__always) private static func get(_ r: Row, _ i: Int) -> Float {
        withUnsafeBytes(of: r) { $0.load(fromByteOffset: i * 4, as: Float.self) }
    }
    @inline(__always) func time(_ i: Int) -> Float { Self.get(times, i) }
    @inline(__always) func level(_ i: Int) -> Float { Self.get(levels, i) }
    @inline(__always) func curve(_ i: Int) -> Float { Self.get(curves, i) }
}

/// The LFO: shape (sine, triangle, square), DELAY, ATT, AMT, SPEED, Tempo and Global.
struct SamplerLFO: Codable, Equatable, Hashable {
    var shape = 0
    var delay: Float = 0
    var attack: Float = 0
    /// −1…1 (0 = off).
    var amount: Float = 0
    var speed: Float = 0.5
    var tempo = false
    /// Every note shares one LFO (its phase runs on); otherwise each hit starts its own.
    var global = false

    static let divisions: [(String, Double)] = [("4 bars", 16), ("2 bars", 8), ("1 bar", 4), ("1/2", 2), ("1/4", 1), ("1/8", 0.5),
                                                 ("1/8T", 1.0 / 3), ("1/16", 0.25), ("1/16T", 1.0 / 6), ("1/32", 0.125)]
    var hertz: Double { 0.05 * pow(400, Double(speed.clamped(0, 1))) }
    var division: (String, Double) { Self.divisions[min(Self.divisions.count - 1, Int(speed.clamped(0, 1) * Float(Self.divisions.count)))] }
    var speedLabel: String { tempo ? division.0 : String(format: hertz < 1 ? "%.2f Hz" : "%.1f Hz", hertz) }
}

/// One track's sampler. Nil on a pad = never opened: its sound plays exactly as it always has.
struct SamplerSettings: Codable, Equatable {
    // the header: VOL pre-amplifies the sound before the mode's effects, 0…200% (0.5 = 100% = 0 dB,
    // all the way up +12 dB; the rack's volume stays 0…100%),
    // PITCH turns ± RANGE semitones
    var volume: Float = 0.5
    var pitch: Float = 0
    var range = 2
    // Content
    var keepOnDisk = false
    var resample = false
    var loadRegions = false
    var loadSliceMarkers = false
    var declick: SamplerDeclick = .outOnly
    // Playback
    var startOffset: Float = 0
    var useLoop = false
    var pingPong = false
    /// Custom loop points (the waveform's loop flags, or the properties menu), as parts of the sound: 0…1.
    var loopStart: Float = 0
    var loopEnd: Float = 1
    /// Region markers added on the waveform (parts of the sound, 0…1); START OFFSET snaps to them.
    var markers: [Float] = []
    /// Regions drawn on the waveform from a selection (parts of the sound). With "Load regions" on, the
    /// first one is what plays (instead of the file's own region).
    var regions: [SamplerRegion] = []
    // Time stretching: PITCH ±12 semitones, MUL ×¼…×4 (0.5 = ×1), TIME, Mode
    var stretchPitch: Float = 0
    var multiplier: Float = 0.5
    var time: SamplerTime = .none
    var stretch: SamplerStretch = .resample
    // Precomputed effects
    var removeDC = false
    var normalize = false
    var reverse = false
    var reversePolarity = false
    var fadeStereo = false
    var swapStereo = false
    var start: Float = 0
    var length: Float = 1
    var fadeIn: Float = 0
    var fadeOut: Float = 0
    var crossfade: Float = 0
    var trim: Float = 0
    /// POGO: a pitch bend over the start of the sound, −1…1 (0 = off). Right: it starts up to two
    /// octaves high and dives to its own pitch (a punchy drop); left: it starts slow and low and spins
    /// up to speed (a turntable start).
    var pogo: Float = 0
    /// EQ: a tilt, −1…1 (0 = flat): right brightens (highs up, lows down, ±6 dB at the ends), left darkens.
    var eq: Float = 0
    /// BOOST: gain after everything else, 0…1 = 0…+12 dB (after Normalize, so it still lifts it).
    var boost: Float = 0
    /// RM MIX: ring modulation by a sine (0 = off, 1 = all ring), at RM FREQ (20 Hz…5 kHz).
    var rmMix: Float = 0
    var rmFreq: Float = 0.5
    /// DELAY: a stereo ping-pong delay computed into the sound (its echoes lengthen it), level 0…1
    /// (0 = off), TIME a step of the tempo (the arpeggiator's steps).
    var delayMix: Float = 0
    var delayTime: Float = 0.5
    /// REVERB: a reverb computed into the sound (its tail lengthens it), level 0…1 (0 = off). Type A
    /// is a tight room, B a long hall.
    var reverbMix: Float = 0
    var reverbB = false
    // ENVELOPE page: one envelope and one LFO per target (SamplerTarget order)
    var envelopes: [SamplerEnvelope] = SamplerSettings.defaultEnvelopes
    var lfos: [SamplerLFO] = Array(repeating: SamplerLFO(), count: SamplerTarget.allCases.count)
    var cutoff: Float = 1
    var resonance: Float = 0
    var filterType: SamplerFilterType = .fastLP
    /// The note the sample plays at its own pitch (MIDI; 60 = C5, as FL names it).
    var rootNote = 60
    var mainPitch = true
    var addToKey = false
    /// Cents, −100…100.
    var fineTune: Float = 0
    // MISC page (Tyrone's third render, Oct 18)
    /// Polyphony: how many notes of this track sound at once (0 = no limit); Mono = one, its notes slide
    /// with Porta. SLIDE is the glide's time.
    var polyMax = 0
    var mono = false
    var porta = false
    var slide: Float = 0.3
    /// Time: GATE sets every note's length (0 = off, the note's own length); Full porta glides from the
    /// last note even after it has ended.
    var gate: Float = 0
    var fullPorta = false
    /// Tracking: how far velocity (Vol) and the note's distance from Mid (Key) move PAN, MOD X and MOD Y (−1…1).
    var velTrack: [Float] = [0, 0, 0]
    var keyTrack: [Float] = [0, 0, 0]
    var keyMid = 60
    /// Levels adjustment (FL's MISC offsets, on top of the main PAN / VOL / MOD X / MOD Y, every note):
    /// PAN and MOD X / MOD Y −1…1 (0 = none), VOL 0…1 with 0.5 = 100% (the header VOL's curve).
    var levelPan: Float = 0
    var levelVol: Float = 0.5
    var levelX: Float = 0
    var levelY: Float = 0
    /// Group: a note on this track stops the tracks whose By is this track's Cut (0 = none); Cut self
    /// stops this track's own last note.
    var cutGroup = 0
    var cutBy = 0
    var cutSelf = false
    /// Arpeggiator: 0 off, 1 up, 2 down, 3 up and down, 4 up and down (ends twice), 5 random.
    var arpMode = 0
    var arpTime: Float = 0.45
    var arpGate: Float = 0.5
    var arpRange = 1
    var arpRepeat = 1
    var arpSlide = false
    var arpChord = 0
    /// Echo delay / fat mode: Echoes repeats, each FEED quieter, moved by PAN, MOD X, MOD Y and PITCH,
    /// TIME apart (FEED at 0 = off). Ping pong swaps the pan each time; Fat mode packs them a few ms apart.
    var echoFeed: Float = 0
    var echoPan: Float = 0
    var echoX: Float = 0
    var echoY: Float = 0
    var echoPitch: Float = 0
    var echoTime: Float = 0.5
    var echoes = 4
    var echoPingPong = false
    var fatMode = false

    /// The arpeggiator's chords, as semitones from the note ("Auto" plays the note itself).
    static let chords: [(String, [Int])] = [("Auto (sustain)", [0]), ("Major", [0, 4, 7]), ("Minor", [0, 3, 7]), ("Major 7", [0, 4, 7, 11]),
                                            ("Minor 7", [0, 3, 7, 10]), ("Dominant 7", [0, 4, 7, 10]), ("Sus2", [0, 2, 7]), ("Sus4", [0, 5, 7]),
                                            ("Diminished", [0, 3, 6]), ("Augmented", [0, 4, 8]), ("Power (5th)", [0, 7]), ("Octave", [0, 12])]
    /// The arpeggiator's and echo's TIME knob: a step from 1/64 to 1 bar, in beats.
    static let steps: [(String, Double)] = [("1/64", 1.0 / 16), ("1/32", 0.125), ("1/16T", 1.0 / 6), ("1/16", 0.25), ("1/8T", 1.0 / 3),
                                            ("1/8", 0.5), ("1/4T", 2.0 / 3), ("1/4", 1), ("1/2", 2), ("1 bar", 4)]
    static func step(_ v: Float) -> (String, Double) { steps[min(steps.count - 1, Int(v.clamped(0, 1) * Float(steps.count)))] }
    /// SLIDE in seconds (cubic: short glides are easy to set).
    static func slideSeconds(_ v: Float) -> Double { 0.005 + 1.5 * pow(Double(v.clamped(0, 1)), 3) }
    /// GATE in seconds (0 = off).
    static func gateSeconds(_ v: Float) -> Double { v <= 0.001 ? 0 : 0.01 + 2 * pow(Double(v.clamped(0, 1)), 3) }

    static var defaultEnvelopes: [SamplerEnvelope] {
        var e = Array(repeating: SamplerEnvelope(), count: SamplerTarget.allCases.count)
        e[SamplerTarget.volume.rawValue].amount = 1
        return e
    }

    var mul: Double { pow(4, Double(multiplier.clamped(0, 1) - 0.5) * 2) }
    /// RM FREQ in Hz (20 Hz…5 kHz, evenly in octaves).
    static func ringHertz(_ v: Float) -> Double { 20 * pow(250, Double(v.clamped(0, 1))) }
    /// BOOST in dB.
    static func boostDB(_ v: Float) -> Float { 12 * v.clamped(0, 1) }

    /// VOL's gain: evenly in dB, −12 dB at the bottom, 100% in the middle, +12 dB at the top (Tyrone, Oct 19).
    static func preGain(_ v: Float) -> Float { powf(4, v.clamped(0, 1) * 2 - 1) }
    /// What a VOL knob shows: 50%…200% (100% = 0 dB, the tracks' volume scale) and its dB.
    static func volumeText(_ v: Float) -> String {
        let x = v.clamped(0, 1) * 2 - 1
        return "\(Int((powf(2, x) * 100).rounded()))%  " + String(format: "%+.1f dB", Double(x) * 12.04)
    }

    func envelope(_ t: SamplerTarget) -> SamplerEnvelope { envelopes.indices.contains(t.rawValue) ? envelopes[t.rawValue] : SamplerEnvelope() }
    func lfo(_ t: SamplerTarget) -> SamplerLFO { lfos.indices.contains(t.rawValue) ? lfos[t.rawValue] : SamplerLFO() }
    mutating func setEnvelope(_ t: SamplerTarget, _ change: (inout SamplerEnvelope) -> Void) {
        while envelopes.count < SamplerTarget.allCases.count { envelopes.append(SamplerEnvelope()) }
        change(&envelopes[t.rawValue])
    }
    mutating func setLFO(_ t: SamplerTarget, _ change: (inout SamplerLFO) -> Void) {
        while lfos.count < SamplerTarget.allCases.count { lfos.append(SamplerLFO()) }
        change(&lfos[t.rawValue])
    }

    /// Everything the SAMPLE page computes into the sound, and the tempo when TIME follows it.
    /// Nil when nothing does (the sound is used as it is).
    func offline(bpm: Double) -> SamplerOffline? {
        let pre = stretch.precomputed
        // the loop points only change the sound when CROSSFADE blends across them
        let blend = crossfade > 0.000_1
        let echo = delayMix > 0.000_1
        let o = SamplerOffline(resample: resample, declick: declick, removeDC: removeDC, normalize: normalize, reverse: reverse,
                               reversePolarity: reversePolarity, fadeStereo: fadeStereo, swapStereo: swapStereo,
                               start: start, length: length, fadeIn: fadeIn, fadeOut: fadeOut, crossfade: crossfade, trim: trim,
                               loopStart: blend ? loopStart : 0, loopEnd: blend ? loopEnd : 1,
                               stretch: pre ? stretch : .resample, stretchPitch: pre ? stretchPitch : 0,
                               multiplier: pre ? multiplier : 0.5, time: pre ? time : .none,
                               bpm: (pre && time.followsTempo) || echo ? bpm : 0,
                               pogo: pogo, eq: eq, boost: boost, rmMix: rmMix, rmFreq: rmMix > 0.000_1 ? rmFreq : 0.5,
                               delayMix: delayMix, delayTime: echo ? delayTime : 0.5,
                               reverbMix: reverbMix, reverbB: reverbMix > 0.000_1 ? reverbB : false)
        return o == SamplerOffline() ? nil : o
    }

    /// Custom loop points are set (not the whole sound).
    var customLoop: Bool { loopStart > 0.000_1 || loopEnd < 0.999_9 }

    /// After a waveform edit: the SAMPLE page's computed settings are in the new file now, so they go
    /// back to neutral (Resample / Realtime stretching plays live and stays), and the loop points and
    /// markers move with the audio (`map` takes a part of the old sound to the new one, nil = cut out).
    mutating func baked(_ map: (Float) -> Float?) {
        let d = SamplerSettings()
        resample = d.resample; declick = d.declick; removeDC = d.removeDC; normalize = d.normalize; reverse = d.reverse
        reversePolarity = d.reversePolarity; fadeStereo = d.fadeStereo; swapStereo = d.swapStereo
        start = d.start; length = d.length; fadeIn = d.fadeIn; fadeOut = d.fadeOut; crossfade = d.crossfade; trim = d.trim
        pogo = d.pogo; eq = d.eq; boost = d.boost; rmMix = d.rmMix; rmFreq = d.rmFreq
        delayMix = d.delayMix; delayTime = d.delayTime; reverbMix = d.reverbMix; reverbB = d.reverbB
        if stretch.precomputed { stretch = .resample; stretchPitch = 0; multiplier = 0.5; time = .none }
        markers = markers.compactMap(map)
        if customLoop {
            let a = map(loopStart) ?? 0, b = map(loopEnd) ?? 1
            loopStart = min(a, b); loopEnd = max(a, b)
            if loopEnd - loopStart < 0.001 { loopStart = 0; loopEnd = 1 }
        }
        startOffset = map(startOffset) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case volume, pitch, range, keepOnDisk, resample, loadRegions, loadSliceMarkers, declick, startOffset, useLoop, pingPong
        case loopStart, loopEnd, markers, regions
        case stretchPitch, multiplier, time, stretch, removeDC, normalize, reverse, reversePolarity, fadeStereo, swapStereo
        case start, length, fadeIn, fadeOut, crossfade, trim, pogo, eq, boost, rmMix, rmFreq, delayMix, delayTime, reverbMix, reverbB
        case envelopes, lfos, cutoff, resonance, filterType
        case rootNote, mainPitch, addToKey, fineTune
        case polyMax, mono, porta, slide, gate, fullPorta, velTrack, keyTrack, keyMid, cutGroup, cutBy, cutSelf
        case levelPan, levelVol, levelX, levelY
        case arpMode, arpTime, arpGate, arpRange, arpRepeat, arpSlide, arpChord
        case echoFeed, echoPan, echoX, echoY, echoPitch, echoTime, echoes, echoPingPong, fatMode
    }
}

extension SamplerSettings {
    /// Every field is optional in a saved project, so later versions can add controls.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        let d = SamplerSettings()
        volume = v(.volume, d.volume); pitch = v(.pitch, d.pitch); range = v(.range, d.range)
        keepOnDisk = v(.keepOnDisk, d.keepOnDisk); resample = v(.resample, d.resample)
        loadRegions = v(.loadRegions, d.loadRegions); loadSliceMarkers = v(.loadSliceMarkers, d.loadSliceMarkers)
        declick = v(.declick, d.declick); startOffset = v(.startOffset, d.startOffset)
        useLoop = v(.useLoop, d.useLoop); pingPong = v(.pingPong, d.pingPong)
        loopStart = v(.loopStart, d.loopStart); loopEnd = v(.loopEnd, d.loopEnd); markers = v(.markers, d.markers)
        regions = v(.regions, d.regions)
        stretchPitch = v(.stretchPitch, d.stretchPitch); multiplier = v(.multiplier, d.multiplier)
        time = v(.time, d.time); stretch = v(.stretch, d.stretch)
        removeDC = v(.removeDC, d.removeDC); normalize = v(.normalize, d.normalize); reverse = v(.reverse, d.reverse)
        reversePolarity = v(.reversePolarity, d.reversePolarity); fadeStereo = v(.fadeStereo, d.fadeStereo); swapStereo = v(.swapStereo, d.swapStereo)
        start = v(.start, d.start); length = v(.length, d.length); fadeIn = v(.fadeIn, d.fadeIn); fadeOut = v(.fadeOut, d.fadeOut)
        crossfade = v(.crossfade, d.crossfade); trim = v(.trim, d.trim)
        pogo = v(.pogo, d.pogo); eq = v(.eq, d.eq); boost = v(.boost, d.boost); rmMix = v(.rmMix, d.rmMix); rmFreq = v(.rmFreq, d.rmFreq)
        delayMix = v(.delayMix, d.delayMix); delayTime = v(.delayTime, d.delayTime)
        reverbMix = v(.reverbMix, d.reverbMix); reverbB = v(.reverbB, d.reverbB)
        envelopes = v(.envelopes, d.envelopes); lfos = v(.lfos, d.lfos)
        cutoff = v(.cutoff, d.cutoff); resonance = v(.resonance, d.resonance); filterType = v(.filterType, d.filterType)
        rootNote = v(.rootNote, d.rootNote); mainPitch = v(.mainPitch, d.mainPitch); addToKey = v(.addToKey, d.addToKey)
        fineTune = v(.fineTune, d.fineTune)
        polyMax = v(.polyMax, d.polyMax); mono = v(.mono, d.mono); porta = v(.porta, d.porta); slide = v(.slide, d.slide)
        gate = v(.gate, d.gate); fullPorta = v(.fullPorta, d.fullPorta)
        velTrack = v(.velTrack, d.velTrack); keyTrack = v(.keyTrack, d.keyTrack); keyMid = v(.keyMid, d.keyMid)
        cutGroup = v(.cutGroup, d.cutGroup); cutBy = v(.cutBy, d.cutBy); cutSelf = v(.cutSelf, d.cutSelf)
        levelPan = v(.levelPan, d.levelPan); levelVol = v(.levelVol, d.levelVol); levelX = v(.levelX, d.levelX); levelY = v(.levelY, d.levelY)
        arpMode = v(.arpMode, d.arpMode); arpTime = v(.arpTime, d.arpTime); arpGate = v(.arpGate, d.arpGate)
        arpRange = v(.arpRange, d.arpRange); arpRepeat = v(.arpRepeat, d.arpRepeat); arpSlide = v(.arpSlide, d.arpSlide); arpChord = v(.arpChord, d.arpChord)
        echoFeed = v(.echoFeed, d.echoFeed); echoPan = v(.echoPan, d.echoPan); echoX = v(.echoX, d.echoX); echoY = v(.echoY, d.echoY)
        echoPitch = v(.echoPitch, d.echoPitch); echoTime = v(.echoTime, d.echoTime); echoes = v(.echoes, d.echoes)
        echoPingPong = v(.echoPingPong, d.echoPingPong); fatMode = v(.fatMode, d.fatMode)
    }
}

/// The SAMPLE page's computed part (what the processed sound depends on).
struct SamplerOffline: Equatable {
    var resample = false
    var declick: SamplerDeclick = .outOnly
    var removeDC = false, normalize = false, reverse = false, reversePolarity = false, fadeStereo = false, swapStereo = false
    var start: Float = 0, length: Float = 1, fadeIn: Float = 0, fadeOut: Float = 0, crossfade: Float = 0, trim: Float = 0
    var loopStart: Float = 0, loopEnd: Float = 1
    var stretch: SamplerStretch = .resample
    var stretchPitch: Float = 0
    var multiplier: Float = 0.5
    var time: SamplerTime = .none
    var bpm: Double = 0
    var pogo: Float = 0, eq: Float = 0, boost: Float = 0, rmMix: Float = 0, rmFreq: Float = 0.5
    var delayMix: Float = 0, delayTime: Float = 0.5, reverbMix: Float = 0, reverbB = false
}

// MARK: - Envelope presets (Tyrone, Oct 18: AHDSR presets for 808s, kicks and snares, and your own)

struct SamplerEnvelopePreset: Codable, Equatable, Identifiable {
    var name: String
    /// "808", "Kick" or "Snare".
    var kind: String
    /// The five envelopes (SamplerTarget order): presets shape the volume and often the pitch.
    var envelopes: [SamplerEnvelope]
    var id: String { kind + "/" + name }

    static let kinds = ["808", "Kick", "Snare"]

    private static func make(_ name: String, _ kind: String, hold: Float, decay: Float, sustain: Float = 0, release: Float,
                             attack: Float = 0.04, decayTension: Float = 0, drop: Float = 0, dropDecay: Float = 0.25) -> SamplerEnvelopePreset {
        var e = SamplerSettings.defaultEnvelopes
        e[SamplerTarget.volume.rawValue] = SamplerEnvelope(on: true, delay: 0, attack: attack, hold: hold, decay: decay, sustain: sustain,
                                                          release: release, attackTension: 0, decayTension: decayTension, releaseTension: -0.3, amount: 1)
        if drop != 0 {
            // the pitch starts `drop` × 12 semitones up and falls to the note (the knock of a kick, an 808's bite)
            e[SamplerTarget.pitch.rawValue] = SamplerEnvelope(on: true, delay: 0, attack: 0, hold: 0, decay: dropDecay, sustain: 0,
                                                             release: 0.1, attackTension: 0, decayTension: -0.6, releaseTension: 0, amount: drop)
        }
        return SamplerEnvelopePreset(name: name, kind: kind, envelopes: e)
    }

    /// The factory presets. Knob values: a time of v lasts v³ × 8 s (0.5 ≈ 1 s, 0.3 ≈ 0.2 s).
    static let factory: [SamplerEnvelopePreset] = [
        make("Long 808", "808", hold: 0.25, decay: 0.78, sustain: 0, release: 0.4, drop: 0.08),
        make("Short 808", "808", hold: 0.18, decay: 0.55, release: 0.25, drop: 0.08),
        make("Sliding 808", "808", hold: 0.3, decay: 0.7, sustain: 0.35, release: 0.45, drop: 0.25, dropDecay: 0.35),
        make("Held 808", "808", hold: 0.2, decay: 0.6, sustain: 0.8, release: 0.35),
        make("Punchy kick", "Kick", hold: 0.16, decay: 0.42, release: 0.15, drop: 0.5, dropDecay: 0.18),
        make("Tight kick", "Kick", hold: 0.1, decay: 0.3, release: 0.1, attack: 0.02, decayTension: -0.5, drop: 0.35, dropDecay: 0.14),
        make("Boomy kick", "Kick", hold: 0.2, decay: 0.6, release: 0.3, drop: 0.3, dropDecay: 0.3),
        make("Snappy snare", "Snare", hold: 0.12, decay: 0.35, release: 0.15, attack: 0.02, decayTension: -0.6),
        make("Fat snare", "Snare", hold: 0.18, decay: 0.48, release: 0.25, drop: 0.12, dropDecay: 0.15),
        make("Roomy snare", "Snare", hold: 0.18, decay: 0.55, sustain: 0.1, release: 0.42)
    ]

    /// The box method: the sound stays at full level while the note is held (Hold all the way up, the
    /// rest at zero) and stops the moment it's let go.
    static let boxMethod: SamplerEnvelopePreset = {
        var e = SamplerSettings.defaultEnvelopes
        e[SamplerTarget.volume.rawValue] = SamplerEnvelope(on: true, delay: 0, attack: 0, hold: 1, decay: 0, sustain: 1,
                                                          release: 0.05, attackTension: 0, decayTension: 0, releaseTension: 0, amount: 1)
        return SamplerEnvelopePreset(name: "Box method", kind: "Basic", envelopes: e)
    }()

    /// Your own presets (saved on this device).
    static var saved: [SamplerEnvelopePreset] {
        get {
            guard let d = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([SamplerEnvelopePreset].self, from: d)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
    private static let key = "samplerEnvelopePresets"

    static func save(_ p: SamplerEnvelopePreset) {
        var all = saved.filter { $0.id != p.id }
        all.append(p)
        saved = all
    }

    static func delete(_ p: SamplerEnvelopePreset) { saved = saved.filter { $0.id != p.id } }
}
