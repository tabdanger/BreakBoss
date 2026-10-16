// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

/// The editor's note operations, kept out of the view so the self-test can check them.
enum PatternEdit {
    static let barTicks = PatternData.ppq * 4
    /// Longest pattern: 16 bars (the drum roll offers 4, 8 or 16).
    static let maxBars = 16

    /// Channel menu "Fill every …": replaces the channel's hits with one every `every` ticks
    /// across the whole pattern (FL's "fill each N steps"). The 808 holds until the next hit.
    static func fill(_ pattern: PatternData, pad: Int, every: Int32, velocity: Float) -> PatternData {
        guard every > 0 else { return pattern }
        var p = pattern
        p.events.removeAll { Int($0.pad) == pad }
        let bass = pad == Pad.bass808.rawValue
        var t: Int32 = 0
        while t < p.lengthTicks {
            p.events.append(GrooveEvent(tick: t, pad: Int8(pad), velocity: velocity, length: bass ? max(6, min(every, p.lengthTicks - t) - 2) : 0))
            t += every
        }
        p.sort()
        return p
    }

    /// Removes every hit of one channel.
    static func clearChannel(_ pattern: PatternData, pad: Int) -> PatternData {
        var p = pattern
        p.events.removeAll { Int($0.pad) == pad }
        return p
    }

    /// Adds a hit at `tick`, or removes the pad's hits already in that cell.
    static func toggle(_ pattern: PatternData, pad: Int, tick: Int32, cell: Int32) -> PatternData {
        var p = pattern
        let lo = tick - cell / 4, hi = tick + cell * 3 / 4
        let before = p.events.count
        p.events.removeAll { Int($0.pad) == pad && $0.tick >= lo && $0.tick < hi }
        if p.events.count == before {
            if pad == Pad.bass808.rawValue {
                p.events.append(GrooveEvent(tick: tick, pad: Int8(pad), velocity: 0.9, semis: 0,
                                            length: max(cell, PatternData.stepTicks * 2)))
            } else {
                p.events.append(GrooveEvent(tick: tick, pad: Int8(pad), velocity: pad == Pad.hat.rawValue ? 0.7 : 0.9))
            }
        }
        p.sort()
        return p
    }

    /// One 808 note held across `cells` cells, replacing the 808 hits under it.
    static func longBass(_ pattern: PatternData, from tick: Int32, cells: Int, cell: Int32) -> PatternData {
        var p = pattern
        let lo = tick - cell / 4, hi = tick + Int32(cells) * cell - cell / 4
        p.events.removeAll { Int($0.pad) == Pad.bass808.rawValue && $0.tick >= lo && $0.tick < hi }
        let length = min(Int32(cells) * cell, max(p.lengthTicks, cell) - tick)
        p.events.append(GrooveEvent(tick: tick, pad: Int8(Pad.bass808.rawValue), velocity: 0.9, semis: 0, length: length))
        p.sort()
        return p
    }

    /// Copies `bars` bars starting at `fromBar` into the bars right after (up to 16 bars long).
    static func copyNext(_ pattern: PatternData, fromBar: Int, bars: Int) -> PatternData {
        var p = pattern
        let span = Int32(bars) * barTicks
        let from = Int32(fromBar) * barTicks, to = from + span
        let needed = min(maxBars, fromBar + bars * 2)
        if needed > p.bars { p.lengthTicks = Int32(needed) * barTicks }
        let destEnd = min(to + span, p.lengthTicks)
        guard to < p.lengthTicks else { return pattern }
        p.events.removeAll { $0.tick >= to && $0.tick < destEnd }
        p.events += p.events.filter { $0.tick >= from && $0.tick < to }.compactMap { e in
            var c = e
            c.tick += span
            return c.tick < destEnd ? c : nil
        }
        p.sort()
        return p
    }

    /// Longer repeats what's there; shorter drops the hits past the new end.
    static func setLength(_ pattern: PatternData, bars: Int) -> PatternData {
        var p = pattern
        let oldLen = max(p.lengthTicks, barTicks), newLen = Int32(max(1, min(maxBars, bars))) * barTicks
        guard newLen != p.lengthTicks else { return pattern }
        if newLen > oldLen {
            let source = p.events
            var offset = oldLen
            while offset < newLen {
                p.events += source.compactMap { e in
                    var c = e
                    c.tick += offset
                    return c.tick < newLen ? c : nil
                }
                offset += oldLen
            }
        } else {
            p.events.removeAll { $0.tick >= newLen }
            for i in p.events.indices where p.events[i].length > 0 {
                p.events[i].length = min(p.events[i].length, newLen - p.events[i].tick)
            }
        }
        p.lengthTicks = newLen
        p.sort()
        return p
    }

