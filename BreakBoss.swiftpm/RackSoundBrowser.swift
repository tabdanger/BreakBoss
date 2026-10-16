import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// The rack and browser share one inventory. Disk enumeration is never part of a View body,
/// a drag callback, or the audio render callback.
final class RackSoundLibrary: ObservableObject {
    @Published private(set) var sounds: [LibrarySound] = []
    @Published private(set) var packs: [String] = []
    @Published private(set) var isLoading = false

    private let queue = DispatchQueue(label: "com.tabdanger.BreakBoss.rack-library", qos: .userInitiated)
    private var index: [String: LibrarySound] = [:]
    private var generation = 0
    private static let factorySounds = StockSampleLibrary.bundled.librarySounds()

    /// Supplying an inventory makes screenshots deterministic without waiting on disk work.
    init(preloadedSounds: [LibrarySound]? = nil) {
        if let preloadedSounds {
            let snapshot = Self.snapshot(preloadedSounds)
            sounds = snapshot.sounds
            index = snapshot.index
            packs = snapshot.packs
        } else { refresh() }
    }

    private static func snapshot(_ input: [LibrarySound]) -> (sounds: [LibrarySound], index: [String: LibrarySound], packs: [String]) {
        let all = input.sorted {
            if $0.user != $1.user { return $0.user }
            let order = $0.pack.localizedStandardCompare($1.pack)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0.id).inserted }
        let lookup = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0) })
        let packNames = Array(Set(unique.map(\.pack))).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        return (unique, lookup, packNames)
    }

    func refresh() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refresh() }
            return
        }
        generation += 1
        let request = generation
        isLoading = true
        queue.async { [weak self] in
            let snapshot = Self.snapshot(UserSoundLibrary.sounds() + Self.factorySounds)
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                self.index = snapshot.index
                self.packs = snapshot.packs
                self.sounds = snapshot.sounds
                self.isLoading = false
            }
        }
    }

    /// Resolution stays inside the app; drag data never includes a file path or a sample payload.
    func sound(id: String) -> LibrarySound? { index[id] }
}

enum RackSoundDrag {
    static let type = UTType(exportedAs: "com.tabdanger.BreakBoss.library-sound", conformingTo: .data)
    private static let maximumBytes = 4096
    private struct Payload: Codable { let version: Int; let id: String }

    static func provider(_ sound: LibrarySound) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = sound.name
        guard let data = try? JSONEncoder().encode(Payload(version: 1, id: sound.id)),
              data.count <= maximumBytes else { return provider }
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    @discardableResult
    static func load(_ providers: [NSItemProvider], completion: @escaping (String?) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(type.identifier) }) else {
            DispatchQueue.main.async { completion(nil) }
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            var id: String?
            if let data, data.count <= maximumBytes,
               let payload = try? JSONDecoder().decode(Payload.self, from: data),
               payload.version == 1, !payload.id.isEmpty,
               payload.id.hasPrefix("stock:") || payload.id.hasPrefix("user:") {
                id = payload.id
            }
            DispatchQueue.main.async { completion(id) }
        }
        return true
    }
}

