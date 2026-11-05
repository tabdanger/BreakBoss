// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import AVFoundation
import UIKit

// MARK: - Self-test: Modes, clipper, tempo sync, host transport, silence, files, loops, empty pads, MIDI pad maps and latency

extension KnockSelfTest {
    /// Renders a loop through a fresh engine and returns the output.
    static func render(kit: KitBuffers, style: GrooveStyle, mode: SoundMode, tempo: Double, seconds: Double,
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
                e.setParam(.drive, 1)          // Vintage / Texture: DRIVE in BOOST's place
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
        // BreakBoss's own STOP / PLAY still work while the DAW runs.
        func run(_ blocks: Int) -> Bool {
            var loud = false
            for _ in 0..<blocks {
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        engine.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!,
                                      host: HostTiming(tempo: tempo, beat: beat, playing: true))
                    }
                }
                beat += 512 / 48_000 * tempo / 60
                if l.contains(where: { abs($0) > 0.01 }) { loud = true }
            }
            return loud
        }
        engine.send(KEvent(kind: .stop))
        _ = run(40)
        check(!run(200), "FOLLOW DAW: BreakBoss STOP mutes the pattern while the DAW keeps playing")
        engine.send(KEvent(kind: .play))
        check(run(200), "FOLLOW DAW: BreakBoss PLAY brings the pattern back on the DAW's beat")
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
        // An empty pattern on the sequencer is silent, even when the other patterns have notes:
        // PLAY and the DAW start the pattern on screen (the cue), not the last one that played.
        let cueEngine = KnockEngine()
        cueEngine.prepare(sampleRate: 48_000, maxFrames: 512)
        cueEngine.setParam(.followDAW, 0)
        cueEngine.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var cueLoops = GrooveGenerator.loops(style: .trap, seed: 1)
        cueLoops[3] = PatternData(name: "EMPTY", lengthTicks: cueLoops[3].lengthTicks, events: [])
        cueEngine.patternHandoff.publish(PatternSet(cueLoops))
        func loud(_ e: KnockEngine, blocks: Int) -> Bool {
            var heard = false
            for _ in 0..<blocks {
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        e.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
                    }
                }
                if l.contains(where: { abs($0) > 0.01 }) { heard = true }
            }
            return heard
        }
        cueEngine.send(KEvent(kind: .loopPad, a: 0))
        check(loud(cueEngine, blocks: 100), "cue test: pattern 1 plays")
        cueEngine.send(KEvent(kind: .stop))
        _ = loud(cueEngine, blocks: 40)
        cueEngine.send(KEvent(kind: .cue, a: 3))
        cueEngine.send(KEvent(kind: .play))
        check(!loud(cueEngine, blocks: 200), "an empty pattern on the sequencer plays nothing")
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
            let allPads = PatternData(name: "ALL 12 MIDI PADS", lengthTicks: PatternData.ppq * 4,
                                      events: Pad.allCases.map { pad in
                GrooveEvent(tick: Int32(pad.rawValue * 12), pad: Int8(pad.rawValue), velocity: 0.75,
                            length: pad == .bass808 ? 12 : 0)
            })
            try MIDIFile.write(allPads, tempo: 95, bounce: 0, bars: 1, to: url)
            let allPadsBack = MIDIFile.read(url)
            check(allPadsBack?.events.count == Pad.count &&
                  Set(allPadsBack?.events.map { Int($0.pad) } ?? []) == Set(Pad.allCases.map { $0.rawValue }),
                  "MIDI export and import preserve all 12 sequential drum pads")
            let lowBass = PatternData(name: "LOW 808 MIDI", lengthTicks: PatternData.ppq * 4,
                                      events: [GrooveEvent(tick: 0, pad: Int8(Pad.bass808.rawValue), velocity: 1,
                                                           semis: -12, length: 96)])
            try MIDIFile.write(lowBass, tempo: 95, bounce: 0, bars: 1, to: url)
            let bassBack = MIDIFile.read(url)?.events.first
            check(bassBack?.pad == Int8(Pad.bass808.rawValue) && bassBack?.semis == -12 && bassBack?.length == 96,
                  "MIDI export keeps a low 808 on note 48, just above the pads")
            check(lowBass.events[0].semis == -12, "MIDI pitch bounding leaves authored and audio-export bass pitch unchanged")
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
    static func renderBlock(_ engine: KnockEngine) {
        var l = [Float](repeating: 0, count: 256), r = l
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                engine.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
            }
        }
    }

    /// Face 2's playhead line (PlayheadSmoother): with the engine's clock arriving once per audio
    /// block, the line still moves the same distance every 120 Hz frame, follows the engine and
    /// wraps at the loop's end.
    static func checkPlayheadGlide() {
        for block in [256, 1_024] {
            let e = KnockEngine()
            e.prepare(sampleRate: 48_000, maxFrames: block)
            e.setParam(.playMode, 1)
            e.setParam(.followDAW, 0)
            e.setParam(.tempoSync, 0)
            e.setTempo(120)
            e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
            let bar = PatternEdit.barTicks
            let p = PatternData(name: "GLIDE", lengthTicks: bar, events: [GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1)])
            e.patternHandoff.publish(PatternSet(Array(repeating: p, count: Pad.count)))
            var l = [Float](repeating: 0, count: block), r = l
            var audio = 0.0
            func render() {
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        e.render(frames: block, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
                    }
                }
                audio += Double(block) / 48_000
            }
            render()
            e.send(KEvent(kind: .loopPad, a: 0))
            render()
            let perSecond = 120.0 / 60 * Double(PatternData.ppq)
            let length = Double(bar)
            var smooth = PlayheadSmoother()
            var lastRaw: Double?, lastShown: Double?
            var rawWorst = 0.0, shownWorst = 0.0, lag = 0.0, wrapped = false, jumps = 0
            let frame = 1.0 / 120
            let start = audio
            for i in 0..<480 {                                   // 4 seconds: two trips round the bar
                let now = start + Double(i) * frame
                while audio < now { render() }                   // the audio thread runs ahead of the screen
                let raw = e.playheadTick.pointee
                guard raw >= 0 else { continue }
                let shown = smooth.step(raw: raw, perSecond: perSecond, length: length, at: now)
                func step(_ a: Double, _ b: Double) -> Double { var d = b - a; if d < -length / 2 { d += length }; return d }
                if i > 30, let lastRaw, let lastShown {
                    let rawStep = abs(step(lastRaw, raw) - perSecond * frame)
                    // the engine's own jump (the queued pattern starting on its bar line): the line
                    // follows it at once, so that frame isn't a glide
                    if rawStep > perSecond * Double(block) / 48_000 * 2 + 1 {
                        jumps += 1
                    } else {
                        rawWorst = max(rawWorst, rawStep)
                        shownWorst = max(shownWorst, abs(step(lastShown, shown) - perSecond * frame))
                    }
                    var d = abs(raw - shown); d = min(d, length - d)
                    lag = max(lag, d)
                    if shown < lastShown { wrapped = true }
                }
                lastRaw = raw
                lastShown = shown
            }
            log("BreakBoss playhead glide (\(block)-frame blocks): engine clock jitters \(String(format: "%.2f", rawWorst)) ticks a frame, the line \(String(format: "%.2f", shownWorst)), \(jumps) jump(s)")
            check(shownWorst < perSecond * frame * 0.2, "playhead glide (\(block)-frame blocks): the line moves evenly every frame")
            check(lag < perSecond * Double(block) / 48_000 + 1, "playhead glide (\(block)-frame blocks): the line stays with the engine's clock")
            check(wrapped, "playhead glide (\(block)-frame blocks): the line wraps at the loop's end")
            check(jumps <= 1, "playhead glide (\(block)-frame blocks): the engine's clock only jumps when the pattern starts")
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
        for note in 36...47 {
            e.receiveMIDI(status: 0x90, data1: UInt8(note), data2: 100, time: 0)
            renderBlock(e)
            check(e.status[0] == 1 && e.status[1] == Double(note - 36), "MIDI note \(note) holds full loop \(note - 35)")
            e.receiveMIDI(status: 0x80, data1: UInt8(note), data2: 0, time: 0)
            renderBlock(e)
            check(e.status[0] == 0 && e.status[1] == -1, "releasing MIDI note \(note) stops its held loop")
        }
        e.receiveMIDI(status: 0x90, data1: 47, data2: 127, time: 0)
        renderBlock(e)
        check(e.status[1] == 11, "MIDI reaches loop 12")
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
        check(e.padHits[Pad.bass808.rawValue] > bassBefore, "MIDI note 48 plays the lowest chromatic 808 without overlapping pads")
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
        checkEmptyPadsSilent()
    }

    /// Tyrone, Oct 26: a pad or track that says EMPTY plays nothing, and cuts nothing that's playing.
    static func checkEmptyPadsSilent() {
        let rate = 48_000.0
        let e = KnockEngine()
        e.prepare(sampleRate: rate, maxFrames: 256)
        let quiet: [KParam] = [.playMode, .velocity, .boost, .clipper, .clipDrive, .gatedReverb, .textureDelay, .tighten]
        for p in quiet { e.setParam(p, 0) }
        var samples = kitBuffers(KitLibrary.modernTrap).samples
        let empty = [Pad.clap.rawValue, Pad.hat.rawValue, Pad.bass808.rawValue]
        for pad in empty { samples[pad] = SampleBuffer(left: [0], sampleRate: rate) }
        let kit = KitBuffers(name: "EMPTY TEST", samples: samples, settings: Array(repeating: PadSettings(), count: Pad.count),
                             bassHz: KitLibrary.modernTrap.bassHz, renderSampleRate: rate)
        check(empty.allSatisfy { kit.silent[$0] } && !kit.silent[Pad.kick.rawValue], "EMPTY pads are marked silent, sounding pads aren't")
        e.kitHandoff.publish(kit)
        var l = [Float](repeating: 0, count: 256), r = l
        func energy(blocks: Int) -> Double {
            var sum = 0.0
            for _ in 0..<blocks {
                for i in 0..<256 { l[i] = 0; r[i] = 0 }
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    e.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil) } }
                for i in 0..<256 { sum += Double(l[i] * l[i] + r[i] * r[i]) }
            }
            return sum
        }
        _ = energy(blocks: 2)
        let floor = energy(blocks: 40)           // whatever the chain makes with nothing playing
        e.send(KEvent(kind: .pad, a: Int32(Pad.clap.rawValue), value: 1))
        e.send(KEvent(kind: .bass, a: 0, value: 1))
        e.send(KEvent(kind: .padPitched, a: Int32(Pad.hat.rawValue + 128 * 64), value: 1))
        let hits = energy(blocks: 40)
        e.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 1))
        let kick = energy(blocks: 40)
        check(hits <= floor * 1.01 + 1e-12 && kick > floor + 1e-6,
              "an EMPTY pad, the EMPTY 808 and an EMPTY pitched hit play nothing (the kick still plays)")
        _ = energy(blocks: 300)                  // the kick rings out
        e.send(KEvent(kind: .pad, a: Int32(Pad.openHat.rawValue), value: 1))
        _ = energy(blocks: 2)
        e.send(KEvent(kind: .pad, a: Int32(Pad.hat.rawValue), value: 1))
        _ = energy(blocks: 2)                    // past a choke's 6 ms fade
        check(energy(blocks: 4) > floor + 1e-6, "an EMPTY closed hat doesn't choke the open hat")
    }

    static func checkPatternEditor() {
        let bar = PatternData.ppq * 4, cell = PatternData.stepTicks
        var p = PatternData(name: "T", lengthTicks: bar * 2, events: [])
        p = PatternEdit.toggle(p, pad: Pad.snare.rawValue, tick: cell * 4, cell: cell)
        check(p.events.count == 1 && p.events[0].tick == cell * 4 && Int(p.events[0].pad) == Pad.snare.rawValue,
              "editor: tap adds a hit on the step")
        p = PatternEdit.toggle(p, pad: Pad.snare.rawValue, tick: cell * 4, cell: cell)
        check(p.events.isEmpty, "editor: tapping the same step removes it")
        var swung = PatternData(name: "S", lengthTicks: bar, events: [GrooveEvent(tick: cell * 2 + 5, pad: Int8(Pad.hat.rawValue), velocity: 0.4)])
        swung = PatternEdit.toggle(swung, pad: Pad.hat.rawValue, tick: cell * 2, cell: cell)
        check(swung.events.isEmpty, "editor: removing a step also removes a swung hit inside it")
        let kept = PatternEdit.toggle(PatternData(name: "K", lengthTicks: bar, events: [GrooveEvent(tick: 0, pad: 0, velocity: 0.33)]),
                                      pad: Pad.hat.rawValue, tick: cell * 8, cell: cell)
        check(kept.events.contains { $0.tick == 0 && $0.velocity == 0.33 }, "editor: untouched hits keep their velocity")
        let bass = PatternEdit.longBass(PatternData(name: "B", lengthTicks: bar, events: []), from: cell * 2, cells: 6, cell: cell)
        check(bass.events.count == 1 && bass.events[0].length == cell * 6 && Int(bass.events[0].pad) == Pad.bass808.rawValue,
              "editor: dragging on the 808 row draws one long note")
        let edge = PatternEdit.longBass(PatternData(name: "E", lengthTicks: bar, events: []), from: bar - cell * 2, cells: 6, cell: cell)
        check(edge.events.first.map { $0.tick + $0.length <= bar } == true, "editor: long 808 stays inside the loop")
        var source = PatternData(name: "C", lengthTicks: bar * 2, events: [
            GrooveEvent(tick: 0, pad: 0, velocity: 1), GrooveEvent(tick: bar + cell * 4, pad: 1, velocity: 1)])
        source = PatternEdit.copyNext(source, fromBar: 0, bars: 2)
        check(source.bars == 4 && source.events.count == 4 && source.events.contains { $0.tick == bar * 2 } &&
              source.events.contains { $0.tick == bar * 3 + cell * 4 }, "editor: COPY NEXT copies bars 1-2 into 3-4")
        let longer = PatternEdit.setLength(PatternData(name: "L", lengthTicks: bar, events: [GrooveEvent(tick: cell, pad: 0, velocity: 1)]), bars: 4)
        check(longer.bars == 4 && longer.events.map { $0.tick } == [cell, bar + cell, bar * 2 + cell, bar * 3 + cell],
              "editor: longer length repeats the pattern")
        let shorter = PatternEdit.setLength(longer, bars: 1)
        check(shorter.bars == 1 && shorter.events.count == 1, "editor: shorter length drops hits past the end")
        let capped = PatternEdit.copyNext(PatternData(name: "M", lengthTicks: bar * 16, events: [GrooveEvent(tick: bar * 14, pad: 0, velocity: 1)]),
                                          fromBar: 14, bars: 2)
        check(capped.bars == 16 && capped.events.count == 1, "editor: COPY NEXT never goes past 16 bars")
        let sixteen = PatternEdit.setLength(PatternData(name: "X", lengthTicks: bar * 4, events: [GrooveEvent(tick: 0, pad: 0, velocity: 1)]), bars: 16)
        check(sixteen.bars == 16 && sixteen.events.count == 4, "drum roll: 16 bars repeats a 4-bar pattern four times")
        check(PatternEdit.setLength(sixteen, bars: 32).bars == 16, "drum roll: patterns stop at 16 bars")
        var saved16 = KnockState()
        saved16.editedLoops[0] = sixteen
        check(saved16.normalized().editedLoops[0]?.bars == 16, "a 16-bar pattern is saved and restored at full length")
        let mid16 = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-16.mid")
        if (try? MIDIFile.write(sixteen, tempo: 120, bounce: 0, bars: 16, to: mid16)) != nil {
            check(MIDIFile.read(mid16)?.bars == 16, "a 16-bar pattern exports and re-imports as MIDI at full length")
        }
        // Edits reach the engine as a valid loop.
        let set = PatternSet([source])
        check(set.loops[0].count == source.events.count && set.loops[0].lengthTicks == Int(source.lengthTicks),
              "editor: edited pattern loads into the engine unchanged")
    }

    static func checkMIDIPadMap() {
        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 0)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        renderBlock(e)
        func hits(_ note: UInt8) -> [UInt32] {
            let before = (0..<Pad.count).map { e.padHits[$0] }
            e.receiveMIDI(status: 0x90, data1: note, data2: 100, time: 0)
            renderBlock(e)
            e.receiveMIDI(status: 0x80, data1: note, data2: 0, time: 0)
            renderBlock(e)
            return (0..<Pad.count).map { e.padHits[$0] - before[$0] }
        }
        func onlyPad(_ d: [UInt32], _ pad: Int) -> Bool { d.enumerated().allSatisfy { $0.offset == pad ? $0.element > 0 : $0.element == 0 } }
        check(onlyPad(hits(36), 0) && onlyPad(hits(47), 11), "MIDI map: standard notes 36-47 by default")
        // MPC Classic, sent the way the controller sends it.
        e.send(KEvent(kind: .mapNote, a: -1))
        for (pad, note) in MIDIPadMap.mpcClassicNotes.enumerated() { e.send(KEvent(kind: .mapNote, a: Int32(note), value: Double(pad))) }
        renderBlock(e)
        for (pad, note) in MIDIPadMap.mpcClassicNotes.enumerated() {
            check(onlyPad(hits(UInt8(note)), pad), "MIDI map: MPC Classic note \(note) plays pad \(pad + 1)")
        }
        check(hits(39).allSatisfy { $0 == 0 } && hits(41).allSatisfy { $0 == 0 }, "MIDI map: notes not on an MPC pad play nothing")
        let bass808 = hits(60)
        check(bass808[Pad.bass808.rawValue] > 0 && bass808.enumerated().allSatisfy { $0.offset == Pad.bass808.rawValue || $0.element == 0 },
              "MIDI map: the chromatic 808 still plays on notes the map doesn't use")
        let learned = MIDIPadMap.learn(MIDIPadMap.standardNotes, pad: 2, note: 36)
        check(learned[2] == 36 && learned[0] == -1 && learned.count == Pad.count, "MIDI learn moves a note to the new pad only")
        check(MIDIPadMap.clean([200, -5]) == [-1, -1] + Array(repeating: -1, count: Pad.count - 2), "MIDI map cleans bad notes")
        var saved = KnockState()
        saved.midiMap = .mpcClassic
        let round = try? JSONDecoder().decode(KnockState.self, from: JSONEncoder().encode(saved))
        check(round?.midiMap == .mpcClassic, "MIDI map is saved with the session / AUv3 project")
        let old = try? JSONDecoder().decode(KnockState.self, from: JSONEncoder().encode(KnockState()))
        check(old != nil && old?.midiMap == nil, "sessions without a MIDI map still load (standard map)")
        check(e.lastNoteOn.pointee & 0x7F == 60 && e.lastNoteOn.pointee >> 8 > 0, "MIDI learn sees the last note played")
        checkMPKMiniPads()
        checkLowLatencyPaths()
        checkTiltShadows()
    }

    /// The touch-to-sound path (Tyrone, Oct 31): the event queue hands every hit over in order with
    /// its lock let go first, an overflow still clears to ALL OFF, and the screen's meter copy tells
    /// a new hit from none without making new arrays.
    /// Shadow tilt (Oct 31): nothing extra at the usual playing angle, so Face 1 matches its picture;
    /// tilting throws the shadows to the low side; leaning back only pulls them in a little.
    static func checkTiltShadows() {
        let rest = TiltShadowMath.lean(gravityX: 0, gravityY: TiltShadowMath.restingDown)
        check(TiltShadowMath.strength(rest) == 0, "shadow tilt: no extra shadow at the usual angle")
        let right = TiltShadowMath.lean(gravityX: 0.5, gravityY: TiltShadowMath.restingDown)
        check(right.dx > 0.6 && TiltShadowMath.strength(right) == 1, "shadow tilt: tip right, shadows go right at full depth")
        let upright = TiltShadowMath.lean(gravityX: 0, gravityY: 1)
        check(upright.dy > 0.99, "shadow tilt: screen upright throws the longest shadows down")
        let flat = TiltShadowMath.lean(gravityX: 0, gravityY: 0)
        check(flat.dy < 0 && flat.dy >= -0.3, "shadow tilt: lying flat only pulls them in a little")
        let (x, y) = TiltShadowMath.screen(0.2, -0.4, .landscapeRight)
        check(abs(x - 0.4) < 1e-9 && abs(y + 0.2) < 1e-9, "shadow tilt: landscape axes")
    }

    static func checkLowLatencyPaths() {
        let q = EventQueue(capacity: 8)
        for p in 0..<3 { q.push(KEvent(kind: .pad, a: Int32(p), value: 0.9)) }
        var seen: [Int32] = []
        q.drain { seen.append($0.a) }
        check(seen == [0, 1, 2], "event queue: hits come out in the order they went in")
        // pushing from inside the drain would have deadlocked before; now the lock is already free
        var again = 0
        q.push(KEvent(kind: .pad, a: 5))
        q.drain { _ in q.push(KEvent(kind: .pad, a: 6)) }
        q.drain { e in if e.a == 6 { again += 1 } }
        check(again == 1, "event queue: the lock is free while events are handled")
        for p in 0..<20 { q.push(KEvent(kind: .pad, a: Int32(p))) }
        var kinds: [KEvent.Kind] = []
        q.drain { kinds.append($0.kind) }
        check(kinds.count == 1 && kinds.first == .allOff, "event queue: an overflow still clears to ALL OFF")

        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 0)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        for _ in 0..<20 { renderBlock(e) }
        var m = MeterSnapshot()
        _ = e.meters.copy(into: &m)
        check(!e.meters.copy(into: &m), "meters: no pad hit, no pad light")
        for p in 0..<4 { e.send(KEvent(kind: .pad, a: Int32(p), value: 0.9)) }
        for _ in 0..<20 { renderBlock(e) }
        check(e.meters.copy(into: &m) && m.padHits.prefix(4).contains(where: { $0 > 0 }), "meters: a pad hit reaches the pad lights")
        check(m.scopePeak > 0.0003, "meters: the screen sees the hit sounding")
        check(m.status.count == SharedMeters.statusCount && m.padHits.count == Pad.count, "meters: the copy keeps its sizes")
    }

    /// An Akai MPK Mini (Plus) out of the box: pads send notes 36-43 (bank A) and 44-51 (bank B)
    /// on channel 10. With MIDI OUT on in the multi-out layout (pad 10 owns channel 10) they
    /// still play pads 1-12 in ONE-SHOT, and record into the pattern when RECORD is armed.
    static func checkMPKMiniPads() {
        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 0); e.setParam(.followDAW, 0); e.setParam(.tempoSync, 0); e.setTempo(120)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        for p in 0..<Pad.count { e.send(KEvent(kind: .midiOut, a: Int32(p), value: Double(KnockController.defaultMIDIOutChannels[p] * 128 + KnockController.defaultMIDIOutNotes[p]))) }
        e.send(KEvent(kind: .midiOut, a: -1, value: 1))
        renderBlock(e)
        func hits(_ note: UInt8, host: Bool) -> [UInt32] {
            let before = (0..<Pad.count).map { e.padHits[$0] }
            if host { e.hostMIDI(offset: 0, status: 0x99, data1: note, data2: 100) }
            else { e.receiveMIDI(status: 0x99, data1: note, data2: 100, time: 0) }
            renderBlock(e)
            if host { e.hostMIDI(offset: 0, status: 0x89, data1: note, data2: 0) }
            else { e.receiveMIDI(status: 0x89, data1: note, data2: 0, time: 0) }
            for _ in 0..<12 { renderBlock(e) }          // past MIDI OUT's 50 ms loop-back guard
            return (0..<Pad.count).map { e.padHits[$0] - before[$0] }
        }
        func onlyPad(_ d: [UInt32], _ pad: Int) -> Bool { d.enumerated().allSatisfy { $0.offset == pad ? $0.element > 0 : $0.element == 0 } }
        for pad in 0..<Pad.count {
            check(onlyPad(hits(UInt8(36 + pad), host: false), pad), "MPK Mini: pad note \(36 + pad) on channel 10 plays BB pad \(pad + 1)")
            check(onlyPad(hits(UInt8(36 + pad), host: true), pad), "MPK Mini via the AUv3 host: note \(36 + pad) plays BB pad \(pad + 1)")
        }
        // Bank B pads 5-8 (notes 48-51) are the 808 range: they play the 808 only, never pad 10 pitched.
        for note in 48...51 {
            check(onlyPad(hits(UInt8(note), host: true), Pad.bass808.rawValue), "MPK Mini via the AUv3 host: bank B note \(note) plays only the 808")
        }
        // A program that sends MPC notes (A01-A08, B01-B04), learned with LEARN ALL 12 pads in a row:
        // every controller pad plays exactly one pad, its own, with MIDI OUT on (pad 10 owns channel 10).
        let mpcNotes = [37, 36, 42, 82, 40, 38, 46, 44, 48, 47, 45, 43]
        var learnedAll = MIDIPadMap.standardNotes
        for (pad, note) in mpcNotes.enumerated() { learnedAll = MIDIPadMap.learn(learnedAll, pad: pad, note: note) }
        check(learnedAll == mpcNotes && Set(learnedAll).count == Pad.count, "LEARN ALL 12: each pad keeps its own note, none shared")
        e.send(KEvent(kind: .mapNote, a: -1))
        for (pad, note) in learnedAll.enumerated() { e.send(KEvent(kind: .mapNote, a: Int32(note), value: Double(pad))) }
        renderBlock(e)
        for (pad, note) in learnedAll.enumerated() {
            check(onlyPad(hits(UInt8(note), host: false), pad), "Learned controller: note \(note) on channel 10 plays only BB pad \(pad + 1)")
            check(onlyPad(hits(UInt8(note), host: true), pad), "Learned controller via the AUv3 host: note \(note) plays only BB pad \(pad + 1)")
        }
        e.send(KEvent(kind: .mapNote, a: -1))
        for (pad, note) in MIDIPadMap.standardNotes.enumerated() { e.send(KEvent(kind: .mapNote, a: Int32(note), value: Double(pad))) }
        // The one-channel MIDI OUT layout (every drum on channel 10, GM notes) still plays its own notes back.
        let gm = [36, 38, 39, 37, 42, 46, 35, 56, 54, 45, 50, 49]
        for p in 0..<Pad.count {
            let ch = p == Pad.bass808.rawValue ? p : 9
            e.send(KEvent(kind: .midiOut, a: Int32(p), value: Double(ch * 128 + gm[p])))
        }
        renderBlock(e)
        check(onlyPad(hits(38, host: true), Pad.snare.rawValue), "One-channel MIDI OUT layout: GM note 38 on channel 10 plays back the snare")
        // ONE TRACK (the plug-in's default): every pad on channel 1, notes 36-47, the 808 chromatic on 48-84.
        // A Logic track holding the whole kit plays each row's own pad back; the MPK on channel 10 still plays its pads.
        for p in 0..<Pad.count {
            e.send(KEvent(kind: .midiOut, a: Int32(p), value: Double(KnockController.oneTrackMIDIOutChannels[p] * 128 + KnockController.defaultMIDIOutNotes[p])))
        }
        renderBlock(e)
        func trackHits(_ note: UInt8) -> [UInt32] {
            let before = (0..<Pad.count).map { e.padHits[$0] }
            e.hostMIDI(offset: 0, status: 0x90, data1: note, data2: 100)
            renderBlock(e)
            e.hostMIDI(offset: 0, status: 0x80, data1: note, data2: 0)
            for _ in 0..<12 { renderBlock(e) }
            return (0..<Pad.count).map { e.padHits[$0] - before[$0] }
        }
        for pad in 0..<Pad.count {
            check(onlyPad(trackHits(UInt8(36 + pad)), pad), "ONE TRACK MIDI OUT: note \(36 + pad) on channel 1 plays back BB pad \(pad + 1)")
            check(onlyPad(hits(UInt8(36 + pad), host: true), pad), "ONE TRACK MIDI OUT: MPK note \(36 + pad) on channel 10 still plays BB pad \(pad + 1)")
        }
        check(onlyPad(trackHits(64), Pad.bass808.rawValue), "ONE TRACK MIDI OUT: note 64 on channel 1 plays the 808")
        for _ in 0..<40 { renderBlock(e) }            // earlier hits' note offs are gone
        let before808 = e.padHits[Pad.bass808.rawValue]
        e.hostMIDI(offset: 0, status: 0x90, data1: UInt8(36 + Pad.bass808.rawValue), data2: 100)
        renderBlock(e)
        check(e.padHits[Pad.bass808.rawValue] > before808 && e.midiOutCount == 0,
              "ONE TRACK MIDI OUT: the 808's pad note (42) plays the 808 and doesn't go back out (\(e.midiOutCount))")
        e.hostMIDI(offset: 0, status: 0x80, data1: UInt8(36 + Pad.bass808.rawValue), data2: 0)
        for _ in 0..<12 { renderBlock(e) }
        for p in 0..<Pad.count { e.send(KEvent(kind: .midiOut, a: Int32(p), value: Double(KnockController.defaultMIDIOutChannels[p] * 128 + KnockController.defaultMIDIOutNotes[p]))) }
        renderBlock(e)
        // Recorded into the sequencer like an on-screen tap.
        var loops = Array(repeating: PatternData(name: "E", lengthTicks: Int32(PatternData.ppq) * 4, events: []), count: Pad.count)
        loops[0] = PatternData(name: "R", lengthTicks: Int32(PatternData.ppq) * 4, events: [])
        e.patternHandoff.publish(PatternSet(loops))
        renderBlock(e)
        e.send(KEvent(kind: .recordArm, a: 1))
        e.send(KEvent(kind: .loopPad, a: 0))
        for _ in 0..<10 { renderBlock(e) }
        _ = e.collectRecorded()
        e.receiveMIDI(status: 0x99, data1: 37, data2: 100, time: 0)
        renderBlock(e)
        let rec = e.collectRecorded()
        check(rec.count == 1 && Int(rec[0].pad) == Pad.snare.rawValue && rec[0].semis == 0, "MPK Mini: a pad hit records into the pattern while RECORD is on")
        e.send(KEvent(kind: .recordArm, a: 0))
        e.send(KEvent(kind: .stop))
        renderBlock(e)
    }
}
