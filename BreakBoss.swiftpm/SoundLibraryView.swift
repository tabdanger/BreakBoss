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

    /// Imported files: the type from the file and folder names (FL-style pack names).
    static func guess(_ path: String) -> SoundType {
        let n = path.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if has("808", "bass", "sub") { return .bass }
        if has("open", "ohh", "oh ") { return .open }
        if has("hihat", "hi hat", "hi-hat", "hh", "hat") { return .hat }
        if has("kick", "kik", "bd") { return .kick }
        if has("clap", "snap") { return .clap }
        if has("rim") { return .rim }
        if has("snare", "sd") { return .snare }
        if has("tom") { return .tom }
        if has("crash", "cymbal", "ride", "splash") { return .cymbal }
        if has("perc", "shaker", "tamb", "conga", "bongo", "cowbell", "clave", "block", "triangle", "bell") { return .perc }
        return .fx
    }
}

extension SoundType {
    /// Stock sounds are named by category ("KICK BOOM 07", "SHAKER 03"): the first word says which.
    static func forStockName(_ name: String) -> SoundType? {
        let words = name.split(separator: " ")
        switch words.first.map(String.init) ?? "" {
        case "KICK": return .kick
        case "SNARE": return .snare
        case "CLAP": return .clap
        case "RIM", "SNAP": return .rim
        case "HAT": return .hat
        case "OPEN": return .open
        case "808": return .bass
        case "PERC", "SHAKER", "TAMB", "CLAVE", "TRIANGLE", "CONGA", "BONGO", "BELL", "BEADS": return .perc
        case "TOM": return .tom
        case "CYMBAL": return .cymbal
        case "FX": return .fx
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
                                    type: SoundType.forStockName(s.displayName) ?? .fx,
                                    pack: kitOf[s.url.lastPathComponent] ?? "MORE SOUNDS", user: false))
        }
        return out
    }
}

enum UserSoundLibrary {
    /// Your imported sounds: Samples/<pack>/… (a pack is a folder), loose files are "MY SOUNDS".
    static func sounds() -> [LibrarySound] {
        let root = KnockFolders.samples.standardizedFileURL.path
        return KnockFolders.sampleFiles().map { url in
            let rel = url.standardizedFileURL.path.replacingOccurrences(of: root + "/", with: "")
            let parts = rel.split(separator: "/")
            let pack = parts.count > 1 ? String(parts[0]).uppercased() : "MY SOUNDS"
            return LibrarySound(id: "user:" + rel, url: url, name: url.deletingPathExtension().lastPathComponent.uppercased(),
                                type: SoundType.guess(rel), pack: pack, user: true)
        }
    }

    /// Copies a whole pack (a folder or a .zip's unpacked folder) into Samples/<pack name>/.
    /// Returns how many sounds came in.
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
            // keep the pack's own type folders (Kicks/, Snares/…), flattened one level
            let parent = url.deletingLastPathComponent().lastPathComponent
            let sub = parent == folder.lastPathComponent ? dest : dest.appendingPathComponent(KnockFolders.safe(parent), isDirectory: true)
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

/// BreakBoss's own sound menu (not Apple's): every factory and imported sound, by type, by pack,
/// with search. Tap a sound to put it on the channel (you hear it right away). IMPORT brings in
/// single sounds or whole packs from Files; they land in the same menu, sorted by type.
struct SoundLibraryView: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    let onClose: () -> Void

    private typealias S = DrumRollStyle
    @State private var type: SoundType?
    @State private var pack: String?
    @State private var showPacks = false
    @State private var search = ""
    @State private var userSounds: [LibrarySound] = UserSoundLibrary.sounds()
    @State private var importKind: ImportKind?
    @State private var message: String?
    @State private var loadedID: String?

    private enum ImportKind: Identifiable { case sounds, pack; var id: Int { self == .sounds ? 0 : 1 } }
    private static let stock: [LibrarySound] = StockSampleLibrary.bundled.librarySounds()

    private var all: [LibrarySound] { userSounds + Self.stock }

    private struct PackInfo: Hashable { let name: String; let count: Int; let user: Bool }

    private var packs: [PackInfo] {
        var order: [String] = []; var count: [String: Int] = [:]; var user: [String: Bool] = [:]
        for s in all {
            if count[s.pack] == nil { order.append(s.pack) }
            count[s.pack, default: 0] += 1; user[s.pack] = s.user
        }
        return order.map { PackInfo(name: $0, count: count[$0] ?? 0, user: user[$0] ?? false) }
    }

