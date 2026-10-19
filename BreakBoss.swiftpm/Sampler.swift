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

    /// VOL's gain: straight up to 100% in the middle, then up to +12 dB.
    static func preGain(_ v: Float) -> Float {
        let x = v.clamped(0, 1)
        return x <= 0.5 ? x * 2 : powf(4, (x - 0.5) * 2)
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
        let o = SamplerOffline(resample: resample, declick: declick, removeDC: removeDC, normalize: normalize, reverse: reverse,
                               reversePolarity: reversePolarity, fadeStereo: fadeStereo, swapStereo: swapStereo,
                               start: start, length: length, fadeIn: fadeIn, fadeOut: fadeOut, crossfade: crossfade, trim: trim,
                               loopStart: blend ? loopStart : 0, loopEnd: blend ? loopEnd : 1,
                               stretch: pre ? stretch : .resample, stretchPitch: pre ? stretchPitch : 0,
                               multiplier: pre ? multiplier : 0.5, time: pre ? time : .none,
                               bpm: pre && time.followsTempo ? bpm : 0)
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
        case start, length, fadeIn, fadeOut, crossfade, trim, envelopes, lfos, cutoff, resonance, filterType
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
}

// MARK: - Computing the sound (off the audio thread)

enum SamplerProcessor {
    /// The sample with the SAMPLE page applied. `engineRate` is what Resample converts to.
    static func process(_ raw: SampleBuffer, _ o: SamplerOffline, engineRate: Double) -> SampleBuffer {
        var l = Array(UnsafeBufferPointer(start: raw.left, count: raw.length))
        var r = Array(UnsafeBufferPointer(start: raw.right, count: raw.length))
        var rate = raw.sampleRate
        // the file's slice markers and loop region follow the sound through every step
        var marks = raw.cues
        var region = raw.region.map { [$0.lowerBound, $0.upperBound] } ?? []
        func remap(_ f: (Int) -> Int) { marks = marks.map(f); region = region.map(f) }
        // Resample: converted to the engine's rate once (smooth cubic), not on every hit
        if o.resample, engineRate > 0, abs(rate - engineRate) > 0.5 {
            let k = engineRate / rate
            remap { Int(Double($0) * k) }
            l = convert(l, step: rate / engineRate)
            r = convert(r, step: rate / engineRate)
            rate = engineRate
        }
        if o.removeDC { removeDC(&l); removeDC(&r) }
        if o.reversePolarity { for i in l.indices { l[i] = -l[i]; r[i] = -r[i] } }
        if o.swapStereo { swap(&l, &r) }
        if o.reverse {
            l.reverse(); r.reverse()
            let last = l.count - 1
            remap { last - $0 }
            region.reverse()
        }

        // SMP START and LENGTH, then TRIM the quiet end
        let total = max(1, l.count)
        let a = min(total - 1, Int(Double(o.start.clamped(0, 1)) * Double(total)))
        var b = min(total, a + max(1, Int((Double(o.length.clamped(0, 1)) * Double(total - a)).rounded())))
        let threshold: Float = o.trim <= 0.000_1 ? 0 : powf(10, (-90 + 70 * o.trim.clamped(0, 1)) / 20)
        while b > a + 1 && max(abs(l[b - 1]), abs(r[b - 1])) <= threshold { b -= 1 }

        // Declicking: bleeding fades use the audio just outside the cut
        let d = o.declick
        let wantIn = Int(d.fadeIn * rate), wantOut = Int(d.fadeOut * rate)
        let bleedIn = d.bleeds ? min(a, wantIn) : 0
        let bleedOut = d.bleeds ? min(total - b, wantOut) : 0
        var ol = Array(l[(a - bleedIn)..<(b + bleedOut)])
        var or = Array(r[(a - bleedIn)..<(b + bleedOut)])
        let n = ol.count
        remap { $0 - (a - bleedIn) }
        // (bleeding fades run over the audio outside the cut; at the file's own start or end there's no cut)
        let fin = d.bleeds ? bleedIn : min(n / 2, wantIn)
        let fout = d.bleeds ? bleedOut : min(n / 2, wantOut)
        if fin > 0 { fade(&ol, &or, from: 0, count: fin, rising: true) }
        if fout > 0 {
            if d == .transient { filterFade(&ol, &or, count: fout) } else { fade(&ol, &or, from: n - fout, count: fout, rising: false) }
        }

        // IN and OUT: quick fades (fully left = off)
        let inLen = Int(Double(n) * Double(o.fadeIn * o.fadeIn))
        if inLen > 1 { fade(&ol, &or, from: 0, count: min(inLen, n), rising: true) }
        let outLen = Int(Double(n) * Double(o.fadeOut * o.fadeOut))
        if outLen > 1 { fade(&ol, &or, from: n - min(outLen, n), count: min(outLen, n), rising: false) }

        // CROSSFADE: the loop's end blends into the audio leading up to its start, so the jump back is
        // seamless. With no audio before the loop start, the end blends into the start and the loop
        // runs from the end of the blend.
        var loopStart = 0, loopEnd = 0
        let ls = min(n - 1, max(0, Int(Double(o.loopStart.clamped(0, 1)) * Double(n))))
        let le = max(ls + 1, min(n, Int(Double(o.loopEnd.clamped(0, 1)) * Double(n))))
        let xLen = Int(Double((le - ls) / 2) * Double(o.crossfade.clamped(0, 1)))
        if xLen > 1 {
            let lead = ls >= xLen
            for i in 0..<xLen {
                let t = Float(i + 1) / Float(xLen)
                let w = 0.5 - 0.5 * cosf(.pi * t)
                let j = le - xLen + i
                let k = lead ? ls - xLen + i : ls + i
                ol[j] = ol[j] * (1 - w) + ol[k] * w
                or[j] = or[j] * (1 - w) + or[k] * w
            }
            loopStart = lead ? ls : ls + xLen
            loopEnd = le
        }

        // Fade stereo: the sound moves from the left channel to the right
        if o.fadeStereo && n > 1 {
            for i in 0..<n {
                let th = Float(i) / Float(n - 1) * .pi / 2
                ol[i] *= cosf(th); or[i] *= sinf(th)
            }
        }

        var stretched = 1.0
        // Time stretching (Stretch / Stretch pro): the length changes, the pitch doesn't (and PITCH keeps the length)
        if o.stretch != .resample {
            let f = o.time.factor(sourceSeconds: Double(n) / rate, bpm: o.bpm) * pow(4, Double(o.multiplier.clamped(0, 1) - 0.5) * 2)
            let p = pow(2, Double(o.stretchPitch) / 12)
            if abs(f - 1) > 0.001 || abs(p - 1) > 0.000_1 {
                let window = Int((o.stretch == .stretchPro ? 0.046 : 0.023) * rate)
                (ol, or) = stretch(ol, or, by: (f * p).clamped(0.1, 10), window: max(256, window))
                if abs(p - 1) > 0.000_1 { ol = convert(ol, step: p); or = convert(or, step: p) }
                loopStart = Int(Double(loopStart) * f)
                loopEnd = Int(Double(loopEnd) * f)
                stretched = f
                remap { Int(Double($0) * f) }
            }
        }

        if o.normalize {
            var peak: Float = 0
            for i in ol.indices { peak = max(peak, abs(ol[i]), abs(or[i])) }
            if peak > 0.000_01 { let g = 0.98 / peak; for i in ol.indices { ol[i] *= g; or[i] *= g } }
        }
        if ol.isEmpty { ol = [0]; or = [0] }
        let out = SampleBuffer(left: ol, right: or, sampleRate: rate)
        out.bitDepth = raw.bitDepth
        out.stereo = raw.stereo || o.fadeStereo
        out.loopStart = min(max(0, loopStart), max(0, ol.count - 2))
        out.loopEnd = loopEnd > out.loopStart + 1 ? min(loopEnd, ol.count - 1) : 0
        out.cues = marks.filter { $0 > 0 && $0 < ol.count }
        if region.count == 2, region[0] >= 0, region[1] < ol.count, region[1] - region[0] > 32 { out.region = region[0]...region[1] }
        if d.bleeds { out.fadeMarks = (Int(Double(fin) * stretched), ol.count - Int(Double(fout) * stretched)) }
        return out
    }

