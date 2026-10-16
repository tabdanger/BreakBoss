// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Grooves
//
// LOOP mode turns a kit into 12 ready-made grooves, generated here from what we know about how
// each style is programmed. Nothing is copied from records: these are rules, and the dice rolls
// new grooves from the same rules.
//
//   Trap        130-150, felt half time: snare/clap on beat 3, sparse kick locked to a sliding
//               808, 16th hats with rolls (1/32, triplets, 1/64) whose velocity swells, an open
//               hat on an off-beat cut by the next closed hat.
//   West Bounce modern West Coast (ratchet / Ty-style): claps and snaps on 2 and 4, bouncing
//               kick, short punchy 808 with octave jumps, 8th hats, shaker on PERC 1.
//   Bay Slap    Bay Area slap: hard snare on 2 and 4, busy syncopated kick, long sliding 808,
//               hats with triplet flips.
//   West 90s    90s G-funk / Quik-style: clap on 2 and 4, open hat mirroring kick and clap with
//               varied velocity, tambourine (PERC 1) doubling the clap but rushing, swung 16ths.
//   Neo Soul    Dilla-style feel: loose late kicks, early snares, quintuplet / septuplet hat
//               swing, ghost notes, rim clicks.
//   Gospel      groove with ghost notes, linear "chop" fills (R L L R L L R L around the kit)
//               every four bars into a crash.
//   Breaks      live-drummer breaks: Funky (busy 16ths, ghosted snare, open hat on the "and"),
//               Loose (hats following the kick), Heavy (slow, big, roomy).

enum GrooveStyle: String, Codable, CaseIterable {
    case trap, westBounce, baySlap, west90s, neoSoul, gospel, funkBreak, looseBreak, heavyBreak, pop, afrobeats, latin, experimental
    // Existing raw values remain valid in saved projects.
    case trapAtlanta, trapMemphis, trapToronto, trapSoul, boomBap, loFi, rnb, pop80s, pop90s, amapiano

    /// Pocket styles receive small bounded timing and velocity variation during preparation.
    var isLive: Bool { [.neoSoul, .gospel, .funkBreak, .looseBreak, .heavyBreak, .west90s, .boomBap, .loFi, .rnb].contains(self) }
    var isTrap: Bool { [.trap, .trapAtlanta, .trapMemphis, .trapToronto, .trapSoul].contains(self) }
}

/// One hit in a groove. Ticks are 96 per quarter note.
struct GrooveEvent: Codable, Equatable {
    var tick: Int32
    var pad: Int8
    var velocity: Float
    /// 808 note: semitones from the kit's tuning.
    var semis: Float = 0
    /// 808 note length in ticks (0 = let it ring).
    var length: Int32 = 0
    /// 808 slides into this note from the one still sounding.
    var glide: Bool = false
}

struct PatternData: Codable, Equatable {
    var name: String
    var lengthTicks: Int32
    var events: [GrooveEvent]
    /// Drum roll HUMANIZE, 0...1: small timing and velocity changes added when the pattern is
    /// handed to the engine. The notes you see and export stay exactly where you put them.
    var humanize: Float? = nil

    static let ppq: Int32 = 96
    static let stepTicks: Int32 = 24  // one 16th

    var bars: Int { Int(lengthTicks / (PatternData.ppq * 4)) }

    mutating func sort() {
        events.sort { $0.tick == $1.tick ? $0.pad < $1.pad : $0.tick < $1.tick }
    }
}

/// The engine's read-only copy of the 12 loops (made on the main thread, read on the audio
/// thread, never changed after).
final class PatternSet {
    final class Loop {
        let events: UnsafeMutableBufferPointer<GrooveEvent>
        let lengthTicks: Int
        init(_ data: PatternData) {
            var sorted = PatternSet.humanized(data)
            sorted.sort()
            // Keep every hit inside the loop (micro-timing can push one past an edge).
            let len = Int(max(sorted.lengthTicks, PatternData.ppq))
            for i in sorted.events.indices {
                var t = Int(sorted.events[i].tick) % len
                if t < 0 { t += len }
                sorted.events[i].tick = Int32(t)
            }
            sorted.sort()
            let buffer = UnsafeMutableBufferPointer<GrooveEvent>.allocate(capacity: max(sorted.events.count, 1))
            _ = buffer.initialize(from: sorted.events)
            events = buffer
            lengthTicks = len
            count = sorted.events.count
        }
        let count: Int
        deinit { events.deallocate() }
    }

    let loops: [Loop]
    let data: [PatternData]

    /// Same pattern, same result: the jitter comes from each note's own position.
    static func humanized(_ data: PatternData) -> PatternData {
        guard let amount = data.humanize, amount > 0.001 else { return data }
        var p = data
        for i in p.events.indices {
            var rng = KRandom(seed: UInt32(truncatingIfNeeded: Int(p.events[i].tick) &* 31 &+ Int(p.events[i].pad) &* 7919 &+ 17))
            let shift = Int32((rng.range(-1, 1) * amount * 6).rounded())
            p.events[i].tick = max(0, p.events[i].tick + shift)
            p.events[i].velocity = (p.events[i].velocity * (1 + rng.range(-1, 1) * amount * 0.18)).clamped(0.05, 1)
        }
        return p
    }

    init(_ data: [PatternData]) {
        self.data = data
        loops = data.map { Loop($0) }
    }
}

enum LoopSlot: Int, CaseIterable {
    case mainA = 0, mainB, mainC, mainD, fillA, fillB, intro, breakdown, no808, kick808, tops, roll

    var title: String {
        switch self {
        case .mainA: return "MAIN A"
        case .mainB: return "MAIN B"
        case .mainC: return "MAIN C"
        case .mainD: return "MAIN D"
        case .fillA: return "A + FILL"
        case .fillB: return "B + FILL"
        case .intro: return "INTRO"
        case .breakdown: return "BREAKDOWN"
        case .no808: return "NO 808"
        case .kick808: return "KICK + 808"
        case .tops: return "TOPS"
        case .roll: return "ROLL UP"
        }
    }
}

// MARK: - Generator

enum GrooveGenerator {
    static let step = Double(PatternData.stepTicks)

    /// Twelve loops, with two-, four- and eight-bar phrases. Generation runs outside render.
    /// Same seed, same grooves; no sampled recording or named song sequence is reproduced.
    static func loops(style: GrooveStyle, seed: UInt32) -> [PatternData] {
        let a = groove(style, seed: seed, flavour: .normal, bars: 2)
        let b = groove(style, seed: seed &+ 101, flavour: .normal, bars: 4)
        let c = groove(style, seed: seed &+ 202, flavour: .busy, bars: 8)
        let d = groove(style, seed: seed &+ 303, flavour: .sparse, bars: 4)
        var rng = KRandom(seed: seed &+ 909)
        var out: [PatternData] = []
        for slot in LoopSlot.allCases {
            var p: PatternData
            switch slot {
            case .mainA: p = a
            case .mainB: p = b
            case .mainC: p = c
            case .mainD: p = d
            case .fillA: p = withFill(a, style, &rng)
            case .fillB: p = withFill(b, style, &rng)
            case .intro: p = keep(b, [.hat, .openHat, .perc1, .perc2, .rim])
            case .breakdown: p = breakdown(b, style)
            case .no808: p = keep(a, Pad.allCases.filter { $0 != .bass808 })
            case .kick808: p = keep(a, [.kick, .bass808])
            case .tops: p = keep(b, [.hat, .openHat, .perc1, .perc2, .rim, .cymbal])
            case .roll: p = rollUp(style, &rng)
            }
            p.name = slot.title
            p = finish(p)
            out.append(p)
        }
        return out
    }

