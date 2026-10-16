// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A portable preset embeds original imported and bundled stock audio, not device-local paths.
/// Bounded to keep sharing from exhausting the device's memory.
enum PortablePreset {
    struct Sample: Codable { var path: String; var bytes: Data }
    struct Package: Codable { var version: Int; var state: KnockState; var samples: [Sample] }
    enum PackageError: LocalizedError {
        case invalid, tooLarge, missing(String), missingStock(String), unreadableStock(String)
        var errorDescription: String? {
            switch self {
            case .invalid: return "This is not a supported BreakBoss preset package."
            case .tooLarge: return "This preset exceeds the 64 MB portable sample limit."
            case .missing(let name): return "The preset needs a missing sample: \(name)."
            case .missingStock(let name): return "The preset needs a missing stock sample: \(name)."
            case .unreadableStock(let name): return "The preset's stock sample cannot be read: \(name)."
            }
        }
    }
    static let maxBytes = 64 * 1024 * 1024
    static let maxPackageBytes = 90 * 1024 * 1024

    static func write(_ state: KnockState, stockLibrary: StockSampleLibrary = .bundled) throws -> URL {
        // Stock references become embedded sample keys only in this export copy. The live
        // preset still uses the factory kit, and older v1 package readers can import the audio.
        var exportState = state.normalized()
        var sources: [String: URL] = [:]
        for path in Set(exportState.pads.compactMap { $0.sampleFile }) {
            sources[path] = SampleLoader.urlInSamples(path)
        }
        var stockKeys: [URL: String] = [:]
        var stockNames: [String: String] = [:]
        let kitID = KitLibrary.kit(id: exportState.kitID).id
        for pad in exportState.pads.indices where exportState.pads[pad].sampleFile == nil {
            guard let stock = stockLibrary.sample(kitID: kitID, pad: pad) else { continue }
            let source = stock.url.resolvingSymlinksInPath().standardizedFileURL
            let key: String
            if let existing = stockKeys[source] {
                key = existing
            } else {
                var candidate: String
                repeat {
                    candidate = "stock-" + UUID().uuidString + "." + source.pathExtension.lowercased()
                } while sources[candidate] != nil
                key = candidate
                stockKeys[source] = key
                stockNames[key] = stock.displayName
                sources[key] = source
            }
            exportState.pads[pad].sampleFile = key
        }

        var samples: [Sample] = []
        var total = 0
        for path in sources.keys.sorted() {
            let url = sources[path]!
            guard FileManager.default.fileExists(atPath: url.path) else {
                if let name = stockNames[path] { throw PackageError.missingStock(name) }
                throw PackageError.missing(path)
            }
            let size: Int
            do { size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? maxBytes + 1 }
            catch {
                if let name = stockNames[path] { throw PackageError.unreadableStock(name) }
                throw error
            }
            guard size <= maxBytes - total else { throw PackageError.tooLarge }
            let data: Data
            do {
                if stockNames[path] != nil { _ = try SampleLoader.load(url) }
                data = try Data(contentsOf: url)
            } catch {
                if let name = stockNames[path] { throw PackageError.unreadableStock(name) }
                throw error
            }
            total += data.count
            guard total <= maxBytes else { throw PackageError.tooLarge }
            samples.append(Sample(path: path, bytes: data))
        }
        let package = Package(version: 1, state: exportState, samples: samples)
        let data = try JSONEncoder().encode(package)
        guard data.count <= maxPackageBytes else { throw PackageError.tooLarge }
        let name = KnockFolders.safe(state.presetName == "INIT" ? state.kitName : state.presetName)
        let url = KnockFolders.exports.appendingPathComponent(name + "-" + UUID().uuidString.prefix(8)).appendingPathExtension("bbpack")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func read(_ url: URL) throws -> KnockState {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= maxPackageBytes else { throw PackageError.tooLarge }
        let package = try JSONDecoder().decode(Package.self, from: Data(contentsOf: url))
        guard package.version == 1, package.samples.count <= Pad.count else { throw PackageError.invalid }
        var state = package.state.normalized()
        var mapping: [String: String] = [:]
        var made: [URL] = []
        var committed = false
        defer { if !committed { for file in made { try? FileManager.default.removeItem(at: file) } } }
        var total = 0
        for sample in package.samples {
            total += sample.bytes.count
            guard total <= maxBytes else { throw PackageError.tooLarge }
            guard mapping[sample.path] == nil else { throw PackageError.invalid }
            let ext = (sample.path as NSString).pathExtension.lowercased()
            guard ["wav", "aif", "aiff", "caf", "mp3", "m4a", "flac", "aac"].contains(ext) else { throw PackageError.invalid }
            let name = UUID().uuidString + "." + ext
            let destination = SampleLoader.urlInSamples(name)
            try sample.bytes.write(to: destination, options: .atomic)
            made.append(destination)
            _ = try SampleLoader.load(destination)
            mapping[sample.path] = name
        }
        for i in state.pads.indices {
            if let old = state.pads[i].sampleFile {
                guard let name = mapping[old] else { throw PackageError.missing(old) }
                state.pads[i].sampleFile = name
            }
        }
        state.userKit = nil
        committed = true
        return state
    }
}

struct PortablePresetView: View {
    @ObservedObject var controller: KnockController
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var working = false
    @State private var url: URL?
    @State private var error: String?
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("Share your current kit, all 12 pad settings, imported audio, patterns, and processing controls in one .bbpack file.")
                    Button(working ? "Preparing…" : "Prepare complete preset") { makePackage() }.disabled(working)
                    if let url { ShareLink(item: url) { Label("Share / save preset", systemImage: "square.and.arrow.up") } }
                    Button("Import .bbpack preset") { importing = true }.disabled(working)
                    Text("After import, use SAVE on the faceplate to keep a named preset.").font(.footnote)
                }
                if let error { Section { Text(error).foregroundColor(.red) } }
            }
            .navigationTitle("Portable presets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.navigationViewStyle(.stack).preferredColorScheme(.dark)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let file = urls.first { importPackage(file) }
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
    private func makePackage() {
        working = true; error = nil; url = nil
        let state = controller.state
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PortablePreset.write(state) }
            DispatchQueue.main.async {
                working = false
                switch result { case .success(let file): url = file; case .failure(let failure): error = failure.localizedDescription }
            }
        }
    }
    private func importPackage(_ file: URL) {
        working = true; error = nil; url = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PortablePreset.read(file) }
            DispatchQueue.main.async {
                working = false
                switch result {
                case .success(var state): state.midiMap = controller.state.midiMap; state.midiCustomNotes = controller.state.midiCustomNotes; controller.restore(state); controller.notice = "Portable preset loaded."
                case .failure(let failure): error = failure.localizedDescription
                }
            }
        }
    }
}
