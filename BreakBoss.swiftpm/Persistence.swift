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

/// Build 42 saved its first rack with this shape. Retained only for decoding those projects.
struct WorkspaceChannel: Codable, Equatable, Identifiable {
    var id: UUID
    var pad: Int
    var soundID: String
    var name: String
    var category: String
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
    /// The groove family the patterns come from. Set by PRESETS (patterns); KITS never change it.
    /// nil (older saves) = the kit's own style.
    var patternStyle: GrooveStyle? = nil
    /// The preset's own pattern (PRESETS load one). The 12 loops are built from it; nil = the
    /// groove generator's patterns for patternStyle.
    var basePattern: PatternData? = nil
    /// Drum roll channel MUTE / SOLO (index = pad).
    var mutedPads: [Bool]? = nil
    var soloPads: [Bool]? = nil
    var pads: [PadSettings] = Array(repeating: PadSettings(), count: RackLimits.maxChannels)
    /// Visible rows, in display order. nil migrates the original twelve drum channels.
    var rackChannels: [RackChannel]? = nil
    /// Compatibility with build 42. An empty array represents an intentionally empty rack.
    var workspaceChannels: [WorkspaceChannel]? = nil
    /// Loops you edited or imported (nil = the generated one).
    var editedLoops: [PatternData?] = Array(repeating: nil, count: Pad.count)
    var presetName: String = "INIT"
    /// Which live MIDI notes play the pads (a controller setting, so presets keep the current one).
    var midiMap: MIDIPadMap? = nil
    var midiCustomNotes: [Int]? = nil
    /// Piano roll SNAP TO SCALE: key (0 = C), FL scale name, on/off.
    var scaleRoot: Int? = nil
    var scaleName: String? = nil
    var snapToScale: Bool? = nil
    /// MIDI OUT (multi-out): send the pattern's hits to external gear, each drum channel on its
    /// own MIDI channel (-1 = not sent) and note. nil = defaults (channels 1-12, notes 36-47).
    /// Home-screen dice: per pad, which kit's stock sound plays ("kitID"), nil = the kit's own.
    var stockPicks: [String?]? = nil
    var midiOut: Bool? = nil
    var midiOutChannels: [Int]? = nil
    var midiOutNotes: [Int]? = nil

    static func normalizedPads(_ source: [PadSettings]) -> [PadSettings] {
        var pads = Array(source.prefix(RackLimits.maxChannels))
        while pads.count < RackLimits.maxChannels { pads.append(PadSettings()) }
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

    /// A kit changes its original drum sounds. Added rows, patterns, tempo and processing stay.
    func selectingKit(_ kit: KitDefinition) -> KnockState {
        var s = self
        s.kitID = kit.id
        s.kitName = kit.name
        s.userKit = nil
        s.soundSeed = 1
        s.pads = Self.normalizedPads(s.pads)
        if let custom = s.midiCustomNotes { s.midiCustomNotes = MIDIPadMap.clean(custom) }
        s.rackChannels = Self.migratedRackChannels(s)
        for i in s.rackChannels!.indices where s.rackChannels![i].usesKitSound {
            let slot = s.rackChannels![i].slot
            s.pads[slot].sampleFile = nil
            s.rackChannels![i].name = nil
            s.rackChannels![i].libraryID = nil
            s.rackChannels![i].stockFileName = nil
            s.rackChannels![i].sourceBassHz = nil
            if slot < Pad.count { s.rackChannels![i].role = slot }
            if s.stockPicks?.indices.contains(slot) == true { s.stockPicks![slot] = nil }
        }
        // KITS change the drum sounds only: the pattern, its edits and the tempo stay put.
        if s.patternStyle == nil { s.patternStyle = KitLibrary.kit(id: kitID).style }
        return s
    }

    func normalized() -> KnockState {
        var s = self
        s.version = 3
        s.bpm = s.bpm.isFinite ? s.bpm.clamped(40, 240) : 140
        s.pads = Self.normalizedPads(s.pads)
        s.rackChannels = Self.migratedRackChannels(s)
        s.workspaceChannels = nil
        s.mutedPads = s.mutedPads.map { Array(($0 + Array(repeating: false, count: RackLimits.maxChannels)).prefix(RackLimits.maxChannels)) }
        s.soloPads = s.soloPads.map { Array(($0 + Array(repeating: false, count: RackLimits.maxChannels)).prefix(RackLimits.maxChannels)) }
        if let picks = s.stockPicks { s.stockPicks = Array((picks + Array(repeating: nil, count: RackLimits.maxChannels)).prefix(RackLimits.maxChannels)) }
        s.editedLoops = Array(s.editedLoops.prefix(Pad.count))
        while s.editedLoops.count < Pad.count { s.editedLoops.append(nil) }
        for i in s.editedLoops.indices {
            guard var loop = s.editedLoops[i] else { continue }
            loop.lengthTicks = loop.lengthTicks.clamped(384, PatternEdit.barTicks * Int32(PatternEdit.maxBars))
            loop.events = Array(loop.events.prefix(4096)).filter {
                $0.pad >= 0 && Int($0.pad) < RackLimits.maxChannels && $0.tick >= 0 && $0.tick < loop.lengthTicks &&
                $0.velocity.isFinite && $0.semis.isFinite
            }
            for j in loop.events.indices {
                loop.events[j].velocity = loop.events[j].velocity.clamped(0, 1)
                loop.events[j].semis = loop.events[j].semis.clamped(-12, 24)
                loop.events[j].length = loop.events[j].length.clamped(0, PatternEdit.barTicks * Int32(PatternEdit.maxBars))
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

    private static func migratedRackChannels(_ state: KnockState) -> [RackChannel] {
        if let channels = state.rackChannels { return RackChannel.normalized(channels) }
        guard let oldRows = state.workspaceChannels else { return RackChannel.legacy }
        return RackChannel.normalized(oldRows.map { row in
            RackChannel(id: row.id, slot: row.pad, name: row.name,
                        role: RackChannel.role(for: SoundType(rawValue: row.category) ?? .perc),
                        libraryID: row.soundID, followsKit: false)
        })
    }
}

/// A saved kit: which factory kit it started from, its sound variation, and your pads.
struct UserKit: Codable {
    var name: String
    var baseKitID: String
    var soundSeed: UInt32
    var pads: [PadSettings]
    var rackChannels: [RackChannel]? = nil
    var stockPicks: [String?]? = nil
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
