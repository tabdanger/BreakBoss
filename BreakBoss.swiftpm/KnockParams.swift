// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Modes

/// The three faceplates. Each one is its own sound: Modern is clean and forward, Vintage adds
/// drive and boost (tape and old-sampler warmth), Texture adds a downsampled, unstable sound
/// with a tempo-synced delay and a plate reverb, each only as its knob is turned up.
enum SoundMode: Int, CaseIterable, Codable {
    case modern = 0, vintage = 1, texture = 2

    var title: String {
        switch self {
        case .modern: return "MODERN"
        case .vintage: return "VINTAGE"
        case .texture: return "TEXTURE"
        }
    }

    /// Asset name suffix of this faceplate's images.
    var assetSuffix: String {
        switch self {
        case .modern: return "modern"
        case .vintage: return "vintage"
        case .texture: return "texture"
        }
    }
}

/// ONE-SHOT: all 12 pads play single drum sounds. LOOP: they start tempo-synced grooves.
enum PlayMode: Int, CaseIterable, Codable {
    case oneShot = 0, loop = 1
}

// MARK: - Parameters

/// Every control the host can see and automate. The raw value is the parameter's address in
/// the engine's parameter array and in the AUv3 parameter tree, so never reorder these.
enum KParam: Int, CaseIterable {
    // Top panel
    case pitch = 0, tune, bounce, velocity, filter, clipDrive, output, clipper
    // Bottom row
    case boost, punch, analogEQ, grit, shine, tighten, noise
    // Switches
    case soundMode, playMode, tempoSync, followDAW

    // Append-only addresses keep existing preset / host parameter IDs stable.
    case resample, instability, textureDelay, gatedReverb, drive
    // Oct 17: Face 2's Texture knobs (WARP and GLITCH used to follow INSTABILITY).
    case warp, glitch, reverbDecay, reverbPredelay, delaySync

    static let count = KParam.allCases.count

    /// Identifier for the host and for saved state.
    var id: String {
        switch self {
        case .pitch: return "pitch"
        case .tune: return "tune"
        case .bounce: return "bounce"
        case .velocity: return "velocity"
        case .filter: return "filter"
        case .clipDrive: return "clipDrive"
        case .output: return "output"
        case .clipper: return "clipper"
        case .boost: return "boost"
        case .punch: return "punch"
        case .analogEQ: return "analogEQ"
        case .grit: return "grit"
        case .shine: return "shine"
        case .tighten: return "tighten"
        case .noise: return "noise"
        case .soundMode: return "mode"
        case .playMode: return "playMode"
        case .tempoSync: return "tempoSync"
        case .followDAW: return "followDAW"
        case .resample: return "resample"
        case .instability: return "instability"
        case .textureDelay: return "textureDelay"
        case .gatedReverb: return "gatedReverb"
        case .drive: return "drive"
        case .warp: return "warp"
        case .glitch: return "glitch"
        case .reverbDecay: return "reverbDecay"
        case .reverbPredelay: return "reverbPredelay"
        case .delaySync: return "delaySync"
        }
    }

    var name: String {
        switch self {
        case .pitch: return "Pitch"
        case .tune: return "Tune"
        case .bounce: return "Bounce"
        case .velocity: return "Velocity"
        case .filter: return "Filter"
        case .clipDrive: return "Clip Drive"
        case .output: return "Output"
        case .clipper: return "Clipper"
        case .boost: return "Boost"
        case .punch: return "Punch"
        case .analogEQ: return "Analog EQ"
        case .grit: return "Grit"
        case .shine: return "Shine"
        case .tighten: return "Tighten"
        case .noise: return "Noise"
        case .soundMode: return "Mode"
        case .playMode: return "One-Shot / Loop"
        case .tempoSync: return "Tempo Sync"
        case .followDAW: return "Follow DAW"
        case .resample: return "Resample"
        case .instability: return "Instability"
        case .textureDelay: return "Delay"
        case .gatedReverb: return "Reverb"
        case .drive: return "Drive"
        case .warp: return "Warp"
        case .glitch: return "Glitch"
        case .reverbDecay: return "Reverb Decay"
        case .reverbPredelay: return "Reverb Pre-Delay"
        case .delaySync: return "Delay Sync"
        }
    }

    /// Knobs are 0...1. Switches hold whole numbers.
    var isKnob: Bool { (rawValue <= KParam.noise.rawValue && self != .clipper) || (rawValue >= KParam.resample.rawValue && self != .delaySync) }

    /// Number of positions for switches (nil for knobs).
    var steps: Int? {
        switch self {
        case .clipper, .tempoSync, .followDAW, .playMode, .delaySync: return 2
        case .soundMode: return 3
        default: return nil
        }
    }

    /// INIT values. Pitch and Tune start centred (nothing detuned). Every FX knob, CLIP DRIVE
    /// included, starts at 0% (Tyrone, Oct 26): they're the extra sauce and only touch the sound
    /// once they're turned up. Every mode is dry with them at zero (Texture too, Oct 28).
    var defaultValue: Float {
        switch self {
        case .pitch: return 0.5
        case .tune: return 0.5
        case .bounce: return 0.0
        case .velocity: return 0.75
        case .filter: return 1.0
        case .clipDrive: return 0
        case .output: return 1
        case .clipper: return 1
        case .boost: return 0
        case .punch: return 0.0
        case .analogEQ: return 0.0
        case .grit: return 0.0
        case .shine: return 0.0
        case .tighten: return 0.0
        case .noise: return 0.0
        case .soundMode: return 0
        case .playMode: return 1
        case .tempoSync: return 1
        case .followDAW: return 1
        case .resample: return 0
        case .instability: return 0
        case .textureDelay: return 0
        case .gatedReverb: return 0
        case .drive: return 0
        case .warp: return 0
        case .glitch: return 0
        case .reverbDecay: return 0.5
        case .reverbPredelay: return 0
        case .delaySync: return 1
        }
    }

