// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Computing the sound (off the audio thread)

enum SamplerProcessor {
    /// The sample with the SAMPLE page applied. `engineRate` is what Resample converts to.
    static func process(_ raw: SampleBuffer, _ o: SamplerOffline, engineRate: Double) -> SampleBuffer {
        var l = Array(UnsafeBufferPointer(start: raw.left, count: raw.length))
        var r = Array(UnsafeBufferPointer(start: raw.right, count: raw.length))
        var rate = raw.sampleRate
        // the file's slice markers and loop region follow the sound through every step
        var marks = raw.cues
        var region = raw.region.map { [$0.lowerBound, $0.upperBound] } ?? []
        func remap(_ f: (Int) -> Int) { marks = marks.map(f); region = region.map(f) }
        // Resample: converted to the engine's rate once (smooth cubic), not on every hit
        if o.resample, engineRate > 0, abs(rate - engineRate) > 0.5 {
            let k = engineRate / rate
            remap { Int(Double($0) * k) }
            l = convert(l, step: rate / engineRate)
            r = convert(r, step: rate / engineRate)
            rate = engineRate
        }
        if o.removeDC { removeDC(&l); removeDC(&r) }
        if o.reversePolarity { for i in l.indices { l[i] = -l[i]; r[i] = -r[i] } }
        if o.swapStereo { swap(&l, &r) }
        if o.reverse {
            l.reverse(); r.reverse()
            let last = l.count - 1
            remap { last - $0 }
            region.reverse()
        }

        // SMP START and LENGTH, then TRIM the quiet end (and, turned up, the quiet start: the cut
        // lands a millisecond before the sound comes in, so its attack stays whole)
        let total = max(1, l.count)
        var a = min(total - 1, Int(Double(o.start.clamped(0, 1)) * Double(total)))
        var b = min(total, a + max(1, Int((Double(o.length.clamped(0, 1)) * Double(total - a)).rounded())))
        let threshold: Float = o.trim <= 0.000_1 ? 0 : powf(10, (-90 + 70 * o.trim.clamped(0, 1)) / 20)
        while b > a + 1 && max(abs(l[b - 1]), abs(r[b - 1])) <= threshold { b -= 1 }
        if o.trim > 0.000_1 {
            var first = a
            while first < b - 1 && max(abs(l[first]), abs(r[first])) <= threshold { first += 1 }
            a = max(a, first - Int(0.001 * rate))
        }

        // Declicking: bleeding fades use the audio just outside the cut
        let d = o.declick
        let wantIn = Int(d.fadeIn * rate), wantOut = Int(d.fadeOut * rate)
        let bleedIn = d.bleeds ? min(a, wantIn) : 0
        let bleedOut = d.bleeds ? min(total - b, wantOut) : 0
        var ol = Array(l[(a - bleedIn)..<(b + bleedOut)])
        var or = Array(r[(a - bleedIn)..<(b + bleedOut)])
        let n = ol.count
        remap { $0 - (a - bleedIn) }
        // (bleeding fades run over the audio outside the cut; at the file's own start or end there's no cut)
        let fin = d.bleeds ? bleedIn : min(n / 2, wantIn)
        let fout = d.bleeds ? bleedOut : min(n / 2, wantOut)
        if fin > 0 { fade(&ol, &or, from: 0, count: fin, rising: true) }
        if fout > 0 {
            if d == .transient { filterFade(&ol, &or, count: fout) } else { fade(&ol, &or, from: n - fout, count: fout, rising: false) }
        }

        // IN and OUT: quick fades (fully left = off)
        let inLen = Int(Double(n) * Double(o.fadeIn * o.fadeIn))
        if inLen > 1 { fade(&ol, &or, from: 0, count: min(inLen, n), rising: true) }
        let outLen = Int(Double(n) * Double(o.fadeOut * o.fadeOut))
        if outLen > 1 { fade(&ol, &or, from: n - min(outLen, n), count: min(outLen, n), rising: false) }

        // CROSSFADE: the loop's end blends into the audio leading up to its start, so the jump back is
        // seamless. With no audio before the loop start, the end blends into the start and the loop
        // runs from the end of the blend.
        var loopStart = 0, loopEnd = 0
        let ls = min(n - 1, max(0, Int(Double(o.loopStart.clamped(0, 1)) * Double(n))))
        let le = max(ls + 1, min(n, Int(Double(o.loopEnd.clamped(0, 1)) * Double(n))))
        let xLen = Int(Double((le - ls) / 2) * Double(o.crossfade.clamped(0, 1)))
        if xLen > 1 {
            let lead = ls >= xLen
            for i in 0..<xLen {
                let t = Float(i + 1) / Float(xLen)
                let w = 0.5 - 0.5 * cosf(.pi * t)
                let j = le - xLen + i
                let k = lead ? ls - xLen + i : ls + i
                ol[j] = ol[j] * (1 - w) + ol[k] * w
                or[j] = or[j] * (1 - w) + or[k] * w
            }
            loopStart = lead ? ls : ls + xLen
            loopEnd = le
        }

        // Fade stereo: the sound moves from the left channel to the right
        if o.fadeStereo && n > 1 {
            for i in 0..<n {
                let th = Float(i) / Float(n - 1) * .pi / 2
                ol[i] *= cosf(th); or[i] *= sinf(th)
            }
        }

        var stretched = 1.0
        // Time stretching (Stretch / Stretch pro): the length changes, the pitch doesn't (and PITCH keeps the length)
        if o.stretch != .resample {
            let f = o.time.factor(sourceSeconds: Double(n) / rate, bpm: o.bpm) * pow(4, Double(o.multiplier.clamped(0, 1) - 0.5) * 2)
            let p = pow(2, Double(o.stretchPitch) / 12)
            if abs(f - 1) > 0.001 || abs(p - 1) > 0.000_1 {
                let window = Int((o.stretch == .stretchPro ? 0.046 : 0.023) * rate)
                (ol, or) = stretch(ol, or, by: (f * p).clamped(0.1, 10), window: max(256, window))
                if abs(p - 1) > 0.000_1 { ol = convert(ol, step: p); or = convert(or, step: p) }
                loopStart = Int(Double(loopStart) * f)
                loopEnd = Int(Double(loopEnd) * f)
                stretched = f
                remap { Int(Double($0) * f) }
            }
        }

        var fadeMarks = (Int(Double(fin) * stretched), ol.count - Int(Double(fout) * stretched))

        // POGO: the start bends from high (or low) into the sound's own pitch
        if abs(o.pogo) > 0.001 && ol.count > 1 {
            let (pl, pr, map) = pogo(ol, or, amount: Double(o.pogo.clamped(-1, 1)), rate: rate)
            ol = pl; or = pr
            loopStart = map(loopStart); loopEnd = map(loopEnd)
            fadeMarks = (map(fadeMarks.0), map(fadeMarks.1))
            remap(map)
        }
        // EQ: a tilt around 800 Hz
        if abs(o.eq) > 0.001 { tilt(&ol, amount: o.eq, rate: rate); tilt(&or, amount: o.eq, rate: rate) }
        // RM MIX: ring modulation by a sine at RM FREQ
        if o.rmMix > 0.001 {
            let m = o.rmMix.clamped(0, 1)
            let step = 2 * Double.pi * SamplerSettings.ringHertz(o.rmFreq) / rate
            for i in ol.indices {
                let g = (1 - m) + m * Float(sin(step * Double(i)))
                ol[i] *= g; or[i] *= g
            }
        }
        // DELAY and REVERB: their echoes and tail are added after the sound's end
        if o.delayMix > 0.001 {
            let beats = SamplerSettings.step(o.delayTime).1
            let seconds = beats * 60 / max(o.bpm > 0 ? o.bpm : 120, 1)
            (ol, or) = echo(ol, or, mix: o.delayMix.clamped(0, 1), delay: max(1, Int(seconds * rate)), rate: rate)
        }
        if o.reverbMix > 0.001 { (ol, or) = reverb(ol, or, mix: o.reverbMix.clamped(0, 1), hall: o.reverbB, rate: rate) }

        if o.normalize {
            var peak: Float = 0
            for i in ol.indices { peak = max(peak, abs(ol[i]), abs(or[i])) }
            if peak > 0.000_01 { let g = 0.98 / peak; for i in ol.indices { ol[i] *= g; or[i] *= g } }
        }
        // BOOST: last, so it lifts a normalized sound too
        if o.boost > 0.001 {
            let g = powf(10, SamplerSettings.boostDB(o.boost) / 20)
            for i in ol.indices { ol[i] *= g; or[i] *= g }
        }
        if ol.isEmpty { ol = [0]; or = [0] }
        let out = SampleBuffer(left: ol, right: or, sampleRate: rate)
        out.bitDepth = raw.bitDepth
        out.stereo = raw.stereo || o.fadeStereo || o.delayMix > 0.001 || o.reverbMix > 0.001
        out.loopStart = min(max(0, loopStart), max(0, ol.count - 2))
        out.loopEnd = loopEnd > out.loopStart + 1 ? min(loopEnd, ol.count - 1) : 0
        out.cues = marks.filter { $0 > 0 && $0 < ol.count }
        if region.count == 2, region[0] >= 0, region[1] < ol.count, region[1] - region[0] > 32 { out.region = region[0]...region[1] }
        if d.bleeds { out.fadeMarks = fadeMarks }
        return out
    }

