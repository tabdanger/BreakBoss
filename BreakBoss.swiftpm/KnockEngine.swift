// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Per-pad settings (pad editor)

struct PadSettings: Codable, Equatable {
    /// 0...1, 0.8 = unity.
    var level: Float = 0.8
    /// -1 (left) ... 1 (right)
    var pan: Float = 0
    /// Semitones, -24 ... +24.
    var tune: Float = 0
    /// 0.05 ... 1 (1 = the sound's own length).
    var decay: Float = 1
    var reverse = false
    /// File name in the Samples folder when the pad holds your own sample.
    var sampleFile: String?

    var gain: Float { level <= 0.001 ? 0 : KnockMath.dbToGain(40 * log10f(level / 0.8)) }
}

/// The sounds on the 12 pads, ready for the audio thread (read-only once published).
final class KitBuffers {
    let name: String
    let samples: [SampleBuffer]
    let settings: [PadSettings]
    let bassHz: Float

    init(name: String, samples: [SampleBuffer], settings: [PadSettings], bassHz: Float) {
        self.name = name
        self.samples = samples
        self.settings = settings
        self.bassHz = bassHz
    }
}

/// Where the host's transport is (AUv3). Nil fields = the host didn't say.
struct HostTiming {
    var tempo: Double?
    var beat: Double?
    var playing: Bool?
}

// MARK: - The engine

/// Plays the pads and loops and runs the processing chain. One instance per app / plug-in; the
/// export renderer makes its own. `render` is the audio callback: no allocation, no locks that
/// wait, no Objective-C.
final class KnockEngine {
    static let maxVoices = 40
    static let maxBlockEvents = 512

    // Controls: the faceplate and host write, the audio thread reads.
    let params: UnsafeMutablePointer<Float>
    /// Tempo of the BPM display (the engine reads it; the controller sets it).
    let displayBPM: UnsafeMutablePointer<Double>

    // What the faceplate shows (written by the audio thread).
    /// 0 playing, 1 current loop (-1 none), 2 queued loop, 3 beat, 4 tempo, 5 host connected,
    /// 6 MIDI clock tempo (0 = none), 7 render count
    let status: UnsafeMutablePointer<Double>
    /// Incremented every time a pad sounds (the faceplate flashes it).
    let padHits: UnsafeMutablePointer<UInt32>

    let queue = EventQueue()
    let kitHandoff = Handoff<KitBuffers>()
    let patternHandoff = Handoff<PatternSet>()

    private(set) var sampleRate: Double = 48_000
    private var maxFrames = 4_096

    // Audio-thread state
    private var kit: KitBuffers?
    private var oldKit: KitBuffers?
    private var oldKitCountdown = 0
    private var retiringKit: KitBuffers?
    private var patterns: PatternSet?
    private var retiringPatterns: PatternSet?

    private let voices: UnsafeMutablePointer<Voice>
    private var voiceAge: UInt32 = 0
    private let mixL: UnsafeMutablePointer<Float>
    private let mixR: UnsafeMutablePointer<Float>
    private let blockEvents: UnsafeMutablePointer<BlockEvent>
    private var blockEventCount = 0

    let bus = BusProcessor()
    let master = MasterBus()

    // Transport
    private var playing = false
    private var beat: Double = 0
    private var currentLoop = -1
    private var queuedLoop = -2      // -2 = nothing queued
    private var loopStartBeat: Double = 0
    private var wasHostPlaying = false
    private var clockTempo: Double = 0
    private var lastClockTime: Double = 0
    private var clockCount: Int = 0
    private var clockRunning = false
    private var midiClockBeat: Double = 0

    /// Pads that sound (bit per pad). The export renderer uses it for stems.
    var padMask: UInt16 = 0xFFFF

    init() {
        params = .allocate(capacity: KParam.count)
        for p in KParam.allCases { (params + p.rawValue).initialize(to: p.defaultValue) }
        displayBPM = .allocate(capacity: 1)
        displayBPM.initialize(to: 140)
        status = .allocate(capacity: 8)
        status.initialize(repeating: 0, count: 8)
        status[1] = -1
        status[2] = -2
        padHits = .allocate(capacity: Pad.count)
        padHits.initialize(repeating: 0, count: Pad.count)
        voices = .allocate(capacity: KnockEngine.maxVoices)
        voices.initialize(repeating: Voice(), count: KnockEngine.maxVoices)
        mixL = .allocate(capacity: 8_192)
        mixR = .allocate(capacity: 8_192)
        mixL.initialize(repeating: 0, count: 8_192)
        mixR.initialize(repeating: 0, count: 8_192)
        blockEvents = .allocate(capacity: KnockEngine.maxBlockEvents)
        blockEvents.initialize(repeating: BlockEvent(), count: KnockEngine.maxBlockEvents)
    }

