// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Our own drum sounds
//
// Every factory sound in BreakBoss is synthesised here, from scratch, when a kit loads: no
// samples from anyone else's library. A recipe says what kind of drum it is and how it's tuned;
// the dice in ONE-SHOT mode re-rolls the small variations (tune, decay, tone) to make new sounds.
// Sounds are rendered once (off the audio thread) into a SampleBuffer that the pads play back.

enum DrumKind: String, Codable, CaseIterable {
    case kick808, kickPunch, kickBoom, kickAcoustic
    case snareTrap, snareCrack, snareAcoustic, clap, rim, snap
    case hatClosed, hatOpen, hatAcousticClosed, hatAcousticOpen
    case shaker, tambourine, conga, bongo, cowbell, woodblock
    case tomLow, tomHigh, crash, ride
    case sub808
}

struct DrumRecipe: Codable, Equatable {
    var kind: DrumKind
    /// Main pitch in Hz (for tonal drums) or a brightness scale around 1.0 (hats, noise).
    var tune: Float
    /// Decay time in seconds.
    var decay: Float
    /// 0...1: darker <-> brighter / more body <-> more noise, depending on the drum.
    var tone: Float = 0.5
    /// 0...1: attack click / snap.
    var snap: Float = 0.5
    /// 0...1: saturation baked into the sound.
    var drive: Float = 0
    /// 0...1: recorded-room ambience (acoustic kits).
    var room: Float = 0
    /// Output level, 0...1.
    var level: Float = 0.9
    /// Display name on the pad editor.
    var label: String = ""

    /// A slightly different take on this sound (dice in ONE-SHOT mode).
    func varied(_ rng: inout KRandom, amount: Float = 1) -> DrumRecipe {
        var r = self
        let tonal: Set<DrumKind> = [.kick808, .kickPunch, .kickBoom, .kickAcoustic, .sub808, .tomLow, .tomHigh,
                                    .conga, .bongo, .snareTrap, .snareCrack, .snareAcoustic, .rim, .cowbell, .woodblock]
        if tonal.contains(kind) {
            r.tune *= powf(2, rng.range(-2.5, 2.5) * amount / 12)
        } else {
            r.tune *= 1 + rng.range(-0.12, 0.12) * amount
        }
        r.decay *= 1 + rng.range(-0.28, 0.28) * amount
        r.tone = (tone + rng.range(-0.2, 0.2) * amount).clamped(0, 1)
        r.snap = (snap + rng.range(-0.2, 0.2) * amount).clamped(0, 1)
        r.drive = (drive + rng.range(-0.1, 0.15) * amount).clamped(0, 1)
        return r
    }
}

/// A stereo sample in memory. Made off the audio thread, read on it, never changed after.
final class SampleBuffer {
    let left: UnsafeMutablePointer<Float>
    let right: UnsafeMutablePointer<Float>
    let length: Int
    let sampleRate: Double
    /// Peak-normalised preview for the pad editor's waveform (256 points).
    let overview: [Float]

    init(left l: [Float], right r: [Float]? = nil, sampleRate: Double) {
        let n = max(l.count, 1)
        length = n
        self.sampleRate = sampleRate
        left = UnsafeMutablePointer<Float>.allocate(capacity: n + 4)
        right = UnsafeMutablePointer<Float>.allocate(capacity: n + 4)
        left.initialize(repeating: 0, count: n + 4)
        right.initialize(repeating: 0, count: n + 4)
        for i in 0..<l.count { left[i] = l[i] }
        let rr = r ?? l
        for i in 0..<min(rr.count, n) { right[i] = rr[i] }
        var points = [Float](repeating: 0, count: 256)
        let per = max(1, n / 256)
        for p in 0..<256 {
            var m: Float = 0
            let s = p * per
            if s < n { for i in s..<min(n, s + per) { m = max(m, abs(left[i]), abs(right[i])) } }
            points[p] = m
        }
        overview = points
    }

    deinit {
        left.deallocate()
        right.deallocate()
    }