    private var shown: [LibrarySound] {
        var list = all
        if let pack { list = list.filter { $0.pack == pack } }
        if let type { list = list.filter { $0.type == type } }
        if !search.isEmpty {
            let q = search.uppercased()
            list = list.filter { $0.name.uppercased().contains(q) || $0.pack.uppercased().contains(q) }
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            chips
            HStack(spacing: 0) {
                sidebar.frame(width: 230)
                Rectangle().fill(S.border).frame(width: 1)
                soundList
            }
        }
        .background(S.channel.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { type = SoundType.forPad(pad) }
        .fileImporter(isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
                      allowedContentTypes: importKind == .pack ? [.folder] : [.audio],
                      allowsMultipleSelection: importKind == .sounds) { result in
            guard case .success(let urls) = result else { importKind = nil; return }
            let n = importKind == .pack ? urls.reduce(0) { $0 + UserSoundLibrary.importPack($1) } : UserSoundLibrary.importSounds(urls)
            if importKind == .pack, let first = urls.first { pack = KnockFolders.safe(first.deletingPathExtension().lastPathComponent).uppercased(); type = nil }
            userSounds = UserSoundLibrary.sounds()
            message = n == 0 ? "No audio files found there." : "Imported \(n) sound\(n == 1 ? "" : "s")."
            importKind = nil
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SOUNDS").font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(S.text)
                Text("LOAD ONTO: \(Pad(rawValue: pad)?.channelTitle ?? "CHANNEL")").font(.system(size: 11, design: .monospaced)).foregroundColor(S.green)
            }
            Spacer()
            if let message { Text(message).font(.system(size: 11, design: .monospaced)).foregroundColor(S.dim).lineLimit(1) }
            button("IMPORT SOUNDS", icon: "square.and.arrow.down") { importKind = .sounds }
            button("IMPORT PACK", icon: "folder.badge.plus") { importKind = .pack }
            Button { onClose() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(S.text)
                    .frame(width: 44, height: 40).background(RoundedRectangle(cornerRadius: 6).fill(S.button))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(S.header)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("ALL", on: type == nil) { type = nil }
                ForEach(SoundType.allCases) { t in chip(t.rawValue, on: type == t) { type = t } }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(S.toolbar)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(S.dim)
                TextField("Search", text: $search).foregroundColor(S.text).autocorrectionDisabled()
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(S.button)).padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    sideRow("ALL PACKS", count: all.count, on: pack == nil) { pack = nil }
                    Text("PACKS & KITS").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(S.dim)
                        .padding(.horizontal, 12).padding(.top, 10)
                    ForEach(packs, id: \.self) { p in
                        sideRow(p.name, count: p.count, on: pack == p.name, user: p.user) { pack = p.name }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(S.lane)
    }

    private var soundList: some View {
        VStack(spacing: 0) {
            if let pack {
                HStack {
                    Text(pack).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundColor(S.text)
                    Spacer()
                    button("LOAD WHOLE PACK", icon: "square.grid.3x3.fill") { loadWholePack(pack) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8).background(S.toolbar)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { s in soundRow(s) }
                    if shown.isEmpty {
                        Text("Nothing here yet.").font(.system(size: 13, design: .monospaced)).foregroundColor(S.dim).padding(30)
                    }
                }
            }
        }
    }

    private func soundRow(_ s: LibrarySound) -> some View {
        Button { load(s) } label: {
            HStack(spacing: 10) {
                Image(systemName: loadedID == s.id ? "speaker.wave.2.fill" : "waveform")
                    .foregroundColor(loadedID == s.id ? S.green : S.dim).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.name).font(.system(size: 14, weight: .medium)).foregroundColor(loadedID == s.id ? S.green : S.text).lineLimit(1)
                    Text("\(s.type.rawValue) · \(s.pack)").font(.system(size: 10, design: .monospaced)).foregroundColor(S.dim).lineLimit(1)
                }
                Spacer()
                if s.user { Text("YOURS").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(S.orange) }
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(loadedID == s.id ? S.green.opacity(0.12) : Color.clear)
            .overlay(Rectangle().fill(S.border.opacity(0.5)).frame(height: 1), alignment: .bottom)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    /// Puts the sound on this channel and plays it once it's loaded.
    private func load(_ s: LibrarySound) {
        controller.importSample(s.url, toPad: pad)
        loadedID = s.id
        let p = pad
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { controller.auditionPad(p) }
    }

    /// A whole pack onto the 12 channels: each channel gets the pack's first sound of its type.
    /// A factory kit loads as itself.
    private func loadWholePack(_ name: String) {
        if let kit = KitLibrary.factory.first(where: { $0.name == name }), !all.contains(where: { $0.pack == name && $0.user }) {
            controller.selectKit(kit)
            message = "Loaded the kit \(name)."
            return
        }
        let sounds = all.filter { $0.pack == name }
        var used = Set<String>(); var n = 0
        for p in 0..<Pad.count {
            let want = SoundType.forPad(p)
            if let s = sounds.first(where: { $0.type == want && !used.contains($0.id) }) ?? sounds.first(where: { $0.type == want }) {
                used.insert(s.id); controller.importSample(s.url, toPad: p); n += 1
            }
        }
        message = n == 0 ? "That pack has no sounds that fit the channels." : "Loaded \(n) channels from \(name)."
    }

    // MARK: Pieces

    private func button(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13))
                Text(title).font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(S.text).padding(.horizontal, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 6).fill(S.button))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(S.border, lineWidth: 1))
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(on ? .black : S.text).padding(.horizontal, 12).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 5).fill(on ? S.green : S.button))
        }
    }

    private func sideRow(_ title: String, count: Int, on: Bool, user: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12, weight: on ? .bold : .regular, design: .monospaced))
                    .foregroundColor(on ? S.green : (user ? S.orange : S.text)).lineLimit(1)
                Spacer()
                Text("\(count)").font(.system(size: 10, design: .monospaced)).foregroundColor(S.dim)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(on ? S.green.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}