    /// What the value means, for the readout on the screen and the host: exactly what the DSP
    /// plays (Tyrone, Nov 14). FX knobs show their position, which is that share of the knob's full
    /// effect (KnobTaper); the others their real unit. `c`: the mode (and main chain or a track's
    /// insert) the value plays in, since an FX knob's taper can differ between them.
    func text(_ value: Float, _ c: KnobContext) -> String {
        switch self {
        case .pitch:
            // the engine rounds to the nearest semitone (KnockEngine: globalSemis)
            let st = KnockMath.pitchSemitones(value)
            return st == 0 ? "0 st" : String(format: "%+d st", st)
        case .tune:
            return String(format: "%+d ct", Int(KnockMath.tuneCents(value).rounded()))
        case .bounce:
            return value < 0.01 ? "STRAIGHT" : String(format: "%d%% SWING", Int(KnockMath.swingPercent(value).rounded()))
        case .velocity:
            return value < 0.01 ? "FIXED" : String(format: "%d%%", Int((value * 100).rounded()))
        case .filter:
            if value > 0.995 { return "OPEN" }
            return String(format: "%.0f Hz", KnockMath.filterCutoff(value))
        case .clipDrive:
            return String(format: "+%.1f dB", KnockMath.clipDriveDB(value))
        case .output:
            let db = KnockMath.outputDB(value)
            return String(format: "%+.1f dB", db)
        case .clipper, .tempoSync, .followDAW:
            return value > 0.5 ? "ON" : "OFF"
        case .delaySync:
            return value > 0.5 ? "TEMPO" : "300 ms"
        case .reverbDecay:
            return String(format: "%d ms", Int((0.06 * powf(10, value)) * 1000))
        case .reverbPredelay:
            return String(format: "%d ms", Int(value * 120))
        case .soundMode:
            return SoundMode(rawValue: Int(value.rounded()))?.title ?? "MODERN"
        case .playMode:
            return value > 0.5 ? "LOOP" : "ONE-SHOT"
        default:
            // in percent of the knob's full effect, 0% to 100%
            return "\(Int((KnobTaper.knob(self, value: value, c) * 100).rounded()))%"
        }
    }
}

// MARK: - Shared maths

enum KnockMath {
    /// PITCH in whole semitones, -12...+12, rounded as the engine plays it.
    static func pitchSemitones(_ v: Float) -> Int { Int(((v - 0.5) * 24).rounded()).clamped(-12, 12) }
    /// TUNE in cents, -100...+100.
    static func tuneCents(_ v: Float) -> Float { (v - 0.5) * 200 }
    /// SWING as the classic percentage: where the off-beat 1/16 lands between two 1/8s (50% = straight).
    /// The engine moves it up to 8 ticks of the 48 between them (PatternData.swingTicks), so the
    /// top is 66.7%.
    static func swingPercent(_ bounce: Float) -> Float { 50 + bounce.clamped(0, 1) * 8 / 48 * 100 }
    static func bounce(swingPercent p: Float) -> Float { ((p - 50) / (8 / 48 * 100)).clamped(0, 1) }
    /// Low-pass cutoff of the FILTER knob: 120 Hz at 0, fully open at 1.
    static func filterCutoff(_ v: Float) -> Float { 120 * powf(20_000 / 120, v) }
    /// CLIP DRIVE: 0 to +18 dB into the clipper.
    static func clipDriveDB(_ v: Float) -> Float { v * 18 }
    /// OUTPUT: 0 is −12 dB, the top 0 dB (100%): only the SAMPLER's VOL goes past 100% (Tyrone, Oct 19).
    static func outputDB(_ v: Float) -> Float { (v.clamped(0, 1) - 1) * 12 }
    /// Saved before Oct 19: 0.75 was 0 dB, 1.0 +12 dB, 0 −12 dB. The same level now (anything over 0 dB stops at 0 dB).
    static func outputFromOld(_ v: Float) -> Float {
        let db: Float = v >= 0.75 ? (v - 0.75) / 0.25 * 12 : (max(0, v) - 0.75) / 0.75 * 12
        return (1 + min(db, 0) / 12).clamped(0, 1)
    }
    static func dbToGain(_ db: Float) -> Float { powf(10, db / 20) }
    /// A track's own DECAY (Face 2's channel strip): the time constant its hits fade with (FULL = none).
    static func padDecayTau(_ d: Float) -> Double {
        d >= 0.999 ? .infinity : 0.03 + Double(d) * Double(d) * 2.5
    }
    /// What that DECAY readout shows: how long a hit rings before it's 60 dB down (12 ms hold + 6.9 time constants).
    static func padDecayText(_ d: Float) -> String {
        let tau = padDecayTau(d)
        guard tau.isFinite else { return "FULL" }
        let t = 0.012 + tau * log(1_000)
        return t < 1 ? "\(Int((t * 1_000).rounded())) ms" : String(format: "%.2f s", t)
    }
    /// TIGHTEN's tail (seconds, the time constant every hit decays with after its first 12 ms):
    /// none at 0, 1.26 s at 10%, 45 ms at the top. Below 10% the decay comes in from nothing (Nov 14:
    /// it used to jump straight to a 1.5 s tail at 0.1%, so the knob's first 10% all sounded the same).
    static func tightenTau(_ t: Float) -> Double {
        guard t > 0.000_01 else { return .infinity }
        let t = Double(t.clamped(0, 1))
        func tau(_ x: Double) -> Double { let r = 1 - x; return 0.045 + r * r * 1.5 }
        return t >= 0.1 ? tau(t) : tau(0.1) * 0.1 / t
    }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