    var seconds: Double { Double(length) / sampleRate }
}

enum DrumSynth {
    /// Renders a recipe at the given sample rate.
    static func render(_ r: DrumRecipe, sampleRate: Double, seed: UInt32) -> SampleBuffer {
        let sr = Float(sampleRate)
        var rng = KRandom(seed: seed &+ 0x51F1)
        var mono: [Float]
        switch r.kind {
        case .kick808, .sub808: mono = kick808(r, sr, &rng)
        case .kickPunch: mono = kickPunch(r, sr, &rng)
        case .kickBoom: mono = kickBoom(r, sr, &rng)
        case .kickAcoustic: mono = kickAcoustic(r, sr, &rng)
        case .snareTrap, .snareCrack: mono = snare(r, sr, &rng, crack: r.kind == .snareCrack)
        case .snareAcoustic: mono = snareAcoustic(r, sr, &rng)
        case .clap: mono = clap(r, sr, &rng)
        case .rim: mono = rim(r, sr, &rng)
        case .snap: mono = snap(r, sr, &rng)
        case .hatClosed, .hatOpen: mono = metalHat(r, sr, &rng, acoustic: false)
        case .hatAcousticClosed, .hatAcousticOpen: mono = metalHat(r, sr, &rng, acoustic: true)
        case .shaker: mono = shaker(r, sr, &rng)
        case .tambourine: mono = tambourine(r, sr, &rng)
        case .conga, .bongo: mono = handDrum(r, sr, &rng)
        case .cowbell: mono = cowbell(r, sr, &rng)
        case .woodblock: mono = woodblock(r, sr, &rng)
        case .tomLow, .tomHigh: mono = tom(r, sr, &rng)
        case .crash, .ride: mono = cymbal(r, sr, &rng, ride: r.kind == .ride)
        }
        if r.drive > 0.01 {
            let g = 1 + r.drive * 5
            let comp = 1 / Shape.soft(g)
            for i in 0..<mono.count { mono[i] = Shape.soft(mono[i] * g) * comp }
        }
        normalise(&mono, to: r.level)
        fadeTail(&mono, sr)
        if r.room > 0.01 {
            let (l, rr) = room(mono, sr, amount: r.room, seed: seed)
            return SampleBuffer(left: l, right: rr, sampleRate: sampleRate)
        }
        if r.kind == .crash || r.kind == .ride || r.kind == .hatOpen || r.kind == .hatAcousticOpen {
            // A little width on long metal: the right side is a second, slightly different strike.
            var rng2 = KRandom(seed: seed &+ 0xA5A5)
            var other = r
            other.tune *= 1.004
            var right: [Float]
            switch r.kind {
            case .crash, .ride: right = cymbal(other, sr, &rng2, ride: r.kind == .ride)
            default: right = metalHat(other, sr, &rng2, acoustic: r.kind == .hatAcousticOpen)
            }
            normalise(&right, to: r.level)
            fadeTail(&right, sr)
            let n = min(mono.count, right.count)
            var l = [Float](repeating: 0, count: n), rr = [Float](repeating: 0, count: n)
            for i in 0..<n { l[i] = 0.75 * mono[i] + 0.25 * right[i]; rr[i] = 0.25 * mono[i] + 0.75 * right[i] }
            return SampleBuffer(left: l, right: rr, sampleRate: sampleRate)
        }
        return SampleBuffer(left: mono, sampleRate: sampleRate)
    }

    // MARK: Kicks

