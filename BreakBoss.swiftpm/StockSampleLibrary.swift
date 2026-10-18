// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

/// Curated factory audio is bundled with the app, separate from the user's Samples folder.
/// No manifest means the original synthesized kits. Imported pad audio always takes priority.
struct StockSampleLibrary {
    struct Assignment: Decodable {
        let kitID: String
        let pad: Int
        let file: String
        let displayName: String
    }

    /// One sound in the library, in a kit or not (named by category: "KICK BOOM 07").
    struct Sound: Decodable {
        let file: String
        let name: String
    }

    private struct Manifest: Decodable {
        let version: Int
        let assignments: [Assignment]
        let sounds: [Sound]?
    }

    struct Sample {
        let url: URL
        let displayName: String
    }

    /// One velocity layer of a multisampled sound (the acoustic drums, acoustic_layers.json):
    /// the hardest hit it takes (0...1) and its round robins.
    struct Layer {
        let top: Float
        let urls: [URL]
    }

    private struct LayerFile: Decodable {
        struct Entry: Decodable { let hi: Float; let files: [String] }
        let version: Int
        let sounds: [String: [Entry]]
    }

    enum ManifestError: LocalizedError {
        case tooLarge, invalid, unsupportedVersion, invalidAssignment, duplicateAssignment

        var errorDescription: String? {
            switch self {
            case .tooLarge: return "The stock sample manifest is too large."
            case .invalid: return "The stock sample manifest cannot be read."
            case .unsupportedVersion: return "The stock sample manifest version is unsupported."
            case .invalidAssignment: return "The stock sample manifest contains an invalid assignment."
            case .duplicateAssignment: return "The stock sample manifest assigns a pad more than once."
            }
        }
    }

    private let samples: [String: [Int: Sample]]
    /// Each multisampled sound's layers, softest first, by the sound's file name.
    private let layers: [String: [Layer]]
    /// Every stock sound, sorted by category (the sound menu lists these).
    let allSounds: [Sample]
    /// Shown by the controller when an installed pack cannot be used.
    let failure: String?

    private init(samples: [String: [Int: Sample]] = [:], layers: [String: [Layer]] = [:], allSounds: [Sample] = [], failure: String? = nil) {
        self.samples = samples
        self.layers = layers
        self.allSounds = allSounds
        self.failure = failure
    }

    static let bundled: StockSampleLibrary = {
        // Uses the app's Playgrounds-compatible lookup, including flattened SwiftPM resources.
        guard let manifestURL = knockResourceURL("manifest", "json") else { return StockSampleLibrary() }
        do {
            return try load(manifestURL: manifestURL, knownKitIDs: Set(KitLibrary.factory.map { $0.id }), padCount: Pad.count)
        } catch {
            return StockSampleLibrary(failure: error.localizedDescription)
        }
    }()

    func sample(kitID: String, pad: Int) -> Sample? { samples[kitID]?[pad] }

    /// The velocity layers of a multisampled stock sound (nil: one sample plays every hit).
    func layers(for sample: Sample) -> [Layer]? { layers[sample.url.lastPathComponent] }

    /// Every kit that has stock audio for this pad (the home-screen dice draws from these).
    func kits(withPad pad: Int) -> [String] { samples.keys.sorted().filter { samples[$0]?[pad] != nil } }

    /// All file names are relative basenames in the manifest's directory. Audio decoding and
    /// per-file failures are handled off the main thread by the normal kit loader.
    static func load(manifestURL: URL, knownKitIDs: Set<String>, padCount: Int) throws -> StockSampleLibrary {
        let maxBytes = 1024 * 1024  // 362 kits x 12 pads is about 400 KB
        guard let size = try? manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw ManifestError.invalid }
        guard size <= maxBytes else { throw ManifestError.tooLarge }
        let data: Data
        do { data = try Data(contentsOf: manifestURL) } catch { throw ManifestError.invalid }
        guard data.count <= maxBytes else { throw ManifestError.tooLarge }
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: data) } catch { throw ManifestError.invalid }
        guard manifest.version == 1 else { throw ManifestError.unsupportedVersion }
        let (maxAssignments, overflow) = knownKitIDs.count.multipliedReportingOverflow(by: padCount)
        guard padCount > 0, !overflow, manifest.assignments.count <= maxAssignments else { throw ManifestError.invalidAssignment }

        let folder = manifestURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let safeFilename = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        let extensions: Set<String> = ["wav", "aif", "aiff", "caf"]
        func sample(file: String, displayName: String) throws -> Sample {
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !file.isEmpty, file.count <= 128,
                  file.unicodeScalars.allSatisfy({ safeFilename.contains($0) }),
                  extensions.contains((file as NSString).pathExtension.lowercased()),
                  !name.isEmpty, name.count <= 80,
                  !displayName.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            else { throw ManifestError.invalidAssignment }
            let url = folder.appendingPathComponent(file).resolvingSymlinksInPath().standardizedFileURL
            guard url.deletingLastPathComponent() == folder else { throw ManifestError.invalidAssignment }
            return Sample(url: url, displayName: name)
        }
        var samples: [String: [Int: Sample]] = [:]
        for assignment in manifest.assignments {
            guard knownKitIDs.contains(assignment.kitID), (0..<padCount).contains(assignment.pad)
            else { throw ManifestError.invalidAssignment }
            guard samples[assignment.kitID]?[assignment.pad] == nil else { throw ManifestError.duplicateAssignment }
            samples[assignment.kitID, default: [:]][assignment.pad] = try sample(file: assignment.file, displayName: assignment.displayName)
        }
        guard (manifest.sounds?.count ?? 0) <= 4096 else { throw ManifestError.invalidAssignment }
        let all = try (manifest.sounds ?? []).map { try sample(file: $0.file, displayName: $0.name) }
        // Multisampled sounds: a layer file that can't be used leaves that sound as one sample.
        var layers: [String: [Layer]] = [:]
        let layerURL = folder.appendingPathComponent("acoustic_layers.json")
        if let data = try? Data(contentsOf: layerURL), data.count <= maxBytes,
           let file = try? JSONDecoder().decode(LayerFile.self, from: data), file.version == 1 {
            let known = Set(all.map { $0.url.lastPathComponent })
            for (main, entries) in file.sounds where known.contains(main) && !entries.isEmpty && entries.count <= 16 {
                let parsed = entries.compactMap { e -> Layer? in
                    guard e.hi.isFinite, e.hi > 0, !e.files.isEmpty, e.files.count <= 8,
                          let urls = try? e.files.map({ try sample(file: $0, displayName: main).url }) else { return nil }
                    return Layer(top: min(e.hi, 1), urls: urls)
                }
                if parsed.count == entries.count { layers[main] = parsed.sorted { $0.top < $1.top } }
            }
        }
        return StockSampleLibrary(samples: samples, layers: layers, allSounds: all)
    }
}
