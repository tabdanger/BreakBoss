import SwiftUI
import UniformTypeIdentifiers


// MARK: - Every sound in BreakBoss, by type

/// One sound in the library: a stock sound from the factory packs, or one you imported.
struct LibrarySound: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let type: SoundType
    let pack: String
    let user: Bool
}

enum SoundType: String, CaseIterable, Identifiable {
    case kick = "KICKS", snare = "SNARES", clap = "CLAPS", rim = "RIMS", hat = "HI HATS", open = "OPEN HATS",
         bass = "808s", perc = "PERCS", tom = "TOMS", cymbal = "CYMBALS", fx = "FX & OTHER"
    var id: String { rawValue }

    /// The type each drum channel plays (the menu opens on it).
    static func forPad(_ pad: Int) -> SoundType {
        switch pad {
        case 0: return .kick
        case 1: return .snare
        case 2: return .clap
        case 3: return .rim
        case 4: return .hat
        case 5: return .open
        case 6: return .bass
        case 7, 8: return .perc
        case 9, 10: return .tom
        default: return .cymbal
        }
    }

    /// Imported files: the folder a sound is in decides what it is (Tyrone, Oct 19: a sound from a
    /// Kicks folder is a kick, whatever its name), the innermost folder that names a kind first; a
    /// folder that names none (the pack's own name) leaves it to the file's name; then FX & OTHER.
    static func guess(_ path: String) -> SoundType {
        let parts = path.split(separator: "/").map(String.init)
        for folder in parts.dropLast().reversed() {
            if let t = named(folder) { return t }
        }
        return parts.last.flatMap { named(($0 as NSString).deletingPathExtension) } ?? .fx
    }

    /// The kind a folder or file name says, by whole words ("Hi-Hats", "OHH", "808s", "[Kick] Astronomy").
    static func named(_ name: String) -> SoundType? {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let w = Set(words)
        func has(_ list: String...) -> Bool { list.contains { w.contains($0) } }
        func pair(_ a: String, _ b: Set<String>) -> Bool { zip(words, words.dropFirst()).contains { $0 == a && b.contains($1) } }
        let hats: Set<String> = ["hat", "hats", "hihat", "hihats"]
        if has("ohh", "ohat", "ohats", "openhat", "openhats") || pair("open", hats) || (has("open") && !w.isDisjoint(with: hats)) { return .open }
        if has("808", "808s", "bass", "basses", "sub", "subs") { return .bass }
        if has("hh", "chh", "hihat", "hihats", "hat", "hats") { return .hat }
        if has("kick", "kicks", "kik", "kiks", "bd") { return .kick }
        if has("snare", "snares", "sd") { return .snare }
        if has("clap", "claps") { return .clap }
        if has("rim", "rims", "rimshot", "rimshots", "snap", "snaps") { return .rim }
        if has("tom", "toms") { return .tom }
        if has("crash", "crashes", "cymbal", "cymbals", "ride", "rides", "splash") { return .cymbal }
        if has("perc", "percs", "percussion", "shaker", "shakers", "tamb", "tambourine", "conga", "congas", "bongo", "bongos",
               "cowbell", "clave", "block", "triangle", "bell") { return .perc }
        if has("fx", "sfx", "riser", "risers", "texture", "textures", "scratch", "impact") { return .fx }
        return nil
    }

    /// A library section as the stock manifest writes it ("OPEN HAT", "808").
    init?(section: String) {
        switch section {
        case "KICK": self = .kick
        case "SNARE": self = .snare
        case "CLAP": self = .clap
        case "RIM": self = .rim
        case "HAT": self = .hat
        case "OPEN HAT": self = .open
        case "808": self = .bass
        case "PERC": self = .perc
        case "TOM": self = .tom
        case "CYMBAL": self = .cymbal
        case "FX": self = .fx
        default: return nil
        }
    }
}

