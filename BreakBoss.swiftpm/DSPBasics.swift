// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// Small building blocks used by the drum synthesis and the processing chains. Everything here
// is a value type with no allocation, safe to run on the audio thread.

/// Fast deterministic noise / random numbers (xorshift32). Same seed -> same sounds and grooves.
struct KRandom {
    private var state: UInt32

    init(seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }

    mutating func next() -> UInt32 {
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
        return state
    }

    /// 0 ..< 1
    mutating func unit() -> Float { Float(next() >> 8) * (1.0 / 16_777_216.0) }
    /// -1 ..< 1
    mutating func bipolar() -> Float { unit() * 2 - 1 }
    mutating func range(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * unit() }
    mutating func int(_ upperBound: Int) -> Int { upperBound <= 1 ? 0 : Int(next() % UInt32(upperBound)) }
    mutating func chance(_ p: Float) -> Bool { unit() < p }
    mutating func pick<T>(_ items: [T]) -> T { items[int(items.count)] }
}

/// Transposed direct form II biquad (RBJ cookbook coefficients).
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    mutating func reset() { z1 = 0; z2 = 0 }

    private mutating func set(_ b0: Float, _ b1: Float, _ b2: Float, _ a0: Float, _ a1: Float, _ a2: Float) {
        self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0
        self.a1 = a1 / a0; self.a2 = a2 / a0
    }

    mutating func lowPass(_ f: Float, q: Float, sr: Float) {
        let w = 2 * Float.pi * min(f, sr * 0.49) / sr, c = cosf(w), al = sinf(w) / (2 * q)
        set((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al)
    }

    mutating func highPass(_ f: Float, q: Float, sr: Float) {
        let w = 2 * Float.pi * min(f, sr * 0.49) / sr, c = cosf(w), al = sinf(w) / (2 * q)
        set((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al)
    }

    mutating func bandPass(_ f: Float, q: Float, sr: Float) {
        let w = 2 * Float.pi * min(f, sr * 0.49) / sr, c = cosf(w), al = sinf(w) / (2 * q)
        set(al, 0, -al, 1 + al, -2 * c, 1 - al)
    }

    mutating func peak(_ f: Float, q: Float, db: Float, sr: Float) {
        let A = powf(10, db / 40), w = 2 * Float.pi * min(f, sr * 0.49) / sr
        let c = cosf(w), al = sinf(w) / (2 * q)
        set(1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A)
    }

    mutating func lowShelf(_ f: Float, db: Float, sr: Float) {
        let A = powf(10, db / 40), w = 2 * Float.pi * min(f, sr * 0.49) / sr
        let c = cosf(w), s = sinf(w), al = s / 2 * sqrtf(2), sa = 2 * sqrtf(A) * al
        set(A * ((A + 1) - (A - 1) * c + sa), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sa),
            (A + 1) + (A - 1) * c + sa, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sa)
    }

    mutating func highShelf(_ f: Float, db: Float, sr: Float) {
        let A = powf(10, db / 40), w = 2 * Float.pi * min(f, sr * 0.49) / sr
        let c = cosf(w), s = sinf(w), al = s / 2 * sqrtf(2), sa = 2 * sqrtf(A) * al
        set(A * ((A + 1) + (A - 1) * c + sa), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sa),
            (A + 1) - (A - 1) * c + sa, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sa)
    }
}

/// One-pole low-pass / high-pass.
struct OnePole {
    var a: Float = 0
    var z: Float = 0

    mutating func setCutoff(_ f: Float, sr: Float) { a = expf(-2 * Float.pi * min(f, sr * 0.49) / sr) }

    @inline(__always) mutating func lowPass(_ x: Float) -> Float { z = x + a * (z - x); return z }
    @inline(__always) mutating func highPass(_ x: Float) -> Float { x - lowPass(x) }
}

/// Peak follower with separate attack and release.
struct EnvelopeFollower {
    var attack: Float = 0
    var release: Float = 0
    var value: Float = 0

    mutating func set(attackMs: Float, releaseMs: Float, sr: Float) {
        attack = expf(-1 / (max(attackMs, 0.01) * 0.001 * sr))
        release = expf(-1 / (max(releaseMs, 0.01) * 0.001 * sr))
    }

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let level = abs(x)
        let c = level > value ? attack : release
        value = level + c * (value - level)
        return value
    }
}