    private static func removeDC(_ x: inout [Float]) {
        guard !x.isEmpty else { return }
        var sum: Double = 0
        for v in x { sum += Double(v) }
        let mean = Float(sum / Double(x.count))
        for i in x.indices { x[i] -= mean }
    }

    /// Cosine S-shaped fade.
    private static func fade(_ l: inout [Float], _ r: inout [Float], from: Int, count: Int, rising: Bool) {
        guard count > 0 else { return }
        for i in 0..<count {
            let j = from + i
            guard j >= 0 && j < l.count else { continue }
            let t = Float(i) / Float(count)
            let w = 0.5 - 0.5 * cosf(.pi * t)
            let g = rising ? w : 1 - w
            l[j] *= g; r[j] *= g
        }
    }

    /// Transient's declick out: a fade with a low-pass closing over it, so the cut doesn't click.
    private static func filterFade(_ l: inout [Float], _ r: inout [Float], count: Int) {
        let from = l.count - count
        guard from >= 0, count > 0 else { return }
        var fl = l[from], fr = r[from]
        for i in 0..<count {
            let t = Float(i) / Float(count)
            let c = 1 - 0.95 * t
            fl += c * (l[from + i] - fl); fr += c * (r[from + i] - fr)
            let g = 0.5 + 0.5 * cosf(.pi * t)
            l[from + i] = fl * g; r[from + i] = fr * g
        }
    }

    /// Reads `x` every `step` samples with cubic (Hermite) interpolation: step > 1 = shorter and higher.
    static func convert(_ x: [Float], step: Double) -> [Float] {
        guard x.count > 1, step > 0, step.isFinite else { return x }
        let count = max(1, Int(Double(x.count) / step))
        var out = [Float](repeating: 0, count: count)
        func at(_ i: Int) -> Float { x[min(max(i, 0), x.count - 1)] }
        for i in 0..<count {
            let pos = Double(i) * step
            let k = Int(pos)
            let t = Float(pos - Double(k))
            let y0 = at(k - 1), y1 = at(k), y2 = at(k + 1), y3 = at(k + 2)
            let c1 = 0.5 * (y2 - y0)
            let c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
            let c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
            out[i] = ((c3 * t + c2) * t + c1) * t + y1
        }
        return out
    }