/// One disposable audition player. File preparation and decoding use a separate queue,
/// so browsing sounds neither replaces a rack channel nor schedules notes in the running pattern.
private final class RackSoundPreview: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var activeID: String?
    @Published private(set) var preparing = false
    @Published private(set) var error: String?

    private let queue = DispatchQueue(label: "com.tabdanger.BreakBoss.rack-preview", qos: .userInitiated)
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var player: AVAudioPlayer?

    private func nextGeneration() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        return generation
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return token == generation
    }

    func toggle(_ sound: LibrarySound) {
        if activeID == sound.id { stop(); return }
        let token = nextGeneration()
        activeID = sound.id
        preparing = true
        error = nil
        player?.stop()
        player = nil
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isCurrent(token) else { return }
            do {
                let access = sound.url.startAccessingSecurityScopedResource()
                defer { if access { sound.url.stopAccessingSecurityScopedResource() } }
                let audio = try AVAudioPlayer(contentsOf: sound.url)
                audio.volume = 0.7
                guard audio.prepareToPlay() else { throw PreviewError.unavailable }
                guard self.isCurrent(token) else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    // Playback/delegate ownership lives on the main run loop; decoding above does not.
                    self.player = audio
                    audio.delegate = self
                    if !audio.play() {
                        self.player = nil
                        self.activeID = nil
                        self.error = "This sound could not be previewed."
                    }
                    self.preparing = false
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrent(token) else { return }
                    self.activeID = nil
                    self.preparing = false
                    self.error = "This sound could not be previewed."
                }
            }
        }
    }

    func stop() {
        _ = nextGeneration()
        activeID = nil
        preparing = false
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish(player, failed: !flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        finish(player, failed: true)
    }

    private func finish(_ finished: AVAudioPlayer, failed: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player === finished else { return }
            self.player = nil
            _ = self.nextGeneration()
            self.activeID = nil
            self.preparing = false
            if failed { self.error = "This sound could not be previewed." }
        }
    }

    private enum PreviewError: Error { case unavailable }
}

/// Embedded right-hand sound library for the rebuilt channel rack.
/// Tap a sound to audition it; drag or press + to create an independent channel.
struct RackSoundBrowser: View {
    @ObservedObject var controller: KnockController
    @ObservedObject var library: RackSoundLibrary
    let onAdd: (LibrarySound) -> Void
    var onClose: (() -> Void)? = nil

    @StateObject private var preview = RackSoundPreview()
    @State private var search = ""
    @State private var type: SoundType? = .kick
    @State private var pack: String?
    @State private var source: Source = .all
    @State private var showImporter = false
    @State private var importKind: ImportKind = .sounds
    @State private var importing = false
    @State private var message: String?

