// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Pads
//
// The 12 pads always hold the same kind of sound, so grooves work with every kit, MIDI maps
// stay the same, and exported MIDI plays back right:
//
//   top row:     7 808     8 PERC 1   9 PERC 2   10 TOM LO   11 TOM HI   12 CYMBAL
//   bottom row:  1 KICK    2 SNARE    3 CLAP     4 RIM/SNAP  5 HAT       6 OPEN HAT
//
// MIDI notes 36...47 play pads 1...12 in order. Notes 48...84 play the 808 chromatically
// (note 60 is the kit's 808 tuning).

enum Pad: Int, CaseIterable {
    case kick = 0, snare, clap, rim, hat, openHat, bass808, perc1, perc2, tomLow, tomHigh, cymbal

    static let count = 12
    static let firstNote = 36
    static let bassRootNote = 60
    static let bassNoteRange = 48...84

    var midiNote: Int { Self.firstNote + rawValue }
    static func index(forMIDINote note: Int) -> Int? {
        (36...47).contains(note) ? note - 36 : nil
    }

    var label: String {
        switch self {
        case .kick: return "KICK"
        case .snare: return "SNARE"
        case .clap: return "CLAP"
        case .rim: return "RIM / SNAP"
        case .hat: return "HAT"
        case .openHat: return "OPEN HAT"
        case .bass808: return "808"
        case .perc1: return "PERC 1"
        case .perc2: return "PERC 2"
        case .tomLow: return "TOM LO"
        case .tomHigh: return "TOM HI"
        case .cymbal: return "CYMBAL"
        }
    }

    /// Pads that cut each other off: the closed hat stops the open hat.
    var chokeGroup: Int {
        switch self {
        case .hat, .openHat: return 1
        case .bass808: return 2
        default: return 0
        }
    }
}

/// Which live MIDI note plays each pad, for hardware pad controllers. MIDI files and MIDI
/// export always use notes 36-47; this only changes what incoming notes trigger.
enum MIDIPadMap: String, CaseIterable, Codable {
    case standard, mpcClassic, custom

    /// Pads 1-12: C1 up (also an MPC's "Chromatic C1" setting).
    static let standardNotes: [Int] = Array(36...47)
    /// An MPC's "Classic MPC" map, pads A01-A12. A01 sits bottom-left like pad 1.
    static let mpcClassicNotes: [Int] = [37, 36, 42, 82, 40, 38, 46, 44, 48, 47, 45, 43]

    var title: String {
        switch self {
        case .standard: return "BreaKing / MPC Chromatic C1 (36–47)"
        case .mpcClassic: return "MPC Classic (A01–A12)"
        case .custom: return "Custom (MIDI learn)"
        }
    }

    /// One note per pad; a note given to two pads only plays the later pad.
    static func notes(_ map: MIDIPadMap, custom: [Int]?) -> [Int] {
        switch map {
        case .standard: return standardNotes
        case .mpcClassic: return mpcClassicNotes
        case .custom: return clean(custom ?? standardNotes)
        }
    }

    static func clean(_ notes: [Int]) -> [Int] {
        var out = Array(notes.prefix(Pad.count)).map { (0...127).contains($0) ? $0 : -1 }
        while out.count < Pad.count { out.append(-1) }
        return out
    }

    /// Gives `note` to `pad` and takes it off any other pad.
    static func learn(_ notes: [Int], pad: Int, note: Int) -> [Int] {
        var out = clean(notes)
        guard (0..<Pad.count).contains(pad), (0...127).contains(note) else { return out }
        for i in out.indices where out[i] == note { out[i] = -1 }
        out[pad] = note
        return out
    }
}

// MARK: - Kits