/// Linear smoothing of a control towards its target over a fixed time.
struct Smoothed {
    var value: Float
    var target: Float
    var step: Float = 0
    var remaining: Int = 0
    var length: Int = 256

    init(_ v: Float) { value = v; target = v }

    mutating func configure(ms: Float, sr: Float) { length = max(1, Int(ms * 0.001 * sr)) }

    mutating func set(_ t: Float) {
        guard t != target else { return }
        target = t
        remaining = length
        step = (t - value) / Float(length)
    }

    mutating func jump(_ t: Float) { target = t; value = t; remaining = 0 }

    @inline(__always)
    mutating func next() -> Float {
        if remaining > 0 {
            value += step
            remaining -= 1
            if remaining == 0 { value = target }
        }
        return value
    }
}

enum Saturate {
    /// Smooth saturation that never exceeds ±1.
    @inline(__always) static func soft(_ x: Float) -> Float {
        if x > 3 { return 1 }
        if x < -3 { return -1 }
        let x2 = x * x
        return x * (27 + x2) / (27 + 9 * x2)
    }

    /// Tape-like: asymmetric, adds some even harmonics.
    @inline(__always) static func tape(_ x: Float, bias: Float = 0.12) -> Float {
        soft(x + bias) - soft(bias)
    }

    /// Clean up to the knee, then curves into the ceiling (the master clipper's shape).
    @inline(__always) static func clip(_ x: Float, ceiling: Float, knee: Float) -> Float {
        let a = abs(x)
        let start = ceiling * (1 - knee)
        if a <= start { return x }
        let over = (a - start) / max(ceiling - start, 1e-6)
        let shaped = start + (ceiling - start) * soft(over * 1.5) // soft(1.5x) reaches ~1 at x≈2
        return x < 0 ? -min(shaped, ceiling) : min(shaped, ceiling)
    }
}

/// 2x oversampling around a nonlinearity with a 31-tap half-band FIR (Kaiser window) on each
/// side, so the clipper and the grit stage don't fold harmonics back down as aliasing.
/// Latency: 15 samples at the base rate.
struct HalfBandOversampler {
    /// The 16 non-zero odd taps h[2i-15], i = 0...15, of the half-band low-pass (centre tap 0.5).
    static let oddTaps: [Float] = {
        func bessel0(_ x: Double) -> Double {
            var sum = 1.0, term = 1.0, k = 1.0
            while term > 1e-12 * sum { term *= (x / (2 * k)) * (x / (2 * k)); sum += term; k += 1 }
            return sum
        }
        let beta = 8.0, n = 15.0
        return (0..<16).map { i -> Float in
            let k = Double(2 * i - 15)                         // odd, -15 ... 15
            let sinc = sin(Double.pi * k / 2) / (Double.pi * k)  // 0.5 * sinc(k / 2)
            let w = bessel0(beta * (1 - (k / n) * (k / n)).squareRoot()) / bessel0(beta)
            return Float(sinc * w)
        }
    }()

    private var xHist = [Float](repeating: 0, count: 32)     // input, base rate
    private var oddHist = [Float](repeating: 0, count: 32)   // processed odd-phase samples
    private var evenHist = [Float](repeating: 0, count: 32)  // processed even-phase samples
    private var index = 0

    /// Runs `f` at twice the rate on one input sample and returns one output sample.
    @inline(__always)
    mutating func process(_ x: Float, _ f: (Float) -> Float) -> Float {
        let taps = HalfBandOversampler.oddTaps
        index = (index + 1) & 31
        xHist[index] = x
        // Upsample (zero-stuffing, gain 2): even output is the FIR over the history, odd output
        // is the input delayed by 7 (the centre tap).
        var a: Float = 0
        for i in 0..<16 { a += taps[i] * xHist[(index - i) & 31] }
        let up0 = 2 * a
        let up1 = xHist[(index - 7) & 31]
        // The nonlinearity at 2x.
        let v0 = f(up0)
        let v1 = f(up1)
        evenHist[index] = v0
        oddHist[index] = v1
        // Downsample: keep the odd samples' output; centre tap lands on an even sample.
        var z: Float = 0.5 * evenHist[(index - 7) & 31]
        for i in 0..<16 { z += taps[i] * oddHist[(index - i) & 31] }
        return z
    }
}