    // MARK: Drum roll (FL Studio-style) operations

    /// Default length of a drawn 808 note when none is given (two 16ths).
    static let default808Length = PatternData.stepTicks * 2

    /// Adds a note, replacing one already on that pad at (almost) the same moment.
    static func addNote(_ pattern: PatternData, pad: Int, tick: Int32, length: Int32 = 0,
                        velocity: Float, semis: Float = 0) -> PatternData {
        var p = pattern
        guard (0..<Pad.count).contains(pad) else { return p }
        let t = max(0, min(tick, max(p.lengthTicks, 1) - 1))
        p.events.removeAll { Int($0.pad) == pad && abs($0.tick - t) <= 2 }
        let isBass = pad == Pad.bass808.rawValue
        let len = isBass ? min(max(length > 0 ? length : default808Length, 6), max(p.lengthTicks, 6) - t) : 0
        p.events.append(GrooveEvent(tick: t, pad: Int8(pad), velocity: velocity.clamped(0.05, 1),
                                    semis: semis.clamped(-12, 24), length: len))
        p.sort()
        return p
    }

    static func remove(_ pattern: PatternData, _ keys: Set<NoteKey>) -> PatternData {
        var p = pattern
        p.events.removeAll { keys.contains(NoteKey($0)) }
        return p
    }

    /// Moves notes in time (snapped by the caller), keeping each on its own channel and
    /// inside the pattern. Returns the pattern and the moved notes' new keys.
    static func move(_ pattern: PatternData, _ keys: Set<NoteKey>, by delta: Int32) -> (PatternData, Set<NoteKey>) {
        var p = pattern
        let len = max(p.lengthTicks, 1)
        let moving = p.events.filter { keys.contains(NoteKey($0)) }
        guard !moving.isEmpty else { return (p, keys) }
        // Keep the whole group inside the pattern.
        let lo = moving.map { $0.tick }.min()!, hi = moving.map { $0.tick + max($0.length, 1) }.max()!
        let d = min(max(delta, -lo), len - hi)
        p.events.removeAll { keys.contains(NoteKey($0)) }
        var newKeys = Set<NoteKey>()
        for var e in moving {
            e.tick += d
            p.events.removeAll { $0.pad == e.pad && $0.tick == e.tick }
            p.events.append(e)
            newKeys.insert(NoteKey(e))
        }
        p.sort()
        return (p, newKeys)
    }

    /// 808 note length (drums have no length).
    static func resize(_ pattern: PatternData, _ key: NoteKey, length: Int32) -> (PatternData, NoteKey) {
        var p = pattern
        guard let i = p.events.firstIndex(where: { NoteKey($0) == key }), Int(p.events[i].pad) == Pad.bass808.rawValue else { return (p, key) }
        p.events[i].length = min(max(length, 6), max(p.lengthTicks, 6) - p.events[i].tick)
        return (p, NoteKey(p.events[i]))
    }

    /// SELECT tool trim: every selected note (any channel) gets longer or shorter by `delta` ticks
    /// from where it was when the drag started. Drum notes without a length start from one step.
    static func trim(_ origin: PatternData, _ keys: Set<NoteKey>, by delta: Int32, minLength: Int32) -> (PatternData, Set<NoteKey>) {
        var p = origin
        var out = Set<NoteKey>()
        for i in p.events.indices where keys.contains(NoteKey(p.events[i])) {
            let e = p.events[i]
            let start = e.length > 0 ? e.length : PatternData.stepTicks
            let room = max(p.lengthTicks, 6) - e.tick
            p.events[i].length = min(max(start + delta, max(minLength, 6)), max(room, 6))
            out.insert(NoteKey(p.events[i]))
        }
        return (p, out)
    }

    static func setVelocity(_ pattern: PatternData, _ keys: Set<NoteKey>, _ velocity: Float) -> PatternData {
        var p = pattern
        for i in p.events.indices where keys.contains(NoteKey(p.events[i])) { p.events[i].velocity = velocity.clamped(0.05, 1) }
        return p
    }