    /// The 12 loops built around a preset's own pattern: A is the pattern itself, B and C
    /// longer versions with a variation and a fill, D a sparse version, then fills,
    /// intro, breakdown, no 808, kick + 808, tops and a roll-up in the preset's style.
    static func loops(fromMain main: PatternData, style: GrooveStyle, seed: UInt32) -> [PatternData] {
        var rng = KRandom(seed: seed &+ 909)
        let bar = PatternData.ppq * 4
        func tiled(_ bars: Int) -> PatternData {
            var p = main
            p.lengthTicks = Int32(bars) * bar
            p.events = PatternRandomizer.tile(main.events, from: max(main.lengthTicks, bar), to: p.lengthTicks)
            return p
        }
        let a = main.lengthTicks < bar * 2 ? tiled(2) : main
        let b = withFill(tiled(max(4, a.bars)), style, &rng)
        var c = tiled(max(8, a.bars))
        c = withFill(c, style, &rng)
        var d = keep(a, [.kick, .snare, .clap, .hat, .bass808])
        d.events.removeAll { $0.velocity < 0.5 }
        var out: [PatternData] = []
        for slot in LoopSlot.allCases {
            var p: PatternData
            switch slot {
            case .mainA: p = a
            case .mainB: p = b
            case .mainC: p = c
            case .mainD: p = d
            case .fillA: p = withFill(a, style, &rng)
            case .fillB: p = withFill(tiled(4), style, &rng)
            case .intro: p = keep(a, [.hat, .openHat, .perc1, .perc2, .rim])
            case .breakdown: p = breakdown(a, style)
            case .no808: p = keep(a, Pad.allCases.filter { $0 != .bass808 })
            case .kick808: p = keep(a, [.kick, .bass808])
            case .tops: p = keep(a, [.hat, .openHat, .perc1, .perc2, .rim, .cymbal])
            case .roll: p = rollUp(style, &rng)
            }
            p.name = slot.title
            p = finishKeepingLength(p)
            out.append(p)
        }
        return out
    }

    /// finish() without its density budget, so authored patterns keep every hit.
    private static func finishKeepingLength(_ pattern: PatternData) -> PatternData {
        var p = pattern
        p.lengthTicks = max(p.lengthTicks, PatternData.ppq * 4)
        let end = p.lengthTicks
        p.events = p.events.compactMap { original in
            guard original.pad >= 0, Int(original.pad) < Pad.count, original.velocity.isFinite, original.semis.isFinite else { return nil }
            var e = original
            e.tick = min(max(e.tick, 0), end - 1)
            e.velocity = e.velocity.clamped(0.05, 1)
            if e.pad == Int8(Pad.bass808.rawValue) { e.length = min(max(e.length, 12), end - e.tick) } else { e.length = 0; e.glide = false }
            return e
        }
        p.sort()
        var seen = Set<NoteKey>()
        p.events = p.events.filter { seen.insert(NoteKey(tick: $0.tick, pad: $0.pad, semis: 0)).inserted }
        return p
    }

    enum Flavour { case normal, busy, sparse }

    static func groove(_ style: GrooveStyle, seed: UInt32, flavour: Flavour, bars: Int = 2) -> PatternData {
        var rng = KRandom(seed: seed)
        // A two-bar call/response is the motif. Longer phrases develop that motif instead of
        // independently randomising every bar or merely copying a two-bar loop four times.
        var b = Builder(bars: 2)
        switch style {
        case .trap: trap(&b, &rng, flavour)
        case .trapAtlanta, .trapMemphis, .trapToronto, .trapSoul: regionalTrap(style, &b, &rng, flavour)
        case .westBounce: westBounce(&b, &rng, flavour)
        case .baySlap: baySlap(&b, &rng, flavour)
        case .west90s: west90s(&b, &rng, flavour)
        case .neoSoul: neoSoul(&b, &rng, flavour)
        case .boomBap, .loFi: sampledPocket(style, &b, &rng, flavour)
        case .rnb: modernRNB(&b, &rng, flavour)
        case .pop80s, .pop90s: decadePop(style, &b, &rng, flavour)
        case .pop: decadePop(.pop90s, &b, &rng, flavour)
        case .amapiano: amapiano(&b, &rng, flavour)
        case .gospel: gospel(&b, &rng, flavour)
        case .funkBreak, .looseBreak, .heavyBreak: breakBeat(style, &b, &rng, flavour)
        case .afrobeats, .latin, .experimental: additionalGroove(style, &b, &rng, flavour)
        }
        if style.isLive { b.humanise(&rng, timing: style == .neoSoul ? 3 : 2, velocity: 0.07) }
        return finish(developPhrase(b.data, style: style, bars: bars, flavour: flavour, rng: &rng))
    }

    /// A hard generation budget limits density even when more styles are added. This is
    /// preparation work, never work done by the audio callback. Imported/edited MIDI is kept.
    static let maxGeneratedEventsPerBar = 64
    static let maxGeneratedEvents = maxGeneratedEventsPerBar * 8

    private static func finish(_ pattern: PatternData) -> PatternData {
        var p = pattern
        let end = max(p.lengthTicks, PatternData.ppq * 4)
        p.lengthTicks = end
        p.events = p.events.compactMap { original in
            guard original.pad >= 0, Int(original.pad) < Pad.count,
                  original.velocity.isFinite, original.semis.isFinite else { return nil }
            var e = original
            e.tick = min(max(e.tick, 0), end - 1)
            e.velocity = e.velocity.clamped(0.05, 1)
            e.semis = e.semis.clamped(-12, 24)
            if e.pad == Int8(Pad.bass808.rawValue) {
                e.length = min(max(e.length, 12), end - e.tick)
            } else {
                e.length = 0
                e.glide = false
            }
            return e
        }
        p.sort()
        var unique: [GrooveEvent] = []
        var counts = [Int](repeating: 0, count: max(1, p.bars))
        for e in p.events {
            if let last = unique.last, last.tick == e.tick && last.pad == e.pad {
                if e.velocity > last.velocity { unique[unique.count - 1] = e }
                continue
            }
            let bar = min(Int(e.tick / (PatternData.ppq * 4)), counts.count - 1)
            guard counts[bar] < maxGeneratedEventsPerBar, unique.count < maxGeneratedEvents else { continue }
            unique.append(e)
            counts[bar] += 1
        }
        // An open hat cannot survive a closed hat at the same tick in the choke group.
        let closed = Set(unique.filter { $0.pad == Int8(Pad.hat.rawValue) }.map { $0.tick })
        unique.removeAll { $0.pad == Int8(Pad.openHat.rawValue) && closed.contains($0.tick) }
        // Ordinary bass notes stop just before the next attack. A flagged slide needs the
        // previous voice to remain alive across the new pitch, so it retains a short overlap.
        let bass = unique.indices.filter { unique[$0].pad == Int8(Pad.bass808.rawValue) }
        for i in bass.indices where i + 1 < bass.count {
            let current = bass[i], next = bass[i + 1]
            let distance = unique[next].tick - unique[current].tick
            if unique[next].glide && distance <= PatternData.ppq && unique[current].length >= distance - 12 {
                unique[current].length = min(distance + 8, end - unique[current].tick)
            } else {
                unique[next].glide = false
                unique[current].length = min(unique[current].length, max(1, distance - 3))
            }
        }
        p.events = unique
        return p
    }