    /// WSOLA time stretch: Hann grains overlapped half and half, each nudged (within a quarter grain)
    /// to where it lines up best with the one before, so transients and tones stay intact.
    static func stretch(_ l: [Float], _ r: [Float], by factor: Double, window w: Int) -> ([Float], [Float]) {
        let n = l.count
        guard n > w * 2, factor.isFinite, factor > 0 else {
            // too short to stretch: change its speed instead
            return (convert(l, step: 1 / factor), convert(r, step: 1 / factor))
        }
        let hop = w / 2
        let outCount = max(1, Int(Double(n) * factor))
        var ol = [Float](repeating: 0, count: outCount + w)
        var or = [Float](repeating: 0, count: outCount + w)
        var norm = [Float](repeating: 0, count: outCount + w)
        let window = (0..<w).map { 0.5 - 0.5 * cosf(2 * .pi * Float($0) / Float(w)) }
        let mid = (0..<n).map { (l[$0] + r[$0]) * 0.5 }
        let tolerance = w / 4
        let compare = hop
        var previous = 0
        var k = 0
        while k * hop < outCount {
            let nominal = Int(Double(k * hop) / factor)
            var pos = min(max(0, nominal), max(0, n - 1))
            if k > 0 {
                // the natural continuation of the last grain, and the best match for it near `nominal`
                let natural = previous + hop
                var best = -Float.infinity
                var d = -tolerance
                while d <= tolerance {
                    let cand = nominal + d
                    if cand >= 0 && cand + compare < n && natural + compare < n {
                        var c: Float = 0
                        var i = 0
                        while i < compare { c += mid[cand + i] * mid[natural + i]; i += 2 }
                        if c > best { best = c; pos = cand }
                    }
                    d += 2
                }
            }
            let o = k * hop
            for i in 0..<w where pos + i < n {
                ol[o + i] += l[pos + i] * window[i]
                or[o + i] += r[pos + i] * window[i]
                norm[o + i] += window[i]
            }
            previous = pos
            k += 1
        }
        for i in 0..<outCount where norm[i] > 0.05 { ol[i] /= norm[i]; or[i] /= norm[i] }
        return (Array(ol[0..<outCount]), Array(or[0..<outCount]))
    }
}

// MARK: - Playing (audio thread: plain values, nothing allocates)

/// A track's sampler as the audio thread reads it (built when the kit is published).
struct SamplerRT {
    var active = false
    /// The header's VOL as a gain: 0 at the bottom, 1 in the middle, 4 (+12 dB) all the way up.
    var preGain: Float = 1
    /// The header's PITCH × RANGE, the root note and the fine tune, in semitones.
    var semis: Float = 0
    var mainPitch = true
    var startOffset: Float = 0
    var loop = false
    var pingPong = false
    /// The loop points, as parts of the sound (a CROSSFADE computes its own into the sound instead).
    var loopStart: Float = 0
    var loopEnd: Float = 1
    /// Realtime stretching: TIME × MUL changes the length and PITCH the pitch, each on its own, live.
    var realtime = false
    var rtTime: SamplerTime = .none
    var rtMul: Double = 1
    var rtPitch: Float = 0
    /// Load regions: the loop runs over the file's own loop region (WAV 'smpl') when it has one.
    var regions = false
    /// The first region drawn on the waveform (parts of the sound), used instead of the file's.
    var userRegion: (Float, Float) = (0, 1)
    var hasUserRegion = false
    /// Resample mode's speed: TIME, MUL and PITCH change it as they would a tape.
    var tapeTime: SamplerTime = .none
    var tapeMul: Double = 1
    var tapePitch: Float = 0
    var pan = SamplerEnvelope(), volume = SamplerEnvelope(), modX = SamplerEnvelope(), modY = SamplerEnvelope(), pitch = SamplerEnvelope()
    /// The Volume envelope is on and the note's end starts its release (see SamplerEnvelope.gates).
    var volumeGates: Bool { volume.on && volume.gates }
    /// Their graph points, copied into fixed storage here (off the audio thread)
    var points = (SamplerEnvPoints(), SamplerEnvPoints(), SamplerEnvPoints(), SamplerEnvPoints(), SamplerEnvPoints())
    var lfoPan = SamplerLFO(), lfoVolume = SamplerLFO(), lfoX = SamplerLFO(), lfoY = SamplerLFO(), lfoPitch = SamplerLFO()
    var cutoff: Float = 1
    var resonance: Float = 0
    var filterType = SamplerFilterType.fastLP
    // MISC
    var polyMax = 0
    var mono = false
    var porta = false
    var slideSeconds = 0.0
    var gateSeconds = 0.0
    var fullPorta = false
    var velTrack: (Float, Float, Float) = (0, 0, 0)
    var keyTrack: (Float, Float, Float) = (0, 0, 0)
    var keyMid: Float = 60
    /// Levels adjustment: pan, MOD X, MOD Y offsets and a gain
    var levels: (Float, Float, Float) = (0, 0, 0)
    var levelGain: Float = 1
    var cutGroup = 0, cutBy = 0
    var cutSelf = false
    var arpMode = 0
    var arpStepBeats = 0.25
    var arpGate: Float = 0.5
    var arpRange = 1
    var arpRepeat = 1
    var arpSlide = false
    /// The chord's notes (semitones), at most 4; `arpNotes` of them are used.
    var arpChord: (Int, Int, Int, Int) = (0, 0, 0, 0)
    var arpNotes = 1
    /// Chord "Auto (sustain)": the arpeggio runs over the notes held on the track (a chord in the piano
    /// roll, keys held on a keyboard), joining and leaving as they start and end.
    var arpAuto = true
    var echoFeed: Float = 0
    var echoPan: Float = 0, echoX: Float = 0, echoY: Float = 0, echoPitch: Float = 0
    var echoBeats = 0.5
    var echoes = 0
    var echoPingPong = false
    var fatMode = false

