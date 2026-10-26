// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Live drummer
//
// HUMANIZE plays a pattern the way a drummer would, instead of shaking every note at random.
// The rules come from studies of real drummers and programming guides (research notes:
// realistic-drums-and-genres.md):
//
//   Velocity    hats: on the beat strongest, the "and" softer, the "e" / "a" softest, and on a
//               fast line the lead hand a little stronger than the other. Backbeats sit in a narrow
//               loud range, ghost notes stay quiet (about 40 of 127), peaks rarely reach 127.
//               The second of two quick kicks is a little louder; a flam's grace note is soft.
//               A fill grows into the next downbeat, and the crash that lands on it is the loudest.
//   Timing      each drum has its own place in the pocket: snare backbeats laid back, hats riding
//               a touch ahead, kick just behind the grid, the 808 locked to the kick. Ghosts and
//               hats move the most, backbeats the least. Time breathes over a 4-bar phrase and a
//               fill rushes a little (players push further than they pull).
//   Two hands   more than two hand-played sounds on one step: the extra ones are played softer.
//   Sound       repeated hits on one drum alternate a few cents up and down, so a hat line or a
//               roll doesn't sound like the same sample fired again and again.
//
// All of this is done once when the pattern is handed to the engine, never in the render
// callback, and the same pattern always gets the same feel. The notes you see stay where you
// put them; MIDI out and MIDI files carry the played feel.

/// How a genre's drummer plays (Tyrone, Oct 26: "velocity, timing, everything from the genres we have"),
/// from the genre guide in realistic-drums-and-genres.md. Pockets are in ticks (96 a beat) at full
/// HUMANIZE: + late, - early. `.general` is the one feel every pattern had before.
struct GenreFeel: Equatable {
    /// HUMANIZE a preset of this genre loads with (the knob shows it).
    var amount: Float = 0
    var kick: Float = 0.3, backbeat: Float = 1.0, ghost: Float = 0.2, snare: Float = 0.5
    var hat: Float = -0.4, tom: Float = 0.2, perc: Float = 0.3
    /// How much each hit wanders around its pocket (1 = a session drummer, under 0.3 = a drum machine).
    var loose: Float = 1
    /// How much time breathes over a 4-bar phrase.
    var breathe: Float = 0.35
    /// Hat accents: the beat, the "and", the "e" / "a".
    var hatAnd: Float = 0.88, hatE: Float = 0.76
    /// Where backbeats and ghost notes settle.
    var backbeatLevel: Float = 0.86, ghostLevel: Float = 0.32

    static let general = GenreFeel()

    /// Programmed genres: on the grid, only the velocity of a hand on the pads.
    static let machine = GenreFeel(amount: 0.2, kick: 0, backbeat: 0, ghost: 0, snare: 0, hat: 0, tom: 0, perc: 0,
                                   loose: 0.25, breathe: 0, hatAnd: 0.9, hatE: 0.8, backbeatLevel: 0.9)
    /// Neo soul: lazy kick late, snare and cross-stick early, ghosts at 25-45.
    static let neoSoul = GenreFeel(amount: 0.6, kick: 1.5, backbeat: -1.5, ghost: -0.5, snare: -1, hat: -0.3,
                                   loose: 1.3, breathe: 0.4, hatAnd: 0.85, hatE: 0.7, ghostLevel: 0.3)
    /// Dilla time: the kick dragging, the snare rushing, hats floating between them.
    static let dilla = GenreFeel(amount: 0.7, kick: 2, backbeat: -2, ghost: -1, snare: -1.5, hat: 0,
                                 loose: 1.5, breathe: 0.5, hatAnd: 0.84, hatE: 0.7, ghostLevel: 0.3)
    /// Boom bap: MPC-tight, a hard even backbeat, the hats carrying the dynamics.
    static let boomBap = GenreFeel(amount: 0.35, kick: 0.3, backbeat: 0.6, ghost: 0.2, snare: 0.4, hat: -0.2,
                                   loose: 0.7, breathe: 0.2, hatAnd: 0.82, hatE: 0.68, backbeatLevel: 0.9)
    /// Lo-fi: everything a touch behind, loose.
    static let loFi = GenreFeel(amount: 0.5, kick: 1, backbeat: 1.2, ghost: 0.6, snare: 0.8, hat: 0,
                                loose: 1.2, breathe: 0.4, hatAnd: 0.8, hatE: 0.66)
    /// 70s soul and funk session drummers: full backbeat, ghosts on the even 16ths, hats a hair ahead.
    static let soul = GenreFeel(amount: 0.65, kick: 0.3, backbeat: 0.8, ghost: 0.2, snare: 0.5, hat: -0.5,
                                loose: 1.0, breathe: 0.35, hatAnd: 0.85, hatE: 0.72, backbeatLevel: 0.9, ghostLevel: 0.3)
    /// The breaks: a band playing, the backbeat sitting back.
    static let breaks = GenreFeel(amount: 0.55, kick: 0.2, backbeat: 0.6, ghost: 0.2, snare: 0.4, hat: -0.4,
                                  loose: 1.0, breathe: 0.35, hatAnd: 0.84, hatE: 0.72)
    /// Rock and live pop: 8th hats accented on the beat (about 100 / 70), the backbeat just behind.
    static let rock = GenreFeel(amount: 0.5, kick: -0.2, backbeat: 0.4, ghost: 0.2, snare: 0.3, hat: -0.6, tom: 0,
                                loose: 0.8, breathe: 0.3, hatAnd: 0.72, hatE: 0.65, backbeatLevel: 0.92)
    /// R&B: the snare laid back (+10 to +25 ms), everything else close to the grid.
    static let rnb = GenreFeel(amount: 0.35, kick: 0.3, backbeat: 1.5, ghost: 0.5, snare: 0.8, hat: -0.2,
                               loose: 0.5, breathe: 0.2, hatAnd: 0.86, hatE: 0.74)
    /// Afrobeats and Latin: the hand percussion and hats drive a little ahead.
    static let world = GenreFeel(amount: 0.45, kick: 0.2, backbeat: 0.3, ghost: 0.1, snare: 0.2, hat: -0.5, perc: -0.3,
                                 loose: 0.8, breathe: 0.25, hatAnd: 0.86, hatE: 0.76)