    private static func developPhrase(_ motif: PatternData, style: GrooveStyle, bars requestedBars: Int,
                                      flavour: Flavour, rng: inout KRandom) -> PatternData {
        let bars = requestedBars <= 2 ? 2 : requestedBars <= 4 ? 4 : 8
        var b = Builder(bars: bars)
        let motifTicks = Int(motif.lengthTicks)
        for part in 0..<(bars / 2) {
            let start = part * motifTicks
            for source in motif.events {
                var e = source
                e.tick += Int32(start)
                if part > 0 {
                    e.velocity = (e.velocity * (part % 2 == 0 ? 0.92 : 1.03)).clamped(0.05, 1)
                    // A phrase breathes at its midpoint; the backbeat and bass anchors remain.
                    if part == 2, e.tick < Int32(start + 96), let pad = Pad(rawValue: Int(e.pad)),
                       [Pad.hat, .perc1, .perc2].contains(pad) { continue }
                }
                b.events.append(e)
            }
            if part > 0 {
                let answer = Double(part * 32 + 29)
                b.hit(style == .amapiano ? Pad.perc2 : .rim, answer, flavour == .sparse ? 0.32 : 0.54,
                      offset: style.isLive ? 3 : 0)
                if flavour != .sparse {
                    b.hit(.perc2, answer + 2, 0.42)
                }
                // Bass answers vary only at phrase ends, preserving an intelligible motif.
                if let i = b.events.lastIndex(where: { $0.pad == Int8(Pad.bass808.rawValue) && Int($0.tick) >= start }) {
                    b.events[i].semis = (b.events[i].semis + (part % 2 == 0 ? 0 : 7)).clamped(-12, 24)
                    b.events[i].glide = false
                }
            }
        }
        if bars >= 4 && flavour != .sparse {
            let end = Double(b.stepsTotal)
            if style.isTrap || style == .baySlap {
                // One restrained turnaround rather than a roll repeated in every bar.
                roll(&b, start: end - 2, span: 2, rateTicks: flavour == .busy ? 12 : 16, from: 0.38, to: 0.78)
            } else if style == .amapiano {
                b.hit(.perc1, end - 1.5, 0.58)
                b.hit(.bass808, end - 1, 0.72, semis: 12, length: 18)
            } else {
                b.hit(.snare, end - 1, 0.28, offset: style.isLive ? 3 : 0)
            }
        }
        if bars == 8 && flavour == .busy {
            return withFill(b.data, style, &rng)
        }
        return b.data
    }

    // MARK: Contemporary regional pockets

    private static func regionalTrap(_ style: GrooveStyle, _ b: inout Builder,
                                     _ rng: inout KRandom, _ f: Flavour) {
        let restrained = style == .trapToronto || style == .trapSoul
        let memphis = style == .trapMemphis
        let templates: [[Int]] = restrained ? [[0, 10], [0, 7, 14], [0, 11]] :
            memphis ? [[0, 3, 10, 14], [0, 6, 10], [0, 3, 7, 13]] :
            [[0, 6, 10], [0, 3, 10, 14], [0, 7, 11], [0, 3, 6, 13]]
        let call = rng.pick(templates)
        var bass: [Double] = []
        for bar in 0..<b.bars {
            let o = bar * 16
            let backbeat: Pad = style == .trapSoul ? .rim : .snare
            b.hit(backbeat, Double(o + 8), style == .trapSoul ? 0.82 : 0.96)
            if style != .trapSoul { b.hit(.clap, Double(o + 8), restrained ? 0.58 : 0.72) }
            var hits = f == .sparse ? Array(call.prefix(2)) : call
            if bar % 2 == 1 && f != .sparse {
                hits = Array(Set(hits + [restrained ? 15 : rng.pick([13, 15])])).sorted()
            }
            if f == .busy && !restrained { hits = Array(Set(hits + [5])).sorted() }
            for s in hits {
                b.hit(.kick, Double(o + s), s == 0 ? 0.96 : 0.84)
            }
            // The bass supports the rhythm but does not double every kick in the airy kits.
            let anchors = restrained ? Array(hits.prefix(f == .busy ? 3 : 2)) : hits
            for s in anchors { bass.append(Double(o + s)) }
            if memphis && f != .sparse {
                for s in [3, 6, 13] { b.hit(.perc2, Double(o + s), s == 6 ? 0.62 : 0.44) }
            } else {
                let accents = bar % 2 == 0 ? [3, 11] : [5, 14]
                for s in accents where f != .sparse || s == accents[0] {
                    b.hit(.perc1, Double(o + s), restrained ? 0.36 : 0.57)
                }
            }
            if bar % 2 == 1 && f != .sparse { b.hit(.snare, Double(o + 15), 0.28) }
        }
        let notes: [Float] = restrained ? rng.pick([[0, 0, 7, 0], [0, 0, 3, 0]]) :
            rng.pick([[0, 0, 7, 0, 12], [0, 0, 3, 0, 7], [0, 5, 0, 7]])
        b.bassLine(bass, notes: notes, glideChance: memphis ? 0.08 : 0.3,
                   maxLength: memphis ? 60 : restrained ? 180 : 144, rng: &rng)
        let spacing = restrained || memphis || f == .sparse ? 2 : 1
        hats(&b, every: spacing, level: restrained ? 0.6 : 0.78)
        if restrained {
            // A missing hat makes room for the vocal; a quiet answer precedes the backbeat.
            b.remove(.hat, from: 6, to: 8)
            if f != .sparse { b.hit(.hat, 7.5, 0.3) }
        }
        let rolls = f == .busy ? 3 : f == .sparse || style == .trapSoul ? 0 : 1
        trapRolls(&b, &rng, count: rolls)
        openHats(&b, &rng, perBar: f == .sparse ? 0 : 1, spots: restrained ? [14] : [6, 14])
        if style == .trapSoul && f == .busy {
            for s in stride(from: 1, to: b.stepsTotal, by: 2) { b.hit(.perc1, Double(s), 0.28) }
        }
    }