    init() {}

    init(_ s: SamplerSettings?) {
        guard let s else { return }
        active = true
        preGain = SamplerSettings.preGain(s.volume)
        let bend = s.pitch.clamped(-1, 1) * Float(max(1, s.range))
        semis = (s.addToKey ? bend.rounded() : bend) + Float(60 - s.rootNote) + s.fineTune.clamped(-100, 100) / 100
        mainPitch = s.mainPitch
        startOffset = s.startOffset.clamped(0, 0.99)
        loop = s.useLoop
        pingPong = s.pingPong
        if s.customLoop { loopStart = s.loopStart.clamped(0, 1); loopEnd = s.loopEnd.clamped(0, 1) }
        regions = s.loadRegions
        if let first = s.regions.first, first.end > first.start {
            userRegion = (first.start.clamped(0, 1), first.end.clamped(0, 1))
            hasUserRegion = true
        }
        if s.stretch == .resample {
            tapeTime = s.time
            tapeMul = s.mul
            tapePitch = s.stretchPitch
        } else if s.stretch == .realtime {
            realtime = true
            rtTime = s.time
            rtMul = s.mul
            rtPitch = s.stretchPitch
        }
        pan = s.envelope(.pan); volume = s.envelope(.volume); modX = s.envelope(.modX); modY = s.envelope(.modY); pitch = s.envelope(.pitch)
        points = (SamplerEnvPoints(pan), SamplerEnvPoints(volume), SamplerEnvPoints(modX), SamplerEnvPoints(modY), SamplerEnvPoints(pitch))
        lfoPan = s.lfo(.pan); lfoVolume = s.lfo(.volume); lfoX = s.lfo(.modX); lfoY = s.lfo(.modY); lfoPitch = s.lfo(.pitch)
        cutoff = s.cutoff.clamped(0, 1)
        resonance = s.resonance.clamped(0, 1)
        filterType = s.filterType
        polyMax = s.mono ? 1 : max(0, s.polyMax)
        mono = s.mono
        porta = s.porta
        slideSeconds = SamplerSettings.slideSeconds(s.slide)
        gateSeconds = SamplerSettings.gateSeconds(s.gate)
        fullPorta = s.fullPorta
        func three(_ a: [Float]) -> (Float, Float, Float) { (a.count > 0 ? a[0] : 0, a.count > 1 ? a[1] : 0, a.count > 2 ? a[2] : 0) }
        velTrack = three(s.velTrack); keyTrack = three(s.keyTrack); keyMid = Float(s.keyMid)
        levels = (s.levelPan.clamped(-1, 1), s.levelX.clamped(-1, 1), s.levelY.clamped(-1, 1))
        levelGain = SamplerSettings.preGain(s.levelVol)
        cutGroup = s.cutGroup; cutBy = s.cutBy; cutSelf = s.cutSelf
        arpMode = s.arpMode.clamped(0, 5)
        arpStepBeats = SamplerSettings.step(s.arpTime).1
        arpGate = 0.05 + 0.95 * s.arpGate.clamped(0, 1)
        arpRange = s.arpRange.clamped(1, 4)
        arpRepeat = s.arpRepeat.clamped(1, 8)
        arpSlide = s.arpSlide
        let chord = SamplerSettings.chords[s.arpChord.clamped(0, SamplerSettings.chords.count - 1)].1
        arpNotes = min(4, chord.count)
        arpAuto = s.arpChord == 0
        arpChord = (chord[0], chord.count > 1 ? chord[1] : 0, chord.count > 2 ? chord[2] : 0, chord.count > 3 ? chord[3] : 0)
        echoFeed = s.echoFeed.clamped(0, 1)
        echoPan = s.echoPan.clamped(-1, 1); echoX = s.echoX.clamped(-1, 1); echoY = s.echoY.clamped(-1, 1)
        echoPitch = s.echoPitch.clamped(-1, 1)
        echoBeats = SamplerSettings.step(s.echoTime).1
        echoes = echoFeed > 0.001 ? s.echoes.clamped(0, 16) : 0
        echoPingPong = s.echoPingPong
        fatMode = s.fatMode
    }

    /// One of the chord's notes (semitones).
    /// The drawn region in frames of a sound `length` long.
    func region(length: Int) -> ClosedRange<Int> {
        let last = max(1, length - 2)
        let a = Int(Float(last) * userRegion.0), b = max(a + 1, Int(Float(last) * userRegion.1))
        return a...min(last, b)
    }

    func chordNote(_ i: Int) -> Int {
        switch i % max(1, arpNotes) { case 1: return arpChord.1; case 2: return arpChord.2; case 3: return arpChord.3; default: return arpChord.0 }
    }

    /// Realtime mode: how much longer the sound plays (1 = as it is).
    func realtimeFactor(sourceSeconds: Double, bpm: Double) -> Double {
        (rtTime.factor(sourceSeconds: sourceSeconds, bpm: bpm) * rtMul).clamped(0.1, 10)
    }

