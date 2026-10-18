// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - The channel sampler (Tyrone, Oct 18: FL Studio's Channel Sampler, one per track)
//
// Every track can open a SAMPLER window with two pages. SAMPLE edits the sound itself: declicking,
// the tools, SMP START / LENGTH / IN / OUT / CROSSFADE / TRIM and time stretching are computed once
// and the new sound is swapped in (like FL's precomputed effects, they act when you let go of a
// control). ENVELOPE shapes every hit while it plays: an envelope and an LFO for pan, volume,
// MOD X (the filter's cutoff), MOD Y (its resonance) and pitch, the filter, and the root note.
//
// Loaded samples play as one-shots: the whole sound, whatever the note's length, unless the
// Volume envelope is on (then the note's end starts its release) or the sample loops.

enum SamplerDeclick: Int, Codable, CaseIterable {
    case outOnly, transient, transientBleed, generic, smooth, crossfade, off

    var title: String {
        switch self {
        case .outOnly: return "Out only (no bleeding)"
        case .transient: return "Transient (no bleeding)"
        case .transientBleed: return "Transient (bleeding)"
        case .generic: return "Generic (bleeding)"
        case .smooth: return "Smooth (bleeding)"
        case .crossfade: return "Crossfade (bleeding)"
        case .off: return "No declicking (sharp)"
        }
    }

    /// Fade in, seconds: the transient modes ramp only the first few samples, keeping the attack.
    var fadeIn: Double {
        switch self {
        case .outOnly, .off: return 0
        case .transient, .transientBleed: return 0.0006
        case .generic: return 0.02
        case .smooth: return 0.1
        case .crossfade: return 0.2
        }
    }

    /// Fade out, seconds (cosine S-shaped; Transient's no-bleeding fade also closes a low-pass).
    var fadeOut: Double {
        switch self {
        case .outOnly, .transient: return 0.01
        case .transientBleed, .generic: return 0.02
        case .smooth: return 0.1
        case .crossfade: return 0.2
        case .off: return 0
        }
    }

    /// Bleeding: the fades use the audio just outside the cut, so everything inside it plays whole.
    var bleeds: Bool { self == .transientBleed || self == .generic || self == .smooth || self == .crossfade }
}

/// Mode (stretch method): Resample changes pitch with speed, like tape; Stretch keeps pitch while
/// the length changes (and keeps the length while PITCH changes); Stretch pro uses longer grains for
/// smoother tonal sounds.
enum SamplerStretch: Int, Codable, CaseIterable {
    case resample, stretch, stretchPro
    var title: String { ["Resample", "Stretch", "Stretch pro"][rawValue] }
}

/// TIME: how long the sample lasts from start to end.
enum SamplerTime: Codable, Equatable, Hashable {
    case none
    case seconds(Double)
    case autodetect
    /// Locked to the project's tempo: the tempo it was locked at.
    case projectTempo(Double)
    case beats(Double)

    var title: String {
        switch self {
        case .none: return "(none)"
        case .seconds(let s): return s < 1 ? "\(Int((s * 1000).rounded())) ms" : String(format: "%.2f s", s)
        case .autodetect: return "Autodetect"
        case .projectTempo: return "Project tempo"
        case .beats(let b): return b >= 4 && Int(b) % 4 == 0 ? "\(Int(b) / 4) bar\(b == 4 ? "" : "s")" : (b == 1 ? "1 beat" : "\(Int(b)) beats")
        }
    }

    /// Changes with the project's tempo.
    var followsTempo: Bool {
        switch self {
        case .none, .seconds: return false
        default: return true
        }
    }

    /// How much longer the sample becomes (1 = as it is).
    func factor(sourceSeconds: Double, bpm: Double) -> Double {
        let secs = max(sourceSeconds, 0.001), tempo = max(bpm, 1)
        switch self {
        case .none: return 1
        case .seconds(let d): return max(0.01, d) / secs
        case .beats(let b): return max(0.25, b) * 60 / tempo / secs
        case .projectTempo(let locked): return max(locked, 1) / tempo
        case .autodetect:
            // the sample's tempo: the whole number of beats (1…64) that puts it nearest 120 BPM
            var best = 0.0, distance = Double.infinity
            var beats = 1.0
            while beats <= 64 {
                let t = beats * 60 / secs
                if t >= 70 && t <= 180 && abs(t - 120) < distance { distance = abs(t - 120); best = t }
                beats *= 2
            }
            return distance.isFinite ? best / tempo : 1
        }
    }
}