    private static func sampledPocket(_ style: GrooveStyle, _ b: inout Builder,
                                      _ rng: inout KRandom, _ f: Flavour) {
        let dusty = style == .loFi
        let swing = dusty ? 7 : 5
        hats(&b, every: dusty || f == .sparse ? 2 : 1, level: dusty ? 0.58 : 0.72, swingTicks: swing)
        // With eighth-note hats, delay the offbeat lane itself instead of sprinkling jitter.
        if dusty {
            for i in b.events.indices where Int(b.events[i].tick) % 96 == 48 { b.events[i].tick += 8 }
        }
        let call = rng.pick([[0, 7, 10], [0, 3, 10], [0, 6, 11]])
        for bar in 0..<b.bars {
            let o = bar * 16
            let kickSteps = f == .sparse ? [0, 10] : bar % 2 == 0 ? call : Array(Set(call + [14])).sorted()
            for s in kickSteps { b.hit(.kick, Double(o + s), s == 0 ? 0.92 : 0.72, offset: dusty ? 5 : 2) }
            for s in [4, 12] { b.hit(.snare, Double(o + s), dusty ? 0.83 : 0.96, offset: dusty ? 4 : 2) }
            if f != .sparse {
                for s in bar % 2 == 0 ? [7, 15] : [2, 11, 15] {
                    b.hit(.snare, Double(o + s), rng.range(0.17, 0.3), offset: swing)
                }
                b.hit(.rim, Double(o + (bar % 2 == 0 ? 11 : 6)), 0.42, offset: 3)
            }
            b.hit(.bass808, Double(o), dusty ? 0.66 : 0.78, semis: bar % 2 == 0 ? 0 : 7, length: dusty ? 144 : 90)
            if f == .busy { b.hit(.bass808, Double(o + 10), 0.66, semis: 0, length: 72) }
        }
        if f == .busy { openHats(&b, &rng, perBar: 1, spots: [14]) }
    }

    private static func modernRNB(_ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        let call = rng.pick([[0, 6, 10], [0, 3, 10], [0, 7, 14]])
        var bass: [Double] = []
        for bar in 0..<b.bars {
            let o = bar * 16
            for s in [4, 12] {
                b.hit(.rim, Double(o + s), 0.83, offset: 2)
                b.hit(.clap, Double(o + s), 0.56, offset: 3)
                if bar % 2 == 1 && f != .sparse { b.hit(.snare, Double(o + s), 0.6, offset: 2) }
            }
            for s in f == .sparse ? Array(call.prefix(2)) : call {
                b.hit(.kick, Double(o + s), s == 0 ? 0.92 : 0.77, offset: s == 0 ? 0 : 2)
                bass.append(Double(o + s))
            }
            if f != .sparse {
                b.hit(.perc1, Double(o + (bar % 2 == 0 ? 7 : 15)), 0.4, offset: 3)
                b.hit(.hat, Double(o + 11), 0.3, offset: 4)
            }
            if f == .busy { b.hit(.perc2, Double(o + 3), 0.42); b.hit(.perc1, Double(o + 14), 0.36) }
        }
        hats(&b, every: 2, level: 0.62)
        let notes: [Float] = rng.pick([[0, 0, 7, 0, 3, 0], [0, 5, 0, 7, 0, 0]])
        b.bassLine(bass, notes: notes, glideChance: 0.08, maxLength: 84, rng: &rng)
        if f != .sparse { openHats(&b, &rng, perBar: 1, spots: [14]) }
    }

    private static func decadePop(_ style: GrooveStyle, _ b: inout Builder,
                                  _ rng: inout KRandom, _ f: Flavour) {
        let eighties = style == .pop80s
        let call = eighties ? rng.pick([[0, 6, 8], [0, 4, 8, 12]]) : rng.pick([[0, 3, 7, 10], [0, 6, 8, 14]])
        hats(&b, every: eighties || f == .sparse ? 2 : 1, level: 0.71, swingTicks: eighties ? 0 : 3)
        for bar in 0..<b.bars {
            let o = bar * 16
            for s in f == .sparse ? [0, 8] : call { b.hit(.kick, Double(o + s), 0.94) }
            for s in [4, 12] {
                b.hit(.snare, Double(o + s), 0.96)
                b.hit(.clap, Double(o + s), eighties ? 0.67 : 0.45, offset: eighties ? 0 : 2)
                if f != .sparse { b.hit(.perc1, Double(o + s), 0.46) }
            }
            b.hit(.bass808, Double(o), 0.79, semis: bar % 2 == 0 ? 0 : 7, length: 72)
            b.hit(.bass808, Double(o + 8), 0.73, semis: 0, length: 66)
            if f != .sparse {
                b.hit(.perc1, Double(o + 3), 0.42)
                b.hit(.perc2, Double(o + (bar % 2 == 0 ? 11 : 15)), 0.49)
            }
        }
        openHats(&b, &rng, perBar: f == .busy ? 2 : f == .sparse ? 0 : 1, spots: [6, 14])
    }

    private static func amapiano(_ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        let calls = [[0, 3, 6, 10, 14], [0, 2, 7, 10, 13]]
        let call = rng.pick(calls)
        for bar in 0..<b.bars {
            let o = bar * 16
            for s in [0, 4, 8, 12] { b.hit(.kick, Double(o + s), s == 0 ? 0.73 : 0.59) }
            for s in [4, 12] { b.hit(.rim, Double(o + s), 0.56) }
            for s in 0..<16 {
                b.hit(.perc1, Double(o + s), s % 4 == 0 ? 0.65 : s % 2 == 0 ? 0.48 : 0.3, offset: s % 2 == 1 ? 3 : 0)
            }
            let bass = f == .sparse ? [0, 7, 10] : bar % 2 == 0 ? call : Array(Set(call + [15])).sorted()
            let notes: [Float] = bar % 2 == 0 ? [0, 0, 12, 7, 0] : [0, 7, 0, 12, 7, 12]
            for (i, s) in bass.enumerated() {
                // The prepared 808-derived log voice is percussive: short gated pitches,
                // syncopated call/response, no long trap-style slides.
                b.hit(.bass808, Double(o + s), i % 2 == 0 ? 0.9 : 0.73,
                      semis: notes[i % notes.count], length: f == .sparse ? 30 : 24)
            }
            for s in [3, 6, 11, 14] where f != .sparse || s == 6 || s == 14 {
                b.hit(.perc2, Double(o + s), s == 6 ? 0.6 : 0.42, offset: s % 2 == 1 ? 2 : 0)
            }
            for s in [2, 10] { b.hit(.perc1, Double(o + s), 0.45) }
            if f == .busy { b.hit(.perc2, Double(o + 15), 0.55); b.hit(.clap, Double(o + 12), 0.45) }
        }
        hats(&b, every: 2, level: 0.43)
        if f == .busy { openHats(&b, &rng, perBar: 1, spots: [14]) }
    }

