// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import AVFoundation
import UIKit

// MARK: - Self-test: Kits, stock sounds, sound swaps, track FX and fresh sounds

extension KnockSelfTest {
    static func checkKits() {
        for def in KitLibrary.factory {
            check(def.pads.count == Pad.count, "\(def.name): 12 pads")
            for (i, r) in def.pads.enumerated() {
                let b = DrumSynth.render(r, sampleRate: 48_000, seed: 7)
                var peak: Float = 0
                var finite = true
                for k in 0..<b.length {
                    let v = max(abs(b.left[k]), abs(b.right[k]))
                    if !v.isFinite { finite = false; break }
                    peak = max(peak, v)
                }
                check(finite, "\(def.name) pad \(i + 1) finite")
                check(peak > 0.2 && peak <= 1.0, "\(def.name) pad \(i + 1) level \(peak)")
                check(b.seconds < 4, "\(def.name) pad \(i + 1) length \(b.seconds)")
            }
        }
        // Dice variations stay sensible
        var rng = KRandom(seed: 99)
        for r in KitLibrary.modernTrap.pads {
            let v = r.varied(&rng)
            let b = DrumSynth.render(v, sampleRate: 44_100, seed: 3)
            check(b.length > 100, "varied \(r.label) renders")
        }
    }

    /// Validate the shipped audio through the same AVAudioFile decoder as the normal kit
    /// loader. This optional off-callback suite retains URLs only, and releases each decoded
    /// buffer before opening the next file instead of keeping the whole sound bank in RAM.
    static func checkStockSamples() {
        #if canImport(AVFoundation)
        let manifestExists = knockResourceURL("manifest", "json") != nil
        check(manifestExists, "stock audio manifest is bundled")
        guard manifestExists else { return }
        let library = StockSampleLibrary.bundled
        check(library.failure == nil, "stock audio manifest loads: \(library.failure ?? "OK")")
        guard library.failure == nil else { return }

        let urls = Set(library.allSounds.map(\.url))
        // Nov 12: the stock sounds ship as Apple Lossless (.caf) under their old "<name>.wav" names, and decode to
        // exactly the samples the WAVs held: each one's length and a hash of its 16-bit samples
        // (tools/compress_stock_sounds.py, stock_pcm.json).
        struct PCM: Decodable { let frames: Int; let channels: Int; let fnv: String }
        struct PCMTable: Decodable { let version: Int; let sounds: [String: PCM] }
        let pcm = knockResourceURL("stock_pcm", "json").flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(PCMTable.self, from: $0) }?.sounds ?? [:]
        check(pcm.count >= urls.count, "stock_pcm.json lists every stock sound (\(pcm.count))")
        check(urls.allSatisfy { $0.pathExtension == "wav" && SampleLoader.stockFile($0).pathExtension == "caf" },
              "every stock sound keeps its .wav name and is read from its Apple Lossless .caf")
        func exact(_ url: URL, _ buffer: SampleBuffer) -> Bool {
            guard let want = pcm[url.lastPathComponent], want.frames == buffer.length,
                  (want.channels == 2) == buffer.stereo, buffer.bitDepth == 16 else { return false }
            var h: UInt64 = 0xcbf2_9ce4_8422_2325
            func add(_ x: Float) {
                let v = UInt16(bitPattern: Int16(clamping: Int((x * 32_768).rounded())))
                h = (h ^ UInt64(v)) &* 0x0000_0100_0000_01b3
            }
            for frame in 0..<buffer.length {
                add(buffer.left[frame])
                if buffer.stereo { add(buffer.right[frame]) }
            }
            return String(format: "%016llx", h) == want.fnv
        }
        // crashes ring out: Tyrone's own (Oct 20) run up to 12.8 s of audible tail
        let cymbals = Set(library.allSounds.filter { SoundType.forStockName($0.displayName) == .cymbal }.map(\.url))
        let names = library.allSounds.map(\.displayName)
        check(library.allSounds.count == 771 && urls.count == 771 && Set(names).count == 771, "the sound library holds 771 sounds (589 + 140 BK + 42 BK acoustic), each with its own name")
        check(names.allSatisfy { SoundType.forStockName($0) != nil }, "every stock sound's name ends in what it is")
        check(SoundType.forStockName("BK NO 60 OPEN HAT") == .open && SoundType.forStockName("BK NO 66 HIHAT") == .hat
              && SoundType.forStockName("BK NO 15 C1 808") == .bass && SoundType.forStockName("BK NO 64 SNARE") == .snare,
              "a stock sound's last word sorts it")
        check(library.librarySounds().count == 771, "the sound menu lists every stock sound, in a kit or not")
        // Tyrone, Oct 19: every sound sits in the section of the folder it came from
        let sections = Dictionary(library.librarySounds().map { ($0.name, $0.type) }, uniquingKeysWith: { a, _ in a })
        check(library.allSounds.allSatisfy { $0.section.flatMap(SoundType.init(section:)) != nil }, "every stock sound has its folder's section")
        check(sections["BK NO 2 TOM"] == .perc && sections["BK NO 2 RIDE"] == .hat && sections["BK NO 40 CLAP"] == .snare
              && sections["BK NO 60 OPEN HAT"] == .open && sections["BK NO 9 KICK"] == .kick,
              "a sound's library section is its original folder's (a tom from a percs folder is a PERC)")
        // Tyrone, Oct 25: no producer tags on any sound, stock or imported
        check(!names.contains { $0.contains("@") || $0.uppercased().contains("PROD") || $0.contains("IIINFINITE") }
              && library.librarySounds().allSatisfy { !$0.name.contains("@") },
              "no stock sound carries a producer's tag")
        check(KnockFolders.untagged("[Kick] Waves - (@prod.by.iiinfinite).wav") == "[Kick] Waves.wav"
              && KnockFolders.untagged("[Lazer] 4 - @prod.by.iiinfinite") == "[Lazer] 4"
              && KnockFolders.untagged("Big Snare (prod. by Someone)") == "Big Snare"
              && KnockFolders.untagged("Pack/808 Hands @maker.wav") == "Pack/808 Hands.wav"
              && KnockFolders.untagged("My Kick 2.wav") == "My Kick 2.wav",
              "an imported sound's name is shown without its producer tag")
        // Tyrone, Oct 26: every sound in Samples shows a Break King name, never its old file name
        let picks = SampleNames.shared
        check(KnockFolders.soundName("bb_2000s-rnb_p00.wav") == "BK NO 9 V2 KICK"
              && KnockFolders.soundName("Edits/bb_2000s-rnb_p00 edit 2.wav") == "BK NO 9 V2 KICK EDIT 2"
              && library.allSounds.allSatisfy { KnockFolders.soundName($0.url.lastPathComponent) == $0.displayName }
              && picks.fresh("!Go2Spinz - (@prod.byiiinfinite)", "!Go2Spinz - (@prod.byiiinfinite)", taken: [:]) == "BK NO 5 808"
              && picks.fresh("x", "!Go2Spinz - (@prod.byiiinfinite)", taken: ["a": "BK NO 5 808"]) == "BK NO 5 V2 808"
              && picks.fresh("(clap) aspen", "(clap) aspen", taken: [:]) == "BK MY 1 CLAP"
              && picks.fresh("(clap) aspen", "(clap) aspen", taken: ["a": "BK MY 1 CLAP", "b": "BK MY 4 KICK"]) == "BK MY 2 CLAP"
              && picks.fresh("Pack/808s/Big", "Big", taken: [:]) == "BK MY 1 808",
              "a Samples sound's name: an old stock copy is that sound now, a pack sound its family, yours BK MY n KIND")
        let tempSamples = FileManager.default.temporaryDirectory.appendingPathComponent("bb-names-test/Samples", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempSamples, withIntermediateDirectories: true)
        let odd = tempSamples.appendingPathComponent("!Go2Spinz - (@prod.byiiinfinite).wav")
        FileManager.default.createFile(atPath: odd.path, contents: Data([0]))
        let walked = (FileManager.default.enumerator(at: tempSamples, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
        let viaPrivate = odd.path.hasPrefix("/var/") ? URL(fileURLWithPath: "/private" + odd.path) : odd
        check(walked.count == 1 && walked.allSatisfy { KnockFolders.relative($0, in: tempSamples) == odd.lastPathComponent }
              && KnockFolders.relative(viaPrivate, in: tempSamples) == odd.lastPathComponent
              && KnockFolders.relative(odd, in: tempSamples.deletingLastPathComponent()) == "Samples/" + odd.lastPathComponent
              && KnockFolders.relative(tempSamples, in: tempSamples) == nil,
              "a Samples file's own name comes back whole, however the iPad spells the folder (no \"private!Go2Spinz\")")
        try? FileManager.default.removeItem(at: tempSamples.deletingLastPathComponent())
        check(SoundType.guess("Danger Demon/Kicks/808 Kick.wav") == .kick && SoundType.guess("Pack/808s/Big.wav") == .bass
              && SoundType.guess("Pack/OHH/Hat 3.wav") == .open && SoundType.guess("Pack/Hi-Hats/Open Thing.wav") == .hat
              && SoundType.guess("Pack/Snares/Clap Layer.wav") == .snare && SoundType.guess("Pack/[Kick] Astronomy.wav") == .kick
              && SoundType.guess("My Sounds/random.wav") == .fx && SoundType.guess("Pack/Open Hats/a.wav") == .open
              && SoundType.guess("Pack/HI HATS/a.wav") == .hat && SoundType.guess("Pack/FX & OTHER/a.wav") == .fx,
              "an imported sound's folder decides its section, then its name")
        // Tyrone, Oct 27: "ALL Rock and Live soul kits need to use ALL acoustic sounds" (tools/kit_catalog.py ACOUSTIC_GENRES),
        // except in Modern (Nov 8: "none of the modern kits should have acoustic samples")
        let acousticGenres: Set<String> = ["ROCK", "POP ROCK", "LIVE ROCK", "SOFT ROCK", "ARENA ROCK", "LIVE SOUL"]
        func acousticKit(_ kit: KitDefinition) -> Bool {
            kit.preferredMode == .vintage || (acousticGenres.contains(kit.genre) && kit.preferredMode != .modern)
        }
        var assignments = 0, empties = 0
        for kit in KitLibrary.factory {
            for pad in Pad.allCases {
                let sample = library.sample(kitID: kit.id, pad: pad.rawValue)
                if library.isEmpty(kitID: kit.id, pad: pad.rawValue) {
                    check(sample == nil, "\(kit.name) pad \(pad.rawValue + 1) is EMPTY and has no sound")
                    empties += 1
                    continue
                }
                check(sample != nil, "\(kit.name) pad \(pad.rawValue + 1) has bundled stock audio")
                guard let sample else { continue }
                assignments += 1
                check(urls.contains(sample.url), "\(kit.name) pad \(pad.rawValue + 1) plays a sound from the library")
                // Each pad holds its own kind of sound (the rim pad may take a short snare, the perc pads an FX).
                let kind = SoundType.forStockName(sample.displayName)
                let fits: Bool
                switch pad {
                case .rim: fits = kind == .rim || kind == .snare
                case .perc1, .perc2: fits = kind == .perc || kind == .fx
                default: fits = kind == SoundType.forPad(pad.rawValue)
                }
                check(fits, "\(kit.name) pad \(pad.rawValue + 1) holds a sound of its kind (\(sample.displayName))")
            }
            let played = Pad.allCases.compactMap { library.sample(kitID: kit.id, pad: $0.rawValue)?.url }
            check(Set(played).count == played.count, "\(kit.name) plays no sound on two pads")
            let pair = KitLibrary.factory.filter { $0.genre == kit.genre }
            let mine = Set(played)
            // Vintage kits and the acoustic-only genres (Oct 26, 27) share drums once Tyrone's acoustic pack runs out of a kind;
            // Bay Area kits are the sounds of his own loops, some loops share a hat or kick, and all play the Go2Spinz 808 (Oct 27);
            // the 20 West Coast kits outnumber the iiinfinite kicks and claps they may play (Nov 8), so they share those
            for other in pair where other.id != kit.id && !acousticKit(kit) && kit.genre != "BAY AREA" && kit.genre != "WEST COAST" {
                let theirs = Set(Pad.allCases.compactMap { library.sample(kitID: other.id, pad: $0.rawValue)?.url })
                check(mine.isDisjoint(with: theirs), "\(kit.name) and \(other.name) share no sounds")
            }
        }
        check(assignments + empties == KitLibrary.factory.count * Pad.count, "stock audio covers every factory pad that isn't EMPTY")
        // Tyrone, Oct 20: a kit from a loop holds only the sounds that loop plays
        for id in ["bk-editions-kit", "bk-danger-kit"] {
            check((0..<6).allSatisfy { library.sample(kitID: id, pad: $0) != nil } && (6..<Pad.count).allSatisfy { library.isEmpty(kitID: id, pad: $0) },
                  "\(id): its loops' 6 sounds, pads 7-12 EMPTY")
        }
        // Home dice draws each pad's sound from every kit's sound for that pad.
        check(Pad.allCases.allSatisfy { pad in
            library.kits(withPad: pad.rawValue).count == KitLibrary.factory.filter { !library.isEmpty(kitID: $0.id, pad: pad.rawValue) }.count
        }, "dice: every pad has a sound in every kit that doesn't leave it EMPTY")
        var picked = KnockState(); picked.stockPicks = Array(repeating: nil, count: Pad.count); picked.stockPicks?[0] = "detroit-2026-a"
        check(KnockController.stockPick(picked, pad: 0) == "detroit-2026-a" && KnockController.stockPick(picked, pad: 1) == nil, "dice: per-pad picks")
        check(picked.selectingKit(KitLibrary.factory[1]).stockPicks == nil, "dice: choosing a kit brings its own sounds back")
        // The acoustic drums: every sound multisampled, softest layer first, the loudest one the sound itself.
        let acoustic = library.allSounds.filter { $0.url.lastPathComponent.hasPrefix("ac_") }
        check(acoustic.count == 12 && acoustic.allSatisfy { (library.layers(for: $0)?.count ?? 0) >= 3 },
              "acoustic drums: 12 multisampled sounds, each with its velocity layers")
        // Tyrone's acoustic pack (tools/build_vintage_acoustic.py): 42 sounds, all but the 6 rolls and riffs multisampled
        let vintage = library.allSounds.filter { $0.url.lastPathComponent.hasPrefix("va_") }
        check(vintage.count == 42 && vintage.filter { (library.layers(for: $0)?.count ?? 0) >= 3 }.count == 36,
              "Vintage acoustic drums: 42 sounds, 36 of them with velocity layers")
        // Vintage is acoustic only (Oct 26), and so is every Rock and Live Soul kit in any bank (Oct 27): only these
        // and the 12 above, never an 808, and a rock or soul kit always has its kick and snare (salsa and bossa have no snare)
        for kit in KitLibrary.factory where acousticKit(kit) {
            let played = Pad.allCases.compactMap { library.sample(kitID: kit.id, pad: $0.rawValue)?.url.lastPathComponent }
            let onlyAcoustic: Bool = !played.isEmpty && played.allSatisfy { $0.hasPrefix("ac_") || $0.hasPrefix("va_") }
            let kickSnare: Bool = library.sample(kitID: kit.id, pad: Pad.kick.rawValue) != nil
                && library.sample(kitID: kit.id, pad: Pad.snare.rawValue) != nil
            let no808: Bool = library.isEmpty(kitID: kit.id, pad: Pad.bass808.rawValue)
            let bank: String = kit.preferredMode == .vintage ? "Vintage" : kit.genre
            check(onlyAcoustic && no808 && (kickSnare || !acousticGenres.contains(kit.genre)),
                  "\(kit.name): a \(bank) kit plays only acoustic drums")
        }
        check(KitLibrary.factory.filter { acousticGenres.contains($0.genre) && $0.preferredMode != .modern }.count == 7,
              "7 Rock and Live Soul kits outside Modern, all acoustic")
        // Tyrone, Nov 8: no Modern kit plays an acoustic drum, and every Modern or Texture WEST COAST kit (Bay Area,
        // West Coast, Hyphy...) plays only sounds from his @prod.by.iiinfinite folders (the Go2Spinz 808 stays on every Bay Area 808 pad)
        let modernAcoustic: [String] = KitLibrary.factory.filter { $0.preferredMode == .modern }.flatMap { (kit: KitDefinition) -> [String] in
            Pad.allCases.compactMap { library.sample(kitID: kit.id, pad: $0.rawValue)?.url.lastPathComponent }
        }.filter { (f: String) -> Bool in f.hasPrefix("ac_") || f.hasPrefix("va_") }
        check(modernAcoustic.isEmpty, "no Modern kit plays an acoustic drum (\(modernAcoustic.prefix(3)))")
        let westFiles: Set<String> = Set(KitLibrary.factory.filter { $0.family == "WEST COAST" && $0.preferredMode != .vintage }.flatMap { (kit: KitDefinition) -> [String] in
            Pad.allCases.compactMap { library.sample(kitID: kit.id, pad: $0.rawValue)?.url.lastPathComponent }
        })
        let notIiinfinite: Set<String> = westFiles.subtracting(KitLibrary.iiinfiniteFiles).subtracting(["bb_808_d1_08.wav"])
        check(notIiinfinite.isEmpty, "WEST COAST kits play only @prod.by.iiinfinite sounds (\(notIiinfinite.sorted().prefix(3)))")
        for sound in acoustic + vintage where library.layers(for: sound) != nil {
            let layers = library.layers(for: sound) ?? []
            check(layers.last?.top == 1 && zip(layers, layers.dropFirst()).allSatisfy { $0.0.top < $0.1.top }
                  && layers.last?.urls.contains(sound.url) == true,
                  "\(sound.displayName): layers rise to full velocity and end on the sound itself")
            for url in layers.flatMap(\.urls) where !urls.contains(url) {
                autoreleasepool {
                    guard let buffer = try? SampleLoader.load(url) else { check(false, "\(url.lastPathComponent): acoustic layer decodes"); return }
                    var peak: Float = 0
                    for frame in 0..<buffer.length { peak = max(peak, max(abs(buffer.left[frame]), abs(buffer.right[frame]))) }
                    check(abs(buffer.sampleRate - 48_000) < 1 && buffer.length > 0 && buffer.seconds <= 4 && peak.isFinite
                          && peak > 0.000_1 && peak <= stockLoudnessCeiling * 1.002,
                          "\(url.lastPathComponent): acoustic layer at 48 kHz, bounded and audible")
                    check(exact(url, buffer), "\(url.lastPathComponent): acoustic layer decodes to its exact 16-bit samples")
                }
            }
        }
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            autoreleasepool {
                do {
                    let buffer = try SampleLoader.load(url)
                    check(abs(buffer.sampleRate - 48_000) < 1, "\(url.lastPathComponent): decodes at 48 kHz")
                    check(buffer.length > 0 && buffer.seconds <= (cymbals.contains(url) ? 13 : 4), "\(url.lastPathComponent): bounded stock duration")
                    var peak: Float = 0
                    var finite = true
                    for frame in 0..<buffer.length {
                        let left = buffer.left[frame], right = buffer.right[frame]
                        if !left.isFinite || !right.isFinite { finite = false; break }
                        peak = max(peak, max(abs(left), abs(right)))
                    }
                    check(finite, "\(url.lastPathComponent): decoded stereo audio is finite")
                    check(peak > 0.005 && peak <= 1.000_01, "\(url.lastPathComponent): decoded stock audio is audible and bounded")
                    check(exact(url, buffer), "\(url.lastPathComponent): decodes to its exact 16-bit samples (length and hash)")
                } catch {
                    check(false, "\(url.lastPathComponent): stock audio decodes (\(error.localizedDescription))")
                }
            }
        }
        #endif
    }