    static func kick808(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.05) * sr)
        var out = [Float](repeating: 0, count: n)
        var phase: Float = 0
        let sweep = 1.6 + r.snap * 2.2
        let sweepTime = 0.018 + r.tone * 0.03
        var click = OnePole(); click.setCutoff(2500, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            let f = r.tune * (1 + sweep * expf(-t / sweepTime))
            phase += f / sr
            if phase > 1 { phase -= 1 }
            // Sustained 808: a long, slightly curved decay that holds before falling off.
            let hold = t < r.decay * 0.25 ? 1 : expf(-(t - r.decay * 0.25) / (r.decay * 0.32))
            let env = min(1, t * sr / 24) * hold
            var s = sinf(2 * .pi * phase) * env
            if i < Int(0.004 * sr) { s += click.highPass(rng.bipolar()) * (1 - t / 0.004) * 0.35 * r.snap }
            // Mild saturation gives the 808 harmonics that show up on small speakers.
            out[i] = Shape.soft(s * (1.3 + r.tone))
        }
        return out
    }

    static func kickPunch(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.04) * sr)
        var out = [Float](repeating: 0, count: n)
        var phase: Float = 0
        var hp = Biquad(); hp.highPass(3000, q: 0.7, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            let f = r.tune * (1 + 3.8 * expf(-t / 0.011) + 0.6 * expf(-t / 0.05))
            phase += f / sr
            if phase > 1 { phase -= 1 }
            let env = min(1, t * sr / 12) * expf(-t / (r.decay * 0.42))
            var s = sinf(2 * .pi * phase) * env
            if t < 0.006 { s += hp.process(rng.bipolar()) * (1 - t / 0.006) * (0.3 + 0.6 * r.snap) }
            out[i] = Shape.soft(s * (1.5 + r.tone * 1.5))
        }
        return out
    }

    static func kickBoom(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        // 90s drum-machine kick: round, a little boxy, short sweep.
        let n = Int((r.decay + 0.05) * sr)
        var out = [Float](repeating: 0, count: n)
        var p1: Float = 0, p2: Float = 0
        var lp = OnePole(); lp.setCutoff(900 + r.tone * 2500, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            let f = r.tune * (1 + 1.8 * expf(-t / 0.02))
            p1 += f / sr; if p1 > 1 { p1 -= 1 }
            p2 += f * 2.02 / sr; if p2 > 1 { p2 -= 1 }
            let env = min(1, t * sr / 30) * expf(-t / (r.decay * 0.4))
            var s = (sinf(2 * .pi * p1) + 0.18 * sinf(2 * .pi * p2) * expf(-t / 0.04)) * env
            if t < 0.005 { s += rng.bipolar() * (1 - t / 0.005) * 0.25 * r.snap }
            out[i] = lp.lowPass(Shape.soft(s * 1.4))
        }
        return out
    }

    static func kickAcoustic(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.05) * sr)
        var out = [Float](repeating: 0, count: n)
        let ratios: [Float] = [1, 1.59, 2.14, 2.65]
        let amps: [Float] = [1, 0.35, 0.18, 0.08]
        var ph = [Float](repeating: 0, count: 4)
        var beater = Biquad(); beater.bandPass(2800 + r.tone * 2500, q: 0.9, sr: sr)
        var lp = OnePole(); lp.setCutoff(3500, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            let bend = 1 + 0.45 * expf(-t / 0.025)
            var s: Float = 0
            for m in 0..<4 {
                ph[m] += r.tune * ratios[m] * bend / sr
                if ph[m] > 1 { ph[m] -= 1 }
                s += sinf(2 * .pi * ph[m]) * amps[m] * expf(-t / (r.decay * (m == 0 ? 0.38 : 0.12)))
            }
            s *= min(1, t * sr / 20)
            if t < 0.012 { s += beater.process(rng.bipolar()) * expf(-t / 0.003) * (0.4 + 0.8 * r.snap) }
            out[i] = lp.lowPass(s)
        }
        return out
    }

    // MARK: Snares, claps, rims

    static func snare(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom, crack: Bool) -> [Float] {
        let n = Int((r.decay + 0.05) * sr)
        var out = [Float](repeating: 0, count: n)
        var p1: Float = 0, p2: Float = 0
        var hp = Biquad(); hp.highPass(crack ? 2200 : 1400, q: 0.7, sr: sr)
        var bp = Biquad(); bp.bandPass(crack ? 5200 : 3600 + r.tone * 2000, q: 0.6, sr: sr)
        let noiseMix = 0.45 + r.tone * 0.5
        for i in 0..<n {
            let t = Float(i) / sr
            let bend = 1 + 0.35 * expf(-t / 0.012)
            p1 += r.tune * bend / sr; if p1 > 1 { p1 -= 1 }
            p2 += r.tune * 1.78 * bend / sr; if p2 > 1 { p2 -= 1 }
            let body = (sinf(2 * .pi * p1) + 0.6 * sinf(2 * .pi * p2)) * expf(-t / (crack ? 0.03 : 0.055))
            let w = rng.bipolar()
            let noise = (hp.process(w) * 0.6 + bp.process(w) * 0.9) * expf(-t / (r.decay * 0.35))
            let attack = t < 0.003 ? (1 - t / 0.003) * rng.bipolar() * r.snap : 0
            out[i] = (body * (1 - noiseMix) * 1.2 + noise * noiseMix * 1.6 + attack) * min(1, t * sr / 6)
        }
        return out
    }

    static func snareAcoustic(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.05) * sr)
        var out = [Float](repeating: 0, count: n)
        let ratios: [Float] = [1, 1.52, 1.83, 2.24]
        var ph = [Float](repeating: 0, count: 4)
        var wires = Biquad(); wires.bandPass(4200 + r.tone * 2500, q: 0.5, sr: sr)
        var wiresLow = Biquad(); wiresLow.bandPass(1800, q: 0.8, sr: sr)
        var stick = Biquad(); stick.highPass(5000, q: 0.7, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            var body: Float = 0
            for m in 0..<4 {
                ph[m] += r.tune * ratios[m] * (1 + 0.15 * expf(-t / 0.01)) / sr
                if ph[m] > 1 { ph[m] -= 1 }
                body += sinf(2 * .pi * ph[m]) * expf(-t / (0.05 / Float(m + 1) + 0.03)) * (m == 0 ? 1 : 0.5)
            }
            let w = rng.bipolar()
            let buzz = (wires.process(w) + 0.5 * wiresLow.process(w)) * expf(-t / (r.decay * 0.3))
            let click = t < 0.004 ? stick.process(rng.bipolar()) * expf(-t / 0.0012) * (0.6 + r.snap) : 0
            out[i] = (body * 0.7 + buzz * 1.4 + click) * min(1, t * sr / 8)
        }
        return out
    }

    static func clap(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.08) * sr)
        var out = [Float](repeating: 0, count: n)
        var bp = Biquad(); bp.bandPass(1050 + r.tone * 900, q: 1.4, sr: sr)
        var hp = Biquad(); hp.highPass(700, q: 0.7, sr: sr)
        // Several hands a few ms apart, then the room tail.
        let spacing = 0.007 + (1 - r.snap) * 0.005
        let bursts: [Float] = [0, spacing, spacing * 2.1, spacing * 3.4]
        for i in 0..<n {
            let t = Float(i) / sr
            var env: Float = 0
            for (k, b) in bursts.enumerated() where t >= b {
                let dt = t - b
                env += (k == bursts.count - 1 ? expf(-dt / (r.decay * 0.3)) : expf(-dt / 0.0035)) * (k == 3 ? 1 : 0.8)
            }
            out[i] = hp.process(bp.process(rng.bipolar())) * env * 2.4
        }
        return out
    }

    static func rim(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.03) * sr)
        var out = [Float](repeating: 0, count: n)
        var p1: Float = 0, p2: Float = 0
        var hp = Biquad(); hp.highPass(2500, q: 0.7, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            p1 += r.tune / sr; if p1 > 1 { p1 -= 1 }
            p2 += r.tune * 2.95 / sr; if p2 > 1 { p2 -= 1 }
            let env = expf(-t / (r.decay * 0.35))
            let tone = (sinf(2 * .pi * p1) * 0.7 + sinf(2 * .pi * p2) * 0.5 * expf(-t / 0.008)) * env
            let click = t < 0.002 ? hp.process(rng.bipolar()) * (1 - t / 0.002) * r.snap : 0
            out[i] = tone + click
        }
        return out
    }

    static func snap(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.03) * sr)
        var out = [Float](repeating: 0, count: n)
        var bp = Biquad(); bp.bandPass(2300 + r.tone * 1500, q: 2.6, sr: sr)
        var bp2 = Biquad(); bp2.bandPass(900, q: 3, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            let w = rng.bipolar()
            let env = t < 0.0015 ? t / 0.0015 : expf(-(t - 0.0015) / (r.decay * 0.3))
            out[i] = (bp.process(w) * 1.8 + bp2.process(w) * 0.6 * expf(-t / 0.01)) * env
        }
        return out
    }

    // MARK: Metal

    static func metalHat(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom, acoustic: Bool) -> [Float] {
        let n = Int((r.decay + 0.04) * sr)
        var out = [Float](repeating: 0, count: n)
        // Six square waves at inharmonic ratios (the classic analog hat recipe), plus noise.
        let ratios: [Float] = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]
        let hatScale: Float = r.tune * (acoustic ? 1.3 : 1)
        let base: [Float] = ratios.map { $0 * hatScale }
        var ph = [Float](repeating: 0, count: 6)
        for k in 0..<6 { ph[k] = rng.unit() }
        var bp = Biquad(); bp.bandPass(acoustic ? 8500 : 10_000, q: 0.8, sr: sr)
        var hp = Biquad(); hp.highPass(acoustic ? 5500 : 7000 - r.tone * 1500, q: 0.7, sr: sr)
        var hp2 = Biquad(); hp2.highPass(6000, q: 0.7, sr: sr)
        let noiseMix: Float = acoustic ? 0.65 : 0.25 + 0.3 * (1 - r.tone)
        for i in 0..<n {
            let t = Float(i) / sr
            var sq: Float = 0
            for k in 0..<6 {
                ph[k] += base[k] / sr
                if ph[k] > 1 { ph[k] -= 1 }
                sq += ph[k] < 0.5 ? 1 : -1
            }
            let metal = hp.process(bp.process(sq / 6))
            let noise = hp2.process(rng.bipolar())
            let env: Float
            if acoustic {
                // "Chick" then a shimmering tail.
                env = 0.7 * expf(-t / 0.006) + expf(-t / (r.decay * 0.42))
            } else {
                env = expf(-t / (r.decay * 0.36))
            }
            out[i] = (metal * (1 - noiseMix) * 3 + noise * noiseMix) * env * min(1, t * sr / 4)
        }
        return out
    }

    static func cymbal(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom, ride: Bool) -> [Float] {
        let n = Int((r.decay + 0.05) * sr)
        var out = [Float](repeating: 0, count: n)
        let count = 14
        var freqs = [Float](), ph = [Float]()
        for _ in 0..<count {
            freqs.append(rng.range(ride ? 380 : 300, ride ? 6200 : 9000) * r.tune)
            ph.append(rng.unit())
        }
        var hp = Biquad(); hp.highPass(ride ? 2500 : 3500, q: 0.7, sr: sr)
        var hpN = Biquad(); hpN.highPass(4500, q: 0.7, sr: sr)
        var bell: Float = 0
        for i in 0..<n {
            let t = Float(i) / sr
            var s: Float = 0
            for k in 0..<count {
                ph[k] += freqs[k] / sr
                if ph[k] > 1 { ph[k] -= 1 }
                s += ph[k] < 0.5 ? 1 : -1
            }
            var x = hp.process(s / Float(count)) * 2.2 + hpN.process(rng.bipolar()) * (ride ? 0.3 : 0.7)
            if ride {
                bell += 3400 * r.tune / sr
                if bell > 1 { bell -= 1 }
                x += sinf(2 * .pi * bell) * 0.25 * expf(-t / 0.4) * r.tone
            }
            let env = (ride ? 0.6 * expf(-t / 0.01) : 0) + expf(-t / (r.decay * 0.33))
            out[i] = x * env * min(1, t * sr / 10)
        }
        return out
    }

    static func cowbell(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.04) * sr)
        var out = [Float](repeating: 0, count: n)
        var p1: Float = 0, p2: Float = 0
        var bp = Biquad(); bp.bandPass(r.tune * 3.1, q: 1.6, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            p1 += r.tune / sr; if p1 > 1 { p1 -= 1 }
            p2 += r.tune * 1.48 / sr; if p2 > 1 { p2 -= 1 }
            let sq: Float = (p1 < 0.5 ? 1 : -1) + (p2 < 0.5 ? 1 : -1)
            let env = 0.6 * expf(-t / 0.012) + expf(-t / (r.decay * 0.35))
            out[i] = bp.process(sq) * env
        }
        return out
    }

    // MARK: Hand percussion

    static func shaker(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.03) * sr)
        var out = [Float](repeating: 0, count: n)
        var hp = Biquad(); hp.highPass(4500 + r.tone * 3000, q: 0.7, sr: sr)
        let attack = 0.006 + (1 - r.snap) * 0.02
        for i in 0..<n {
            let t = Float(i) / sr
            let env = t < attack ? t / attack : expf(-(t - attack) / (r.decay * 0.3))
            out[i] = hp.process(rng.bipolar()) * env
        }
        return out
    }

    static func tambourine(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.04) * sr)
        var out = [Float](repeating: 0, count: n)
        var bp1 = Biquad(); bp1.bandPass(6500 * r.tune, q: 3, sr: sr)
        var bp2 = Biquad(); bp2.bandPass(9200 * r.tune, q: 3, sr: sr)
        var bp3 = Biquad(); bp3.bandPass(11_800 * r.tune, q: 2.5, sr: sr)
        var hp = Biquad(); hp.highPass(4000, q: 0.7, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            // Jingles: a handful of rattles in the first 20 ms, then the ring.
            let rattle = 1 + 0.6 * sinf(2 * .pi * 70 * t) * expf(-t / 0.03)
            let env = min(1, t * sr / 30) * expf(-t / (r.decay * 0.35)) * rattle
            let w = rng.bipolar()
            out[i] = (bp1.process(w) + bp2.process(w) + 0.8 * bp3.process(w) + 0.3 * hp.process(w)) * env * 1.4
        }
        return out
    }

    static func handDrum(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.04) * sr)
        var out = [Float](repeating: 0, count: n)
        var p1: Float = 0, p2: Float = 0
        var slap = Biquad(); slap.bandPass(2200 + r.tone * 1800, q: 1, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            let bend = 1 + 0.12 * expf(-t / 0.02)
            p1 += r.tune * bend / sr; if p1 > 1 { p1 -= 1 }
            p2 += r.tune * 1.5 * bend / sr; if p2 > 1 { p2 -= 1 }
            let body = (sinf(2 * .pi * p1) + 0.3 * sinf(2 * .pi * p2) * expf(-t / 0.03)) * expf(-t / (r.decay * 0.38))
            let s = t < 0.01 ? slap.process(rng.bipolar()) * expf(-t / 0.002) * r.snap : 0
            out[i] = (body + s) * min(1, t * sr / 10)
        }
        return out
    }

    static func woodblock(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.03) * sr)
        var out = [Float](repeating: 0, count: n)
        var res = Biquad(); res.bandPass(r.tune, q: 22, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            let x = t < 0.0015 ? rng.bipolar() : 0
            out[i] = res.process(x) * 12 * expf(-t / (r.decay * 0.5))
        }
        return out
    }

    static func tom(_ r: DrumRecipe, _ sr: Float, _ rng: inout KRandom) -> [Float] {
        let n = Int((r.decay + 0.05) * sr)
        var out = [Float](repeating: 0, count: n)
        var p1: Float = 0, p2: Float = 0
        var stick = Biquad(); stick.bandPass(3000, q: 0.8, sr: sr)
        for i in 0..<n {
            let t = Float(i) / sr
            let bend = 1 + (0.3 + r.snap * 0.4) * expf(-t / 0.05)
            p1 += r.tune * bend / sr; if p1 > 1 { p1 -= 1 }
            p2 += r.tune * 1.6 * bend / sr; if p2 > 1 { p2 -= 1 }
            let body = (sinf(2 * .pi * p1) + 0.25 * sinf(2 * .pi * p2) * expf(-t / 0.06)) * expf(-t / (r.decay * 0.4))
            let s = t < 0.008 ? stick.process(rng.bipolar()) * expf(-t / 0.002) * 0.6 : 0
            out[i] = (body + s + rng.bipolar() * 0.03 * expf(-t / 0.05) * r.tone) * min(1, t * sr / 12)
        }
        return out
    }

    // MARK: Finishing

    static func normalise(_ x: inout [Float], to level: Float) {
        var peak: Float = 0
        for v in x { peak = max(peak, abs(v)) }
        guard peak > 1e-6 else { return }
        let g = level / peak
        for i in 0..<x.count { x[i] *= g }
    }

    /// Fades the last 15 ms and trims trailing silence.
    static func fadeTail(_ x: inout [Float], _ sr: Float) {
        var end = x.count
        while end > 64 && abs(x[end - 1]) < 0.000_15 { end -= 1 }
        if end < x.count { x.removeLast(x.count - end) }
        let f = min(x.count, Int(0.015 * sr))
        for k in 0..<f {
            x[x.count - 1 - k] *= Float(k) / Float(f)
        }
    }

    /// A small stereo room (four combs and two all-passes per side), for acoustic kits.
    static func room(_ x: [Float], _ sr: Float, amount: Float, seed: UInt32) -> ([Float], [Float]) {
        let tail = Int(0.45 * sr)
        let n = x.count + tail
        var inp = x
        inp.append(contentsOf: [Float](repeating: 0, count: tail))
        let scale = sr / 44_100
        func side(_ combsMs: [Float], _ apMs: [Float]) -> [Float] {
            var out = [Float](repeating: 0, count: n)
            for d in combsMs {
                let len = max(1, Int(d * 0.001 * sr))
                var buf = [Float](repeating: 0, count: len)
                var idx = 0
                var lp: Float = 0
                let fb: Float = 0.72
                for i in 0..<n {
                    let y = buf[idx]
                    lp = y + 0.35 * (lp - y)
                    buf[idx] = inp[i] + lp * fb
                    idx += 1; if idx == len { idx = 0 }
                    out[i] += y * 0.25
                }
            }
            for d in apMs {
                let len = max(1, Int(d * 0.001 * sr))
                var buf = [Float](repeating: 0, count: len)
                var idx = 0
                for i in 0..<n {
                    let b = buf[idx]
                    let y = -0.6 * out[i] + b
                    buf[idx] = out[i] + 0.6 * y
                    idx += 1; if idx == len { idx = 0 }
                    out[i] = y
                }
            }
            return out
        }
        _ = scale
        let wetL = side([23.1, 26.9, 29.3, 31.7], [5.0, 1.7])
        let wetR = side([24.3, 27.7, 30.1, 33.1], [5.3, 1.9])
        var l = [Float](repeating: 0, count: n), r = [Float](repeating: 0, count: n)
        let dry = 1 - amount * 0.35
        let wet = amount * 0.9
        for i in 0..<n {
            let d = inp[i] * dry
            l[i] = d + wetL[i] * wet
            r[i] = d + wetR[i] * wet
        }
        var peak: Float = 0
        for i in 0..<n { peak = max(peak, abs(l[i]), abs(r[i])) }
        if peak > 0.99 { let g = 0.99 / peak; for i in 0..<n { l[i] *= g; r[i] *= g } }
        var end = n
        while end > x.count && abs(l[end - 1]) < 0.0002 && abs(r[end - 1]) < 0.0002 { end -= 1 }
        l.removeLast(n - end); r.removeLast(n - end)
        let f = min(end, Int(0.02 * sr))
        for k in 0..<f { let g = Float(k) / Float(f); l[end - 1 - k] *= g; r[end - 1 - k] *= g }
        return (l, r)
    }
}