extension SoundType {
    /// A stock sound's name ends in what it is ("BK NO 9 KICK", "BK NO 60 OPEN HAT", "BK NO 15 E1 808").
    static func forStockName(_ name: String) -> SoundType? {
        let words = name.split(separator: " ").map(String.init)
        guard let last = words.last else { return nil }
        if words.count >= 2, words[words.count - 2] == "OPEN", last == "HAT" || last == "HIHAT" { return .open }
        switch last {
        case "KICK": return .kick
        case "SNARE": return .snare
        case "CLAP": return .clap
        case "RIM", "RIMSHOT", "SNAP": return .rim
        case "HAT", "HIHAT": return .hat
        case "808": return .bass
        case "PERC", "SHAKER", "TAMB", "TAMBOURINE", "TRIANGLE", "COWBELL", "CLAVE": return .perc
        case "TOM": return .tom
        case "CYMBAL", "CRASH", "RIDE": return .cymbal
        case "FX", "SFX", "LAZER", "SCRATCH", "RISER", "TEXTURE": return .fx
        default: return nil
        }
    }
}

extension StockSampleLibrary {
    /// Every stock sound once, by category, with the first kit that plays it as its pack.
    func librarySounds() -> [LibrarySound] {
        var kitOf: [String: String] = [:]
        var seen = Set<String>()
        var out: [LibrarySound] = []
        for kit in KitLibrary.factory {
            for pad in 0..<Pad.count {
                guard let s = sample(kitID: kit.id, pad: pad) else { continue }
                if kitOf[s.url.lastPathComponent] == nil { kitOf[s.url.lastPathComponent] = kit.name }
                guard allSounds.isEmpty, seen.insert(s.url.lastPathComponent).inserted else { continue }
                out.append(LibrarySound(id: "stock:" + s.url.lastPathComponent, url: s.url, name: s.displayName,
                                        type: SoundType.forStockName(s.displayName) ?? SoundType.forPad(pad), pack: kit.name, user: false))
            }
        }
        for s in allSounds where seen.insert(s.url.lastPathComponent).inserted {
            out.append(LibrarySound(id: "stock:" + s.url.lastPathComponent, url: s.url, name: s.displayName,
                                    type: s.section.flatMap(SoundType.init(section:)) ?? SoundType.forStockName(s.displayName) ?? .fx,
                                    pack: kitOf[s.url.lastPathComponent] ?? "MORE SOUNDS", user: false))
        }
        return out
    }
}

enum UserSoundLibrary {
    /// Your imported sounds: Samples/<pack>/… (a pack is a folder), loose files are "MY SOUNDS".
    static func sounds() -> [LibrarySound] {
        return KnockFolders.sampleFiles().map { url in
            let rel = KnockFolders.relative(url, in: KnockFolders.samples) ?? url.lastPathComponent
            let parts = rel.split(separator: "/")
            let pack = parts.count > 1 ? String(parts[0]).uppercased() : "MY SOUNDS"
            return LibrarySound(id: "user:" + rel, url: url, name: KnockFolders.soundName(rel),
                                type: KnockFolders.soundType(rel) ?? SoundType.guess(rel), pack: pack, user: true)
        }
    }

    /// Copies a whole pack (a folder or a .zip's unpacked folder) into Samples/<pack name>/, each sound
    /// sorted into its section's folder (KICKS, SNARES, 808s, HI HATS, OPEN HATS…) by the folder it was
    /// in, or its name (Tyrone, Oct 19). Returns how many sounds came in.
    @discardableResult
    static func importPack(_ folder: URL) -> Int {
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        let exts: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a", "flac", "aac"]
        let name = KnockFolders.safe(folder.deletingPathExtension().lastPathComponent)
        let dest = KnockFolders.samples.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        var count = 0
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return 0 }
        for case let url as URL in walker where exts.contains(url.pathExtension.lowercased()) && !url.path.contains("__MACOSX") {
            // the sound's path inside the pack decides its section
            let inside = KnockFolders.relative(url, in: folder) ?? url.lastPathComponent
            let sub = dest.appendingPathComponent(KnockFolders.safe(SoundType.guess(inside).rawValue), isDirectory: true)
            try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
            let target = sub.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            if (try? FileManager.default.copyItem(at: url, to: target)) != nil { count += 1 }
        }
        return count
    }

    /// Single sounds into Samples/IMPORTED/.
    @discardableResult
    static func importSounds(_ urls: [URL]) -> Int {
        let dest = KnockFolders.samples.appendingPathComponent("IMPORTED", isDirectory: true)
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        var count = 0
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let target = dest.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) { count += 1; continue }
            if (try? FileManager.default.copyItem(at: url, to: target)) != nil { count += 1 }
        }
        return count
    }
}
