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
    /// 0...1 logarithmic low-pass cutoff; 1 bypasses the per-pad filter.
    var filter: Float = 1
    var reverse = false
    /// File name in the Samples folder when the pad holds your own sample.
    var sampleFile: String?

    private enum CodingKeys: String, CodingKey {
        case level, pan, tune, decay, filter, reverse, sampleFile
    }

    var gain: Float { level <= 0.001 ? 0 : KnockMath.dbToGain(40 * log10f(level / 0.8)) }
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
    }
}

/// The sounds on the 12 pads, ready for the audio thread (read-only once published).
final class KitBuffers {
    let name: String
    let samples: [SampleBuffer]
    let settings: [PadSettings]
    let bassHz: Float
    /// One-pole coefficients prepared on the control plane, never at note-on or render time.
    let filterCoefficients: [Float]
    /// Each pad's LEVEL and PAN as left / right gains (equal-power pan). Notes that are already
    /// sounding glide to these, so turning a channel's volume or pan never steps the gain.
    let mixL: [Float]
    let mixR: [Float]

    init(name: String, samples: [SampleBuffer], settings: [PadSettings], bassHz: Float,
         renderSampleRate: Double = 48_000) {
        self.name = name
        self.samples = samples
        self.settings = settings
        self.bassHz = bassHz
        let rate = renderSampleRate.isFinite && renderSampleRate > 0 ? renderSampleRate : 48_000
        filterCoefficients = settings.map { pad in
            let amount = pad.filter.isFinite ? pad.filter.clamped(0, 1) : 1
            guard amount < 0.999_999 else { return 1 }
            let cutoff = min(40 * pow(450, Double(amount)), rate * 0.45)
            return Float(1 - exp(-2 * Double.pi * cutoff / rate))
        }
        mixL = settings.map { $0.gain * cosf(($0.pan.clamped(-1, 1) + 1) * .pi / 4) * 1.414 }
        mixR = settings.map { $0.gain * sinf(($0.pan.clamped(-1, 1) + 1) * .pi / 4) * 1.414 }
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
    /// Short fades for stolen voices. The render cost stays bounded even during MIDI bursts.
    static let maxStealTails = 8
    static let maxBlockEvents = 512

    // Controls: the faceplate and host write, the audio thread reads.
    private let controls = SharedControls()
    private let params: UnsafeMutablePointer<Float>
    /// AU render events write here, never through the control-plane lock. Publication to the
    /// faceplate retries on subsequent callbacks if the control-plane writer is busy.
    private let hostParams: UnsafeMutablePointer<Float>
    private var hostParamMask: UInt32 = 0
    /// Tempo of the BPM display (the engine reads it; the controller sets it).
    private let displayBPM: UnsafeMutablePointer<Double>

    // What the faceplate shows (written by the audio thread).
    /// 0 playing, 1 current loop (-1 none), 2 queued loop, 3 beat, 4 tempo, 5 host connected,
    /// 6 MIDI clock tempo (0 = none), 7 render count
    let status: UnsafeMutablePointer<Double>
    /// Incremented every time a pad sounds (the faceplate flashes it).
    let padHits: UnsafeMutablePointer<UInt32>

    let meters = SharedMeters()
    private var meterFrames = 0
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
    private let stealTails: UnsafeMutablePointer<Voice>
    private var voiceAge: UInt32 = 0
    private let mixL: UnsafeMutablePointer<Float>
    private let mixR: UnsafeMutablePointer<Float>
    private let blockEvents: UnsafeMutablePointer<BlockEvent>
    private var blockEventCount = 0

    let bus = BusProcessor()
    let master = MasterBus()

    // Transport
    // Fixed storage: last-held note wins, releasing it returns to the previous held note.
    private let heldLoops = UnsafeMutablePointer<UInt64>.allocate(capacity: 2064)
    private var heldOrder: UInt64 = 0
    private var gatedToken = -1
    private var lastPlayMode: Float = -1
    private var playing = false
    private var beat: Double = 0
    private var currentLoop = -1
    private var queuedLoop = -2      // -2 = nothing queued
    private var loopStartBeat: Double = 0
    private var wasHostPlaying = false
    /// FOLLOW DAW: BreakBoss's own STOP mutes the pattern while the DAW keeps running (PLAY brings it
    /// back on the DAW's beat); with the DAW stopped, PLAY runs BreakBoss on its own at the DAW's tempo.
    private var userArmed = true
    private var localRun = false
    private var clockTempo: Double = 0
    private var lastClockTime: Double = 0
    private var clockCount: Int = 0
    private var clockRunning = false
    private var midiClockBeat: Double = 0

    /// Live MIDI note -> pad (-1 = not a pad). Written only by the audio thread, from .mapNote
    /// events, so it never changes in the middle of a block. MIDI files keep notes 36-47.
    private let midiPadTable = UnsafeMutablePointer<Int8>.allocate(capacity: 128)
    /// The last live note-on: (count << 8) | note, so the MIDI learn screen can see it.
    let lastNoteOn = UnsafeMutablePointer<Int32>.allocate(capacity: 1)

    /// Drum roll RECORD: hits played while the pattern runs are written here (audio thread)
    /// and collected by the main thread. Single writer, single reader, fixed size.
    struct RecordedHit { var loop: Int16 = 0; var pad: Int8 = 0; var tick: Int32 = 0; var velocity: Float = 0; var semis: Float = 0 }
    static let recordCapacity = 512
    let recordRing = UnsafeMutablePointer<RecordedHit>.allocate(capacity: KnockEngine.recordCapacity)
    let recordWrite = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    private var recordRead = 0
    private var recordArmed = false
    /// Where the playing pattern is, in ticks from its start (for the drum roll's playhead).
    let playheadTick = UnsafeMutablePointer<Double>.allocate(capacity: 1)
    private var lastBeatsPerSample: Double = 0
    private var blockBeat0: Double = 0
    // Metronome (drum roll): a short sine click, accented on the bar. Mixed after the master
    // section so the clipper and effects never touch it.
    private var metronomeOn = false
    private var clickPhase: Double = 0
    private var clickRemaining = 0
    /// RECORD's count-in: the transport is still below the pattern's first beat.
    private var countingIn: Bool { playing && blockBeat0 < loopStartBeat - 1e-9 }
    private var clickFreq: Double = 1500
    private var clickGain: Float = 0

    /// Pads that sound (bit per pad). The export renderer uses it for stems.
    var padMask: UInt16 = 0xFFFF

    // MIDI OUT (drum roll): the pattern's hits as MIDI, each drum channel on its own MIDI
    // channel and note. Collected per render call with sample offsets into fixed storage;
    // the plug-in hands them to the host, the app to CoreMIDI. Nothing allocates here.
    struct MIDIOutMessage { var frame: Int32 = 0; var status: UInt8 = 0; var data1: UInt8 = 0; var data2: UInt8 = 0 }
    static let midiOutCapacity = 256
    let midiOut = UnsafeMutablePointer<MIDIOutMessage>.allocate(capacity: KnockEngine.midiOutCapacity)
    /// Messages from the last render call (read right after render() on the same thread).
    private(set) var midiOutCount = 0
    /// Hands the last render call's MIDI out to `send` (frame offset, status, data1, data2).
    @inline(__always)
    func forEachMIDIOut(_ send: (Int, UInt8, UInt8, UInt8) -> Void) {
        for i in 0..<midiOutCount { let m = midiOut[i]; send(Int(m.frame), m.status, m.data1, m.data2) }
    }
    private var midiOutOn = false
    /// True while a note from the DAW is being played: those hits don't go back out (no MIDI thru).
    private var playingHostNote = false
    private let midiOutChannel = UnsafeMutablePointer<Int16>.allocate(capacity: Pad.count)   // -1 = off
    private let midiOutNote = UnsafeMutablePointer<UInt8>.allocate(capacity: Pad.count)
    private let midiOffDue = UnsafeMutablePointer<Int64>.allocate(capacity: Pad.count)       // -1 = none
    private let midiOffChannel = UnsafeMutablePointer<UInt8>.allocate(capacity: Pad.count)
    private let midiOffNote = UnsafeMutablePointer<UInt8>.allocate(capacity: Pad.count)
    private var sampleClock: Int64 = 0
    /// When each channel*128+note was last sent by MIDI OUT (loop-back guard).
    private let midiSentAt = UnsafeMutablePointer<Int64>.allocate(capacity: 2048)
    private var renderBase = 0

    init() {
        precondition(KParam.count <= UInt32.bitWidth)
        heldLoops.initialize(repeating: 0, count: 2064)
        midiPadTable.initialize(repeating: -1, count: 128)
        midiOut.initialize(repeating: MIDIOutMessage(), count: KnockEngine.midiOutCapacity)
        midiOutChannel.initialize(repeating: -1, count: Pad.count)
        midiOutNote.initialize(repeating: 36, count: Pad.count)
        midiOffDue.initialize(repeating: -1, count: Pad.count)
        midiOffChannel.initialize(repeating: 0, count: Pad.count)
        midiOffNote.initialize(repeating: 0, count: Pad.count)
        midiSentAt.initialize(repeating: Int64.min / 2, count: 2048)
        for pad in 0..<Pad.count { midiPadTable[MIDIPadMap.standardNotes[pad]] = Int8(pad) }
        lastNoteOn.initialize(to: 0)
        recordRing.initialize(repeating: RecordedHit(), count: KnockEngine.recordCapacity)
        recordWrite.initialize(to: 0)
        playheadTick.initialize(to: -1)
        params = .allocate(capacity: KParam.count)
        hostParams = .allocate(capacity: KParam.count)
        for p in KParam.allCases { (params + p.rawValue).initialize(to: p.defaultValue) }
        for p in KParam.allCases { (hostParams + p.rawValue).initialize(to: p.defaultValue) }
        displayBPM = .allocate(capacity: 1)
        displayBPM.initialize(to: 140)
        status = .allocate(capacity: 10)
        status.initialize(repeating: 0, count: 10)
        status[1] = -1
        status[2] = -2
        padHits = .allocate(capacity: Pad.count)
        padHits.initialize(repeating: 0, count: Pad.count)
        voices = .allocate(capacity: KnockEngine.maxVoices)
        voices.initialize(repeating: Voice(), count: KnockEngine.maxVoices)
        stealTails = .allocate(capacity: KnockEngine.maxStealTails)
        stealTails.initialize(repeating: Voice(), count: KnockEngine.maxStealTails)
        mixL = .allocate(capacity: 8_192)
        mixR = .allocate(capacity: 8_192)
        mixL.initialize(repeating: 0, count: 8_192)
        mixR.initialize(repeating: 0, count: 8_192)
        blockEvents = .allocate(capacity: KnockEngine.maxBlockEvents)
        blockEvents.initialize(repeating: BlockEvent(), count: KnockEngine.maxBlockEvents)
    }

    deinit {
        midiOut.deallocate(); midiOutChannel.deallocate(); midiOutNote.deallocate()
        midiOffDue.deallocate(); midiOffChannel.deallocate(); midiOffNote.deallocate(); midiSentAt.deallocate()
        heldLoops.deallocate()
        midiPadTable.deallocate()
        lastNoteOn.deallocate()
        recordRing.deallocate()
        recordWrite.deallocate()
        playheadTick.deallocate()
        params.deallocate()
        hostParams.deallocate()
        displayBPM.deallocate()
        status.deallocate()
        padHits.deallocate()
        voices.deallocate()
        stealTails.deallocate()
        mixL.deallocate()
        mixR.deallocate()
        blockEvents.deallocate()
    }

    /// Main thread, before audio starts (or when the host changes the sample rate).
    func prepare(sampleRate: Double, maxFrames: Int) {
        self.sampleRate = sampleRate
        self.maxFrames = min(maxFrames, 8_192)
        // The FIR coefficients are a lazy static array. Build them before the first callback.
        _ = HalfBandOversampler.oddTaps
        bus.prepare(sampleRate: sampleRate)
        master.prepare(sampleRate: sampleRate)
        for i in 0..<KnockEngine.maxVoices { voices[i].active = false }
        for i in 0..<KnockEngine.maxStealTails { stealTails[i].active = false }
    }

    func param(_ p: KParam) -> Float { controls.get(p) }
    func setParam(_ p: KParam, _ v: Float) { controls.set(p, v) }
    func setTempo(_ bpm: Double) { controls.setTempo(bpm) }

    /// AU render thread only, before render(). Automation is normalized into fixed storage;
    /// render() applies it even if publishing the value to the faceplate cannot try-lock yet.
    /// Control-plane writers keep using setParam(). Parameter addresses stay append-only.
    @inline(__always)
    func hostParameter(_ p: KParam, _ value: Float) {
        let finite = value.isFinite ? value : p.defaultValue
        if let steps = p.steps {
            hostParams[p.rawValue] = finite.rounded().clamped(0, Float(steps - 1))
        } else {
            hostParams[p.rawValue] = finite.clamped(0, 1)
        }
        hostParamMask |= UInt32(1) << p.rawValue
    }

    // MARK: Events from outside the audio thread

    func send(_ e: KEvent) { queue.push(e) }

    /// MIDI from a hardware port (standalone app). Runs on the MIDI thread.
    func receiveMIDI(status st: UInt8, data1: UInt8, data2: UInt8, time: Double) {
        switch st & 0xF0 {
        case 0x90 where data2 > 0: queue.push(KEvent(kind: .midiNoteOn, a: Int32(Int(st & 0x0F) * 128 + Int(data1)), value: Double(data2) / 127))
        case 0x80, 0x90: queue.push(KEvent(kind: .noteOff, a: Int32(Int(st & 0x0F) * 128 + Int(data1))))
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

    @inline(__always)
    /// MIDI shaped like BreakBoss's own MIDI OUT (each pad on its channel and note, the 808 on its
    /// channel from C2 to C5): which pad it is, and the 808's pitch. Nil for anything else (a
    /// controller), which keeps the normal pad map and LOOP launching.
    private func outRoute(channel: Int, note: Int) -> (pad: Int, semis: Int)? {
        guard midiOutOn, channel >= 0, channel < 16 else { return nil }
        let bass = Pad.bass808.rawValue
        for p in 0..<Pad.count where p != bass && midiOutChannel[p] == Int16(channel) && Int(midiOutNote[p]) == note {
            return (p, 0)
        }
        if midiOutChannel[bass] == Int16(channel) && Pad.bassNoteRange.contains(note) {
            return (bass, note - Pad.bassRootNote)
        }
        // A drum on a MIDI channel of its own (multi-out): any note on that channel plays it,
        // pitched around its own note, so a DAW piano roll has full control of pitch and velocity.
        if let p = ownerOfChannel(channel), p != bass {
            return (p, (note - Int(midiOutNote[p])).clamped(-24, 24))
        }
        return nil
    }

    /// The one pad sent on this MIDI channel, or nil when no pad or several pads share it.
    @inline(__always)
    private func ownerOfChannel(_ channel: Int) -> Int? {
        var owner = -1
        for p in 0..<Pad.count where midiOutChannel[p] == Int16(channel) {
            if owner >= 0 { return nil }
            owner = p
        }
        return owner >= 0 ? owner : nil
    }

    private func livePad(_ note: Int) -> Int? {
        guard note >= 0 && note < 128 else { return nil }
        let pad = Int(midiPadTable[note])
        return pad >= 0 && pad < Pad.count ? pad : nil
    }

    private func noteEvent(note: Int, velocity: UInt8) -> KEvent {
        let v = Double(velocity) / 127
        if let pad = livePad(note) {
            if params[KParam.playMode.rawValue] > 0.5 && !recordArmed { return KEvent(kind: .loopPad, a: Int32(pad), value: v) }
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
            let e = KEvent(kind: .midiNoteOn, a: Int32(Int(st & 0x0F) * 128 + Int(data1)), value: Double(data2) / 127)
            addBlockEvent(BlockEvent(offset: max(0, offset), event: e))
        case 0x80, 0x90:
            addBlockEvent(BlockEvent(offset: max(0, offset),
                                     event: KEvent(kind: .noteOff, a: Int32(Int(st & 0x0F) * 128 + Int(data1)))))
        case 0xB0 where data1 == 123 || data1 == 120:
            addBlockEvent(BlockEvent(offset: max(0, offset), event: KEvent(kind: .allOff)))
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
        // One bounded try-lock, including publication of any pending AU automation. If the
        // lock is busy, retain the previous UI snapshot and apply pending host values locally.
        if controls.copy(to: params, tempo: displayBPM, hostValues: hostParams, hostMask: hostParamMask) {
            hostParamMask = 0
        } else {
            var dirty = hostParamMask
            while dirty != 0 {
                let index = dirty.trailingZeroBitCount
                params[index] = hostParams[index]
                dirty &= dirty - 1
            }
        }
        midiOutCount = 0
        var done = 0
        while done < total {
            renderBase = done
            // A loop gate must change transport before its part of the block is scheduled.
            // Splitting at that exact boundary also keeps stop/release fades at the correct
            // sample. Ordinary pad and bass notes remain inexpensive segmented BlockEvents.
            let n = nextHostTransportBoundary(before: min(total - done, 8_192))
            renderBlock(frames: n, left: left + done, right: right + done,
                        host: done == 0 ? host : advanced(host, by: done))
            done += n
        }
        flushMIDIOffs(frames: total)
        sampleClock += Int64(total)
        status[7] += 1
    }

    @inline(__always)
    private func isHostTransport(_ event: KEvent) -> Bool {
        switch event.kind {
        case .midiNoteOn, .noteOff:
            return params[KParam.playMode.rawValue] > 0.5 && !recordArmed && event.a >= 0 &&
                livePad(Int(event.a) % 128) != nil
        case .allOff:
            return true
        default:
            return false
        }
    }

    private func nextHostTransportBoundary(before limit: Int) -> Int {
        var result = limit
        for i in 0..<blockEventCount {
            let b = blockEvents[i]
            if !b.fromLoop && b.offset > 0 && b.offset < result && isHostTransport(b.event) {
                result = b.offset
            }
        }
        return result
    }

    /// Transport events at this segment's first sample precede loop scheduling. Future
    /// events remain in fixed storage, with their offsets reduced as each segment renders.
    private func applyHostTransportAtBlockStart() {
        var keep = 0
        for i in 0..<blockEventCount {
            let b = blockEvents[i]
            if !b.fromLoop && b.offset <= 0 && isHostTransport(b.event) {
                apply(b.event, offset: 0)
            } else {
                blockEvents[keep] = b
                keep += 1
            }
        }
        blockEventCount = keep
    }

    /// Samples rendered with nothing playing (after a few seconds the chain is skipped).
    private var idleSamples = 0

    private func renderBlock(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>,
                             host: HostTiming?) {
        defer {
            meterFrames += frames
            if meterFrames >= Int(sampleRate / 30) {
                meterFrames = 0
                meters.publish(status: status, hits: padHits, master: master)
            }
        }
        pickUpNewKitAndLoops(frames: frames)
        let playMode = params[KParam.playMode.rawValue]
        if lastPlayMode >= 0 && playMode != lastPlayMode { clearGates(); playing = false; queuedLoop = -2; releaseAll() }
        lastPlayMode = playMode

        // Events from the faceplate and MIDI ports happen at the start of the block.
        // Transport events (start, stop, loop picks, MIDI clock) are handled before the loop is
        // scheduled, so a loop starts on this block's first sample, not one block late.
        queue.drain { e in
            if KnockEngine.isTransport(e.kind) {
                self.apply(e, offset: 0)
            } else {
                self.addBlockEvent(BlockEvent(offset: 0, event: e))
            }
        }
        applyHostTransportAtBlockStart()
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
        if !anyVoice {
            for v in 0..<KnockEngine.maxStealTails where stealTails[v].active { anyVoice = true; break }
        }
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
        bs.resample = params[KParam.resample.rawValue]
        bs.instability = params[KParam.instability.rawValue]
        bs.delay = params[KParam.textureDelay.rawValue]
        bs.reverb = params[KParam.gatedReverb.rawValue]
        bs.drive = params[KParam.drive.rawValue]
        bs.beat = playing ? blockBeat0 : nil
        bus.process(mixL, mixR, count: frames, bs)

        var ms = MasterBus.Settings()
        ms.filter = params[KParam.filter.rawValue]
        ms.clipDrive = params[KParam.clipDrive.rawValue]
        ms.output = params[KParam.output.rawValue]
        ms.clipperOn = params[KParam.clipper.rawValue] > 0.5
        master.process(mixL, mixR, count: frames, ms)
        if metronomeOn || recordArmed || countingIn || clickRemaining > 0 { addClicks(frames: frames) }

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
            // A pad whose sound didn't change (only its level, pan, tune, decay...) keeps ringing:
            // the new kit holds the same sample, and its level and pan glide to the new values.
            func sameSound(_ pad: Int) -> Bool {
                guard let kit, pad >= 0, pad < kit.samples.count, pad < newKit.samples.count else { return false }
                return kit.samples[pad] === newKit.samples[pad]
            }
            for v in 0..<KnockEngine.maxVoices where voices[v].active && !sameSound(voices[v].pad) {
                voices[v].startFade(samples: Int(sampleRate * 0.005))
            }
            for v in 0..<KnockEngine.maxStealTails where stealTails[v].active && !sameSound(stealTails[v].pad) {
                stealTails[v].startFade(samples: Int(sampleRate * 0.005))
            }
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
        case .mapNote:
            if e.a < 0 {
                midiPadTable.update(repeating: -1, count: 128)
            } else if e.a < 128 {
                midiPadTable[Int(e.a)] = Int8(clamping: Int(e.value))
            }
        case .midiNoteOn:
            // Our own MIDI OUT coming back in (a loop-back route): ignore it, or every hit retriggers itself.
            if midiOutOn, e.a >= 0, e.a < 2048, sampleClock - midiSentAt[Int(e.a)] < Int64(sampleRate * 0.05) { break }
            let note = Int(e.a) % 128
            lastNoteOn.pointee = (lastNoteOn.pointee &+ 256) & ~0xFF | Int32(note)
            // The DAW playing back what BreakBoss recorded into it (same channels and notes as
            // MIDI OUT): always the drum itself, in ONE-SHOT and LOOP mode alike.
            if e.a >= 0, let r = outRoute(channel: Int(e.a) / 128, note: note) {
                playingHostNote = true
                if r.pad == Pad.bass808.rawValue {
                    apply(KEvent(kind: .bass, a: Int32(r.semis), value: e.value), offset: offset)
                } else if r.semis != 0 {
                    apply(KEvent(kind: .padPitched, a: Int32(r.pad + 128 * (r.semis + 64)), value: e.value), offset: offset)
                } else {
                    apply(KEvent(kind: .pad, a: Int32(r.pad), value: e.value), offset: offset)
                }
                playingHostNote = false
                break
            }
            if params[KParam.playMode.rawValue] > 0.5, !recordArmed, livePad(note) != nil {
                beginGate(Int(e.a))
            } else {
                let event = noteEvent(note: note, velocity: UInt8(clamping: Int(e.value * 127)))
                apply(event, offset: offset)
            }
        case .loopGateOn:
            beginGate(Int(e.a))
        case .loopGateOff:
            endGate(Int(e.a))
        case .pad:
            trigger(pad: Int(e.a), velocity: Float(e.value), semis: 0, lengthSamples: 0, glide: false)
            midiOutHit(pad: Int(e.a), velocity: Float(e.value), semis: 0, length: 0, offset: offset)   // pad taps reach the DAW
            record(pad: Int(e.a), velocity: Float(e.value), semis: 0, offset: offset)
        case .padPitched:
            let pad = Int(e.a) % 128, semis = Float(Int(e.a) / 128 - 64)
            guard pad >= 0 && pad < Pad.count else { break }
            trigger(pad: pad, velocity: Float(e.value), semis: semis, lengthSamples: 0, glide: false)
            midiOutHit(pad: pad, velocity: Float(e.value), semis: semis, length: 0, offset: offset)
            record(pad: pad, velocity: Float(e.value), semis: semis, offset: offset)
        case .cue:
            // The sequencer's pattern: what plays next when nothing is playing (PLAY, the DAW, MIDI start).
            if !playing && e.a >= 0 && e.a < Int32(Pad.count) { currentLoop = Int(e.a) }
        case .countIn:
            // RECORD with a count-in: the clicks run for `a` beats before the pattern's first
            // beat (the transport starts below zero; nothing plays until it reaches the top).
            clearGates()
            if e.value >= 0 && Int(e.value) < Pad.count { currentLoop = Int(e.value) }
            if currentLoop < 0 { currentLoop = 0 }
            userArmed = true
            localRun = true
            playing = true
            queuedLoop = -2
            loopStartBeat = 0
            beat = -Double(max(0, e.a))
        case .bass:
            trigger(pad: Pad.bass808.rawValue, velocity: Float(e.value), semis: Float(e.a), lengthSamples: 0, glide: false, heldNote: Int(e.a) + Pad.bassRootNote)
            midiOutHit(pad: Pad.bass808.rawValue, velocity: Float(e.value), semis: Float(e.a), length: 0, offset: offset)
            record(pad: Pad.bass808.rawValue, velocity: Float(e.value), semis: Float(e.a), offset: offset)
        case .padMask:
            padMask = UInt16(truncatingIfNeeded: e.a)
        case .recordArm:
            recordArmed = e.a != 0
        case .metronome:
            metronomeOn = e.a != 0
        case .midiOut:
            if e.a < 0 {
                let on = e.value > 0.5
                if !on { midiOutAllOff(offset: offset) }
                midiOutOn = on
            } else if e.a < Int32(Pad.count) {
                let pad = Int(e.a)
                if midiOffDue[pad] >= 0 { midiOutAllOff(offset: offset) }
                if e.value < 0 { midiOutChannel[pad] = -1 } else {
                    let v = Int(e.value)
                    midiOutChannel[pad] = Int16((v / 128).clamped(0, 15))
                    midiOutNote[pad] = UInt8((v % 128).clamped(0, 127))
                }
            }
        case .noteOff:
            // A recorded part playing back: the 808 note ends where the DAW's note ends (its
            // length as recorded); drums are one-shots and ring out.
            if e.a >= 0, let r = outRoute(channel: Int(e.a) / 128, note: Int(e.a) % 128) {
                if r.pad == Pad.bass808.rawValue {
                    let note = Int(e.a) % 128
                    for v in 0..<KnockEngine.maxVoices where voices[v].active && voices[v].heldNote == note {
                        voices[v].release(samples: Int(sampleRate * 0.03))
                    }
                }
                break
            }
            // One-shot duration belongs to the sample and DECAY control, even for a
            // chromatic 808. Only Loop mode treats MIDI note length as a gate.
            guard params[KParam.playMode.rawValue] > 0.5 else { break }
            if e.a >= 0 { endGate(Int(e.a)) }
            let note = Int(e.a) % 128
            for v in 0..<KnockEngine.maxVoices where voices[v].active && voices[v].heldNote == note && e.a >= 0 {
                voices[v].release(samples: Int(sampleRate * 0.06))
            }
        case .loopPad:
            clearGates()
            let pad = Int(e.a)
            let armedBefore = userArmed
            if pad >= 0 { userArmed = true }
            let following = followingHost
            if pad < 0 || (pad == currentLoop && (playing || (following && armedBefore))) {
                // Same pad again (or -1): stop at the end of the bar.
                queuedLoop = -1
                if !playing && !following { currentLoop = -1; queuedLoop = -2 }
            } else if !playing && !following {
                currentLoop = pad
                queuedLoop = -2
                localRun = true
                startTransport(at: 0)
            } else if currentLoop < 0 {
                currentLoop = pad
                queuedLoop = -2
                loopStartBeat = (beat / 4).rounded(.down) * 4
            } else {
                queuedLoop = pad
            }
        case .play:
            clearGates()
            if e.value >= 1 && e.value < Double(Pad.count + 1) { currentLoop = Int(e.value) - 1 }   // value: pattern + 1
            else if currentLoop < 0 { currentLoop = 0 }
            userArmed = true
            if followingHost && wasHostPlaying {
                playing = true                  // back in on the DAW's own beat
            } else {
                localRun = true
                startTransport(at: 0)
            }
        case .stop:
            midiOutAllOff(offset: offset)
            clearGates()
            userArmed = false
            localRun = false
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
            midiOutAllOff(offset: offset)
            clearGates()
            localRun = false
            playing = false
            currentLoop = -1
            queuedLoop = -2
            releaseAll()
        }
    }

    private func loopForToken(_ token: Int) -> Int? {
        if token >= 2048 && token < 2064 { return token - 2048 }
        guard token >= 0 && token < 2048 else { return nil }
        return livePad(token % 128)
    }

    private func clearGates() {
        heldLoops.update(repeating: 0, count: 2064)
        gatedToken = -1
    }

    private func beginGate(_ token: Int) {
        guard let loop = loopForToken(token) else { return }
        heldOrder &+= 1
        heldLoops[token] = heldOrder
        gatedToken = token
        currentLoop = loop
        queuedLoop = -2
        startTransport(at: 0)
    }

    private func endGate(_ token: Int) {
        guard token >= 0 && token < 2064 else { return }
        heldLoops[token] = 0
        guard gatedToken == token else { return }
        var newest: UInt64 = 0
        var next = -1
        for i in 0..<2064 where heldLoops[i] > newest { newest = heldLoops[i]; next = i }
        gatedToken = next
        if next >= 0, let loop = loopForToken(next) {
            currentLoop = loop
            queuedLoop = -2
            startTransport(at: 0)
        } else {
            currentLoop = -1
            queuedLoop = -2
            playing = false
            releaseAll()
        }
    }

    private var followingHost = false

    @inline(__always)
    static func isTransport(_ k: KEvent.Kind) -> Bool {
        switch k {
        case .midiNoteOn, .noteOff, .loopGateOn, .loopGateOff, .allOff, .loopPad, .play, .stop, .midiStart, .midiStop, .midiContinue, .midiClock, .songPosition, .countIn, .cue: return true
        default: return false
        }
    }

    private func startTransport(at b: Double) {
        playing = true
        beat = b
        loopStartBeat = b
    }

    private func releaseAll() {
        for v in 0..<KnockEngine.maxVoices where voices[v].active { voices[v].release(samples: Int(sampleRate * 0.03)) }
    }

    /// Drum roll RECORD: note a live hit at its place in the playing pattern.
    @inline(__always)
    private func record(pad: Int, velocity: Float, semis: Float, offset: Int) {
        guard recordArmed, playing, let patterns, currentLoop >= 0, currentLoop < patterns.loops.count else { return }
        let len = Double(max(patterns.loops[currentLoop].lengthTicks, 1))
        let b = beat + Double(offset) * lastBeatsPerSample
        guard b >= loopStartBeat - 1e-6 else { return }     // still counting in
        var t = ((b - loopStartBeat) * Double(PatternData.ppq)).truncatingRemainder(dividingBy: len)
        if t < 0 { t += len }
        let w = recordWrite.pointee
        recordRing[w % KnockEngine.recordCapacity] = RecordedHit(loop: Int16(currentLoop), pad: Int8(pad), tick: Int32(t),
                                                                  velocity: velocity, semis: semis)
        recordWrite.pointee = w &+ 1
    }

    /// Main thread: the hits recorded since the last call.
    func collectRecorded() -> [RecordedHit] {
        let w = recordWrite.pointee
        var out: [RecordedHit] = []
        if w &- recordRead > KnockEngine.recordCapacity { recordRead = w &- KnockEngine.recordCapacity }
        while recordRead != w {
            out.append(recordRing[recordRead % KnockEngine.recordCapacity])
            recordRead &+= 1
        }
        return out
    }

    /// Metronome clicks for this block: one on every beat the transport crosses.
    private func addClicks(frames: Int) {
        let clickLength = Int(sampleRate * 0.035)
        var nextClick = -1, accent = false
        if (metronomeOn || recordArmed || countingIn) && playing && lastBeatsPerSample > 0 {
            let first = (blockBeat0 - 1e-9).rounded(.up)
            let offset = Int(((first - blockBeat0) / lastBeatsPerSample).rounded(.down))
            if offset >= 0 && offset < frames {
                nextClick = offset
                accent = Int((first - loopStartBeat).rounded()) % 4 == 0
            }
        }
        for i in 0..<frames {
            if i == nextClick {
                clickRemaining = clickLength
                clickPhase = 0
                clickFreq = accent ? 2_200 : 1_500
                clickGain = accent ? 0.42 : 0.28
                // A second beat inside one block (very long buffers / fast tempos).
                let after = blockBeat0 + Double(i + 1) * lastBeatsPerSample
                let next = (after - 1e-9).rounded(.up)
                let o = Int(((next - blockBeat0) / lastBeatsPerSample).rounded(.down))
                if o > i && o < frames { nextClick = o; accent = Int((next - loopStartBeat).rounded()) % 4 == 0 }
            }
            guard clickRemaining > 0 else { continue }
            let env = Float(clickRemaining) / Float(clickLength)
            let s = Float(sin(clickPhase)) * clickGain * env * env
            clickPhase += 2 * .pi * clickFreq / sampleRate
            clickRemaining -= 1
            mixL[i] = (mixL[i] + s).clamped(-1, 1)
            mixR[i] = (mixR[i] + s).clamped(-1, 1)
        }
    }

    // MARK: MIDI out

    @inline(__always)
    private func pushMIDIOut(frame: Int, _ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        guard midiOutCount < KnockEngine.midiOutCapacity else { return }
        midiOut[midiOutCount] = MIDIOutMessage(frame: Int32(frame), status: status, data1: d1, data2: d2)
        midiOutCount += 1
    }

    /// A pattern hit as MIDI on its channel's own MIDI channel. The 808 sends its played pitch.
    @inline(__always)
    private func midiOutHit(pad: Int, velocity: Float, semis: Float, length: Int, offset: Int) {
        guard midiOutOn, !playingHostNote, pad >= 0, pad < Pad.count, padMask & (1 << UInt16(pad)) != 0 else { return }
        let ch = midiOutChannel[pad]
        guard ch >= 0 else { return }
        var note = Int(midiOutNote[pad])
        // The 808 plays chromatically around C3 (60), the same range BreakBoss reads back in.
        // A drum on a MIDI channel of its own sends its pitch the same way (around its note).
        if pad == Pad.bass808.rawValue { note = Pad.bassRootNote + Int(semis.rounded()) }
        else if semis != 0, ownerOfChannel(Int(ch)) == pad { note += Int(semis.rounded()) }
        note = note.clamped(0, 127)
        let frame = renderBase + max(0, offset)
        if midiOffDue[pad] >= 0 {
            pushMIDIOut(frame: frame, 0x80 | midiOffChannel[pad], midiOffNote[pad], 0)
            midiOffDue[pad] = -1
        }
        let vel = UInt8((Int((velocity * 127).rounded())).clamped(1, 127))
        pushMIDIOut(frame: frame, 0x90 | UInt8(ch), UInt8(note), vel)
        midiSentAt[Int(ch) * 128 + note] = sampleClock + Int64(frame)
        let gate = length > 0 ? length : (pad == Pad.bass808.rawValue ? Int(sampleRate * 0.3) : Int(sampleRate * 0.06))
        midiOffDue[pad] = sampleClock + Int64(frame + max(1, gate))
        midiOffChannel[pad] = UInt8(ch)
        midiOffNote[pad] = UInt8(note)
    }

    /// Note-offs that fall inside this render call, then the call's messages in time order.
    private func flushMIDIOffs(frames: Int) {
        let end = sampleClock + Int64(frames)
        for pad in 0..<Pad.count where midiOffDue[pad] >= 0 && midiOffDue[pad] < end {
            pushMIDIOut(frame: Int(max(0, midiOffDue[pad] - sampleClock)), 0x80 | midiOffChannel[pad], midiOffNote[pad], 0)
            midiOffDue[pad] = -1
        }
        guard midiOutCount > 1 else { return }
        for i in 1..<midiOutCount {      // insertion sort: a handful of messages per call
            let m = midiOut[i]
            var j = i - 1
            while j >= 0 && midiOut[j].frame > m.frame { midiOut[j + 1] = midiOut[j]; j -= 1 }
            midiOut[j + 1] = m
        }
    }

    /// Stop / all off: release every MIDI note still held.
    private func midiOutAllOff(offset: Int) {
        for pad in 0..<Pad.count where midiOffDue[pad] >= 0 {
            pushMIDIOut(frame: renderBase + max(0, offset), 0x80 | midiOffChannel[pad], midiOffNote[pad], 0)
            midiOffDue[pad] = -1
        }
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

        // Decide before choking anything: an overload rejection leaves sounding notes alone.
        guard let slot = freeVoice() else { return }

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
        // LEVEL and PAN are applied while rendering (kit.mixL / mixR), so they can move under a sounding note.
        let ml = pad < kit.mixL.count ? kit.mixL[pad] : ps.gain
        let mr = pad < kit.mixR.count ? kit.mixR[pad] : ps.gain

        // TIGHTEN shortens tails (the 808 half as much); the pad's own DECAY too.
        let tighten = params[KParam.tighten.rawValue] * (pad == Pad.bass808.rawValue ? 0.5 : 1)
        var tau: Double = .infinity
        if tighten > 0.001 { tau = 0.045 + (1 - Double(tighten)) * (1 - Double(tighten)) * 1.5 }
        if ps.decay < 0.999 { tau = min(tau, 0.03 + Double(ps.decay) * Double(ps.decay) * 2.5) }
        let coef: Float = tau.isFinite ? Float(exp(-1 / (tau * sampleRate))) : 1

        voiceAge &+= 1
        voices[slot] = Voice(sample: sample, pad: pad, rate: rate, reverse: ps.reverse, gainL: velGain, gainR: velGain,
                             decayCoef: coef, holdSamples: Int(sampleRate * 0.012), chokeGroup: group,
                             age: voiceAge, remaining: lengthSamples > 0 ? lengthSamples : Int.max, heldNote: heldNote,
                             attackSamples: max(1, Int(sampleRate * 0.0005)), filterCoefficient: kit.filterCoefficients[pad],
                             mixL: ml, mixR: mr)
        padHits[pad] &+= 1
    }

    private func freeVoice() -> Int? {
        var oldest = 0
        var oldestAge = UInt32.max
        for v in 0..<KnockEngine.maxVoices {
            if !voices[v].active { return v }
            if voices[v].age < oldestAge { oldestAge = voices[v].age; oldest = v }
        }
        // Keep playing the stolen waveform during its release. Raw sample pointers remain
        // owned by kit / oldKit; this fade is shorter than oldKit's 15 ms retention window.
        for tail in 0..<KnockEngine.maxStealTails where !stealTails[tail].active {
            stealTails[tail] = voices[oldest]
            stealTails[tail].startFade(samples: max(1, Int(sampleRate * 0.004)))
            return oldest
        }
        // An extreme burst uses all 48 slots. Drop the excess hit instead of allocating or
        // abruptly cutting a sounding waveform. Tail slots become available within 4 ms.
        return nil
    }

    private func renderVoices(from start: Int, to end: Int) {
        guard end > start else { return }
        // Level / pan glide: at most 0 -> full gain in 10 ms, the same at any buffer size.
        let step = Float(1 / (0.01 * sampleRate))
        let release = Int(sampleRate * 0.03)
        for v in 0..<KnockEngine.maxVoices where voices[v].active {
            let (tl, tr) = mixTarget(voices[v])
            voices[v].render(into: mixL + start, mixR + start, frames: end - start, releaseSamples: release,
                             targetL: tl, targetR: tr, mixStep: step)
        }
        for v in 0..<KnockEngine.maxStealTails where stealTails[v].active {
            let (tl, tr) = mixTarget(stealTails[v])
            stealTails[v].render(into: mixL + start, mixR + start, frames: end - start, releaseSamples: release,
                                 targetL: tl, targetR: tr, mixStep: step)
        }
    }

    /// Where a sounding note's level and pan are heading: its pad's current LEVEL and PAN.
    @inline(__always)
    private func mixTarget(_ voice: Voice) -> (Float, Float) {
        guard let kit, voice.pad >= 0, voice.pad < kit.mixL.count, voice.pad < kit.mixR.count else { return (voice.mixL, voice.mixR) }
        return (kit.mixL[voice.pad], kit.mixR[voice.pad])
    }

    // MARK: Loops

    /// Works out where the transport is this block and puts the loop's hits into it.
    private func scheduleLoops(frames: Int, host: HostTiming?) {
        let follow = params[KParam.followDAW.rawValue] > 0.5
        let sync = params[KParam.tempoSync.rawValue] > 0.5
        let loopMode = params[KParam.playMode.rawValue] > 0.5
        let hostHasTransport = host?.beat != nil && host?.playing != nil
        followingHost = follow && ((hostHasTransport && host?.playing == true) || clockRunning)
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
        lastBeatsPerSample = beatsPerSample
        var b0: Double
        if follow, hostHasTransport, let hb = host?.beat, let hp = host?.playing {
            if hp && !wasHostPlaying {
                releaseAll()
                if currentLoop < 0 && loopMode { currentLoop = 0 }
                userArmed = true            // the DAW starting brings BreakBoss in
                localRun = false
            }
            if !hp && wasHostPlaying { releaseAll(); localRun = false }
            wasHostPlaying = hp
            if hp {
                playing = userArmed && currentLoop >= 0
                b0 = hb
                loopStartBeat = 0
            } else {
                playing = localRun && currentLoop >= 0
                b0 = beat
            }
        } else if follow && clockRunning {
            b0 = beat
        } else {
            b0 = beat
        }
        let b1 = b0 + Double(frames) * beatsPerSample
        blockBeat0 = b0
        defer {
            beat = b1
            status[0] = playing ? 1 : 0
            status[1] = Double(currentLoop)
            status[2] = Double(queuedLoop)
            status[3] = b1
            status[8] = playing && b1 < loopStartBeat - 1e-9 ? loopStartBeat - b1 : 0
            if playing && b1 < loopStartBeat - 1e-9 {
                playheadTick.pointee = -1
            } else if playing, let patterns, currentLoop >= 0, currentLoop < patterns.loops.count {
                let len = Double(max(patterns.loops[currentLoop].lengthTicks, 1))
                let t = ((b1 - loopStartBeat) * Double(PatternData.ppq)).truncatingRemainder(dividingBy: len)
                playheadTick.pointee = t < 0 ? t + len : t
            } else {
                playheadTick.pointee = -1
            }
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
        // The BOUNCE control can move a hit between -3 and +12 ticks at maximum, a track's own swing
        // up to +8, and NOTE OFFSET / push-pull as far as the loop's earliest and latest note. Search
        // only that neighbourhood, then retain the exact timing and interval checks.
        let loose = bounce > 0.001 ? bounce * bounce : 0
        let maxSwing = max(bounce > 0.001 ? bounce * 8 + loose * 4 : 0, loop.hasOwnSwing ? 8 : 0) + max(0, loop.latest)
        let minSwing = -loose * 3 + min(0, loop.earliest)
        // One cycle either side, so swung hits near the loop's edges aren't missed.
        var cycle = max(0, (t0 / len).rounded(.down) - 1)
        let lastCycle = (t1 / len).rounded(.down) + 1
        while cycle <= lastCycle {
            let base = cycle * len
            let lower = t0 - base - maxSwing - 1e-7
            let upper = t1 - base - minSwing + 1e-7
            var k = firstEvent(loop, atOrAfter: lower)
            while k < loop.count && Double(loop.events[k].tick) < upper {
                let ev = loop.events[k]
                k += 1
                // An early note on the very first downbeat plays on it (nothing plays before the start).
                let t = max(0, base + Double(ev.tick) + Double(ev.offset)
                            + PatternData.swingTicks(tick: Int(ev.tick), pad: Int(ev.pad), bounce: bounce, own: loop.ownSwing[Int(ev.pad)]))
                guard t >= t0 && t < t1 else { continue }
                if ev.chance < 1 && PatternData.chanceRoll(pass: Int(cycle), tick: ev.tick, pad: ev.pad) >= ev.chance { continue }
                let offset = Int(((t - tBlock) * samplesPerTick).rounded(.down))
                var e = KEvent(kind: ev.pad == Int8(Pad.bass808.rawValue) ? .bass : .pad, a: Int32(ev.pad), value: Double(ev.velocity))
                if e.kind == .bass { e.a = Int32(ev.semis.rounded()) }
                let lengthSamples = ev.length > 0 ? Int(Double(ev.length) * samplesPerTick) : 0
                addBlockEvent(BlockEvent(offset: min(max(offset, 0), frames - 1), event: e, length: lengthSamples,
                                         glide: ev.glide, fromLoop: true, pad: Int(ev.pad), semis: ev.semis))
            }
            cycle += 1
        }
    }

    /// PatternSet sorts and wraps ticks before publication, outside the render callback.
    @inline(__always)
    private func firstEvent(_ loop: PatternSet.Loop, atOrAfter tick: Double) -> Int {
        var low = 0
        var high = loop.count
        while low < high {
            let mid = low + (high - low) / 2
            if Double(loop.events[mid].tick) < tick { low = mid + 1 }
            else { high = mid }
        }
        return low
    }

    // Block events carry loop info (808 length, glide).
    struct BlockEvent {
        var offset: Int = 0
        var event = KEvent(kind: .allOff)
        var length: Int = 0
        var glide = false
        var fromLoop = false
        var pad: Int = 0
        /// Per-hit pitch from the drum roll (0 for generated drum hits).
        var semis: Float = 0
    }

    // Loop hits use the same trigger with length and glide.
    private func apply(_ b: BlockEvent, offset: Int) {
        if b.fromLoop {
            if b.event.kind == .bass {
                midiOutHit(pad: Pad.bass808.rawValue, velocity: Float(b.event.value), semis: Float(b.event.a), length: b.length, offset: offset)
            } else {
                midiOutHit(pad: b.pad, velocity: Float(b.event.value), semis: b.semis, length: b.length, offset: offset)
            }
            if b.event.kind == .bass {
                trigger(pad: Pad.bass808.rawValue, velocity: Float(b.event.value), semis: Float(b.event.a),
                        lengthSamples: b.length, glide: b.glide)
            } else {
                trigger(pad: b.pad, velocity: Float(b.event.value), semis: b.semis, lengthSamples: b.length, glide: false)
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
    var attack: Float = 1
    var attackStep: Float = 0
    var fade: Float = 1
    var fadeStep: Float = 0
    var releasing = false
    var chokeGroup = 0
    var age: UInt32 = 0
    var remaining = Int.max
    var heldNote = -1
    var filterCoefficient: Float = 1
    var filterL: Float = 0
    var filterR: Float = 0
    /// The pad's LEVEL / PAN gains right now; render() glides them to the pad's current setting.
    var mixL: Float = 1
    var mixR: Float = 1

    init() {}

    init(sample: SampleBuffer, pad: Int, rate: Double, reverse: Bool, gainL: Float, gainR: Float,
         decayCoef: Float, holdSamples: Int, chokeGroup: Int, age: UInt32, remaining: Int, heldNote: Int,
         attackSamples: Int = 0, filterCoefficient: Float = 1, mixL: Float = 1, mixR: Float = 1) {
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
        if attackSamples > 0 {
            attack = 0
            attackStep = 1 / Float(attackSamples)
        }
        self.chokeGroup = chokeGroup
        self.age = age
        self.remaining = remaining
        self.heldNote = heldNote
        self.filterCoefficient = filterCoefficient
        self.mixL = mixL
        self.mixR = mixR
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
    mutating func render(into outL: UnsafeMutablePointer<Float>, _ outR: UnsafeMutablePointer<Float>, frames: Int, releaseSamples: Int,
                         targetL: Float = 1, targetR: Float = 1, mixStep: Float = 1) {
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
            var l = left[idx] + (left[idx + 1] - left[idx]) * frac
            var r = right[idx] + (right[idx + 1] - right[idx]) * frac
            if filterCoefficient < 1 {
                filterL += filterCoefficient * (l - filterL)
                filterR += filterCoefficient * (r - filterR)
                l = filterL
                r = filterR
            }
            var g = env * fade
            if hold > 0 { hold -= 1 } else { env *= decayCoef }
            if releasing {
                fade -= fadeStep
                if fade <= 0 { active = false; return }
                g = env * fade
            }
            if attack < 1 {
                g *= attack
                attack = min(1, attack + attackStep)
            }
            if g < 0.000_05 && env < 0.000_05 { active = false; return }
            if mixL != targetL { mixL = targetL > mixL ? min(targetL, mixL + mixStep) : max(targetL, mixL - mixStep) }
            if mixR != targetR { mixR = targetR > mixR ? min(targetR, mixR + mixStep) : max(targetR, mixR - mixStep) }
            outL[i] += l * g * gainL * mixL
            outR[i] += r * g * gainR * mixR
            if glideLeft > 0 {
                rate += rateStep
                glideLeft -= 1
                if glideLeft == 0 { rate = targetRate }
            }
            position += reverse ? -rate : rate
        }
    }
}
