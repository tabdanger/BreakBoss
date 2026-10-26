// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - The sound of each faceplate, and the seven knobs on the bottom row
//
// MODERN   clean, hard-hitting, forward.
// VINTAGE  the same knobs, plus built-in drive and boost: tape saturation, a low-end bump and a
//          rolled-off top like an old sampler.
// TEXTURE  the same knobs, plus a downsampled (lower sample rate, 12-bit) sound, instability
//          (tape wow and flutter, and the warp below), a tempo-synced delay and a gated reverb.
//          WARP: every bar or two it rolls a new scene (how far the pitch swings up and down, how
//          fast it wobbles, its shape, how hard the resonant filter sweeps against it). GLITCH: some
//          1/16s stutter. Oct 17 (Face 2's Texture knobs): WARP and GLITCH have their own knobs
//          (they used to follow INSTABILITY), the reverb has DECAY and PRE-DELAY, and a double tap on
//          DELAY frees it from the tempo (300 ms) or locks it back to a dotted 1/8.
//
// Oct 24 (Tyrone): each mode has its own seven-knob section (TrackFX.params); DRIVE replaces BOOST
// in Vintage and Texture. Settings.keepSection keeps the other modes' knobs out of the sound.
//
// BOOST    low-end and level push into the chain.
// DRIVE    BOOST's push plus tape saturation into the GRIT stage (Vintage, Texture).
// PUNCH    transient shaper: louder attacks, a little less sustain.
// ANALOG EQ  console-style curve: tight low shelf, scooped low-mids, airy top.
// GRIT     saturation (2x oversampled so it doesn't alias).
// SHINE    high-frequency exciter.
// TIGHTEN  shortens every drum's tail (done per voice in the engine).
// NOISE    hiss / crackle under the drums; follows the drums so silence stays silent.
//
// All buffers are made in init(); process() never allocates.
//
// Oct 19 (Tyrone): each track on Face 2 has its own copy of these knobs. A track's copy is an
// insert on that track (`Settings.insert`): only what its own knobs add, none of the mode's fixed
// colour (Vintage's tape and bump, Texture's grit), which the main chain already gives every drum.
// So a track with its knobs at zero sounds exactly as it did.

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
    private let delaySize: Int
    private let delayL: UnsafeMutablePointer<Float>
    private let delayR: UnsafeMutablePointer<Float>
    private var delayIndex = 0
    private var delayLP = [OnePole(), OnePole()]
    private var delaySamples = Smoothed(12_000)
    // Texture: gated reverb
    private var verb: GatedReverb
    // Texture: WARP. A two-head pitch shifter whose pitch swings up and down, a resonant filter
    // sweeping against it, and stutters that repeat the start of a 1/16. Its settings are a
    // random "scene" that changes every bar or two.
    private let warpSize: Int
    private let warpL: UnsafeMutablePointer<Float>
    private let warpR: UnsafeMutablePointer<Float>
    private var warpIndex = 0
    private var warpHead: Float = 0
    private var warpWindow: Float = 2_400
    private var warpRatio: Float = 1
    private var wobblePhase: Double = 0
    private var warpFilter = [StateVariableFilter(), StateVariableFilter()]
    private var warpControl = 0
    private var warpMix = Smoothed(0)
    private let stutterSize: Int
    private let stutterL: UnsafeMutablePointer<Float>
    private let stutterR: UnsafeMutablePointer<Float>
    private var stutterIndex = 0
    private var glitchBeat: Double = 0
    private var stutterStep = Int.min
    private var stutterOn = false
    private var stutterStart = 0
    private var stutterLength = 1
    private var stutterPos = 0
    private var stutterReverse = false
    private var stutterMix = Smoothed(0)
    private var glitchRNG = KRandom(seed: 0x6A17C4)
    private var sceneSteps = 0              // 1/16s left in this scene
    private var sceneRate: Double = 1       // wobbles per beat
    private var sceneSemis: Float = 0       // how far the pitch swings, either way
    private var sceneShape = 0              // 0 sine, 1 triangle, 2 random steps
    private var sceneBand: Float = 0        // how much of the sweep is the resonant band-pass
    private var sceneHold: Float = 0        // the current random step (shape 2)
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

    /// `compact`: a track's insert (Face 2). Shorter delay and stutter memory (still more than the
    /// longest dotted 1/8 and stutter at 40 BPM, 48 kHz), so twelve tracks stay light.
    init(compact: Bool = false) {
        delaySize = compact ? 65_536 : 262_144
        warpSize = 16_384
        stutterSize = compact ? 32_768 : 131_072
        wow = .allocate(capacity: wowSize)
        wow.initialize(repeating: 0, count: wowSize)
        delayL = .allocate(capacity: delaySize)
        delayR = .allocate(capacity: delaySize)
        delayL.initialize(repeating: 0, count: delaySize)
        delayR.initialize(repeating: 0, count: delaySize)
        warpL = .allocate(capacity: warpSize)
        warpR = .allocate(capacity: warpSize)
        warpL.initialize(repeating: 0, count: warpSize)
        warpR.initialize(repeating: 0, count: warpSize)
        stutterL = .allocate(capacity: stutterSize)
        stutterR = .allocate(capacity: stutterSize)
        stutterL.initialize(repeating: 0, count: stutterSize)
        stutterR.initialize(repeating: 0, count: stutterSize)
        verb = GatedReverb()
        prepare(sampleRate: 48_000)
    }

    deinit {
        wow.deallocate()
        delayL.deallocate()
        delayR.deallocate()
        warpL.deallocate()
        warpR.deallocate()
        stutterL.deallocate()
        stutterR.deallocate()
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
        warpWindow = min(Float(warpSize - 8), sr * 0.05)     // 50 ms grains
        warpMix.configure(ms: 40, sr: sr)
        stutterMix.configure(ms: 3, sr: sr)
        for c in 0..<2 { warpFilter[c].set(1_200, q: 0.8, sr: sr) }
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
        warpL.update(repeating: 0, count: warpSize)
        warpR.update(repeating: 0, count: warpSize)
        stutterL.update(repeating: 0, count: stutterSize)
        stutterR.update(repeating: 0, count: stutterSize)
        for c in 0..<2 { warpFilter[c].reset() }
        warpMix.jump(0); stutterMix.jump(0)
        stutterOn = false; stutterStep = Int.min; warpHead = 0; warpRatio = 1; sceneSteps = 0
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
        var resample: Float = 0
        var instability: Float = 0
        var delay: Float = 0
        var reverb: Float = 0
        var drive: Float = 0
        var warp: Float = 0
        var glitch: Float = 0
        var reverbDecay: Float = 0.5
        var reverbPredelay: Float = 0
        var delaySync = true
        /// A track's own knobs (Face 2): only what they add, without the mode's fixed colour.
        var insert = false
        /// The transport's beat at this block's first sample, while playing (stutters land on its 1/16s).
        var beat: Double?

        /// Texture's own lo-fi sound under its knobs: RESAMPLE and INSTABILITY at zero sound like
        /// they used to at their old 50% start, and turn up from there to the same top.
        static let textureBase: Float = 0.5
        static func textureAmount(_ knob: Float) -> Float { textureBase + knob.clamped(0, 1) * (1 - textureBase) }

        /// The mode's own sound with every FX knob at 0% (Tyrone, Oct 26: the knobs are the extra
        /// sauce, they only touch the sound once turned up). The main chain only, before
        /// keepSection: Vintage's tape and bump are already fixed in process(); Texture's
        /// downsampling and wow (and the warp and stutters that follow INSTABILITY) sit under its
        /// knobs. DELAY and GATED REVERB stay off until they're turned up.
        mutating func addModeSound() {
            guard mode == .texture else { return }
            resample = Settings.textureAmount(resample)
            instability = Settings.textureAmount(instability)
        }

        /// Only the mode's own FX section reaches the sound (Tyrone, Oct 24; TrackFX.params), so a
        /// knob left turned in another mode can't colour this one. DRIVE (Vintage, Texture) takes
        /// BOOST's push (level and low shelf) on top of its tape saturation; Texture's INSTABILITY
        /// also warps and stutters, its reverb at the middle DECAY and no PRE-DELAY.
        mutating func keepSection() {
            switch mode {
            case .modern:
                drive = 0
            case .vintage:
                boost = drive
            case .texture:
                boost = drive; punch = 0; analogEQ = 0; grit = 0
                warp = instability; glitch = instability
                reverbDecay = KParam.reverbDecay.defaultValue; reverbPredelay = KParam.reverbPredelay.defaultValue
            }
        }
    }

    /// Processes `count` stereo samples in place.
    func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, count: Int, _ s: Settings) {
        let mode = s.mode
        updateCoefficients(s)
        let vintage = mode == .vintage
        // the mode's fixed colour (the main chain's, not a track's insert)
        let colour = !s.insert
        let tape = vintage && colour
        // a track's insert skips the Texture section while all its Texture knobs are at zero
        let texture = mode == .texture && (colour || max(s.resample, s.instability, s.delay, s.reverb, s.warp, s.glitch) > 0.001)

        // Gains
        let boostGain = 1 + s.boost * 0.6 + (tape ? 0.35 : 0)
        let punchAmount = s.punch * 1.6
        let gritAmount = s.grit + ((vintage || mode == .texture) ? s.drive * 0.8 : 0) + (tape ? 0.38 : 0) + (texture && colour ? 0.12 : 0)
        let drive = 1 + gritAmount * 6
        let gritMakeup = 1 / Saturate.soft(drive) * 0.95
        let gritMix = min(1, gritAmount * 2.2)
        let shineAmount = s.shine * 0.55
        let noiseLevel = s.noise * s.noise * 0.06
        // Texture delay: dotted 1/8 at the current tempo, or 300 ms when it's freed from the tempo
        let beat = 60.0 / max(s.tempo, 40)
        let delaySeconds = s.delaySync ? beat * 0.75 : 0.3
        delaySamples.set(Float(min(Double(delaySize - 4), delaySeconds * Double(sr))))
        verb.set(decay: s.reverbDecay, predelay: s.reverbPredelay)
        let dsStep = texture ? min(1, (sr * powf(18_900 / sr, s.resample * 2)) / sr) : 1   // hold-and-sample down to ~19 kHz
        let wowDepth: Float = sr * 0.0022 * s.instability, flutterDepth: Float = sr * 0.00024 * s.instability
        let quantization = powf(2, 15 - s.resample * 8)
        // WARP: wider swings and more resonance; GLITCH: more stutters.
        let warp = texture ? s.warp.clamped(0, 1) : 0
        let glitch = texture ? s.glitch.clamped(0, 1) : 0
        if warp <= 0.001 { warpMix.set(0); sceneSteps = 0 }
        if glitch <= 0.001 { stutterOn = false }
        let beatsPerSample = max(s.tempo, 40) / 60 / Double(sr)
        let warpQ = 0.8 + warp * 3
        let stutterChance = glitch * glitch * 0.4
        if let b = s.beat { glitchBeat = b }

        for i in 0..<count {
            var l = left[i] * boostGain, r = right[i] * boostGain
            l = boostShelf[0].process(l); r = boostShelf[1].process(r)

            if tape {
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

            if tape {
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
                    held = ((dl * quantization).rounded() / quantization, (dr * quantization).rounded() / quantization)
                }
                if s.resample > 0.001 { l = held.0; r = held.1 }
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
                if s.instability > 0.001 { l = mid + side; r = mid - side }
                // WARP
                warpL[warpIndex] = l; warpR[warpIndex] = r
                if warpMix.target > 0 || warpMix.value > 0 {
                    let (wl, wr) = warpSample(warpQ: warpQ)
                    let m = warpMix.next()
                    l += (wl - l) * m
                    r += (wr - r) * m
                }
                warpIndex = (warpIndex + 1) & (warpSize - 1)
                wobblePhase += sceneRate * beatsPerSample
                if wobblePhase >= 1 { wobblePhase -= 1; sceneHold = glitchRNG.bipolar() }
                // Stutters: on some 1/16s the first 1/32 (or 1/48, 1/64) repeats, sometimes backwards.
                stutterL[stutterIndex] = l; stutterR[stutterIndex] = r
                let step = Int((glitchBeat * 4).rounded(.down))
                if step != stutterStep {
                    stutterStep = step
                    if warp > 0.001 {
                        sceneSteps -= 1
                        if sceneSteps <= 0 { rollScene(warp) }
                    }
                    stutterOn = glitch > 0.001 && glitchRNG.unit() < stutterChance
                    if stutterOn {
                        let pick = glitchRNG.int(4)
                        let fraction = pick < 2 ? 0.125 : (pick == 2 ? 1.0 / 12 : 0.0625)   // of a beat
                        stutterLength = Int(fraction / beatsPerSample).clamped(256, stutterSize / 4)
                        stutterStart = stutterIndex
                        stutterPos = 0
                        stutterReverse = glitchRNG.chance(0.3)
                    }
                }
                stutterMix.set(stutterOn && stutterPos >= stutterLength ? 1 : 0)
                if stutterOn || stutterMix.value > 0 {
                    let q = stutterPos % stutterLength
                    let at = (stutterStart + (stutterReverse ? stutterLength - 1 - q : q)) & (stutterSize - 1)
                    // A short fade at each repeat's edges keeps the loop seams from clicking.
                    let edge = min(1, Float(min(q, stutterLength - 1 - q)) / 48)
                    let m = stutterMix.next()
                    l += (stutterL[at] * edge - l) * m
                    r += (stutterR[at] * edge - r) * m
                    stutterPos += 1
                }
                stutterIndex = (stutterIndex + 1) & (stutterSize - 1)
                glitchBeat += beatsPerSample
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
                l += el * s.delay * 0.5 + vl * s.reverb * 0.6
                r += er * s.delay * 0.5 + vr * s.reverb * 0.6
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

    /// A new WARP scene, every one or two bars: wobble speed (1/2 to 1/32), swing (2 to 12
    /// semitones), shape, filter, and how much of it you hear (sometimes none: only stutters).
    private func rollScene(_ amount: Float) {
        sceneSteps = 16 * (1 + glitchRNG.int(2))
        sceneRate = 0.5 * pow(2, Double(glitchRNG.int(5)))
        sceneSemis = amount * glitchRNG.range(2, 12)
        sceneShape = glitchRNG.int(3)
        sceneBand = glitchRNG.range(0, 0.7) * amount
        warpMix.set(glitchRNG.chance(0.25) ? 0 : min(0.85, amount * glitchRNG.range(0.6, 1.6)))
    }

    /// One sample of WARP's wet signal: pitch shifted by the wobble, through the swept filter.
    @inline(__always)
    private func warpSample(warpQ: Float) -> (Float, Float) {
        // Pitch and filter move at control rate (every 16 samples).
        warpControl -= 1
        if warpControl <= 0 {
            warpControl = 16
            let lfo: Float, sweep: Float
            switch sceneShape {
            case 0:     // sine; the filter a quarter-cycle behind, opening as the pitch passes the middle
                lfo = Float(sin(2 * Double.pi * wobblePhase))
                sweep = Float(cos(2 * Double.pi * wobblePhase))
            case 1:     // triangle; the filter against it
                lfo = Float(4 * abs(wobblePhase - 0.5) - 1)
                sweep = -lfo
            default:    // random steps, a new one each wobble; the filter falls through each step
                lfo = sceneHold
                sweep = Float(1 - 2 * wobblePhase)
            }
            warpRatio = exp2f(sceneSemis * lfo / 12)
            let cutoff = 300 * powf(9_000 / 300, 0.5 + 0.5 * sweep)
            for c in 0..<2 { warpFilter[c].set(cutoff, q: warpQ, sr: sr) }
        }
        // Two read heads half a grain apart, each faded in and out (they sum to 1).
        warpHead += (1 - warpRatio) / warpWindow
        if warpHead >= 1 { warpHead -= 1 } else if warpHead < 0 { warpHead += 1 }
        var wl: Float = 0, wr: Float = 0
        for head in 0..<2 {
            var p = warpHead + Float(head) * 0.5
            if p >= 1 { p -= 1 }
            let g = 0.5 - 0.5 * cosf(2 * .pi * p)
            let at = Float(warpIndex) - (2 + p * warpWindow)
            wl += readInterpolated(warpL, warpSize, at) * g
            wr += readInterpolated(warpR, warpSize, at) * g
        }
        let (ll, lb) = warpFilter[0].process(wl)
        let (rl, rb) = warpFilter[1].process(wr)
        let band = sceneBand
        return (Saturate.soft(ll * (1 - band * 0.5) + lb * band), Saturate.soft(rl * (1 - band * 0.5) + rb * band))
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
        let modeKey = s.mode.rawValue + (s.insert ? 8 : 0)
        if abs(s.boost - lastBoost) > 0.001 || modeKey != lastMode {
            let db = s.boost * 6 + (s.mode == .vintage && !s.insert ? 1.5 : 0)
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
        lastMode = modeKey
    }
}

/// A small reverb (four combs, two all-passes per side) whose output is gated: it opens on each
/// hit, holds (DECAY: about 60 to 600 ms, 170 ms in the middle), then shuts quickly. The 80s
/// "gated" sound, used by TEXTURE. PRE-DELAY (0 to 120 ms) holds the hit back before it reaches the room.
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
    private var feedback: Float = 0.82
    private var sr: Float = 48_000
    private var pre: [Float] = []
    private var preIndex = 0
    private var preSamples = 0

    mutating func prepare(sampleRate sr: Float) {
        let combMs: [Float] = [25.3, 26.9, 28.9, 30.7, 25.9, 27.7, 29.5, 31.9]
        let apMs: [Float] = [5.0, 1.7, 5.3, 1.9]
        combs = combMs.map { [Float](repeating: 0, count: max(1, Int($0 * 0.001 * sr))) }
        aps = apMs.map { [Float](repeating: 0, count: max(1, Int($0 * 0.001 * sr))) }
        combIndex = [Int](repeating: 0, count: 8)
        apIndex = [Int](repeating: 0, count: 4)
        env.set(attackMs: 1, releaseMs: 40, sr: sr)
        self.sr = sr
        holdSamples = Int(0.17 * sr)
        closeCoef = expf(-1 / (0.025 * sr))
        pre = [Float](repeating: 0, count: max(2, Int(0.125 * sr)))
        preIndex = 0
    }

    /// DECAY and PRE-DELAY knobs, 0...1. Decay 0.5 is the original sound (170 ms hold, 0.82 feedback).
    mutating func set(decay: Float, predelay: Float) {
        let d = decay.clamped(0, 1)
        holdSamples = Int(sr * 0.06 * powf(10, d * 1.0))                 // 60 ms ... 600 ms (190 at 0.5)
        if abs(d - 0.5) < 0.01 { holdSamples = Int(0.17 * sr) }
        feedback = 0.7 + 0.24 * d                                          // 0.70 ... 0.94 (0.82 at 0.5)
        closeCoef = expf(-1 / ((0.015 + 0.06 * d) * sr))                   // shuts in 15 ... 75 ms
        if abs(d - 0.5) < 0.01 { closeCoef = expf(-1 / (0.025 * sr)) }
        preSamples = min(pre.count - 1, Int(predelay.clamped(0, 1) * 0.12 * sr))
    }

    mutating func reset() {
        for i in combs.indices { for j in combs[i].indices { combs[i][j] = 0 } }
        for i in aps.indices { for j in aps[i].indices { aps[i][j] = 0 } }
        for i in pre.indices { pre[i] = 0 }
        combLP = [Float](repeating: 0, count: 8)
        gate = 0
        hold = 0
    }

    mutating func process(_ l: Float, _ r: Float) -> (Float, Float) {
        guard combs.count == 8 else { return (0, 0) }
        var input = (l + r) * 0.5
        if preSamples > 0, !pre.isEmpty {
            pre[preIndex] = input
            var at = preIndex - preSamples
            if at < 0 { at += pre.count }
            input = pre[at]
            preIndex += 1
            if preIndex == pre.count { preIndex = 0 }
        }
        let e = env.process(input)
        if e > 0.12 { hold = holdSamples; gate = 1 }
        if hold > 0 { hold -= 1 } else { gate *= closeCoef }
        var outs: (Float, Float) = (0, 0)
        for c in 0..<8 {
            let n = combs[c].count
            let y = combs[c][combIndex[c]]
            combLP[c] = y + 0.3 * (combLP[c] - y)
            combs[c][combIndex[c]] = input + combLP[c] * feedback
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
    // Each point keeps the average (the line), the lowest and highest sample it covers (the
    // band a hi-hat's fizz fills, like a real scope's phosphor) and how loud its lows and highs
    // are (bass under 150 Hz, top over 2.5 kHz), so the screen can follow what's playing.
    static let scopeSize = 1024
    let scope: UnsafeMutablePointer<Float>
    let scopeLow: UnsafeMutablePointer<Float>
    let scopeHigh: UnsafeMutablePointer<Float>
    let scopeBass: UnsafeMutablePointer<Float>
    let scopeTop: UnsafeMutablePointer<Float>
    private(set) var scopeWrite = 0
    /// Counts clearScope calls, so the screen's copy knows to take the whole ring again.
    private(set) var scopeCleared = 0
    private var scopeAccum: Float = 0
    private var scopeMin: Float = 0
    private var scopeMax: Float = 0
    private var bassAccum: Float = 0
    private var topAccum: Float = 0
    private var bassLP: Float = 0
    private var topLP: Float = 0
    private var bassCoef: Float = 0.02
    private var topCoef: Float = 0.28
    private var scopeCount = 0
    private var scopeDecimate = 8

    init() {
        scope = .allocate(capacity: MasterBus.scopeSize)
        scopeLow = .allocate(capacity: MasterBus.scopeSize)
        scopeHigh = .allocate(capacity: MasterBus.scopeSize)
        scopeBass = .allocate(capacity: MasterBus.scopeSize)
        scopeTop = .allocate(capacity: MasterBus.scopeSize)
        for ring in [scope, scopeLow, scopeHigh, scopeBass, scopeTop] { ring.initialize(repeating: 0, count: MasterBus.scopeSize) }
        prepare(sampleRate: 48_000)
    }

    deinit { for ring in [scope, scopeLow, scopeHigh, scopeBass, scopeTop] { ring.deallocate() } }

    /// Silence on the screen (the engine stops calling process when nothing has played for a while).
    func clearScope() {
        guard scopeHigh[(scopeWrite - 1) & (MasterBus.scopeSize - 1)] != 0
                || scopeLow[(scopeWrite - 1) & (MasterBus.scopeSize - 1)] != 0 else { return }
        scope.update(repeating: 0, count: MasterBus.scopeSize)
        scopeLow.update(repeating: 0, count: MasterBus.scopeSize)
        scopeHigh.update(repeating: 0, count: MasterBus.scopeSize)
        scopeBass.update(repeating: 0, count: MasterBus.scopeSize)
        scopeTop.update(repeating: 0, count: MasterBus.scopeSize)
        scopeCleared &+= 1
        scopeAccum = 0; scopeCount = 0; scopeMin = 0; scopeMax = 0; bassAccum = 0; topAccum = 0
        bassLP = 0; topLP = 0
    }

    func prepare(sampleRate: Double) {
        sr = Float(sampleRate)
        cutoff.configure(ms: 30, sr: sr)
        drive.configure(ms: 20, sr: sr)
        output.configure(ms: 20, sr: sr)
        scopeDecimate = max(1, Int(sampleRate / 6_000))
        bassCoef = 1 - exp(-2 * .pi * 150 / sr)
        topCoef = 1 - exp(-2 * .pi * 2_500 / sr)
        lastCutoff = -1
        for c in 0..<2 { filter[c].reset() }
    }

    struct Settings {
        var filter: Float = 1
        var clipDrive: Float = 0
        var output: Float = 0.75
        var clipperOn = true
    }

    /// The clipper's ceiling: -0.3 dBFS.
    static let ceiling: Float = 0.966

    func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, count: Int, _ s: Settings) {
        let open = s.filter > 0.995
        cutoff.set(KnockMath.filterCutoff(s.filter))
        drive.set(KnockMath.dbToGain(KnockMath.clipDriveDB(s.clipDrive)))
        output.set(KnockMath.dbToGain(KnockMath.outputDB(s.output)))
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
            let m = (l + r) * 0.5
            if scopeCount == 0 { scopeMin = m; scopeMax = m }
            scopeAccum += m
            scopeMin = min(scopeMin, m); scopeMax = max(scopeMax, m)
            bassLP += (m - bassLP) * bassCoef
            topLP += (m - topLP) * topCoef
            let top = m - topLP
            bassAccum += bassLP * bassLP
            topAccum += top * top
            scopeCount += 1
            if scopeCount >= scopeDecimate {
                let c = Float(scopeCount)
                scope[scopeWrite] = scopeAccum / c
                scopeLow[scopeWrite] = scopeMin
                scopeHigh[scopeWrite] = scopeMax
                scopeBass[scopeWrite] = (bassAccum / c).squareRoot()
                scopeTop[scopeWrite] = (topAccum / c).squareRoot()
                scopeWrite = (scopeWrite + 1) & (MasterBus.scopeSize - 1)
                scopeAccum = 0; bassAccum = 0; topAccum = 0
                scopeCount = 0
            }
        }
    }
}
