// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

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