    deinit {
        params.deallocate()
        displayBPM.deallocate()
        status.deallocate()
        padHits.deallocate()
        voices.deallocate()
        mixL.deallocate()
        mixR.deallocate()
        blockEvents.deallocate()
    }

    /// Main thread, before audio starts (or when the host changes the sample rate).
    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        self.maxFrames = min(maxFrames, 8_192)
        bus.prepare(sampleRate: sampleRate)
        master.prepare(sampleRate: sampleRate)
        for i in 0..<KnockEngine.maxVoices { voices[i].active = false }
    }

    func param(_ p: KParam) -> Float { params[p.rawValue] }
    func setParam(_ p: KParam, _ v: Float) { params[p.rawValue] = v }

    // MARK: Events from outside the audio thread

    func send(_ e: KEvent) { queue.push(e) }

    /// MIDI from a hardware port (standalone app). Runs on the MIDI thread.
    func receiveMIDI(status st: UInt8, data1: UInt8, data2: UInt8, time: Double) {
        switch st & 0xF0 {
        case 0x90 where data2 > 0: queue.push(noteEvent(note: Int(data1), velocity: data2))
        case 0x80, 0x90: queue.push(KEvent(kind: .noteOff, a: Int32(data1)))
        case 0xB0 where data1 == 123 || data1 == 120: queue.push(KEvent(kind: .allOff))
        default:
            switch st {
            case 0xF8: queue.push(KEvent(kind: .midiClock, value: time))
            case 0xFA: queue.push(KEvent(kind: .midiStart))
            case 0xFB: queue.push(KEvent(kind: .midiContinue))
            case 0xFC: queue.push(KEvent(kind: .midiStop))
            case 0xF2: queue.push(KEvent(kind: .songPosition, a: Int32(Int(data1) | Int(data2) << 7)))
            default: break
            }
        }
    }

    private func noteEvent(note: Int, velocity: UInt8) -> KEvent {
        let v = Double(velocity) / 127
        if note >= Pad.firstNote && note < Pad.firstNote + Pad.count {
            let pad = note - Pad.firstNote
            if params[KParam.playMode.rawValue] > 0.5 { return KEvent(kind: .loopPad, a: Int32(pad), value: v) }
            return KEvent(kind: .pad, a: Int32(pad), value: v)
        }
        if Pad.bassNoteRange.contains(note) { return KEvent(kind: .bass, a: Int32(note - Pad.bassRootNote), value: v) }
        return KEvent(kind: .noteOff, a: -1)
    }

    // MARK: Audio thread

    /// Host MIDI for the current block (AUv3), sample-accurate. Call before render().
    func hostMIDI(offset: Int, status st: UInt8, data1: UInt8, data2: UInt8) {
        switch st & 0xF0 {
        case 0x90 where data2 > 0:
            let e = noteEvent(note: Int(data1), velocity: data2)
            addBlockEvent(BlockEvent(offset: offset, event: e))
        case 0x80, 0x90:
            addBlockEvent(BlockEvent(offset: offset, event: KEvent(kind: .noteOff, a: Int32(data1))))
        case 0xB0 where data1 == 123 || data1 == 120:
            addBlockEvent(BlockEvent(offset: offset, event: KEvent(kind: .allOff)))
        default: break
        }
    }

    @inline(__always)
    private func addBlockEvent(_ e: BlockEvent) {
        guard blockEventCount < KnockEngine.maxBlockEvents else { return }
        blockEvents[blockEventCount] = e
        blockEventCount += 1
    }

    /// Renders `frames` stereo samples. `host` is nil in the standalone app. Host MIDI added
    /// with hostMIDI() beforehand uses offsets from the start of this call.
    func render(frames total: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, host: HostTiming?) {
        var done = 0
        while done < total {
            let n = min(total - done, 8_192)
            renderBlock(frames: n, left: left + done, right: right + done,
                        host: done == 0 ? host : advanced(host, by: done))
            done += n
        }
        status[7] += 1
    }

    /// Samples rendered with nothing playing (after a few seconds the chain is skipped).
    private var idleSamples = 0

    private func renderBlock(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                             host: HostTiming?) {
        pickUpNewKitAndLoops(frames: frames)

        // Events from the faceplate and MIDI ports happen at the start of the block.
        queue.drain { e in
            self.addBlockEvent(BlockEvent(offset: 0, event: e))
        }
        scheduleLoops(frames: frames, host: host)
        sortBlockEvents()

        // Voices, segment by segment between events.
        mixL.update(repeating: 0, count: frames)
        mixR.update(repeating: 0, count: frames)
        var cursor = 0
        var keep = 0
        for i in 0..<blockEventCount {
            var e = blockEvents[i]
            if e.offset >= frames {           // belongs to the next block of this call
                e.offset -= frames
                blockEvents[keep] = e
                keep += 1
                continue
            }
            let at = max(0, e.offset)
            if at > cursor {
                renderVoices(from: cursor, to: at)
                cursor = at
            }
            apply(e, offset: at)
        }
        if cursor < frames { renderVoices(from: cursor, to: frames) }
        blockEventCount = keep

        // Nothing sounding for 4 s and stopped: skip the chain (tails have long died away).
        var anyVoice = false
        for v in 0..<KnockEngine.maxVoices where voices[v].active { anyVoice = true; break }
        if anyVoice || playing { idleSamples = 0 } else { idleSamples += frames }
        if idleSamples > Int(sampleRate * 4) {
            left.update(repeating: 0, count: frames)
            right.update(repeating: 0, count: frames)
            return
        }

        // The faceplate's sound, then the master section.
        var bs = BusProcessor.Settings()
        bs.mode = SoundMode(rawValue: Int(params[KParam.soundMode.rawValue].rounded())) ?? .modern
        bs.boost = params[KParam.boost.rawValue]
        bs.punch = params[KParam.punch.rawValue]
        bs.analogEQ = params[KParam.analogEQ.rawValue]
        bs.grit = params[KParam.grit.rawValue]
        bs.shine = params[KParam.shine.rawValue]
        bs.noise = params[KParam.noise.rawValue]
        bs.tempo = status[4] > 0 ? status[4] : 120
        bus.process(mixL, mixR, count: frames, bs)

        var ms = MasterBus.Settings()
        ms.filter = params[KParam.filter.rawValue]
        ms.clipDrive = params[KParam.clipDrive.rawValue]
        ms.output = params[KParam.output.rawValue]
        ms.clipperOn = params[KParam.clipper.rawValue] > 0.5
        master.process(mixL, mixR, count: frames, ms)

        left.update(from: mixL, count: frames)
        right.update(from: mixR, count: frames)
    }

    private func advanced(_ host: HostTiming?, by frames: Int) -> HostTiming? {
        guard var h = host, let b = h.beat, let t = h.tempo else { return host }
        h.beat = b + Double(frames) / sampleRate * t / 60
        return h
    }

    private func pickUpNewKitAndLoops(frames: Int) {
        if let r = retiringKit, kitHandoff.retire(r) { retiringKit = nil }
        if let r = retiringPatterns, patternHandoff.retire(r) { retiringPatterns = nil }
        if oldKit != nil {
            // Counted in samples: the old kit's voices fade for 5 ms; free it after 15 ms.
            oldKitCountdown -= frames
            if oldKitCountdown <= 0 && retiringKit == nil {
                retiringKit = oldKit
                oldKit = nil
                if let r = retiringKit, kitHandoff.retire(r) { retiringKit = nil }
            }
        }
        if oldKit == nil, retiringKit == nil, let newKit = kitHandoff.take() {
            // Fade out what's playing from the old kit, keep its memory until the fade is done.
            for v in 0..<KnockEngine.maxVoices where voices[v].active { voices[v].startFade(samples: Int(sampleRate * 0.005)) }
            oldKit = kit
            kit = newKit
            oldKitCountdown = Int(sampleRate * 0.015)
        }
        if retiringPatterns == nil, let newPatterns = patternHandoff.take() {
            retiringPatterns = patterns
            patterns = newPatterns
            if let r = retiringPatterns, patternHandoff.retire(r) { retiringPatterns = nil }
        }
    }

    private func sortBlockEvents() {
        guard blockEventCount > 1 else { return }
        for i in 1..<blockEventCount {
            let e = blockEvents[i]
            var j = i - 1
            while j >= 0 && blockEvents[j].offset > e.offset {
                blockEvents[j + 1] = blockEvents[j]
                j -= 1
            }
            blockEvents[j + 1] = e
        }
    }

    // MARK: Events

    private func apply(_ e: KEvent, offset: Int) {
        switch e.kind {
        case .pad:
            trigger(pad: Int(e.a), velocity: Float(e.value), semis: 0, lengthSamples: 0, glide: false)
        case .bass:
            trigger(pad: Pad.bass808.rawValue, velocity: Float(e.value), semis: Float(e.a), lengthSamples: 0, glide: false, heldNote: Int(e.a) + Pad.bassRootNote)
        case .noteOff:
            for v in 0..<KnockEngine.maxVoices where voices[v].active && voices[v].heldNote == Int(e.a) && e.a >= 0 {
                voices[v].release(samples: Int(sampleRate * 0.06))
            }
        case .loopPad:
            let pad = Int(e.a)
            let following = followingHost
            if pad < 0 || (pad == currentLoop && (playing || following)) {
                // Same pad again (or -1): stop at the end of the bar.
                queuedLoop = -1
                if !playing && !following { currentLoop = -1; queuedLoop = -2 }
            } else if !playing && !following {
                currentLoop = pad
                queuedLoop = -2
                startTransport(at: 0)
            } else if currentLoop < 0 {
                currentLoop = pad
                queuedLoop = -2
                loopStartBeat = (beat / 4).rounded(.down) * 4
            } else {
                queuedLoop = pad
            }
        case .play:
            if currentLoop < 0 { currentLoop = 0 }
            startTransport(at: 0)
        case .stop:
            playing = false
            queuedLoop = -2
            releaseAll()
        case .midiStart:
            clockRunning = true
            clockCount = 0
            midiClockBeat = 0
            if params[KParam.followDAW.rawValue] > 0.5 { if currentLoop < 0 { currentLoop = 0 }; startTransport(at: 0) }
        case .midiContinue:
            clockRunning = true
            if params[KParam.followDAW.rawValue] > 0.5 { if currentLoop < 0 { currentLoop = 0 }; playing = true }
        case .midiStop:
            clockRunning = false
            if params[KParam.followDAW.rawValue] > 0.5 { playing = false; releaseAll() }
        case .midiClock:
            if lastClockTime > 0 {
                let dt = e.value - lastClockTime
                if dt > 0.001 && dt < 0.1 {
                    let t = 60 / (dt * 24)
                    clockTempo = clockTempo <= 0 ? t : clockTempo * 0.92 + t * 0.08
                }
            }
            lastClockTime = e.value
            clockCount += 1
        case .songPosition:
            midiClockBeat = Double(e.a) / 4
            if params[KParam.followDAW.rawValue] > 0.5 { beat = midiClockBeat }
        case .allOff:
            releaseAll()
        }
    }

    private var followingHost = false

    private func startTransport(at b: Double) {
        playing = true
        beat = b
        loopStartBeat = b
    }

    private func releaseAll() {
        for v in 0..<KnockEngine.maxVoices where voices[v].active { voices[v].release(samples: Int(sampleRate * 0.03)) }
    }

    // MARK: Pads

    private func trigger(pad: Int, velocity: Float, semis: Float, lengthSamples: Int, glide: Bool, heldNote: Int = -1) {
        guard pad >= 0 && pad < Pad.count, padMask & (1 << UInt16(pad)) != 0, let kit else { return }
        let sample = kit.samples[pad]
        let ps = kit.settings[pad]
        let globalSemis = Float(Int(((params[KParam.pitch.rawValue] - 0.5) * 24).rounded()))
        let cents = (params[KParam.tune.rawValue] - 0.5) * 200
        let totalSemis = globalSemis + cents / 100 + ps.tune + semis
        let rate = Double(sample.sampleRate / sampleRate) * Double(powf(2, totalSemis / 12))

        // 808 glide: bend the note that's still sounding instead of starting a new one.
        if glide && pad == Pad.bass808.rawValue {
            for v in 0..<KnockEngine.maxVoices where voices[v].active && voices[v].pad == pad && !voices[v].releasing {
                voices[v].glide(to: rate, samples: Int(sampleRate * 0.07))
                voices[v].remaining = lengthSamples > 0 ? lengthSamples : Int.max
                padHits[pad] &+= 1
                return
            }
        }

        // Choke group (closed hat stops open hat; the 808 is mono).
        let group = Pad(rawValue: pad)?.chokeGroup ?? 0
        if group != 0 {
            for v in 0..<KnockEngine.maxVoices where voices[v].active && voices[v].chokeGroup == group {
                if pad == Pad.openHat.rawValue && voices[v].pad == Pad.openHat.rawValue { voices[v].startFade(samples: Int(sampleRate * 0.004)) }
                else if pad != Pad.openHat.rawValue || voices[v].pad != Pad.hat.rawValue { voices[v].startFade(samples: Int(sampleRate * 0.006)) }
            }
        }

        // Velocity: VELOCITY at 0 = every hit full; at 1 = the whole range.
        let sens = params[KParam.velocity.rawValue]
        let velGain = (1 - sens) + sens * powf(velocity.clamped(0, 1), 1.5)
        let gain = velGain * ps.gain
        let pan = ps.pan.clamped(-1, 1)
        let gl = gain * cosf((pan + 1) * .pi / 4) * 1.414
        let gr = gain * sinf((pan + 1) * .pi / 4) * 1.414

        // TIGHTEN shortens tails (the 808 half as much); the pad's own DECAY too.
        let tighten = params[KParam.tighten.rawValue] * (pad == Pad.bass808.rawValue ? 0.5 : 1)
        var tau: Double = .infinity
        if tighten > 0.001 { tau = 0.045 + (1 - Double(tighten)) * (1 - Double(tighten)) * 1.5 }
        if ps.decay < 0.999 { tau = min(tau, 0.03 + Double(ps.decay) * Double(ps.decay) * 2.5) }
        let coef: Float = tau.isFinite ? Float(exp(-1 / (tau * sampleRate))) : 1

        let slot = freeVoice()
        voiceAge &+= 1
        voices[slot] = Voice(sample: sample, pad: pad, rate: rate, reverse: ps.reverse, gainL: gl, gainR: gr,
                             decayCoef: coef, holdSamples: Int(sampleRate * 0.012), chokeGroup: group,
                             age: voiceAge, remaining: lengthSamples > 0 ? lengthSamples : Int.max, heldNote: heldNote)
        padHits[pad] &+= 1
    }

    private func freeVoice() -> Int {
        var oldest = 0
        var oldestAge = UInt32.max
        for v in 0..<KnockEngine.maxVoices {
            if !voices[v].active { return v }
            if voices[v].age < oldestAge { oldestAge = voices[v].age; oldest = v }
        }
        return oldest
    }

    private func renderVoices(from start: Int, to end: Int) {
        guard end > start else { return }
        for v in 0..<KnockEngine.maxVoices where voices[v].active {
            voices[v].render(into: mixL + start, mixR + start, frames: end - start, releaseSamples: Int(sampleRate * 0.03))
        }
    }

    // MARK: Loops

    /// Works out where the transport is this block and puts the loop's hits into it.
    private func scheduleLoops(frames: Int, host: HostTiming?) {
        let follow = params[KParam.followDAW.rawValue] > 0.5
        let sync = params[KParam.tempoSync.rawValue] > 0.5
        let loopMode = params[KParam.playMode.rawValue] > 0.5
        let hostHasTransport = host?.beat != nil && host?.playing != nil
        followingHost = follow && (hostHasTransport || clockRunning)
        status[5] = host?.tempo != nil ? 1 : 0
        status[6] = clockTempo

        // Tempo: the DAW's (or MIDI clock's) when TEMPO SYNC is on and there is one, otherwise the display's.
        var tempo = displayBPM.pointee
        if sync || follow {
            if let t = host?.tempo, t > 0 { tempo = t } else if clockTempo > 0 && clockRunning { tempo = clockTempo }
        }
        tempo = tempo.clamped(30, 300)
        status[4] = tempo

        let beatsPerSample = tempo / 60 / sampleRate
        var b0: Double
        if follow, hostHasTransport, let hb = host?.beat, let hp = host?.playing {
            if hp && !wasHostPlaying {
                releaseAll()
                if currentLoop < 0 && loopMode { currentLoop = 0 }
            }
            if !hp && wasHostPlaying { releaseAll() }
            wasHostPlaying = hp
            playing = hp && currentLoop >= 0
            b0 = hb
            loopStartBeat = 0
        } else if follow && clockRunning {
            b0 = beat
        } else {
            b0 = beat
        }
        let b1 = b0 + Double(frames) * beatsPerSample
        defer {
            beat = b1
            status[0] = playing ? 1 : 0
            status[1] = Double(currentLoop)
            status[2] = Double(queuedLoop)
            status[3] = b1
        }
        guard playing, let patterns, currentLoop >= 0 else { return }

        // Loop changes (and stops) land on the next bar line.
        if queuedLoop != -2 {
            let nextBar = (b0 / 4 - 1e-9).rounded(.up) * 4
            if nextBar < b1 {
                // The old loop plays up to the bar line...
                schedule(patterns, loop: currentLoop, start: loopStartBeat, from: b0, to: nextBar, blockStart: b0,
                         tempo: tempo, frames: frames)
                if queuedLoop == -1 {
                    if !followingHost { playing = false }
                    currentLoop = -1
                    queuedLoop = -2
                    return
                }
                // ...and the new one from there.
                currentLoop = queuedLoop
                queuedLoop = -2
                loopStartBeat = followingHost ? 0 : nextBar
                schedule(patterns, loop: currentLoop, start: loopStartBeat, from: nextBar, to: b1, blockStart: b0,
                         tempo: tempo, frames: frames)
                return
            }
        }
        schedule(patterns, loop: currentLoop, start: loopStartBeat, from: b0, to: b1, blockStart: b0, tempo: tempo, frames: frames)
    }

    /// Puts the hits of one loop that fall between two beat positions into this block.
    private func schedule(_ patterns: PatternSet, loop index: Int, start: Double, from: Double, to: Double,
                          blockStart: Double, tempo: Double, frames: Int) {
        guard index >= 0 && index < patterns.loops.count, to > from else { return }
        let loop = patterns.loops[index]
        guard loop.count > 0 else { return }
        let bounce = Double(params[KParam.bounce.rawValue])
        let ppq = Double(PatternData.ppq)
        let t0 = (from - start) * ppq
        let t1 = (to - start) * ppq
        let tBlock = (blockStart - start) * ppq
        let len = Double(loop.lengthTicks)
        let samplesPerTick = 60 / tempo / ppq * sampleRate
        // One cycle either side, so swung hits near the loop's edges aren't missed.
        var cycle = max(0, (t0 / len).rounded(.down) - 1)
        let lastCycle = (t1 / len).rounded(.down) + 1
        while cycle <= lastCycle {
            let base = cycle * len
            for k in 0..<loop.count {
                let ev = loop.events[k]
                let t = base + Double(ev.tick) + swingOffset(tick: Int(ev.tick), pad: Int(ev.pad), bounce: bounce)
                guard t >= t0 && t < t1 && t >= 0 else { continue }
                let offset = Int(((t - tBlock) * samplesPerTick).rounded(.down))
                var e = KEvent(kind: ev.pad == Int8(Pad.bass808.rawValue) ? .bass : .pad, a: Int32(ev.pad), value: Double(ev.velocity))
                if e.kind == .bass { e.a = Int32(ev.semis.rounded()) }
                let lengthSamples = ev.length > 0 ? Int(Double(ev.length) * samplesPerTick) : 0
                addBlockEvent(BlockEvent(offset: min(max(offset, 0), frames - 1), event: e, length: lengthSamples,
                                         glide: ev.glide, fromLoop: true, pad: Int(ev.pad)))
            }
            cycle += 1
        }
    }

    /// BOUNCE: swing on the off 16ths, and at the top of the knob a loose "late kick, early
    /// snare" feel.
    @inline(__always)
    private func swingOffset(tick: Int, pad: Int, bounce: Double) -> Double {
        guard bounce > 0.001 else { return 0 }
        var o: Double = 0
        let inBeat = tick % 48
        if abs(inBeat - 24) <= 2 { o += bounce * 8 }
        let loose = bounce * bounce
        if pad == Pad.kick.rawValue { o += loose * 4 }
        if pad == Pad.snare.rawValue || pad == Pad.clap.rawValue { o -= loose * 3 }
        return o
    }

    // Block events carry loop info (808 length, glide).
    struct BlockEvent {
        var offset: Int = 0
        var event = KEvent(kind: .allOff)
        var length: Int = 0
        var glide = false
        var fromLoop = false
        var pad: Int = 0
    }

    // Loop hits use the same trigger with length and glide.
    private func apply(_ b: BlockEvent, offset: Int) {
        if b.fromLoop {
            if b.event.kind == .bass {
                trigger(pad: Pad.bass808.rawValue, velocity: Float(b.event.value), semis: Float(b.event.a),
                        lengthSamples: b.length, glide: b.glide)
            } else {
                trigger(pad: b.pad, velocity: Float(b.event.value), semis: 0, lengthSamples: 0, glide: false)
            }
        } else {
            apply(b.event, offset: offset)
        }
    }
}

