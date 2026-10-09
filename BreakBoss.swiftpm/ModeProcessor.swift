// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - The sound of each faceplate, and the seven knobs on the bottom row
//
// MODERN   clean, hard-hitting, forward.
// VINTAGE  the same knobs, plus built-in drive and boost: tape saturation, a low-end bump and a
//          rolled-off top like an old sampler.
// TEXTURE  the same knobs, plus a downsampled (lower sample rate, 12-bit) sound, instability
//          (tape wow and flutter), a tempo-synced delay and a gated reverb.
//
// BOOST    low-end and level push into the chain.
// PUNCH    transient shaper: louder attacks, a little less sustain.
// ANALOG EQ  console-style curve: tight low shelf, scooped low-mids, airy top.
// GRIT     saturation (2x oversampled so it doesn't alias).
// SHINE    high-frequency exciter.
// TIGHTEN  shortens every drum's tail (done per voice in the engine).
// NOISE    hiss / crackle under the drums; follows the drums so silence stays silent.
//
// All buffers are made in init(); process() never allocates.

final class BusProcessor {
    private var sr: Float = 48_000

    // Boost / Vintage
    private var boostShelf = [Biquad(), Biquad()]
    private var headBump = [Biquad(), Biquad()]
    private var tapeLP = [Biquad(), Biquad()]
    // Punch
    private var fast = EnvelopeFollower()
    private var slow = EnvelopeFollower()
    // Analog EQ
    private var eqLow = [Biquad(), Biquad()]
    private var eqMid = [Biquad(), Biquad()]
    private var eqHigh = [Biquad(), Biquad()]
    // Grit (+ Vintage tape) at 2x
    private var oversample = [HalfBandOversampler(), HalfBandOversampler()]
    // Shine
    private var shineHP = [Biquad(), Biquad()]
    private var shineShelf = [Biquad(), Biquad()]
    // Texture: downsampling
    private var holdPhase: Float = 0
    private var held: (Float, Float) = (0, 0)
    private var preDS = [Biquad(), Biquad()]
    // Texture: instability (modulated short delay)
    private let wowSize = 4096
    private let wow: UnsafeMutablePointer<Float>
    private var wowIndex = 0
    private var wowPhase: Float = 0
    private var flutterPhase: Float = 0
    private var drift: Float = 0
    private var driftTarget: Float = 0
    private var driftCount = 0
    // Texture: tempo-synced delay
    private let delaySize = 262_144
    private let delayL: UnsafeMutablePointer<Float>
    private let delayR: UnsafeMutablePointer<Float>
    private var delayIndex = 0
    private var delayLP = [OnePole(), OnePole()]
    private var delaySamples = Smoothed(12_000)
    // Texture: gated reverb
    private var verb: GatedReverb
    // Noise
    private var rng = KRandom(seed: 0xC0FFEE)
    private var noiseEnv = EnvelopeFollower()
    private var hissLP = [OnePole(), OnePole()]
    private var hissHP = [OnePole(), OnePole()]
    private var crackle: Float = 0
    // Clean-up
    private var dcBlock = [OnePole(), OnePole()]

    // Last settings (coefficients are only recomputed when something moves)
    private var lastBoost: Float = -1, lastEQ: Float = -1, lastShine: Float = -1, lastMode = -1

    init() {
        wow = .allocate(capacity: wowSize)
        wow.initialize(repeating: 0, count: wowSize)
        delayL = .allocate(capacity: delaySize)
        delayR = .allocate(capacity: delaySize)
        delayL.initialize(repeating: 0, count: delaySize)
        delayR.initialize(repeating: 0, count: delaySize)
        verb = GatedReverb()
        prepare(sampleRate: 48_000)
    }

    deinit {
        wow.deallocate()
        delayL.deallocate()
        delayR.deallocate()
    }