    /// Resample mode's playback speed for a sample this long at this tempo.
    func tapeRate(sourceSeconds: Double, bpm: Double) -> Double {
        let f = tapeTime.factor(sourceSeconds: sourceSeconds, bpm: bpm) * tapeMul
        return pow(2, Double(tapePitch) / 12) / max(0.05, f)
    }
}

/// One envelope as it runs: delay, attack, hold, decay, sustain, release.
struct SamplerEnvRun {
    var stage = 7          // 0 delay … 5 release, 6 done, 7 off
    var pos = 0
    var lenDelay = 0, lenAttack = 0, lenHold = 0, lenDecay = 0, lenRelease = 0
    var sustain: Float = 1
    var curveA: Float = 1, curveD: Float = 1, curveR: Float = 1
    var from: Float = 0
    var value: Float = 0
    var amount: Float = 0
    // the graph's own points (FL style), when the envelope has them
    var usePoints = false
    var table = SamplerEnvPoints()
    var seg = 0, segLen = 0
    var unit: Float = 48_000
    var released = false

    init() {}

    init(_ e: SamplerEnvelope, points: SamplerEnvPoints, sampleRate: Double, samplesPerBeat: Double) {
        guard e.on else { return }
        let unit = e.tempo ? samplesPerBeat : sampleRate
        amount = e.amount.clamped(-1, 1)
        if points.count > 0 {
            usePoints = true
            table = points
            self.unit = Float(unit)
            stage = 0
            seg = 0
            from = 0
            segLen = Int(table.time(0) * self.unit)
            return
        }
        func len(_ v: Float) -> Int { Int(SamplerEnvelope.units(v, tempo: e.tempo) * unit) }
        stage = 0
        lenDelay = len(e.delay); lenAttack = len(e.attack); lenHold = len(e.hold); lenDecay = len(e.decay)
        // REL at 0 still fades over 3 ms, so the note's end doesn't click
        lenRelease = max(len(e.release), Int(sampleRate * 0.003))
        sustain = e.sustain.clamped(0, 1)
        curveA = powf(4, e.attackTension.clamped(-1, 1))
        curveD = powf(4, e.decayTension.clamped(-1, 1))
        curveR = powf(4, e.releaseTension.clamped(-1, 1))
        amount = e.amount.clamped(-1, 1)
    }

    var on: Bool { stage != 7 }
    var done: Bool { stage == 6 }

    mutating func release() {
        if usePoints {
            guard stage < 6, !released else { return }
            released = true
            // jump past the sustain point from wherever it is now
            if table.sustain >= 0 && seg <= table.sustain + 1 {
                seg = table.sustain + 1; pos = 0; from = value
                segLen = seg < table.count ? Int(table.time(seg) * unit) : 0
            }
            return
        }
        guard stage < 5 else { return }
        from = value; stage = 5; pos = 0
        if lenRelease == 0 { stage = 6; value = 0 }
    }

    /// Moves `n` samples on and returns the level (0…1).
    @inline(__always)
    mutating func advance(_ n: Int) -> Float {
        guard stage < 6 else { return stage == 6 ? 0 : 1 }
        if usePoints { return advancePoints(n) }
        pos += n
        while true {
            switch stage {
            case 0:
                if pos >= lenDelay { pos -= lenDelay; stage = 1; continue }
                value = 0
            case 1:
                if pos >= lenAttack { pos -= lenAttack; stage = 2; continue }
                value = powf(Float(pos) / Float(lenAttack), curveA)
            case 2:
                if pos >= lenHold { pos -= lenHold; stage = 3; continue }
                value = 1
            case 3:
                if pos >= lenDecay { pos -= lenDecay; stage = 4; continue }
                value = 1 - (1 - sustain) * powf(Float(pos) / Float(lenDecay), curveD)
            case 4:
                pos = 0
                value = sustain
            case 5:
                if pos >= lenRelease { stage = 6; value = 0; break }
                value = from * (1 - powf(Float(pos) / Float(lenRelease), curveR))
            default:
                value = 0
            }
            break
        }
        return value
    }

    /// The graph's points: each segment runs from the level before to its point's level, bent by its
    /// tension; it waits on the sustain point while the note is held, and ends after the last point.
    @inline(__always)
    private mutating func advancePoints(_ n: Int) -> Float {
        pos += n
        while true {
            if seg >= table.count {
                value = table.count > 0 ? table.level(table.count - 1) : 0
                if value < 0.0001 { stage = 6; value = 0 }
                pos = 0
                break
            }
            // holding on the sustain point until the note lets go
            if !released && seg == table.sustain + 1 && table.sustain >= 0 {
                value = table.level(table.sustain)
                pos = 0
                break
            }
            if pos >= segLen {
                pos -= segLen
                from = table.level(seg)
                seg += 1
                segLen = seg < table.count ? Int(table.time(seg) * unit) : 0
                continue
            }
            value = from + (table.level(seg) - from) * powf(Float(pos) / Float(max(1, segLen)), table.curve(seg))
            break
        }
        return value
    }
}

/// One LFO as it runs.
struct SamplerLfoRun {
    var on = false
    var shape = 0
    var delay = 0, attack = 0
    var amount: Float = 0
    var increment: Double = 0      // cycles per sample
    var phase: Double = 0

    init() {}