    private static func additionalGroove(_ style: GrooveStyle, _ b: inout Builder, _ rng: inout KRandom, _ flavour: Flavour) {
        for bar in 0..<b.bars {
            let base = bar * 16
            let kicks = style == .afrobeats ? [0, 6, 10] : style == .latin ? [0, 7, 10] : style == .experimental ? [0, 5, 13] : [0, 8]
            for step in kicks { b.hit(.kick, Double(base + step), 0.92) }
            for step in [4, 12] { b.hit(.snare, Double(base + step), 0.9) }
            for step in stride(from: 0, to: 16, by: 2) { b.hit(.hat, Double(base + step), step % 4 == 0 ? 0.7 : 0.5) }
            if style == .afrobeats || style == .latin {
                for step in [0, 3, 6, 10, 12] { b.hit(.perc1, Double(base + step), rng.range(0.6, 0.9)) }
                for step in [2, 5, 9, 14] { b.hit(.perc2, Double(base + step), rng.range(0.45, 0.75)) }
                for step in 0..<16 { b.hit(.perc1, Double(base + step), step % 2 == 0 ? 0.65 : 0.4) }
            }
            if style == .experimental {
                for step in [3, 11, 15] { b.hit(.perc2, Double(base + step), rng.range(0.4, 0.8)) }
            }
            if flavour == .busy { b.hit(.openHat, Double(base + 14), 0.65) }
            b.hit(.bass808, Double(base), 0.85, length: Int(PatternData.ppq * 2))
        }
    }

    // MARK: Builder

    struct Builder {
        let bars: Int
        var events: [GrooveEvent] = []
        var stepsTotal: Int { bars * 16 }

        init(bars: Int) { self.bars = bars }

        mutating func hit(_ pad: Pad, _ stepPos: Double, _ velocity: Float, offset: Int = 0,
                          semis: Float = 0, length: Int = 0, glide: Bool = false) {
            let tick = Int((stepPos * GrooveGenerator.step).rounded()) + offset
            events.append(GrooveEvent(tick: Int32(tick), pad: Int8(pad.rawValue), velocity: velocity.clamped(0.05, 1),
                                      semis: semis, length: Int32(length), glide: glide))
        }

        mutating func remove(_ pad: Pad, from: Double, to: Double) {
            let lo = Int32(from * GrooveGenerator.step), hi = Int32(to * GrooveGenerator.step)
            events.removeAll { $0.pad == Int8(pad.rawValue) && $0.tick >= lo && $0.tick < hi }
        }

        func has(_ pad: Pad, at stepPos: Int) -> Bool {
            let t = Int32(stepPos) * PatternData.stepTicks
            return events.contains { $0.pad == Int8(pad.rawValue) && abs($0.tick - t) < 6 }
        }

        mutating func humanise(_ rng: inout KRandom, timing: Int, velocity: Float) {
            for i in events.indices {
                events[i].tick += Int32(rng.int(timing * 2 + 1) - timing)
                events[i].velocity = (events[i].velocity * (1 + rng.bipolar() * velocity)).clamped(0.05, 1)
            }
        }

        /// Bass notes follow the sorted steps, with a short gap and an optional gate limit.
        mutating func bassLine(_ steps: [Double], notes: [Float], glideChance: Float, gap: Int = 6,
                               maxLength: Int? = nil, rng: inout KRandom) {
            let sorted = steps.sorted()
            for (i, s) in sorted.enumerated() {
                let next = i + 1 < sorted.count ? sorted[i + 1] : Double(stepsTotal)
                var len = Int((next - s) * GrooveGenerator.step) - gap
                if let m = maxLength { len = min(len, m) }
                let semis = notes[i % notes.count]
                let prev = i > 0 ? notes[(i - 1) % notes.count] : semis
                let glide = i > 0 && prev != semis && rng.chance(glideChance)
                hit(.bass808, s, 0.95, semis: semis, length: max(len, 12), glide: glide)
            }
        }

        var data: PatternData {
            PatternData(name: "", lengthTicks: Int32(bars) * PatternData.ppq * 4, events: events)
        }
    }

    // MARK: Hat helpers

    /// Steady hats with a loud-soft-medium-soft accent shape.
    static func hats(_ b: inout Builder, every: Int, level: Float, swingTicks: Int = 0, skip: Set<Int> = []) {
        let shape16: [Float] = [1, 0.55, 0.8, 0.55]
        var s = 0
        while s < b.stepsTotal {
            if !skip.contains(s) {
                let v = every == 1 ? shape16[s % 4] : (s % 4 == 0 ? 1 : 0.72)
                b.hit(.hat, Double(s), v * level, offset: s % 2 == 1 ? swingTicks : 0)
            }
            s += every
        }
    }

    /// A hat roll from `start` covering `span` steps at `rateTicks` per hit, velocity swelling
    /// up (or down).
    static func roll(_ b: inout Builder, pad: Pad = .hat, start: Double, span: Double, rateTicks: Double,
                     from: Float, to: Float) {
        guard start >= 0, start < Double(b.stepsTotal), rateTicks > 0 else { return }
        let duration = min(span, Double(b.stepsTotal) - start)
        guard duration > 0 else { return }
        b.remove(pad, from: start, to: start + duration)
        let count = min(64, max(1, Int(ceil(duration * step / rateTicks))))
        for k in 0..<count {
            let t = start * step + Double(k) * rateTicks
            let v = from + (to - from) * Float(k) / Float(max(count - 1, 1))
            b.events.append(GrooveEvent(tick: Int32(t.rounded()), pad: Int8(pad.rawValue), velocity: v))
        }
    }

    static func trapRolls(_ b: inout Builder, _ rng: inout KRandom, count: Int) {
        var spots = [6.0, 14.0, 11.0, 22.0, 30.0, 27.0, 15.0, 31.0].filter { $0 < Double(b.stepsTotal) }
        for _ in 0..<count {
            guard !spots.isEmpty else { break }
            let i = rng.int(spots.count)
            let s = spots.remove(at: i)
            let up = rng.chance(0.65)
            switch rng.int(5) {
            case 0: roll(&b, start: s, span: 2, rateTicks: 12, from: up ? 0.45 : 0.95, to: up ? 0.95 : 0.45)      // 1/32
            case 1: roll(&b, start: s, span: 2, rateTicks: 16, from: up ? 0.5 : 0.9, to: up ? 0.9 : 0.5)          // 1/16 triplets
            case 2: roll(&b, start: s, span: 1, rateTicks: 8, from: 0.55, to: 0.9)                                // 1/32 triplets
            case 3: roll(&b, start: s, span: 1, rateTicks: 6, from: 0.4, to: 0.85)                                // 1/64
            default: roll(&b, start: s - 1, span: 3, rateTicks: 16, from: 0.6, to: 0.95)                          // triplet bounce
            }
        }
    }

