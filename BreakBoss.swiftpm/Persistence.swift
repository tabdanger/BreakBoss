// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Folders
//
// In the app these are in Files › On My iPhone/iPad › BreakBoss:
//   Samples   your own sounds (anything you put here shows up in the pad editor)
//   Kits      saved kits (.bbkit)
//   Presets   saved presets (.bbpreset)
//   Exports   rendered MIDI, mixes and stems
// The plug-in has its own private copy of these folders (iOS keeps plug-ins separate).

enum KnockFolders {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static var samples: URL { folder("Samples") }
    static var kits: URL { folder("Kits") }
    static var presets: URL { folder("Presets") }
    static var exports: URL { folder("Exports") }

    private static func folder(_ name: String) -> URL {
        let url = documents.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Audio files in Samples (subfolders included), sorted by name.
    static func sampleFiles() -> [URL] {
        let exts: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "flac", "aac"]
        guard let walker = FileManager.default.enumerator(at: samples, includingPropertiesForKeys: nil) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker where exts.contains(url.pathExtension.lowercased()) { out.append(url) }
        return out.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// A name that's safe as a file name.
    static func safe(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : String(cleaned.prefix(60))
    }
}

// MARK: - Everything on the faceplate, saved

struct KnockState: Codable, Equatable {
    var version = 1
    var mode: SoundMode = .modern
    var playMode: PlayMode = .loop
    var values: [String: Float] = [:]
    var bpm: Double = 140
    /// The factory kit the sounds and grooves come from.
    var kitID: String = KitLibrary.drumMastery.id
    /// What the KITS window shows (a saved kit's own name).
    var kitName: String = KitLibrary.drumMastery.name
    /// Set when the kit was loaded from (or saved as) one of your kits.
    var userKit: String?
    var soundSeed: UInt32 = 1
    var grooveSeed: UInt32 = 1
    var pads: [PadSettings] = Array(repeating: PadSettings(), count: Pad.count)
    /// Loops you edited or imported (nil = the generated one).
    var editedLoops: [PatternData?] = Array(repeating: nil, count: Pad.count)
    var presetName: String = "INIT"

    static func normalizedPads(_ source: [PadSettings]) -> [PadSettings] {
        var pads = Array(source.prefix(Pad.count))
        while pads.count < Pad.count { pads.append(PadSettings()) }
        for i in pads.indices {
            pads[i].level = pads[i].level.isFinite ? pads[i].level.clamped(0, 1) : 0.8
            pads[i].pan = pads[i].pan.isFinite ? pads[i].pan.clamped(-1, 1) : 0
            pads[i].tune = pads[i].tune.isFinite ? pads[i].tune.clamped(-24, 24) : 0
            pads[i].decay = pads[i].decay.isFinite ? pads[i].decay.clamped(0.05, 1) : 1
            pads[i].filter = pads[i].filter.isFinite ? pads[i].filter.clamped(0, 1) : 1
            if let file = pads[i].sampleFile,
               file.hasPrefix("/") || file.split(separator: "/").contains("..") { pads[i].sampleFile = nil }
        }
        return pads
    }

    /// A kit changes the raw sample collection and its generated grooves. Keep the current
    /// processing chain, including every pad's tone and envelope, when auditioning new sounds.
    /// Imported sample identities are cleared so every pad actually receives the new kit.
    func selectingKit(_ kit: KitDefinition) -> KnockState {
        var s = self
        s.kitID = kit.id
        s.kitName = kit.name
        s.userKit = nil
        s.soundSeed = 1
        s.grooveSeed = 1
        s.pads = Self.normalizedPads(s.pads)
        for i in s.pads.indices { s.pads[i].sampleFile = nil }
        s.editedLoops = Array(repeating: nil, count: Pad.count)
        if (s.values[KParam.tempoSync.id] ?? KParam.tempoSync.defaultValue) < 0.5 {
            s.bpm = kit.tempo
        }
        return s
    }

    func normalized() -> KnockState {
        var s = self
        s.version = 2
        s.bpm = s.bpm.isFinite ? s.bpm.clamped(40, 240) : 140
        s.pads = Self.normalizedPads(s.pads)
        s.editedLoops = Array(s.editedLoops.prefix(Pad.count))
        while s.editedLoops.count < Pad.count { s.editedLoops.append(nil) }
        for i in s.editedLoops.indices {
            guard var loop = s.editedLoops[i] else { continue }
            loop.lengthTicks = loop.lengthTicks.clamped(384, 3072)
            loop.events = Array(loop.events.prefix(4096)).filter {
                $0.pad >= 0 && Int($0.pad) < Pad.count && $0.tick >= 0 && $0.tick < loop.lengthTicks &&
                $0.velocity.isFinite && $0.semis.isFinite
            }
            for j in loop.events.indices {
                loop.events[j].velocity = loop.events[j].velocity.clamped(0, 1)
                loop.events[j].semis = loop.events[j].semis.clamped(-12, 24)
                loop.events[j].length = loop.events[j].length.clamped(0, 3072)
            }
            loop.sort(); s.editedLoops[i] = loop
        }
        for p in KParam.allCases {
            let value = s.values[p.id] ?? p.defaultValue
            let finite = value.isFinite ? value : p.defaultValue
            s.values[p.id] = p.steps.map { finite.rounded().clamped(0, Float($0 - 1)) } ?? finite.clamped(0, 1)
        }
        s.mode = SoundMode(rawValue: Int(s.values[KParam.soundMode.id] ?? 0)) ?? .modern
        s.playMode = (s.values[KParam.playMode.id] ?? 1) > 0.5 ? .loop : .oneShot
        return s
    }
}

/// A saved kit: which factory kit it started from, its sound variation, and your pads.
struct UserKit: Codable {
    var name: String
    var baseKitID: String
    var soundSeed: UInt32
    var pads: [PadSettings]
}

/// A saved preset: the whole faceplate (knobs, mode, kit, loops).
struct UserPreset: Codable {
    var name: String
    var state: KnockState
}

enum KnockStore {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    // Kits
    static func userKitNames() -> [String] {
        list(KnockFolders.kits, ext: "bbkit")
    }