    // The acoustic layers' peak ceiling (tools/build_acoustic_sounds.py; the pack sounds are their original files).
    static let stockLoudnessCeiling: Float = 0.944  // -0.5 dBFS

    /// Tyrone, Oct 18: a track switched from a kick to a hat or clap (and back) must play the new
    /// sound, from the sound library, the rack, the notes and the Face 1 pads alike, and pattern and
    /// kit changes must not undo it. Drives the controller the way the screen does and listens to the engine.
    static func checkSoundSwap() {
        #if canImport(AVFoundation)
        let all = StockSampleLibrary.bundled.librarySounds()
        let kitKickURL = StockSampleLibrary.bundled.sample(kitID: KnockState().kitID, pad: 0)?.url
        guard let hat = all.first(where: { $0.type == .hat }), let clap = all.first(where: { $0.type == .clap }),
              let kick = all.first(where: { $0.type == .kick && $0.url != kitKickURL }) else {
            check(false, "sound swap: the library has a kick, a clap and a hat"); return
        }
        // A MY SOUNDS copy of a stock sound that was levelled (same name and size, other audio) goes back
        // to the original; a different file of yours with that name stays.
        let hatFile = SampleLoader.stockFile(hat.url)
        if let original = try? Data(contentsOf: hatFile), original.count > 100 {
            let copy = KnockFolders.samples.appendingPathComponent(hatFile.lastPathComponent)
            var levelled = original; levelled[levelled.count - 2] ^= 0x5A; levelled[levelled.count - 40] ^= 0x33
            try? levelled.write(to: copy)
            let n = SampleLoader.restoreStockCopies([hat.url])
            check(n == 1 && (try? Data(contentsOf: copy)) == original, "MY SOUNDS: a levelled copy of a stock sound goes back to the original")
            let mine = Data(original.prefix(original.count / 2))
            try? mine.write(to: copy)
            SampleLoader.restoreStockCopies([hat.url])
            check((try? Data(contentsOf: copy)) == mine, "MY SOUNDS: your own file with a stock sound's name is left alone")
            try? FileManager.default.removeItem(at: copy)
        }
        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        var rcOpt: KnockController?
        DispatchQueue.main.sync { rcOpt = KnockController(engine: engine, isPlugin: true) }
        guard let rc = rcOpt else { return }
        let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                        (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0)]
        func onMain<T>(_ work: () -> T) -> T { var out: T?; DispatchQueue.main.sync { out = work() }; return out! }
        func render(_ frames: Int) -> [Float] {
            var out: [Float] = []
            var left = [Float](repeating: 0, count: 128), right = left
            for _ in 0..<(frames / 128) {
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in engine.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                out += left
            }
            return out
        }
        /// Waits for the main thread (keeps the engine running, as the audio thread would).
        func settle(_ seconds: Double = 4, _ done: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if onMain(done) { return true }
                _ = render(1_024)
                Thread.sleep(forTimeInterval: 0.01)
            }
            return onMain(done)
        }
        /// 24 log-spaced band energies: what a sound is, whatever its level.
        func bands(_ x: [Float]) -> [Double] {
            let n = 4_096
            var re = [Double](repeating: 0, count: n)
            for i in 0..<min(n, x.count) { re[i] = Double(x[i]) * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n))) }
            var out = [Double](repeating: 0, count: 24)
            for k in 1..<(n / 2) where k % 2 == 1 || k < 64 {
                var a = 0.0, b = 0.0
                for i in stride(from: 0, to: n, by: 1) { let w = 2 * Double.pi * Double(k * i) / Double(n); a += re[i] * cos(w); b -= re[i] * sin(w) }
                let f = Double(k) * 48_000 / Double(n)
                let band = min(23, max(0, Int(log2(f / 30) * 3)))
                out[band] += a * a + b * b
            }
            let total = out.reduce(0, +)
            return out.map { log10(1e-9 + $0 / max(total, 1e-12)) }
        }
        func distance(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + abs($1.0 - $1.1) } }
        func source(_ url: URL) -> [Float] { (try? SampleLoader.load(url)).map { Array(UnsafeBufferPointer(start: $0.left, count: $0.length)) } ?? [] }
        guard settle(10, { rc.kitSamples.count == Pad.count && !rc.loadingKit }) else { check(false, "sound swap: the kit loads"); return }
        for (p, v) in quiet { engine.setParam(p, v) }
        let kitKick = onMain({ rc.kitSamples[0] })
        let candidates: [(String, [Double])] = [("the kit's kick", bands(Array(UnsafeBufferPointer(start: kitKick.left, count: kitKick.length)))),
                                                (hat.name, bands(source(hat.url))), (clap.name, bands(source(clap.url))), (kick.name, bands(source(kick.url)))]
        /// What the track plays: the candidate its sound is nearest to.
        func heard(_ x: [Float]) -> String {
            let b = bands(x)
            return candidates.min { distance(b, $0.1) < distance(b, $1.1) }?.0 ?? "?"
        }
        func audition() -> String {
            _ = render(2_048)
            onMain { rc.auditionPad(0) }
            return heard(render(8_192))
        }
        log("sound swap: kick \(kick.name), clap \(clap.name), hat \(hat.name)")
        check(audition() == "the kit's kick", "sound swap: the kick track starts on the kit's kick")
        let kickTrack = onMain({ rc.rackChannels.first { $0.pad == 0 }! })
        // From the SOUNDS panel: tap a sound with the track selected (the screen auditions it once it's loaded).
        for sound in [hat, clap, kick, hat] {
            var ready = false
            onMain { rc.replaceRackSound(kickTrack.id, with: sound) { ready = true } }
            let start = Date()
            let loaded = settle { ready }
            log("sound swap: \(sound.name) loaded=\(loaded) after \(String(format: "%.2f", Date().timeIntervalSince(start))) s, file \(onMain({ rc.state.pads[0].sampleFile ?? "nil" }))")
            let early = audition()
            check(loaded && early == sound.name, "sound swap: the audition when \(sound.name) is picked plays \(sound.name) (heard \(early))")
            let now = audition()
            check(now == sound.name, "sound swap: the track plays \(sound.name) once it's picked (heard \(now))")
            check(onMain({ rc.rackChannels.first { $0.pad == 0 }!.name }) == sound.name, "sound swap: the rack names \(sound.name)")
        }
        check(onMain({ rc.state.pads[0].sampleFile })?.hasSuffix(".caf") == true && onMain({ rc.padName(0) }) == hat.name,
              "sound swap: a picked stock sound is copied as its Apple Lossless file and keeps its stock name")
        // Playing, kick track soloed, sounds picked while the pattern runs (Tyrone's video).
        if let preset = PatternBank.all.first(where: { $0.name.uppercased().contains("HYPHY") }) ?? PatternBank.all.first {
            onMain { rc.loadPatternPreset(preset); if !rc.soloPads[0] { rc.toggleSolo(0) } }
            _ = settle(0.3) { false }
            for (p, v) in quiet { engine.setParam(p, v) }
            engine.send(KEvent(kind: .play, value: 1))
            for sound in [clap, kick, hat] {
                onMain { rc.replaceRackSound(kickTrack.id, with: sound) }
                _ = settle(2) { rc.padName(0).uppercased() == sound.url.deletingPathExtension().lastPathComponent.uppercased() }
                _ = render(12_000)
                let beat = render(96_000)
                var loudest = 0, best: Float = 0
                for i in stride(from: 0, to: beat.count - 4_096, by: 256) { let e = beat[i..<(i + 512)].reduce(0) { $0 + $1 * $1 }; if e > best { best = e; loudest = i } }
                let h = heard(Array(beat[max(0, loudest - 256)...].prefix(4_096)))
                check(best > 0.000_1 && h == sound.name, "sound swap: the soloed track plays \(sound.name) in the pattern (heard \(h))")
            }
            engine.send(KEvent(kind: .stop))
            onMain { rc.clearSolos() }
            // A pattern change right after a pick must not lose the pick.
            var ready = false
            onMain { rc.replaceRackSound(kickTrack.id, with: clap) { ready = true }; rc.loadPatternPreset(preset) }
            _ = settle(3) { ready }
            for (p, v) in quiet { engine.setParam(p, v) }
            let afterPattern = audition()
            check(afterPattern == clap.name && onMain({ rc.rackChannels.first { $0.pad == 0 }!.name }) == clap.name,
                  "sound swap: a pattern change keeps the picked sound and its name (heard \(afterPattern))")
        }
        // A kit change brings the kit's own sounds back, rack and pads together.
        onMain { rc.selectKit(KitLibrary.factory[0]) }
        _ = settle(5) { !rc.loadingKit && rc.state.pads[0].sampleFile == nil }
        for (p, v) in quiet { engine.setParam(p, v) }
        let kitDef = KitLibrary.factory[0]
        let kitFile = StockSampleLibrary.bundled.sample(kitID: kitDef.id, pad: 0)
        let heardKit = { () -> Bool in
            _ = render(2_048); onMain { rc.auditionPad(0) }
            let b = bands(render(8_192))
            guard let kitFile else { return false }
            let k = bands(source(kitFile.url))
            return distance(b, k) < distance(b, bands(source(hat.url))) && distance(b, k) < distance(b, bands(source(clap.url)))
        }()
        check(heardKit && onMain({ rc.rackChannels.first { $0.pad == 0 }!.soundID }) == "kit", "sound swap: a kit change puts the kit's kick back on the track and in the rack")
        #endif
    }

    /// Tyrone, Oct 19: after a kit or pattern change some pads came out silent, quiet or out of tune, and
    /// the kick and 808 leaned to one side. Every kit and every new sound comes in as itself (its original
    /// pitch and level, centered, SAMPLER at SMP START 0%, LENGTH 100%, IN 0%, OUT 0%), whatever the last
    /// kit or sound had been set to, and plays exactly as a cold load of that kit.
    /// Face 2's FX knobs per track (Tyrone, Oct 19): a track's own knobs change that track and no
    /// other, each mode keeps its own, an untouched track sounds exactly as before, and they save.
    static func checkTrackFX() {
        let rate = 48_000.0
        var wave = [Float](repeating: 0, count: 48_000)
        for i in 0..<wave.count {
            let t = Float(i)
            let phase: Float = t * 2 * Float.pi * 180 / 48_000
            wave[i] = sinf(phase) * 0.45 * (1 - t / 60_000)
        }
        let tone = SampleBuffer(left: wave, sampleRate: rate)
        func render(_ pads: [PadSettings], mode: SoundMode, hit: Int, blocks: Int = 300) -> [Float] {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                            (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0), (.resample, 0), (.instability, 0),
                                            (.warp, 0), (.glitch, 0), (.soundMode, Float(mode.rawValue))]
            for (p, v) in quiet { e.setParam(p, v) }
            e.kitHandoff.publish(KitBuffers(name: "TRACK FX", samples: Array(repeating: tone, count: Pad.count), settings: pads, bassHz: 110))
            var out: [Float] = []
            var left = [Float](repeating: 0, count: 128), right = left
            for b in 0..<blocks {
                if b == 2 { e.send(KEvent(kind: .pad, a: Int32(hit), value: 1)) }
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                out += left
            }
            return out
        }
        func energy(_ x: [Float], from: Int = 0) -> Double {
            var e: Double = 0
            for i in from..<x.count { e += Double(x[i] * x[i]) }
            return e
        }
        func difference(_ a: [Float], _ b: [Float]) -> Double {
            var e: Double = 0
            for i in 0..<min(a.count, b.count) { let d = Double(a[i] - b[i]); e += d * d }
            return e
        }
        let plain = Array(repeating: PadSettings(), count: Pad.count)
        let a = Pad.kick.rawValue, b = Pad.snare.rawValue

        // an untouched track: no FX stored, and turning a knob back to its start leaves nothing behind
        var back = PadSettings(); back.setFX(.grit, .modern, 0.8); back.setFX(.grit, .modern, 0)
        check(PadSettings().fx == nil && back.fx == nil && back == PadSettings(), "track FX: a track starts untouched; a knob turned back to zero leaves nothing")
        check(!TrackFX.insert(PadSettings(), .texture).active && !TrackFX.insert(PadSettings(), .vintage).active,
              "track FX: an untouched track's insert does nothing in every mode")

        for mode in SoundMode.allCases {
            var pads = plain
            for p in TrackFX.params(mode) where p != .reverbDecay && p != .reverbPredelay && p != .tighten && p != .noise {
                pads[a].setFX(p, mode, p == .warp || p == .glitch ? 1 : 0.8)
            }
            let dryA = render(plain, mode: mode, hit: a), wetA = render(pads, mode: mode, hit: a)
            let dryB = render(plain, mode: mode, hit: b), withAB = render(pads, mode: mode, hit: b)
            let changed = difference(dryA, wetA) / max(energy(dryA), 1e-9)
            let leaked = difference(dryB, withAB) / max(energy(dryB), 1e-9)
            check(changed > 0.02, "track FX \(mode.title): track A's own knobs change A's sound (\(String(format: "%.3f", changed)))")
            check(leaked < 1e-6, "track FX \(mode.title): track A's knobs leave track B exactly as it was (\(leaked))")
            // the other modes' knobs on A stay where they were: nothing
            for other in SoundMode.allCases where other != mode {
                check(TrackFX.insert(pads[a], other).active == false, "track FX \(mode.title): \(other.title)'s knobs on the same track stay untouched")
            }
        }
        // TIGHTEN on one track shortens its tail and no other's
        var tight = plain; tight[a].setFX(.tighten, .modern, 1)
        let tailA = energy(render(tight, mode: .modern, hit: a), from: 20_000), plainTail = energy(render(plain, mode: .modern, hit: a), from: 20_000)
        let tailB = energy(render(tight, mode: .modern, hit: b), from: 20_000), plainB = energy(render(plain, mode: .modern, hit: b), from: 20_000)
        check(tailA < plainTail * 0.05 && abs(tailB - plainB) < plainB * 1e-6, "track FX: TIGHTEN on track A shortens A's tail only")
        // Texture's DELAY on a track: echoes after the hit has gone
        var echo = plain; echo[a].setFX(.textureDelay, .texture, 1)
        let late = energy(render(echo, mode: .texture, hit: a, blocks: 700), from: 60_000)
        let lateDry = energy(render(plain, mode: .texture, hit: a, blocks: 700), from: 60_000)
        check(late > lateDry * 4 + 1e-6, "track FX TEXTURE: DELAY on a track echoes that track (\(late) vs \(lateDry))")
        // saved with the track and restored
        var saved = PadSettings(); saved.setFX(.punch, .vintage, 0.6); saved.setFX(.instability, .texture, 0.3)
        let decoded = (try? JSONEncoder().encode(saved)).flatMap { try? JSONDecoder().decode(PadSettings.self, from: $0) }
        check(decoded == saved && decoded?.fxValue(.punch, .vintage) == 0.6 && decoded?.fxValue(.punch, .modern) == 0,
              "track FX: a track's knobs save and come back per mode")
        // a new kit brings every track in untouched
        var s = KnockState(); s.pads = Array(repeating: saved, count: Pad.count)
        check(s.selectingKit(KitLibrary.factory[1]).pads.allSatisfy { $0.fx == nil }, "track FX: a kit change brings every track in with its FX untouched")
    }

    static func checkFreshSounds() {
        #if canImport(AVFoundation)
        var tweaked = PadSettings()
        tweaked.level = 0.2; tweaked.pan = -1; tweaked.tune = 7; tweaked.decay = 0.3; tweaked.filter = 0.4; tweaked.reverse = true
        var sm = SamplerSettings()
        sm.start = 0.5; sm.length = 0.3; sm.fadeIn = 0.5; sm.fadeOut = 0.5; sm.rootNote = 48; sm.pitch = 0.5; sm.volume = 0.1; sm.startOffset = 0.4
        sm.setEnvelope(.volume) { $0.on = true; $0.hold = 0; $0.decay = 0.1; $0.sustain = 0 }
        tweaked.sampler = sm
        let fresh = Array(repeating: PadSettings(), count: Pad.count)
        var before = KnockState()
        before.pads = Array(repeating: tweaked, count: Pad.count)
        let acoustic = KitLibrary.factory.first { $0.id == "soul-session" } ?? KitLibrary.factory[KitLibrary.factory.count - 1]
        for kit in [KitLibrary.factory[1], acoustic] {
            check(before.selectingKit(kit).pads == fresh, "fresh sounds: \(kit.name) comes in with every pad as itself, whatever the last kit was set to")
        }
        let d = SamplerSettings()
        check(d.start == 0 && d.length == 1 && d.fadeIn == 0 && d.fadeOut == 0 && d.startOffset == 0 && d.rootNote == 60 &&
              d.pitch == 0 && d.fineTune == 0 && d.offline(bpm: 120) == nil,
              "fresh sounds: an untouched SAMPLER is SMP START 0%, LENGTH 100%, IN 0%, OUT 0%, at the sound's own pitch")

        // the kick and the 808 of every kit are centered (every stock file and velocity layer they play)
        let stock = StockSampleLibrary.bundled
        var seen = Set<String>(), leaning: [String] = []
        func lean(_ b: SampleBuffer) -> Double {
            var el = 0.0, er = 0.0
            for i in 0..<b.length { el += Double(b.left[i] * b.left[i]); er += Double(b.right[i] * b.right[i]) }
            return 10 * log10((el + 1e-12) / (er + 1e-12))
        }
        for kit in KitLibrary.factory {
            for pad in [Pad.kick.rawValue, Pad.bass808.rawValue] {
                guard let sample = stock.sample(kitID: kit.id, pad: pad) else { continue }
                let urls = [sample.url] + (stock.layers(for: sample) ?? []).flatMap { $0.urls }
                for url in urls where seen.insert("\(pad)/\(url.lastPathComponent)").inserted {
                    guard let raw = try? SampleLoader.load(url) else { continue }
                    let l = lean(KnockController.centered(raw, pad: pad))
                    if abs(l) > 0.1 { leaning.append("\(url.lastPathComponent) \(String(format: "%.2f", l)) dB") }
                }
            }
        }
        check(!seen.isEmpty && leaning.isEmpty, "fresh sounds: every kit's kick and 808 files play centered (\(seen.count) files; leaning: \(leaning.prefix(5)))")
        let hat = SampleBuffer(left: [0.5, -0.5, 0.25], right: [0.1, -0.1, 0.05], sampleRate: 48_000)
        check(KnockController.centered(hat, pad: Pad.hat.rawValue) === hat, "fresh sounds: pads other than the kick and 808 are left exactly as they are")
        // From here on a test controller saves a kit into Kits and copies a library sound into Samples:
        // the menu's run leaves the user's folders alone (Tyrone, Nov 1).
        if inApp {
            skipNote("the kit-change, library-pick, dice and saved-kit checks (they save a test kit in Kits and copy a sound into Samples)")
            return
        }

        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        var rcOpt: KnockController?
        DispatchQueue.main.sync { rcOpt = KnockController(engine: engine, isPlugin: true) }
        guard let rc = rcOpt else { return }
        let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                        (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0), (.pitch, 0.5), (.tune, 0.5)]
        func onMain<T>(_ work: () -> T) -> T { var out: T?; DispatchQueue.main.sync { out = work() }; return out! }
        func render(_ frames: Int) -> (l: [Float], r: [Float]) {
            var outL: [Float] = [], outR: [Float] = []
            var left = [Float](repeating: 0, count: 128), right = left
            for _ in 0..<(frames / 128) {
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in engine.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                outL += left; outR += right
            }
            return (outL, outR)
        }
        func settle(_ seconds: Double = 6, _ done: () -> Bool) -> Bool {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end {
                if onMain(done) { return true }
                _ = render(1_024)
                Thread.sleep(forTimeInterval: 0.01)
            }
            return onMain(done)
        }
        struct Hit { var l: Double; var r: Double; var crossings: Int }
        func hit(_ pad: Int) -> Hit {
            engine.send(KEvent(kind: .allOff))
            _ = render(12_288)                  // the last hit's tail and the effects die away first
            onMain { rc.auditionPad(pad) }
            let (l, r) = render(24_576)
            var c = 0
            for i in 1..<l.count where (l[i - 1] < 0) != (l[i] < 0) { c += 1 }
            return Hit(l: l.reduce(0) { $0 + Double($1 * $1) }, r: r.reduce(0) { $0 + Double($1 * $1) }, crossings: c)
        }
        func loadKit(_ kit: KitDefinition) -> Bool {
            onMain { rc.selectKit(kit) }
            let ok = settle { !rc.loadingKit && rc.kitSamples.count == Pad.count && rc.state.kitID == kit.id }
            _ = settle(0.3) { false }
            for (p, v) in quiet { engine.setParam(p, v) }
            return ok
        }
        let kitA = KitLibrary.factory[0]
        guard settle(10, { rc.kitSamples.count == Pad.count && !rc.loadingKit }), loadKit(kitA) else { check(false, "fresh sounds: the kit loads"); return }
        let cold = (0..<Pad.count).map(hit)
        // every pad set as far from the kit's own as it goes, then a pattern and two kit changes
        onMain { for p in 0..<Pad.count { rc.setPadSettings(p, tweaked) } }
        _ = settle(2) { false }
        if let preset = PatternBank.all.dropFirst(7).first { onMain { rc.loadPatternPreset(preset) } }
        _ = settle(1) { false }
        let switched = loadKit(acoustic) && loadKit(kitA)
        check(switched && onMain({ rc.state.pads }) == fresh, "fresh sounds: after a pattern and two kit changes every pad is as the kit made it")
        func compare(_ when: String) {
            for pad in 0..<Pad.count {
                let now = hit(pad), was = cold[pad]
                let level = (now.l + now.r) / max(was.l + was.r, 1e-12)
                let pitch = Double(now.crossings) / Double(max(1, was.crossings))
                check(was.l + was.r > 1e-6 && abs(level - 1) < 0.03 && abs(pitch - 1) < 0.03,
                      "fresh sounds: \(when), pad \(pad + 1) plays as a cold load of the kit (level ×\(String(format: "%.3f", level)), pitch ×\(String(format: "%.3f", pitch)))")
            }
        }
        compare("after kit changes")
        if let preset = PatternBank.all.dropFirst(31).first { onMain { rc.loadPatternPreset(preset) } }
        _ = settle(1) { false }
        for (p, v) in quiet { engine.setParam(p, v) }
        compare("after a pattern change")

        // kick and 808 centered as they play, through a drum machine kit and an acoustic kit (round robins too)
        for kit in [kitA, acoustic] {
            guard loadKit(kit) else { check(false, "fresh sounds: \(kit.name) loads"); continue }
            for pad in [Pad.kick.rawValue, Pad.bass808.rawValue] where !stock.isEmpty(kitID: kit.id, pad: pad) {   // Vintage: no 808
                for k in 0..<3 {
                    let h = hit(pad)
                    let db = 10 * log10((h.l + 1e-12) / (h.r + 1e-12))
                    check(h.l > 1e-6 && abs(db) < 0.3, "fresh sounds: \(kit.name) \(pad == 0 ? "kick" : "808") hit \(k + 1) is centered (L/R \(String(format: "%+.2f", db)) dB)")
                }
            }
        }

        // a sound picked from the library comes in as itself, not with the last sound's settings
        let all = stock.librarySounds()
        _ = loadKit(kitA)
        if let kick = all.first(where: { $0.type == .kick }) {
            onMain { rc.setPadSettings(0, tweaked) }
            var ready = false
            onMain { rc.replaceRackSound(rc.rackChannels.first { $0.pad == 0 }!.id, with: kick) { ready = true } }
            let loaded = settle { ready }
            let ps = onMain({ rc.state.pads[0] })
            var expected = PadSettings(); expected.sampleFile = ps.sampleFile
            check(loaded && ps.sampleFile != nil && ps == expected, "fresh sounds: a library sound picked onto a track comes in as itself")
        } else { check(false, "fresh sounds: the library has a kick") }
        // dice: a pad that gets a new sound comes in as itself
        _ = loadKit(kitA)
        onMain { rc.setPadSettings(Pad.snare.rawValue, tweaked); rc.dice() }
        _ = settle { !rc.loadingKit }
        check(onMain({ rc.state.pads[Pad.snare.rawValue] }) == PadSettings(), "fresh sounds: dice brings each new sound in as itself")
        // a saved kit plays its own sounds, not the last dice roll's (that could put the 808 in another key)
        let name = "SELFTEST FRESH \(Int.random(in: 1000...9999))"
        onMain { rc.saveKit(as: name) }
        _ = loadKit(KitLibrary.factory[1])
        onMain { rc.dice() }
        onMain { rc.selectUserKit(name) }
        _ = settle { !rc.loadingKit }
        check(onMain({ rc.state.stockPicks }) == nil && onMain({ rc.state.userKit }) == name, "fresh sounds: opening a saved kit drops the last dice roll's sounds")
        onMain { rc.deleteUserKit(name) }
        #endif
    }
}