    func prepare(sampleRate: Double) {
        sr = Float(sampleRate)
        fast.set(attackMs: 0.3, releaseMs: 18, sr: sr)
        slow.set(attackMs: 12, releaseMs: 120, sr: sr)
        noiseEnv.set(attackMs: 2, releaseMs: 380, sr: sr)
        for c in 0..<2 {
            headBump[c].peak(95, q: 0.9, db: 2.5, sr: sr)
            tapeLP[c].lowPass(12_500, q: 0.6, sr: sr)
            preDS[c].lowPass(8_200, q: 0.7, sr: sr)
            shineHP[c].highPass(3_500, q: 0.7, sr: sr)
            delayLP[c].setCutoff(3_800, sr: sr)
            hissLP[c].setCutoff(7_000, sr: sr)
            hissHP[c].setCutoff(1_800, sr: sr)
            dcBlock[c].setCutoff(18, sr: sr)
        }
        delaySamples.configure(ms: 60, sr: sr)
        verb.prepare(sampleRate: sr)
        lastBoost = -1; lastEQ = -1; lastShine = -1; lastMode = -1
        reset()
    }

    func reset() {
        for c in 0..<2 {
            boostShelf[c].reset(); headBump[c].reset(); tapeLP[c].reset()
            eqLow[c].reset(); eqMid[c].reset(); eqHigh[c].reset()
            shineHP[c].reset(); shineShelf[c].reset(); preDS[c].reset()
        }
        wow.update(repeating: 0, count: wowSize)
        delayL.update(repeating: 0, count: delaySize)
        delayR.update(repeating: 0, count: delaySize)
        verb.reset()
        fast.value = 0; slow.value = 0; noiseEnv.value = 0
    }

    struct Settings {
        var mode: SoundMode = .modern
        var boost: Float = 0
        var punch: Float = 0
        var analogEQ: Float = 0
        var grit: Float = 0
        var shine: Float = 0
        var noise: Float = 0
        var tempo: Double = 120
    }

