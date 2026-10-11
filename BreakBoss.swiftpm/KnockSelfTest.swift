// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Self-test
//
// Optional test suite (BREAKBOSS_SELFTEST=1), never in normal use. No CI target is bundled.
// It checks the sound, not the screen: every kit renders, every style makes grooves, loops stay
// in time at different tempos and with the host's transport, the clipper holds its ceiling in
// all three modes, idle stays silent, and files round-trip.

enum KnockSelfTest {
    private static var failures: [String] = []
    private static var lines: [String] = []

    @discardableResult
    static func run() -> Bool {
        failures = []
        lines = []
        let started = Date()
        phase("checkKits", checkKits)
        phase("checkStockSamples", checkStockSamples)
        phase("checkGrooves", checkGrooves)
        phase("checkSmallBuffersAndVoiceStealing", checkSmallBuffersAndVoiceStealing)
        phase("checkHostMIDIAndAutomation", checkHostMIDIAndAutomation)
        phase("checkModesAndClipper", checkModesAndClipper)
        phase("checkTempoSync", checkTempoSync)
        phase("checkHostTransport", checkHostTransport)
        phase("checkSilence", checkSilence)
        phase("checkFiles", checkFiles)
        phase("checkHeldLoops", checkHeldLoops)
        phase("checkMigration", checkMigration)
        phase("checkTextureControls", checkTextureControls)
        let seconds = Date().timeIntervalSince(started)
        if failures.isEmpty {
            log("BreakBoss self-test passed (\(lines.count) checks, \(String(format: "%.1f", seconds)) s)")
        } else {
            for f in failures { log("BreakBoss SELF-TEST FAILED: \(f)") }
        }
        return failures.isEmpty
    }

    /// Persist progress before entering each phase so simulator timeouts distinguish a slow
    /// stage from a crash. The normal app never calls this optional self-test entry point.
    private static func phase(_ name: String, _ work: () -> Void) {
        log("BreakBoss self-test phase START: \(name)")
        let started = Date()
        let previousChecks = lines.count
        work()
        let seconds = Date().timeIntervalSince(started)
        log("BreakBoss self-test phase END: \(name) (\(lines.count - previousChecks) checks, \(String(format: "%.2f", seconds)) s)")
    }

    private static func check(_ ok: Bool, _ what: String) {
        lines.append(what)
        if !ok { failures.append(what) }
    }

