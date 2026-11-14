// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Self-test: knob tapers, readouts and response (Tyrone, Nov 14)
//
// "For each knob: the value shown must be exactly what the DSP does, checked at every 1% from 1 to
// 100; no dead zone; % knobs feel even, so 23% means 23% of the full effect; show the exact value
// while turning; the sound responds within about 5 ms." Every check renders the real DSP.

extension KnockSelfTest {
    static func checkKnobTapers() {
        checkFXKnobSweeps()
        checkUnitKnobReadouts()
        checkKnobResponseTime()
    }

    /// Every FX knob in every mode, main chain and track insert: at each 1% the readout is that
    /// percentage, and the measured change to the sound is that share of the knob's full change.
    private static func checkFXKnobSweeps() {
        for c in KnobContext.all {
            for p in KnobTaperProbe.params(c) {
                let name = "\(c.name) \(SequencerView.fxLabel(p))"
                guard KnobTaper.tapered(p, c) else { check(false, "\(name) has a measured taper"); continue }
                // the readout says the position, and the position comes back from the stored value
                var readoutOK = true, roundTripOK = true
                for k in 0...100 {
                    let v = KnobTaper.value(p, knob: Float(k) / 100, c)
                    if p.text(v, c) != "\(k)%" { readoutOK = false }
                    if abs(KnobTaper.knob(p, value: v, c) - Float(k) / 100) > 0.000_5 { roundTripOK = false }
                }
                check(readoutOK, "\(name): the readout shows 0% to 100% at every 1%")
                // a stored value (an old preset, a host's automation) keeps its exact value under the knob
                var storedOK = true
                for i in 0...200 {
                    let v = Float(i) / 200
                    if abs(KnobTaper.value(p, knob: KnobTaper.knob(p, value: v, c), c) - v) > 0.000_2 { storedOK = false }
                }
                check(roundTripOK && storedOK, "\(name): knob and stored value round-trip, so old presets and automation play as before")
                // the sound, at every 1%. A track's knob with the main chain's taper and the same sound
                // (checked at 25%, 50% and 75%) shares the main chain's sweep, which keeps this phase short.
                if c.insert, let mine = KnobTaperTables.table(p, c), mine == KnobTaperTables.table(p, KnobContext(c.mode)) {
                    let main = KnobTaperProbe.Curve(p, KnobContext(c.mode)), track = KnobTaperProbe.Curve(p, c)
                    let same = [25, 50, 75].allSatisfy { k in
                        let v = KnobTaper.value(p, knob: Float(k) / 100, c)
                        return abs(main.share(v) - track.share(v)) < 0.01
                    }
                    if same { log("\(name): same taper and sound as the main chain's (25/50/75%), its 1% sweep covers it"); continue }
                }
                let shares = KnobTaperProbe.sweep(p, c)
                let tol = KnobTaperProbe.tolerance(p)
                var worst = 0.0, worstAt = 0
                for k in 1...100 {
                    let e = abs(shares[k] - Double(k) / 100)
                    if e > worst { worst = e; worstAt = k }
                }
                check(worst <= tol, "\(name): the sound at every 1% is that share of the full effect (worst \(worstAt)%: \(String(format: "%.1f", shares[worstAt] * 100))%)")
                check(shares[1] >= 0.0025 && shares[10] >= 0.07 && shares[20] >= 0.16,
                      "\(name): no dead zone (1% \(String(format: "%.1f", shares[1] * 100))%, 10% \(String(format: "%.1f", shares[10] * 100))%, 20% \(String(format: "%.1f", shares[20] * 100))% of the full effect)")
                log("\(name): 10% = \(String(format: "%.1f", shares[10] * 100))%, 23% = \(String(format: "%.1f", shares[23] * 100))%, 50% = \(String(format: "%.1f", shares[50] * 100))%, worst \(String(format: "%.1f", worst * 100)) points at \(worstAt)%")
            }
        }
    }

