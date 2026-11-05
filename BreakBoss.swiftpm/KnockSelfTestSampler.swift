// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import AVFoundation
import UIKit

// MARK: - Self-test: The channel sampler, precomputed effects, note repeat, one-shots, envelopes and velocity layers

extension KnockSelfTest {
    static func checkSampler() {
        let rate = 48_000.0
        let ramp = SampleBuffer(left: (0..<9_600).map { Float($0) / 9_600 * 0.5 }, sampleRate: rate)
        func process(_ change: (inout SamplerSettings) -> Void) -> SampleBuffer {
            var s = SamplerSettings(); change(&s)
            return SamplerProcessor.process(ramp, s.offline(bpm: 120) ?? SamplerOffline(), engineRate: rate)
        }
        check(SamplerSettings().offline(bpm: 120) == nil, "Sampler: an untouched sampler leaves the sound as it is")
        let reversed = process { $0.reverse = true; $0.declick = .off }
        check(abs(reversed.left[0] - ramp.left[ramp.length - 1]) < 0.000_1, "Sampler: Reverse plays the sound backwards")
        let trimmed = process { $0.start = 0.25; $0.length = 0.5; $0.declick = .off }
        check(abs(trimmed.length - 3_600) <= 2, "Sampler: SMP START and LENGTH cut the sound (\(trimmed.length) samples)")
        let normalized = process { $0.normalize = true }
        var peak: Float = 0
        for i in 0..<normalized.length { peak = max(peak, abs(normalized.left[i])) }
        check(abs(peak - 0.98) < 0.01, "Sampler: Normalize brings the peak to just under full scale")
        let polarity = process { $0.reversePolarity = true; $0.declick = .off }
        check(polarity.left[5_000] < 0 && abs(polarity.left[5_000] + ramp.left[5_000]) < 0.000_1, "Sampler: Reverse polarity flips the wave")
        let cut = process { $0.length = 0.5; $0.declick = .generic }
        check(cut.length > 4_800 && cut.fadeMarks.1 > 0 && abs(cut.left[cut.length - 1]) < 0.01,
              "Sampler: a bleeding declick fades out past the cut (\(cut.length) samples)")
        let tone = SampleBuffer(left: (0..<48_000).map { sinf(Float($0) * 2 * .pi * 220 / 48_000) * 0.5 }, sampleRate: rate)
        var stretch = SamplerSettings(); stretch.stretch = .stretch; stretch.multiplier = 1
        let longer = SamplerProcessor.process(tone, stretch.offline(bpm: 120)!, engineRate: rate)
        check(abs(Double(longer.length) / 48_000 - 4) < 0.05, "Sampler: MUL ×4 with Stretch makes it four times longer (\(longer.length))")
        var locked = SamplerSettings(); locked.stretch = .stretch; locked.time = .projectTempo(120)
        let slower = SamplerProcessor.process(tone, locked.offline(bpm: 60)!, engineRate: rate)
        check(abs(Double(slower.length) / 48_000 - 2) < 0.05, "Sampler: TIME locked to the tempo stretches when the tempo halves")
        var pitched = SamplerSettings(); pitched.stretch = .stretch; pitched.stretchPitch = 12
        let up = SamplerProcessor.process(tone, pitched.offline(bpm: 120)!, engineRate: rate)
        var crossings = 0
        for i in 1..<min(up.length, 24_000) where (up.left[i - 1] < 0) != (up.left[i] < 0) { crossings += 1 }
        check(abs(up.length - 48_000) < 600 && crossings > 380 && crossings < 500,
              "Sampler: PITCH +12 with Stretch keeps the length and doubles the pitch (\(crossings) crossings)")
        var saved = PadSettings(); saved.sampler = stretch
        let decoded = (try? JSONEncoder().encode(saved)).flatMap { try? JSONDecoder().decode(PadSettings.self, from: $0) }
        check(decoded?.sampler == stretch, "Sampler: its settings are saved with the track")

        // playing: the Volume envelope, the filter, a loop and the one-shot rule
        let long = SampleBuffer(left: (0..<48_000).map { $0 % 2 == 0 ? 0.2 : -0.2 }, sampleRate: rate)
        func energy(_ settings: PadSettings, _ sample: SampleBuffer = long, blocks: ClosedRange<Int>) -> Float {
            var all = Array(repeating: PadSettings(), count: Pad.count)
            all[0] = settings
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                            (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0)]
            for (p, v) in quiet { e.setParam(p, v) }
            e.kitHandoff.publish(KitBuffers(name: "SAMPLER", samples: Array(repeating: sample, count: Pad.count), settings: all, bassHz: 110))
            e.send(KEvent(kind: .pad, a: 0, value: 1))
            var total: Float = 0
            for b in 0...blocks.upperBound {
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                if blocks.contains(b) { total += left.reduce(0) { $0 + $1 * $1 } }
            }
            return total
        }
        let plain = PadSettings()
        var shaped = PadSettings(); shaped.sampler = SamplerSettings()
        shaped.sampler?.setEnvelope(.volume) { $0.on = true; $0.attack = 0; $0.hold = 0; $0.decay = 0.15; $0.sustain = 0 }
        let tail = 100...140
        check(energy(plain, blocks: tail) > 1 && energy(shaped, blocks: tail) < energy(plain, blocks: tail) * 0.01,
              "Sampler: the Volume envelope shapes the hit")
        var filtered = PadSettings(); filtered.sampler = SamplerSettings(); filtered.sampler?.cutoff = 0.2; filtered.sampler?.filterType = .lp
        check(energy(filtered, blocks: 5...20) < energy(plain, blocks: 5...20) * 0.05, "Sampler: the filter (MOD X) takes the top off")
        let short = SampleBuffer(left: (0..<3_000).map { $0 % 2 == 0 ? 0.2 : -0.2 }, sampleRate: rate)
        var looped = PadSettings(); looped.sampler = SamplerSettings(); looped.sampler?.useLoop = true
        check(energy(looped, short, blocks: 60...80) > 1 && energy(plain, short, blocks: 60...80) < energy(looped, short, blocks: 60...80) * 0.01,
              "Sampler: Use loop points keeps a short sound going")
        var offset = PadSettings(); offset.sampler = SamplerSettings(); offset.sampler?.startOffset = 0.9
        check(energy(plain, blocks: 50...60) > 1 && energy(offset, blocks: 50...60) < energy(plain, blocks: 50...60) * 0.01,
              "Sampler: START OFFSET starts the sound later in")