/// What an envelope or LFO moves (the ENVELOPE page's tabs).
enum SamplerTarget: Int, CaseIterable {
    case pan, volume, modX, modY, pitch
    var title: String { ["Panning", "Volume", "Mod X", "Mod Y", "Pitch"][rawValue] }
}

enum SamplerFilterType: Int, Codable, CaseIterable {
    case fastLP, lp, bp, hp, bs, lp2
    var title: String { ["Fast LP", "LP", "BP", "HP", "BS", "LPx2"][rawValue] }
}

/// DELAY, ATT, HOLD, DEC, SUS, REL and the three TENSIONs. Knob values 0…1.
struct SamplerEnvelope: Codable, Equatable, Hashable {
    var on = false
    var delay: Float = 0
    var attack: Float = 0.12
    var hold: Float = 0.18
    var decay: Float = 0.45
    var sustain: Float = 0.5
    var release: Float = 0.3
    /// −1…1: negative bends the curve so it moves fast first, positive slow first.
    var attackTension: Float = 0
    var decayTension: Float = 0
    var releaseTension: Float = 0
    /// −1…1, how far it moves its target (the volume envelope is the volume itself).
    var amount: Float = 0.5
    /// Times in beats instead of seconds.
    var tempo = false

    /// A time knob in seconds (or beats with Tempo): cubic, so short times are easy to set.
    static func units(_ v: Float, tempo: Bool) -> Double {
        let x = Double(v.clamped(0, 1))
        return x * x * x * (tempo ? 16 : 8)
    }
}

/// The LFO: shape (sine, triangle, square), DELAY, ATT, AMT, SPEED, Tempo and Global.
struct SamplerLFO: Codable, Equatable, Hashable {
    var shape = 0
    var delay: Float = 0
    var attack: Float = 0
    /// −1…1 (0 = off).
    var amount: Float = 0
    var speed: Float = 0.5
    var tempo = false
    /// Every note shares one LFO (its phase runs on); otherwise each hit starts its own.
    var global = false

    static let divisions: [(String, Double)] = [("4 bars", 16), ("2 bars", 8), ("1 bar", 4), ("1/2", 2), ("1/4", 1), ("1/8", 0.5),
                                                 ("1/8T", 1.0 / 3), ("1/16", 0.25), ("1/16T", 1.0 / 6), ("1/32", 0.125)]
    var hertz: Double { 0.05 * pow(400, Double(speed.clamped(0, 1))) }
    var division: (String, Double) { Self.divisions[min(Self.divisions.count - 1, Int(speed.clamped(0, 1) * Float(Self.divisions.count)))] }
    var speedLabel: String { tempo ? division.0 : String(format: hertz < 1 ? "%.2f Hz" : "%.1f Hz", hertz) }
}

/// One track's sampler. Nil on a pad = never opened: its sound plays exactly as it always has.
struct SamplerSettings: Codable, Equatable {
    // the header: PITCH turns ± RANGE semitones
    var pitch: Float = 0
    var range = 2
    // Content
    var keepOnDisk = false
    var resample = false
    var loadRegions = false
    var loadSliceMarkers = false
    var declick: SamplerDeclick = .outOnly
    // Playback
    var startOffset: Float = 0
    var useLoop = false
    var pingPong = false
    // Time stretching: PITCH ±12 semitones, MUL ×¼…×4 (0.5 = ×1), TIME, Mode
    var stretchPitch: Float = 0
    var multiplier: Float = 0.5
    var time: SamplerTime = .none
    var stretch: SamplerStretch = .resample
    // Precomputed effects
    var removeDC = false
    var normalize = false
    var reverse = false
    var reversePolarity = false
    var fadeStereo = false
    var swapStereo = false
    var start: Float = 0
    var length: Float = 1
    var fadeIn: Float = 0
    var fadeOut: Float = 0
    var crossfade: Float = 0
    var trim: Float = 0
    // ENVELOPE page: one envelope and one LFO per target (SamplerTarget order)
    var envelopes: [SamplerEnvelope] = SamplerSettings.defaultEnvelopes
    var lfos: [SamplerLFO] = Array(repeating: SamplerLFO(), count: SamplerTarget.allCases.count)
    var cutoff: Float = 1
    var resonance: Float = 0
    var filterType: SamplerFilterType = .fastLP
    /// The note the sample plays at its own pitch (MIDI; 60 = C5, as FL names it).
    var rootNote = 60
    var mainPitch = true
    var addToKey = false
    /// Cents, −100…100.
    var fineTune: Float = 0

