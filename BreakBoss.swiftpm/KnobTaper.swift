// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Knob tapers (Tyrone, Nov 14)
//
// "23% means 23% of the full effect." Every FX knob's position is a percentage of what the knob
// does to the sound at 100%: how far the sound moves away from the dry sound, measured on a test
// groove (KnobTaperProbe below). The DSP and the stored values are untouched, so every saved
// preset, kit, project and host automation lane sounds exactly as before: only the knob's
// position (and the readout, which shows the position) is spread so the effect comes in evenly,
// with no dead zone at the bottom and no flat stretch at the top.
//
//   stored value  = KnobTaper.value(p, knob: position, context)    (what the engine plays)
//   knob position = KnobTaper.knob(p, value: stored, context)      (what the knob and readout show)
//
// The tables (KnobTaperTables.swift) are made by tools/knob_taper/make_tables.sh from this file's
// probe; the self-test (checkKnobTapers) measures every knob again at every 1% from 1 to 100.
// A knob with no table (PITCH, TUNE, FILTER, OUTPUT, ...) turns its stored value directly and
// shows its real unit (st, ct, Hz, dB).

/// Where a knob turns the sound: the main chain (Face 1, Face 2 with no track selected) or a
/// track's own insert (Face 2 with a track selected), in one mode. The same stored value can do a
/// little more or less in another mode (Vintage's DRIVE also brings in its tape), so each has its
/// own taper.
struct KnobContext: Hashable {
    var mode: SoundMode
    var insert: Bool

    init(_ mode: SoundMode, insert: Bool = false) {
        self.mode = mode
        self.insert = insert
    }

    /// Every context with an FX section.
    static let all: [KnobContext] = SoundMode.allCases.flatMap { [KnobContext($0), KnobContext($0, insert: true)] }

    var name: String { "\(mode.title)\(insert ? " track" : "")" }
}

enum KnobTaper {
    /// The stored value (what the DSP plays) for a knob position, 0...1.
    static func value(_ p: KParam, knob k: Float, _ c: KnobContext) -> Float {
        let k = k.isFinite ? k.clamped(0, 1) : 0
        guard let t = KnobTaperTables.table(p, c) else { return k }
        let x = k * Float(t.count - 1)
        let i = min(Int(x), t.count - 2)
        return (t[i] + (t[i + 1] - t[i]) * (x - Float(i))).clamped(0, 1)
    }

    /// The knob position (and readout percentage, 0...1) of a stored value.
    static func knob(_ p: KParam, value v: Float, _ c: KnobContext) -> Float {
        let v = v.isFinite ? v.clamped(0, 1) : 0
        guard let t = KnobTaperTables.table(p, c) else { return v }
        if v <= t[0] { return 0 }
        if v >= t[t.count - 1] { return 1 }
        // the tables rise all the way (strictly), so the first entry past v brackets it
        var lo = 0, hi = t.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if t[mid] <= v { lo = mid } else { hi = mid }
        }
        let span = t[hi] - t[lo]
        let f = span > 0 ? (v - t[lo]) / span : 0
        return (Float(lo) + f) / Float(t.count - 1)
    }

    /// True when the knob has a measured taper in this context.
    static func tapered(_ p: KParam, _ c: KnobContext) -> Bool { KnobTaperTables.table(p, c) != nil }
}

// MARK: - Measuring what a knob does

/// Renders a short test groove (kick, snare, hats with real tails) through the same DSP the app
/// plays, with one knob set, and measures how far the sound moved from the dry sound: the
/// difference of their short-time spectra (1024-point frames), so a knob that only delays the
/// sound by a few samples doesn't count as changing it. Used by the table maker and the self-test.
/// Not for the audio thread (it allocates).
enum KnobTaperProbe {
    static let sampleRate: Float = 48_000

    /// How long a knob's test groove plays: 1.5 s, or 24 s for INSTABILITY, whose stutters are
    /// random 1/16s (a short groove has too few 1/16s for their share to come in smoothly).
    static func seconds(_ p: KParam) -> Float { p == .instability ? 24 : 1.5 }

    /// The knobs a context's FX section has (TrackFX.params), the ones the probe can measure.
    static func params(_ c: KnobContext) -> [KParam] { TrackFX.params(c.mode) }