    /// Processes `count` stereo samples in place.
    func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, count: Int, _ s: Settings) {
        let mode = s.mode
        updateCoefficients(s)
        let vintage = mode == .vintage
        let texture = mode == .texture

        // Gains
        let boostGain = 1 + s.boost * 0.6 + (vintage ? 0.35 : 0)
        let punchAmount = s.punch * 1.6
        let gritAmount = s.grit + (vintage ? 0.38 : 0) + (texture ? 0.12 : 0)
        let drive = 1 + gritAmount * 6
        let gritMakeup = 1 / Saturate.soft(drive) * 0.95
        let gritMix = min(1, gritAmount * 2.2)
        let shineAmount = s.shine * 0.55
        let noiseLevel = s.noise * s.noise * 0.06
        // Texture delay: dotted 1/8 at the current tempo
        let beat = 60.0 / max(s.tempo, 40)
        delaySamples.set(Float(min(Double(delaySize - 4), beat * 0.75 * Double(sr))))
        let dsStep = texture ? Float(18_900) / sr : 1   // hold-and-sample down to ~19 kHz
        let wowDepth: Float = sr * 0.0011, flutterDepth: Float = sr * 0.00012

        for i in 0..<count {
            var l = left[i] * boostGain, r = right[i] * boostGain
            l = boostShelf[0].process(l); r = boostShelf[1].process(r)

            if vintage {
                l = headBump[0].process(l); r = headBump[1].process(r)
            }

            // PUNCH: attack = fast envelope above slow envelope
            if punchAmount > 0.001 {
                let level = max(abs(l), abs(r))
                let f = fast.process(level), sl = slow.process(level)
                let ratio = (f + 1e-5) / (sl + 1e-5)
                var g = powf(ratio, punchAmount * 0.55)
                g = min(g, 2.8)                     // at most about +9 dB on attacks
                let sustainCut = 1 - 0.18 * s.punch * (ratio < 1.05 ? 1 : 0)
                l *= g * sustainCut; r *= g * sustainCut
            }

            // ANALOG EQ
            if s.analogEQ > 0.001 {
                l = eqHigh[0].process(eqMid[0].process(eqLow[0].process(l)))
                r = eqHigh[1].process(eqMid[1].process(eqLow[1].process(r)))
            }

            // GRIT (+ Vintage tape drive), 2x oversampled
            if gritMix > 0.001 {
                let tapeBias: Float = vintage ? 0.14 : 0.05
                let wl = oversample[0].process(l) { Saturate.tape($0 * drive, bias: tapeBias) * gritMakeup }
                let wr = oversample[1].process(r) { Saturate.tape($0 * drive, bias: tapeBias) * gritMakeup }
                // The oversampler delays by 15 samples; the dry share is small and blends in.
                l = l * (1 - gritMix) + wl * gritMix
                r = r * (1 - gritMix) + wr * gritMix
            }

            if vintage {
                l = tapeLP[0].process(l); r = tapeLP[1].process(r)
            }

            // SHINE
            if shineAmount > 0.001 {
                let hl = shineHP[0].process(l), hr = shineHP[1].process(r)
                l += Saturate.soft(hl * 3) * shineAmount
                r += Saturate.soft(hr * 3) * shineAmount
                l = shineShelf[0].process(l); r = shineShelf[1].process(r)
            }

            // TEXTURE
            if texture {
                // Downsample: low-pass, sample-and-hold, 12-bit.
                let dl = preDS[0].process(l), dr = preDS[1].process(r)
                holdPhase += dsStep
                if holdPhase >= 1 {
                    holdPhase -= 1
                    held = ((dl * 2048).rounded() / 2048, (dr * 2048).rounded() / 2048)
                }
                l = held.0; r = held.1
                // Instability: wow and flutter on a short delay.
                wowPhase += 0.55 / sr; if wowPhase > 1 { wowPhase -= 1 }
                flutterPhase += 6.8 / sr; if flutterPhase > 1 { flutterPhase -= 1 }
                driftCount -= 1
                if driftCount <= 0 { driftTarget = rng.bipolar(); driftCount = Int(sr * 0.4) }
                drift += (driftTarget - drift) * (3 / sr)
                let mod = wowDepth * (0.6 * sinf(2 * .pi * wowPhase) + 0.4 * drift) + flutterDepth * sinf(2 * .pi * flutterPhase)
                wowIndex = (wowIndex + 1) & (wowSize - 1)
                wow[wowIndex] = (l + r) * 0.5
                let side = (l - r) * 0.5
                let readPos = Float(wowIndex) - (sr * 0.004 + mod)
                let mid = readInterpolated(wow, wowSize, readPos)
                l = mid + side; r = mid - side
                // Gated reverb (send, then gate on the drums' envelope).
                let (vl, vr) = verb.process(l, r)
                // Delay: dotted 1/8, filtered feedback.
                let d = delaySamples.next()
                let rp = Float(delayIndex) - d
                let el = readInterpolated(delayL, delaySize, rp)
                let er = readInterpolated(delayR, delaySize, rp)
                delayL[delayIndex] = l + delayLP[0].lowPass(er) * 0.34   // ping-pong
                delayR[delayIndex] = r + delayLP[1].lowPass(el) * 0.34
                delayIndex += 1; if delayIndex == delaySize { delayIndex = 0 }
                l += el * 0.16 + vl * 0.3
                r += er * 0.16 + vr * 0.3
            }

            // NOISE, following the drums
            if noiseLevel > 0.000_01 {
                let env = noiseEnv.process(max(abs(l), abs(r)))
                let gate = min(1, env * 6)
                var nl = rng.bipolar(), nr = rng.bipolar()
                switch mode {
                case .modern:
                    nl = hissHP[0].highPass(nl); nr = hissHP[1].highPass(nr)
                case .vintage, .texture:
                    nl = hissLP[0].lowPass(nl); nr = hissLP[1].lowPass(nr)
                    // Crackle: sparse little clicks.
                    if rng.unit() < (mode == .vintage ? 0.0009 : 0.0005) { crackle = rng.bipolar() * 6 }
                    nl += crackle; nr += crackle * 0.8
                    crackle *= 0.55
                }
                l += nl * noiseLevel * gate
                r += nr * noiseLevel * gate
            }

            left[i] = dcBlock[0].highPass(l)
            right[i] = dcBlock[1].highPass(r)
        }
    }

    @inline(__always)
    private func readInterpolated(_ buffer: UnsafeMutablePointer<Float>, _ size: Int, _ position: Float) -> Float {
        var p = position
        while p < 0 { p += Float(size) }
        let i0 = Int(p) % size
        let frac = p - Float(Int(p))
        let i1 = (i0 + 1) % size
        return buffer[i0] + (buffer[i1] - buffer[i0]) * frac
    }

    private func updateCoefficients(_ s: Settings) {
        if abs(s.boost - lastBoost) > 0.001 || s.mode.rawValue != lastMode {
            let db = s.boost * 6 + (s.mode == .vintage ? 1.5 : 0)
            for c in 0..<2 { boostShelf[c].lowShelf(80, db: db, sr: sr) }
            lastBoost = s.boost
        }
        if abs(s.analogEQ - lastEQ) > 0.001 {
            for c in 0..<2 {
                eqLow[c].lowShelf(60, db: s.analogEQ * 4.5, sr: sr)
                eqMid[c].peak(360, q: 0.8, db: -s.analogEQ * 4, sr: sr)
                eqHigh[c].highShelf(10_000, db: s.analogEQ * 3.5, sr: sr)
            }
            lastEQ = s.analogEQ
        }
        if abs(s.shine - lastShine) > 0.001 {
            for c in 0..<2 { shineShelf[c].highShelf(12_000, db: s.shine * 4, sr: sr) }
            lastShine = s.shine
        }
        lastMode = s.mode.rawValue
    }
}