struct KitDefinition: Identifiable {
    let id: String
    let name: String
    let style: GrooveStyle
    /// The groove's own tempo (used when TEMPO SYNC is off, and when the kit is picked).
    let tempo: Double
    /// 808 tuning in Hz (note 60 plays this).
    let bassHz: Float
    let pads: [DrumRecipe]
    /// The mode bank it lives in. Browser home only: every kit and imported sample works through all three modes.
    let preferredMode: SoundMode
    /// The genre tab it sits under in the KITS browser (KitLibrary.families), or "FX".
    let family: String
    /// What it is, on its card: "G-FUNK", "AMAPIANO". The A/B kits use their name without the A / B.
    let genre: String

    init(id: String, name: String, style: GrooveStyle, tempo: Double, bassHz: Float, pads: [DrumRecipe],
         mode: SoundMode = .modern, family: String = "", genre: String? = nil) {
        self.id = id; self.name = name; self.style = style; self.tempo = tempo; self.bassHz = bassHz
        self.pads = Array(pads.prefix(Pad.count))
        self.preferredMode = mode; self.family = family
        self.genre = genre ?? (name.hasSuffix(" A") || name.hasSuffix(" B") ? String(name.dropLast(2)) : name)
    }
}

enum KitLibrary {
    // The factory kits are in FactoryKits.swift (made by tools/build_kits.py from tools/kit_catalog.py):
    // every pad a stock sound sorted and named by category. The synth voices below are what each
    // kit falls back on (and what plays its variations); they are not kits of their own.

    /// The genre tabs of the KITS browser, in order. Every mode bank has at least 20 kits under each.
    static let families = ["TRAP", "WEST COAST", "SOUL & R&B", "BREAKS", "POP", "WORLD"]

    /// The kits grouped by genre ("BOOM BAP A" and "BOOM BAP B" -> "BOOM BAP"), in browser order.
    static var genreGroups: [(genre: String, kits: [KitDefinition])] { groups(factory, by: \.genre) }

    /// This mode's kits under their genre tabs (TRAP, WEST COAST...), for the kit menus.
    static func genreGroups(for mode: SoundMode) -> [(genre: String, kits: [KitDefinition])] {
        groups(kits(for: mode), by: \.family)
    }