    /// The feel of a PATTERNS group, or nil for the grooves learned from Tyrone's own loops
    /// (BK Editions, West Coast, Bay Area: they already play the way they were played).
    static func of(_ group: String?) -> GenreFeel? {
        guard let group else { return nil }
        if group.hasPrefix("BK Editions") { return nil }
        switch group {
        case "West Coast", "Bay Area": return nil
        case "Neo Soul": return .neoSoul
        case "Dilla Time": return .dilla
        case "Boom Bap", "90s Rap", "East Coast": return .boomBap
        case "Lo-fi": return .loFi
        case "70s Soul", "Live Soul", "Vintage R&B": return .soul
        case "80s Breaks": return .breaks
        case "Rock", "Live Pop": return .rock
        case "RnB", "90s RnB", "UK RnB", "2000s R&B", "Toronto R&B", "Trapsoul": return .rnb
        case "Afrobeats", "World & Latin": return .world
        case "Trap", "Alt Trap", "Drill", "UK Drill", "NY Drill", "Detroit 2026", "Dark Trap", "Phonk", "ATL Trap",
             "Memphis", "Bouncy", "Dark Experimental", "80s Pop": return .machine
        default: return nil
        }
    }
}

enum LiveDrummer {
    enum Role { case kick, snare, hat, cymbal, tom, perc, bass }

    static func role(_ pad: Int) -> Role {
        switch Pad(rawValue: pad) ?? .perc1 {
        case .kick: return .kick
        case .snare, .clap, .rim: return .snare
        case .hat, .openHat: return .hat
        case .cymbal: return .cymbal
        case .tomLow, .tomHigh: return .tom
        case .bass808: return .bass
        default: return .perc
        }
    }

    /// The furthest the feel moves a hit from where the pattern puts it, in ticks (96 a beat).
    static let maxFeel: Float = 6