/// A small reverb (four combs, two all-passes per side) whose output is gated: it opens on each
/// hit, holds about 170 ms, then shuts quickly. The 80s "gated" sound, used by TEXTURE.
struct GatedReverb {
    private var combs: [[Float]] = []
    private var combIndex = [Int](repeating: 0, count: 8)
    private var combLP = [Float](repeating: 0, count: 8)
    private var aps: [[Float]] = []
    private var apIndex = [Int](repeating: 0, count: 4)
    private var env = EnvelopeFollower()
    private var hold = 0
    private var gate: Float = 0
    private var holdSamples = 8_000
    private var closeCoef: Float = 0.999

    mutating func prepare(sampleRate sr: Float) {
        let combMs: [Float] = [25.3, 26.9, 28.9, 30.7, 25.9, 27.7, 29.5, 31.9]
        let apMs: [Float] = [5.0, 1.7, 5.3, 1.9]
        combs = combMs.map { [Float](repeating: 0, count: max(1, Int($0 * 0.001 * sr))) }
        aps = apMs.map { [Float](repeating: 0, count: max(1, Int($0 * 0.001 * sr))) }
        combIndex = [Int](repeating: 0, count: 8)
        apIndex = [Int](repeating: 0, count: 4)
        env.set(attackMs: 1, releaseMs: 40, sr: sr)
        holdSamples = Int(0.17 * sr)
        closeCoef = expf(-1 / (0.025 * sr))
    }

    mutating func reset() {
        for i in combs.indices { for j in combs[i].indices { combs[i][j] = 0 } }
        for i in aps.indices { for j in aps[i].indices { aps[i][j] = 0 } }
        combLP = [Float](repeating: 0, count: 8)
        gate = 0
        hold = 0
    }

    mutating func process(_ l: Float, _ r: Float) -> (Float, Float) {
        guard combs.count == 8 else { return (0, 0) }
        let input = (l + r) * 0.5
        let e = env.process(input)
        if e > 0.12 { hold = holdSamples; gate = 1 }
        if hold > 0 { hold -= 1 } else { gate *= closeCoef }
        var outs: (Float, Float) = (0, 0)
        for c in 0..<8 {
            let n = combs[c].count
            let y = combs[c][combIndex[c]]
            combLP[c] = y + 0.3 * (combLP[c] - y)
            combs[c][combIndex[c]] = input + combLP[c] * 0.82
            combIndex[c] += 1
            if combIndex[c] == n { combIndex[c] = 0 }
            if c < 4 { outs.0 += y * 0.25 } else { outs.1 += y * 0.25 }
        }
        for a in 0..<4 {
            let n = aps[a].count
            let x = a < 2 ? outs.0 : outs.1
            let b = aps[a][apIndex[a]]
            let y = -0.6 * x + b
            aps[a][apIndex[a]] = x + 0.6 * y
            apIndex[a] += 1
            if apIndex[a] == n { apIndex[a] = 0 }
            if a < 2 { outs.0 = y } else { outs.1 = y }
        }
        return (outs.0 * gate, outs.1 * gate)
    }
}

