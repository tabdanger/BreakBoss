// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - PRESETS = patterns (Resources/PatternBank.json, made by tools/make_patterns.py)
//
// A preset loads a pattern only: its groove, tempo and swing. The kit (sounds), mode, knobs
// and pad settings stay as they are, so any pattern plays through any kit. The 12 loops are
// built from the preset's pattern (main, variations, fills, breakdown, tops, roll).
// Styles (rebuilt Oct 17 from the drum research, 10 presets each, written with accents, ghosts and
// fills): Neo Soul, Dilla Time, Boom Bap, 90s Rap, 70s Soul, 80s Breaks, Rock, Trap, Alt Trap, Drill,
// UK Drill, NY Drill, Detroit 2026, Bay Area 2026, RnB, 90s RnB and UK RnB. Then the BK Editions (Oct 20):
// Vol 1, grooves tools/learn_from_loops.py heard in Tyrone's own drum loops (4 or 8 bars, the loop's own tempo);
// Vol 2, his R&B loops, split from the full mix by tools/learn_fills.py; Vol 3, his Drum Loops pack (tops loops,
// split the same way, each with the kick of the Vol 1 groove nearest its tempo).

struct PatternPreset: Decodable, Equatable {
    let style: String
    let name: String
    let bpm: Double
    /// MPC-style swing percent (50 = straight).
    let swing: Double
    let glide: Bool
    let lanes: [String: String]
    /// The feel a drummer plays it with, by lane: each track's own swing (0...1 like the SWING
    /// knob), its push (-) or pull (+) in ticks, and how often its ghost notes play (0...1).
    var swingLanes: [String: Float]? = nil
    var shift: [String: Float]? = nil
    var ghostChance: [String: Float]? = nil

    static let laneToPad: [String: Pad] = ["k": .kick, "s": .snare, "c": .clap, "r": .rim, "h": .hat, "o": .openHat,
                                           "b": .bass808, "p1": .perc1, "p2": .perc2, "lt": .tomLow, "ht": .tomHigh, "cr": .cymbal]

    var steps: Int { lanes.values.first?.count ?? 16 }

    /// The groove family used for the fills, breakdown and roll-up built around the pattern.
    var grooveStyle: GrooveStyle {
        switch style {
        case "Neo Soul", "Dilla Time": return .neoSoul
        case "Boom Bap", "90s Rap": return .boomBap
        case "70s Soul": return .funkBreak
        case "80s Breaks", "Rock": return .heavyBreak
        case "Trap", "Alt Trap", "Detroit 2026": return .trapAtlanta
        case "Drill", "UK Drill", "NY Drill": return .trapMemphis
        case "Bay Area 2026": return .baySlap
        case "RnB": return .trapSoul
        case "90s RnB", "UK RnB": return .rnb
        case "BK Editions Vol 1", "BK Editions Vol 3": return bpm >= 120 ? .trapAtlanta : .boomBap
        case "BK Editions Vol 2": return .rnb
        default:
            if name.contains("AFRO") { return .afrobeats }
            if name.contains("BREAK") { return .funkBreak }
            return .boomBap
        }
    }

    /// The SWING (Bounce) value for this pattern's swing.
    var bounce: Float { Float(((swing - 50) / 22).clamped(0, 1)) }