    /// Open hat on an off-beat; the next closed hat chokes it.
    static func openHats(_ b: inout Builder, _ rng: inout KRandom, perBar: Int, spots: [Int]) {
        for bar in 0..<b.bars {
            var choices = spots
            for _ in 0..<perBar {
                guard !choices.isEmpty else { break }
                let s = bar * 16 + choices.remove(at: rng.int(choices.count))
                b.remove(.hat, from: Double(s), to: Double(s) + 1)
                b.hit(.openHat, Double(s), 0.8)
                if !b.has(.hat, at: s + 1) && s + 1 < b.stepsTotal { b.hit(.hat, Double(s + 1), 0.6) }
            }
        }
    }

    // MARK: Styles

    static func trap(_ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        // Backbeat on beat 3 of each bar (half-time feel).
        for bar in 0..<b.bars {
            b.hit(.snare, Double(bar * 16 + 8), 0.95)
            b.hit(.clap, Double(bar * 16 + 8), 0.85)
        }
        if f != .sparse && rng.chance(0.4) { b.hit(.snare, Double(b.stepsTotal - 1), 0.4) }
        // Sparse kick; the 808 follows it.
        let templates: [[Int]] = [[0, 10], [0, 7, 10], [0, 3, 10, 14], [0, 6, 11], [0, 11, 14], [0, 3, 6, 10], [0, 10, 13]]
        var kicks: [Double] = []
        for bar in 0..<b.bars {
            var t = rng.pick(templates)
            if f == .sparse { t = Array(t.prefix(2)) }
            if f == .busy && rng.chance(0.6) { t.append(rng.pick([5, 13, 15])) }
            for s in Set(t) { kicks.append(Double(bar * 16 + s)) }
        }
        kicks.sort()
        for k in kicks { b.hit(.kick, k, 0.95) }
        let noteSets: [[Float]] = [[0, 0, 0, 7], [0, 0, 10, 7], [0, 12, 0, 10], [0, -2, 0, 3], [0, 0, 5, 7], [0, 7, 12, 10]]
        let trapNotes = rng.pick(noteSets)
        b.bassLine(kicks, notes: trapNotes, glideChance: f == .busy ? 0.55 : 0.35, rng: &rng)
        if rng.chance(0.4) { b.hit(.bass808, Double(b.stepsTotal - 2), 0.8, semis: 12, length: 30, glide: true) }
        // Hats
        let every = (f == .sparse || rng.chance(0.4)) ? 2 : 1
        hats(&b, every: every, level: 0.85)
        let rollCount = f == .busy ? 4 : f == .sparse ? 1 : 2 + rng.int(2)
        trapRolls(&b, &rng, count: rollCount)
        let trapOpen = rng.chance(0.6) ? 1 : 0
        openHats(&b, &rng, perBar: trapOpen, spots: [6, 14])
        // A recurring percussion tile gives the loop its own bounce; its second bar answers.
        let p: Pad = rng.chance(0.5) ? .rim : .perc1
        let accents = rng.pick([[3, 11], [5, 13], [7, 15]])
        for bar in 0..<b.bars {
            for (i, s) in accents.enumerated() where f != .sparse || i == 0 {
                b.hit(p, Double(bar * 16 + s), i == 0 ? 0.58 : 0.44)
            }
            if bar % 2 == 1 && f == .busy { b.hit(.perc2, Double(bar * 16 + 14), 0.52) }
        }
    }

    static func westBounce(_ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        for bar in 0..<b.bars {
            for s in [4, 12] {
                b.hit(.clap, Double(bar * 16 + s), 0.95)
                b.hit(.rim, Double(bar * 16 + s), 0.7)  // snap layered on the clap
            }
            if rng.chance(f == .busy ? 0.8 : 0.45) { b.hit(.clap, Double(bar * 16 + rng.pick([7, 15, 11])), 0.6) }
        }
        let templates: [[Int]] = [[0, 6, 10], [0, 3, 8, 10], [0, 7, 10, 13], [0, 2, 6, 10], [0, 6, 9, 14]]
        var kicks: [Double] = []
        for bar in 0..<b.bars {
            var t = rng.pick(templates)
            if f == .sparse { t = [0, t.count > 2 ? t[2] : 10] }
            for s in t { kicks.append(Double(bar * 16 + s)) }
        }
        for k in kicks { b.hit(.kick, k, 0.95) }
        // Short punchy 808 with octave jumps.
        let bounceNotes: [Float] = rng.pick([[0, 12, 0, 7], [0, 0, 12, 10], [0, 7, 12, 0], [0, 5, 7, 12]])
        b.bassLine(kicks, notes: bounceNotes, glideChance: 0.15, maxLength: 40, rng: &rng)
        hats(&b, every: 2, level: 0.8)
        if f != .sparse {
            for bar in 0..<b.bars where rng.chance(0.6) {
                let s = bar * 16 + rng.pick([3, 7, 11, 15])
                b.hit(.hat, Double(s), 0.5)
            }
            for s in 0..<b.stepsTotal where s % 2 == 1 && rng.chance(0.55) { b.hit(.perc1, Double(s), 0.45) }
        }
        openHats(&b, &rng, perBar: 1, spots: [14])
        if rng.chance(0.4) { for bar in 0..<b.bars { b.hit(.perc2, Double(bar * 16 + 12), 0.55) } }
    }

    static func baySlap(_ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        for bar in 0..<b.bars {
            b.hit(.snare, Double(bar * 16 + 4), 1)
            b.hit(.snare, Double(bar * 16 + 12), 1)
            if rng.chance(0.5) { b.hit(.clap, Double(bar * 16 + 12), 0.7) }
        }
        let templates: [[Int]] = [[0, 3, 7, 10, 11], [0, 6, 9, 14], [0, 3, 8, 11, 14], [0, 2, 7, 10, 13]]
        var kicks: [Double] = []
        for bar in 0..<b.bars {
            var t = rng.pick(templates)
            if f == .sparse { t = Array(t.prefix(3)) }
            for s in t { kicks.append(Double(bar * 16 + s)) }
        }
        for k in kicks { b.hit(.kick, k, 0.95) }
        let slapNotes: [Float] = rng.pick([[0, 0, 3, 5, 7], [0, -2, 0, 3], [0, 7, 5, 3, 0], [0, 0, 10, 12]])
        b.bassLine(kicks, notes: slapNotes, glideChance: 0.45, rng: &rng)
        hats(&b, every: 2, level: 0.8)
        // Triplet flips near the end of each bar.
        for bar in 0..<b.bars where rng.chance(f == .sparse ? 0.3 : 0.75) {
            let s = Double(bar * 16 + rng.pick([12, 14]))
            roll(&b, start: s, span: 2, rateTicks: 16, from: 0.6, to: 0.85)
        }
        if f == .busy { trapRolls(&b, &rng, count: 2) }
        for s in 0..<b.stepsTotal where rng.chance(0.12) { b.hit(.perc1, Double(s), 0.5) }
    }

