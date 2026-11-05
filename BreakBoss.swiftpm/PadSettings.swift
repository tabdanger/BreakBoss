// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Per-pad settings (pad editor)

/// A sound for the library's preview: its buffer and how loud (the preview volume).
final class PreviewSound {
    let sample: SampleBuffer
    let gain: Float
    init(_ sample: SampleBuffer, gain: Float) { self.sample = sample; self.gain = gain }
}

struct PadSettings: Codable, Equatable {
    /// 0...maxLevel, 0.8 = unity (100%), the top (Tyrone, Oct 19: only the SAMPLER's VOL goes past 100%).
    var level: Float = 0.8
    /// -1 (left) ... 1 (right)
    var pan: Float = 0
    /// Semitones, -24 ... +24.
    var tune: Float = 0
    /// 0.05 ... 1 (1 = the sound's own length).
    var decay: Float = 1
    /// 0...1 logarithmic low-pass cutoff; 1 bypasses the per-pad filter.
    var filter: Float = 1
    var reverse = false
    /// File name in the Samples folder when the pad holds your own sample.
    var sampleFile: String?
    /// The track's SAMPLER window (nil until it's opened and something is changed).
    var sampler: SamplerSettings?
    /// The track's own FX knobs on Face 2 (Tyrone, Oct 19), each mode's separately, keyed
    /// "<mode>.<param>" (TrackFX.key). Nil until a knob is turned: a track starts untouched.
    var fx: [String: Float]?
    /// NOTE REPEAT (Tyrone, Oct 26): while the pad is held it plays again every `repeatDivision`
    /// (NoteRepeat), on the engine's beat. Off until it's turned on.
    var noteRepeat = false
    /// NoteRepeat.names index: 1/4, 1/8, 1/8T, 1/16, 1/16T, 1/32, 1/32T, 1/64.
    var repeatDivision = NoteRepeat.defaultDivision

    private enum CodingKeys: String, CodingKey {
        case level, pan, tune, decay, filter, reverse, sampleFile, sampler, fx, noteRepeat, repeatDivision
    }

    var gain: Float { level <= 0.001 ? 0 : KnockMath.dbToGain(40 * log10f(level / 0.8)) }

    /// A track's volume goes down to 50%, −12 dB (Oct 19), and up to 100%, unity: past 100% (to
    /// 200%) only in the track's SAMPLER window (its VOL knob), Tyrone, Oct 19. It went to 200% on Oct 18.
    static let maxLevel: Float = 0.8
    static let minLevel: Float = 0.4
    /// The volume knobs turn evenly in dB: 0 = −12 dB (50%), the top 0 dB (100%).
    static func knob(level: Float) -> Float { (log2f(max(level, 0.000_1) / 0.8) + 1).clamped(0, 1) }
    static func level(knob v: Float) -> Float { 0.8 * powf(2, v.clamped(0, 1) - 1) }
    /// What a volume control shows: 100% at unity.
    static func levelText(_ level: Float) -> String { String(format: "%.0f%%", level / 0.8 * 100) }
}

extension PadSettings {
    /// Older presets have no per-pad filter, so their original tone remains open.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        level = try values.decodeIfPresent(Float.self, forKey: .level) ?? 0.8
        pan = try values.decodeIfPresent(Float.self, forKey: .pan) ?? 0
        tune = try values.decodeIfPresent(Float.self, forKey: .tune) ?? 0
        decay = try values.decodeIfPresent(Float.self, forKey: .decay) ?? 1
        filter = try values.decodeIfPresent(Float.self, forKey: .filter) ?? 1
        reverse = try values.decodeIfPresent(Bool.self, forKey: .reverse) ?? false
        sampleFile = try values.decodeIfPresent(String.self, forKey: .sampleFile)
        sampler = try? values.decodeIfPresent(SamplerSettings.self, forKey: .sampler)
        fx = try? values.decodeIfPresent([String: Float].self, forKey: .fx)
        // saved before NOTE REPEAT: off, 1/16
        noteRepeat = (try? values.decodeIfPresent(Bool.self, forKey: .noteRepeat)) ?? false
        repeatDivision = NoteRepeat.clamped((try? values.decodeIfPresent(Int.self, forKey: .repeatDivision)) ?? NoteRepeat.defaultDivision)
    }

    /// A new sound on the pad comes in as itself, but how the pad is played (NOTE REPEAT) stays.
    func freshSound() -> PadSettings {
        var s = PadSettings()
        s.noteRepeat = noteRepeat
        s.repeatDivision = repeatDivision
        return s
    }

    /// This track's own value of an FX knob in a mode (its neutral value until it's turned).
    func fxValue(_ p: KParam, _ mode: SoundMode) -> Float { fx?[TrackFX.key(p, mode)] ?? TrackFX.neutral(p) }

    mutating func setFX(_ p: KParam, _ mode: SoundMode, _ value: Float) {
        let v = value.isFinite ? value.clamped(0, 1) : TrackFX.neutral(p)
        var table = fx ?? [:]
        table[TrackFX.key(p, mode)] = abs(v - TrackFX.neutral(p)) < 0.000_1 ? nil : v
        fx = table.isEmpty ? nil : table
    }
}