    static func loadUserKit(_ name: String) -> UserKit? {
        let url = KnockFolders.kits.appendingPathComponent(KnockFolders.safe(name)).appendingPathExtension("bbkit")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UserKit.self, from: data)
    }

    @discardableResult
    static func saveUserKit(_ kit: UserKit) -> Bool {
        let url = KnockFolders.kits.appendingPathComponent(KnockFolders.safe(kit.name)).appendingPathExtension("bbkit")
        guard let data = try? encoder.encode(kit) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func deleteUserKit(_ name: String) {
        let url = KnockFolders.kits.appendingPathComponent(KnockFolders.safe(name)).appendingPathExtension("bbkit")
        try? FileManager.default.removeItem(at: url)
    }

    // Presets
    static func userPresetNames() -> [String] {
        list(KnockFolders.presets, ext: "bbpreset")
    }

    static func loadUserPreset(_ name: String) -> UserPreset? {
        let url = KnockFolders.presets.appendingPathComponent(KnockFolders.safe(name)).appendingPathExtension("bbpreset")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UserPreset.self, from: data)
    }

    @discardableResult
    static func saveUserPreset(_ preset: UserPreset) -> Bool {
        let url = KnockFolders.presets.appendingPathComponent(KnockFolders.safe(preset.name)).appendingPathExtension("bbpreset")
        guard let data = try? encoder.encode(preset) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func deleteUserPreset(_ name: String) {
        let url = KnockFolders.presets.appendingPathComponent(KnockFolders.safe(name)).appendingPathExtension("bbpreset")
        try? FileManager.default.removeItem(at: url)
    }

    private static func list(_ folder: URL, ext: String) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == ext }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

// MARK: - Factory presets

struct FactoryPreset {
    let name: String
    let mode: SoundMode
    let kitID: String
    /// FX/tuning overrides; omitted knobs use INIT, never the preceding preset's settings.
    let values: [KParam: Float]
    /// Complete pad control snapshot, separate from the kit's raw sample identities.
    let pads: [PadSettings]

    init(name: String, mode: SoundMode, kitID: String, values: [KParam: Float],
         pads: [PadSettings] = Array(repeating: PadSettings(), count: Pad.count)) {
        self.name = name; self.mode = mode; self.kitID = kitID; self.values = values
        self.pads = KnockState.normalizedPads(pads)
    }

    /// Factory presets choose a matching kit, mode, FX, master clipper and every pad control.
    /// Transport selection and host sync remain as set by the player/DAW.
    func applying(to source: KnockState) -> KnockState {
        var s = source.selectingKit(KitLibrary.kit(id: kitID))
        for p in KParam.allCases where p.isKnob || p == .clipper {
            s.values[p.id] = values[p] ?? p.defaultValue
        }
        s.mode = mode
        s.values[KParam.soundMode.id] = Float(mode.rawValue)
        s.pads = pads
        s.presetName = name
        return s.normalized()
    }
}

enum FactoryPresets {
    // These are authored recipes, not randomized aliases. Each preset has a different FX
    // snapshot and specific pad adjustments. The profiles provide sensible starting envelopes
    // for the 12 fixed drum roles; edits below tune each recipe to its own musical purpose.
    private enum PadShape {
        case modernPunch, modernSmooth, modernDry, memphis
        case vintageDry, vintageLive, vintageDust, vintageDisco
        case texturePerc, textureWash, textureCrush, textureGate
    }

    private struct PadEdit {
        var tune: Float? = nil
        var decay: Float? = nil
        var filter: Float? = nil
        var level: Float? = nil
        var pan: Float? = nil
        var reverse: Bool? = nil
    }

    private static func preset(_ name: String, _ mode: SoundMode, _ kit: String,
                               _ values: [KParam: Float], _ shape: PadShape,
                               _ edits: [Pad: PadEdit] = [:]) -> FactoryPreset {
        var pads = snapshot(shape)
        for (pad, edit) in edits {
            let i = pad.rawValue
            if let v = edit.tune { pads[i].tune = v }
            if let v = edit.decay { pads[i].decay = v }
            if let v = edit.filter { pads[i].filter = v }
            if let v = edit.level { pads[i].level = v }
            if let v = edit.pan { pads[i].pan = v }
            if let v = edit.reverse { pads[i].reverse = v }
        }
        return FactoryPreset(name: name, mode: mode, kitID: kit, values: values, pads: pads)
    }