    /// The test groove at 120 BPM: hats on every 1/8, kick on 1 and 3, snare on 2 and 4. Each hit
    /// is shaped by `envelope` (TIGHTEN's tail) from its start.
    static func groove(tighten: Float = 0, seconds: Float = 1.5) -> [Float] {
        let sr = sampleRate
        let n = Int(sr * seconds)
        var x = [Float](repeating: 0, count: n)
        var rng = KRandom(seed: 1234)
        let tau = KnockMath.tightenTau(tighten)
        let coef: Float = tau.isFinite ? Float(exp(-1 / (tau * Double(sr)))) : 1
        let hold = Int(sr * 0.012)
        let step = Int(sr * 0.25)
        var start = 0, k = 0
        while start < n {
            func add(_ length: Int, _ f: (Float) -> Float) {
                var env: Float = 1
                for j in 0..<min(length, n - start) {
                    x[start + j] += f(Float(j) / sr) * env
                    if j >= hold { env *= coef }
                }
            }
            add(Int(sr * 0.05)) { t in rng.bipolar() * 0.18 * expf(-t / 0.012) }
            if k % 4 == 0 {
                var ph: Float = 0
                add(Int(sr * 0.6)) { t in
                    let f = 50 + 90 * expf(-t / 0.04)
                    ph += 2 * .pi * f / sr
                    return sinf(ph) * 0.7 * expf(-t / 0.25)
                }
            }
            if k % 4 == 2 {
                var ph: Float = 0
                add(Int(sr * 0.4)) { t in
                    ph += 2 * .pi * 190 / sr
                    return sinf(ph) * 0.35 * expf(-t / 0.06) + rng.bipolar() * 0.3 * expf(-t / 0.11)
                }
            }
            start += step
            k += 1
        }
        return x
    }

    /// The main chain's or a track's settings with one knob at `v`, as the engine builds them.
    static func settings(_ p: KParam, _ v: Float, _ c: KnobContext) -> BusProcessor.Settings {
        var s = BusProcessor.Settings()
        s.mode = c.mode
        s.insert = c.insert
        s.tempo = 120
        switch p {
        case .boost: s.boost = v
        case .drive: s.drive = v
        case .punch: s.punch = v
        case .analogEQ: s.analogEQ = v
        case .grit: s.grit = v
        case .shine: s.shine = v
        case .noise: s.noise = v
        case .resample: s.resample = v
        case .instability: s.instability = v
        case .textureDelay: s.delay = v
        case .gatedReverb: s.reverb = v
        default: break
        }
        s.keepSection()
        return s
    }

    /// The groove through the context's chain (in 128-sample blocks, like the iPad at its lowest buffer).
    static func render(_ p: KParam, _ v: Float, _ c: KnobContext) -> ([Float], [Float]) {
        var l = groove(tighten: p == .tighten ? v : 0, seconds: seconds(p))
        var r = l
        guard p != .tighten else { return (l, r) }
        let bus = BusProcessor(compact: c.insert)
        bus.prepare(sampleRate: Double(sampleRate))
        let s = settings(p, v, c)
        let block = 128
        var at = 0
        l.withUnsafeMutableBufferPointer { left in
            r.withUnsafeMutableBufferPointer { right in
                guard let lb = left.baseAddress, let rb = right.baseAddress else { return }
                while at < left.count {
                    let n = min(block, left.count - at)
                    var piece = s
                    piece.beat = Double(at) / Double(sampleRate) * 2
                    bus.process(lb + at, rb + at, count: n, piece)
                    at += n
                }
            }
        }
        return (l, r)
    }

    /// Short-time spectra of one channel (1024-point Hann frames, half overlapped), up to 14 kHz and
    /// loudness-compressed, so a change you'd hear counts more than one far above the drums' top.
    static func spectra(_ x: [Float]) -> [Float] {
        let n = 1024, hop = 512, bins = Int(14_000 / sampleRate * Float(n))
        let floor: Float = 0.1 * 0.1          // a full-scale sine reads 256 in these frames
        var window = [Float](repeating: 0, count: n)
        for i in 0..<n { window[i] = 0.5 - 0.5 * cosf(2 * .pi * Float(i) / Float(n)) }
        var out: [Float] = []
        out.reserveCapacity((x.count / hop) * n / 2)
        var re = [Float](repeating: 0, count: n), im = [Float](repeating: 0, count: n)
        var at = 0
        while at + n <= x.count {
            for i in 0..<n { re[i] = x[at + i] * window[i]; im[i] = 0 }
            fft(&re, &im)
            // up to 14 kHz, as loud as each band sounds (magnitude to the 0.6, close to how loudness grows)
            // and nothing below about -68 dB counts (hiss that low is under the drums: 15-bit dither isn't an effect)
            for k in 0..<bins { out.append(powf(max(re[k] * re[k] + im[k] * im[k], floor), 0.3)) }
            at += hop
        }
        return out
    }