    static func west90s(_ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        let templates: [[Int]] = [[0, 7, 10], [0, 3, 7, 10], [0, 8, 10, 15], [0, 6, 10, 11]]
        var kicks: [Int] = []
        for bar in 0..<b.bars {
            var t = rng.pick(templates)
            if f == .sparse { t = [0, 10] }
            for s in t { kicks.append(bar * 16 + s) }
        }
        var claps: [Int] = []
        for bar in 0..<b.bars { claps += [bar * 16 + 4, bar * 16 + 12] }
        for k in kicks { b.hit(.kick, Double(k), 0.95) }
        for c in claps {
            b.hit(.clap, Double(c), 0.95)
            b.hit(.snare, Double(c), 0.6)
            // Tambourine doubles the clap but rushes ahead.
            b.hit(.perc1, Double(c), 0.7, offset: -(5 + rng.int(4)))
        }
        // Open hat mirrors kick and clap, with one exception, at varied velocity.
        let mirror = (kicks + claps).sorted()
        let skip = mirror.isEmpty ? -1 : mirror[rng.int(mirror.count)]
        for s in mirror where s != skip { b.hit(.openHat, Double(s), rng.range(0.45, 0.85)) }
        // Light swung 16th closed hats between them.
        for s in 0..<b.stepsTotal where !mirror.contains(s) && (f != .sparse || s % 2 == 0) {
            b.hit(.hat, Double(s), s % 2 == 0 ? 0.55 : 0.35, offset: s % 2 == 1 ? 6 : 0)
        }
        let funkNotes: [Float] = rng.pick([[0, 0, 5, 7], [0, 3, 5, 0], [0, 7, 5, 3]])
        b.bassLine(kicks.map { Double($0) }, notes: funkNotes, glideChance: 0.1, maxLength: 60, rng: &rng)
        if f == .busy { for bar in 0..<b.bars { b.hit(.perc2, Double(bar * 16 + 14), 0.5) } }
    }

    static func neoSoul(_ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        // Hats: two per beat, the second late (quintuplet or septuplet swing).
        let ratio = rng.pick([0.6, 4.0 / 7.0, 0.58])
        let ride = f == .busy && rng.chance(0.5)
        for beat in 0..<(b.bars * 4) {
            let base = Double(beat) * 4
            let p: Pad = ride ? .cymbal : .hat
            b.hit(p, base, 0.72)
            b.hit(p, base + ratio * 4, 0.45)
            if f == .busy && rng.chance(0.3) { b.hit(p, base + 3.2, 0.3) }
        }
        // Snares slightly early, sometimes a rim on the second backbeat.
        for bar in 0..<b.bars {
            b.hit(.snare, Double(bar * 16 + 4), 0.9, offset: -(3 + rng.int(5)))
            if rng.chance(0.35) {
                b.hit(.rim, Double(bar * 16 + 12), 0.85, offset: -(2 + rng.int(4)))
            } else {
                b.hit(.snare, Double(bar * 16 + 12), 0.9, offset: -(3 + rng.int(5)))
            }
            for g in [7, 15, 10] where rng.chance(f == .sparse ? 0.15 : 0.4) {
                b.hit(.snare, Double(bar * 16 + g), rng.range(0.18, 0.32))
            }
        }
        // Kicks loose and late.
        let templates: [[Int]] = [[0, 9, 10], [0, 7, 10], [0, 3, 10, 14], [0, 6, 9], [0, 8, 11]]
        var kicks: [Double] = []
        for bar in 0..<b.bars {
            var t = rng.pick(templates)
            if f == .sparse { t = [0, t.last ?? 10] }
            for s in t {
                kicks.append(Double(bar * 16 + s))
                b.hit(.kick, Double(bar * 16 + s), s == 0 ? 0.9 : 0.75, offset: 2 + rng.int(8))
            }
        }
        if rng.chance(0.5) {
            for bar in 0..<b.bars { b.hit(.bass808, Double(bar * 16), 0.6, semis: 0, length: 150) }
        }
        if f != .sparse {
            for s in 0..<b.stepsTotal where s % 4 == 2 && rng.chance(0.35) { b.hit(.perc1, Double(s), 0.4) }
            if rng.chance(0.4) { b.hit(.perc2, Double(b.stepsTotal - 3), 0.5) }
        }
    }

    static func gospel(_ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        for bar in 0..<b.bars {
            let o = bar * 16
            b.hit(.snare, Double(o + 4), 1)
            b.hit(.snare, Double(o + 12), 1)
            for g in [2, 6, 7, 9, 14, 15] where rng.chance(f == .busy ? 0.6 : f == .sparse ? 0.15 : 0.4) {
                b.hit(.snare, Double(o + g), rng.range(0.16, 0.3))
            }
            var kicks = [0, 10]
            if rng.chance(0.5) { kicks.append(rng.pick([7, 14, 13])) }
            for k in kicks { b.hit(.kick, Double(o + k), 0.9) }
        }
        hats(&b, every: 1, level: 0.75)
        let gospelOpen = rng.chance(0.5) ? 1 : 0
        openHats(&b, &rng, perBar: gospelOpen, spots: [14, 6])
        if rng.chance(0.4) { for bar in 0..<b.bars { b.hit(.perc1, Double(bar * 16 + 4), 0.5); b.hit(.perc1, Double(bar * 16 + 12), 0.5) } }
        // Every four bars: a chop fill into the crash at the top.
        let total = Double(b.stepsTotal)
        chops(&b, &rng, fromStep: total - (f == .busy ? 8 : 4), toStep: total)
        b.hit(.cymbal, 0, 0.85)
    }

    /// Linear "chops": R L L R L L R L, hands around the snare and toms, feet on the kick.
    static func chops(_ b: inout Builder, _ rng: inout KRandom, fromStep: Double, toStep: Double) {
        for pad in [Pad.hat, .openHat, .snare, .kick] { b.remove(pad, from: fromStep, to: toStep) }
        let rate = rng.chance(0.5) ? 16.0 : 12.0   // 16th triplets or 32nds
        let sticking: [Character] = Array("RLLRLLRL")
        let hands: [Pad] = rng.chance(0.5) ? [.snare, .perc2, .tomHigh, .tomLow] : [.perc2, .snare, .tomHigh, .tomLow]
        var t = fromStep * step
        var k = 0
        var handIndex = 0
        while t < toStep * step - 1 {
            let s = sticking[k % sticking.count]
            let progress = Float((t - fromStep * step) / ((toStep - fromStep) * step))
            if s == "R" {
                let pad = hands[min(handIndex / 2, hands.count - 1)]
                handIndex += 1
                b.events.append(GrooveEvent(tick: Int32(t.rounded()), pad: Int8(pad.rawValue), velocity: 0.75 + 0.25 * progress))
            } else if k % 3 == 1 {
                b.events.append(GrooveEvent(tick: Int32(t.rounded()), pad: Int8(Pad.snare.rawValue), velocity: 0.35 + 0.2 * progress))
            } else {
                b.events.append(GrooveEvent(tick: Int32(t.rounded()), pad: Int8(Pad.kick.rawValue), velocity: 0.8))
            }
            t += rate
            k += 1
        }
    }