// MARK: - A playing sound

struct Voice {
    var active = false
    var pad = 0
    var left: UnsafeMutablePointer<Float>?
    var right: UnsafeMutablePointer<Float>?
    var length = 0
    var position: Double = 0
    var rate: Double = 1
    var targetRate: Double = 1
    var rateStep: Double = 0
    var glideLeft = 0
    var reverse = false
    var gainL: Float = 0
    var gainR: Float = 0
    var env: Float = 1
    var decayCoef: Float = 1
    var hold = 0
    var fade: Float = 1
    var fadeStep: Float = 0
    var releasing = false
    var chokeGroup = 0
    var age: UInt32 = 0
    var remaining = Int.max
    var heldNote = -1

    init() {}

    init(sample: SampleBuffer, pad: Int, rate: Double, reverse: Bool, gainL: Float, gainR: Float,
         decayCoef: Float, holdSamples: Int, chokeGroup: Int, age: UInt32, remaining: Int, heldNote: Int) {
        active = true
        self.pad = pad
        left = sample.left
        right = sample.right
        length = sample.length
        self.rate = rate
        targetRate = rate
        self.reverse = reverse
        position = reverse ? Double(sample.length - 1) : 0
        self.gainL = gainL
        self.gainR = gainR
        self.decayCoef = decayCoef
        hold = holdSamples
        self.chokeGroup = chokeGroup
        self.age = age
        self.remaining = remaining
        self.heldNote = heldNote
    }