    private static func snapshot(_ shape: PadShape) -> [PadSettings] {
        var pads = Array(repeating: PadSettings(), count: Pad.count)
        // Keep kick/sub centered; place auxiliary percussion around the stereo field.
        let levels: [Float] = [0.86, 0.82, 0.75, 0.71, 0.68, 0.65, 0.81, 0.66,
                               0.65, 0.73, 0.70, 0.59, 0.60, 0.58, 0.66, 0.56]
        let pans: [Float] = [0, 0, 0.04, -0.06, -0.12, 0.16, 0, -0.24,
                            0.26, -0.18, 0.18, 0.20, -0.30, 0.30, -0.10, 0.14]
        for i in pads.indices { pads[i].level = levels[i]; pads[i].pan = pans[i] }
        let tunes: [Float]
        let decays: [Float]
        let cutoff: Float
        switch shape {
        case .modernPunch:
            tunes = [0, 1, 0.5, 1, 1, 0.5, 0, 0.5, -0.5, 0, 2, 0, 1, 0, 0, 0]
            decays = [0.88, 0.76, 0.80, 0.72, 0.58, 0.66, 0.98, 0.72, 0.70, 0.84, 0.78, 0.72, 0.68, 0.72, 0.82, 0.72]
            cutoff = 1
        case .modernSmooth:
            tunes = [-0.5, -0.5, 0, -1, 0, 0, 0, -1, 0.5, -1, 1, -0.5, 0, -0.5, -1, 0]
            decays = [0.84, 0.88, 0.84, 0.86, 0.72, 0.82, 1, 0.82, 0.86, 0.90, 0.84, 0.92, 0.82, 0.86, 0.90, 0.92]
            cutoff = 0.97
        case .modernDry:
            tunes = [0.5, 2, 1, 2, 2, 1, 0, 1, 2, 0, 2, 1, 1, 1, 0, 2]
            decays = [0.72, 0.62, 0.58, 0.52, 0.42, 0.52, 0.78, 0.56, 0.54, 0.72, 0.64, 0.58, 0.50, 0.54, 0.68, 0.58]
            cutoff = 1
        case .memphis:
            tunes = [-1, 0.5, -1, 2, 2, -1, 0, -2, -3, -2, 1, -1, 1, -1, -2, -3]
            decays = [0.80, 0.68, 0.72, 0.60, 0.44, 0.60, 1, 0.66, 0.82, 0.84, 0.76, 0.70, 0.56, 0.68, 0.72, 0.80]
            cutoff = 0.94
        case .vintageDry:
            tunes = [-0.5, -1, -0.5, -1, -0.8, -0.8, 0, -1, -0.5, -1, 1, -0.8, -0.5, -0.5, -1, -1]
            decays = [0.82, 0.72, 0.72, 0.80, 0.72, 0.70, 0.88, 0.76, 0.74, 0.82, 0.78, 0.76, 0.76, 0.80, 0.82, 0.70]
            cutoff = 0.90
        case .vintageLive:
            tunes = [0, 0.5, 0, 0, -0.3, -0.3, 0, -0.5, 0.5, -1, 1, -0.3, 0, 0, 0, -0.5]
            decays = [0.96, 1, 0.90, 0.96, 0.94, 1, 0.90, 0.96, 0.96, 1, 1, 1, 0.96, 1, 1, 0.94]
            cutoff = 0.98
        case .vintageDust:
            tunes = [-1.5, -2, -1.5, -2, -1, -1, -1, -2, -1, -2, 0, -1.5, -1, -1, -2, -2]
            decays = [0.90, 0.84, 0.80, 0.86, 0.66, 0.74, 0.94, 0.82, 0.80, 0.90, 0.82, 0.82, 0.76, 0.80, 0.88, 0.84]
            cutoff = 0.80
        case .vintageDisco:
            tunes = [0.5, 1.5, 1, 1, 0.5, 0.5, 0, 1, 0.5, 0, 2, 0.5, 1, 1, 0, 1]
            decays = [0.78, 0.90, 0.92, 0.76, 0.72, 0.94, 0.76, 0.80, 0.86, 0.84, 0.82, 0.96, 0.82, 0.96, 0.88, 0.82]
            cutoff = 0.96
        case .texturePerc:
            tunes = [-1, 0, 2, -2, 3, 1, 0, -3, 4, -2, 3, -1, 3, -1, -2, 5]
            decays = [0.76, 0.74, 0.64, 0.72, 0.56, 0.72, 0.90, 0.90, 0.84, 0.86, 0.82, 0.76, 0.86, 0.88, 0.94, 0.82]
            cutoff = 0.86
        case .textureWash:
            tunes = [-3, -4, -3, -5, -2, -2, 0, -5, -2, -4, -1, -4, -2, -3, -4, -7]
            decays = [0.92, 1, 1, 0.94, 0.84, 1, 1, 1, 1, 1, 1, 1, 0.96, 1, 1, 1]
            cutoff = 0.74
        case .textureCrush:
            tunes = [-2, 3, -4, 4, 5, -3, 0, -5, 7, -4, 5, -2, 4, -3, -4, -7]
            decays = [0.72, 0.66, 0.60, 0.64, 0.40, 0.64, 0.94, 0.70, 0.66, 0.78, 0.70, 0.68, 0.58, 0.66, 0.78, 0.82]
            cutoff = 0.88
        case .textureGate:
            tunes = [0, -1, 1, -1, 1, -1, 0, -2, 2, -2, 2, -1, 2, -1, -2, -3]
            decays = [0.70, 0.52, 0.48, 0.58, 0.40, 0.54, 0.86, 0.56, 0.54, 0.60, 0.56, 0.48, 0.48, 0.54, 0.64, 0.56]
            cutoff = 0.94
        }
        for i in pads.indices {
            pads[i].tune = tunes[i]; pads[i].decay = decays[i]; pads[i].filter = cutoff
        }
        // Preserve fundamental weight even in darker profiles; hats/cymbals carry the grain.
        pads[Pad.kick.rawValue].filter = max(cutoff, 0.94)
        pads[Pad.bass808.rawValue].filter = 1
        return pads
    }