    private static func log(_ s: String) {
        print(s)
        NSLog("%@", s)
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let url = caches.appendingPathComponent("BreakBoss-selftest.log")
            let old = (try? String(contentsOf: url)) ?? ""
            try? (old + s + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func kitBuffers(_ def: KitDefinition, rate: Double = 48_000) -> KitBuffers {
        let samples = def.pads.enumerated().map { DrumSynth.render($0.element, sampleRate: rate, seed: UInt32($0.offset + 1)) }
        return KitBuffers(name: def.name, samples: samples, settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: def.bassHz)
    }

    static func checkKits() {
        for def in KitLibrary.factory {
            check(def.pads.count == Pad.count, "\(def.name): 16 pads")
            for (i, r) in def.pads.enumerated() {
                let b = DrumSynth.render(r, sampleRate: 48_000, seed: 7)
                var peak: Float = 0
                var finite = true
                for k in 0..<b.length {
                    let v = max(abs(b.left[k]), abs(b.right[k]))
                    if !v.isFinite { finite = false; break }
                    peak = max(peak, v)
                }
                check(finite, "\(def.name) pad \(i + 1) finite")
                check(peak > 0.2 && peak <= 1.0, "\(def.name) pad \(i + 1) level \(peak)")
                check(b.seconds < 4, "\(def.name) pad \(i + 1) length \(b.seconds)")
            }
        }
        // Dice variations stay sensible
        var rng = KRandom(seed: 99)
        for r in KitLibrary.modernTrap.pads {
            let v = r.varied(&rng)
            let b = DrumSynth.render(v, sampleRate: 44_100, seed: 3)
            check(b.length > 100, "varied \(r.label) renders")
        }
    }

    /// Validate the shipped audio through the same AVAudioFile decoder as the normal kit
    /// loader. This optional off-callback suite retains URLs only, and releases each decoded
    /// buffer before opening the next file instead of keeping the whole sound bank in RAM.
    static func checkStockSamples() {
        #if canImport(AVFoundation)
        let manifestExists = knockResourceURL("manifest", "json") != nil
        check(manifestExists, "stock audio manifest is bundled")
        guard manifestExists else { return }
        let library = StockSampleLibrary.bundled
        check(library.failure == nil, "stock audio manifest loads: \(library.failure ?? "OK")")
        guard library.failure == nil else { return }

        var urls = Set<URL>()
        var assignments = 0
        for kit in KitLibrary.factory {
            for pad in Pad.allCases {
                let sample = library.sample(kitID: kit.id, pad: pad.rawValue)
                check(sample != nil, "\(kit.name) pad \(pad.rawValue + 1) has bundled stock audio")
                if let sample {
                    assignments += 1
                    urls.insert(sample.url)
                }
            }
        }
        check(assignments == 544, "stock audio covers all 544 factory pad assignments")
        check(urls.count == 308, "stock audio contains 308 distinct assigned WAV files")
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            autoreleasepool {
                do {
                    let buffer = try SampleLoader.load(url)
                    check(abs(buffer.sampleRate - 48_000) < 1, "\(url.lastPathComponent): decodes at 48 kHz")
                    check(buffer.length > 0 && buffer.seconds <= 4, "\(url.lastPathComponent): bounded stock duration")
                    var peak: Float = 0
                    var finite = true
                    for frame in 0..<buffer.length {
                        let left = buffer.left[frame], right = buffer.right[frame]
                        if !left.isFinite || !right.isFinite { finite = false; break }
                        peak = max(peak, max(abs(left), abs(right)))
                    }
                    check(finite, "\(url.lastPathComponent): decoded stereo audio is finite")
                    check(peak > 0.005 && peak <= 1.000_01, "\(url.lastPathComponent): decoded stock audio is audible and bounded")
                } catch {
                    check(false, "\(url.lastPathComponent): stock audio decodes (\(error.localizedDescription))")
                }
            }
        }
        #endif
    }

    static func checkGrooves() {
        for style in GrooveStyle.allCases {
            for seed: UInt32 in [1, 2, 77, 12345] {
                let loops = GrooveGenerator.loops(style: style, seed: seed)
                check(loops.count == Pad.count, "\(style) seed \(seed): 16 loops")
                for (i, p) in loops.enumerated() {
                    check(!p.events.isEmpty, "\(style) loop \(i + 1) has hits")
                    check(p.lengthTicks % (PatternData.ppq * 4) == 0, "\(style) loop \(i + 1) whole bars")
                    check(p.events.allSatisfy { $0.pad >= 0 && Int($0.pad) < Pad.count && $0.velocity > 0 && $0.velocity <= 1 },
                          "\(style) loop \(i + 1) valid hits")
                    check(p.events.count <= GrooveGenerator.maxGeneratedEvents,
                          "\(style) loop \(i + 1) bounded phrase density")
                    check(p.events.allSatisfy { $0.tick >= 0 && $0.tick < p.lengthTicks && $0.semis.isFinite && $0.velocity.isFinite },
                          "\(style) loop \(i + 1) finite events inside phrase")
                    check(zip(p.events, p.events.dropFirst()).allSatisfy { $0.0.tick <= $0.1.tick },
                          "\(style) loop \(i + 1) events sorted")
                    for bar in 0..<p.bars {
                        let start = Int32(bar) * PatternData.ppq * 4
                        let count = p.events.filter { $0.tick >= start && $0.tick < start + PatternData.ppq * 4 }.count
                        check(count <= GrooveGenerator.maxGeneratedEventsPerBar,
                              "\(style) loop \(i + 1) bar \(bar) bounded density")
                    }
                    let bass = p.events.filter { $0.pad == Int8(Pad.bass808.rawValue) }
                    check(bass.allSatisfy { $0.length > 0 && $0.tick + $0.length <= p.lengthTicks },
                          "\(style) loop \(i + 1) bass gates remain inside phrase")
                    let closed = Set(p.events.filter { $0.pad == Int8(Pad.hat.rawValue) }.map { $0.tick })
                    check(!p.events.contains { $0.pad == Int8(Pad.openHat.rawValue) && closed.contains($0.tick) },
                          "\(style) loop \(i + 1) no same-tick hat choke conflict")
                }
                check(Array(loops.prefix(4)).map { $0.bars } == [2, 4, 8, 4], "\(style): main phrase lengths")
                check(loops[LoopSlot.no808.rawValue].events.allSatisfy { $0.pad != Int8(Pad.bass808.rawValue) },
                      "\(style): No 808 excludes bass")
                check(loops[LoopSlot.kick808.rawValue].events.allSatisfy {
                    $0.pad == Int8(Pad.kick.rawValue) || $0.pad == Int8(Pad.bass808.rawValue)
                }, "\(style): Kick + 808 has only its two lanes")
                check(loops[LoopSlot.shakerGroove.rawValue].events.allSatisfy { $0.pad == Int8(Pad.shaker.rawValue) },
                      "\(style): shaker slot keeps its role")
                // The main groove has a backbeat (snare or clap or rim) and a kick.
                let a = loops[0]
                check(a.events.contains { $0.pad == Int8(Pad.kick.rawValue) }, "\(style) main A has a kick")
                check(a.events.contains { [Pad.snare.rawValue, Pad.clap.rawValue, Pad.rim.rawValue].contains(Int($0.pad)) },
                      "\(style) main A has a backbeat")
            }
            // Same seed, same grooves
            check(GrooveGenerator.loops(style: style, seed: 5) == GrooveGenerator.loops(style: style, seed: 5), "\(style) repeatable")
        }
    }

    /// These regressions check audio continuity; they do not measure device callback timing.
    static func checkSmallBuffersAndVoiceStealing() {
        let rate = 48_000.0
        let total = 6_144
        let sine = (0..<(total + 4)).map { Float(sin(Double($0) * 2 * Double.pi * 110 / rate)) * 0.06 }
        let sample = SampleBuffer(left: sine, sampleRate: rate)
        let settings = Array(repeating: PadSettings(), count: Pad.count)
        let kit = KitBuffers(name: "BUFFER REGRESSION", samples: Array(repeating: sample, count: Pad.count),
                             settings: settings, bassHz: 110)

        func makeEngine(_ kit: KitBuffers, mode: SoundMode) -> KnockEngine {
            let engine = KnockEngine()
            engine.prepare(sampleRate: rate, maxFrames: 512)
            engine.setParam(.playMode, 0)
            engine.setParam(.followDAW, 0)
            engine.setParam(.tempoSync, 0)
            engine.setParam(.soundMode, Float(mode.rawValue))
            engine.setParam(.boost, 0)
            engine.setParam(.filter, 1)
            engine.kitHandoff.publish(kit)
            return engine
        }

        func trace(_ mode: SoundMode, block: Int) -> ([Float], [Float]) {
            let engine = makeEngine(kit, mode: mode)
            engine.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 0.8))
            var left = [Float](repeating: 0, count: total), right = left
            var done = 0
            while done < total {
                let count = min(block, total - done)
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        engine.render(frames: count, left: l.baseAddress! + done, right: r.baseAddress! + done, host: nil)
                    }
                }
                done += count
            }
            return (left, right)
        }

        for mode in SoundMode.allCases {
            let small = trace(mode, block: 128)
            let large = trace(mode, block: 512)
            var difference: Float = 0
            for i in 0..<total {
                difference = max(difference, max(abs(small.0[i] - large.0[i]), abs(small.1[i] - large.1[i])))
            }
            check(small.0.allSatisfy { $0.isFinite } && small.1.allSatisfy { $0.isFinite }, "\(mode): 128-frame output finite")
            check(small.0.contains { abs($0) > 0.001 }, "\(mode): 128-frame output audible")
            check(difference < 0.000_01, "\(mode): isolated audio matches at 128/512 frames (\(difference))")
        }

        // Constant signals make an abrupt stolen-voice cut visible. The replacement's
        // higher level also prevents a same-amplitude replacement from hiding that cut.
        let old = SampleBuffer(left: Array(repeating: Float(0.01), count: 12_000), sampleRate: rate)
        let replacement = SampleBuffer(left: Array(repeating: Float(0.025), count: 12_000), sampleRate: rate)
        var samples = Array(repeating: old, count: Pad.count)
        samples[Pad.snare.rawValue] = replacement
        let stealKit = KitBuffers(name: "STEAL REGRESSION", samples: samples, settings: settings, bassHz: 110)
        let baseline = makeEngine(stealKit, mode: .modern)
        let overloaded = makeEngine(stealKit, mode: .modern)
        for engine in [baseline, overloaded] {
            engine.setParam(.clipper, 0)
            for _ in 0..<KnockEngine.maxVoices {
                engine.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 1))
            }
            var left = [Float](repeating: 0, count: 512), right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    engine.render(frames: 512, left: l.baseAddress!, right: r.baseAddress!, host: nil)
                }
            }
        }
        // Exceed both the primary voices and the small fading-tail reserve at once.
        for _ in 0..<32 {
            overloaded.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 1))
        }
        func nextBlock(_ engine: KnockEngine) -> [Float] {
            var left = [Float](repeating: 0, count: 128), right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    engine.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil)
                }
            }
            return left
        }
        let reference = nextBlock(baseline)
        let burst = nextBlock(overloaded)
        check(burst.allSatisfy { $0.isFinite }, "voice overload keeps audio finite")
        check(abs(burst[0] - reference[0]) < 0.002, "voice overload begins without an abrupt cut")
        check(burst.contains { abs($0) > 0.001 }, "voice overload keeps existing audio audible")
    }

    /// The AU adapter queues notes before render(). Their offsets must survive the control
    /// snapshot and kit handoff, including gates that change loop scheduling within a block.
    static func checkHostMIDIAndAutomation() {
        let rate = 48_000.0
        let sample = SampleBuffer(left: Array(repeating: Float(0.025), count: 12_000), sampleRate: rate)
        let kit = KitBuffers(name: "HOST EVENT REGRESSION", samples: Array(repeating: sample, count: Pad.count),
                             settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110)
        let firstHit = PatternData(name: "GATE", lengthTicks: PatternData.ppq * 4,
                                   events: [GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1)])
        func engine(loop: Bool = false) -> KnockEngine {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            e.setParam(.playMode, loop ? 1 : 0)
            e.setParam(.followDAW, 0)
            e.setParam(.tempoSync, 0)
            e.setParam(.boost, 0)
            e.setParam(.clipper, 0)
            e.setParam(.clipDrive, 0)
            e.kitHandoff.publish(kit)
            e.patternHandoff.publish(PatternSet(Array(repeating: firstHit, count: Pad.count)))
            return e
        }
        func block(_ e: KnockEngine, _ frames: Int) -> [Float] {
            var left = [Float](repeating: 0, count: frames), right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    e.render(frames: frames, left: l.baseAddress!, right: r.baseAddress!, host: nil)
                }
            }
            return left
        }
        func maxDifference(_ a: [Float], _ b: [Float]) -> Float {
            var difference: Float = 0
            for i in a.indices { difference = max(difference, abs(a[i] - b[i])) }
            return difference
        }
        for note: UInt8 in [36, 48, 85] {
            let e = engine()
            e.hostMIDI(offset: 73, status: 0x90, data1: note, data2: 127)
            let actual = block(e, 128)
            check(actual.prefix(73).allSatisfy { abs($0) < 0.000_001 }, "host MIDI \(note): silent before sample 73")
            check(actual.dropFirst(73).contains { abs($0) > 0.001 }, "host MIDI \(note): sounds after sample 73 on first callback")
        }

        let carried = engine()
        carried.hostMIDI(offset: 191, status: 0x90, data1: 36, data2: 127)
        check(block(carried, 128).allSatisfy { abs($0) < 0.000_001 }, "host MIDI: future offset remains silent in first block")
        let carriedOutput = block(carried, 128)
        check(carriedOutput.prefix(63).allSatisfy { abs($0) < 0.000_001 } &&
              carriedOutput.dropFirst(63).contains { abs($0) > 0.001 }, "host MIDI: offset carries across 128-frame boundary")

        let actualBass = engine(), expectedBass = engine()
        for e in [actualBass, expectedBass] {
            e.hostMIDI(offset: 0, status: 0x90, data1: 60, data2: 127)
            _ = block(e, 128)
        }
        actualBass.hostMIDI(offset: 77, status: 0x80, data1: 60, data2: 0)
        let actualRelease = block(actualBass, 128)
        var expectedRelease = block(expectedBass, 77)
        expectedBass.hostMIDI(offset: 0, status: 0x80, data1: 60, data2: 0)
        expectedRelease += block(expectedBass, 51)
        check(maxDifference(actualRelease, expectedRelease) < 0.000_001, "host bass release begins at its sample offset")

        let actualLoop = engine(loop: true), expectedLoop = engine(loop: true)
        actualLoop.hostMIDI(offset: 73, status: 0x90, data1: 36, data2: 127)
        actualLoop.hostMIDI(offset: 193, status: 0x80, data1: 36, data2: 0)
        let actualGate = block(actualLoop, 256)
        var expectedGate = block(expectedLoop, 73)
        expectedLoop.hostMIDI(offset: 0, status: 0x90, data1: 36, data2: 127)
        expectedGate += block(expectedLoop, 120)
        expectedLoop.hostMIDI(offset: 0, status: 0x80, data1: 36, data2: 0)
        expectedGate += block(expectedLoop, 63)
        check(actualGate.prefix(73).allSatisfy { abs($0) < 0.000_001 } &&
              actualGate.dropFirst(73).contains { abs($0) > 0.001 }, "host loop gate starts on sample 73")
        check(maxDifference(actualGate, expectedGate) < 0.000_001 && actualLoop.status[0] == 0,
              "host loop gate schedules and releases at host offsets")

        let automated = engine()
        automated.hostParameter(.playMode, 42)
        automated.hostParameter(.pitch, -5)
        automated.hostParameter(.output, .nan)
        automated.hostMIDI(offset: 73, status: 0x90, data1: 36, data2: 127)
        let automatedGate = block(automated, 128)
        check(automated.param(.playMode) == 1 && automated.param(.pitch) == 0 &&
              automated.param(.output) == KParam.output.defaultValue, "host automation normalizes and publishes values")
        check(automatedGate.prefix(73).allSatisfy { abs($0) < 0.000_001 } && automated.status[0] == 1,
              "host play-mode automation precedes MIDI classification")

        // Control-plane updates contend with the render snapshot; callbacks keep using local
        // pending automation. This exercises publication retries, not device timing budgets.
        let contended = engine()
        let writers = DispatchGroup()
        writers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<2_000 {
                contended.setParam(.tune, Float(i % 100) / 100)
                contended.setTempo(Double(80 + i % 80))
            }
            writers.leave()
        }
        var finite = true
        for i in 0..<64 {
            contended.hostParameter(.pitch, Float(i % 2))
            contended.hostMIDI(offset: 63, status: 0x90, data1: 36, data2: 100)
            finite = finite && block(contended, 128).allSatisfy { $0.isFinite }
        }
        writers.wait()
        contended.hostParameter(.pitch, 0.75)
        _ = block(contended, 128)
        check(finite && contended.param(.pitch) == 0.75, "host automation survives concurrent UI control updates")
    }

    /// Renders a loop through a fresh engine and returns the output.
    private static func render(kit: KitBuffers, style: GrooveStyle, mode: SoundMode, tempo: Double, seconds: Double,
                               tweak: (KnockEngine) -> Void = { _ in }) -> ([Float], [Float]) {
        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        engine.setParam(.soundMode, Float(mode.rawValue))
        engine.setParam(.followDAW, 0)
        engine.setParam(.tempoSync, 0)
        engine.setTempo(tempo)
        tweak(engine)
        engine.kitHandoff.publish(kit)
        engine.patternHandoff.publish(PatternSet(GrooveGenerator.loops(style: style, seed: 1)))
        engine.send(KEvent(kind: .loopPad, a: 0))
        let total = Int(seconds * 48_000)
        var outL = [Float](repeating: 0, count: total), outR = [Float](repeating: 0, count: total)
        var done = 0
        while done < total {
            let n = min(256, total - done)
            outL.withUnsafeMutableBufferPointer { l in
                outR.withUnsafeMutableBufferPointer { r in
                    engine.render(frames: n, left: l.baseAddress! + done, right: r.baseAddress! + done, host: nil)
                }
            }
            done += n
        }
        return (outL, outR)
    }

    static func checkModesAndClipper() {
        let kit = kitBuffers(KitLibrary.modernTrap)
        for mode in SoundMode.allCases {
            let (l, r) = render(kit: kit, style: .trap, mode: mode, tempo: 140, seconds: 4) { e in
                e.setParam(.clipDrive, 1)      // +18 dB into the clipper
                e.setParam(.boost, 1); e.setParam(.punch, 1); e.setParam(.grit, 1); e.setParam(.shine, 1); e.setParam(.noise, 0.6)
            }
            var peak: Float = 0
            var finite = true
            var energy: Double = 0
            for i in 0..<l.count {
                if !l[i].isFinite || !r[i].isFinite { finite = false; break }
                peak = max(peak, abs(l[i]), abs(r[i]))
                energy += Double(l[i] * l[i])
            }
            check(finite, "\(mode.title): finite at full drive")
            check(peak <= MasterBus.ceiling + 0.0005, "\(mode.title): clipper ceiling held (\(peak))")
            check(energy > 100, "\(mode.title): makes sound")
        }
        // Clipper off passes level through (OUTPUT 0 dB, low drive): no clipping applied.
        let (l, _) = render(kit: kit, style: .trap, mode: .modern, tempo: 140, seconds: 2) { e in
            e.setParam(.clipper, 0); e.setParam(.clipDrive, 0)
        }
        check(l.contains { abs($0) > 0.05 }, "clipper off still sounds")
    }

    /// The first kick of each bar must land on the bar line at several tempos.
    static func checkTempoSync() {
        var kick = Array(repeating: PadSettings(), count: Pad.count)
        kick[Pad.kick.rawValue].level = 0.8
        let def = KitLibrary.modernTrap
        // A kit where only the kick sounds, so onsets are easy to find.
        let samples = def.pads.enumerated().map { i, r -> SampleBuffer in
            i == Pad.kick.rawValue ? DrumSynth.render(r, sampleRate: 48_000, seed: 1) : SampleBuffer(left: [0, 0, 0, 0], sampleRate: 48_000)
        }
        let kit = KitBuffers(name: "test", samples: samples, settings: kick, bassHz: def.bassHz)
        for tempo in [72.0, 101.0, 140.0, 172.0] {
            let (l, _) = render(kit: kit, style: .trap, mode: .modern, tempo: tempo, seconds: 60 / tempo * 4 * 2 + 0.2) { e in
                e.setParam(.clipper, 0); e.setParam(.boost, 0)
            }
            let barSamples = 60 / tempo * 4 * 48_000
            for bar in 0..<2 {
                let expected = Int(Double(bar) * barSamples)
                let window = l[max(0, expected - 200)..<min(l.count, expected + 600)]
                let onset = window.firstIndex { abs($0) > 0.02 } ?? -99_999
                // The oversampled clipper path adds 15 samples; allow a few more.
                check(abs(onset - expected) <= 40, "tempo \(Int(tempo)) bar \(bar + 1) kick on the line (\(onset - expected) samples)")
            }
        }
    }

    /// FOLLOW DAW: the loop starts with the host's transport, at the host's bar position.
    static func checkHostTransport() {
        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        engine.setParam(.followDAW, 1)
        engine.setParam(.tempoSync, 1)
        engine.setParam(.playMode, 1)
        engine.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        engine.patternHandoff.publish(PatternSet(GrooveGenerator.loops(style: .trap, seed: 1)))
        var l = [Float](repeating: 0, count: 512), r = [Float](repeating: 0, count: 512)
        var beat = 0.0
        let tempo = 120.0
        var heard = false
        var heardWhileStopped = false
        for block in 0..<400 {
            let playing = block >= 100
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    engine.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!,
                                  host: HostTiming(tempo: tempo, beat: beat, playing: playing))
                }
            }
            let loud = l.contains { abs($0) > 0.01 }
            if playing { if loud { heard = true }; beat += 512 / 48_000 * tempo / 60 } else if loud { heardWhileStopped = true }
        }
        check(!heardWhileStopped, "FOLLOW DAW: silent while the DAW is stopped")
        check(heard, "FOLLOW DAW: plays when the DAW plays")
        check(abs(engine.status[4] - tempo) < 0.01, "TEMPO SYNC: uses the DAW's tempo")
    }

    /// Nothing playing: silence (and after a while the chain stops running).
    static func checkSilence() {
        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        engine.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var l = [Float](repeating: 1, count: 512), r = [Float](repeating: 1, count: 512)
        var maxOut: Float = 0
        for _ in 0..<600 {
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    engine.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
                }
            }
            maxOut = max(maxOut, l.map { abs($0) }.max() ?? 0)
        }
        check(maxOut < 1e-4, "idle is silent (\(maxOut))")
        // A pad hit after idling sounds right away.
        engine.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 1))
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                engine.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
            }
        }
        check(l.contains { abs($0) > 0.05 }, "pad sounds after idle")
    }

    static func checkFiles() {
        let loops = GrooveGenerator.loops(style: .west90s, seed: 3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest.mid")
        do {
            try MIDIFile.write(loops[0], tempo: 95, bounce: 0, bars: loops[0].bars, to: url)
            let back = MIDIFile.read(url)
            check(back != nil, "MIDI file reads back")
            if let back {
                check(back.events.count == loops[0].events.count, "MIDI round trip keeps every hit (\(back.events.count)/\(loops[0].events.count))")
                check(back.lengthTicks == loops[0].lengthTicks, "MIDI round trip keeps the length")
            }
        } catch {
            check(false, "MIDI file writes: \(error)")
        }
        var s = KnockState()
        s.values["boost"] = 0.3
        s.editedLoops[2] = loops[1]
        let data = try? JSONEncoder().encode(s)
        let decoded = data.flatMap { try? JSONDecoder().decode(KnockState.self, from: $0) }
        check(decoded == s, "saved state round trip")
        // Export renders a seamless loop of the right length
        let kit = kitBuffers(KitLibrary.west90s)
        var params = [Float](repeating: 0, count: KParam.count)
        for p in KParam.allCases { params[p.rawValue] = p.defaultValue }
        let job = Exporter.Job(kit: kit, patterns: PatternSet(loops), loop: 0, params: params, tempo: 95, bars: 2, baseName: "selftest")
        let (l, _) = Exporter.render(job, mask: 0xFFFF)
        check(l.count == Int((Double(2) * 4 * (60 / 95.0 * 48_000)).rounded()), "export length is exactly 2 bars")
        check(l.contains { abs($0) > 0.05 }, "export makes sound")
    }
    private static func renderBlock(_ engine: KnockEngine) {
        var l = [Float](repeating: 0, count: 256), r = l
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                engine.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
            }
        }
    }

    static func checkHeldLoops() {
        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 1)
        e.setParam(.followDAW, 0)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        e.patternHandoff.publish(PatternSet(GrooveGenerator.loops(style: .trap, seed: 1)))
        e.receiveMIDI(status: 0x90, data1: 36, data2: 100, time: 0)
        renderBlock(e)
        check(e.status[0] == 1 && e.status[1] == 0, "MIDI hold starts loop")
        e.receiveMIDI(status: 0x91, data1: 37, data2: 100, time: 0)
        renderBlock(e)
        check(e.status[1] == 1, "last-held note takes priority")
        e.receiveMIDI(status: 0x81, data1: 37, data2: 0, time: 0)
        renderBlock(e)
        check(e.status[0] == 1 && e.status[1] == 0, "release returns to previous held note")
        e.receiveMIDI(status: 0x90, data1: 36, data2: 0, time: 0)
        renderBlock(e)
        check(e.status[0] == 0 && e.status[1] == -1, "zero velocity note-on releases final loop")
        e.receiveMIDI(status: 0x90, data1: 88, data2: 127, time: 0)
        renderBlock(e)
        check(e.status[1] == 15, "MIDI reaches loop 16")
        e.receiveMIDI(status: 0xB0, data1: 123, data2: 0, time: 0)
        renderBlock(e)
        check(e.status[0] == 0, "all notes off stops loop sequencing")
        e.setParam(.playMode, 0)
        for pad in Pad.allCases {
            let before = e.padHits[pad.rawValue]
            e.receiveMIDI(status: 0x90, data1: UInt8(pad.midiNote), data2: 100, time: 0)
            renderBlock(e)
            check(e.padHits[pad.rawValue] > before, "MIDI plays pad \(pad.rawValue + 1)")
        }
        let bassBefore = e.padHits[Pad.bass808.rawValue]
        e.receiveMIDI(status: 0x90, data1: 48, data2: 100, time: 0)
        renderBlock(e)
        check(e.padHits[Pad.bass808.rawValue] > bassBefore, "legacy note 48 still plays chromatic 808")
        e.setParam(.playMode, 1)
        for _ in 0..<1200 { e.receiveMIDI(status: 0x90, data1: 36, data2: 100, time: 0) }
        renderBlock(e)
        check(e.status[0] == 0, "queue overflow fails silent instead of stuck loop")
        for i in 0..<40 {
            e.kitHandoff.publish(kitBuffers(i % 2 == 0 ? KitLibrary.modernTrap : KitLibrary.west90s))
            e.send(KEvent(kind: .pad, a: 0, value: 1))
            for _ in 0..<4 { renderBlock(e) }
            e.kitHandoff.collect()
        }
        check(e.status[7] > 0, "rapid kit switches keep rendering")
    }

    static func checkMigration() {
        var old = KnockState()
        old.pads = Array(repeating: PadSettings(), count: 12)
        old.pads[0].tune = 7
        old.editedLoops = Array(repeating: nil, count: 12)
        old.editedLoops[2] = PatternData(name: "KEEP", lengthTicks: 384, events: [])
        let new = old.normalized()
        check(new.pads.count == 16 && new.pads[0].tune == 7, "12-pad kits migrate without losing pad settings")
        check(new.editedLoops.count == 16 && new.editedLoops[2]?.name == "KEEP", "12-loop presets preserve edits")
        check(KitLibrary.core.count == 17 && KitLibrary.textures.count == 7 && KitLibrary.legacy.count == 10 && KitLibrary.factory.count == 34,
              "34 factory kits include 17 core, seven textures, and ten original kits")
        check(Set(KitLibrary.factory.map { $0.id }).count == KitLibrary.factory.count, "factory kit identifiers unique")
        check(Pad.allCases.allSatisfy { Pad.index(forMIDINote: $0.midiNote) == $0.rawValue }, "all pad MIDI mappings round trip")
    }

    static func checkTextureControls() {
        let kit = kitBuffers(KitLibrary.modernTrap)
        for parameter in [KParam.resample, .instability, .textureDelay, .gatedReverb, .drive] {
            let (a, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 120, seconds: 1) { $0.setParam(parameter, 0) }
            let (b, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 120, seconds: 1) { $0.setParam(parameter, 1) }
            var difference: Double = 0
            for i in a.indices { difference += Double(abs(a[i] - b[i])) }
            check(difference > 0.1, "\(parameter.name) changes texture output")
            check(b.allSatisfy { $0.isFinite && abs($0) <= MasterBus.ceiling + 0.001 }, "\(parameter.name) stays finite and clipped")
        }
    }

}