    static var defaultEnvelopes: [SamplerEnvelope] {
        var e = Array(repeating: SamplerEnvelope(), count: SamplerTarget.allCases.count)
        e[SamplerTarget.volume.rawValue].amount = 1
        return e
    }

    var mul: Double { pow(4, Double(multiplier.clamped(0, 1) - 0.5) * 2) }

    func envelope(_ t: SamplerTarget) -> SamplerEnvelope { envelopes.indices.contains(t.rawValue) ? envelopes[t.rawValue] : SamplerEnvelope() }
    func lfo(_ t: SamplerTarget) -> SamplerLFO { lfos.indices.contains(t.rawValue) ? lfos[t.rawValue] : SamplerLFO() }
    mutating func setEnvelope(_ t: SamplerTarget, _ change: (inout SamplerEnvelope) -> Void) {
        while envelopes.count < SamplerTarget.allCases.count { envelopes.append(SamplerEnvelope()) }
        change(&envelopes[t.rawValue])
    }
    mutating func setLFO(_ t: SamplerTarget, _ change: (inout SamplerLFO) -> Void) {
        while lfos.count < SamplerTarget.allCases.count { lfos.append(SamplerLFO()) }
        change(&lfos[t.rawValue])
    }

    /// Everything the SAMPLE page computes into the sound, and the tempo when TIME follows it.
    /// Nil when nothing does (the sound is used as it is).
    func offline(bpm: Double) -> SamplerOffline? {
        let o = SamplerOffline(resample: resample, declick: declick, removeDC: removeDC, normalize: normalize, reverse: reverse,
                               reversePolarity: reversePolarity, fadeStereo: fadeStereo, swapStereo: swapStereo,
                               start: start, length: length, fadeIn: fadeIn, fadeOut: fadeOut, crossfade: crossfade, trim: trim,
                               stretch: stretch, stretchPitch: stretch == .resample ? 0 : stretchPitch,
                               multiplier: stretch == .resample ? 0.5 : multiplier, time: stretch == .resample ? .none : time,
                               bpm: stretch != .resample && time.followsTempo ? bpm : 0)
        return o == SamplerOffline() ? nil : o
    }

    private enum CodingKeys: String, CodingKey {
        case pitch, range, keepOnDisk, resample, loadRegions, loadSliceMarkers, declick, startOffset, useLoop, pingPong
        case stretchPitch, multiplier, time, stretch, removeDC, normalize, reverse, reversePolarity, fadeStereo, swapStereo
        case start, length, fadeIn, fadeOut, crossfade, trim, envelopes, lfos, cutoff, resonance, filterType
        case rootNote, mainPitch, addToKey, fineTune
    }
}