/// NOTE REPEAT's divisions (the PAD tab's REPEAT DIVISION knob). T = triplet.
enum NoteRepeat {
    static let names = ["1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T", "1/64"]
    static let count = 8
    /// 1/16.
    static let defaultDivision = 3

    static func clamped(_ index: Int) -> Int { min(max(index, 0), count - 1) }
    static func name(_ index: Int) -> String { names[clamped(index)] }

    /// How many beats (quarter notes) apart the repeats are. A switch, not a table, so the audio
    /// thread never touches a lazily made array.
    @inline(__always)
    static func beats(_ index: Int) -> Double {
        switch index {
        case 0: return 1
        case 1: return 0.5
        case 2: return 1.0 / 3
        case 4: return 1.0 / 6
        case 5: return 0.125
        case 6: return 1.0 / 12
        case 7: return 0.0625
        default: return 0.25
        }
    }
}

/// Each mode's FX section: the seven knobs on Face 1's bottom row and on Face 2's bottom rail, per
/// track (Tyrone, Oct 19). They morph with the mode:
/// MODERN   clean analog punch: BOOST, PUNCH, ANALOG EQ, TIGHTEN, GRIT, SHINE, NOISE
/// VINTAGE  (Tyrone, Oct 24) DRIVE, PUNCH, ANALOG EQ, GRIT, SHINE, TIGHTEN, NOISE: DRIVE takes BOOST's
///          place, so every hit runs hotter and rounder (BOOST's push plus tape saturation)
/// TEXTURE  (Tyrone, Oct 24) DRIVE, RESAMPLE, INSTABILITY, DELAY, SHINE, REVERB, NOISE:
///          INSTABILITY also drives the warp and the stutters (as before Oct 17); REVERB (GATED
///          REVERB until Oct 28, now a bright drum plate; KParam.gatedReverb keeps its id for saved
///          states and hosts) has its DECAY and PRE-DELAY at their middle / zero.
///          Dry at 0%: nothing in Texture plays until its knob is turned up (Oct 28)
/// Only a mode's own knobs reach its sound (BusProcessor.Settings.keepSection), so every label
/// matches what you hear. With a track selected they turn that track's own insert (BusProcessor,
/// `insert`); Face 1's knobs (and Face 2 with no track) stay the main chain's.
enum TrackFX {
    static func params(_ mode: SoundMode) -> [KParam] {
        switch mode {
        case .modern: return [.boost, .punch, .analogEQ, .tighten, .grit, .shine, .noise]
        case .vintage: return [.drive, .punch, .analogEQ, .grit, .shine, .tighten, .noise]
        case .texture: return [.drive, .resample, .instability, .textureDelay, .shine, .gatedReverb, .noise]
        }
    }

    /// The knob a Face 1 bottom-row place turns in a mode. The places are named by Modern's art
    /// (BOOST, PUNCH, ANALOG EQ, GRIT, SHINE, TIGHTEN, NOISE); Vintage and Texture print their own
    /// section there, in order.
    static func face1(_ place: KParam, _ mode: SoundMode) -> KParam {
        guard mode != .modern, let i = face1Places.firstIndex(of: place) else { return place }
        return params(mode)[i]
    }
    static let face1Places: [KParam] = [.boost, .punch, .analogEQ, .grit, .shine, .tighten, .noise]

    static func key(_ p: KParam, _ mode: SoundMode) -> String { "\(mode.assetSuffix).\(p.id)" }

    /// Where a track's knob starts: nothing added. DECAY sits in the middle (it only shapes the
    /// track's REVERB, which starts at zero).
    static func neutral(_ p: KParam) -> Float { p == .reverbDecay ? 0.5 : 0 }

    /// A track's insert in one mode, as the audio thread plays it.
    struct Insert {
        var settings = BusProcessor.Settings()
        /// Something on the insert adds to the sound (it runs only then).
        var active = false
        /// The track's own TIGHTEN (done per voice, like the main one).
        var tighten: Float = 0
    }

    static func insert(_ pad: PadSettings, _ mode: SoundMode) -> Insert {
        var r = Insert()
        r.settings.mode = mode
        r.settings.insert = true
        guard pad.fx != nil else { return r }
        func v(_ p: KParam) -> Float { pad.fxValue(p, mode) }
        var s = r.settings
        switch mode {
        case .modern, .vintage:
            if mode == .modern { s.boost = v(.boost) } else { s.drive = v(.drive) }
            s.punch = v(.punch); s.analogEQ = v(.analogEQ); s.grit = v(.grit); s.shine = v(.shine); s.noise = v(.noise)
            r.tighten = v(.tighten)
            s.resample = 0; s.instability = 0; s.delay = 0; s.reverb = 0; s.warp = 0; s.glitch = 0
        case .texture:
            s.drive = v(.drive); s.resample = v(.resample); s.instability = v(.instability); s.delay = v(.textureDelay)
            s.shine = v(.shine); s.reverb = v(.gatedReverb); s.noise = v(.noise)
        }
        s.keepSection()
        r.settings = s
        r.active = max(s.boost, s.drive, s.punch, s.analogEQ, s.grit, s.shine, s.noise,
                       s.resample, s.instability, s.delay, s.reverb, s.warp, s.glitch) > 0.001
        return r
    }
}