    /// How far two renders' spectra are apart (both channels).
    static func distance(_ a: ([Float], [Float]), _ b: ([Float], [Float])) -> Double {
        let pairs = [(spectra(a.0), spectra(b.0)), (spectra(a.1), spectra(b.1))]
        var e: Double = 0
        for (x, y) in pairs { for i in 0..<min(x.count, y.count) { let d = Double(x[i] - y[i]); e += d * d } }
        return e.squareRoot()
    }

    /// The size of the dry groove's spectra, to put a knob's change in dB.
    static func size(_ a: ([Float], [Float])) -> Double {
        var e: Double = 0
        for x in [spectra(a.0), spectra(a.1)] { for v in x { e += Double(v * v) } }
        return e.squareRoot()
    }

    /// What a knob does over its range: the change at stored value `v` as a share of the change at
    /// the top (0...1), from one set of renders.
    struct Curve {
        let dry: ([Float], [Float])
        let full: Double
        let p: KParam
        let c: KnobContext

        init(_ p: KParam, _ c: KnobContext) {
            self.p = p
            self.c = c
            let dry = KnobTaperProbe.render(p, 0, c)
            self.dry = dry
            full = KnobTaperProbe.distance(KnobTaperProbe.render(p, 1, c), dry)
        }

        func share(_ v: Float) -> Double {
            guard full > 0 else { return 0 }
            return KnobTaperProbe.distance(KnobTaperProbe.render(p, v, c), dry) / full
        }

        /// The change at the top against the dry sound, in dB (how big "100%" is).
        var fullDB: Double {
            20 * log10(max(full, 1e-12) / max(KnobTaperProbe.size(dry), 1e-12))
        }
    }

    /// How far each knob may be from its own position, as a share of its full effect (3 points; Texture's
    /// INSTABILITY 4, its stutters are random 1/16s). Measured on Linux on Nov 14: every knob within 2.2.
    static func tolerance(_ p: KParam) -> Double { p == .instability ? 0.04 : 0.03 }

    /// The measured effect at every knob position 0%...100% (the self-test's sweep), through the taper.
    /// The 100 renders run side by side on every core (each its own processor).
    static func sweep(_ p: KParam, _ c: KnobContext) -> [Double] {
        let curve = Curve(p, c)
        var out = [Double](repeating: 0, count: 101)
        out.withUnsafeMutableBufferPointer { o in
            let base = o.baseAddress!
            DispatchQueue.concurrentPerform(iterations: 100) { i in
                base[i + 1] = curve.share(KnobTaper.value(p, knob: Float(i + 1) / 100, c))
            }
        }
        return out
    }

    /// In-place radix-2 FFT (n a power of two).
    static func fft(_ re: inout [Float], _ im: inout [Float]) {
        let n = re.count
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 { j ^= bit; bit >>= 1 }
            j |= bit
            if i < j { re.swapAt(i, j); im.swapAt(i, j) }
        }
        var len = 2
        while len <= n {
            let angle = -2 * Float.pi / Float(len)
            let wr = cosf(angle), wi = sinf(angle)
            var start = 0
            while start < n {
                var cr: Float = 1, ci: Float = 0
                for k in 0..<len / 2 {
                    let a = start + k, b = a + len / 2
                    let tr = re[b] * cr - im[b] * ci, ti = re[b] * ci + im[b] * cr
                    re[b] = re[a] - tr; im[b] = im[a] - ti
                    re[a] += tr; im[a] += ti
                    let ncr = cr * wr - ci * wi
                    ci = cr * wi + ci * wr
                    cr = ncr
                }
                start += len
            }
            len <<= 1
        }
    }
}