    /// Lane dice: new velocities only (the notes, timing and pitch stay). Only `pad`'s notes when one
    /// is given, every note otherwise. Downbeats lean loud, off-beats and ghost spots lean softer.
    static func randomizeVelocity(_ pattern: PatternData, pad: Int?, keys: Set<NoteKey> = [], seed: UInt64) -> PatternData {
        var p = pattern
        var rng = SplitMix(seed)
        for i in p.events.indices {
            let e = p.events[i]
            if let pad, Int(e.pad) != pad { continue }
            if !keys.isEmpty && !keys.contains(NoteKey(e)) { continue }
            let onBeat = e.tick % PatternData.ppq == 0
            let lo: Float = onBeat ? 0.72 : 0.38, hi: Float = 1.0
            p.events[i].velocity = (lo + (hi - lo) * rng.unit()).clamped(0.05, 1)
        }
        return p
    }

    /// Pitch per note in semitones (drums: -12...+12, 808: -12...+24). Keys change with pitch.
    static func setPitch(_ pattern: PatternData, _ keys: Set<NoteKey>, _ semis: Float) -> (PatternData, Set<NoteKey>) {
        var p = pattern
        var newKeys = Set<NoteKey>()
        for i in p.events.indices where keys.contains(NoteKey(p.events[i])) {
            let isBass = Int(p.events[i].pad) == Pad.bass808.rawValue
            p.events[i].semis = semis.rounded().clamped(-12, isBass ? 24 : 12)
            newKeys.insert(NoteKey(p.events[i]))
        }
        p.sort()
        return (p, newKeys)
    }

    /// FL's Ctrl+B: copies the notes right after themselves (whole beats), adding bars up to 16.
    static func duplicate(_ pattern: PatternData, _ keys: Set<NoteKey>) -> (PatternData, Set<NoteKey>) {
        var p = pattern
        let picked = p.events.filter { keys.contains(NoteKey($0)) }
        guard !picked.isEmpty else { return (p, keys) }
        let beat = PatternData.ppq
        let lo = (picked.map { $0.tick }.min()! / beat) * beat
        let hiRaw = picked.map { $0.tick + max($0.length, 1) }.max()!
        let span = max(beat, ((hiRaw - lo + beat - 1) / beat) * beat)
        let needed = min(Int32(maxBars) * barTicks, ((lo + span * 2 + barTicks - 1) / barTicks) * barTicks)
        if needed > p.lengthTicks { p.lengthTicks = needed }
        var newKeys = Set<NoteKey>()
        for var e in picked {
            e.tick += span
            guard e.tick < p.lengthTicks else { continue }
            if e.length > 0 { e.length = min(e.length, p.lengthTicks - e.tick) }
            p.events.removeAll { $0.pad == e.pad && $0.tick == e.tick }
            p.events.append(e)
            newKeys.insert(NoteKey(e))
        }
        p.sort()
        return (p, newKeys)
    }

    /// Moves notes to the nearest grid line.
    static func quantize(_ pattern: PatternData, _ keys: Set<NoteKey>?, grid: Int32) -> PatternData {
        guard grid > 0 else { return pattern }
        var p = pattern
        let len = max(p.lengthTicks, 1)
        for i in p.events.indices where keys == nil || keys!.contains(NoteKey(p.events[i])) {
            var t = ((p.events[i].tick + grid / 2) / grid) * grid
            if t >= len { t = 0 }
            p.events[i].tick = t
        }
        var seen = Set<NoteKey>()
        p.events = p.events.filter { seen.insert(NoteKey(tick: $0.tick, pad: $0.pad, semis: 0)).inserted }
        p.sort()
        return p
    }

    /// A hit played while recording: snapped to `snap` (0 = where it was played).
    static func addRecorded(_ pattern: PatternData, pad: Int, tick: Int32, velocity: Float, semis: Float, snap: Int32) -> PatternData {
        let len = max(pattern.lengthTicks, 1)
        var t = tick
        if snap > 0 { t = ((tick + snap / 2) / snap) * snap }
        if t >= len { t -= len }
        return addNote(pattern, pad: pad, tick: max(0, t), length: 0, velocity: velocity, semis: semis)
    }
}

/// Identifies a note in a pattern (its time, channel and pitch).
struct NoteKey: Hashable {
    var tick: Int32
    var pad: Int8
    var semis: Float
    init(tick: Int32, pad: Int8, semis: Float) { self.tick = tick; self.pad = pad; self.semis = semis }
    init(_ e: GrooveEvent) { tick = e.tick; pad = e.pad; semis = e.semis }
}



/// Small seeded generator for the edit helpers.
struct SplitMix {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
}