    /// Every factory kit that opens in this mode, in browser order: tab by tab.
    static func kits(for mode: SoundMode) -> [KitDefinition] {
        let mine = factory.filter { $0.preferredMode == mode }
        let rank = { (k: KitDefinition) in families.firstIndex(of: k.family) ?? families.count }
        return mine.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// Mode lists first, the way the browsers show them (the ◀ ▶ kit arrows step through this).
    static var browserOrder: [KitDefinition] { SoundMode.allCases.flatMap { kits(for: $0) } }

    private static func groups(_ kits: [KitDefinition], by key: KeyPath<KitDefinition, String>) -> [(genre: String, kits: [KitDefinition])] {
        var order: [String] = []; var map: [String: [KitDefinition]] = [:]
        for k in kits {
            let g = k[keyPath: key]
            if map[g] == nil { order.append(g) }
            map[g, default: []].append(k)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    static func variant(_ id: String, _ name: String, _ base: KitDefinition, _ style: GrooveStyle,
                        _ tempo: Double, _ seed: UInt32, bass: Float, _ mode: SoundMode, _ family: String, _ genre: String,
                        tone: Float = 0, drive: Float = 0.1) -> KitDefinition {
        var rng = KRandom(seed: seed)
        var pads = base.pads.map { $0.varied(&rng, amount: 0.75) }
        for i in pads.indices {
            pads[i].tone = (pads[i].tone + tone).clamped(0, 1)
            pads[i].drive = (pads[i].drive + drive).clamped(0, 1)
        }
        pads[Pad.bass808.rawValue].tune = bass
        if style == .latin || style == .afrobeats {
            pads[7] = DrumRecipe(kind: .conga, tune: 240, decay: 0.26, level: 0.8, label: "CONGA LOW")
            pads[8] = DrumRecipe(kind: .bongo, tune: 410, decay: 0.18, level: 0.7, label: "BONGO")
        }
        return KitDefinition(id: id, name: name, style: style, tempo: tempo, bassHz: bass, pads: pads,
                             mode: mode, family: family, genre: genre)
    }

    /// A kit by its identifier. Kits from before Oct 17 open the new kit nearest their genre.
    static func kit(id: String) -> KitDefinition {
        let id = retired[id] ?? id
        return factory.first { $0.id == id } ?? factory[0]
    }

    /// The current identifier for a saved one (old kits map to their new kit).
    static func currentID(_ id: String) -> String { kit(id: id).id }

    // Note frequencies used for 808 tunings.
    static let E1: Float = 41.20, F1: Float = 43.65, Fs1: Float = 46.25, G1: Float = 49.00, A1: Float = 55.00, D1: Float = 36.71

    static let drumMastery = KitDefinition(
        id: "voice-drum-mastery", name: "DRUM MASTERY", style: .trap, tempo: 140, bassHz: F1,
        pads: [
            DrumRecipe(kind: .kickPunch, tune: 52, decay: 0.32, tone: 0.55, snap: 0.6, drive: 0.15, label: "KICK"),
            DrumRecipe(kind: .snareTrap, tune: 195, decay: 0.26, tone: 0.55, snap: 0.6, label: "SNARE"),
            DrumRecipe(kind: .clap, tune: 1, decay: 0.32, tone: 0.5, snap: 0.6, label: "CLAP"),
            DrumRecipe(kind: .rim, tune: 520, decay: 0.08, tone: 0.5, snap: 0.6, label: "RIM"),
            DrumRecipe(kind: .hatClosed, tune: 1.05, decay: 0.06, tone: 0.6, label: "HAT"),
            DrumRecipe(kind: .hatOpen, tune: 1.05, decay: 0.42, tone: 0.6, label: "OPEN HAT"),
            DrumRecipe(kind: .kick808, tune: F1, decay: 1.9, tone: 0.45, snap: 0.5, drive: 0.1, label: "808"),
            DrumRecipe(kind: .shaker, tune: 1, decay: 0.11, tone: 0.5, snap: 0.5, level: 0.7, label: "SHAKER"),
            DrumRecipe(kind: .woodblock, tune: 880, decay: 0.12, level: 0.75, label: "BLOCK"),
            DrumRecipe(kind: .tomLow, tune: 98, decay: 0.45, tone: 0.3, snap: 0.5, label: "TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 147, decay: 0.38, tone: 0.3, snap: 0.5, label: "TOM HI"),
            DrumRecipe(kind: .crash, tune: 1, decay: 1.6, tone: 0.5, level: 0.7, label: "CRASH")
        ])

    static let modernTrap = KitDefinition(
        id: "voice-modern-trap", name: "MODERN TRAP", style: .trap, tempo: 144, bassHz: E1,
        pads: [
            DrumRecipe(kind: .kickPunch, tune: 50, decay: 0.26, tone: 0.7, snap: 0.75, drive: 0.25, label: "KICK"),
            DrumRecipe(kind: .snareCrack, tune: 210, decay: 0.22, tone: 0.65, snap: 0.7, drive: 0.1, label: "SNARE"),
            DrumRecipe(kind: .clap, tune: 1, decay: 0.28, tone: 0.65, snap: 0.75, label: "CLAP"),
            DrumRecipe(kind: .snap, tune: 1, decay: 0.07, tone: 0.6, label: "SNAP"),
            DrumRecipe(kind: .hatClosed, tune: 1.12, decay: 0.045, tone: 0.75, label: "HAT"),
            DrumRecipe(kind: .hatOpen, tune: 1.12, decay: 0.32, tone: 0.75, label: "OPEN HAT"),
            DrumRecipe(kind: .kick808, tune: E1, decay: 2.3, tone: 0.6, snap: 0.6, drive: 0.25, label: "808"),
            DrumRecipe(kind: .rim, tune: 610, decay: 0.06, snap: 0.8, level: 0.75, label: "PERC"),
            DrumRecipe(kind: .cowbell, tune: 560, decay: 0.2, level: 0.6, label: "BELL"),
            DrumRecipe(kind: .tomLow, tune: 82, decay: 0.5, tone: 0.2, snap: 0.6, drive: 0.2, label: "808 TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 123, decay: 0.4, tone: 0.2, snap: 0.6, drive: 0.2, label: "808 TOM HI"),
            DrumRecipe(kind: .crash, tune: 1.1, decay: 1.3, tone: 0.6, level: 0.65, label: "CRASH")
        ])

    static let westBounce = KitDefinition(
        id: "voice-west-bounce", name: "WEST BOUNCE", style: .westBounce, tempo: 100, bassHz: G1,
        pads: [
            DrumRecipe(kind: .kickBoom, tune: 58, decay: 0.3, tone: 0.5, snap: 0.6, drive: 0.15, label: "KICK"),
            DrumRecipe(kind: .snareTrap, tune: 230, decay: 0.2, tone: 0.6, snap: 0.6, label: "SNARE"),
            DrumRecipe(kind: .clap, tune: 1, decay: 0.24, tone: 0.75, snap: 0.85, label: "CLAP"),
            DrumRecipe(kind: .snap, tune: 1.1, decay: 0.08, tone: 0.7, label: "SNAP"),
            DrumRecipe(kind: .hatClosed, tune: 1.0, decay: 0.05, tone: 0.55, label: "HAT"),
            DrumRecipe(kind: .hatOpen, tune: 1.0, decay: 0.28, tone: 0.55, label: "OPEN HAT"),
            DrumRecipe(kind: .kick808, tune: G1, decay: 0.75, tone: 0.55, snap: 0.6, drive: 0.15, label: "808"),
            DrumRecipe(kind: .shaker, tune: 1, decay: 0.09, tone: 0.6, snap: 0.6, level: 0.65, label: "SHAKER"),
            DrumRecipe(kind: .tambourine, tune: 1, decay: 0.22, level: 0.6, label: "TAMB"),
            DrumRecipe(kind: .tomLow, tune: 110, decay: 0.3, tone: 0.3, label: "TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 165, decay: 0.26, tone: 0.3, label: "TOM HI"),
            DrumRecipe(kind: .crash, tune: 1, decay: 1.2, level: 0.6, label: "CRASH")
        ])

    static let baySlap = KitDefinition(
        id: "voice-bay-slap", name: "BAY SLAP", style: .baySlap, tempo: 92, bassHz: Fs1,
        pads: [
            DrumRecipe(kind: .kickPunch, tune: 56, decay: 0.3, tone: 0.65, snap: 0.8, drive: 0.3, label: "KICK"),
            DrumRecipe(kind: .snareCrack, tune: 240, decay: 0.24, tone: 0.75, snap: 0.85, drive: 0.25, label: "SNARE"),
            DrumRecipe(kind: .clap, tune: 1, decay: 0.26, tone: 0.6, snap: 0.8, label: "CLAP"),
            DrumRecipe(kind: .rim, tune: 470, decay: 0.07, snap: 0.7, label: "RIM"),
            DrumRecipe(kind: .hatClosed, tune: 0.95, decay: 0.05, tone: 0.5, label: "HAT"),
            DrumRecipe(kind: .hatOpen, tune: 0.95, decay: 0.3, tone: 0.5, label: "OPEN HAT"),
            DrumRecipe(kind: .kick808, tune: Fs1, decay: 1.6, tone: 0.65, snap: 0.7, drive: 0.35, label: "808"),
            DrumRecipe(kind: .conga, tune: 260, decay: 0.2, snap: 0.6, level: 0.7, label: "CONGA"),
            DrumRecipe(kind: .woodblock, tune: 1040, decay: 0.1, level: 0.65, label: "BLOCK"),
            DrumRecipe(kind: .tomLow, tune: 92, decay: 0.42, tone: 0.3, label: "TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 138, decay: 0.34, tone: 0.3, label: "TOM HI"),
            DrumRecipe(kind: .crash, tune: 0.95, decay: 1.4, level: 0.6, label: "CRASH")
        ])

    static let west90s = KitDefinition(
        id: "voice-west-90s", name: "WEST 90S", style: .west90s, tempo: 95, bassHz: A1,
        pads: [
            DrumRecipe(kind: .kickBoom, tune: 54, decay: 0.42, tone: 0.35, snap: 0.45, drive: 0.1, label: "KICK"),
            DrumRecipe(kind: .snareTrap, tune: 185, decay: 0.24, tone: 0.45, snap: 0.5, label: "SNARE"),
            DrumRecipe(kind: .clap, tune: 1, decay: 0.3, tone: 0.45, snap: 0.55, label: "CLAP"),
            DrumRecipe(kind: .rim, tune: 450, decay: 0.08, snap: 0.5, label: "RIM"),
            DrumRecipe(kind: .hatClosed, tune: 0.9, decay: 0.055, tone: 0.45, label: "HAT"),
            DrumRecipe(kind: .hatOpen, tune: 0.9, decay: 0.26, tone: 0.45, label: "OPEN HAT"),
            DrumRecipe(kind: .sub808, tune: A1, decay: 0.55, tone: 0.3, snap: 0.3, label: "SUB"),
            DrumRecipe(kind: .tambourine, tune: 1, decay: 0.25, level: 0.7, label: "TAMB"),
            DrumRecipe(kind: .cowbell, tune: 540, decay: 0.22, level: 0.55, label: "BELL"),
            DrumRecipe(kind: .tomLow, tune: 105, decay: 0.36, tone: 0.3, label: "TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 155, decay: 0.3, tone: 0.3, label: "TOM HI"),
            DrumRecipe(kind: .ride, tune: 1, decay: 1.1, tone: 0.6, level: 0.55, label: "RIDE")
        ])

    static let neoSoul = KitDefinition(
        id: "voice-neo-soul", name: "NEO SOUL", style: .neoSoul, tempo: 88, bassHz: D1,
        pads: [
            DrumRecipe(kind: .kickAcoustic, tune: 58, decay: 0.38, tone: 0.4, snap: 0.4, room: 0.25, label: "KICK"),
            DrumRecipe(kind: .snareAcoustic, tune: 190, decay: 0.28, tone: 0.4, snap: 0.45, room: 0.3, label: "SNARE"),
            DrumRecipe(kind: .clap, tune: 1, decay: 0.3, tone: 0.35, snap: 0.4, room: 0.2, level: 0.75, label: "CLAP"),
            DrumRecipe(kind: .rim, tune: 400, decay: 0.09, snap: 0.45, room: 0.25, label: "RIM"),
            DrumRecipe(kind: .hatAcousticClosed, tune: 0.95, decay: 0.08, tone: 0.4, room: 0.15, label: "HAT"),
            DrumRecipe(kind: .hatAcousticOpen, tune: 0.95, decay: 0.45, tone: 0.4, room: 0.15, label: "OPEN HAT"),
            DrumRecipe(kind: .sub808, tune: D1, decay: 0.9, tone: 0.2, snap: 0.2, label: "SUB"),
            DrumRecipe(kind: .shaker, tune: 0.9, decay: 0.12, tone: 0.4, snap: 0.3, level: 0.6, label: "SHAKER"),
            DrumRecipe(kind: .conga, tune: 230, decay: 0.24, snap: 0.4, room: 0.2, level: 0.7, label: "CONGA"),
            DrumRecipe(kind: .tomLow, tune: 96, decay: 0.5, tone: 0.3, room: 0.3, label: "TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 140, decay: 0.42, tone: 0.3, room: 0.3, label: "TOM HI"),
            DrumRecipe(kind: .ride, tune: 0.92, decay: 1.6, tone: 0.5, room: 0.15, level: 0.55, label: "RIDE")
        ])

    static let gospelChops = KitDefinition(
        id: "voice-gospel-chops", name: "GOSPEL CHOPS", style: .gospel, tempo: 98, bassHz: F1,
        pads: [
            DrumRecipe(kind: .kickAcoustic, tune: 62, decay: 0.32, tone: 0.55, snap: 0.6, room: 0.2, label: "KICK"),
            DrumRecipe(kind: .snareAcoustic, tune: 260, decay: 0.22, tone: 0.6, snap: 0.7, room: 0.25, label: "SNARE"),
            DrumRecipe(kind: .clap, tune: 1, decay: 0.26, tone: 0.55, snap: 0.6, room: 0.2, level: 0.75, label: "CLAP"),
            DrumRecipe(kind: .rim, tune: 520, decay: 0.08, snap: 0.6, room: 0.2, label: "RIM"),
            DrumRecipe(kind: .hatAcousticClosed, tune: 1.05, decay: 0.07, tone: 0.55, room: 0.1, label: "HAT"),
            DrumRecipe(kind: .hatAcousticOpen, tune: 1.05, decay: 0.4, tone: 0.55, room: 0.1, label: "OPEN HAT"),
            DrumRecipe(kind: .sub808, tune: F1, decay: 0.8, tone: 0.3, snap: 0.3, label: "SUB"),
            DrumRecipe(kind: .tambourine, tune: 1.05, decay: 0.24, level: 0.65, label: "TAMB"),
            DrumRecipe(kind: .tomHigh, tune: 196, decay: 0.32, tone: 0.3, snap: 0.6, room: 0.25, label: "TOM RACK"),
            DrumRecipe(kind: .tomLow, tune: 88, decay: 0.55, tone: 0.3, snap: 0.6, room: 0.3, label: "FLOOR TOM"),
            DrumRecipe(kind: .tomHigh, tune: 140, decay: 0.42, tone: 0.3, snap: 0.6, room: 0.25, label: "TOM MID"),
            DrumRecipe(kind: .crash, tune: 1.05, decay: 1.8, tone: 0.55, room: 0.15, level: 0.6, label: "CRASH")
        ])

    static let funkBreak = KitDefinition(
        id: "voice-funk-break", name: "FUNK BREAK", style: .funkBreak, tempo: 101, bassHz: E1,
        pads: [
            DrumRecipe(kind: .kickAcoustic, tune: 64, decay: 0.3, tone: 0.5, snap: 0.55, drive: 0.15, room: 0.45, label: "KICK"),
            DrumRecipe(kind: .snareAcoustic, tune: 215, decay: 0.26, tone: 0.55, snap: 0.6, drive: 0.15, room: 0.45, label: "SNARE"),
            DrumRecipe(kind: .snareAcoustic, tune: 230, decay: 0.12, tone: 0.3, snap: 0.25, room: 0.4, level: 0.55, label: "GHOST"),
            DrumRecipe(kind: .rim, tune: 480, decay: 0.08, snap: 0.6, room: 0.4, label: "RIM"),
            DrumRecipe(kind: .hatAcousticClosed, tune: 0.92, decay: 0.07, tone: 0.45, room: 0.3, label: "HAT"),
            DrumRecipe(kind: .hatAcousticOpen, tune: 0.92, decay: 0.38, tone: 0.45, room: 0.3, label: "OPEN HAT"),
            DrumRecipe(kind: .sub808, tune: E1, decay: 0.7, tone: 0.3, snap: 0.3, label: "SUB"),
            DrumRecipe(kind: .tambourine, tune: 0.95, decay: 0.24, room: 0.3, level: 0.6, label: "TAMB"),
            DrumRecipe(kind: .conga, tune: 210, decay: 0.24, snap: 0.5, room: 0.35, level: 0.65, label: "CONGA"),
            DrumRecipe(kind: .tomLow, tune: 90, decay: 0.45, tone: 0.3, room: 0.45, label: "TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 132, decay: 0.38, tone: 0.3, room: 0.45, label: "TOM HI"),
            DrumRecipe(kind: .crash, tune: 0.95, decay: 1.5, room: 0.35, level: 0.55, label: "CRASH")
        ])

    static let looseBreak = KitDefinition(
        id: "voice-loose-break", name: "LOOSE BREAK", style: .looseBreak, tempo: 96, bassHz: G1,
        pads: [
            DrumRecipe(kind: .kickAcoustic, tune: 60, decay: 0.34, tone: 0.45, snap: 0.5, drive: 0.2, room: 0.35, label: "KICK"),
            DrumRecipe(kind: .snareAcoustic, tune: 240, decay: 0.24, tone: 0.65, snap: 0.75, drive: 0.15, room: 0.35, label: "SNARE"),
            DrumRecipe(kind: .snareAcoustic, tune: 250, decay: 0.1, tone: 0.3, snap: 0.25, room: 0.3, level: 0.5, label: "GHOST"),
            DrumRecipe(kind: .rim, tune: 500, decay: 0.08, snap: 0.6, room: 0.3, label: "RIM"),
            DrumRecipe(kind: .hatAcousticClosed, tune: 1.0, decay: 0.065, tone: 0.5, room: 0.25, label: "HAT"),
            DrumRecipe(kind: .hatAcousticOpen, tune: 1.0, decay: 0.36, tone: 0.5, room: 0.25, label: "OPEN HAT"),
            DrumRecipe(kind: .sub808, tune: G1, decay: 0.7, tone: 0.3, snap: 0.3, label: "SUB"),
            DrumRecipe(kind: .shaker, tune: 0.95, decay: 0.1, tone: 0.45, level: 0.55, label: "SHAKER"),
            DrumRecipe(kind: .cowbell, tune: 590, decay: 0.2, room: 0.2, level: 0.5, label: "BELL"),
            DrumRecipe(kind: .tomLow, tune: 94, decay: 0.42, tone: 0.3, room: 0.35, label: "TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 140, decay: 0.36, tone: 0.3, room: 0.35, label: "TOM HI"),
            DrumRecipe(kind: .ride, tune: 1.0, decay: 1.3, tone: 0.5, room: 0.25, level: 0.5, label: "RIDE")
        ])

    static let heavyBreak = KitDefinition(
        id: "voice-heavy-break", name: "HEAVY BREAK", style: .heavyBreak, tempo: 72, bassHz: D1,
        pads: [
            DrumRecipe(kind: .kickAcoustic, tune: 52, decay: 0.5, tone: 0.35, snap: 0.6, drive: 0.3, room: 0.8, label: "KICK"),
            DrumRecipe(kind: .snareAcoustic, tune: 175, decay: 0.34, tone: 0.45, snap: 0.7, drive: 0.25, room: 0.85, label: "SNARE"),
            DrumRecipe(kind: .clap, tune: 0.9, decay: 0.34, tone: 0.35, snap: 0.5, room: 0.7, level: 0.7, label: "CLAP"),
            DrumRecipe(kind: .rim, tune: 380, decay: 0.1, snap: 0.5, room: 0.6, label: "RIM"),
            DrumRecipe(kind: .hatAcousticClosed, tune: 0.85, decay: 0.09, tone: 0.35, room: 0.55, label: "HAT"),
            DrumRecipe(kind: .hatAcousticOpen, tune: 0.85, decay: 0.55, tone: 0.35, room: 0.55, label: "OPEN HAT"),
            DrumRecipe(kind: .sub808, tune: D1, decay: 1.0, tone: 0.3, snap: 0.3, label: "SUB"),
            DrumRecipe(kind: .tambourine, tune: 0.9, decay: 0.3, room: 0.5, level: 0.55, label: "TAMB"),
            DrumRecipe(kind: .conga, tune: 180, decay: 0.3, snap: 0.5, room: 0.6, level: 0.6, label: "CONGA"),
            DrumRecipe(kind: .tomLow, tune: 78, decay: 0.6, tone: 0.3, room: 0.8, label: "TOM LO"),
            DrumRecipe(kind: .tomHigh, tune: 116, decay: 0.5, tone: 0.3, room: 0.8, label: "TOM HI"),
            DrumRecipe(kind: .crash, tune: 0.85, decay: 2.0, room: 0.6, level: 0.55, label: "CRASH")
        ])
}