    /// The pattern as notes. 16 steps per bar.
    var pattern: PatternData {
        var events: [GrooveEvent] = []
        let step = PatternData.stepTicks
        for (lane, text) in lanes {
            guard let pad = PatternPreset.laneToPad[lane] else { continue }
            let chars = Array(text)
            if pad == .bass808 {
                var i = 0
                while i < chars.count {
                    if let semis = PatternPreset.semitones(chars[i]) {
                        var len = 1
                        while i + len < chars.count && chars[i + len] == "-" { len += 1 }
                        let prev = events.last { Int($0.pad) == Pad.bass808.rawValue }
                        events.append(GrooveEvent(tick: Int32(i) * step, pad: Int8(pad.rawValue), velocity: 0.9, semis: semis,
                                                  length: Int32(len) * step - 2,
                                                  glide: glide && prev != nil && prev!.semis != semis && prev!.tick + prev!.length >= Int32(i) * step - 4))
                        i += len
                    } else {
                        i += 1
                    }
                }
                continue
            }
            for (i, c) in chars.enumerated() {
                let t = Int32(i) * step
                switch c {
                case "x": events.append(GrooveEvent(tick: t, pad: Int8(pad.rawValue), velocity: 0.82))
                case "X": events.append(GrooveEvent(tick: t, pad: Int8(pad.rawValue), velocity: 1))
                case "o": events.append(GrooveEvent(tick: t, pad: Int8(pad.rawValue), velocity: 0.62))
                case "g": events.append(GrooveEvent(tick: t, pad: Int8(pad.rawValue), velocity: 0.38))
                case "r":
                    for k in 0..<2 { events.append(GrooveEvent(tick: t + Int32(k) * step / 2, pad: Int8(pad.rawValue), velocity: k == 0 ? 0.8 : 0.62)) }
                case "q":
                    for k in 0..<4 { events.append(GrooveEvent(tick: t + Int32(k) * step / 4, pad: Int8(pad.rawValue), velocity: 0.5 + 0.1 * Float(k))) }
                case "t":
                    for k in 0..<3 { events.append(GrooveEvent(tick: t + Int32(k) * 16, pad: Int8(pad.rawValue), velocity: k == 0 ? 0.8 : 0.6)) }
                default: break
                }
            }
        }
        var p = PatternData(name: name, lengthTicks: Int32(max(16, steps)) * step, events: events)
        for (lane, v) in swingLanes ?? [:] { if let pad = PatternPreset.laneToPad[lane] { p.setSwing(pad: pad.rawValue, v) } }
        for (lane, v) in shift ?? [:] { if let pad = PatternPreset.laneToPad[lane] { p.setShift(pad: pad.rawValue, v) } }
        for (lane, v) in ghostChance ?? [:] {
            guard let pad = PatternPreset.laneToPad[lane] else { continue }
            for i in p.events.indices where Int(p.events[i].pad) == pad.rawValue && p.events[i].velocity < 0.5 { p.events[i].chance = v.clamped(0.05, 1) }
        }
        p.sort()
        return p
    }

    static func semitones(_ c: Character) -> Float? {
        if let d = c.wholeNumberValue, c.isASCII { return Float(d) }
        switch c {
        case "a": return 10
        case "b": return 11
        case "c": return 12
        default:
            let downs = Array("ABCDEFGHIJKL")
            if let i = downs.firstIndex(of: c) { return -Float(i + 1) }
            return nil
        }
    }

    /// PRESETS change the pattern only (and its tempo and swing). Kit, mode, knobs and pad
    /// sounds stay put. Inside a DAW with TEMPO SYNC on, the DAW's tempo stays in charge; the
    /// standalone app has no host, so the pattern's tempo always comes with it (Tyrone, Oct 17).
    func applying(to source: KnockState, hosted: Bool = true) -> KnockState {
        var s = source
        s.basePattern = pattern
        s.patternStyle = grooveStyle
        s.grooveSeed = PatternPreset.seed(name)
        s.editedLoops = Array(repeating: nil, count: Pad.count)
        if !hosted || (s.values[KParam.tempoSync.id] ?? KParam.tempoSync.defaultValue) < 0.5 { s.bpm = bpm }
        s.values[KParam.bounce.id] = bounce
        s.presetName = name
        return s.normalized()
    }

    static func seed(_ name: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for b in name.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
        return max(2, h)
    }
}

enum PatternBank {
    private struct File: Decodable { let version: Int; let patterns: [PatternPreset] }

    static let all: [PatternPreset] = {
        guard let url = knockResourceURL("PatternBank", "json"), let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.patterns
    }()

    /// Style names in browser order (the genre guide's order).
    static let styles: [String] = {
        var seen: [String] = []
        for p in all where !seen.contains(p.style) { seen.append(p.style) }
        return seen
    }()

    static func presets(in style: String) -> [PatternPreset] { all.filter { $0.style == style } }
    static func preset(named name: String) -> PatternPreset? { all.first { $0.name == name } }
}