    static func breakBeat(_ style: GrooveStyle, _ b: inout Builder, _ rng: inout KRandom, _ f: Flavour) {
        switch style {
        case .funkBreak:
            hats(&b, every: 1, level: 0.8, swingTicks: 2)
            openHats(&b, &rng, perBar: 1, spots: [7])
            for bar in 0..<b.bars {
                let o = bar * 16
                b.hit(.snare, Double(o + 4), 1)
                b.hit(.snare, Double(o + 12), 1)
                for g in [7, 9, 11, 15, 1] where rng.chance(f == .busy ? 0.6 : 0.4) {
                    b.hit(.clap, Double(o + g), rng.range(0.3, 0.5))  // ghost snare pad
                }
                let t = rng.pick([[0, 2, 10], [0, 2, 6, 10, 13], [0, 3, 10, 11], [0, 2, 10, 14]])
                for k in (f == .sparse ? Array(t.prefix(2)) : t) { b.hit(.kick, Double(o + k), 0.9, offset: 3) }
            }
        case .looseBreak:
            var kickSteps: [Int] = []
            for bar in 0..<b.bars {
                let o = bar * 16
                let t = rng.pick([[0, 7, 10], [0, 7, 9, 10], [0, 3, 7, 10], [0, 10, 11]])
                for k in t { kickSteps.append(o + k); b.hit(.kick, Double(o + k), 0.9) }
                b.hit(.snare, Double(o + 4), 1)
                b.hit(.snare, Double(o + 12), 1)
                if rng.chance(0.4) { b.hit(.clap, Double(o + 15), 0.35) }
            }
            // Hats on the 8ths, plus wherever the kick lands (they follow its syncopation).
            for s in 0..<b.stepsTotal where s % 2 == 0 || kickSteps.contains(s) {
                b.hit(.hat, Double(s), s % 4 == 0 ? 0.85 : 0.6, offset: s % 2 == 1 ? 5 : 0)
            }
            let looseOpen = rng.chance(0.5) ? 1 : 0
            openHats(&b, &rng, perBar: looseOpen, spots: [14])
        default: // heavy
            for bar in 0..<b.bars {
                let o = bar * 16
                let t = rng.pick([[0, 7, 10], [0, 3, 7, 10], [0, 2, 10], [0, 7, 9]])
                for k in t { b.hit(.kick, Double(o + k), 1) }
                b.hit(.snare, Double(o + 4), 1)
                b.hit(.snare, Double(o + 12), 1)
            }
            hats(&b, every: 2, level: 0.75)
            openHats(&b, &rng, perBar: 1, spots: [6, 14])
            if f == .busy { for bar in 0..<b.bars { b.hit(.perc1, Double(bar * 16 + 4), 0.5); b.hit(.perc1, Double(bar * 16 + 12), 0.5) } }
        }
    }

    // MARK: Variations

    static func keep(_ p: PatternData, _ pads: [Pad]) -> PatternData {
        var q = p
        let allowed = Set(pads.map { Int8($0.rawValue) })
        q.events = p.events.filter { allowed.contains($0.pad) }
        return q
    }

    static func withFill(_ p: PatternData, _ style: GrooveStyle, _ rng: inout KRandom) -> PatternData {
        var b = Builder(bars: p.bars)
        b.events = p.events
        let end = Double(b.stepsTotal)
        switch style {
        case .gospel:
            chops(&b, &rng, fromStep: end - 8, toStep: end)
        case .trap, .trapAtlanta, .trapMemphis, .trapToronto, .trapSoul, .baySlap, .westBounce:
            b.remove(.hat, from: end - 4, to: end)
            roll(&b, pad: .snare, start: end - 4, span: 4, rateTicks: rng.chance(0.5) ? 12 : 16, from: 0.35, to: 1)
            roll(&b, pad: .hat, start: end - 4, span: 4, rateTicks: 8, from: 0.4, to: 0.9)
        default:
            for pad in [Pad.hat, .snare, .openHat] { b.remove(pad, from: end - 4, to: end) }
            let pads: [Pad] = [.snare, .snare, .tomHigh, .tomHigh, .tomLow, .tomLow, .snare, .tomLow]
            for k in 0..<8 {
                b.hit(pads[k], end - 4 + Double(k) * 0.5, 0.7 + 0.04 * Float(k))
            }
            b.hit(.kick, end - 2, 0.85)
        }
        // Replace the slightly humanised first hit rather than layering another kick a few
        // ticks away from it. The turnaround lands on one clean downbeat when it loops.
        b.remove(.cymbal, from: 0, to: 1)
        b.remove(.kick, from: 0, to: 1)
        b.hit(.cymbal, 0, 0.85)
        b.hit(.kick, 0, 1)
        return b.data
    }

    static func breakdown(_ p: PatternData, _ style: GrooveStyle) -> PatternData {
        var q = p
        let len = p.lengthTicks
        q.events = p.events.compactMap { e in
            var e = e
            switch Pad(rawValue: Int(e.pad)) {
            case .kick?: return e.tick % (PatternData.ppq * 4) < 6 ? e : nil
            case .bass808?:
                guard e.tick % (PatternData.ppq * 4) < 6 else { return nil }
                e.length = PatternData.ppq * 4 - 12
                e.glide = false
                return e
            case .snare?, .clap?: return e.tick > len - PatternData.ppq ? e : nil
            case .hat?, .openHat?, .perc1?, .perc2?, .rim?:
                e.velocity *= 0.7
                return e
            default: return e
            }
        }
        return q
    }

    static func rollUp(_ style: GrooveStyle, _ rng: inout KRandom) -> PatternData {
        var b = Builder(bars: 2)
        // Bar 1: snare in 8ths then 16ths; bar 2: 16th triplets then 32nds, swelling.
        roll(&b, pad: .snare, start: 0, span: 8, rateTicks: 48, from: 0.4, to: 0.55)
        roll(&b, pad: .snare, start: 8, span: 8, rateTicks: 24, from: 0.55, to: 0.7)
        roll(&b, pad: .snare, start: 16, span: 8, rateTicks: 16, from: 0.7, to: 0.85)
        roll(&b, pad: .snare, start: 24, span: 8, rateTicks: 12, from: 0.85, to: 1)
        let hatRate = style.isTrap ? 12.0 : 24.0
        roll(&b, pad: .hat, start: 16, span: 16, rateTicks: hatRate, from: 0.35, to: 0.9)
        b.hit(.kick, 0, 0.9)
        b.hit(.kick, 16, 0.9)
        if style.isTrap || style == .baySlap { b.hit(.bass808, 0, 0.8, semis: 0, length: 700) }
        _ = rng.next()
        return b.data
    }
}