        // Tyrone, Oct 18 (build 82): every ENVELOPE-page control changes the sound
        func stereo(_ settings: PadSettings, _ sample: SampleBuffer = long, blocks: ClosedRange<Int>) -> (Float, Float) {
            var all = Array(repeating: PadSettings(), count: Pad.count)
            all[0] = settings
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                            (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0)]
            for (p, v) in quiet { e.setParam(p, v) }
            e.kitHandoff.publish(KitBuffers(name: "SAMPLER", samples: Array(repeating: sample, count: Pad.count), settings: all, bassHz: 110))
            e.send(KEvent(kind: .pad, a: 0, value: 1))
            var l2: Float = 0, r2: Float = 0
            for b in 0...blocks.upperBound {
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                if blocks.contains(b) { l2 += left.reduce(0) { $0 + $1 * $1 }; r2 += right.reduce(0) { $0 + $1 * $1 } }
            }
            return (l2, r2)
        }
        let low = SampleBuffer(left: (0..<48_000).map { sinf(Float($0) * 2 * .pi * 110 / 48_000) * 0.3 }, sampleRate: rate)
        for type in SamplerFilterType.allCases {
            var f = PadSettings(); f.sampler = SamplerSettings(); f.sampler?.filterType = type
            f.sampler?.cutoff = type == .hp ? 0.75 : (type == .bs ? 0.2468 : 0.2); f.sampler?.resonance = type == .fastLP ? 0.4 : 0
            let sample = type == .hp || type == .bs ? low : long
            let changed = energy(f, sample, blocks: 5...20), was = energy(plain, sample, blocks: 5...20)
            check(changed < was * 0.3, "Sampler: the \(type.title) filter changes the sound (\(changed) vs \(was))")
        }
        let box = SamplerEnvelopePreset.boxMethod
        var boxed = PadSettings(); boxed.sampler = SamplerSettings(); boxed.sampler?.envelopes = box.envelopes
        check(energy(boxed, blocks: 2...8) > energy(plain, blocks: 2...8) * 0.9 && energy(boxed, blocks: tail) < energy(plain, blocks: tail) * 0.001,
              "Sampler: the box method plays at full level and stops when the note ends")
        var swept = PadSettings(); swept.sampler = SamplerSettings()
        swept.sampler?.setEnvelope(.modX) { $0.on = true; $0.attack = 0; $0.hold = 0; $0.decay = 0.2; $0.sustain = 0; $0.amount = 1 }
        check(energy(swept, blocks: tail) < energy(plain, blocks: tail) * 0.1, "Sampler: a Mod X envelope closes the open filter")
        var wobble = PadSettings(); wobble.sampler = SamplerSettings()
        wobble.sampler?.setLFO(.pan) { $0.shape = 2; $0.amount = 1 }
        let (wl, wr) = stereo(wobble, blocks: 5...60)
        check(wr > wl * 4, "Sampler: a square LFO on the panning moves the sound (L \(wl), R \(wr))")
        var tremolo = PadSettings(); tremolo.sampler = SamplerSettings()
        tremolo.sampler?.setLFO(.volume) { $0.shape = 2; $0.amount = -1 }
        check(abs(energy(tremolo, blocks: 5...300) - energy(plain, blocks: 5...300)) > energy(plain, blocks: 5...300) * 0.2,
              "Sampler: an LFO on the volume changes the level")
        var dip = PadSettings(); dip.sampler = SamplerSettings()
        dip.sampler?.setLFO(.volume) { $0.shape = 2; $0.amount = -1; $0.speed = 0.2 }
        var crest = PadSettings(); crest.sampler = SamplerSettings()
        crest.sampler?.setLFO(.volume) { $0.shape = 2; $0.amount = 1; $0.speed = 0.2 }
        check(energy(dip, blocks: 2...8) < energy(plain, blocks: 2...8) * 0.1 && energy(crest, blocks: 2...8) > energy(plain, blocks: 2...8) * 0.9,
              "Sampler: AMT turned left inverts the volume LFO (a square starts in its dip)")
        var bent = PadSettings(); bent.sampler = SamplerSettings()
        bent.sampler?.setEnvelope(.pan) { $0.on = true; $0.attack = 0; $0.hold = 0.4; $0.amount = -1 }
        let (bl, br) = stereo(bent, blocks: 5...30)
        check(bl > br * 4, "Sampler: the Panning envelope turned left moves the sound left (L \(bl), R \(br))")
        check(abs(SamplerEnvelope.units(SamplerEnvelope.knob(beats: 1), tempo: true) - 1) < 0.001
              && abs(SamplerEnvelope.units(SamplerEnvelope.knob(beats: 2, scale: 0.5), tempo: true) * 0.5 - 2) < 0.001,
              "Sampler: a knob's Set menu puts it on a tempo length")
        var loud = PadSettings(); loud.sampler = SamplerSettings(); loud.sampler?.volume = 1
        var soft = PadSettings(); soft.sampler = SamplerSettings(); soft.sampler?.volume = 0.25
        let unity = energy(plain, blocks: 5...20)
        let boost = energy(loud, blocks: 5...20) / unity, down = energy(soft, blocks: 5...20) / unity
        check(boost > 6 && down > 0.15 && down < 0.35,
              "Sampler: VOL goes from −12 dB to +12 dB, 100% in the middle (×\(boost), ×\(down))")
        check(abs(20 * log10f(SamplerSettings.preGain(0)) + 12) < 0.1 && abs(20 * log10f(SamplerSettings.preGain(1)) - 12) < 0.1
              && SamplerSettings.preGain(0.5) == 1 && SamplerSettings.volumeText(0.5).hasPrefix("100%"),
              "Sampler: the VOL knobs run evenly from −12 dB to +12 dB (Tyrone, Oct 19)")
        let dragged = SamplerWindow.dragged(SamplerEnvelope.shaped, handle: 4, dx: 0, dy: -0.3)
        check(dragged.on && abs(dragged.sustain - 0.2) < 0.001, "Sampler: dragging the sustain point down lowers the sustain")
        let bulged = SamplerWindow.dragged(SamplerEnvelope.shaped, handle: 6, dx: 0, dy: 0.25)
        check(bulged.attackTension < -0.4, "Sampler: dragging the attack curve up bends it")

        // free envelope points (FL style): add, move, delete, sustain point; the voice follows them
        var pts = SamplerEnvelope(); pts.on = true
        pts.points = [SamplerEnvPoint(time: 0.005, level: 1), SamplerEnvPoint(time: 0.02, level: 0.5), SamplerEnvPoint(time: 0.05, level: 0)]
        pts.sustainPoint = 1
        var run = SamplerEnvRun(pts, points: SamplerEnvPoints(pts), sampleRate: 48_000, samplesPerBeat: 24_000)
        for _ in 0..<300 { _ = run.advance(16) }               // 0.1 s: waiting on the sustain point
        let held = run.value
        run.release()
        for _ in 0..<200 { _ = run.advance(16) }               // 0.067 s: past the last point
        check(abs(held - 0.5) < 0.001 && run.done, "Sampler: envelope points wait on the sustain point and end after the last one (\(held), done \(run.done))")
        var through = pts; through.sustainPoint = -1
        var run2 = SamplerEnvRun(through, points: SamplerEnvPoints(through), sampleRate: 48_000, samplesPerBeat: 24_000)
        for _ in 0..<300 { _ = run2.advance(16) }
        check(run2.done, "Sampler: with no sustain point the envelope runs straight through")
        let added = SamplerWindow.addingPoint(time: 0.3, level: 0.8, to: SamplerEnvelope.shaped)
        let knobShape = SamplerEnvelope.shaped.knobPoints()
        check(added.points.count == knobShape.points.count + 1 && added.points.contains { abs($0.level - 0.8) < 0.001 }
              && abs(added.points.reduce(0) { $0 + $1.time } - knobShape.points.reduce(0) { $0 + $1.time }) < 0.0001,
              "Sampler: tapping the graph adds a point and the others stay where they were")
        let removed = SamplerWindow.removingPoint(added.points.firstIndex { abs($0.level - 0.8) < 0.001 } ?? 0, from: added)
        check(removed.points.count == knobShape.points.count && removed.sustainPoint == knobShape.sustain
              && zip(removed.points, knobShape.points).allSatisfy { abs($0.time - $1.time) < 0.0001 && $0.level == $1.level },
              "Sampler: double tapping a point deletes it")
        let moved = SamplerWindow.draggedPoint(pts, handle: 1, dt: 0.1, dy: -0.25)
        check(abs(moved.points[1].time - 0.12) < 0.0001 && abs(moved.points[1].level - 0.25) < 0.0001, "Sampler: dragging a point moves its time and level")
        var pointed = PadSettings(); pointed.sampler = SamplerSettings()
        pointed.sampler?.setEnvelope(.volume) { $0 = through }
        let cutLate = energy(pointed, blocks: 40...100), plainLate = energy(plain, blocks: 40...100)
        check(cutLate < plainLate * 0.01, "Sampler: a voice follows the graph's points (late energy \(cutLate) vs \(plainLate))")
        if let old = try? JSONDecoder().decode(SamplerEnvelope.self, from: Data(#"{"on":true,"attack":0.3,"sustain":0.7}"#.utf8)) {
            check(old.on && old.attack == 0.3 && old.points.isEmpty && old.sustainPoint == -1 && old.release == SamplerEnvelope().release,
                  "Sampler: envelopes saved before points still load")
        } else { check(false, "Sampler: envelopes saved before points still load") }

        // Tyrone, Oct 18: the MISC page (third tab): every control changes what plays
        /// Plays `hits` (block, pad, semitones) on a fresh engine; returns each block's left / right
        /// energy and zero crossings, and how many hits each pad made.
        func play(_ all: [PadSettings], _ sample: SampleBuffer = long, hits: [(Int, Int, Int)], blocks: Int)
            -> (l: [Float], r: [Float], zc: [Int], hits: [UInt32]) {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                            (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0)]
            for (p, v) in quiet { e.setParam(p, v) }
            var settings = all
            while settings.count < Pad.count { settings.append(PadSettings()) }
            e.kitHandoff.publish(KitBuffers(name: "MISC", samples: Array(repeating: sample, count: Pad.count), settings: settings, bassHz: 110))
            var ls: [Float] = [], rs: [Float] = [], zs: [Int] = []
            var last: Float = 0
            for b in 0..<blocks {
                for h in hits where h.0 == b { e.send(KEvent(kind: .padPitched, a: Int32(h.1 + 128 * (h.2 + 64)), value: 1)) }
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                ls.append(left.reduce(0) { $0 + $1 * $1 }); rs.append(right.reduce(0) { $0 + $1 * $1 })
                var z = 0
                for x in left { if (x < 0) != (last < 0) && abs(x) > 0.000_1 { z += 1 }; if abs(x) > 0.000_1 { last = x } }
                zs.append(z)
            }
            return (ls, rs, zs, (0..<Pad.count).map { e.padHits[$0] })
        }
        func misc(_ change: (inout SamplerSettings) -> Void) -> PadSettings {
            var p = PadSettings(); var sm = SamplerSettings(); change(&sm); p.sampler = sm; return p
        }
        func sum(_ v: [Float], _ r: ClosedRange<Int>) -> Float { r.reduce(0) { $0 + v[$1] } }
        func sumZ(_ v: [Int], _ r: ClosedRange<Int>) -> Int { r.reduce(0) { $0 + v[$1] } }
        let one = [(0, 0, 0)]
        // Arpeggiator: a tap becomes a run of notes, TIME apart (a beat's worth at 140 BPM)
        let arp16 = play([misc { $0.arpMode = 1; $0.arpTime = 0.35; $0.arpChord = 1 }], hits: one, blocks: 200).hits[0]
        let arp8 = play([misc { $0.arpMode = 1; $0.arpTime = 0.55; $0.arpChord = 1 }], hits: one, blocks: 200).hits[0]
        let arpOff = play([misc { _ in }], hits: one, blocks: 200).hits[0]
        check(arpOff == 1 && arp16 == 4 && arp8 == 2, "Sampler MISC: the arpeggiator plays 1/16s and 1/8s (\(arp16), \(arp8), off \(arpOff))")
        for mode in 2...5 {
            check(play([misc { $0.arpMode = mode; $0.arpTime = 0.35; $0.arpChord = 3; $0.arpRange = 2; $0.arpRepeat = 2 }], hits: one, blocks: 200).hits[0] == 4,
                  "Sampler MISC: arpeggiator mode \(mode) with a chord, Range and Repeat plays its run")
        }
        let tone1k = SampleBuffer(left: (0..<48_000).map { sinf(Float($0) * 2 * .pi * 1_000 / 48_000) * 0.3 }, sampleRate: rate)
        let upRun = play([misc { $0.arpMode = 1; $0.arpTime = 0.35; $0.arpChord = 11 }], tone1k, hits: one, blocks: 60)
        let downRun = play([misc { $0.arpMode = 2; $0.arpTime = 0.35; $0.arpChord = 11 }], tone1k, hits: one, blocks: 60)
        check(sumZ(upRun.zc, 2...30) * 3 < sumZ(downRun.zc, 2...30) * 2,
              "Sampler MISC: Up starts on the low note, Down on the high one (\(sumZ(upRun.zc, 2...30)) vs \(sumZ(downRun.zc, 2...30)) crossings)")
        // Chord "Auto (sustain)", latched: a chord held on the track is arpeggiated as one run, low to high,
        // and keeps running after it is let go until the transport stops
        let chordHits = [(0, 0, 0), (0, 0, 4), (0, 0, 7)]
        let autoChord = play([misc { $0.arpMode = 1; $0.arpTime = 0.35 }], tone1k, hits: chordHits, blocks: 200)
        let autoSingle = play([misc { $0.arpMode = 1; $0.arpTime = 0.35 }], tone1k, hits: one, blocks: 450)
        check(autoChord.hits[0] >= 4 && autoChord.hits[0] <= 6, "Sampler MISC: Auto (sustain) runs one arpeggio over a held chord (\(autoChord.hits[0]) notes, not 12+)")
        check(autoSingle.hits[0] >= 9 && sum(autoSingle.l, 400...449) > 0.001,
              "Sampler MISC: Auto latch keeps the arpeggio running after the note is let go (\(autoSingle.hits[0]) notes)")
        // a short blip, so the notes don't overlap: crossings per sounding block give each note's pitch
        // (the latched low note left on the run would pull it down to about 1.3x)
        let blip1k = SampleBuffer(left: (0..<2_000).map { sinf(Float($0) * 2 * .pi * 1_000 / 48_000) * 0.3 }, sampleRate: rate)
        func pitchRate(_ z: [Int], _ r: ClosedRange<Int>) -> Double {
            let on = r.filter { z[$0] > 0 }.count
            return on == 0 ? 0 : Double(sumZ(z, r)) / Double(on)
        }
        let lowRun = play([misc { $0.arpMode = 1; $0.arpTime = 0.35 }], blip1k, hits: one, blocks: 450)
        let relatched = play([misc { $0.arpMode = 1; $0.arpTime = 0.35 }], blip1k, hits: [(0, 0, 0), (250, 0, 12)], blocks: 450)
        check(pitchRate(relatched.zc, 300...449) > pitchRate(lowRun.zc, 300...449) * 1.6,
              "Sampler MISC: Auto latch: a note played after letting go starts a new set (\(pitchRate(relatched.zc, 300...449)) vs \(pitchRate(lowRun.zc, 300...449)) crossings a block)")
        check(sumZ(autoChord.zc, 0...199) * 10 > sumZ(autoSingle.zc, 0...199) * 11,
              "Sampler MISC: Auto (sustain) plays the chord's notes (\(sumZ(autoChord.zc, 0...199)) vs \(sumZ(autoSingle.zc, 0...199)) crossings)")
        let joined = play([misc { $0.arpMode = 1; $0.arpTime = 0.35 }], tone1k, hits: [(0, 0, 0), (20, 0, 12)], blocks: 200)
        check(joined.hits[0] >= 4 && sumZ(joined.zc, 25...199) > sumZ(autoSingle.zc, 25...199),
              "Sampler MISC: a note held later joins the running arpeggio (\(joined.hits[0]) notes)")
        // Echo delay: FEED repeats the note, TIME apart; Ping pong swaps sides; Fat mode packs them in
        let blip = SampleBuffer(left: (0..<3_000).map { $0 % 2 == 0 ? 0.2 : -0.2 }, sampleRate: rate)
        let dry = play([misc { _ in }], blip, hits: one, blocks: 200)
        let wet = play([misc { $0.echoFeed = 0.6; $0.echoTime = 0.35; $0.echoes = 4 }], blip, hits: one, blocks: 200)
        check(wet.hits[0] == 5 && sum(wet.l, 40...199) > sum(dry.l, 0...30) * 0.2 && sum(dry.l, 40...199) < 0.001,
              "Sampler MISC: echoes repeat the note, each quieter (\(wet.hits[0]) hits)")
        check(sum(wet.l, 40...60) > sum(wet.l, 80...100), "Sampler MISC: each echo is quieter than the last")
        let pong = play([misc { $0.echoFeed = 0.6; $0.echoTime = 0.35; $0.echoes = 1; $0.echoPan = 1; $0.echoPingPong = true }], blip, hits: one, blocks: 80)
        check(sum(pong.l, 40...79) > sum(pong.r, 40...79) * 4, "Sampler MISC: Ping pong puts the first echo on the other side")
        let fat = play([misc { $0.echoFeed = 0.6; $0.fatMode = true; $0.echoes = 4 }], blip, hits: one, blocks: 30)
        check(fat.hits[0] == 5, "Sampler MISC: Fat mode packs the echoes in a few ms apart (\(fat.hits[0]) hits in 80 ms)")
        let high = play([misc { $0.echoFeed = 0.6; $0.echoTime = 0.35; $0.echoes = 1; $0.echoPitch = 1 }], tone1k, hits: one, blocks: 70)
        let flat = play([misc { $0.echoFeed = 0.6; $0.echoTime = 0.35; $0.echoes = 1 }], tone1k, hits: one, blocks: 70)
        check(high.l != flat.l, "Sampler MISC: the echo's PITCH changes the echoes")
        // GATE: every note stops at the gate
        let gated = play([misc { $0.gate = 0.3 }], hits: one, blocks: 80)
        let open = play([misc { _ in }], hits: one, blocks: 80)
        check(sum(gated.l, 50...79) < sum(open.l, 50...79) * 0.05, "Sampler MISC: GATE cuts the note short")
        // Polyphony, Mono, Cut self: a second hit stops the first (two in phase sound 4× the energy)
        let twice = [(0, 0, 0), (10, 0, 0)]
        let both = sum(play([misc { _ in }], hits: twice, blocks: 60).l, 30...59)
        for (name, setting) in [("Max 1", misc { $0.polyMax = 1 }), ("Mono", misc { $0.mono = true }), ("Cut self", misc { $0.cutSelf = true })] {
            let alone = sum(play([setting], hits: twice, blocks: 60).l, 30...59)
            check(alone < both * 0.4, "Sampler MISC: \(name) stops the track's last note (\(alone) vs \(both))")
        }
        // Group: track 1's note cuts track 2 when track 2's By is track 1's Cut
        let cutter = misc { $0.cutGroup = 1 }, cutBy1 = misc { $0.cutBy = 1 }
        let grouped = sum(play([cutter, cutBy1], hits: [(0, 1, 0), (10, 0, 0)], blocks: 60).l, 30...59)
        let ungrouped = sum(play([cutter, misc { _ in }], hits: [(0, 1, 0), (10, 0, 0)], blocks: 60).l, 30...59)
        check(grouped < ungrouped * 0.4, "Sampler MISC: Cut / By stops the other track (\(grouped) vs \(ungrouped))")
        // Porta and Full porta: the next note slides in from the last
        let leap = [(0, 0, 0), (10, 0, 12)]
        let monoJump = play([misc { $0.mono = true }], tone1k, hits: leap, blocks: 30)
        let monoSlide = play([misc { $0.mono = true; $0.porta = true; $0.slide = 0.4 }], tone1k, hits: leap, blocks: 30)
        check(sumZ(monoSlide.zc, 11...16) * 10 < sumZ(monoJump.zc, 11...16) * 9,
              "Sampler MISC: Mono with Porta slides up to the next note (\(sumZ(monoSlide.zc, 11...16)) vs \(sumZ(monoJump.zc, 11...16)) crossings)")
        let shortTone = SampleBuffer(left: (0..<2_000).map { sinf(Float($0) * 2 * .pi * 1_000 / 48_000) * 0.3 }, sampleRate: rate)
        let later = [(0, 0, 0), (30, 0, 12)]
        let ended = play([misc { $0.porta = true; $0.slide = 0.4 }], shortTone, hits: later, blocks: 40)
        let full = play([misc { $0.porta = true; $0.fullPorta = true; $0.slide = 0.4 }], shortTone, hits: later, blocks: 40)
        check(sumZ(full.zc, 31...36) * 10 < sumZ(ended.zc, 31...36) * 9,
              "Sampler MISC: Full porta slides even after the last note ended (\(sumZ(full.zc, 31...36)) vs \(sumZ(ended.zc, 31...36)))")
        // Tracking: velocity (Vol) and the note above Mid (Key) move the pan
        let velLeft = play([misc { $0.velTrack = [-1, 0, 0] }], hits: one, blocks: 30)
        check(sum(velLeft.l, 2...29) > sum(velLeft.r, 2...29) * 4, "Sampler MISC: Vol tracking moves a hard hit's pan")
        let keyRight = play([misc { $0.keyTrack = [1, 0, 0]; $0.keyMid = 48 }], hits: [(0, 0, 0)], blocks: 30)
        check(sum(keyRight.r, 2...29) > sum(keyRight.l, 2...29) * 2, "Sampler MISC: Key tracking moves a note above Mid")
        let keyDark = play([misc { $0.keyTrack = [0, 1, 0]; $0.keyMid = 84 }], hits: one, blocks: 30)
        check(sum(keyDark.l, 2...29) < sum(open.l, 2...29) * 0.3, "Sampler MISC: Key tracking on MOD X closes the filter below Mid")
        // Levels adjustment: its own offsets on top of the main PAN, VOL, MOD X, MOD Y (not the same knobs)
        let lvlLeft = play([misc { $0.levelPan = -1 }], hits: one, blocks: 30)
        check(sum(lvlLeft.l, 2...29) > sum(lvlLeft.r, 2...29) * 4, "Sampler MISC: Levels PAN moves every note")
        let lvlSoft = play([misc { $0.levelVol = 0.25 }], hits: one, blocks: 30)
        let lvlRatio = (sum(lvlSoft.l, 2...29) + sum(lvlSoft.r, 2...29)) / max(1e-9, sum(open.l, 2...29) + sum(open.r, 2...29))
        check(lvlRatio > 0.15 && lvlRatio < 0.35, "Sampler MISC: Levels VOL turns every note down (×\(lvlRatio))")
        let lvlDark = play([misc { $0.levelX = -0.8 }], hits: one, blocks: 30)
        check(sum(lvlDark.l, 2...29) < sum(open.l, 2...29) * 0.3, "Sampler MISC: Levels MOD X closes the filter")
        let lvlRes = play([misc { $0.cutoff = 0.5; $0.levelY = 0.9 }], hits: one, blocks: 30)
        let lvlNoRes = play([misc { $0.cutoff = 0.5 }], hits: one, blocks: 30)
        check(abs(sum(lvlRes.l, 2...29) - sum(lvlNoRes.l, 2...29)) > sum(lvlNoRes.l, 2...29) * 0.05, "Sampler MISC: Levels MOD Y changes the resonance")
        // a region drawn on the waveform: with Load regions on, a note plays just that part
        let whole = play([misc { _ in }], hits: one, blocks: 150)
        let part = play([misc { $0.loadRegions = true; $0.regions = [SamplerRegion(start: 0.25, end: 0.5)] }], hits: one, blocks: 150)
        check(sum(part.l, 2...80) > sum(whole.l, 2...80) * 0.5 && sum(part.l, 100...149) < sum(whole.l, 100...149) * 0.01,
              "Sampler: a drawn region plays just that part of the sound (\(sum(part.l, 100...149)) after its end)")
        var mainPan = PadSettings(); mainPan.sampler = misc { $0.levelPan = 0.5 }.sampler
        check(mainPan.pan == 0 && mainPan.sampler?.volume == SamplerSettings().volume, "Sampler MISC: Levels leaves the main PAN and VOL where they are")
        var restored = PadSettings(); restored.sampler = misc { $0.arpMode = 3; $0.echoFeed = 0.4; $0.keyTrack = [0.5, 0, 0]; $0.cutGroup = 2; $0.mono = true }.sampler
        let back = (try? JSONEncoder().encode(restored)).flatMap { try? JSONDecoder().decode(PadSettings.self, from: $0) }
        check(back?.sampler == restored.sampler, "Sampler MISC: its settings are saved with the track")

        // Realtime stretching: ×2 plays twice as long with nothing computed first
        let quarter = SampleBuffer(left: (0..<12_000).map { sinf(Float($0) * 2 * .pi * 220 / 48_000) * 0.5 }, sampleRate: rate)
        var realtime = PadSettings(); realtime.sampler = SamplerSettings()
        realtime.sampler?.stretch = .realtime; realtime.sampler?.multiplier = 0.75
        check(realtime.sampler?.offline(bpm: 120) == nil, "Sampler: Realtime stretching computes nothing ahead")
        let after = 110...160
        check(energy(plain, quarter, blocks: after) < 0.01 && energy(realtime, quarter, blocks: after) > 1,
              "Sampler: Realtime ×2 keeps a quarter-second sound going twice as long")

        // custom loop points with a crossfade: the loop's end blends into what leads up to its start
        var looping = SamplerSettings(); looping.loopStart = 0.5; looping.loopEnd = 0.9; looping.crossfade = 0.5; looping.declick = .off
        let blended = SamplerProcessor.process(tone, looping.offline(bpm: 120)!, engineRate: rate)
        check(abs(blended.loopStart - 24_000) < 2 && abs(blended.loopEnd - 43_200) < 2,
              "Sampler: loop points with CROSSFADE keep the loop where it was set (\(blended.loopStart)…\(blended.loopEnd))")
        var loopOnly = SamplerSettings(); loopOnly.loopStart = 0.5
        check(loopOnly.offline(bpm: 120) == nil, "Sampler: loop points alone compute nothing ahead")

        // the waveform's edits
        let edited = SampleEditor.apply(.delete(0..<4_800), to: ramp)
        check(edited.left.count == 4_800 && abs(edited.left[0] - ramp.left[4_800]) < 0.000_1,
              "Sampler: DELETE takes the selection out")
        check(abs((edited.map(0.75) ?? -1) - 0.5) < 0.001 && edited.map(0.25) == nil,
              "Sampler: markers after a cut move with the audio, those in it go")
        let piece = SampleEditor.clip(ramp, 0..<960)
        let inserted = SampleEditor.apply(.insert(piece, at: 4_800), to: ramp)
        check(inserted.left.count == 10_560 && abs(inserted.left[4_800] - ramp.left[0]) < 0.000_1,
              "Sampler: PASTE inserts at the selection")
        let replaced = SampleEditor.apply(.replace(piece, over: 0..<4_800), to: ramp)
        check(replaced.left.count == 960 + 4_800, "Sampler: PASTE can replace the selection")
        let padded = SampleBuffer(left: Array(repeating: 0, count: 4_800) + (0..<4_800).map { sinf(Float($0) * 0.1) * 0.5 } + Array(repeating: 0, count: 9_600),
                                  sampleRate: rate)
        let trimmedSilence = SampleEditor.apply(.trimSilence, to: padded)
        check(trimmedSilence.left.count < 5_000 && trimmedSilence.left.count > 4_700,
              "Sampler: TRIM takes the silence off both ends (\(trimmedSilence.left.count))")
        let faded = SampleEditor.apply(.fadeIn(0..<9_600), to: ramp)
        check(abs(faded.left[1]) < 0.001 && abs(faded.left[9_599] - ramp.left[9_599]) < 0.01, "Sampler: FADE IN rises from silence")
        var bake = SamplerSettings(); bake.normalize = true; bake.stretch = .stretch; bake.multiplier = 1; bake.markers = [0.75]
        bake.baked { $0 < 0.5 ? nil : ($0 - 0.5) * 2 }
        check(bake.offline(bpm: 120) == nil && bake.markers == [0.5], "Sampler: an edit bakes the computed settings into the file")

        // envelope presets
        let presets = SamplerEnvelopePreset.factory
        check(SamplerEnvelopePreset.kinds.allSatisfy { k in presets.contains { $0.kind == k } }
              && presets.allSatisfy { $0.envelopes[SamplerTarget.volume.rawValue].on },
              "Sampler: envelope presets for 808s, kicks and snares shape the volume")
        let round = (try? JSONEncoder().encode(presets)).flatMap { try? JSONDecoder().decode([SamplerEnvelopePreset].self, from: $0) }
        check(round == presets, "Sampler: envelope presets save and load")
    }

    /// Tyrone, Oct 19: every precomputed effect and time stretch on the SAMPLE page is heard, each
    /// one off leaves the sound exactly as it loaded (nothing is computed), the file is never touched
    /// (the processor works on a copy), and the library's preview volume sets how loud a preview plays.
    static func checkPrecomputedEffects() {
        let rate = 48_000.0
        func sine(_ hz: Float, _ seconds: Double, _ amp: Float = 0.5) -> [Float] { (0..<Int(seconds * rate)).map { sinf(Float($0) * 2 * .pi * hz / Float(rate)) * amp } }
        let tone = SampleBuffer(left: sine(220, 1), sampleRate: rate)
        func run(_ sample: SampleBuffer = tone, bpm: Double = 120, _ change: (inout SamplerSettings) -> Void) -> SampleBuffer {
            var st = SamplerSettings(); st.declick = .off; change(&st)
            return SamplerProcessor.process(sample, st.offline(bpm: bpm) ?? SamplerOffline(declick: .off), engineRate: rate)
        }
        func values(_ b: SampleBuffer, right: Bool = false) -> [Float] { Array(UnsafeBufferPointer(start: right ? b.right : b.left, count: b.length)) }
        func energy(_ x: [Float], _ r: Range<Int>) -> Float { x[r.clamped(to: 0..<x.count)].reduce(0) { $0 + $1 * $1 } }
        func peak(_ b: SampleBuffer) -> Float { (0..<b.length).reduce(0) { max($0, abs(b.left[$1]), abs(b.right[$1])) } }
        func crossings(_ x: [Float], _ r: Range<Int>) -> Int { r.clamped(to: 1..<x.count).reduce(0) { $0 + ((x[$1 - 1] < 0) != (x[$1] < 0) ? 1 : 0) } }

        // untouched: nothing is computed, and every new control turned back to its start computes nothing again
        let changes: [(String, (inout SamplerSettings) -> Void, (inout SamplerSettings) -> Void)] = [
            ("Remove DC offset", { $0.removeDC = true }, { $0.removeDC = false }),
            ("Normalize", { $0.normalize = true }, { $0.normalize = false }),
            ("Reverse", { $0.reverse = true }, { $0.reverse = false }),
            ("Reverse polarity", { $0.reversePolarity = true }, { $0.reversePolarity = false }),
            ("Fade stereo", { $0.fadeStereo = true }, { $0.fadeStereo = false }),
            ("Swap stereo", { $0.swapStereo = true }, { $0.swapStereo = false }),
            ("POGO", { $0.pogo = 0.6 }, { $0.pogo = 0 }),
            ("TRIM", { $0.trim = 0.5 }, { $0.trim = 0 }),
            ("CROSSFADE", { $0.crossfade = 0.5 }, { $0.crossfade = 0 }),
            ("EQ", { $0.eq = 0.8 }, { $0.eq = 0 }),
            ("BOOST", { $0.boost = 1 }, { $0.boost = 0 }),
            ("RM MIX", { $0.rmMix = 1; $0.rmFreq = 0.2 }, { $0.rmMix = 0 }),
            ("DELAY", { $0.delayMix = 0.6; $0.delayTime = 0.9 }, { $0.delayMix = 0 }),
            ("REVERB", { $0.reverbMix = 0.6; $0.reverbB = true }, { $0.reverbMix = 0 }),
            ("Time stretch MUL", { $0.stretch = .stretchPro; $0.multiplier = 0.8 }, { $0.stretch = .resample; $0.multiplier = 0.5 }),
        ]
        check(SamplerSettings().offline(bpm: 120) == nil, "Precomputed effects: an untouched sampler computes nothing (the sound plays as it loaded)")
        for (name, on, off) in changes {
            var st = SamplerSettings(); on(&st)
            let changed = st.offline(bpm: 120) != nil
            off(&st)
            check(changed && st.offline(bpm: 120) == nil, "Precomputed effects: \(name) computes the sound only while it's on")
        }
        let before = values(tone)
        _ = run { $0.reverse = true; $0.normalize = true; $0.boost = 1; $0.reverbMix = 1 }
        check(values(tone) == before, "Precomputed effects: processing works on a copy (the original sound is untouched)")

        // the switches
        let offset = SampleBuffer(left: sine(220, 1).map { $0 + 0.25 }, sampleRate: rate)
        let centred = values(run(offset) { $0.removeDC = true })
        let mean = centred.reduce(0, +) / Float(centred.count)
        check(abs(mean) < 0.001, "Precomputed effects: Remove DC offset centres a skewed wave (mean \(mean))")
        let faded = run { $0.fadeStereo = true }
        let fl = values(faded), fr = values(faded, right: true), n = faded.length
        check(energy(fl, 0..<n / 10) > energy(fr, 0..<n / 10) * 20 && energy(fr, n * 9 / 10..<n) > energy(fl, n * 9 / 10..<n) * 20,
              "Precomputed effects: Fade stereo moves the sound from left to right")
        let wide = SampleBuffer(left: sine(220, 0.5), right: sine(220, 0.5, 0.1), sampleRate: rate)
        let swapped = run(wide) { $0.swapStereo = true }
        check(abs(swapped.left[1_000] - wide.right[1_000]) < 0.000_1 && abs(swapped.right[1_000] - wide.left[1_000]) < 0.000_1,
              "Precomputed effects: Swap stereo swaps left and right")

        // time stretching
        let pro = run { $0.stretch = .stretchPro; $0.multiplier = 0.75 }
        check(abs(Double(pro.length) / rate - 2) < 0.05, "Precomputed effects: MUL ×2 with Stretch pro doubles the length (\(pro.length))")
        let fourBeats = SampleBuffer(left: sine(220, 2), sampleRate: rate)
        let auto = run(fourBeats, bpm: 60) { $0.stretch = .stretch; $0.time = .autodetect }
        check(abs(Double(auto.length) / rate - 4) < 0.1, "Precomputed effects: TIME Autodetect follows the tempo (\(auto.length))")
        let fixed = run { $0.stretch = .stretch; $0.time = .seconds(0.5) }
        check(abs(Double(fixed.length) / rate - 0.5) < 0.03, "Precomputed effects: TIME in seconds sets the length (\(fixed.length))")

        // the knobs
        let late = SampleBuffer(left: [Float](repeating: 0, count: 14_400) + sine(220, 0.5), sampleRate: rate)
        let trimmed = run(late) { $0.trim = 0.3 }
        let firstLoud = values(trimmed).firstIndex { abs($0) > 0.01 } ?? -1
        check(trimmed.length < late.length - 14_000 && firstLoud >= 0 && firstLoud < 200,
              "Precomputed effects: TRIM cuts the silence before the sound (\(trimmed.length) samples, sound at \(firstLoud))")
        let rawZ = crossings(values(tone), 0..<1_200)
        let dive = run { $0.pogo = 0.5 }, rise = run { $0.pogo = -0.5 }
        let diveZ = crossings(values(dive), 0..<1_200), riseZ = crossings(values(rise), 0..<1_200)
        check(Double(diveZ) > Double(rawZ) * 1.6 && Double(riseZ) < Double(rawZ) * 0.75 && dive.length < tone.length && rise.length > tone.length,
              "Precomputed effects: POGO bends the start's pitch (crossings raw \(rawZ), dive \(diveZ), rise \(riseZ))")
        let mix = SampleBuffer(left: zip(sine(100, 0.5, 0.3), sine(6_000, 0.5, 0.3)).map { $0 + $1 }, sampleRate: rate)
        func band(_ b: SampleBuffer, high: Bool) -> Float {
            // one-pole split at 1 kHz: what's above or below it
            let x = values(b), a = Float(1 - exp(-2 * Double.pi * 1_000 / rate))
            var low: Float = 0, e: Float = 0
            for v in x { low += a * (v - low); let part = high ? v - low : low; e += part * part }
            return e
        }
        let bright = run(mix) { $0.eq = 1 }, dark = run(mix) { $0.eq = -1 }
        check(band(bright, high: true) > band(mix, high: true) * 2.5 && band(bright, high: false) < band(mix, high: false) * 0.5
              && band(dark, high: true) < band(mix, high: true) * 0.5,
              "Precomputed effects: EQ tilts the sound bright (right) or dark (left) (highs ×\(band(bright, high: true) / band(mix, high: true)), lows ×\(band(bright, high: false) / band(mix, high: false)), dark highs ×\(band(dark, high: true) / band(mix, high: true)))")
        let boosted = peak(run { $0.boost = 1 }) / peak(tone)
        let normBoost = peak(run { $0.normalize = true; $0.boost = 0.5 })
        check(abs(boosted - 3.98) < 0.1 && abs(normBoost - 0.98 * 1.995) < 0.05,
              "Precomputed effects: BOOST adds up to +12 dB, after Normalize too (×\(boosted), \(normBoost))")
        let ring = values(run { $0.rmMix = 1; $0.rmFreq = 0.5 })
        var ringDiff: Float = 0
        for i in 0..<min(ring.count, before.count) { ringDiff = max(ringDiff, abs(ring[i] - before[i])) }
        let ringZ = crossings(ring, 0..<24_000), toneZ = crossings(before, 0..<24_000)
        check(ringDiff > 0.2 && ringZ > toneZ, "Precomputed effects: RM MIX ring-modulates the sound (crossings \(toneZ) → \(ringZ))")
        let hit = SampleBuffer(left: (0..<4_800).map { sinf(Float($0) * 2 * .pi * 200 / Float(rate)) * 0.5 * expf(-Float($0) / 800) }, sampleRate: rate)
        let echoed = run(hit, bpm: 120) { $0.delayMix = 0.8; $0.delayTime = 0.55 }   // 1/8 at 120 = 0.25 s
        let el = values(echoed), er = values(echoed, right: true)
        let first = 12_000..<16_800, second = 24_000..<28_800
        check(echoed.length > hit.length + 24_000 && energy(el, first) > energy(er, first) * 10 && energy(er, second) > energy(el, second) * 10,
              "Precomputed effects: DELAY adds ping-pong echoes, left then right (\(echoed.length) samples)")
        let room = run(hit) { $0.reverbMix = 0.8 }, hall = run(hit) { $0.reverbMix = 0.8; $0.reverbB = true }
        let roomTail = energy(values(room), 9_600..<24_000), hallLate = energy(values(hall), 28_800..<38_400), roomLate = energy(values(room), 28_800..<38_400)
        check(roomTail > 0.01 && hall.length > room.length && hallLate > roomLate * 10,
              "Precomputed effects: REVERB adds a tail, B longer than A (room \(roomTail), hall late \(hallLate))")
        let looped = run { $0.crossfade = 0.5; $0.loopStart = 0.25; $0.loopEnd = 0.75 }
        check(looped.loopEnd > looped.loopStart && looped.loopStart > 0, "Precomputed effects: CROSSFADE makes a blended loop (\(looped.loopStart)…\(looped.loopEnd))")

        // saved with the track; older saves load with everything off; an edit bakes them in
        var all = SamplerSettings(); all.pogo = 0.3; all.eq = -0.2; all.boost = 0.4; all.rmMix = 0.5; all.rmFreq = 0.3
        all.delayMix = 0.2; all.delayTime = 0.7; all.reverbMix = 0.3; all.reverbB = true
        let round = (try? JSONEncoder().encode(all)).flatMap { try? JSONDecoder().decode(SamplerSettings.self, from: $0) }
        check(round == all, "Precomputed effects: the new knobs are saved with the track")
        let old = try? JSONDecoder().decode(SamplerSettings.self, from: Data(#"{"volume":0.5,"normalize":false}"#.utf8))
        check(old?.offline(bpm: 120) == nil, "Precomputed effects: a sampler saved before them loads with them off")
        all.baked { $0 }
        check(all.offline(bpm: 120) == nil, "Precomputed effects: an edit bakes the new knobs into the file")

        // the library's preview volume: a hit's level follows it
        func previewPeak(_ gain: Float) -> Float {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                            (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0)]
            for (p, v) in quiet { e.setParam(p, v) }
            let flat = SampleBuffer(left: [Float](repeating: 0.2, count: 9_600), sampleRate: rate)
            e.kitHandoff.publish(KitBuffers(name: "PREVIEW", samples: Array(repeating: flat, count: Pad.count),
                                            settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110))
            e.send(KEvent(kind: .pad, a: 0, value: 1, gain: gain))
            var top: Float = 0
            for _ in 0..<20 {
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                top = max(top, left.map { abs($0) }.max() ?? 0)
            }
            return top
        }
        // a library sound previewed (double tap): heard at the preview volume, no track plays or changes
        func libraryPreview(_ gain: Float) -> (Float, UInt32) {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0)]
            for (p, v) in quiet { e.setParam(p, v) }
            let silent = SampleBuffer(left: [Float](repeating: 0, count: 64), sampleRate: rate)
            e.kitHandoff.publish(KitBuffers(name: "PREVIEW", samples: Array(repeating: silent, count: Pad.count),
                                            settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110))
            e.previewHandoff.publish(PreviewSound(SampleBuffer(left: [Float](repeating: 0.25, count: 4_800), sampleRate: 44_100), gain: gain))
            var top: Float = 0
            for _ in 0..<30 {
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                top = max(top, left.map { abs($0) }.max() ?? 0)
            }
            return (top, (0..<Pad.count).reduce(0) { $0 + e.padHits[$1] })
        }
        let (libFull, libHits) = libraryPreview(1), (libHalf, _) = libraryPreview(0.5)
        check(abs(libFull - 0.25) < 0.01 && abs(libHalf - 0.125) < 0.01 && libHits == 0,
              "Library preview: a double-tapped sound is heard at the preview volume and no track plays (\(libFull), \(libHalf), hits \(libHits))")
        let full = previewPeak(1), half = previewPeak(0.5), none = previewPeak(0)
        check(full > 0.01 && abs(half / full - 0.5) < 0.05 && none < 0.000_1,
              "Preview volume: a preview plays at the slider's level (100% \(full), 50% \(half), 0% \(none))")
    }

    /// Tyrone, Oct 25: every sound is a one-shot. A piano-roll note's length (the 808's too, slides
    /// included) never cuts the sound: kit sounds and loaded samples ring out exactly as a note with
    /// no length does, untouched or with the sampler opened. A Volume envelope with a release is a
    /// change on top, so its note ends where the note does.
    /// NOTE REPEAT (Tyrone, Oct 26): a held pad repeats every division on the engine's beat, sample
    /// for sample, at the press's velocity; lifting, turning it off, panic and a mode change stop it;
    /// two hands on one pad never double it; it follows the DAW's tempo and locks to the running
    /// pattern's grid; a controller pad repeats until its note off; saved pads keep it, old saves
    /// load it off at 1/16.
    static func checkNoteRepeat() {
        let rate = 48_000.0
        let kick = Pad.kick.rawValue
        let def = KitLibrary.drumMastery
        let samples = def.pads.enumerated().map { DrumSynth.render($0.element, sampleRate: rate, seed: UInt32($0.offset + 1)) }
        func kit(repeatOn: Bool, division: Int = NoteRepeat.defaultDivision) -> KitBuffers {
            var settings = Array(repeating: PadSettings(), count: Pad.count)
            settings[kick].noteRepeat = repeatOn
            settings[kick].repeatDivision = division
            return KitBuffers(name: def.name, samples: samples, settings: settings, bassHz: def.bassHz, renderSampleRate: rate)
        }
        func engine(division: Int = NoteRepeat.defaultDivision, standalone: Bool = true) -> KnockEngine {
            let e = KnockEngine()
            e.standalone = standalone
            e.prepare(sampleRate: rate, maxFrames: 4_096)
            e.setTempo(120)
            e.setParam(.playMode, 0)                                     // ONE-SHOT
            e.kitHandoff.publish(kit(repeatOn: true, division: division))
            e.patternHandoff.publish(PatternSet(Array(repeating: PatternData(name: "EMPTY", lengthTicks: PatternData.ppq * 4, events: []),
                                                      count: Pad.count)))
            // the kick's hits come back out as MIDI on channel 16, each at its own sample
            e.send(KEvent(kind: .midiOut, a: Int32(kick), value: 15 * 128 + 36))
            e.send(KEvent(kind: .midiOut, a: -1, value: 1))
            return e
        }
        var l = [Float](repeating: 0, count: 4_096), r = [Float](repeating: 0, count: 4_096)
        var clock = 0
        var onsets: [(at: Int, velocity: UInt8)] = []
        func render(_ e: KnockEngine, samples total: Int, block: Int = 128, host: ((Int) -> HostTiming)? = nil) {
            var done = 0
            while done < total {
                let n = min(block, total - done)
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        e.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!, host: host?(clock))
                    }
                }
                e.forEachMIDIOut { frame, status, _, velocity in
                    if status == 0x9F && velocity > 0 { onsets.append((clock + frame, velocity)) }
                }
                clock += n
                done += n
            }
        }
        func gaps() -> [Int] { onsets.count > 1 ? (1..<onsets.count).map { onsets[$0].at - onsets[$0 - 1].at } : [] }

        // Every division at 120 BPM, transport stopped: the press, then a repeat every division.
        for division in 0..<NoteRepeat.count {
            let e = engine(division: division)
            clock = 0; onsets = []
            render(e, samples: 256)
            onsets = []
            e.send(KEvent(kind: .padHold, a: Int32(kick), value: 0.8))
            let step = NoteRepeat.beats(division) * 0.5 * rate          // 120 BPM: half a second a beat
            render(e, samples: Int(step * 4.5))
            let g = gaps()
            let exact = !g.isEmpty && g.allSatisfy { abs(Double($0) - step) <= 1.01 }
            check(onsets.count == 5 && exact && onsets.first?.at == 256 && onsets.allSatisfy { $0.velocity == 102 },
                  "NOTE REPEAT \(NoteRepeat.name(division)): press + 4 repeats, \(Int(step)) samples apart, same velocity (got \(onsets.count) hits, gaps \(Set(g)))")
            e.send(KEvent(kind: .padLift, a: Int32(kick)))
            let held = onsets.count
            render(e, samples: Int(step * 4) + 2_048)
            check(onsets.count == held, "NOTE REPEAT \(NoteRepeat.name(division)): letting go stops the repeats (\(onsets.count - held) after release)")
        }

        // Off on the pad: a hold is one hit, and nothing more.
        do {
            let e = engine()
            e.kitHandoff.publish(kit(repeatOn: false))
            clock = 0; onsets = []
            render(e, samples: 256)
            e.send(KEvent(kind: .padHold, a: Int32(kick), value: 0.8))
            render(e, samples: 48_000)
            e.send(KEvent(kind: .padLift, a: Int32(kick)))
            check(onsets.count == 1, "NOTE REPEAT off: holding the pad plays it once (\(onsets.count) hits)")
        }

        // Turned off while held, panic, and a ONE-SHOT / LOOP change each stop it.
        let stops: [(String, (KnockEngine) -> Void)] = [
            ("turning NOTE REPEAT off", { e in e.kitHandoff.publish(kit(repeatOn: false)) }),
            ("panic", { e in e.send(KEvent(kind: .allOff)) }),
            ("switching to LOOP", { e in e.setParam(.playMode, 1) })
        ]
        for (what, stop) in stops {
            let e = engine()
            clock = 0; onsets = []
            e.send(KEvent(kind: .padHold, a: Int32(kick), value: 0.8))
            render(e, samples: 13_000)                                   // press + 2 repeats
            let before = onsets.count
            stop(e)
            render(e, samples: 48_000)
            check(before == 3 && onsets.count == before, "NOTE REPEAT: \(what) while the pad is held stops its repeats (\(before) then \(onsets.count))")
            // and nothing is left behind: a fresh press with repeat on runs normally again
            e.setParam(.playMode, 0)
            e.kitHandoff.publish(kit(repeatOn: true))
            render(e, samples: 1_024)
            onsets = []
            e.send(KEvent(kind: .padHold, a: Int32(kick), value: 0.8))
            render(e, samples: 12_500)
            e.send(KEvent(kind: .padLift, a: Int32(kick)))
            render(e, samples: 12_000)
            check(onsets.count == 3, "NOTE REPEAT: after \(what) a new hold repeats again and stops on release (\(onsets.count) hits)")
        }

        // A finger and a controller pad on the same pad: their own presses, but one stream of repeats,
        // and it runs until both have let go.
        do {
            let e = engine()
            clock = 0; onsets = []
            e.send(KEvent(kind: .padHold, a: Int32(kick), value: 0.8))
            render(e, samples: 3_000)
            e.receiveMIDI(status: 0x99, data1: 36, data2: 100, time: 0)
            render(e, samples: 21_000)
            let hits = onsets.map { $0.at }
            let repeats = hits.filter { $0 % 6_000 == 0 }
            check(hits.count == 5 && repeats.count == 4, "NOTE REPEAT: two hands on one pad repeat once, not twice (hits at \(hits))")
            e.send(KEvent(kind: .padLift, a: Int32(kick)))
            let afterFinger = onsets.count
            render(e, samples: 12_000)
            check(onsets.count == afterFinger + 2, "NOTE REPEAT: still held on the controller after the finger lifts (\(onsets.count - afterFinger))")
            e.receiveMIDI(status: 0x89, data1: 36, data2: 0, time: 0)
            let afterAll = onsets.count
            render(e, samples: 24_000)
            check(onsets.count == afterAll, "NOTE REPEAT: the controller's note off stops it (\(onsets.count - afterAll) more)")
        }

        // The DAW's tempo (TEMPO SYNC): 90 BPM makes a 1/16 8,000 samples.
        do {
            let e = engine(standalone: false)
            e.setParam(.tempoSync, 1)
            clock = 0; onsets = []
            let host = { (at: Int) in HostTiming(tempo: 90, beat: Double(at) / rate * 1.5, playing: false) }
            render(e, samples: 512, host: host)
            onsets = []
            e.send(KEvent(kind: .padHold, a: Int32(kick), value: 0.8))
            render(e, samples: 33_000, host: host)
            let g = gaps()
            check(onsets.count == 5 && g.allSatisfy { abs($0 - 8_000) <= 1 }, "NOTE REPEAT follows the DAW's tempo (gaps \(Set(g)))")
        }

        // The pattern running: the repeats land on its 1/16 grid, not counted from the press.
        do {
            let e = engine()
            clock = 0; onsets = []
            e.send(KEvent(kind: .play))
            render(e, samples: 1_000, block: 1_000)
            e.send(KEvent(kind: .padHold, a: Int32(kick), value: 0.8))
            render(e, samples: 25_000)
            let hits = onsets.map { $0.at }
            check(hits == [1_000, 6_000, 12_000, 18_000, 24_000], "NOTE REPEAT locks to the playing pattern's grid (hits at \(hits))")
        }

        // Saved: kept as set; a save from before NOTE REPEAT loads it off at 1/16; a new sound keeps it.
        var set = PadSettings()
        set.noteRepeat = true
        set.repeatDivision = 6
        let decoded = (try? JSONEncoder().encode(set)).flatMap { try? JSONDecoder().decode(PadSettings.self, from: $0) }
        check(decoded == set, "NOTE REPEAT: saved and loaded as set (1/32T on)")
        let old = try? JSONDecoder().decode(PadSettings.self, from: Data(#"{"level":0.7,"reverse":true}"#.utf8))
        check(old?.noteRepeat == false && old?.repeatDivision == NoteRepeat.defaultDivision && old?.reverse == true && old?.level == 0.7,
              "NOTE REPEAT: an older save loads with it off at 1/16 and keeps its other settings")
        let bad = try? JSONDecoder().decode(PadSettings.self, from: Data(#"{"noteRepeat":true,"repeatDivision":42}"#.utf8))
        check(bad?.repeatDivision == NoteRepeat.count - 1, "NOTE REPEAT: a division out of range loads as the nearest one")
        let fresh = set.freshSound()
        check(fresh.noteRepeat && fresh.repeatDivision == 6 && fresh.sampleFile == nil, "NOTE REPEAT: a new sound on the pad keeps how the pad repeats")
        check(NoteRepeat.names == ["1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T", "1/64"]
              && (0..<NoteRepeat.count).map(NoteRepeat.beats) == [1, 0.5, 1.0 / 3, 0.25, 1.0 / 6, 0.125, 1.0 / 12, 0.0625],
              "NOTE REPEAT: the knob's eight divisions in order, T = triplet")
    }

    static func checkNoteLengthOneShots() {
        let rate = 48_000.0
        let tail = SampleBuffer(left: (0..<72_000).map { i in sinf(Float(i) * 2 * .pi * 110 / 48_000) * 0.4 * expf(-Float(i) / 30_000) },
                                sampleRate: rate)
        let step = Int32(PatternData.ppq / 4)
        func pattern(_ length: Int32) -> PatternData {
            PatternData(name: "ONE-SHOT", lengthTicks: PatternData.ppq * 4, events: [
                GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1, length: length),
                GrooveEvent(tick: step * 4, pad: Int8(Pad.snare.rawValue), velocity: 0.9, length: length),
                GrooveEvent(tick: step * 6, pad: Int8(Pad.bass808.rawValue), velocity: 1, semis: 3, length: length),
                GrooveEvent(tick: step * 10, pad: Int8(Pad.bass808.rawValue), velocity: 1, semis: 7, length: length, glide: true)
            ])
        }
        var params = [Float](repeating: 0, count: KParam.count)
        for p in KParam.allCases { params[p.rawValue] = p.defaultValue }
        func export(_ length: Int32, sampler: SamplerSettings?, file: String?) -> [Float] {
            let settings = (0..<Pad.count).map { _ in var p = PadSettings(); p.sampler = sampler; p.sampleFile = file; return p }
            let kit = KitBuffers(name: "ONE-SHOT", samples: Array(repeating: tail, count: Pad.count), settings: settings, bassHz: 110)
            let job = Exporter.Job(kit: kit, patterns: PatternSet(Array(repeating: pattern(length), count: Pad.count)), loop: 0, params: params,
                                   tempo: 120, bars: 2, baseName: "oneshot")
            return Exporter.render(job, mask: 0xFFFF).0
        }
        func difference(_ a: [Float], _ b: [Float]) -> Float {
            guard a.count == b.count else { return .infinity }
            var d: Float = 0
            for i in a.indices { d = max(d, abs(a[i] - b[i])) }
            return d
        }
        var released = SamplerSettings()
        released.setEnvelope(.volume) { $0.on = true; $0.sustain = 0.6; $0.release = 0.05 }
        for file in [nil, "oneshot.wav"] as [String?] {
            let what = file == nil ? "kit sounds" : "loaded samples"
            for sampler in [nil, SamplerSettings()] as [SamplerSettings?] {
                let opened = sampler == nil ? "" : " (sampler opened)"
                let whole = export(0, sampler: sampler, file: file)
                let d = max(difference(whole, export(step / 2, sampler: sampler, file: file)),
                            difference(whole, export(step, sampler: sampler, file: file)))
                check(whole.contains { abs($0) > 0.01 } && d < 1e-5,
                      "One-shots: short piano-roll notes and 808 slides play the \(what) whole\(opened) (max difference \(d))")
            }
            let shaped = difference(export(step / 2, sampler: released, file: file), export(step * 8, sampler: released, file: file))
            check(shaped > 0.01, "One-shots: a Volume envelope release on \(what) follows the note length (difference \(shaped))")
        }
    }

    /// Tyrone, Oct 19: the ENVELOPE page changes nothing until it's changed. A track whose sampler
    /// was opened (or whose envelopes were switched on with no knob moved off its start) renders
    /// sample for sample what it did with no sampler: note lengths, one-shots, the 808 and a
    /// multisampled drum's velocity layers. Turning one knob is heard as that knob alone.
    static func checkUntouchedEnvelopes() {
        let rate = 48_000.0
        // a long decaying tone (a drum with a tail), so a cut or a fade anywhere shows
        let tail = SampleBuffer(left: (0..<72_000).map { i in sinf(Float(i) * 2 * .pi * 220 / 48_000) * 0.4 * expf(-Float(i) / 30_000) },
                                sampleRate: rate)
        let opened = SamplerSettings()
        var switchedOn = SamplerSettings()
        for t in SamplerTarget.allCases { switchedOn.setEnvelope(t) { $0.on = true } }
        func pads(_ sampler: SamplerSettings?, file: String?) -> [PadSettings] {
            (0..<Pad.count).map { _ in var p = PadSettings(); p.sampler = sampler; p.sampleFile = file; return p }
        }
        // drum notes with and without a length (piano roll / drum roll), and an 808 with a length and a slide
        let step = Int32(PatternData.ppq / 4)
        let pattern = PatternData(name: "UNTOUCHED", lengthTicks: PatternData.ppq * 4, events: [
            GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1, length: step),
            GrooveEvent(tick: step * 2, pad: Int8(Pad.hat.rawValue), velocity: 0.6),
            GrooveEvent(tick: step * 4, pad: Int8(Pad.snare.rawValue), velocity: 0.9, length: step * 3),
            GrooveEvent(tick: step * 6, pad: Int8(Pad.bass808.rawValue), velocity: 1, semis: 3, length: step * 2),
            GrooveEvent(tick: step * 8, pad: Int8(Pad.bass808.rawValue), velocity: 1, semis: 7, length: step * 2, glide: true),
            GrooveEvent(tick: step * 12, pad: Int8(Pad.clap.rawValue), velocity: 0.4, length: step)
        ])
        var params = [Float](repeating: 0, count: KParam.count)
        for p in KParam.allCases { params[p.rawValue] = p.defaultValue }
        func export(_ settings: [PadSettings]) -> [Float] {
            let kit = KitBuffers(name: "UNTOUCHED", samples: Array(repeating: tail, count: Pad.count), settings: settings, bassHz: 110)
            let job = Exporter.Job(kit: kit, patterns: PatternSet(Array(repeating: pattern, count: Pad.count)), loop: 0, params: params,
                                   tempo: 120, bars: 2, baseName: "untouched")
            return Exporter.render(job, mask: 0xFFFF).0
        }
        func difference(_ a: [Float], _ b: [Float]) -> Float {
            guard a.count == b.count else { return .infinity }
            var d: Float = 0
            for i in a.indices { d = max(d, abs(a[i] - b[i])) }
            return d
        }
        for file in [nil, "untouched.wav"] as [String?] {
            let what = file == nil ? "kit sounds" : "loaded samples"
            let plain = export(pads(nil, file: file))
            check(plain.contains { abs($0) > 0.01 } && difference(plain, export(pads(nil, file: file))) == 0,
                  "Untouched envelopes: the \(what) pattern renders the same twice")
            let a = difference(plain, export(pads(opened, file: file)))
            check(a < 1e-5, "Untouched envelopes: an opened sampler leaves \(what) as they were (max difference \(a))")
            let b = difference(plain, export(pads(switchedOn, file: file)))
            check(b < 1e-5, "Untouched envelopes: envelopes switched on with no knob moved leave \(what) as they were (max difference \(b))")
        }

        // pad taps, one at a time: the whole hit, sample for sample
        func tap(_ settings: PadSettings, velocity: Double = 1, blocks: Int = 600, layers: [VelocityLayers?] = []) -> [Float] {
            var all = Array(repeating: PadSettings(), count: Pad.count)
            all[Pad.snare.rawValue] = settings
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            e.setParam(.playMode, 0); e.setParam(.followDAW, 0); e.setParam(.tempoSync, 0)
            e.setParam(.velocity, 1); e.setParam(.boost, 0); e.setParam(.clipper, 0); e.setParam(.clipDrive, 0)
            e.kitHandoff.publish(KitBuffers(name: "TAP", samples: Array(repeating: tail, count: Pad.count), settings: all, bassHz: 110, layers: layers))
            e.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: velocity))
            var out: [Float] = []
            for _ in 0..<blocks {
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                out += left
            }
            return out
        }
        var loaded = PadSettings(); loaded.sampleFile = "untouched.wav"
        var loadedOn = loaded; loadedOn.sampler = switchedOn
        let tapDiff = difference(tap(loaded), tap(loadedOn))
        check(tapDiff < 1e-5, "Untouched envelopes: a tapped one-shot plays whole with its envelopes switched on (max difference \(tapDiff))")

        // a multisampled drum keeps its velocity layers and round robins with the sampler opened
        func tone(_ amplitude: Float) -> SampleBuffer {
            SampleBuffer(left: (0..<12_000).map { sinf(Float($0) * 2 * .pi * 1_000 / 48_000) * amplitude }, sampleRate: rate)
        }
        if let layers = VelocityLayers(source: tail, tops: [0.5, 1], hits: [[tone(0.02)], [tone(0.4), tone(0.2)]]) {
            var padLayers = [VelocityLayers?](repeating: nil, count: Pad.count)
            padLayers[Pad.snare.rawValue] = layers
            var withSampler = PadSettings(); withSampler.sampler = opened
            for velocity in [0.25, 1.0] {
                let d = difference(tap(PadSettings(), velocity: velocity, blocks: 120, layers: padLayers),
                                   tap(withSampler, velocity: velocity, blocks: 120, layers: padLayers))
                check(d < 1e-5, "Untouched envelopes: an opened sampler keeps the drum's velocity layers (velocity \(velocity), max difference \(d))")
            }
        } else { check(false, "Untouched envelopes: layers made") }

        // one knob turned: only that knob is heard (ATT fades the start in; the rest of the hit and its
        // full length stay as they were)
        var attack = loadedOn
        attack.sampler?.setEnvelope(.volume) { $0.attack = 0.3 }
        let plainHit = tap(loaded), slow = tap(attack)
        func energy(_ x: [Float], _ blocks: ClosedRange<Int>) -> Float { x[(blocks.lowerBound * 128)..<(blocks.upperBound * 128)].reduce(0) { $0 + $1 * $1 } }
        let early = energy(slow, 0...20) / max(energy(plainHit, 0...20), 1e-9)
        let late = energy(slow, 200...500) / max(energy(plainHit, 200...500), 1e-9)
        check(early < 0.2 && abs(late - 1) < 0.001, "Untouched envelopes: turning ATT changes only the attack (early ×\(early), late ×\(late))")
        var pan = loadedOn
        pan.sampler?.setEnvelope(.pan) { $0.attack = 0.4 }
        let panDiff = difference(tap(loaded), tap(pan))
        check(panDiff < 1e-5, "Untouched envelopes: a Panning envelope moves nothing until its AMT is turned (max difference \(panDiff))")

        // Tyrone, Oct 19: the Volume envelope knows the sound before it changes it. It starts as the sound
        // is (HOLD = the sound's length), so switched on as it comes nothing changes, on a tap, a loaded
        // one-shot or a pattern; turning HOLD down then shortens the sound from there.
        let soundShape = SamplerEnvelope.measured(tail)
        check(abs(SamplerEnvelope.units(soundShape.hold, tempo: false) - 1.1 * 1.5 - 0.005) < 0.01 && soundShape.sustain == 0 && !soundShape.on,
              "Untouched envelopes: the envelope measures the sound's length into HOLD (\(SamplerEnvelope.units(soundShape.hold, tempo: false)) s)")
        let blip = SampleBuffer(left: (0..<48_000).map { i in i < 9_600 ? sinf(Float(i) * 2 * .pi * 300 / 48_000) * 0.5 * expf(-Float(i) / 1_200) : 0 }, sampleRate: rate)
        let blipHold = SamplerEnvelope.units(SamplerEnvelope.measured(blip).hold, tempo: false)
        check(blipHold > 0.15 && blipHold < 0.25, "Untouched envelopes: a short hit's HOLD is its own length, not the silence after it (\(blipHold) s)")
        var fromSound = SamplerSettings()
        fromSound.setEnvelope(.volume) { $0 = soundShape; $0.on = true }
        var loadedSound = loaded; loadedSound.sampler = fromSound
        var kitSound = PadSettings(); kitSound.sampler = fromSound
        let seededLoaded = difference(tap(loaded), tap(loadedSound))
        let seededKit = difference(tap(PadSettings()), tap(kitSound))
        check(seededLoaded < 1e-5 && seededKit < 1e-5,
              "Untouched envelopes: the envelope switched on as the sound is changes nothing (loaded \(seededLoaded), kit \(seededKit))")
        func exportPad(_ settings: [PadSettings], _ mask: UInt16) -> [Float] {
            let kit = KitBuffers(name: "UNTOUCHED", samples: Array(repeating: tail, count: Pad.count), settings: settings, bassHz: 110)
            let job = Exporter.Job(kit: kit, patterns: PatternSet(Array(repeating: pattern, count: Pad.count)), loop: 0, params: params,
                                   tempo: 120, bars: 2, baseName: "untouched")
            return Exporter.render(job, mask: mask).0
        }
        for file in [nil, "untouched.wav"] as [String?] {
            let plain = export(pads(nil, file: file)), shaped = export(pads(fromSound, file: file))
            let ratio = shaped.reduce(0) { $0 + $1 * $1 } / max(plain.reduce(0) { $0 + $1 * $1 }, 1e-9)
            // each drum on its own, so a failure says which note type changed
            let perPad = [Pad.kick, .snare, .hat, .clap, .bass808].map { p -> String in
                let a = exportPad(pads(nil, file: file), 1 << UInt16(p.rawValue)).reduce(0) { $0 + $1 * $1 }
                let b = exportPad(pads(fromSound, file: file), 1 << UInt16(p.rawValue)).reduce(0) { $0 + $1 * $1 }
                return "\(p.label) ×" + String(format: "%.3f", b / max(a, 1e-9))
            }
            check(abs(ratio - 1) < 0.02, "Untouched envelopes: a pattern plays the same with the envelope as the sound is (\(file == nil ? "kit sounds" : "loaded samples"), level ×\(ratio); \(perPad.joined(separator: ", ")))")
        }
        var shorter = loadedSound
        shorter.sampler?.setEnvelope(.volume) { $0.hold = SamplerEnvelope.knob(seconds: 0.1) }
        let cutLate = energy(tap(shorter), 200...500) / max(energy(tap(loaded), 200...500), 1e-9)
        let keptEarly = energy(tap(shorter), 0...20) / max(energy(tap(loaded), 0...20), 1e-9)
        check(cutLate < 0.01 && abs(keptEarly - 1) < 0.001, "Untouched envelopes: HOLD turned down shortens the sound from its own shape (late ×\(cutLate), start ×\(keptEarly))")

        // saved before Oct 19: envelopes never switched on take the new defaults; ones in use keep their shape
        var oldVolume = SamplerEnvelope.shaped; oldVolume.amount = 1
        var oldPan = SamplerEnvelope.shaped
        var used = SamplerEnvelope.shaped; used.on = true
        func roundTrip(_ e: SamplerEnvelope) -> SamplerEnvelope? { (try? JSONEncoder().encode(e)).flatMap { try? JSONDecoder().decode(SamplerEnvelope.self, from: $0) } }
        oldPan.amount = 0.5
        var neutralVolume = SamplerEnvelope(); neutralVolume.amount = 1
        check(roundTrip(oldVolume) == neutralVolume && roundTrip(oldPan) == SamplerEnvelope() && roundTrip(used) == used,
              "Untouched envelopes: old saves' untouched envelopes load with the new defaults, used ones as they were")
        check(SamplerSettings.defaultEnvelopes.allSatisfy { !$0.on && $0.attack == 0 && $0.hold == 0 && $0.sustain == 1 && $0.release == 0 && $0.delay == 0 }
              && SamplerSettings.defaultEnvelopes[SamplerTarget.volume.rawValue].amount == 1
              && SamplerSettings.defaultEnvelopes.enumerated().allSatisfy { $0.offset == SamplerTarget.volume.rawValue || $0.element.amount == 0 },
              "Untouched envelopes: the defaults are no attack, full sustain, no release, AMT 0")
    }

    /// A multisampled pad: a soft hit plays the soft recording, a hard one the loud one, and repeated
    /// hits step through the layer's round robins.
    static func checkVelocityLayers() {
        let rate = 48_000.0
        func tone(_ amplitude: Float) -> SampleBuffer {
            SampleBuffer(left: (0..<12_000).map { sinf(Float($0) * 2 * .pi * 1_000 / 48_000) * amplitude }, sampleRate: rate)
        }
        let main = tone(0.4), soft = tone(0.02), hardA = tone(0.4), hardB = tone(0.2)
        guard let layers = VelocityLayers(source: main, tops: [0.5, 1], hits: [[soft], [hardA, hardB]]) else {
            check(false, "layers: made"); return
        }
        check(layers.layer(for: 0.3) == 0 && layers.layer(for: 0.5) == 0 && layers.layer(for: 0.51) == 1 && layers.layer(for: 1) == 1,
              "layers: how hard a hit is picks its layer")
        check(VelocityLayers(source: main, tops: [1], hits: [[]]) == nil, "layers: a layer needs a hit")
        var padLayers = [VelocityLayers?](repeating: nil, count: Pad.count)
        padLayers[Pad.snare.rawValue] = layers
        let kit = KitBuffers(name: "LAYERS", samples: Array(repeating: main, count: Pad.count),
                             settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110, layers: padLayers)
        func engine() -> KnockEngine {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            e.setParam(.playMode, 0); e.setParam(.followDAW, 0); e.setParam(.tempoSync, 0)
            e.setParam(.velocity, 1); e.setParam(.boost, 0); e.setParam(.clipper, 0); e.setParam(.clipDrive, 0)
            e.kitHandoff.publish(kit)
            return e
        }
        func peak(_ e: KnockEngine, blocks: Int = 4) -> Float {
            var p: Float = 0
            for _ in 0..<blocks {
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) }
                }
                p = max(p, left.map(abs).max() ?? 0)
            }
            return p
        }
        let snare = UInt8(Pad.snare.midiNote), kick = UInt8(Pad.kick.midiNote)
        let s = engine(); s.hostMIDI(offset: 0, status: 0x90, data1: snare, data2: 32)
        let h = engine(); h.hostMIDI(offset: 0, status: 0x90, data1: snare, data2: 127)
        let k = engine(); k.hostMIDI(offset: 0, status: 0x90, data1: kick, data2: 127)
        let softPeak = peak(s), hardPeak = peak(h), plainPeak = peak(k)
        check(softPeak > 0.002 && softPeak < hardPeak * 0.1, "layers: a soft hit plays the soft recording (\(softPeak) vs \(hardPeak))")
        check(abs(hardPeak - plainPeak) < plainPeak * 0.1, "layers: a full hit plays the loud recording at full level")
        _ = peak(h, blocks: 110)   // let the first hit end
        h.hostMIDI(offset: 0, status: 0x90, data1: snare, data2: 127)
        let second = peak(h)
        check(second > hardPeak * 0.3 && second < hardPeak * 0.7, "layers: the next hit takes the layer's next round robin")
    }

    /// A one-shot's tail is independent of note length. Exercise every sequential pad,
    /// the chromatic bass extension, dynamics, and the new per-pad filter at 128 frames.
    static func checkOneShotMIDIAndPadFilters() {
        let rate = 48_000.0
        let sample = SampleBuffer(left: Array(repeating: Float(0.025), count: 12_000), sampleRate: rate)
        let kit = KitBuffers(name: "ONE-SHOT MIDI", samples: Array(repeating: sample, count: Pad.count),
                             settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110)
        func engine(using sounds: KitBuffers? = nil) -> KnockEngine {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            e.setParam(.playMode, 0)
            e.setParam(.followDAW, 0)
            e.setParam(.tempoSync, 0)
            e.setParam(.velocity, 1)
            e.setParam(.boost, 0)
            e.setParam(.clipper, 0)
            e.setParam(.clipDrive, 0)
            e.kitHandoff.publish(sounds ?? kit)
            return e
        }
        func block(_ e: KnockEngine) -> [Float] {
            var left = [Float](repeating: 0, count: 128), right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil)
                }
            }
            return left
        }
        func energy(_ values: [Float]) -> Float { values.reduce(0) { $0 + $1 * $1 } }
        for note in (36...47).map({ UInt8($0) }) + [48, 60, 84] {
            let short = engine(), held = engine()
            for e in [short, held] { e.hostMIDI(offset: 0, status: 0x90, data1: note, data2: 127) }
            // An immediate key release must leave the first sample, attack and entire tail
            // identical to a key held through all 32 callbacks, including the 808.
            short.hostMIDI(offset: 1, status: 0x80, data1: note, data2: 0)
            var identical = true
            var audible = false
            for _ in 0..<32 {
                let a = block(short), b = block(held)
                identical = identical && zip(a, b).allSatisfy { abs($0.0 - $0.1) < 0.000_001 }
                audible = audible || a.contains { abs($0) > 0.001 }
            }
            let pad = Pad.index(forMIDINote: Int(note)) ?? Pad.bass808.rawValue
            check(identical && audible, "One-Shot MIDI \(note): immediate release preserves the complete tail")
            check(short.padHits[pad] == 1 && short.status[0] == 0, "One-Shot MIDI \(note): one note creates one strike without sequencing")
            short.hostMIDI(offset: 7, status: 0x90, data1: note, data2: 0)
            _ = block(short)
            check(short.padHits[pad] == 1, "One-Shot MIDI \(note): zero velocity releases without retriggering")
            short.hostMIDI(offset: 7, status: 0x90, data1: note, data2: 100)
            _ = block(short)
            check(short.padHits[pad] == 2, "One-Shot MIDI \(note): another programmed note creates the next strike")
        }
        for note: UInt8 in [36, 37, 42, 47, 48, 60] {
            let soft = engine(), hard = engine()
            soft.hostMIDI(offset: 0, status: 0x90, data1: note, data2: 32)
            hard.hostMIDI(offset: 0, status: 0x90, data1: note, data2: 127)
            let softEnergy = energy(block(soft)), hardEnergy = energy(block(hard))
            check(softEnergy > 0 && softEnergy < hardEnergy * 0.1, "One-Shot MIDI \(note): velocity controls strike volume")
        }

        var filteredSettings = Array(repeating: PadSettings(), count: Pad.count)
        filteredSettings[0].filter = 0.35
        let highFrequency = SampleBuffer(left: (0..<2_048).map { $0 % 4 == 0 ? 0.1 : $0 % 4 == 2 ? -0.1 : 0 },
                                         right: (0..<2_048).map { $0 % 4 == 0 ? -0.1 : $0 % 4 == 2 ? 0.1 : 0 }, sampleRate: rate)
        let filteredKit = KitBuffers(name: "PAD FILTER", samples: Array(repeating: highFrequency, count: Pad.count),
                                     settings: filteredSettings, bassHz: 110)
        check(filteredKit.filterCoefficients[0] > 0 && filteredKit.filterCoefficients[0] < 1 &&
              filteredKit.filterCoefficients.dropFirst().allSatisfy { $0 == 1 }, "per-pad filter coefficients prepare only the selected pad")
        func voice(_ coefficient: Float) -> Voice {
            Voice(sample: highFrequency, pad: 0, rate: 1, reverse: false, gainL: 1, gainR: 1,
                  decayCoef: 1, holdSamples: 0, chokeGroup: 0, age: 0, remaining: Int.max, heldNote: -1,
                  filterCoefficient: coefficient)
        }
        var open = voice(1), filtered = voice(filteredKit.filterCoefficients[0])
        var openEnergy: Float = 0, filteredEnergy: Float = 0
        var finite = true, stereo = true, bypassExact = true
        for _ in 0..<12 {
            var a = [Float](repeating: 0, count: 128), ar = a, b = a, br = a
            a.withUnsafeMutableBufferPointer { l in ar.withUnsafeMutableBufferPointer { r in
                open.render(into: l.baseAddress!, r.baseAddress!, frames: 128, releaseSamples: 128)
            } }
            b.withUnsafeMutableBufferPointer { l in br.withUnsafeMutableBufferPointer { r in
                filtered.render(into: l.baseAddress!, r.baseAddress!, frames: 128, releaseSamples: 128)
            } }
            openEnergy += energy(a)
            filteredEnergy += energy(b)
            finite = finite && b.allSatisfy { $0.isFinite } && br.allSatisfy { $0.isFinite }
            stereo = stereo && zip(b, br).allSatisfy { abs($0.0 + $0.1) < 0.000_001 }
            bypassExact = bypassExact && a.enumerated().allSatisfy {
                $0.element == ($0.offset % 4 == 0 ? 0.1 : $0.offset % 4 == 2 ? -0.1 : 0)
            }
        }
        check(finite && filteredEnergy > 0 && filteredEnergy < openEnergy * 0.05, "per-pad filter attenuates high frequencies across 128-frame boundaries")
        check(stereo, "per-pad filter preserves independent stereo channels")
        check(bypassExact, "open per-pad filter bypass preserves original samples exactly")
        let openKit = KitBuffers(name: "OPEN PAD FILTER", samples: Array(repeating: highFrequency, count: Pad.count),
                                 settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110)
        let openEngine = engine(using: openKit), filteredEngine = engine(using: filteredKit)
        for e in [openEngine, filteredEngine] { e.hostMIDI(offset: 0, status: 0x90, data1: 36, data2: 127) }
        var engineOpenEnergy: Float = 0, engineFilteredEnergy: Float = 0
        for _ in 0..<12 {
            engineOpenEnergy += energy(block(openEngine))
            engineFilteredEnergy += energy(block(filteredEngine))
        }
        check(engineFilteredEnergy > 0 && engineFilteredEnergy < engineOpenEnergy * 0.1,
              "note-on applies the selected pad filter in the production engine")
        let oldPadJSON = Data(#"{"level":0.6,"pan":-0.2,"tune":7,"decay":0.4,"reverse":true}"#.utf8)
        let oldPad = try? JSONDecoder().decode(PadSettings.self, from: oldPadJSON)
        check(oldPad?.filter == 1 && oldPad?.tune == 7 && oldPad?.reverse == true,
              "older pad presets decode with the filter open and original controls intact")
        let filteredData = try? JSONEncoder().encode(filteredSettings[0])
        let filteredBack = filteredData.flatMap { try? JSONDecoder().decode(PadSettings.self, from: $0) }
        check(filteredBack == filteredSettings[0], "per-pad filter round-trips in presets")
    }
}