    init(_ l: SamplerLFO, sampleRate: Double, samplesPerBeat: Double, clock: Int64) {
        guard abs(l.amount) > 0.001 else { return }
        on = true
        shape = l.shape
        amount = l.amount.clamped(-1, 1)
        let unit = l.tempo ? samplesPerBeat : sampleRate
        delay = Int(SamplerEnvelope.units(l.delay, tempo: l.tempo) * unit * 0.5)
        attack = Int(SamplerEnvelope.units(l.attack, tempo: l.tempo) * unit * 0.5)
        increment = l.tempo ? 1 / (l.division.1 * max(1, samplesPerBeat)) : l.hertz / max(1, sampleRate)
        if l.global { phase = (Double(clock) * increment).truncatingRemainder(dividingBy: 1) }
    }

    /// −amount…amount after `n` more samples (`age` = samples since the hit).
    @inline(__always)
    mutating func advance(_ n: Int, age: Int) -> Float {
        guard on else { return 0 }
        phase += increment * Double(n)
        phase -= phase.rounded(.down)
        let ramp: Float = age < delay ? 0 : (attack <= 0 ? 1 : min(1, Float(age - delay) / Float(attack)))
        let p = Float(phase)
        let v: Float
        switch shape {
        case 1: v = 1 - 4 * abs(p - 0.5)
        case 2: v = p < 0.5 ? 1 : -1
        default: v = sinf(2 * .pi * p)
        }
        return v * ramp * amount
    }
}

/// The sampler part of a sounding voice: envelopes, LFOs and the filter, worked out every 16 samples.
struct SamplerVoice {
    var on = false
    var age = 0
    var env = (SamplerEnvRun(), SamplerEnvRun(), SamplerEnvRun(), SamplerEnvRun(), SamplerEnvRun())   // pan, vol, x, y, pitch
    var lfo = (SamplerLfoRun(), SamplerLfoRun(), SamplerLfoRun(), SamplerLfoRun(), SamplerLfoRun())
    var cutoff: Float = 1, resonance: Float = 0
    var filterType = SamplerFilterType.fastLP
    var filterOn = false
    // this block's results
    var gain: Float = 1
    /// The Volume envelope releases when the note ends (otherwise it stays at its sustain).
    var volumeGates = false
    var panL: Float = 1, panR: Float = 1
    var rateMul: Double = 1
    var done = false
    /// How the filter runs this block: 0 one-pole, 1 biquad, 2 state-variable.
    var filterMode = 0
    // the one-pole coefficient, the SVF's (two stages for the x2 types) and the biquad's
    var c1: Float = 1, a1: Float = 0, a2: Float = 0, a3: Float = 0, k: Float = 2
    var s1L: Float = 0, s2L: Float = 0, s1R: Float = 0, s2R: Float = 0
    var t1L: Float = 0, t2L: Float = 0, t1R: Float = 0, t2R: Float = 0
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, q1: Float = 0, q2: Float = 0
    var sampleRate: Float = 48_000
    // looping
    var looping = false
    var pingPong = false
    var direction: Double = 1
    var loopStart: Double = 0, loopEnd: Double = 0
    // Realtime stretching: the voice's position moves on at `timeStep` (the length) while two
    // overlapping grains read the sound from there at the note's speed × `grainPitch` (the pitch).
    var grains = false
    var timeStep: Double = 1
    var grainPitch: Double = 1
    var grainA: Double = 0, grainB: Double = 0
    var grainAge = 0, grainHalf = 1_680
    /// A region drawn on the waveform plays to here, then fades out (0 = the sound's end).
    var regionEnd: Double = 0

    init() {}

    /// This note's own pan, MOD X and MOD Y on top of the track's (key and velocity tracking, echoes).
    var panOffset: Float = 0, xOffset: Float = 0, yOffset: Float = 0
    /// GATE cut this note short: it releases when the gate closes even with the envelope off.
    var gateCut = false

    init(_ rt: SamplerRT, sampleRate rate: Double, samplesPerBeat: Double, clock: Int64,
         panOffset: Float = 0, xOffset: Float = 0, yOffset: Float = 0) {
        on = true
        self.panOffset = panOffset
        self.xOffset = xOffset
        self.yOffset = yOffset
        sampleRate = Float(rate)
        env = (SamplerEnvRun(rt.pan, points: rt.points.0, sampleRate: rate, samplesPerBeat: samplesPerBeat),
               SamplerEnvRun(rt.volume, points: rt.points.1, sampleRate: rate, samplesPerBeat: samplesPerBeat),
               SamplerEnvRun(rt.modX, points: rt.points.2, sampleRate: rate, samplesPerBeat: samplesPerBeat),
               SamplerEnvRun(rt.modY, points: rt.points.3, sampleRate: rate, samplesPerBeat: samplesPerBeat),
               SamplerEnvRun(rt.pitch, points: rt.points.4, sampleRate: rate, samplesPerBeat: samplesPerBeat))
        lfo = (SamplerLfoRun(rt.lfoPan, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock),
               SamplerLfoRun(rt.lfoVolume, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock),
               SamplerLfoRun(rt.lfoX, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock),
               SamplerLfoRun(rt.lfoY, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock),
               SamplerLfoRun(rt.lfoPitch, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock))
        cutoff = rt.cutoff
        resonance = rt.resonance
        filterType = rt.filterType
        // Fast LP fully open with no resonance is bypassed (the default)
        filterOn = filterType != .fastLP || cutoff + xOffset < 0.999 || resonance + yOffset > 0.001 || env.2.on || env.3.on || lfo.2.on || lfo.3.on
        volumeGates = rt.volumeGates
        gain = env.1.on ? 0 : 1
        control(0)
        gain = env.1.on ? env.1.value : gain
    }

