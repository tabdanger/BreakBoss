// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Modes

/// The three faceplates. Each one is its own sound: Modern is clean and forward, Vintage adds
/// drive and boost (tape and old-sampler warmth), Texture adds a downsampled, unstable sound
/// with a tempo-synced delay and a gated reverb.
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
    // TEXTURE's glitch: WARP is how much (pitch sweeping up and down, a swept filter, stutters),
    // WOBBLE how fast it sweeps, in note values at the tempo.
    case warp, wobble

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
        case .wobble: return "wobble"
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
        case .gatedReverb: return "Gated Reverb"
        case .drive: return "Drive"
        case .warp: return "Warp"
        case .wobble: return "Wobble"
        }
    }

    /// Knobs are 0...1. Switches hold whole numbers.
    var isKnob: Bool { (rawValue <= KParam.noise.rawValue && self != .clipper) || rawValue >= KParam.resample.rawValue }

    /// Number of positions for switches (nil for knobs).
    var steps: Int? {
        switch self {
        case .clipper, .tempoSync, .followDAW, .playMode: return 2
        case .soundMode: return 3
        default: return nil
        }
    }

    /// INIT values. Knob pointers start where the faceplate artwork shows them, except Pitch and
    /// Tune (centred, so nothing is detuned) and Clip Drive (lower, so INIT isn't clipped hard).
    var defaultValue: Float {
        switch self {
        case .pitch: return 0.5
        case .tune: return 0.5
        case .bounce: return 0.0
        case .velocity: return 0.75
        case .filter: return 1.0
        case .clipDrive: return 0.25
        case .output: return 0.75
        case .clipper: return 1
        case .boost: return 0.42
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
        case .resample: return 0.5
        case .instability: return 0.5
        case .textureDelay: return 0.32
        case .gatedReverb: return 0.5
        case .drive: return 0
        case .warp: return 0
        case .wobble: return 0.6
        }
    }

    /// What the value means, for the readout on the screen and the host.
    func text(_ value: Float) -> String {
        switch self {
        case .pitch:
            let st = Int((value - 0.5) * 24).clamped(-12, 12)
            return st == 0 ? "0 st" : String(format: "%+d st", st)
        case .tune:
            return String(format: "%+d ct", Int(((value - 0.5) * 200).rounded()))
        case .bounce:
            return value < 0.01 ? "STRAIGHT" : String(format: "%d%% SWING", Int(50 + value * 22))
        case .velocity:
            return value < 0.01 ? "FIXED" : String(format: "%d%%", Int(value * 100))
        case .filter:
            if value > 0.995 { return "OPEN" }
            return String(format: "%.0f Hz", KnockMath.filterCutoff(value))
        case .clipDrive:
            return String(format: "+%.1f dB", KnockMath.clipDriveDB(value))
        case .output:
            let db = KnockMath.outputDB(value)
            return db < -59 ? "-inf dB" : String(format: "%+.1f dB", db)
        case .clipper, .tempoSync, .followDAW:
            return value > 0.5 ? "ON" : "OFF"
        case .soundMode:
            return SoundMode(rawValue: Int(value.rounded()))?.title ?? "MODERN"
        case .playMode:
            return value > 0.5 ? "LOOP" : "ONE-SHOT"
        case .warp:
            return value < 0.005 ? "OFF" : "\(Int((value * 10).rounded()))"
        case .wobble:
            return KnockMath.wobbleNames[KnockMath.wobbleStep(value)]
        default:
            return "\(Int((value * 10).rounded()))"
        }
    }
}

// MARK: - Shared maths

enum KnockMath {
    /// Low-pass cutoff of the FILTER knob: 120 Hz at 0, fully open at 1.
    static func filterCutoff(_ v: Float) -> Float { 120 * powf(20_000 / 120, v) }
    /// CLIP DRIVE: 0 to +18 dB into the clipper.
    static func clipDriveDB(_ v: Float) -> Float { v * 18 }
    /// OUTPUT: 0.75 is 0 dB, 1.0 is +6 dB, 0 is silent.
    static func outputDB(_ v: Float) -> Float {
        if v <= 0.001 { return -120 }
        if v >= 0.75 { return (v - 0.75) / 0.25 * 6 }
        // 40 dB per decade of knob travel: 0.75 -> 0 dB, 0.25 -> -19 dB, 0.05 -> -47 dB
        return 40 * log10f(v / 0.75)
    }
    static func dbToGain(_ db: Float) -> Float { powf(10, db / 20) }
    /// WOBBLE snaps to six note values: one sweep per bar up to one per 1/32 note.
    static let wobbleNames = ["1 BAR", "1/2", "1/4", "1/8", "1/16", "1/32"]
    static func wobbleStep(_ v: Float) -> Int { Int((v.clamped(0, 1) * 5).rounded()) }
    /// Sweeps per beat for a WOBBLE setting (0.25 = one per 4/4 bar).
    static func wobbleRate(_ v: Float) -> Double { 0.25 * pow(2, Double(wobbleStep(v))) }
}

extension Comparable {
    func clamped(_ lo: Self, _ hi: Self) -> Self { min(max(self, lo), hi) }
}