// MARK: - Master section (top panel)

/// FILTER (low-pass, open at the top), CLIP DRIVE into the CLIPPER, then OUTPUT. Also feeds
/// the screen's waveform.
final class MasterBus {
    private var sr: Float = 48_000
    private var filter = [Biquad(), Biquad()]
    private var cutoff = Smoothed(20_000)
    private var lastCutoff: Float = -1
    private var drive = Smoothed(1)
    private var output = Smoothed(1)
    private var oversample = [HalfBandOversampler(), HalfBandOversampler()]
    private var counter = 0

    // Waveform for the screen: 1024 points, written here, read by the UI (tearing is harmless).
    static let scopeSize = 1024
    let scope: UnsafeMutablePointer<Float>
    private(set) var scopeWrite = 0
    private var scopeAccum: Float = 0
    private var scopeCount = 0
    private var scopeDecimate = 8

    init() {
        scope = .allocate(capacity: MasterBus.scopeSize)
        scope.initialize(repeating: 0, count: MasterBus.scopeSize)
        prepare(sampleRate: 48_000)
    }

    deinit { scope.deallocate() }

    func prepare(sampleRate: Double) {
        sr = Float(sampleRate)
        cutoff.configure(ms: 30, sr: sr)
        drive.configure(ms: 20, sr: sr)
        output.configure(ms: 20, sr: sr)
        scopeDecimate = max(1, Int(sampleRate / 6_000))
        lastCutoff = -1
        for c in 0..<2 { filter[c].reset() }
    }

    struct Settings {
        var filter: Float = 1
        var clipDrive: Float = 0.25
        var output: Float = 0.75
        var clipperOn = true
    }

    /// The clipper's ceiling: -0.3 dBFS.
    static let ceiling: Float = 0.966

    func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, count: Int, _ s: Settings) {
        let open = s.filter > 0.995
        cutoff.set(KnockMath.filterCutoff(s.filter))
        drive.set(KnockMath.dbToGain(KnockMath.clipDriveDB(s.clipDrive)))
        output.set(s.output <= 0.001 ? 0 : KnockMath.dbToGain(KnockMath.outputDB(s.output)))
        let ceiling = MasterBus.ceiling
        for i in 0..<count {
            var l = left[i], r = right[i]
            let fc = cutoff.next()
            if !open || fc < 19_000 {
                counter += 1
                if counter >= 16 || abs(fc - lastCutoff) > 200 && counter >= 4 {
                    counter = 0
                    if abs(fc - lastCutoff) > 0.5 {
                        for c in 0..<2 { filter[c].lowPass(fc, q: 0.85, sr: sr) }
                        lastCutoff = fc
                    }
                }
                l = filter[0].process(l); r = filter[1].process(r)
            }
            let g = drive.next()
            if s.clipperOn {
                l = oversample[0].process(l * g) { Saturate.clip($0, ceiling: ceiling, knee: 0.18) }
                r = oversample[1].process(r * g) { Saturate.clip($0, ceiling: ceiling, knee: 0.18) }
                // The half-band filter can ring a hair over the ceiling; hold the line.
                l = min(max(l, -ceiling), ceiling)
                r = min(max(r, -ceiling), ceiling)
            } else {
                l *= g; r *= g
            }
            let o = output.next()
            l *= o; r *= o
            left[i] = l; right[i] = r
            // Scope
            scopeAccum += (l + r) * 0.5
            scopeCount += 1
            if scopeCount >= scopeDecimate {
                scope[scopeWrite] = scopeAccum / Float(scopeCount)
                scopeWrite = (scopeWrite + 1) & (MasterBus.scopeSize - 1)
                scopeAccum = 0
                scopeCount = 0
            }
        }
    }
}