    /// POGO: reads the sound at a speed that starts `amount` × 2 octaves away from its own and glides
    /// back to it (most of the way within about a tenth of a second). Also returns where each point of
    /// the old sound lands in the new one.
    static func pogo(_ l: [Float], _ r: [Float], amount: Double, rate: Double) -> ([Float], [Float], (Int) -> Int) {
        let n = l.count
        let depth = amount * 24
        let tau = 0.08 * rate
        var positions: [Double] = []
        positions.reserveCapacity(n)
        var pos = 0.0, i = 0.0
        let cap = n * 4
        while pos < Double(n - 1) && positions.count < cap {
            positions.append(pos)
            pos += pow(2, depth * exp(-i / tau) / 12)
            i += 1
        }
        func at(_ x: [Float], _ p: Double) -> Float {
            let k = Int(p), t = Float(p - Double(k))
            func v(_ j: Int) -> Float { x[min(max(j, 0), n - 1)] }
            let y0 = v(k - 1), y1 = v(k), y2 = v(k + 1), y3 = v(k + 2)
            let c1 = 0.5 * (y2 - y0)
            let c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
            let c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
            return ((c3 * t + c2) * t + c1) * t + y1
        }
        let ol = positions.map { at(l, $0) }, or = positions.map { at(r, $0) }
        let map: (Int) -> Int = { j in
            // the first new sample that reads at or past old sample j
            var lo = 0, hi = positions.count
            while lo < hi { let mid = (lo + hi) / 2; if positions[mid] < Double(j) { lo = mid + 1 } else { hi = mid } }
            return lo
        }
        return (ol, or, map)
    }

