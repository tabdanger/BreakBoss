// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import AVFoundation
import UIKit

// MARK: - Self-test: Grooves, small buffers, voice stealing, host MIDI, sampler playhead and scope

extension KnockSelfTest {
    static func checkGrooves() {
        for style in GrooveStyle.allCases {
            for seed: UInt32 in [1, 2, 77, 12345] {
                let loops = GrooveGenerator.loops(style: style, seed: seed)
                check(loops.count == Pad.count, "\(style) seed \(seed): 12 loops")
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

        // Finger drumming (Oct 26): a pad tap sounds at the top of the very next 128-frame buffer (no
        // extra block of delay in any mode), and four fingers landing together all sound in that buffer.
        let step = SampleBuffer(left: Array(repeating: Float(0.02), count: 12_000), sampleRate: rate)
        let fingerKit = KitBuffers(name: "FINGER DRUMMING", samples: Array(repeating: step, count: Pad.count),
                                   settings: settings, bassHz: 110)
        for mode in SoundMode.allCases {
            func firstBuffer(_ pads: [Pad]) -> [Float] {
                let engine = makeEngine(fingerKit, mode: mode)
                var left = [Float](repeating: 0, count: 128), right = left
                engine.render(frames: 128, left: &left, right: &right, host: nil)   // idle buffer before the tap
                for pad in pads { engine.send(KEvent(kind: .pad, a: Int32(pad.rawValue), value: 0.8)) }
                engine.render(frames: 128, left: &left, right: &right, host: nil)
                return left
            }
            let one = firstBuffer([.kick])
            let onset = one.firstIndex { abs($0) > 0.000_01 } ?? 128
            check(onset < 128, "\(mode): pad tap sounds inside the very next buffer (frame \(onset))")
            let four = firstBuffer([.kick, .snare, .hat, .clap])
            let e1 = one.reduce(0) { $0 + $1 * $1 }, e4 = four.reduce(0) { $0 + $1 * $1 }
            check(e4 > e1 * 1.5, "\(mode): four fingers at once all sound in the same buffer (\(e1) vs \(e4))")
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
        for note: UInt8 in [36, 47, 48, 52, 60, 84] {
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

        let actualBass = engine(loop: true), expectedBass = engine(loop: true)
        for e in [actualBass, expectedBass] {
            e.hostMIDI(offset: 0, status: 0x90, data1: 60, data2: 127)
            _ = block(e, 128)
        }
        actualBass.hostMIDI(offset: 77, status: 0x80, data1: 60, data2: 0)
        let actualRelease = block(actualBass, 128)
        var expectedRelease = block(expectedBass, 77)
        expectedBass.hostMIDI(offset: 0, status: 0x80, data1: 60, data2: 0)
        expectedRelease += block(expectedBass, 51)
        check(maxDifference(actualRelease, expectedRelease) < 0.000_001, "host Loop-mode bass release begins at its sample offset")

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

    /// The SAMPLER window: the SAMPLE page's computed sound and the ENVELOPE page while it plays.
    /// The SAMPLER's live waveform (Tyrone, Oct 18): the cursor follows the track's newest voice
    /// from the engine (start, speed, pitch, reverse, START OFFSET, loop, STOP), and the waveform's
    /// kept peaks match the sound.
    static func checkSamplerPlayhead() {
        let rate = 48_000.0
        let sound = SampleBuffer(left: (0..<48_000).map { sinf(Float($0) * 0.05) * (1 - Float($0) / 48_000) }, sampleRate: rate)
        func run(_ settings: PadSettings, hits: Int = 1, blocks: Int = 10, stop: Bool = false) -> (SharedPlayheads.Row, [UInt32]) {
            var all = Array(repeating: PadSettings(), count: Pad.count)
            all[0] = settings
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.tighten, 0)]
            for (p, v) in quiet { e.setParam(p, v) }
            e.kitHandoff.publish(KitBuffers(name: "PLAYHEAD", samples: Array(repeating: sound, count: Pad.count), settings: all, bassHz: 110))
            var left = [Float](repeating: 0, count: 128), right = left
            func render() {
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
            }
            render()
            var ids: [UInt32] = []
            for _ in 0..<hits {
                e.send(KEvent(kind: .pad, a: 0, value: 1))
                for _ in 0..<blocks { render() }
                ids.append(e.playheads.row(0).id)
            }
            if stop {
                e.send(KEvent(kind: .stop))
                for _ in 0..<40 { render() }
            }
            return (e.playheads.row(0), ids)
        }
        let after = 10.0 * 128 / 48_000   // the part of the sound 10 blocks play at speed 1
        let (plain, _) = run(PadSettings())
        check(plain.id != 0 && plain.start == 0 && abs(plain.position - after) < 0.004 && abs(plain.speed - 1) < 0.01,
              "Sampler cursor: a hit starts at the sound's start and moves at its speed (\(plain.position), \(plain.speed)/s)")
        check(plain.block > 0 && plain.time > 0, "Sampler cursor: the engine stamps when it wrote the position")
        var up = PadSettings(); up.tune = 12
        let (octave, _) = run(up)
        check(abs(octave.speed - 2) < 0.02 && abs(octave.position - 2 * after) < 0.006,
              "Sampler cursor: an octave up moves twice as fast (\(octave.speed)/s)")
        var back = PadSettings(); back.reverse = true
        let (reversed, _) = run(back)
        check(reversed.start > 0.99 && reversed.speed < 0 && abs((reversed.start - reversed.position) - after) < 0.004,
              "Sampler cursor: reverse starts at the end and moves backwards (\(reversed.position))")
        var offset = PadSettings(); offset.sampler = SamplerSettings(); offset.sampler?.startOffset = 0.5
        let (late, _) = run(offset)
        check(abs(late.start - 0.5) < 0.002 && late.position > late.start, "Sampler cursor: START OFFSET moves where it starts (\(late.start))")
        var looped = PadSettings(); looped.sampler = SamplerSettings(); looped.sampler?.useLoop = true
        let (loop, _) = run(looped)
        check(loop.loopEnd > loop.loopStart && loop.loopStart >= 0, "Sampler cursor: a looping voice reports its loop (\(loop.loopStart)…\(loop.loopEnd))")
        check(plain.loopEnd < 0, "Sampler cursor: a one-shot reports no loop")
        let (again, ids) = run(PadSettings(), hits: 2, blocks: 5)
        check(ids.count == 2 && ids[1] != ids[0] && again.id == ids[1] && again.position < after,
              "Sampler cursor: overlapping hits follow the newest one, from its start (\(again.position))")
        let (stopped, _) = run(PadSettings(), stop: true)
        check(stopped.id == 0, "Sampler cursor: STOP ends the voice so the cursor resets")
        // the waveform's kept peaks: the same lows and highs as reading every frame
        let peaks = SamplerPeaks(sound)
        var worst: Float = 0
        for (a, b) in [(0, 10), (100, 5_000), (7_000, 48_000), (31, 33), (40_000, 41_500)] {
            var lo: Float = 0, hi: Float = 0
            for i in a..<b { let v = (sound.left[i] + sound.right[i]) * 0.5; lo = min(lo, v); hi = max(hi, v) }
            let (plo, phi) = peaks.range(sound, a, b)
            // the kept blocks may reach a block past either edge: never less than the frames hold
            worst = max(worst, max(0, plo - lo), max(0, hi - phi))
        }
        check(worst < 0.000_1, "Sampler waveform: the kept peaks cover the sound's own lows and highs")
        let cols = peaks.columns(sound, count: 1_330, zoom: 1, scroll: 0)
        check(cols.count == 1_330 && cols[0].1 > cols[1_300].1, "Sampler waveform: one column per pixel, louder at the start of a decaying hit")
    }

    /// The faceplate scope: the engine publishes the master waveform every block, it moves while a
    /// pad plays, goes flat when nothing does, and its bass / top measure tells an 808 from a hat.
    static func checkScope() {
        let rate = 48_000.0
        let n = 24_000
        let subWave: [Float] = (0..<n).map { i -> Float in
            let t = Float(i)
            let fade: Float = 1 - t / Float(n)
            return sinf(t * 2 * Float.pi * 50 / 48_000) * 0.8 * fade
        }
        let sub = SampleBuffer(left: subWave, sampleRate: rate)
        var seed: UInt32 = 12_345
        let fizz = SampleBuffer(left: (0..<n).map { i -> Float in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Float(seed >> 8) / Float(1 << 24) * 2 - 1
            return white * 0.5 * exp(-Float(i) / 6_000)
        }, sampleRate: rate)
        var samples = Array(repeating: sub, count: Pad.count)
        samples[Pad.hat.rawValue] = fizz
        let e = KnockEngine()
        e.prepare(sampleRate: rate, maxFrames: 128)
        let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.tighten, 0)]
        for (p, v) in quiet { e.setParam(p, v) }
        e.kitHandoff.publish(KitBuffers(name: "SCOPE", samples: samples, settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110))
        var left = [Float](repeating: 0, count: 128), right = left
        func render(_ blocks: Int) {
            for _ in 0..<blocks {
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
            }
        }
        var rings = ScopeRings()
        // The last ~45 ms on screen: loudest point, and the bass and top shares.
        func look() -> (loud: Float, bass: Float, top: Float, write: Int) {
            e.meters.copyScope(into: &rings)
            var loud: Float = 0, bass: Float = 0, top: Float = 0
            for k in 1...ScopeTracer.window {
                let i = (rings.write - k + MasterBus.scopeSize * 2) & (MasterBus.scopeSize - 1)
                loud = max(loud, abs(rings.low[i]), abs(rings.high[i]))
                bass += rings.bass[i]; top += rings.top[i]
            }
            let total = max(0.000_1, bass + top)
            return (loud, bass / total, top / total, rings.write)
        }
        render(4)
        e.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 1))
        render(20)
        let low = look()
        render(1)
        let moved = look().write
        check(low.loud > 0.05, "Scope: a pad playing puts its waveform on the screen (\(low.loud))")
        check(moved != low.write, "Scope: the waveform reaches the screen every audio block, not in 30 Hz steps")
        check(low.bass > 0.7, "Scope: a 50 Hz sub reads as bass (\(low.bass) bass, \(low.top) top)")
        render(Int(rate * 6 / 128))
        let idle = look()
        check(idle.loud == 0, "Scope: the screen goes flat when nothing plays (\(idle.loud))")
        e.send(KEvent(kind: .pad, a: Int32(Pad.hat.rawValue), value: 1))
        render(20)
        let high = look()
        check(high.loud > 0.05 && high.top > 0.6, "Scope: a hat's fizz reads as top end (\(high.top) top, \(high.bass) bass)")
        // the fizz fills a band around the line, the sub stays a thin line
        e.meters.copyScope(into: &rings)
        var band: Float = 0
        for k in 1...ScopeTracer.window {
            let i = (rings.write - k + MasterBus.scopeSize * 2) & (MasterBus.scopeSize - 1)
            band = max(band, rings.high[i] - rings.low[i])
        }
        check(band > 0.1, "Scope: a hat's fizz fills a band on the screen (\(band))")
        // Every face's trace runs between its own two colours.
        for face in ["modern", "texture", "vintage", "platinum"] {
            let light = FaceLight.of(face)
            check(light.coreRGB.max() <= 1 && light.glowRGB.min() >= 0, "Scope: \(face) light blends inside its own colours")
        }
    }
}
