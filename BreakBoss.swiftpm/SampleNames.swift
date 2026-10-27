// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Break King names for the Samples folder
//
// Tyrone, Oct 26: the SAMPLES tab still showed old file names ("!Go2Spinz", "(clap) aspen",
// "bb_2000s-rnb_p00"). Every sound shows as a Break King name, read from what its old name says:
//   a copy of a stock sound (any build's file name)   -> that sound's name now ("BK NO 9 V2 KICK")
//   a pack sound the stock sounds were made from      -> the same family's number ("!Go2Spinz" -> "BK NO 5 808")
//   anything else of yours                            -> "BK MY n KIND", the kind from its name or folder
// Only the name shown changes: the file keeps its own name on disk. Your own sounds' numbers are kept
// in Samples/.names.json so a name never moves when you add more.

extension KnockFolders {
    /// A sound file's name as shown: "Samples/x/!Go2Spinz - (@prod.byiiinfinite).wav" -> "BK NO 5 808".
    static func soundName(_ file: String) -> String { SampleNames.shared.name(file) }

    /// The stock sound's name now when the file is (a copy of) one, nil otherwise.
    static func stockSoundName(_ file: String) -> String? { SampleNames.shared.stock(file) }

    /// The kind a sound's Break King name says (its last word), for the sound library's sections.
    static func soundType(_ file: String) -> SoundType? { SoundType.forStockName(soundName(file)) }

    /// A file name squashed for matching: lower case, the maker's tag cut, letters and digits only
    /// ("[808] Vacuum - (@prod.by.iiinfinite)" -> "808vacuum"). tools/sample_names.py squashes the same way.
    static func nameKey(_ stem: String) -> String {
        let s = stem.lowercased().replacingOccurrences(of: #"@prod\.?by\.?[a-z0-9._]*"#, with: "", options: .regularExpression)
        return String(s.unicodeScalars.filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) }.map(Character.init))
    }
}

final class SampleNames {
    static let shared = SampleNames()

    private struct Table: Decodable {
        let version: Int
        let stock: [String: String]
        let sources: [String: String]
        let families: [String: [String: String]]
        let kinds: [String: String]
    }

    private let table: Table?
    /// Each stock file's name now, from the manifest.
    private let stockNames: [String: String]
    private let lock = NSLock()
    private var mine: [String: String]?
    private var saveQueued = false