    /// The note ended: every envelope lets go.
    mutating func release() {
        env.0.release(); env.2.release(); env.3.release(); env.4.release()
        if volumeGates { env.1.release() }
    }

    /// Works out the next `n` samples' gain, pan, pitch and filter.
    @inline(__always)
    mutating func control(_ n: Int) {
        age += n
        var g: Float = 1
        if env.1.on {
            g = env.1.advance(n)
            if env.1.done { done = true }
        }
        if lfo.1.on {
            let a = abs(lfo.1.amount)
            // advance() already carries AMT's sign: turned left, the LFO dips where it would peak
            g *= (1 - 0.5 * a) + 0.5 * lfo.1.advance(n, age: age)
        }
        gain = max(0, g)

        var p: Float = panOffset
        if env.0.on { p += env.0.advance(n) * env.0.amount }
        if lfo.0.on { p += lfo.0.advance(n, age: age) }
        if p != 0 {
            let th = (p.clamped(-1, 1) + 1) * .pi / 4
            panL = cosf(th) * 1.414_2; panR = sinf(th) * 1.414_2
        } else {
            panL = 1; panR = 1
        }

        var semis: Float = 0
        if env.4.on { semis += env.4.advance(n) * env.4.amount * 12 }
        if lfo.4.on { semis += lfo.4.advance(n, age: age) * 12 }
        rateMul = semis == 0 ? 1 : Double(exp2f(semis / 12))

        guard filterOn else { return }
        var x = (cutoff + xOffset).clamped(0, 1), y = resonance + yOffset
        if env.2.on {
            // the envelope opens the filter up to MOD X (or, turned left, closes it from there), so it's
            // heard even with the filter wide open
            let v = env.2.advance(n), a = env.2.amount
            x *= a >= 0 ? 1 - a * (1 - v) : 1 + a * v
        }
        if lfo.2.on { x += lfo.2.advance(n, age: age) }
        if env.3.on { y += env.3.advance(n) * env.3.amount }
        if lfo.3.on { y += lfo.3.advance(n, age: age) }
        x = x.clamped(0, 1); y = y.clamped(0, 1)
        let hz = min(20 * powf(1000, x), sampleRate * 0.45)
        switch filterType {
        case .fastLP where y <= 0.001:
            filterMode = 0
            c1 = x >= 0.999 ? 1 : 1 - expf(-2 * .pi * hz / sampleRate)
        case .lp, .lp2:
            // RBJ low-pass, its Q from MOD Y (a gentler peak for two in a row)
            filterMode = 1
            let q = 0.707 + y * (filterType == .lp2 ? 5 : 11)
            let w = 2 * Float.pi * hz / sampleRate
            let cw = cosf(w), alpha = sinf(w) / (2 * q)
            let a0 = 1 + alpha
            b0 = (1 - cw) / 2 / a0; b1 = (1 - cw) / a0; b2 = b0
            q1 = -2 * cw / a0; q2 = (1 - alpha) / a0
        default:
            filterMode = 2
            let gg = tanf(.pi * hz / sampleRate)
            k = 2 - 1.96 * y
            a1 = 1 / (1 + gg * (gg + k)); a2 = gg * a1; a3 = gg * a2
        }
    }

    /// The filter on one stereo sample.
    @inline(__always)
    mutating func filter(_ l: inout Float, _ r: inout Float) {
        guard filterOn else { return }
        switch filterMode {
        case 0:
            guard c1 < 1 else { return }
            s1L += c1 * (l - s1L); s1R += c1 * (r - s1R)
            l = s1L; r = s1R
        case 1:
            // transposed direct form II; the x2 type runs a second one on the SVF's spare state
            let x = l, z = r
            l = b0 * x + s1L; s1L = b1 * x - q1 * l + s2L; s2L = b2 * x - q2 * l
            r = b0 * z + s1R; s1R = b1 * z - q1 * r + s2R; s2R = b2 * z - q2 * r
            if filterType == .lp2 {
                let x2 = l, z2 = r
                l = b0 * x2 + t1L; t1L = b1 * x2 - q1 * l + t2L; t2L = b2 * x2 - q2 * l
                r = b0 * z2 + t1R; t1R = b1 * z2 - q1 * r + t2R; t2R = b2 * z2 - q2 * r
            }
        default:
            let type = filterType, f1 = a1, f2 = a2, f3 = a3, kk = k
            l = Self.svf(l, &s1L, &s2L, type, f1, f2, f3, kk)
            r = Self.svf(r, &s1R, &s2R, type, f1, f2, f3, kk)
            if type == .svfLP2 {
                l = Self.svf(l, &t1L, &t2L, .svfLP, f1, f2, f3, kk)
                r = Self.svf(r, &t1R, &t2R, .svfLP, f1, f2, f3, kk)
            }
        }
    }