    /// PITCH, TUNE, FILTER, CLIP DRIVE, OUTPUT and SWING: at every 1% the readout is what the
    /// engine plays, measured from a render.
    private static func checkUnitKnobReadouts() {
        let c = KnobContext(.modern)
        let rate = 48_000.0
        // PITCH and TUNE: a 220 Hz sine on the kick pad, its played frequency from its zero crossings
        let sine = (0..<48_000).map { Float(sin(Double($0) * 2 * Double.pi * 220 / rate)) * 0.2 }
        let samples = Array(repeating: SampleBuffer(left: sine, sampleRate: rate), count: Pad.count)
        func playedHz(_ p: KParam, _ v: Float) -> Double {
            let engine = KnockEngine()
            engine.prepare(sampleRate: rate, maxFrames: 512)
            engine.setParam(.playMode, 0); engine.setParam(.followDAW, 0); engine.setParam(.tempoSync, 0); engine.setParam(.clipper, 0)
            engine.setParam(p, v)
            engine.kitHandoff.publish(KitBuffers(name: "PITCH", samples: samples, settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110))
            engine.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 1))
            let total = 12_288
            var left = [Float](repeating: 0, count: total), right = left
            var done = 0
            while done < total {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        engine.render(frames: 128, left: l.baseAddress! + done, right: r.baseAddress! + done, host: nil)
                    }
                }
                done += 128
            }
            // rising zero crossings between 40 ms and the end, interpolated inside the sample
            var first = -1.0, last = -1.0, count = 0
            for i in 1_920..<(total - 1) where left[i] <= 0 && left[i + 1] > 0 {
                let t = Double(i) + Double(-left[i] / (left[i + 1] - left[i]))
                if first < 0 { first = t } else { count += 1 }
                last = t
            }
            return count > 0 ? Double(count) / ((last - first) / rate) : 0
        }
        var pitchOK = true, tuneOK = true, worstCents = 0.0
        for k in 0...100 {
            let v = Float(k) / 100
            let st = KnockMath.pitchSemitones(v)
            let semis = 12 * log2(max(playedHz(.pitch, v), 1) / 220)
            if KParam.pitch.text(v, c) != (st == 0 ? "0 st" : String(format: "%+d st", st)) || abs(semis - Double(st)) > 0.05 { pitchOK = false }
            let cents = 1_200 * log2(max(playedHz(.tune, v), 1) / 220)
            let shown = Double(KParam.tune.text(v, c).split(separator: " ")[0]) ?? .nan
            worstCents = max(worstCents, abs(cents - shown))
            if !(abs(cents - shown) <= 1.5) { tuneOK = false }
        }
        check(pitchOK, "PITCH: at every 1% the readout's semitones are what the engine plays")
        check(tuneOK, "TUNE: at every 1% the readout's cents are what the engine plays (worst \(String(format: "%.2f", worstCents)) ct)")

        // OUTPUT, CLIP DRIVE (clipper off, so it's only gain) and FILTER through the master section
        func masterGain(_ s: MasterBus.Settings, hz: Double) -> Double {
            let bus = MasterBus()
            bus.prepare(sampleRate: rate)
            let n = 9_600
            var l = (0..<n).map { Float(sin(Double($0) * 2 * Double.pi * hz / rate)) * 0.05 }, r = l
            l.withUnsafeMutableBufferPointer { lb in r.withUnsafeMutableBufferPointer { rb in
                var at = 0
                while at < n { let m = min(128, n - at); bus.process(lb.baseAddress! + at, rb.baseAddress! + at, count: m, s); at += m }
            } }
            var e = 0.0
            for i in 4_800..<n { e += Double(l[i] * l[i]) }
            return (e / Double(n - 4_800)).squareRoot() / (0.05 / 2.0.squareRoot())
        }
        var outOK = true, driveOK = true, filterOK = true
        var worstOut = 0.0, worstDrive = 0.0, worstFilter = 0.0
        for k in 0...100 {
            let v = Float(k) / 100
            func shownDB(_ p: KParam) -> Double { Double(p.text(v, c).replacingOccurrences(of: " dB", with: "")) ?? .nan }
            var s = MasterBus.Settings(); s.clipperOn = false; s.output = v
            let outDB = 20 * log10(masterGain(s, hz: 1_000))
            worstOut = max(worstOut, abs(outDB - shownDB(.output)))
            if !(abs(outDB - shownDB(.output)) <= 0.06) { outOK = false }
            s = MasterBus.Settings(); s.clipperOn = false; s.output = 1; s.clipDrive = v
            let driveDB = 20 * log10(masterGain(s, hz: 1_000))
            worstDrive = max(worstDrive, abs(driveDB - shownDB(.clipDrive)))
            if !(abs(driveDB - shownDB(.clipDrive)) <= 0.06) { driveOK = false }
            if k < 100 {
                // at the frequency the readout names, the filter (Q 0.85) is 1.4 dB down
                let text = KParam.filter.text(v, c)
                let hz = Double(text.replacingOccurrences(of: " Hz", with: "")) ?? .nan
                s = MasterBus.Settings(); s.clipperOn = false; s.output = 1; s.filter = v
                let g = 20 * log10(masterGain(s, hz: hz))
                let want = 20 * log10(0.85)
                worstFilter = max(worstFilter, abs(g - want))
                if !(abs(g - want) <= 0.35) { filterOK = false }
            }
        }
        check(outOK, "OUTPUT: at every 1% the readout's dB is the level the engine plays (worst \(String(format: "%.3f", worstOut)) dB)")
        check(driveOK, "CLIP DRIVE: at every 1% the readout's dB is the drive the engine plays (worst \(String(format: "%.3f", worstDrive)) dB)")
        check(filterOK, "FILTER: at every 1% the readout's Hz is the filter's real cutoff (worst \(String(format: "%.2f", worstFilter)) dB off at the named frequency)")

        // SWING: the percentage is where the engine puts the off-beat 1/16 between two 1/8s
        var swingOK = true
        for k in 1...100 {
            let b = Float(k) / 100
            let ticks = PatternData.swingTicks(tick: 24, pad: Pad.hat.rawValue, bounce: Double(b), own: -1)
            let real = (24 + ticks) / 48 * 100
            let shown = Double(KParam.bounce.text(b, c).replacingOccurrences(of: "% SWING", with: "")) ?? .nan
            if !(abs(shown - real) <= 0.501) { swingOK = false }
        }
        check(swingOK, "SWING: at every 1% the readout is the swing the engine plays (50% straight to 67%)")

        // a track's VOLUME readout is the gain its voices play
        var volumeOK = true
        for k in 0...100 {
            var ps = PadSettings(); ps.level = PadSettings.level(knob: Float(k) / 100)
            let db = 20 * log10(Double(ps.gain))
            let shown = Double(KnobHUD.volume(ps.level).split(separator: " ")[0]) ?? .nan
            if !(abs(db - shown) <= 0.051) { volumeOK = false }
        }
        check(volumeOK, "track VOLUME: at every 1% the readout's dB is the gain the track plays")
    }

    /// A turn is heard within about 5 ms, and without a click.
    private static func checkKnobResponseTime() {
        let rate = 48_000.0
        let n = 9_600, at = 4_864          // a block boundary (128s), where a turn reaches the audio
        let sine = (0..<n).map { Float(sin(Double($0) * 2 * Double.pi * 1_000 / rate)) * 0.1 }
        // FX: BOOST from 0% to 100% on the main chain at `at`
        func bus(_ before: Float, _ after: Float) -> [Float] {
            let b = BusProcessor()
            b.prepare(sampleRate: rate)
            var l = sine, r = sine
            l.withUnsafeMutableBufferPointer { lb in r.withUnsafeMutableBufferPointer { rb in
                var i = 0
                while i < n {
                    var s = BusProcessor.Settings(); s.boost = i < at ? before : after
                    let m = min(128, n - i)
                    b.process(lb.baseAddress! + i, rb.baseAddress! + i, count: m, s)
                    i += m
                }
            } }
            return l
        }
        func master(_ before: Float, _ after: Float) -> [Float] {
            let m = MasterBus()
            m.prepare(sampleRate: rate)
            var l = sine, r = sine
            l.withUnsafeMutableBufferPointer { lb in r.withUnsafeMutableBufferPointer { rb in
                var i = 0
                while i < n {
                    var s = MasterBus.Settings(); s.clipperOn = false; s.output = i < at ? before : after
                    let c = min(128, n - i)
                    m.process(lb.baseAddress! + i, rb.baseAddress! + i, count: c, s)
                    i += c
                }
            } }
            return l
        }
        for (name, turned, low, high) in [("FX knob (BOOST)", bus(0, 1), bus(0, 0), bus(1, 1)),
                                          ("OUTPUT", master(0, 1), master(0, 0), master(1, 1))] {
            let full = (at..<n).map { abs(high[$0] - low[$0]) }.max() ?? 0
            // how far from the new setting it still is 5 ms after the turn
            let window = (at + 240)..<(at + 480)
            let left = window.map { abs(turned[$0] - high[$0]) }.max() ?? 1
            var step: Float = 0, natural: Float = 0
            for i in (at - 480)..<(at + 960) {
                step = max(step, abs(turned[i] - turned[i - 1]))
                natural = max(natural, abs(high[i] - high[i - 1]))
            }
            check(full > 0 && left <= full * 0.06, "\(name): 5 ms after a turn the sound is at the new setting (\(String(format: "%.1f", Double(left / max(full, 1e-9)) * 100))% left)")
            check(step <= natural * 1.15, "\(name): the turn is click-free (largest step \(step), the sine's own \(natural))")
        }
        check(KnockEngine.mixGlideSeconds <= 0.005 && BusProcessor.glideSeconds * 3 <= 0.005 && MasterBus.rampMs <= 5,
              "every knob's smoothing settles within 5 ms (FX \(BusProcessor.glideSeconds * 3_000) ms, master \(MasterBus.rampMs) ms, track volume/pan \(KnockEngine.mixGlideSeconds * 1_000) ms)")
    }
}