    private init() {
        let library = StockSampleLibrary.bundled.allSounds
        stockNames = Dictionary(library.map { ($0.url.lastPathComponent, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        if let folder = library.first?.url.deletingLastPathComponent() ?? knockResourceURL("manifest", "json")?.deletingLastPathComponent(),
           let data = try? Data(contentsOf: folder.appendingPathComponent("sample_names.json")),
           let t = try? JSONDecoder().decode(Table.self, from: data), t.version == 1 {
            table = t
        } else {
            table = nil
        }
    }

    func name(_ file: String) -> String {
        // Samples-relative path, no extension: "Pack/808s/!Go2Spinz - (@prod.byiiinfinite)"
        var rel = file
        if AudioFormats.isAudio(ext: (rel as NSString).pathExtension) { rel = (rel as NSString).deletingPathExtension }
        let stem = (rel as NSString).lastPathComponent
        // A sampler edit ("Edits/<sound> edit 2") is its sound's name and EDIT 2.
        if let m = stem.range(of: #" edit (\d+)$"#, options: .regularExpression) {
            let base = String(stem[..<m.lowerBound])
            return name(base) + " EDIT " + String(stem[m].dropFirst(6))
        }
        if let known = stockName(stem) { return known }
        // A second copy under the same name ("x 2"): the same stock sound
        if let m = stem.range(of: #" \d+$"#, options: .regularExpression), let known = stockName(String(stem[..<m.lowerBound])) { return known }
        return own(rel, stem)
    }

    func stock(_ file: String) -> String? {
        var stem = (file as NSString).lastPathComponent
        if AudioFormats.isAudio(ext: (stem as NSString).pathExtension) { stem = (stem as NSString).deletingPathExtension }
        return stockName(stem)
    }

    /// The stock sound this file is a copy of (by any name a build gave it, or its pack file's name).
    private func stockName(_ stem: String) -> String? {
        guard let table else { return nil }
        let key = KnockFolders.nameKey(stem)
        guard !key.isEmpty, let file = table.stock[key] ?? table.sources[key] else { return nil }
        return stockNames[file]
    }

    /// One of your own sounds: its family's BK number when it's a pack sound the stock sounds came
    /// from, otherwise the next "BK MY n" of its kind. Kept in Samples/.names.json.
    private func own(_ rel: String, _ stem: String) -> String {
        lock.lock(); defer { lock.unlock() }
        var names = loadMine()
        if let kept = names[rel] { return kept }
        let result = fresh(rel, stem, taken: names)
        names[rel] = result
        mine = names
        // The SAMPLES tab names a whole folder at once: one write for the lot.
        if !saveQueued {
            saveQueued = true
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [self] in
                lock.lock(); let all = mine ?? [:]; saveQueued = false; lock.unlock()
                saveMine(all)
            }
        }
        return result
    }

    /// The name a sound of yours gets the first time it's seen, next to the names already given.
    func fresh(_ rel: String, _ stem: String, taken names: [String: String]) -> String {
        let words = stem.lowercased().replacingOccurrences(of: #"@prod\.?by\.?[a-z0-9._]*"#, with: "", options: .regularExpression)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let said = SoundType.named(stem) ?? folderKind(rel)
        var kind = table?.kinds[KnockFolders.nameKey(stem)] ?? said.map(Self.word)
        var number: String?
        // A pack family ("!Go2Spinz" is one of the GO2SPINZ 808s): its own words, the kind words left out.
        let ownKey = KnockFolders.nameKey(words.filter { SoundType.named($0) == nil }.joined())
        if let family = table?.families[ownKey] ?? table?.families[KnockFolders.nameKey(stem)] {
            if let k = kind, let n = family[k] { number = n }
            else if kind == nil, family.count == 1, let only = family.first { kind = only.key; number = only.value }
        }
        let kindWord = kind ?? "SAMPLE"
        let taken = Set(names.values)
        var result: String
        if let number {
            result = "\(number) \(kindWord)"
            var v = 2
            while taken.contains(result) { result = "\(number) V\(v) \(kindWord)"; v += 1 }
        } else {
            let pattern = #"^BK MY (\d+) "# + NSRegularExpression.escapedPattern(for: kindWord) + "$"
            let top = names.values.compactMap { n -> Int? in
                guard let r = n.range(of: pattern, options: .regularExpression) else { return nil }
                return Int(n[r].split(separator: " ")[2])
            }.max() ?? 0
            result = "BK MY \(top + 1) \(kindWord)"
        }
        return result
    }

    /// The kind a sound's folder says ("Pack/808s/x" -> 808), nil when no folder says one.
    private func folderKind(_ rel: String) -> SoundType? {
        for folder in rel.split(separator: "/").dropLast().reversed() {
            if let t = SoundType.named(String(folder)) { return t }
        }
        return nil
    }

    private static func word(_ type: SoundType) -> String {
        switch type {
        case .kick: return "KICK"
        case .snare: return "SNARE"
        case .clap: return "CLAP"
        case .rim: return "RIM"
        case .hat: return "HIHAT"
        case .open: return "OPEN HAT"
        case .bass: return "808"
        case .perc: return "PERC"
        case .tom: return "TOM"
        case .cymbal: return "CYMBAL"
        case .fx: return "FX"
        }
    }

    private var mineURL: URL { KnockFolders.samples.appendingPathComponent(".names.json") }

    private func loadMine() -> [String: String] {
        if let mine { return mine }
        let loaded = (try? Data(contentsOf: mineURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        mine = loaded
        return loaded
    }

    private func saveMine(_ names: [String: String]) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        try? data.write(to: mineURL, options: .atomic)
    }
}
