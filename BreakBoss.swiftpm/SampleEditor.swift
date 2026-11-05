// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Editing the waveform (Tyrone, Oct 18: red selection handles, cut / copy / paste, delete,
// trim silence, fades)
//
// Edits work on the sound the track plays now and are saved as a new WAV in Samples/Edits, which
// the track then loads (the old file stays, so the window's UNDO can go back to it).

enum SampleEdit {
    case delete(Range<Int>)
    /// Puts `clip` in at `at` (insert) or over `over` (replace).
    case insert(SampleClip, at: Int)
    case replace(SampleClip, over: Range<Int>)
    /// Mixes `clip` into the sound from `at` (Tyrone, Oct 20: paste merges with what's there); the
    /// sound gets longer if the clip runs past its end.
    case mix(SampleClip, at: Int)
    case trimSilence
    case fadeIn(Range<Int>)
    case fadeOut(Range<Int>)
}

/// Copied audio (any track can paste it).
struct SampleClip {
    var left: [Float]
    var right: [Float]
    var sampleRate: Double
    var count: Int { left.count }
}

enum SampleEditor {
    static func clip(_ s: SampleBuffer, _ range: Range<Int>) -> SampleClip {
        let r = range.clamped(to: 0..<s.length)
        return SampleClip(left: Array(UnsafeBufferPointer(start: s.left + r.lowerBound, count: r.count)),
                          right: Array(UnsafeBufferPointer(start: s.right + r.lowerBound, count: r.count)), sampleRate: s.sampleRate)
    }

    /// The clip at `rate` (smooth cubic if it came from a sound at another rate).
    static func converted(_ c: SampleClip, to rate: Double) -> SampleClip {
        guard rate > 0, abs(c.sampleRate - rate) > 0.5 else { return c }
        let step = c.sampleRate / rate
        return SampleClip(left: SamplerProcessor.convert(c.left, step: step), right: SamplerProcessor.convert(c.right, step: step), sampleRate: rate)
    }

    /// The edited audio, and where a point of the old sound (0…1) lands in the new one (nil = cut out).
    static func apply(_ edit: SampleEdit, to s: SampleBuffer) -> (left: [Float], right: [Float], map: (Float) -> Float?) {
        var l = Array(UnsafeBufferPointer(start: s.left, count: s.length))
        var r = Array(UnsafeBufferPointer(start: s.right, count: s.length))
        let n = max(1, l.count)
        func clampRange(_ x: Range<Int>) -> Range<Int> { x.clamped(to: 0..<l.count) }
        /// A part of the old sound to the new: `cut` frames removed at `at`, `added` put in there.
        func mapper(at: Int, cut: Int, added: Int) -> (Float) -> Float? {
            let newCount = Float(max(1, n - cut + added))
            return { f in
                let i = Int((f * Float(n)).rounded())
                if i < at { return Float(i) / newCount }
                if i < at + cut { return cut > 0 && i > at ? nil : Float(at) / newCount }
                return (Float(i - cut + added) / newCount).clamped(0, 1)
            }
        }
        switch edit {
        case .delete(let range):
            let x = clampRange(range)
            guard !x.isEmpty, x.count < l.count else { return (l, r, { $0 }) }
            l.removeSubrange(x); r.removeSubrange(x)
            return (l, r, mapper(at: x.lowerBound, cut: x.count, added: 0))
        case .insert(let c, let at):
            let c = converted(c, to: s.sampleRate)
            let p = min(max(0, at), l.count)
            l.insert(contentsOf: c.left, at: p); r.insert(contentsOf: c.right, at: p)
            return (l, r, mapper(at: p, cut: 0, added: c.count))
        case .replace(let c, let over):
            let c = converted(c, to: s.sampleRate)
            let x = clampRange(over)
            l.replaceSubrange(x, with: c.left); r.replaceSubrange(x, with: c.right)
            return (l, r, mapper(at: x.lowerBound, cut: x.count, added: c.count))
        case .mix(let c, let at):
            let c = converted(c, to: s.sampleRate)
            let p = min(max(0, at), l.count)
            let extra = max(0, p + c.count - l.count)
            if extra > 0 { l += [Float](repeating: 0, count: extra); r += [Float](repeating: 0, count: extra) }
            for k in 0..<c.count { l[p + k] += c.left[k]; r[p + k] += c.right[k] }
            // nothing moves: a point of the old sound stays where it was (in a longer sound if it grew)
            let grown = Float(l.count) / Float(n)
            return (l, r, { f in f / grown })
        case .trimSilence:
            // quieter than 60 dB under the peak, at either end (a hair is kept before the first sound)
            var peak: Float = 0
            for i in l.indices { peak = max(peak, abs(l[i]), abs(r[i])) }
            let floor = max(peak * 0.001, 0.000_01)
            guard let first = l.indices.first(where: { abs(l[$0]) > floor || abs(r[$0]) > floor }),
                  let last = l.indices.last(where: { abs(l[$0]) > floor || abs(r[$0]) > floor }) else { return (l, r, { $0 }) }
            let a = max(0, first - Int(s.sampleRate * 0.002))
            let b = min(l.count, last + 1)
            guard a > 0 || b < l.count else { return (l, r, { $0 }) }
            let kept = b - a
            return (Array(l[a..<b]), Array(r[a..<b]), { f in
                let i = Int((f * Float(n)).rounded())
                return i < a || i > b ? nil : Float(i - a) / Float(max(1, kept))
            })
        case .fadeIn(let range), .fadeOut(let range):
            let x = clampRange(range)
            let rising: Bool
            if case .fadeIn = edit { rising = true } else { rising = false }
            let count = max(1, x.count)
            for (k, i) in x.enumerated() {
                let t = Float(k) / Float(count)
                let w = 0.5 - 0.5 * cosf(.pi * t)
                let g = rising ? w : 1 - w
                l[i] *= g; r[i] *= g
            }
            return (l, r, { $0 })
        }
    }
}
