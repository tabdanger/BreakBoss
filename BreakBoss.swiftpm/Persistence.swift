// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Folders
//
// In the app these are in Files › On My iPad › BreakBoss:
//   Samples   your own sounds (anything you put here shows up in the pad editor)
//   Kits      saved kits (.bbkit)
//   Presets   saved presets (.bbpreset)
//   Exports   rendered MIDI, mixes and stems
// The plug-in has its own private copy of these folders (iPadOS keeps plug-ins separate).

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
    let values: [KParam: Float]
}

enum FactoryPresets {
    static let all: [FactoryPreset] = [
        FactoryPreset(name: "KNOCK HARD", mode: .modern, kitID: "modern-trap",
                      values: [.boost: 0.7, .punch: 0.6, .grit: 0.25, .shine: 0.35, .clipDrive: 0.45, .tighten: 0.1]),
        FactoryPreset(name: "SLAP CITY", mode: .modern, kitID: "bay-slap",
                      values: [.boost: 0.6, .punch: 0.5, .analogEQ: 0.4, .tighten: 0.3, .clipDrive: 0.4]),
        FactoryPreset(name: "BOUNCE CLUB", mode: .modern, kitID: "west-bounce",
                      values: [.boost: 0.5, .punch: 0.35, .shine: 0.4, .bounce: 0.2, .clipDrive: 0.35]),
        FactoryPreset(name: "DUSTY TAPE", mode: .vintage, kitID: "west-90s",
                      values: [.boost: 0.5, .grit: 0.3, .noise: 0.35, .filter: 0.82, .bounce: 0.3]),
        FactoryPreset(name: "SOUL SAMPLER", mode: .vintage, kitID: "neo-soul",
                      values: [.boost: 0.4, .bounce: 0.55, .noise: 0.25, .tighten: 0.2, .analogEQ: 0.3]),
        FactoryPreset(name: "SUNDAY CHOPS", mode: .vintage, kitID: "gospel-chops",
                      values: [.boost: 0.45, .punch: 0.4, .analogEQ: 0.5, .shine: 0.2]),
        FactoryPreset(name: "BREAK ROOM", mode: .vintage, kitID: "funk-break",
                      values: [.boost: 0.6, .grit: 0.35, .punch: 0.3, .clipDrive: 0.4]),
        FactoryPreset(name: "LO-FI HAZE", mode: .texture, kitID: "neo-soul",
                      values: [.noise: 0.4, .filter: 0.72, .bounce: 0.45, .grit: 0.15]),
        FactoryPreset(name: "GATED DREAM", mode: .texture, kitID: "heavy-break",
                      values: [.punch: 0.5, .boost: 0.5, .analogEQ: 0.3]),
        FactoryPreset(name: "WARPED TRAP", mode: .texture, kitID: "modern-trap",
                      values: [.boost: 0.6, .punch: 0.4, .grit: 0.2, .clipDrive: 0.4])
    ]
}