    /// EQ: a one-pole split at 800 Hz, the highs turned up and the lows down by the same dB (or the
    /// other way round), ±6 dB at the ends.
    static func tilt(_ x: inout [Float], amount: Float, rate: Double) {
        let a = Float(1 - exp(-2 * Double.pi * 800 / rate))
        let g = powf(10, 6 * amount.clamped(-1, 1) / 20)
        var low: Float = 0
        for i in x.indices {
            low += a * (x[i] - low)
            x[i] = low / g + (x[i] - low) * g
        }
    }

    /// DELAY: ping-pong echoes, the first on the left, then the right, each half as loud (until they
    /// fade under −60 dB), mixed in at `mix`.
    static func echo(_ l: [Float], _ r: [Float], mix: Float, delay d: Int, rate: Double) -> ([Float], [Float]) {
        let feedback: Float = 0.5
        let repeats = 10
        let n = l.count
        let total = min(n + d * repeats, n + Int(8 * rate))
        var ol = l + [Float](repeating: 0, count: total - n), or = r + [Float](repeating: 0, count: total - n)
        var el = [Float](repeating: 0, count: total), er = el
        for i in d..<max(d, total) {
            let j = i - d
            let dry = j < n ? (l[j] + r[j]) * 0.5 : 0
            el[i] = dry + feedback * er[j]
            er[i] = feedback * el[j]
        }
        for i in 0..<total { ol[i] += mix * el[i]; or[i] += mix * er[i] }
        return (ol, or)
    }

    /// REVERB: four damped combs and two all-passes a side (Schroeder / Freeverb), A a tight room
    /// (0.8 s), B a hall (2.4 s, a little pre-delay), mixed in at `mix`; the tail is added to the end.
    static func reverb(_ l: [Float], _ r: [Float], mix: Float, hall: Bool, rate: Double) -> ([Float], [Float]) {
        let seconds = hall ? 2.4 : 0.8
        let damp: Float = hall ? 0.25 : 0.4
        let pre = hall ? Int(0.02 * rate) : 0
        let k = rate / 44_100
        let n = l.count
        let total = n + Int(seconds * rate) + pre
        func side(_ x: [Float], spread: Int) -> [Float] {
            let combs = [1116, 1188, 1277, 1356].map { max(1, Int(Double($0 + spread) * k)) }
            let passes = [556, 441].map { max(1, Int(Double($0 + spread) * k)) }
            var out = [Float](repeating: 0, count: total)
            for c in combs {
                let g = Float(pow(10, -3 * Double(c) / (seconds * rate)))
                var buf = [Float](repeating: 0, count: c)
                var store: Float = 0, at = 0
                for i in 0..<total {
                    let j = i - pre
                    let input = j >= 0 && j < n ? x[j] : 0
                    let y = buf[at]
                    store = y * (1 - damp) + store * damp
                    buf[at] = input + store * g
                    at += 1; if at == c { at = 0 }
                    out[i] += y * 0.08
                }
            }
            for p in passes {
                var buf = [Float](repeating: 0, count: p)
                var at = 0
                for i in 0..<total {
                    let b = buf[at]
                    let y = -out[i] + b
                    buf[at] = out[i] + b * 0.5
                    at += 1; if at == p { at = 0 }
                    out[i] = y
                }
            }
            return out
        }
        let wl = side(l, spread: 0), wr = side(r, spread: 23)
        var ol = l + [Float](repeating: 0, count: total - n), or = r + [Float](repeating: 0, count: total - n)
        for i in 0..<total { ol[i] += mix * wl[i]; or[i] += mix * wr[i] }
        return (ol, or)
    }