    mutating func startFade(samples: Int) {
        guard active else { return }
        releasing = true
        let step = 1 / Float(max(samples, 1))
        fadeStep = max(fadeStep, step)
        chokeGroup = -1   // a fading voice no longer belongs to a group
        heldNote = -1
    }

    mutating func release(samples: Int) { startFade(samples: samples) }

    mutating func glide(to newRate: Double, samples: Int) {
        targetRate = newRate
        glideLeft = max(samples, 1)
        rateStep = (newRate - rate) / Double(glideLeft)
    }

    @inline(__always)
    mutating func render(into outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, frames: Int, releaseSamples: Int) {
        guard let left, let right else { active = false; return }
        let last = Double(length - 1)
        for i in 0..<frames {
            if remaining != Int.max {
                remaining -= 1
                if remaining == 0 { release(samples: releaseSamples); remaining = Int.max }
            }
            if position < 0 || position >= last { active = false; return }
            let idx = Int(position)
            let frac = Float(position - Double(idx))
            let l = left[idx] + (left[idx + 1] - left[idx]) * frac
            let r = right[idx] + (right[idx + 1] - right[idx]) * frac
            var g = env * fade
            if hold > 0 { hold -= 1 } else { env *= decayCoef }
            if releasing {
                fade -= fadeStep
                if fade <= 0 { active = false; return }
                g = env * fade
            }
            if g < 0.000_05 && env < 0.000_05 { active = false; return }
            outL[i] += l * g * gainL
            outR[i] += r * g * gainR
            if glideLeft > 0 {
                rate += rateStep
                glideLeft -= 1
                if glideLeft == 0 { rate = targetRate }
            }
            position += reverse ? -rate : rate
        }
    }
}