extension SamplerSettings {
    /// Every field is optional in a saved project, so later versions can add controls.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        let d = SamplerSettings()
        pitch = v(.pitch, d.pitch); range = v(.range, d.range)
        keepOnDisk = v(.keepOnDisk, d.keepOnDisk); resample = v(.resample, d.resample)
        loadRegions = v(.loadRegions, d.loadRegions); loadSliceMarkers = v(.loadSliceMarkers, d.loadSliceMarkers)
        declick = v(.declick, d.declick); startOffset = v(.startOffset, d.startOffset)
        useLoop = v(.useLoop, d.useLoop); pingPong = v(.pingPong, d.pingPong)
        stretchPitch = v(.stretchPitch, d.stretchPitch); multiplier = v(.multiplier, d.multiplier)
        time = v(.time, d.time); stretch = v(.stretch, d.stretch)
        removeDC = v(.removeDC, d.removeDC); normalize = v(.normalize, d.normalize); reverse = v(.reverse, d.reverse)
        reversePolarity = v(.reversePolarity, d.reversePolarity); fadeStereo = v(.fadeStereo, d.fadeStereo); swapStereo = v(.swapStereo, d.swapStereo)
        start = v(.start, d.start); length = v(.length, d.length); fadeIn = v(.fadeIn, d.fadeIn); fadeOut = v(.fadeOut, d.fadeOut)
        crossfade = v(.crossfade, d.crossfade); trim = v(.trim, d.trim)
        envelopes = v(.envelopes, d.envelopes); lfos = v(.lfos, d.lfos)
        cutoff = v(.cutoff, d.cutoff); resonance = v(.resonance, d.resonance); filterType = v(.filterType, d.filterType)
        rootNote = v(.rootNote, d.rootNote); mainPitch = v(.mainPitch, d.mainPitch); addToKey = v(.addToKey, d.addToKey)
        fineTune = v(.fineTune, d.fineTune)
    }
}

/// The SAMPLE page's computed part (what the processed sound depends on).
struct SamplerOffline: Equatable {
    var resample = false
    var declick: SamplerDeclick = .outOnly
    var removeDC = false, normalize = false, reverse = false, reversePolarity = false, fadeStereo = false, swapStereo = false
    var start: Float = 0, length: Float = 1, fadeIn: Float = 0, fadeOut: Float = 0, crossfade: Float = 0, trim: Float = 0
    var stretch: SamplerStretch = .resample
    var stretchPitch: Float = 0
    var multiplier: Float = 0.5
    var time: SamplerTime = .none
    var bpm: Double = 0
}

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

        // SMP START and LENGTH, then TRIM the quiet end
        let total = max(1, l.count)
        let a = min(total - 1, Int(Double(o.start.clamped(0, 1)) * Double(total)))
        var b = min(total, a + max(1, Int((Double(o.length.clamped(0, 1)) * Double(total - a)).rounded())))
        let threshold: Float = o.trim <= 0.000_1 ? 0 : powf(10, (-90 + 70 * o.trim.clamped(0, 1)) / 20)
        while b > a + 1 && max(abs(l[b - 1]), abs(r[b - 1])) <= threshold { b -= 1 }

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

        // CROSSFADE: the end blends into the start, so the loop (from the end of the blend) is seamless
        var loopStart = 0
        let xLen = Int(Double(n / 2) * Double(o.crossfade.clamped(0, 1)))
        if xLen > 1 {
            for i in 0..<xLen {
                let t = Float(i + 1) / Float(xLen)
                let w = 0.5 - 0.5 * cosf(.pi * t)
                let j = n - xLen + i
                ol[j] = ol[j] * (1 - w) + ol[i] * w
                or[j] = or[j] * (1 - w) + or[i] * w
            }
            loopStart = xLen
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
                stretched = f
                remap { Int(Double($0) * f) }
            }
        }

        if o.normalize {
            var peak: Float = 0
            for i in ol.indices { peak = max(peak, abs(ol[i]), abs(or[i])) }
            if peak > 0.000_01 { let g = 0.98 / peak; for i in ol.indices { ol[i] *= g; or[i] *= g } }
        }
        if ol.isEmpty { ol = [0]; or = [0] }
        let out = SampleBuffer(left: ol, right: or, sampleRate: rate)
        out.bitDepth = raw.bitDepth
        out.stereo = raw.stereo || o.fadeStereo
        out.loopStart = min(max(0, loopStart), max(0, ol.count - 2))
        out.cues = marks.filter { $0 > 0 && $0 < ol.count }
        if region.count == 2, region[0] >= 0, region[1] < ol.count, region[1] - region[0] > 32 { out.region = region[0]...region[1] }
        if d.bleeds { out.fadeMarks = (Int(Double(fin) * stretched), ol.count - Int(Double(fout) * stretched)) }
        return out
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