    // 20 Modern: clean transients, electronic low end, sparse trap and polished R&B pockets.
    static let all: [FactoryPreset] = [
        preset("KNOCK HARD", .modern, "modern-trap",
               [.boost: 0.70, .punch: 0.60, .grit: 0.25, .shine: 0.35, .clipDrive: 0.45, .tighten: 0.10, .output: 0.69], .modernPunch,
               [.kick: .init(tune: -0.5, decay: 0.92), .snare: .init(tune: 1.5), .hat: .init(decay: 0.45)]),
        preset("2300 TRAP", .modern, "atl-trap",
               [.boost: 0.62, .punch: 0.46, .grit: 0.12, .shine: 0.28, .clipDrive: 0.38, .tighten: 0.22, .bounce: 0.08, .output: 0.71], .modernDry,
               [.bass808: .init(decay: 1), .snare: .init(tune: -0.5, decay: 0.75), .perc2: .init(tune: -3)]),
        preset("MEMPHIS AFTER DARK", .modern, "memphis-trap",
               [.boost: 0.68, .punch: 0.28, .grit: 0.38, .filter: 0.92, .clipDrive: 0.46, .analogEQ: 0.20, .velocity: 0.82, .output: 0.68], .memphis,
               [.perc2: .init(tune: -5, decay: 0.90), .hat: .init(tune: 3), .clap: .init(filter: 0.90)]),
        preset("SIX SIDE SPACE", .modern, "six-side",
               [.boost: 0.53, .punch: 0.20, .shine: 0.18, .filter: 0.94, .analogEQ: 0.16, .clipDrive: 0.24, .bounce: 0.12, .output: 0.73], .modernSmooth,
               [.rim: .init(decay: 0.62, pan: -0.18), .openHat: .init(decay: 0.88), .perc1: .init(level: 0.58)]),
        preset("TRAP SOUL", .modern, "trap-soul",
               [.boost: 0.48, .punch: 0.24, .bounce: 0.31, .filter: 0.93, .analogEQ: 0.28, .clipDrive: 0.22, .shine: 0.12, .output: 0.74], .modernSmooth,
               [.snare: .init(tune: -1.5), .hat: .init(filter: 0.91, pan: -0.18), .bass808: .init(decay: 0.92)]),
        preset("R&B GLASS", .modern, "modern-rnb",
               [.boost: 0.36, .punch: 0.16, .shine: 0.42, .analogEQ: 0.18, .clipDrive: 0.16, .bounce: 0.24, .velocity: 0.90, .output: 0.76], .modernSmooth,
               [.clap: .init(tune: 1, filter: 1), .hat: .init(tune: 1.5, filter: 1), .cymbal: .init(level: 0.54)]),
        preset("SLAP CITY", .modern, "bay-slap",
               [.boost: 0.60, .punch: 0.50, .analogEQ: 0.40, .tighten: 0.30, .clipDrive: 0.40, .bounce: 0.26, .output: 0.70], .modernPunch,
               [.clap: .init(tune: 1.5, level: 0.80), .bass808: .init(decay: 0.76), .rim: .init(tune: 2)]),
        preset("BOUNCE CLUB", .modern, "west-bounce",
               [.boost: 0.50, .punch: 0.35, .shine: 0.40, .bounce: 0.20, .clipDrive: 0.35, .velocity: 0.64, .output: 0.72], .modernPunch,
               [.kick: .init(decay: 0.75), .clap: .init(decay: 0.90), .openHat: .init(pan: 0.25)]),
        preset("DIGITAL HEAT", .modern, "drum-mastery",
               [.boost: 0.66, .punch: 0.54, .shine: 0.24, .grit: 0.18, .clipDrive: 0.52, .tighten: 0.16, .velocity: 0.68, .output: 0.66], .modernPunch,
               [.kick: .init(level: 0.88), .snare: .init(tune: 2, decay: 0.66), .bass808: .init(decay: 0.88)]),
        preset("TIGHT POCKET", .modern, "2000s-rnb",
               [.boost: 0.40, .punch: 0.32, .tighten: 0.42, .shine: 0.26, .bounce: 0.35, .clipDrive: 0.20, .analogEQ: 0.12, .output: 0.75], .modernDry,
               [.rim: .init(tune: 1, level: 0.76), .perc1: .init(pan: -0.32), .perc2: .init(pan: 0.34)]),
        preset("NIGHTS IN ATLANTA", .modern, "atl-trap",
               [.boost: 0.57, .punch: 0.38, .grit: 0.10, .shine: 0.22, .bounce: 0.03, .clipDrive: 0.30, .tighten: 0.26, .output: 0.72], .modernDry,
               [.hat: .init(tune: 3, decay: 0.34), .openHat: .init(decay: 0.76), .bass808: .init(decay: 1)]),
        preset("ROLLER COASTER", .modern, "modern-trap",
               [.boost: 0.58, .punch: 0.42, .shine: 0.38, .bounce: 0.16, .clipDrive: 0.34, .velocity: 0.94, .tighten: 0.18, .output: 0.72], .modernDry,
               [.hat: .init(tune: 4, decay: 0.32), .rim: .init(tune: 3), .perc2: .init(tune: 5, pan: 0.36)]),
        preset("CLEAN ROOM", .modern, "modern-rnb",
               [.boost: 0.32, .punch: 0.22, .shine: 0.22, .clipDrive: 0.08, .clipper: 0, .bounce: 0.15, .velocity: 1, .output: 0.72], .modernSmooth,
               [.kick: .init(tune: 0, filter: 1), .snare: .init(tune: 0, filter: 1), .clap: .init(filter: 1)]),
        preset("VELVET TRANSIENTS", .modern, "modern-rnb",
               [.boost: 0.38, .punch: 0.10, .analogEQ: 0.32, .filter: 0.94, .shine: 0.08, .bounce: 0.38, .clipDrive: 0.14, .output: 0.76], .modernSmooth,
               [.snare: .init(tune: -2, filter: 0.88), .rim: .init(filter: 0.90), .cymbal: .init(filter: 0.86)]),
        preset("LOW END PRESSURE", .modern, "memphis-trap",
               [.boost: 0.76, .punch: 0.36, .grit: 0.26, .clipDrive: 0.48, .analogEQ: 0.26, .shine: 0.08, .output: 0.65], .memphis,
               [.kick: .init(decay: 0.70, level: 0.84), .bass808: .init(decay: 1, level: 0.86), .clap: .init(level: 0.70)]),
        preset("NEON SNAP", .modern, "2000s-rnb",
               [.boost: 0.42, .punch: 0.28, .shine: 0.50, .bounce: 0.27, .tighten: 0.28, .clipDrive: 0.24, .analogEQ: 0.14, .output: 0.74], .modernDry,
               [.rim: .init(tune: 4, level: 0.80), .snare: .init(decay: 0.72), .perc1: .init(tune: 2, filter: 1)]),
        preset("OFF GRID FUTURE", .modern, "toronto-weird",
               [.boost: 0.55, .punch: 0.25, .grit: 0.20, .filter: 0.90, .shine: 0.18, .bounce: 0.42, .clipDrive: 0.32, .output: 0.72], .memphis,
               [.perc1: .init(tune: -7, pan: -0.40), .perc2: .init(tune: 7, pan: 0.40), .rim: .init(tune: -3)]),
        preset("AFTER HOURS", .modern, "trap-soul",
               [.boost: 0.44, .punch: 0.12, .filter: 0.88, .analogEQ: 0.22, .bounce: 0.44, .clipDrive: 0.18, .velocity: 0.92, .output: 0.76], .modernSmooth,
               [.hat: .init(decay: 0.66, filter: 0.84), .snare: .init(tune: -2.5), .openHat: .init(level: 0.58)]),
        preset("WIDE BLOCK", .modern, "bay-slap",
               [.boost: 0.54, .punch: 0.44, .analogEQ: 0.30, .shine: 0.28, .bounce: 0.32, .clipDrive: 0.36, .tighten: 0.22, .output: 0.72], .modernPunch,
               [.perc1: .init(pan: -0.46), .perc2: .init(pan: 0.46), .clap: .init(tune: -0.5, decay: 0.88)]),
        preset("RADIO PUNCH", .modern, "west-bounce",
               [.boost: 0.46, .punch: 0.48, .shine: 0.32, .analogEQ: 0.24, .clipDrive: 0.28, .tighten: 0.32, .velocity: 0.62, .output: 0.73], .modernPunch,
               [.kick: .init(decay: 0.78), .snare: .init(tune: 2.5, level: 0.84), .cymbal: .init(decay: 0.66)]),

        // 21 Vintage: acoustic breaks, soul, classic drum machines and restrained vinyl/tape dirt.
        preset("OLD HEAD", .vintage, "boom-bap",
               [.boost: 0.54, .punch: 0.24, .grit: 0.42, .drive: 0.30, .noise: 0.20, .filter: 0.84, .bounce: 0.40, .analogEQ: 0.28, .clipDrive: 0.28, .output: 0.70], .vintageDust,
               [.snare: .init(tune: -1, decay: 0.78), .hat: .init(filter: 0.78), .kick: .init(decay: 0.84)]),
        preset("ANALOG OLDIES", .vintage, "live-soul",
               [.boost: 0.42, .punch: 0.12, .grit: 0.24, .drive: 0.28, .noise: 0.16, .filter: 0.90, .analogEQ: 0.38, .bounce: 0.26, .clipDrive: 0.18, .output: 0.73], .vintageLive,
               [.snare: .init(tune: -1.5, filter: 0.90), .cymbal: .init(filter: 0.86), .bass808: .init(level: 0.72)]),
        preset("IS THAT DISCO?", .vintage, "funk-break",
               [.boost: 0.46, .punch: 0.34, .analogEQ: 0.28, .shine: 0.32, .drive: 0.14, .noise: 0.05, .bounce: 0.04, .clipDrive: 0.20, .output: 0.74], .vintageDisco,
               [.openHat: .init(decay: 1, level: 0.70), .perc2: .init(filter: 1, level: 0.67), .snare: .init(tune: 2)]),
        preset("DUSTY TAPE", .vintage, "west-90s",
               [.boost: 0.50, .grit: 0.30, .noise: 0.24, .filter: 0.82, .bounce: 0.30, .drive: 0.34, .analogEQ: 0.22, .clipDrive: 0.22, .output: 0.72], .vintageDust,
               [.clap: .init(tune: -2.5), .rim: .init(filter: 0.76), .cymbal: .init(filter: 0.72)]),
        preset("SOUL SAMPLER", .vintage, "neo-soul",
               [.boost: 0.40, .bounce: 0.55, .noise: 0.12, .tighten: 0.20, .analogEQ: 0.30, .grit: 0.16, .drive: 0.20, .clipDrive: 0.16, .output: 0.75], .vintageDry,
               [.rim: .init(tune: -2, level: 0.75), .hat: .init(decay: 0.78), .perc2: .init(pan: -0.22)]),
        preset("SUNDAY CHOPS", .vintage, "gospel-chops",
               [.boost: 0.45, .punch: 0.40, .analogEQ: 0.50, .shine: 0.20, .drive: 0.10, .clipDrive: 0.18, .velocity: 1, .output: 0.74], .vintageLive,
               [.snare: .init(tune: 1.5), .tomHigh: .init(tune: 3), .cymbal: .init(level: 0.62)]),
        preset("BREAK ROOM", .vintage, "funk-break",
               [.boost: 0.60, .grit: 0.35, .punch: 0.30, .clipDrive: 0.40, .drive: 0.24, .noise: 0.08, .bounce: 0.18, .output: 0.69], .vintageLive,
               [.kick: .init(decay: 0.86), .snare: .init(tune: -0.5), .clap: .init(level: 0.66)]),
        preset("70S POCKET", .vintage, "live-soul",
               [.boost: 0.38, .punch: 0.16, .analogEQ: 0.32, .filter: 0.92, .drive: 0.18, .noise: 0.06, .bounce: 0.34, .clipDrive: 0.12, .output: 0.76], .vintageDry,
               [.kick: .init(tune: -1.5, decay: 0.74), .snare: .init(decay: 0.66), .openHat: .init(decay: 0.82)]),
        preset("90S BASEMENT", .vintage, "boom-bap",
               [.boost: 0.58, .punch: 0.32, .grit: 0.32, .drive: 0.26, .noise: 0.14, .filter: 0.88, .bounce: 0.48, .clipDrive: 0.30, .output: 0.71], .vintageDry,
               [.snare: .init(tune: -1.5, level: 0.85), .hat: .init(filter: 0.82), .kick: .init(decay: 0.90)]),
        preset("SIDE A SOUL", .vintage, "dirty-soul",
               [.boost: 0.42, .punch: 0.08, .grit: 0.28, .drive: 0.32, .noise: 0.18, .filter: 0.86, .analogEQ: 0.26, .bounce: 0.60, .clipDrive: 0.18, .output: 0.74], .vintageDust,
               [.rim: .init(tune: -3, level: 0.74), .perc1: .init(pan: -0.34), .cymbal: .init(decay: 0.92)]),
        preset("RIMSHOT SESSION", .vintage, "vintage-rnb",
               [.boost: 0.34, .punch: 0.18, .analogEQ: 0.34, .shine: 0.12, .drive: 0.14, .bounce: 0.44, .noise: 0.04, .clipDrive: 0.12, .output: 0.76], .vintageDry,
               [.rim: .init(tune: 1.5, filter: 0.95, level: 0.80), .snare: .init(level: 0.73), .hat: .init(decay: 0.82)]),
        preset("R&B ON WAX", .vintage, "vintage-rnb",
               [.boost: 0.36, .punch: 0.10, .analogEQ: 0.40, .filter: 0.90, .drive: 0.22, .grit: 0.14, .bounce: 0.50, .noise: 0.10, .clipDrive: 0.14, .output: 0.75], .vintageLive,
               [.snare: .init(tune: -2), .clap: .init(filter: 0.86, level: 0.68), .perc1: .init(pan: -0.40)]),
        preset("LOOSE VINYL", .vintage, "loose-break",
               [.boost: 0.44, .punch: 0.12, .grit: 0.26, .drive: 0.28, .noise: 0.16, .filter: 0.88, .bounce: 0.62, .velocity: 1, .clipDrive: 0.16, .output: 0.74], .vintageLive,
               [.kick: .init(tune: -1), .hat: .init(tune: -1.5, filter: 0.88), .tomLow: .init(decay: 0.96)]),
        preset("FLOOR TOM FUNK", .vintage, "funk-break",
               [.boost: 0.48, .punch: 0.26, .analogEQ: 0.36, .drive: 0.20, .grit: 0.12, .bounce: 0.24, .clipDrive: 0.22, .output: 0.73], .vintageLive,
               [.tomLow: .init(tune: -3, level: 0.82), .tomHigh: .init(tune: 0, level: 0.78), .snare: .init(decay: 0.88)]),
        preset("LIVE FEEL BREAK", .vintage, "heavy-break",
               [.boost: 0.50, .punch: 0.22, .analogEQ: 0.22, .grit: 0.18, .drive: 0.22, .bounce: 0.12, .clipDrive: 0.26, .velocity: 1, .output: 0.72], .vintageLive,
               [.kick: .init(tune: -2), .snare: .init(tune: -1, decay: 0.96), .cymbal: .init(level: 0.56)]),
        preset("SAMPLE SHOP", .vintage, "west-end",
               [.boost: 0.48, .punch: 0.28, .analogEQ: 0.30, .grit: 0.20, .drive: 0.18, .noise: 0.08, .bounce: 0.32, .clipDrive: 0.24, .output: 0.73], .vintageDry,
               [.clap: .init(tune: 0.5, level: 0.79), .bass808: .init(decay: 0.76), .hat: .init(filter: 0.94)]),
        preset("DOWNTEMPO GRAIN", .vintage, "lo-fi",
               [.boost: 0.32, .punch: 0.06, .grit: 0.34, .drive: 0.30, .noise: 0.20, .filter: 0.78, .bounce: 0.66, .analogEQ: 0.20, .clipDrive: 0.12, .output: 0.75], .vintageDust,
               [.snare: .init(tune: -3), .hat: .init(decay: 0.60, filter: 0.74), .cymbal: .init(level: 0.52)]),
        preset("TAPE DECK 78", .vintage, "lo-fi",
               [.boost: 0.36, .punch: 0.14, .grit: 0.22, .drive: 0.42, .noise: 0.12, .filter: 0.84, .bounce: 0.54, .analogEQ: 0.26, .clipDrive: 0.18, .output: 0.74], .vintageDust,
               [.kick: .init(tune: -2, decay: 0.86), .rim: .init(tune: -4), .openHat: .init(filter: 0.80)]),
        preset("POLISHED SOUL", .vintage, "gospel-chops",
               [.boost: 0.36, .punch: 0.28, .analogEQ: 0.32, .shine: 0.26, .drive: 0.04, .noise: 0, .grit: 0, .clipDrive: 0.08, .velocity: 1, .output: 0.76], .vintageLive,
               [.kick: .init(tune: 0.5), .snare: .init(tune: 1, filter: 1), .cymbal: .init(filter: 1)]),
        preset("WEST COAST CRATE", .vintage, "west-90s",
               [.boost: 0.54, .punch: 0.20, .analogEQ: 0.38, .grit: 0.16, .drive: 0.24, .bounce: 0.36, .shine: 0.10, .noise: 0.06, .clipDrive: 0.24, .output: 0.72], .vintageDry,
               [.clap: .init(tune: -1, decay: 0.88), .bass808: .init(decay: 0.70), .perc2: .init(tune: -3)]),
        preset("LATE SOUL", .vintage, "neo-soul",
               [.boost: 0.34, .punch: 0.04, .analogEQ: 0.28, .drive: 0.16, .filter: 0.88, .bounce: 0.58, .grit: 0.10, .noise: 0.04, .clipDrive: 0.10, .output: 0.76], .vintageLive,
               [.snare: .init(tune: -2.5, decay: 0.92), .rim: .init(level: 0.78), .hat: .init(filter: 0.86)]),

        // 20 Texture: experimental percussion, dark filtering, resampling, delay and gated space.
        preset("LO-FI HAZE", .texture, "resampled-textures",
               [.boost: 0.30, .noise: 0.18, .filter: 0.76, .bounce: 0.45, .grit: 0.15, .resample: 0.52, .instability: 0.46, .textureDelay: 0.16, .gatedReverb: 0.20, .drive: 0.16, .clipDrive: 0.12, .output: 0.74], .textureWash,
               [.snare: .init(tune: -3), .hat: .init(filter: 0.70), .perc2: .init(tune: -5, level: 0.50)]),
        preset("GATED DREAM", .texture, "heavy-break",
               [.punch: 0.50, .boost: 0.50, .analogEQ: 0.30, .resample: 0.14, .instability: 0.10, .textureDelay: 0.12, .gatedReverb: 0.78, .drive: 0.12, .clipDrive: 0.22, .output: 0.70], .textureGate,
               [.snare: .init(decay: 0.62, level: 0.84), .clap: .init(decay: 0.56), .cymbal: .init(decay: 0.40)]),
        preset("WARPED TRAP", .texture, "dark-experimental",
               [.boost: 0.60, .punch: 0.40, .grit: 0.20, .clipDrive: 0.40, .resample: 0.46, .instability: 0.38, .textureDelay: 0.24, .gatedReverb: 0.26, .drive: 0.24, .filter: 0.94, .output: 0.68], .textureCrush,
               [.bass808: .init(decay: 1), .hat: .init(tune: 5, decay: 0.34), .perc2: .init(tune: 7)]),
        preset("UNDERWATER", .texture, "resampled-textures",
               [.boost: 0.32, .filter: 0.54, .analogEQ: 0.18, .resample: 0.22, .instability: 0.30, .textureDelay: 0.42, .gatedReverb: 0.56, .drive: 0.08, .clipDrive: 0.10, .output: 0.76], .textureWash,
               [.snare: .init(filter: 0.56), .cymbal: .init(filter: 0.52, reverse: true), .perc2: .init(tune: -12, filter: 0.50)]),
        preset("FILTERED PERCS", .texture, "perc-loops",
               [.boost: 0.28, .punch: 0.18, .filter: 0.78, .bounce: 0.32, .resample: 0.18, .instability: 0.08, .textureDelay: 0.26, .gatedReverb: 0.14, .drive: 0.10, .clipDrive: 0.12, .output: 0.75], .texturePerc,
               [.perc1: .init(filter: 0.68, level: 0.76), .perc2: .init(filter: 0.74, level: 0.74), .tomLow: .init(filter: 0.80, level: 0.75)]),
        preset("WORLDWIDE", .texture, "world-latin",
               [.boost: 0.32, .punch: 0.12, .analogEQ: 0.20, .bounce: 0.20, .resample: 0.08, .instability: 0.06, .textureDelay: 0.22, .gatedReverb: 0.20, .drive: 0.06, .clipDrive: 0.10, .output: 0.76], .texturePerc,
               [.perc1: .init(tune: -1, filter: 0.98), .perc2: .init(tune: 3, filter: 0.98), .tomLow: .init(filter: 0.96, level: 0.78)]),
        preset("AFRO ECHO", .texture, "afrobeats",
               [.boost: 0.34, .punch: 0.18, .bounce: 0.27, .shine: 0.12, .resample: 0.12, .instability: 0.14, .textureDelay: 0.42, .gatedReverb: 0.12, .drive: 0.08, .clipDrive: 0.14, .output: 0.74], .texturePerc,
               [.perc1: .init(filter: 0.96, pan: -0.38), .rim: .init(tune: 1), .perc2: .init(pan: 0.38)]),
        preset("AMAPIANO DUB", .texture, "amapiano",
               [.boost: 0.48, .punch: 0.20, .bounce: 0.38, .filter: 0.90, .resample: 0.08, .instability: 0.08, .textureDelay: 0.28, .gatedReverb: 0.22, .drive: 0.10, .clipDrive: 0.20, .output: 0.73], .texturePerc,
               [.bass808: .init(decay: 0.78, level: 0.84), .rim: .init(tune: 2, decay: 0.64), .perc1: .init(filter: 0.94)]),
        preset("GLASS WORLDS", .texture, "shakers",
               [.boost: 0.24, .shine: 0.30, .filter: 0.98, .resample: 0.10, .instability: 0.16, .textureDelay: 0.46, .gatedReverb: 0.38, .drive: 0.04, .clipDrive: 0.08, .output: 0.74], .textureWash,
               [.perc1: .init(tune: 5, filter: 1, pan: -0.46), .perc2: .init(tune: 3, filter: 1, pan: 0.46), .tomHigh: .init(tune: 7)]),
        preset("DOWNSAMPLED FUTURE", .texture, "dark-experimental",
               [.boost: 0.42, .punch: 0.32, .grit: 0.26, .resample: 0.78, .instability: 0.24, .textureDelay: 0.18, .gatedReverb: 0.18, .drive: 0.28, .clipDrive: 0.30, .filter: 0.90, .output: 0.70], .textureCrush,
               [.snare: .init(tune: 5), .hat: .init(tune: 7, decay: 0.28), .perc1: .init(tune: -7)]),
        preset("WET CONCRETE", .texture, "dark-experimental",
               [.boost: 0.44, .punch: 0.24, .grit: 0.22, .filter: 0.82, .resample: 0.40, .instability: 0.18, .textureDelay: 0.30, .gatedReverb: 0.66, .drive: 0.20, .clipDrive: 0.28, .output: 0.69], .textureGate,
               [.kick: .init(tune: -3, decay: 0.84), .snare: .init(tune: -4, decay: 0.70), .perc2: .init(reverse: true)]),
        preset("CRUSHED VELVET", .texture, "resampled-textures",
               [.boost: 0.32, .analogEQ: 0.32, .filter: 0.86, .bounce: 0.48, .resample: 0.62, .instability: 0.36, .textureDelay: 0.20, .gatedReverb: 0.28, .drive: 0.22, .noise: 0.10, .clipDrive: 0.18, .output: 0.74], .textureCrush,
               [.snare: .init(tune: -3, filter: 0.80), .rim: .init(tune: -5), .cymbal: .init(filter: 0.76)]),
        preset("OCEAN ROOM", .texture, "world-latin",
               [.boost: 0.26, .filter: 0.70, .resample: 0.16, .instability: 0.22, .textureDelay: 0.50, .gatedReverb: 0.62, .drive: 0.06, .clipDrive: 0.08, .output: 0.74], .textureWash,
               [.perc1: .init(tune: -5, filter: 0.66), .perc2: .init(tune: -3, filter: 0.70), .cymbal: .init(reverse: true)]),
        preset("HALF STEP TAPE", .texture, "dark-experimental",
               [.boost: 0.48, .punch: 0.16, .filter: 0.88, .bounce: 0.18, .resample: 0.34, .instability: 0.54, .textureDelay: 0.34, .gatedReverb: 0.32, .drive: 0.28, .noise: 0.12, .clipDrive: 0.24, .output: 0.72], .textureWash,
               [.kick: .init(tune: -2, decay: 0.82), .snare: .init(tune: -5), .bass808: .init(decay: 0.94)]),
        preset("AIR GATE", .texture, "shakers",
               [.boost: 0.20, .punch: 0.28, .shine: 0.26, .resample: 0.06, .instability: 0.04, .textureDelay: 0.10, .gatedReverb: 0.64, .drive: 0.04, .clipDrive: 0.10, .output: 0.75], .textureGate,
               [.perc1: .init(tune: 3, filter: 1, level: 0.72), .perc2: .init(filter: 1, level: 0.68), .openHat: .init(decay: 0.44)]),
        preset("LATIN GHOSTS", .texture, "world-latin",
               [.boost: 0.28, .bounce: 0.42, .filter: 0.90, .resample: 0.20, .instability: 0.18, .textureDelay: 0.38, .gatedReverb: 0.24, .drive: 0.12, .clipDrive: 0.12, .output: 0.75], .texturePerc,
               [.perc1: .init(tune: -4, level: 0.78), .perc2: .init(tune: 5, pan: 0.42), .rim: .init(level: 0.76)]),
        preset("PHASED PULSE", .texture, "perc-loops",
               [.boost: 0.30, .punch: 0.22, .bounce: 0.16, .resample: 0.30, .instability: 0.66, .textureDelay: 0.28, .gatedReverb: 0.16, .drive: 0.14, .clipDrive: 0.14, .output: 0.74], .texturePerc,
               [.perc1: .init(tune: -7, pan: -0.48), .perc2: .init(tune: 7, pan: 0.48), .tomHigh: .init(decay: 0.94)]),
        preset("SLOW MOTION", .texture, "world-latin",
               [.boost: 0.30, .filter: 0.80, .bounce: 0.54, .resample: 0.28, .instability: 0.40, .textureDelay: 0.44, .gatedReverb: 0.42, .drive: 0.12, .clipDrive: 0.10, .output: 0.74], .textureWash,
               [.perc2: .init(tune: -7), .perc1: .init(tune: -7), .cymbal: .init(tune: -5, reverse: true)]),
        preset("CABIN NOISE", .texture, "resampled-textures",
               [.boost: 0.24, .filter: 0.74, .noise: 0.28, .grit: 0.18, .resample: 0.44, .instability: 0.48, .textureDelay: 0.14, .gatedReverb: 0.24, .drive: 0.18, .clipDrive: 0.10, .output: 0.72], .textureWash,
               [.hat: .init(filter: 0.68, level: 0.60), .perc2: .init(tune: -9, reverse: true), .rim: .init(filter: 0.72)]),
        preset("DRY EXPERIMENT", .texture, "dark-experimental",
               [.boost: 0.36, .punch: 0.30, .grit: 0.28, .filter: 0.96, .resample: 0.64, .instability: 0.12, .textureDelay: 0, .gatedReverb: 0, .drive: 0.26, .clipDrive: 0.24, .output: 0.72], .textureCrush,
               [.snare: .init(tune: 4, decay: 0.54), .hat: .init(decay: 0.30), .perc2: .init(tune: 12, decay: 0.60)])
    ]
}