// MARK: - Randomize (whole pattern, or one channel)
//
// Randomizing stays in the pattern's own style: each channel is taken from a different preset
// of the same style, then lightly varied (a few hits moved, ghosts added or dropped).

enum PatternRandomizer {
    static func style(for presetName: String) -> String {
        PatternBank.preset(named: presetName)?.style ?? PatternBank.styles.first ?? "Trap"
    }

    static func randomPattern(style: String, length: Int32, seed: UInt32) -> PatternData {
        var rng = KRandom(seed: seed)
        let pool = PatternBank.presets(in: style).map { $0.pattern }
        guard !pool.isEmpty else { return PatternData(name: "RANDOM", lengthTicks: length, events: []) }
        var events: [GrooveEvent] = []
        for pad in 0..<Pad.count {
            let src = pool[rng.int(pool.count)]
            events += mutate(tile(src.events.filter { Int($0.pad) == pad }, from: src.lengthTicks, to: length), pad: pad, length: length, rng: &rng)
        }
        var p = PatternData(name: "\(style.uppercased()) RANDOM", lengthTicks: length, events: events)
        p.sort()
        return p
    }

    /// New notes for one channel, the rest of the pattern untouched.
    static func randomChannel(_ pattern: PatternData, pad: Int, style: String, seed: UInt32) -> PatternData {
        var rng = KRandom(seed: seed)
        let pool = PatternBank.presets(in: style).map { $0.pattern }.filter { p in p.events.contains { Int($0.pad) == pad } }
        var p = pattern
        p.events.removeAll { Int($0.pad) == pad }
        if let src = pool.isEmpty ? nil : pool[rng.int(pool.count)] {
            p.events += mutate(tile(src.events.filter { Int($0.pad) == pad }, from: src.lengthTicks, to: p.lengthTicks),
                               pad: pad, length: p.lengthTicks, rng: &rng)
        } else {
            // No preset in this style uses the channel: a light, sparse part on the grid.
            let step = PatternData.stepTicks
            for s in 0..<Int(p.lengthTicks / step) where rng.chance(0.12) {
                p.events.append(GrooveEvent(tick: Int32(s) * step, pad: Int8(pad), velocity: rng.range(0.45, 0.85),
                                            length: pad == Pad.bass808.rawValue ? step * 2 : 0))
            }
        }
        p.sort()
        return p
    }

    static func tile(_ events: [GrooveEvent], from len: Int32, to target: Int32) -> [GrooveEvent] {
        guard len > 0 else { return [] }
        var out: [GrooveEvent] = []
        var offset: Int32 = 0
        while offset < target {
            for var e in events {
                e.tick += offset
                if e.tick < target {
                    if e.length > 0 { e.length = min(e.length, target - e.tick) }
                    out.append(e)
                }
            }
            offset += len
        }
        return out
    }

    private static func mutate(_ events: [GrooveEvent], pad: Int, length: Int32, rng: inout KRandom) -> [GrooveEvent] {
        let step = PatternData.stepTicks
        var out: [GrooveEvent] = []
        let anchor = pad == Pad.snare.rawValue || pad == Pad.clap.rawValue
        for var e in events {
            // Backbeats stay put; other hits sometimes move one step or drop out.
            if !anchor && e.tick % (PatternData.ppq * 4) != 0 {
                if rng.chance(0.08) { continue }
                if rng.chance(0.1) { e.tick = min(length - 1, max(0, e.tick + (rng.chance(0.5) ? step : -step))) }
            }
            e.velocity = (e.velocity * rng.range(0.9, 1.08)).clamped(0.05, 1)
            out.append(e)
        }
        if pad == Pad.snare.rawValue || pad == Pad.hat.rawValue || pad == Pad.perc1.rawValue {
            for s in 0..<Int(length / step) where rng.chance(0.04) {
                let t = Int32(s) * step
                if !out.contains(where: { $0.tick == t }) { out.append(GrooveEvent(tick: t, pad: Int8(pad), velocity: 0.35)) }
            }
        }
        var seen = Set<Int32>()
        return out.filter { seen.insert($0.tick).inserted }
    }
}