// MARK: - Playing (audio thread: plain values, nothing allocates)

/// A track's sampler as the audio thread reads it (built when the kit is published).
struct SamplerRT {
    var active = false
    /// The header's PITCH × RANGE, the root note and the fine tune, in semitones.
    var semis: Float = 0
    var mainPitch = true
    var startOffset: Float = 0
    var loop = false
    var pingPong = false
    /// Load regions: the loop runs over the file's own loop region (WAV 'smpl') when it has one.
    var regions = false
    /// Resample mode's speed: TIME, MUL and PITCH change it as they would a tape.
    var tapeTime: SamplerTime = .none
    var tapeMul: Double = 1
    var tapePitch: Float = 0
    var pan = SamplerEnvelope(), volume = SamplerEnvelope(), modX = SamplerEnvelope(), modY = SamplerEnvelope(), pitch = SamplerEnvelope()
    var lfoPan = SamplerLFO(), lfoVolume = SamplerLFO(), lfoX = SamplerLFO(), lfoY = SamplerLFO(), lfoPitch = SamplerLFO()
    var cutoff: Float = 1
    var resonance: Float = 0
    var filterType = SamplerFilterType.fastLP

    init() {}

    init(_ s: SamplerSettings?) {
        guard let s else { return }
        active = true
        let bend = s.pitch.clamped(-1, 1) * Float(max(1, s.range))
        semis = (s.addToKey ? bend.rounded() : bend) + Float(60 - s.rootNote) + s.fineTune.clamped(-100, 100) / 100
        mainPitch = s.mainPitch
        startOffset = s.startOffset.clamped(0, 0.99)
        loop = s.useLoop
        pingPong = s.pingPong
        regions = s.loadRegions
        if s.stretch == .resample {
            tapeTime = s.time
            tapeMul = s.mul
            tapePitch = s.stretchPitch
        }
        pan = s.envelope(.pan); volume = s.envelope(.volume); modX = s.envelope(.modX); modY = s.envelope(.modY); pitch = s.envelope(.pitch)
        lfoPan = s.lfo(.pan); lfoVolume = s.lfo(.volume); lfoX = s.lfo(.modX); lfoY = s.lfo(.modY); lfoPitch = s.lfo(.pitch)
        cutoff = s.cutoff.clamped(0, 1)
        resonance = s.resonance.clamped(0, 1)
        filterType = s.filterType
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

    init() {}

    init(_ e: SamplerEnvelope, sampleRate: Double, samplesPerBeat: Double) {
        guard e.on else { return }
        let unit = e.tempo ? samplesPerBeat : sampleRate
        func len(_ v: Float) -> Int { Int(SamplerEnvelope.units(v, tempo: e.tempo) * unit) }
        stage = 0
        lenDelay = len(e.delay); lenAttack = len(e.attack); lenHold = len(e.hold); lenDecay = len(e.decay); lenRelease = len(e.release)
        sustain = e.sustain.clamped(0, 1)
        curveA = powf(4, e.attackTension.clamped(-1, 1))
        curveD = powf(4, e.decayTension.clamped(-1, 1))
        curveR = powf(4, e.releaseTension.clamped(-1, 1))
        amount = e.amount.clamped(-1, 1)
    }

    var on: Bool { stage != 7 }
    var done: Bool { stage == 6 }

    mutating func release() {
        guard stage < 5 else { return }
        from = value; stage = 5; pos = 0
        if lenRelease == 0 { stage = 6; value = 0 }
    }

    /// Moves `n` samples on and returns the level (0…1).
    @inline(__always)
    mutating func advance(_ n: Int) -> Float {
        guard stage < 6 else { return stage == 6 ? 0 : 1 }
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
    var panL: Float = 1, panR: Float = 1
    var rateMul: Double = 1
    var done = false
    // the filter: one-pole coefficient, or the SVF's (two stages for LPx2)
    var c1: Float = 1, a1: Float = 0, a2: Float = 0, a3: Float = 0, k: Float = 2
    var s1L: Float = 0, s2L: Float = 0, s1R: Float = 0, s2R: Float = 0
    var t1L: Float = 0, t2L: Float = 0, t1R: Float = 0, t2R: Float = 0
    var sampleRate: Float = 48_000
    // looping
    var looping = false
    var pingPong = false
    var direction: Double = 1
    var loopStart: Double = 0, loopEnd: Double = 0

    init() {}

    init(_ rt: SamplerRT, sampleRate rate: Double, samplesPerBeat: Double, clock: Int64) {
        on = true
        sampleRate = Float(rate)
        env = (SamplerEnvRun(rt.pan, sampleRate: rate, samplesPerBeat: samplesPerBeat),
               SamplerEnvRun(rt.volume, sampleRate: rate, samplesPerBeat: samplesPerBeat),
               SamplerEnvRun(rt.modX, sampleRate: rate, samplesPerBeat: samplesPerBeat),
               SamplerEnvRun(rt.modY, sampleRate: rate, samplesPerBeat: samplesPerBeat),
               SamplerEnvRun(rt.pitch, sampleRate: rate, samplesPerBeat: samplesPerBeat))
        lfo = (SamplerLfoRun(rt.lfoPan, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock),
               SamplerLfoRun(rt.lfoVolume, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock),
               SamplerLfoRun(rt.lfoX, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock),
               SamplerLfoRun(rt.lfoY, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock),
               SamplerLfoRun(rt.lfoPitch, sampleRate: rate, samplesPerBeat: samplesPerBeat, clock: clock))
        cutoff = rt.cutoff
        resonance = rt.resonance
        filterType = rt.filterType
        filterOn = filterType != .fastLP || cutoff < 0.999 || env.2.on || env.3.on || lfo.2.on || lfo.3.on
        gain = env.1.on ? 0 : 1
        control(0)
        gain = env.1.on ? env.1.value : gain
    }

    /// The note ended: every envelope lets go.
    mutating func release() {
        env.0.release(); env.1.release(); env.2.release(); env.3.release(); env.4.release()
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
            g *= (1 - 0.5 * a) + 0.5 * lfo.1.advance(n, age: age) * (lfo.1.amount < 0 ? -1 : 1)
        }
        gain = max(0, g)

        var p: Float = 0
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
        var x = cutoff, y = resonance
        if env.2.on { x += env.2.advance(n) * env.2.amount }
        if lfo.2.on { x += lfo.2.advance(n, age: age) }
        if env.3.on { y += env.3.advance(n) * env.3.amount }
        if lfo.3.on { y += lfo.3.advance(n, age: age) }
        x = x.clamped(0, 1); y = y.clamped(0, 1)
        let hz = min(20 * powf(1000, x), sampleRate * 0.45)
        if filterType == .fastLP {
            c1 = x >= 0.999 ? 1 : 1 - expf(-2 * .pi * hz / sampleRate)
        } else {
            let gg = tanf(.pi * hz / sampleRate)
            k = 2 - 1.96 * y
            a1 = 1 / (1 + gg * (gg + k)); a2 = gg * a1; a3 = gg * a2
        }
    }

    /// The filter on one stereo sample.
    @inline(__always)
    mutating func filter(_ l: inout Float, _ r: inout Float) {
        guard filterOn else { return }
        if filterType == .fastLP {
            guard c1 < 1 else { return }
            s1L += c1 * (l - s1L); s1R += c1 * (r - s1R)
            l = s1L; r = s1R
            return
        }
        let type = filterType, b1 = a1, b2 = a2, b3 = a3, kk = k
        l = Self.svf(l, &s1L, &s2L, type, b1, b2, b3, kk)
        r = Self.svf(r, &s1R, &s2R, type, b1, b2, b3, kk)
        if type == .lp2 {
            l = Self.svf(l, &t1L, &t2L, .lp, b1, b2, b3, kk)
            r = Self.svf(r, &t1R, &t2R, .lp, b1, b2, b3, kk)
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
