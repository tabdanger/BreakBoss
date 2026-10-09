// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Self-test
//
// Runs on GitHub's iPad simulator after every build (BREAKBOSS_SELFTEST=1), never in normal use.
// It checks the sound, not the screen: every kit renders, every style makes grooves, loops stay
// in time at different tempos and with the host's transport, the clipper holds its ceiling in
// all three modes, idle stays silent, and files round-trip.

enum KnockSelfTest {
    private static var failures: [String] = []
    private static var lines: [String] = []

    static func run() {
        failures = []
        lines = []
        let started = Date()
        checkKits()
        checkGrooves()
        checkModesAndClipper()
        checkTempoSync()
        checkHostTransport()
        checkSilence()
        checkFiles()
        let seconds = Date().timeIntervalSince(started)
        if failures.isEmpty {
            log("BreakBoss self-test passed (\(lines.count) checks, \(String(format: "%.1f", seconds)) s)")
        } else {
            for f in failures { log("BreakBoss SELF-TEST FAILED: \(f)") }
        }
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
            check(def.pads.count == Pad.count, "\(def.name): 12 pads")
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

    static func checkGrooves() {
        for style in GrooveStyle.allCases {
            for seed: UInt32 in [1, 2, 77, 12345] {
                let loops = GrooveGenerator.loops(style: style, seed: seed)
                check(loops.count == 12, "\(style) seed \(seed): 12 loops")
                for (i, p) in loops.enumerated() {
                    check(!p.events.isEmpty, "\(style) loop \(i + 1) has hits")
                    check(p.lengthTicks % (PatternData.ppq * 4) == 0, "\(style) loop \(i + 1) whole bars")
                    check(p.events.allSatisfy { $0.pad >= 0 && Int($0.pad) < Pad.count && $0.velocity > 0 && $0.velocity <= 1 },
                          "\(style) loop \(i + 1) valid hits")
                }
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

    /// Renders a loop through a fresh engine and returns the output.
    private static func render(kit: KitBuffers, style: GrooveStyle, mode: SoundMode, tempo: Double, seconds: Double,
                               tweak: (KnockEngine) -> Void = { _ in }) -> ([Float], [Float]) {
        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        engine.setParam(.soundMode, Float(mode.rawValue))
        engine.setParam(.followDAW, 0)
        engine.setParam(.tempoSync, 0)
        engine.displayBPM.pointee = tempo
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
}