    /// One step of a state-variable filter (Zavalishin's trapezoidal form).
    @inline(__always)
    private static func svf(_ x: Float, _ ic1: inout Float, _ ic2: inout Float, _ type: SamplerFilterType,
                            _ a1: Float, _ a2: Float, _ a3: Float, _ k: Float) -> Float {
        let v3 = x - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        switch type {
        case .bp: return v1
        case .hp: return x - k * v1 - v2
        case .bs: return x - k * v1
        default: return v2
        }
    }
}

// MARK: - Editing the waveform (Tyrone, Oct 18: red selection handles, cut / copy / paste, delete,
// trim silence, fades)
//
// Edits work on the sound the track plays now and are saved as a new WAV in Samples/Edits, which
// the track then loads (the old file stays, so the window's UNDO can go back to it).

enum SampleEdit {
    case delete(Range<Int>)
    /// Puts `clip` in at `at` (insert) or over `over` (replace).
    case insert(SampleClip, at: Int)
    case replace(SampleClip, over: Range<Int>)
    case trimSilence
    case fadeIn(Range<Int>)
    case fadeOut(Range<Int>)
}

/// Copied audio (any track can paste it).
struct SampleClip {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    var count: Int { left.count }
}

enum SampleEditor {
    static func clip(_ s: SampleBuffer, _ range: Range<Int>) -> SampleClip {
        let r = range.clamped(to: 0..<s.length)
        return SampleClip(left: Array(UnsafeBufferPointer(start: s.left + r.lowerBound, count: r.count)),
                          right: Array(UnsafeBufferPointer(start: s.right + r.lowerBound, count: r.count)), sampleRate: s.sampleRate)
    }

    /// The clip at `rate` (smooth cubic if it came from a sound at another rate).
    static func converted(_ c: SampleClip, to rate: Double) -> SampleClip {
        guard rate > 0, abs(c.sampleRate - rate) > 0.5 else { return c }
        let step = c.sampleRate / rate
        return SampleClip(left: SamplerProcessor.convert(c.left, step: step), right: SamplerProcessor.convert(c.right, step: step), sampleRate: rate)
    }

    /// The edited audio, and where a point of the old sound (0…1) lands in the new one (nil = cut out).
    static func apply(_ edit: SampleEdit, to s: SampleBuffer) -> (left: [Float], right: [Float], map: (Float) -> Float?) {
        var l = Array(UnsafeBufferPointer(start: s.left, count: s.length))
        var r = Array(UnsafeBufferPointer(start: s.right, count: s.length))
        let n = max(1, l.count)
        func clampRange(_ x: Range<Int>) -> Range<Int> { x.clamped(to: 0..<l.count) }
        /// A part of the old sound to the new: `cut` frames removed at `at`, `added` put in there.
        func mapper(at: Int, cut: Int, added: Int) -> (Float) -> Float? {
            let newCount = Float(max(1, n - cut + added))
            return { f in
                let i = Int((f * Float(n)).rounded())
                if i < at { return Float(i) / newCount }
                if i < at + cut { return cut > 0 && i > at ? nil : Float(at) / newCount }
                return (Float(i - cut + added) / newCount).clamped(0, 1)
            }
        }
        switch edit {
        case .delete(let range):
            let x = clampRange(range)
            guard !x.isEmpty, x.count < l.count else { return (l, r, { $0 }) }
            l.removeSubrange(x); r.removeSubrange(x)
            return (l, r, mapper(at: x.lowerBound, cut: x.count, added: 0))
        case .insert(let c, let at):
            let c = converted(c, to: s.sampleRate)
            let p = min(max(0, at), l.count)
            l.insert(contentsOf: c.left, at: p); r.insert(contentsOf: c.right, at: p)
            return (l, r, mapper(at: p, cut: 0, added: c.count))
        case .replace(let c, let over):
            let c = converted(c, to: s.sampleRate)
            let x = clampRange(over)
            l.replaceSubrange(x, with: c.left); r.replaceSubrange(x, with: c.right)
            return (l, r, mapper(at: x.lowerBound, cut: x.count, added: c.count))
        case .trimSilence:
            // quieter than 60 dB under the peak, at either end (a hair is kept before the first sound)
            var peak: Float = 0
            for i in l.indices { peak = max(peak, abs(l[i]), abs(r[i])) }
            let floor = max(peak * 0.001, 0.000_01)
            guard let first = l.indices.first(where: { abs(l[$0]) > floor || abs(r[$0]) > floor }),
                  let last = l.indices.last(where: { abs(l[$0]) > floor || abs(r[$0]) > floor }) else { return (l, r, { $0 }) }
            let a = max(0, first - Int(s.sampleRate * 0.002))
            let b = min(l.count, last + 1)
            guard a > 0 || b < l.count else { return (l, r, { $0 }) }
            let kept = b - a
            return (Array(l[a..<b]), Array(r[a..<b]), { f in
                let i = Int((f * Float(n)).rounded())
                return i < a || i > b ? nil : Float(i - a) / Float(max(1, kept))
            })
        case .fadeIn(let range), .fadeOut(let range):
            let x = clampRange(range)
            let rising: Bool
            if case .fadeIn = edit { rising = true } else { rising = false }
            let count = max(1, x.count)
            for (k, i) in x.enumerated() {
                let t = Float(k) / Float(count)
                let w = 0.5 - 0.5 * cosf(.pi * t)
                let g = rising ? w : 1 - w
                l[i] *= g; r[i] *= g
            }
            return (l, r, { $0 })
        }
    }
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