    /// `amount` is HUMANIZE, 0...1; `feel` the pattern's genre (GenreFeel.of its PATTERNS group).
    static func play(_ data: PatternData, amount: Float, feel g: GenreFeel = .general) -> PatternData {
        let a = amount.clamped(0, 1)
        guard a > 0.001, !data.events.isEmpty else { return data }
        var p = data
        let beat = Int(PatternData.ppq), bar = beat * 4
        let len = max(Int(p.lengthTicks), bar)
        let bars = max(1, len / bar)
        let phraseBars = min(bars, 4)
        let phraseLen = Float(phraseBars * bar)

        // Hand-played sounds on each step (the kick and the 808 are feet / not the drummer).
        var hands: [Int32: Int] = [:]
        for e in p.events {
            let r = role(Int(e.pad))
            if r != .kick && r != .bass { hands[e.tick, default: 0] += 1 }
        }

        let order = p.events.indices.sorted { (p.events[$0].tick, p.events[$0].pad) < (p.events[$1].tick, p.events[$1].pad) }
        var lastTick = Array(repeating: Int.min / 2, count: Pad.count)
        var lastIndex = Array(repeating: -1, count: Pad.count)
        var hits = Array(repeating: 0, count: Pad.count)
        var lastGap = Array(repeating: Int.max / 2, count: Pad.count)
        var kickFeel: [Int32: Float] = [:]

        for i in order {
            var e = p.events[i]
            let pad = Int(e.pad)
            guard pad >= 0, pad < Pad.count else { continue }
            let r = role(pad)
            if r == .bass { continue }   // placed with the kick below
            var rng = KRandom(seed: UInt32(truncatingIfNeeded: Int(e.tick) &* 2_654_435_761 &+ pad &* 40_503 &+ 1))
            let tick = Int(e.tick)
            let pos = ((tick % bar) + bar) % bar
            let sub = pos % beat
            let barInPhrase = (tick / bar) % phraseBars
            let fillBar = phraseBars > 1 && barInPhrase == phraseBars - 1
            let gap = tick - lastTick[pad]
            let v0 = e.velocity
            var v = v0
            var feel: Float = 0, timeJitter: Float = 0.6, velJitter: Float = 0.05

            switch r {
            case .hat:
                let accent: Float = sub == 0 ? 1 : sub == 48 ? g.hatAnd : (sub == 24 || sub == 72) ? g.hatE : (g.hatAnd + g.hatE) / 2
                v *= 1 + (accent - 1) * a
                if gap <= 24 && hits[pad] % 2 == 1 { v *= 1 - 0.07 * a }   // the other hand
                feel = g.hat * a
                timeJitter = 0.9; velJitter = 0.06
            case .snare:
                if v0 < 0.45 {   // ghost note
                    v += (g.ghostLevel - v) * 0.5 * a
                    feel = g.ghost * a
                    timeJitter = 1.0; velJitter = 0.10
                } else if v0 >= 0.6 {   // backbeat
                    v += (g.backbeatLevel - v) * 0.45 * a
                    feel = g.backbeat * a
                    timeJitter = 0.4; velJitter = 0.03
                } else {
                    feel = g.snare * a
                    timeJitter = 0.7; velJitter = 0.06
                }
            case .kick:
                if pos == 0 { v *= 1 + 0.04 * a }
                feel = g.kick * a
                timeJitter = 0.5; velJitter = 0.04
            case .tom:
                feel = g.tom * a
                timeJitter = 0.6; velJitter = 0.05
            case .cymbal:
                if pos == 0 && barInPhrase == 0 { v *= 1 + 0.06 * a }   // the crash after the fill
                timeJitter = 0.5; velJitter = 0.05
            case .perc:
                feel = g.perc * a
                timeJitter = 0.9; velJitter = 0.07
            case .bass:
                break
            }

            // Doubles and flams on one drum (the first of a quick pair on a snare or tom is the grace note).
            if gap <= 6 && lastGap[pad] > 12 && (r == .snare || r == .tom), lastIndex[pad] >= 0 {
                p.events[lastIndex[pad]].velocity = min(p.events[lastIndex[pad]].velocity, 0.45)   // grace note
            } else if gap <= 24 && r == .kick {
                v *= 1 + 0.05 * a
            }
            // A fill grows from beat 3 of a phrase's last bar and rushes a little.
            if fillBar && pos >= 2 * beat && (r == .snare || r == .tom) {
                v *= 1 + 0.08 * a * Float(pos - 2 * beat) / Float(2 * beat)
                feel -= 0.5 * a
            }
            // Only two hands.
            if (hands[e.tick] ?? 0) > 2 && (r == .hat || r == .perc) { v *= 1 - 0.12 * a }
            // Peaks rarely hit 127.
            if v > 0.93 { v -= (v - 0.93) * 0.7 * a }
            // Time breathes over the phrase.
            feel += g.breathe * a * sinf(2 * .pi * Float(tick) / phraseLen)

            let wobble = (rng.unit() + rng.unit() + rng.unit() - 1.5) * 1.15
            feel += wobble * timeJitter * g.loose * a
            v *= 1 + rng.bipolar() * velJitter * a
            e.velocity = v.clamped(0.05, 1)
            e.feel = feel.clamped(-maxFeel, maxFeel)
            // Each hit a few cents from the last one on the same drum.
            e.semis += (hits[pad] % 2 == 0 ? 0.08 : -0.08) * a + rng.bipolar() * 0.04 * a
            if r == .kick { kickFeel[e.tick] = e.feel }

            p.events[i] = e
            lastGap[pad] = gap
            lastTick[pad] = tick
            lastIndex[pad] = i
            hits[pad] += 1
        }
        for i in p.events.indices where role(Int(p.events[i].pad)) == .bass {
            p.events[i].feel = kickFeel[p.events[i].tick] ?? g.kick * a
        }
        return p
    }
}