    private static func removeDC(_ x: inout [Float]) {
        guard !x.isEmpty else { return }
        var sum: Double = 0
        for v in x { sum += Double(v) }
        let mean = Float(sum / Double(x.count))
        for i in x.indices { x[i] -= mean }
    }

    /// Cosine S-shaped fade.
    private static func fade(_ l: inout [Float], _ r: inout [Float], from: Int, count: Int, rising: Bool) {
        guard count > 0 else { return }
        for i in 0..<count {
            let j = from + i
            guard j >= 0 && j < l.count else { continue }
            let t = Float(i) / Float(count)
            let w = 0.5 - 0.5 * cosf(.pi * t)
            let g = rising ? w : 1 - w
            l[j] *= g; r[j] *= g
        }
    }

    /// Transient's declick out: a fade with a low-pass closing over it, so the cut doesn't click.
    private static func filterFade(_ l: inout [Float], _ r: inout [Float], count: Int) {
        let from = l.count - count
        guard from >= 0, count > 0 else { return }
        var fl = l[from], fr = r[from]
        for i in 0..<count {
            let t = Float(i) / Float(count)
            let c = 1 - 0.95 * t
            fl += c * (l[from + i] - fl); fr += c * (r[from + i] - fr)
            let g = 0.5 + 0.5 * cosf(.pi * t)
            l[from + i] = fl * g; r[from + i] = fr * g
        }
    }

    /// Reads `x` every `step` samples with cubic (Hermite) interpolation: step > 1 = shorter and higher.
    static func convert(_ x: [Float], step: Double) -> [Float] {
        guard x.count > 1, step > 0, step.isFinite else { return x }
        let count = max(1, Int(Double(x.count) / step))
        var out = [Float](repeating: 0, count: count)
        func at(_ i: Int) -> Float { x[min(max(i, 0), x.count - 1)] }
        for i in 0..<count {
            let pos = Double(i) * step
            let k = Int(pos)
            let t = Float(pos - Double(k))
            let y0 = at(k - 1), y1 = at(k), y2 = at(k + 1), y3 = at(k + 2)
            let c1 = 0.5 * (y2 - y0)
            let c2 = y0 - 2.5 * y1 + 2 * y2 - 0.5 * y3
            let c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)
            out[i] = ((c3 * t + c2) * t + c1) * t + y1
        }
        return out
    }

    /// WSOLA time stretch: Hann grains overlapped half and half, each nudged (within a quarter grain)
    /// to where it lines up best with the one before, so transients and tones stay intact.
    static func stretch(_ l: [Float], _ r: [Float], by factor: Double, window w: Int) -> ([Float], [Float]) {
        let n = l.count
        guard n > w * 2, factor.isFinite, factor > 0 else {
            // too short to stretch: change its speed instead
            return (convert(l, step: 1 / factor), convert(r, step: 1 / factor))
        }
        let hop = w / 2
        let outCount = max(1, Int(Double(n) * factor))
        var ol = [Float](repeating: 0, count: outCount + w)
        var or = [Float](repeating: 0, count: outCount + w)
        var norm = [Float](repeating: 0, count: outCount + w)
        let window = (0..<w).map { 0.5 - 0.5 * cosf(2 * .pi * Float($0) / Float(w)) }
        let mid = (0..<n).map { (l[$0] + r[$0]) * 0.5 }
        let tolerance = w / 4
        let compare = hop
        var previous = 0
        var k = 0
        while k * hop < outCount {
            let nominal = Int(Double(k * hop) / factor)
            var pos = min(max(0, nominal), max(0, n - 1))
            if k > 0 {
                // the natural continuation of the last grain, and the best match for it near `nominal`
                let natural = previous + hop
                var best = -Float.infinity
                var d = -tolerance
                while d <= tolerance {
                    let cand = nominal + d
                    if cand >= 0 && cand + compare < n && natural + compare < n {
                        var c: Float = 0
                        var i = 0
                        while i < compare { c += mid[cand + i] * mid[natural + i]; i += 2 }
                        if c > best { best = c; pos = cand }
                    }
                    d += 2
                }
            }
            let o = k * hop
            for i in 0..<w where pos + i < n {
                ol[o + i] += l[pos + i] * window[i]
                or[o + i] += r[pos + i] * window[i]
                norm[o + i] += window[i]
            }
            previous = pos
            k += 1
        }
        for i in 0..<outCount where norm[i] > 0.05 { ol[i] /= norm[i]; or[i] /= norm[i] }
        return (Array(ol[0..<outCount]), Array(or[0..<outCount]))
    }
}