    private enum Source: String, CaseIterable { case all = "ALL", factory = "FACTORY", user = "YOURS" }
    private enum ImportKind { case sounds, pack }
    private static let importQueue = DispatchQueue(label: "com.tabdanger.BreakBoss.rack-import", qos: .userInitiated)
    private static let green = Color(red: 0.68, green: 0.88, blue: 0.16)
    private static let dark = Color(red: 0.065, green: 0.07, blue: 0.075)
    private static let dim = Color(white: 0.63)
    private static let metal = LinearGradient(colors: [Color(white: 0.80), Color(white: 0.60), Color(white: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing)

    private static let categories: [SoundType?] = [.kick, .clap, .snare, .rim, .hat, .open, .bass, .perc, .tom, .cymbal, .fx, nil]
    private var categoryTitle: String { type?.rawValue ?? "ALL SOUNDS" }
    private var categoryIndex: Int { Self.categories.firstIndex(where: { $0 == type }) ?? 0 }
    private var rackFull: Bool { controller.rackChannelCount >= RackLimits.maxChannels }

    private func changeCategory(_ offset: Int) {
        let count = Self.categories.count
        type = Self.categories[(categoryIndex + offset + count) % count]
        preview.stop()
    }

    private var shown: [LibrarySound] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.sounds.filter { sound in
            (type == nil || sound.type == type) &&
            (pack == nil || sound.pack == pack) &&
            (source == .all || sound.user == (source == .user)) &&
            (query.isEmpty || sound.name.localizedCaseInsensitiveContains(query) ||
                sound.pack.localizedCaseInsensitiveContains(query) || sound.type.rawValue.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let short = geometry.size.height < 300
            VStack(spacing: 0) {
                if !short { header }
                filters(compact: short)
                soundList(compact: short)
                if !short { footer }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Self.dark)
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.black.opacity(0.7), lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.18), lineWidth: 1).padding(2))
        .onDisappear { preview.stop() }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importKind == .pack ? [.folder] : [.audio],
                      allowsMultipleSelection: importKind == .sounds) { result in
            switch result {
            case .success(let urls): importURLs(urls, kind: importKind)
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { message = "The selected sounds could not be imported." }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform").font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("SOUND LIBRARY").font(.system(size: 12, weight: .heavy, design: .rounded))
                Text(rackFull ? "12 / 12 CHANNELS · RACK FULL" : "DRAG LEFT TO ADD A CHANNEL").font(.system(size: 7, weight: .semibold, design: .monospaced))
            }
            Spacer(minLength: 0)
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 32, height: 36) }
                    .buttonStyle(.plain).accessibilityLabel("Close sound library")
            }
        }
        .foregroundColor(Color(white: 0.10)).padding(.horizontal, 10).padding(.vertical, 6)
        .background(Self.metal)
    }

    private func filters(compact: Bool) -> some View {
        VStack(spacing: compact ? 4 : 6) {
            HStack(spacing: 4) {
                Button { changeCategory(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).frame(width: 34, height: compact ? 32 : 40)
                }.accessibilityLabel("Previous sound category")
                VStack(spacing: 2) {
                    Text(categoryTitle).font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(0.6)
                    Text("SWIPE TO CHANGE CATEGORY").font(.system(size: 6, weight: .semibold, design: .monospaced))
                        .foregroundColor(Self.dim)
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 32 : 40)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 24).onEnded { gesture in
                    if abs(gesture.translation.width) > abs(gesture.translation.height) {
                        changeCategory(gesture.translation.width < 0 ? 1 : -1)
                    }
                })
                .accessibilityElement(children: .combine)
                .accessibilityAdjustableAction { changeCategory($0 == .increment ? 1 : -1) }
                Button { changeCategory(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).frame(width: 34, height: compact ? 32 : 40)
                }.accessibilityLabel("Next sound category")
            }
            .foregroundColor(Self.green)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.4)))
            if !compact {
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Self.categories.indices, id: \.self) { index in
                            let category = Self.categories[index]
                            Button { type = category; preview.stop() } label: {
                                Text(category?.rawValue ?? "ALL").font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(type == category ? Color.black : Self.dim)
                                    .padding(.horizontal, 9).frame(height: 28)
                                    .background(Capsule().fill(type == category ? Self.green : Color.black.opacity(0.25)))
                            }
                            .id(index).accessibilityAddTraits(type == category ? .isSelected : [])
                        }
                    }
                }
                    .onChange(of: categoryIndex) { reader.scrollTo($0, anchor: .center) }
                }
            }
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundColor(Self.dim).font(.system(size: 12))
                TextField("Search \(type?.rawValue.lowercased() ?? "sounds")", text: $search)
                    .font(.system(size: 12)).foregroundColor(.white)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityLabel("Search the sound library")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Self.dim) }
                        .buttonStyle(.plain).accessibilityLabel("Clear sound search")
                }
                Menu {
                    Section("Import") {
                        Button("Import sounds…") { importKind = .sounds; showImporter = true }
                        Button("Import a pack folder…") { importKind = .pack; showImporter = true }
                        if preview.activeID != nil { Button("Stop preview") { preview.stop() } }
                    }
                    Section("Source") {
                        ForEach(Source.allCases, id: \.self) { item in
                            Button { source = item } label: {
                                if source == item { Label(item.rawValue, systemImage: "checkmark") }
                                else { Text(item.rawValue) }
                            }
                        }
                    }
                    Section("Pack") {
                        Button("All packs") { pack = nil }
                        ForEach(library.packs, id: \.self) { name in Button(name) { pack = name } }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(pack != nil || source != .all ? Self.green : Self.dim).frame(width: 30, height: 35)
                }
                .accessibilityLabel("Filter sounds by source and pack")
            }
            .padding(.leading, 9).frame(height: compact ? 30 : 35)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(compact ? 6 : 8).background(Color(white: 0.12))
    }

    private func soundList(compact: Bool) -> some View {
        let results = shown
        return VStack(spacing: 0) {
            HStack {
                Text("\(results.count) SOUND\(results.count == 1 ? "" : "S")")
                Spacer()
                if library.isLoading { ProgressView().scaleEffect(0.65).tint(Self.green) }
            }
            .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(Self.dim)
            .frame(height: compact ? 17 : 25).padding(.horizontal, 12)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(results) { sound in soundRow(sound) }
                    if results.isEmpty && !library.isLoading {
                        VStack(spacing: 7) {
                            Image(systemName: "waveform").font(.system(size: 24, weight: .light))
                            Text("No matching sounds").font(.system(size: 12, weight: .semibold))
                            Text("Try another filter or import a pack.").font(.system(size: 10))
                        }
                        .foregroundColor(Self.dim).multilineTextAlignment(.center).padding(.vertical, 35).padding(.horizontal, 10)
                    }
                }
                .padding(.horizontal, 7).padding(.bottom, 8)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func soundRow(_ sound: LibrarySound) -> some View {
        let active = preview.activeID == sound.id
        return HStack(spacing: 4) {
            Button { preview.toggle(sound) } label: {
                HStack(spacing: 8) {
                    Image(systemName: active ? "stop.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold)).frame(width: 20, height: 32)
                        .foregroundColor(active ? Self.green : Self.dim)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sound.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                            .foregroundColor(active ? Self.green : Color(white: 0.91))
                        Text("\(sound.type.rawValue) · \(sound.pack)")
                            .font(.system(size: 8, design: .monospaced)).foregroundColor(Self.dim).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 43, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(active ? "Stop preview of" : "Preview") \(sound.name)")
            Button { onAdd(sound) } label: {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    .foregroundColor(Self.green).frame(width: 36, height: 43).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(rackFull).opacity(rackFull ? 0.35 : 1)
            .accessibilityLabel(rackFull ? "Rack is full. Remove a channel to add \(sound.name)" : "Add \(sound.name) as a new channel")
        }
        .padding(.leading, 6).padding(.trailing, 2)
        .background(RoundedRectangle(cornerRadius: 9).fill(active ? Self.green.opacity(0.09) : Color(white: 0.11)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(active ? Self.green.opacity(0.35) : Color.white.opacity(0.055), lineWidth: 1))
        .onDrag { RackSoundDrag.provider(sound) }
        .accessibilityHint("Drag to the channel rack, or use the add button, to create a channel.")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(preview.activeID == nil ? Color(white: 0.30) : Self.green).frame(width: 5, height: 5)
                Text(preview.activeID == nil ? "TAP TO PREVIEW · DRAG TO ADD" : (preview.preparing ? "PREPARING PREVIEW" : "PREVIEWING SOUND"))
                    .font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundColor(Self.dim).lineLimit(1)
                Spacer(minLength: 0)
                Menu {
                    Button("Import sounds…") { importKind = .sounds; showImporter = true }
                    Button("Import a pack folder…") { importKind = .pack; showImporter = true }
                    if preview.activeID != nil { Button("Stop preview") { preview.stop() } }
                } label: {
                    Image(systemName: importing ? "hourglass" : "folder.badge.plus")
                        .foregroundColor(Self.green).frame(width: 34, height: 34)
                }
                .disabled(importing).accessibilityLabel("Import sounds or a sound pack")
            }
            if let status = message ?? preview.error {
                Text(status).font(.system(size: 9)).foregroundColor(Self.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 3).background(Color(white: 0.10))
        .overlay(Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1), alignment: .top)
    }

    private func importURLs(_ urls: [URL], kind: ImportKind) {
        guard !urls.isEmpty else { return }
        importing = true
        message = nil
        Self.importQueue.async {
            let count = kind == .pack ? urls.reduce(0) { $0 + UserSoundLibrary.importPack($1) } : UserSoundLibrary.importSounds(urls)
            DispatchQueue.main.async {
                importing = false
                message = count == 0 ? "No new audio files found." : "Imported \(count) sound\(count == 1 ? "" : "s")."
                if count > 0 {
                    source = .user
                    type = nil
                    search = ""
                    if kind == .pack, let first = urls.first {
                        pack = KnockFolders.safe(first.deletingPathExtension().lastPathComponent).uppercased()
                    } else { pack = "IMPORTED" }
                }
                library.refresh()
            }
        }
    }
}
