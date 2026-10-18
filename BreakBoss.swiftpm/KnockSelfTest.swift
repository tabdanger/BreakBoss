// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import AVFoundation

// MARK: - Self-test
//
// Optional test suite (BREAKBOSS_SELFTEST=1), never in normal use. No CI target is bundled.
// It checks the sound, not the screen: every kit renders, every style makes grooves, loops stay
// in time at different tempos and with the host's transport, the clipper holds its ceiling in
// all three modes, idle stays silent, and files round-trip.

enum KnockSelfTest {
    private static var failures: [String] = []
    private static var lines: [String] = []

    @discardableResult
    static func run() -> Bool {
        failures = []
        lines = []
        let started = Date()
        phase("checkKits", checkKits)
        phase("checkStockSamples", checkStockSamples)
        phase("checkSoundSwap", checkSoundSwap)
        phase("checkGrooves", checkGrooves)
        phase("checkSmallBuffersAndVoiceStealing", checkSmallBuffersAndVoiceStealing)
        phase("checkHostMIDIAndAutomation", checkHostMIDIAndAutomation)
        phase("checkOneShotMIDIAndPadFilters", checkOneShotMIDIAndPadFilters)
        phase("checkVelocityLayers", checkVelocityLayers)
        phase("checkModesAndClipper", checkModesAndClipper)
        phase("checkTempoSync", checkTempoSync)
        phase("checkHostTransport", checkHostTransport)
        phase("checkSilence", checkSilence)
        phase("checkFiles", checkFiles)
        phase("checkHeldLoops", checkHeldLoops)
        phase("checkMigration", checkMigration)
        phase("checkFactoryPresetsAndKitIndependence", checkFactoryPresetsAndKitIndependence)
        phase("checkEveryPatternAudible", checkEveryPatternAudible)
        phase("checkTextureControls", checkTextureControls)
        phase("checkLevelPanGlide", checkLevelPanGlide)
        phase("checkPatternEditor", checkPatternEditor)
        phase("checkMIDIPadMap", checkMIDIPadMap)
        phase("checkRecordingTrim", checkRecordingTrim)
        phase("checkDrumRoll", checkDrumRoll)
        phase("checkWorkspaceChannels", checkWorkspaceChannels)
        phase("checkSampler", checkSampler)
        let seconds = Date().timeIntervalSince(started)
        if failures.isEmpty {
            log("BreakBoss self-test passed (\(lines.count) checks, \(String(format: "%.1f", seconds)) s)")
        } else {
            for f in failures { log("BreakBoss SELF-TEST FAILED: \(f)") }
        }
        return failures.isEmpty
    }

    /// Persist progress before entering each phase so simulator timeouts distinguish a slow
    /// stage from a crash. The normal app never calls this optional self-test entry point.
    private static func phase(_ name: String, _ work: () -> Void) {
        log("BreakBoss self-test phase START: \(name)")
        let started = Date()
        let previousChecks = lines.count
        work()
        let seconds = Date().timeIntervalSince(started)
        log("BreakBoss self-test phase END: \(name) (\(lines.count - previousChecks) checks, \(String(format: "%.2f", seconds)) s)")
    }

    private static func check(_ ok: Bool, _ what: String) {
        lines.append(what)
        if !ok { failures.append(what) }
    }

    private static func log(_ s: String) {
        print(s)
        NSLog("%@", s)
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let url = caches.appendingPathComponent("BreakBoss-selftest.log")
            let old = (try? String(contentsOf: url)) ?? ""
            try? (old + s + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func kitBuffers(_ def: KitDefinition, rate: Double = 48_000) -> KitBuffers {
        let samples = def.pads.enumerated().map { DrumSynth.render($0.element, sampleRate: rate, seed: UInt32($0.offset + 1)) }
        return KitBuffers(name: def.name, samples: samples, settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: def.bassHz,
                          renderSampleRate: rate)
    }

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
        let names = library.allSounds.map(\.displayName)
        check(library.allSounds.count == 589 && urls.count == 589 && Set(names).count == 589, "the sound library holds 589 sounds, each with its own name")
        check(names.allSatisfy { SoundType.forStockName($0) != nil }, "every stock sound's name ends in what it is")
        check(SoundType.forStockName("THRONE OPEN HIHAT") == .open && SoundType.forStockName("THRONE HIHAT") == .hat
              && SoundType.forStockName("SUKUNA E1 808") == .bass && SoundType.forStockName("ISSA BOUNCE CLAP SNARE") == .snare,
              "a stock sound's last word sorts it")
        check(library.librarySounds().count == 589, "the sound menu lists every stock sound, in a kit or not")
        var assignments = 0
        for kit in KitLibrary.factory {
            for pad in Pad.allCases {
                let sample = library.sample(kitID: kit.id, pad: pad.rawValue)
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
            let pair = KitLibrary.factory.filter { $0.genre == kit.genre }
            let mine = Set(Pad.allCases.compactMap { library.sample(kitID: kit.id, pad: $0.rawValue)?.url })
            for other in pair where other.id != kit.id {
                let theirs = Set(Pad.allCases.compactMap { library.sample(kitID: other.id, pad: $0.rawValue)?.url })
                check(mine.isDisjoint(with: theirs), "\(kit.name) and \(other.name) share no sounds")
            }
        }
        check(assignments == KitLibrary.factory.count * Pad.count, "stock audio covers every factory pad")
        // Home dice draws each pad's sound from every kit's sound for that pad.
        check(Pad.allCases.allSatisfy { library.kits(withPad: $0.rawValue).count == KitLibrary.factory.count }, "dice: every pad has a sound in every kit")
        var picked = KnockState(); picked.stockPicks = Array(repeating: nil, count: Pad.count); picked.stockPicks?[0] = "detroit-2026-a"
        check(KnockController.stockPick(picked, pad: 0) == "detroit-2026-a" && KnockController.stockPick(picked, pad: 1) == nil, "dice: per-pad picks")
        check(picked.selectingKit(KitLibrary.factory[1]).stockPicks == nil, "dice: choosing a kit brings its own sounds back")
        // The acoustic drums: every sound multisampled, softest layer first, the loudest one the sound itself.
        let acoustic = library.allSounds.filter { $0.displayName.hasPrefix("VIRTUOSITY ") }
        check(acoustic.count == 12 && acoustic.allSatisfy { (library.layers(for: $0)?.count ?? 0) >= 3 },
              "acoustic drums: 12 multisampled sounds, each with its velocity layers")
        for sound in acoustic {
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
                }
            }
        }
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            autoreleasepool {
                do {
                    let buffer = try SampleLoader.load(url)
                    check(abs(buffer.sampleRate - 48_000) < 1, "\(url.lastPathComponent): decodes at 48 kHz")
                    check(buffer.length > 0 && buffer.seconds <= 4, "\(url.lastPathComponent): bounded stock duration")
                    var peak: Float = 0
                    var finite = true
                    for frame in 0..<buffer.length {
                        let left = buffer.left[frame], right = buffer.right[frame]
                        if !left.isFinite || !right.isFinite { finite = false; break }
                        peak = max(peak, max(abs(left), abs(right)))
                    }
                    check(finite, "\(url.lastPathComponent): decoded stereo audio is finite")
                    check(peak > 0.005 && peak <= 1.000_01, "\(url.lastPathComponent): decoded stock audio is audible and bounded")
                } catch {
                    check(false, "\(url.lastPathComponent): stock audio decodes (\(error.localizedDescription))")
                }
            }
        }
        #endif
    }

    // The acoustic layers' loudness (tools/build_acoustic_sounds.py; the pack sounds are their original files).
    static let stockLoudnessTarget = -10.0
    static let stockLoudnessTolerance = 1.0
    static let stockLoudnessCeiling: Float = 0.944  // -0.5 dBFS

    /// LUFS of the loudest 100 ms (BS.1770 K-weighting at 48 kHz), the same measure as the levelling tool.
    static func stockLoudness(_ buffer: SampleBuffer) -> Double {
        func kWeighted(_ x: UnsafeMutablePointer<Float>) -> [Double] {
            let stages: [([Double], [Double])] = [
                ([1.53512485958697, -2.69169618940638, 1.19839281085285], [-1.69065929318241, 0.73248077421585]),
                ([1.0, -2.0, 1.0], [-1.99004745483398, 0.99007225036621]),
            ]
            var y = (0..<buffer.length).map { Double(x[$0]) }
            for (b, a) in stages {
                var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
                for i in 0..<y.count {
                    let v = y[i]
                    let o = b[0] * v + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2
                    x2 = x1; x1 = v; y2 = y1; y1 = o
                    y[i] = o
                }
            }
            return y
        }
        let l = kWeighted(buffer.left), r = kWeighted(buffer.right)
        let window = 4_800
        var sum = 0.0, loudest = 0.0
        for i in 0..<buffer.length {
            sum += l[i] * l[i] + r[i] * r[i]
            if i >= window { sum -= l[i - window] * l[i - window] + r[i - window] * r[i - window] }
            loudest = max(loudest, sum)
        }
        return -0.691 + 10 * log10(max(loudest / Double(window), 1e-12))
    }

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
        if let original = try? Data(contentsOf: hat.url), original.count > 100 {
            let copy = KnockFolders.samples.appendingPathComponent(hat.url.lastPathComponent)
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
        let kickTrack = onMain({ rc.rackChannels[0] })
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
            check(onMain({ rc.rackChannels[0].name }) == sound.name, "sound swap: the rack names \(sound.name)")
        }
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
            check(afterPattern == clap.name && onMain({ rc.rackChannels[0].name }) == clap.name,
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
        check(heardKit && onMain({ rc.rackChannels[0].soundID }) == "kit", "sound swap: a kit change puts the kit's kick back on the track and in the rack")
        #endif
    }

    static func checkGrooves() {
        for style in GrooveStyle.allCases {
            for seed: UInt32 in [1, 2, 77, 12345] {
                let loops = GrooveGenerator.loops(style: style, seed: seed)
                check(loops.count == Pad.count, "\(style) seed \(seed): 12 loops")
                for (i, p) in loops.enumerated() {
                    check(!p.events.isEmpty, "\(style) loop \(i + 1) has hits")
                    check(p.lengthTicks % (PatternData.ppq * 4) == 0, "\(style) loop \(i + 1) whole bars")
                    check(p.events.allSatisfy { $0.pad >= 0 && Int($0.pad) < Pad.count && $0.velocity > 0 && $0.velocity <= 1 },
                          "\(style) loop \(i + 1) valid hits")
                    check(p.events.count <= GrooveGenerator.maxGeneratedEvents,
                          "\(style) loop \(i + 1) bounded phrase density")
                    check(p.events.allSatisfy { $0.tick >= 0 && $0.tick < p.lengthTicks && $0.semis.isFinite && $0.velocity.isFinite },
                          "\(style) loop \(i + 1) finite events inside phrase")
                    check(zip(p.events, p.events.dropFirst()).allSatisfy { $0.0.tick <= $0.1.tick },
                          "\(style) loop \(i + 1) events sorted")
                    for bar in 0..<p.bars {
                        let start = Int32(bar) * PatternData.ppq * 4
                        let count = p.events.filter { $0.tick >= start && $0.tick < start + PatternData.ppq * 4 }.count
                        check(count <= GrooveGenerator.maxGeneratedEventsPerBar,
                              "\(style) loop \(i + 1) bar \(bar) bounded density")
                    }
                    let bass = p.events.filter { $0.pad == Int8(Pad.bass808.rawValue) }
                    check(bass.allSatisfy { $0.length > 0 && $0.tick + $0.length <= p.lengthTicks },
                          "\(style) loop \(i + 1) bass gates remain inside phrase")
                    let closed = Set(p.events.filter { $0.pad == Int8(Pad.hat.rawValue) }.map { $0.tick })
                    check(!p.events.contains { $0.pad == Int8(Pad.openHat.rawValue) && closed.contains($0.tick) },
                          "\(style) loop \(i + 1) no same-tick hat choke conflict")
                }
                check(Array(loops.prefix(4)).map { $0.bars } == [2, 4, 8, 4], "\(style): main phrase lengths")
                check(loops[LoopSlot.no808.rawValue].events.allSatisfy { $0.pad != Int8(Pad.bass808.rawValue) },
                      "\(style): No 808 excludes bass")
                check(loops[LoopSlot.kick808.rawValue].events.allSatisfy {
                    $0.pad == Int8(Pad.kick.rawValue) || $0.pad == Int8(Pad.bass808.rawValue)
                }, "\(style): Kick + 808 has only its two lanes")
                // The main groove has a backbeat (snare or clap or rim) and a kick.
                let a = loops[0]
                check(a.events.contains { $0.pad == Int8(Pad.kick.rawValue) }, "\(style) main A has a kick")
                check(a.events.contains { [Pad.snare.rawValue, Pad.clap.rawValue, Pad.rim.rawValue].contains(Int($0.pad)) },
                      "\(style) main A has a backbeat")
            }
            // Same seed, same grooves
            check(GrooveGenerator.loops(style: style, seed: 5) == GrooveGenerator.loops(style: style, seed: 5), "\(style) repeatable")
        }
    }

    /// These regressions check audio continuity; they do not measure device callback timing.
    static func checkSmallBuffersAndVoiceStealing() {
        let rate = 48_000.0
        let total = 6_144
        let sine = (0..<(total + 4)).map { Float(sin(Double($0) * 2 * Double.pi * 110 / rate)) * 0.06 }
        let sample = SampleBuffer(left: sine, sampleRate: rate)
        let settings = Array(repeating: PadSettings(), count: Pad.count)
        let kit = KitBuffers(name: "BUFFER REGRESSION", samples: Array(repeating: sample, count: Pad.count),
                             settings: settings, bassHz: 110)

        func makeEngine(_ kit: KitBuffers, mode: SoundMode) -> KnockEngine {
            let engine = KnockEngine()
            engine.prepare(sampleRate: rate, maxFrames: 512)
            engine.setParam(.playMode, 0)
            engine.setParam(.followDAW, 0)
            engine.setParam(.tempoSync, 0)
            engine.setParam(.soundMode, Float(mode.rawValue))
            engine.setParam(.boost, 0)
            engine.setParam(.filter, 1)
            engine.kitHandoff.publish(kit)
            return engine
        }

        func trace(_ mode: SoundMode, block: Int) -> ([Float], [Float]) {
            let engine = makeEngine(kit, mode: mode)
            engine.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 0.8))
            var left = [Float](repeating: 0, count: total), right = left
            var done = 0
            while done < total {
                let count = min(block, total - done)
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        engine.render(frames: count, left: l.baseAddress! + done, right: r.baseAddress! + done, host: nil)
                    }
                }
                done += count
            }
            return (left, right)
        }

        for mode in SoundMode.allCases {
            let small = trace(mode, block: 128)
            let large = trace(mode, block: 512)
            var difference: Float = 0
            for i in 0..<total {
                difference = max(difference, max(abs(small.0[i] - large.0[i]), abs(small.1[i] - large.1[i])))
            }
            check(small.0.allSatisfy { $0.isFinite } && small.1.allSatisfy { $0.isFinite }, "\(mode): 128-frame output finite")
            check(small.0.contains { abs($0) > 0.001 }, "\(mode): 128-frame output audible")
            check(difference < 0.000_01, "\(mode): isolated audio matches at 128/512 frames (\(difference))")
        }

        // Constant signals make an abrupt stolen-voice cut visible. The replacement's
        // higher level also prevents a same-amplitude replacement from hiding that cut.
        let old = SampleBuffer(left: Array(repeating: Float(0.01), count: 12_000), sampleRate: rate)
        let replacement = SampleBuffer(left: Array(repeating: Float(0.025), count: 12_000), sampleRate: rate)
        var samples = Array(repeating: old, count: Pad.count)
        samples[Pad.snare.rawValue] = replacement
        let stealKit = KitBuffers(name: "STEAL REGRESSION", samples: samples, settings: settings, bassHz: 110)
        let baseline = makeEngine(stealKit, mode: .modern)
        let overloaded = makeEngine(stealKit, mode: .modern)
        for engine in [baseline, overloaded] {
            engine.setParam(.clipper, 0)
            for _ in 0..<KnockEngine.maxVoices {
                engine.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 1))
            }
            var left = [Float](repeating: 0, count: 512), right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    engine.render(frames: 512, left: l.baseAddress!, right: r.baseAddress!, host: nil)
                }
            }
        }
        // Exceed both the primary voices and the small fading-tail reserve at once.
        for _ in 0..<32 {
            overloaded.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 1))
        }
        func nextBlock(_ engine: KnockEngine) -> [Float] {
            var left = [Float](repeating: 0, count: 128), right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    engine.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil)
                }
            }
            return left
        }
        let reference = nextBlock(baseline)
        let burst = nextBlock(overloaded)
        check(burst.allSatisfy { $0.isFinite }, "voice overload keeps audio finite")
        check(abs(burst[0] - reference[0]) < 0.002, "voice overload begins without an abrupt cut")
        check(burst.contains { abs($0) > 0.001 }, "voice overload keeps existing audio audible")
    }

    /// The AU adapter queues notes before render(). Their offsets must survive the control
    /// snapshot and kit handoff, including gates that change loop scheduling within a block.
    static func checkHostMIDIAndAutomation() {
        let rate = 48_000.0
        let sample = SampleBuffer(left: Array(repeating: Float(0.025), count: 12_000), sampleRate: rate)
        let kit = KitBuffers(name: "HOST EVENT REGRESSION", samples: Array(repeating: sample, count: Pad.count),
                             settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110)
        let firstHit = PatternData(name: "GATE", lengthTicks: PatternData.ppq * 4,
                                   events: [GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1)])
        func engine(loop: Bool = false) -> KnockEngine {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            e.setParam(.playMode, loop ? 1 : 0)
            e.setParam(.followDAW, 0)
            e.setParam(.tempoSync, 0)
            e.setParam(.boost, 0)
            e.setParam(.clipper, 0)
            e.setParam(.clipDrive, 0)
            e.kitHandoff.publish(kit)
            e.patternHandoff.publish(PatternSet(Array(repeating: firstHit, count: Pad.count)))
            return e
        }
        func block(_ e: KnockEngine, _ frames: Int) -> [Float] {
            var left = [Float](repeating: 0, count: frames), right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    e.render(frames: frames, left: l.baseAddress!, right: r.baseAddress!, host: nil)
                }
            }
            return left
        }
        func maxDifference(_ a: [Float], _ b: [Float]) -> Float {
            var difference: Float = 0
            for i in a.indices { difference = max(difference, abs(a[i] - b[i])) }
            return difference
        }
        for note: UInt8 in [36, 47, 48, 52, 60, 84] {
            let e = engine()
            e.hostMIDI(offset: 73, status: 0x90, data1: note, data2: 127)
            let actual = block(e, 128)
            check(actual.prefix(73).allSatisfy { abs($0) < 0.000_001 }, "host MIDI \(note): silent before sample 73")
            check(actual.dropFirst(73).contains { abs($0) > 0.001 }, "host MIDI \(note): sounds after sample 73 on first callback")
        }

        let carried = engine()
        carried.hostMIDI(offset: 191, status: 0x90, data1: 36, data2: 127)
        check(block(carried, 128).allSatisfy { abs($0) < 0.000_001 }, "host MIDI: future offset remains silent in first block")
        let carriedOutput = block(carried, 128)
        check(carriedOutput.prefix(63).allSatisfy { abs($0) < 0.000_001 } &&
              carriedOutput.dropFirst(63).contains { abs($0) > 0.001 }, "host MIDI: offset carries across 128-frame boundary")

        let actualBass = engine(loop: true), expectedBass = engine(loop: true)
        for e in [actualBass, expectedBass] {
            e.hostMIDI(offset: 0, status: 0x90, data1: 60, data2: 127)
            _ = block(e, 128)
        }
        actualBass.hostMIDI(offset: 77, status: 0x80, data1: 60, data2: 0)
        let actualRelease = block(actualBass, 128)
        var expectedRelease = block(expectedBass, 77)
        expectedBass.hostMIDI(offset: 0, status: 0x80, data1: 60, data2: 0)
        expectedRelease += block(expectedBass, 51)
        check(maxDifference(actualRelease, expectedRelease) < 0.000_001, "host Loop-mode bass release begins at its sample offset")

        let actualLoop = engine(loop: true), expectedLoop = engine(loop: true)
        actualLoop.hostMIDI(offset: 73, status: 0x90, data1: 36, data2: 127)
        actualLoop.hostMIDI(offset: 193, status: 0x80, data1: 36, data2: 0)
        let actualGate = block(actualLoop, 256)
        var expectedGate = block(expectedLoop, 73)
        expectedLoop.hostMIDI(offset: 0, status: 0x90, data1: 36, data2: 127)
        expectedGate += block(expectedLoop, 120)
        expectedLoop.hostMIDI(offset: 0, status: 0x80, data1: 36, data2: 0)
        expectedGate += block(expectedLoop, 63)
        check(actualGate.prefix(73).allSatisfy { abs($0) < 0.000_001 } &&
              actualGate.dropFirst(73).contains { abs($0) > 0.001 }, "host loop gate starts on sample 73")
        check(maxDifference(actualGate, expectedGate) < 0.000_001 && actualLoop.status[0] == 0,
              "host loop gate schedules and releases at host offsets")

        let automated = engine()
        automated.hostParameter(.playMode, 42)
        automated.hostParameter(.pitch, -5)
        automated.hostParameter(.output, .nan)
        automated.hostMIDI(offset: 73, status: 0x90, data1: 36, data2: 127)
        let automatedGate = block(automated, 128)
        check(automated.param(.playMode) == 1 && automated.param(.pitch) == 0 &&
              automated.param(.output) == KParam.output.defaultValue, "host automation normalizes and publishes values")
        check(automatedGate.prefix(73).allSatisfy { abs($0) < 0.000_001 } && automated.status[0] == 1,
              "host play-mode automation precedes MIDI classification")

        // Control-plane updates contend with the render snapshot; callbacks keep using local
        // pending automation. This exercises publication retries, not device timing budgets.
        let contended = engine()
        let writers = DispatchGroup()
        writers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<2_000 {
                contended.setParam(.tune, Float(i % 100) / 100)
                contended.setTempo(Double(80 + i % 80))
            }
            writers.leave()
        }
        var finite = true
        for i in 0..<64 {
            contended.hostParameter(.pitch, Float(i % 2))
            contended.hostMIDI(offset: 63, status: 0x90, data1: 36, data2: 100)
            finite = finite && block(contended, 128).allSatisfy { $0.isFinite }
        }
        writers.wait()
        contended.hostParameter(.pitch, 0.75)
        _ = block(contended, 128)
        check(finite && contended.param(.pitch) == 0.75, "host automation survives concurrent UI control updates")
    }

    /// The SAMPLER window: the SAMPLE page's computed sound and the ENVELOPE page while it plays.
    static func checkSampler() {
        let rate = 48_000.0
        let ramp = SampleBuffer(left: (0..<9_600).map { Float($0) / 9_600 * 0.5 }, sampleRate: rate)
        func process(_ change: (inout SamplerSettings) -> Void) -> SampleBuffer {
            var s = SamplerSettings(); change(&s)
            return SamplerProcessor.process(ramp, s.offline(bpm: 120) ?? SamplerOffline(), engineRate: rate)
        }
        check(SamplerSettings().offline(bpm: 120) == nil, "Sampler: an untouched sampler leaves the sound as it is")
        let reversed = process { $0.reverse = true; $0.declick = .off }
        check(abs(reversed.left[0] - ramp.left[ramp.length - 1]) < 0.000_1, "Sampler: Reverse plays the sound backwards")
        let trimmed = process { $0.start = 0.25; $0.length = 0.5; $0.declick = .off }
        check(abs(trimmed.length - 3_600) <= 2, "Sampler: SMP START and LENGTH cut the sound (\(trimmed.length) samples)")
        let normalized = process { $0.normalize = true }
        var peak: Float = 0
        for i in 0..<normalized.length { peak = max(peak, abs(normalized.left[i])) }
        check(abs(peak - 0.98) < 0.01, "Sampler: Normalize brings the peak to just under full scale")
        let polarity = process { $0.reversePolarity = true; $0.declick = .off }
        check(polarity.left[5_000] < 0 && abs(polarity.left[5_000] + ramp.left[5_000]) < 0.000_1, "Sampler: Reverse polarity flips the wave")
        let cut = process { $0.length = 0.5; $0.declick = .generic }
        check(cut.length > 4_800 && cut.fadeMarks.1 > 0 && abs(cut.left[cut.length - 1]) < 0.01,
              "Sampler: a bleeding declick fades out past the cut (\(cut.length) samples)")
        let tone = SampleBuffer(left: (0..<48_000).map { sinf(Float($0) * 2 * .pi * 220 / 48_000) * 0.5 }, sampleRate: rate)
        var stretch = SamplerSettings(); stretch.stretch = .stretch; stretch.multiplier = 1
        let longer = SamplerProcessor.process(tone, stretch.offline(bpm: 120)!, engineRate: rate)
        check(abs(Double(longer.length) / 48_000 - 4) < 0.05, "Sampler: MUL ×4 with Stretch makes it four times longer (\(longer.length))")
        var locked = SamplerSettings(); locked.stretch = .stretch; locked.time = .projectTempo(120)
        let slower = SamplerProcessor.process(tone, locked.offline(bpm: 60)!, engineRate: rate)
        check(abs(Double(slower.length) / 48_000 - 2) < 0.05, "Sampler: TIME locked to the tempo stretches when the tempo halves")
        var pitched = SamplerSettings(); pitched.stretch = .stretch; pitched.stretchPitch = 12
        let up = SamplerProcessor.process(tone, pitched.offline(bpm: 120)!, engineRate: rate)
        var crossings = 0
        for i in 1..<min(up.length, 24_000) where (up.left[i - 1] < 0) != (up.left[i] < 0) { crossings += 1 }
        check(abs(up.length - 48_000) < 600 && crossings > 380 && crossings < 500,
              "Sampler: PITCH +12 with Stretch keeps the length and doubles the pitch (\(crossings) crossings)")
        var saved = PadSettings(); saved.sampler = stretch
        let decoded = (try? JSONEncoder().encode(saved)).flatMap { try? JSONDecoder().decode(PadSettings.self, from: $0) }
        check(decoded?.sampler == stretch, "Sampler: its settings are saved with the track")

        // playing: the Volume envelope, the filter, a loop and the one-shot rule
        let long = SampleBuffer(left: (0..<48_000).map { $0 % 2 == 0 ? 0.2 : -0.2 }, sampleRate: rate)
        func energy(_ settings: PadSettings, _ sample: SampleBuffer = long, blocks: ClosedRange<Int>) -> Float {
            var all = Array(repeating: PadSettings(), count: Pad.count)
            all[0] = settings
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                            (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0)]
            for (p, v) in quiet { e.setParam(p, v) }
            e.kitHandoff.publish(KitBuffers(name: "SAMPLER", samples: Array(repeating: sample, count: Pad.count), settings: all, bassHz: 110))
            e.send(KEvent(kind: .pad, a: 0, value: 1))
            var total: Float = 0
            for b in 0...blocks.upperBound {
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
                if blocks.contains(b) { total += left.reduce(0) { $0 + $1 * $1 } }
            }
            return total
        }
        let plain = PadSettings()
        var shaped = PadSettings(); shaped.sampler = SamplerSettings()
        shaped.sampler?.setEnvelope(.volume) { $0.on = true; $0.attack = 0; $0.hold = 0; $0.decay = 0.15; $0.sustain = 0 }
        let tail = 100...140
        check(energy(plain, blocks: tail) > 1 && energy(shaped, blocks: tail) < energy(plain, blocks: tail) * 0.01,
              "Sampler: the Volume envelope shapes the hit")
        var filtered = PadSettings(); filtered.sampler = SamplerSettings(); filtered.sampler?.cutoff = 0.2; filtered.sampler?.filterType = .lp
        check(energy(filtered, blocks: 5...20) < energy(plain, blocks: 5...20) * 0.05, "Sampler: the filter (MOD X) takes the top off")
        let short = SampleBuffer(left: (0..<3_000).map { $0 % 2 == 0 ? 0.2 : -0.2 }, sampleRate: rate)
        var looped = PadSettings(); looped.sampler = SamplerSettings(); looped.sampler?.useLoop = true
        check(energy(looped, short, blocks: 60...80) > 1 && energy(plain, short, blocks: 60...80) < energy(looped, short, blocks: 60...80) * 0.01,
              "Sampler: Use loop points keeps a short sound going")
        var offset = PadSettings(); offset.sampler = SamplerSettings(); offset.sampler?.startOffset = 0.9
        check(energy(plain, blocks: 50...60) > 1 && energy(offset, blocks: 50...60) < energy(plain, blocks: 50...60) * 0.01,
              "Sampler: START OFFSET starts the sound later in")

        // Realtime stretching: ×2 plays twice as long with nothing computed first
        let quarter = SampleBuffer(left: (0..<12_000).map { sinf(Float($0) * 2 * .pi * 220 / 48_000) * 0.5 }, sampleRate: rate)
        var realtime = PadSettings(); realtime.sampler = SamplerSettings()
        realtime.sampler?.stretch = .realtime; realtime.sampler?.multiplier = 0.75
        check(realtime.sampler?.offline(bpm: 120) == nil, "Sampler: Realtime stretching computes nothing ahead")
        let after = 110...160
        check(energy(plain, quarter, blocks: after) < 0.01 && energy(realtime, quarter, blocks: after) > 1,
              "Sampler: Realtime ×2 keeps a quarter-second sound going twice as long")

        // custom loop points with a crossfade: the loop's end blends into what leads up to its start
        var looping = SamplerSettings(); looping.loopStart = 0.5; looping.loopEnd = 0.9; looping.crossfade = 0.5; looping.declick = .off
        let blended = SamplerProcessor.process(tone, looping.offline(bpm: 120)!, engineRate: rate)
        check(abs(blended.loopStart - 24_000) < 2 && abs(blended.loopEnd - 43_200) < 2,
              "Sampler: loop points with CROSSFADE keep the loop where it was set (\(blended.loopStart)…\(blended.loopEnd))")
        var loopOnly = SamplerSettings(); loopOnly.loopStart = 0.5
        check(loopOnly.offline(bpm: 120) == nil, "Sampler: loop points alone compute nothing ahead")

        // the waveform's edits
        let edited = SampleEditor.apply(.delete(0..<4_800), to: ramp)
        check(edited.left.count == 4_800 && abs(edited.left[0] - ramp.left[4_800]) < 0.000_1,
              "Sampler: DELETE takes the selection out")
        check(abs((edited.map(0.75) ?? -1) - 0.5) < 0.001 && edited.map(0.25) == nil,
              "Sampler: markers after a cut move with the audio, those in it go")
        let piece = SampleEditor.clip(ramp, 0..<960)
        let inserted = SampleEditor.apply(.insert(piece, at: 4_800), to: ramp)
        check(inserted.left.count == 10_560 && abs(inserted.left[4_800] - ramp.left[0]) < 0.000_1,
              "Sampler: PASTE inserts at the selection")
        let replaced = SampleEditor.apply(.replace(piece, over: 0..<4_800), to: ramp)
        check(replaced.left.count == 960 + 4_800, "Sampler: PASTE can replace the selection")
        let padded = SampleBuffer(left: Array(repeating: 0, count: 4_800) + (0..<4_800).map { sinf(Float($0) * 0.1) * 0.5 } + Array(repeating: 0, count: 9_600),
                                  sampleRate: rate)
        let trimmedSilence = SampleEditor.apply(.trimSilence, to: padded)
        check(trimmedSilence.left.count < 5_000 && trimmedSilence.left.count > 4_700,
              "Sampler: TRIM takes the silence off both ends (\(trimmedSilence.left.count))")
        let faded = SampleEditor.apply(.fadeIn(0..<9_600), to: ramp)
        check(abs(faded.left[1]) < 0.001 && abs(faded.left[9_599] - ramp.left[9_599]) < 0.01, "Sampler: FADE IN rises from silence")
        var bake = SamplerSettings(); bake.normalize = true; bake.stretch = .stretch; bake.multiplier = 1; bake.markers = [0.75]
        bake.baked { $0 < 0.5 ? nil : ($0 - 0.5) * 2 }
        check(bake.offline(bpm: 120) == nil && bake.markers == [0.5], "Sampler: an edit bakes the computed settings into the file")

        // envelope presets
        let presets = SamplerEnvelopePreset.factory
        check(SamplerEnvelopePreset.kinds.allSatisfy { k in presets.contains { $0.kind == k } }
              && presets.allSatisfy { $0.envelopes[SamplerTarget.volume.rawValue].on },
              "Sampler: envelope presets for 808s, kicks and snares shape the volume")
        let round = (try? JSONEncoder().encode(presets)).flatMap { try? JSONDecoder().decode([SamplerEnvelopePreset].self, from: $0) }
        check(round == presets, "Sampler: envelope presets save and load")
    }

    /// A multisampled pad: a soft hit plays the soft recording, a hard one the loud one, and repeated
    /// hits step through the layer's round robins.
    static func checkVelocityLayers() {
        let rate = 48_000.0
        func tone(_ amplitude: Float) -> SampleBuffer {
            SampleBuffer(left: (0..<12_000).map { sinf(Float($0) * 2 * .pi * 1_000 / 48_000) * amplitude }, sampleRate: rate)
        }
        let main = tone(0.4), soft = tone(0.02), hardA = tone(0.4), hardB = tone(0.2)
        guard let layers = VelocityLayers(source: main, tops: [0.5, 1], hits: [[soft], [hardA, hardB]]) else {
            check(false, "layers: made"); return
        }
        check(layers.layer(for: 0.3) == 0 && layers.layer(for: 0.5) == 0 && layers.layer(for: 0.51) == 1 && layers.layer(for: 1) == 1,
              "layers: how hard a hit is picks its layer")
        check(VelocityLayers(source: main, tops: [1], hits: [[]]) == nil, "layers: a layer needs a hit")
        var padLayers = [VelocityLayers?](repeating: nil, count: Pad.count)
        padLayers[Pad.snare.rawValue] = layers
        let kit = KitBuffers(name: "LAYERS", samples: Array(repeating: main, count: Pad.count),
                             settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110, layers: padLayers)
        func engine() -> KnockEngine {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            e.setParam(.playMode, 0); e.setParam(.followDAW, 0); e.setParam(.tempoSync, 0)
            e.setParam(.velocity, 1); e.setParam(.boost, 0); e.setParam(.clipper, 0); e.setParam(.clipDrive, 0)
            e.kitHandoff.publish(kit)
            return e
        }
        func peak(_ e: KnockEngine, blocks: Int = 4) -> Float {
            var p: Float = 0
            for _ in 0..<blocks {
                var left = [Float](repeating: 0, count: 128), right = left
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) }
                }
                p = max(p, left.map(abs).max() ?? 0)
            }
            return p
        }
        let snare = UInt8(Pad.snare.midiNote), kick = UInt8(Pad.kick.midiNote)
        let s = engine(); s.hostMIDI(offset: 0, status: 0x90, data1: snare, data2: 32)
        let h = engine(); h.hostMIDI(offset: 0, status: 0x90, data1: snare, data2: 127)
        let k = engine(); k.hostMIDI(offset: 0, status: 0x90, data1: kick, data2: 127)
        let softPeak = peak(s), hardPeak = peak(h), plainPeak = peak(k)
        check(softPeak > 0.002 && softPeak < hardPeak * 0.1, "layers: a soft hit plays the soft recording (\(softPeak) vs \(hardPeak))")
        check(abs(hardPeak - plainPeak) < plainPeak * 0.1, "layers: a full hit plays the loud recording at full level")
        _ = peak(h, blocks: 110)   // let the first hit end
        h.hostMIDI(offset: 0, status: 0x90, data1: snare, data2: 127)
        let second = peak(h)
        check(second > hardPeak * 0.3 && second < hardPeak * 0.7, "layers: the next hit takes the layer's next round robin")
    }

    /// A one-shot's tail is independent of note length. Exercise every sequential pad,
    /// the chromatic bass extension, dynamics, and the new per-pad filter at 128 frames.
    static func checkOneShotMIDIAndPadFilters() {
        let rate = 48_000.0
        let sample = SampleBuffer(left: Array(repeating: Float(0.025), count: 12_000), sampleRate: rate)
        let kit = KitBuffers(name: "ONE-SHOT MIDI", samples: Array(repeating: sample, count: Pad.count),
                             settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110)
        func engine(using sounds: KitBuffers? = nil) -> KnockEngine {
            let e = KnockEngine()
            e.prepare(sampleRate: rate, maxFrames: 128)
            e.setParam(.playMode, 0)
            e.setParam(.followDAW, 0)
            e.setParam(.tempoSync, 0)
            e.setParam(.velocity, 1)
            e.setParam(.boost, 0)
            e.setParam(.clipper, 0)
            e.setParam(.clipDrive, 0)
            e.kitHandoff.publish(sounds ?? kit)
            return e
        }
        func block(_ e: KnockEngine) -> [Float] {
            var left = [Float](repeating: 0, count: 128), right = left
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil)
                }
            }
            return left
        }
        func energy(_ values: [Float]) -> Float { values.reduce(0) { $0 + $1 * $1 } }
        for note in (36...47).map({ UInt8($0) }) + [48, 60, 84] {
            let short = engine(), held = engine()
            for e in [short, held] { e.hostMIDI(offset: 0, status: 0x90, data1: note, data2: 127) }
            // An immediate key release must leave the first sample, attack and entire tail
            // identical to a key held through all 32 callbacks, including the 808.
            short.hostMIDI(offset: 1, status: 0x80, data1: note, data2: 0)
            var identical = true
            var audible = false
            for _ in 0..<32 {
                let a = block(short), b = block(held)
                identical = identical && zip(a, b).allSatisfy { abs($0.0 - $0.1) < 0.000_001 }
                audible = audible || a.contains { abs($0) > 0.001 }
            }
            let pad = Pad.index(forMIDINote: Int(note)) ?? Pad.bass808.rawValue
            check(identical && audible, "One-Shot MIDI \(note): immediate release preserves the complete tail")
            check(short.padHits[pad] == 1 && short.status[0] == 0, "One-Shot MIDI \(note): one note creates one strike without sequencing")
            short.hostMIDI(offset: 7, status: 0x90, data1: note, data2: 0)
            _ = block(short)
            check(short.padHits[pad] == 1, "One-Shot MIDI \(note): zero velocity releases without retriggering")
            short.hostMIDI(offset: 7, status: 0x90, data1: note, data2: 100)
            _ = block(short)
            check(short.padHits[pad] == 2, "One-Shot MIDI \(note): another programmed note creates the next strike")
        }
        for note: UInt8 in [36, 37, 42, 47, 48, 60] {
            let soft = engine(), hard = engine()
            soft.hostMIDI(offset: 0, status: 0x90, data1: note, data2: 32)
            hard.hostMIDI(offset: 0, status: 0x90, data1: note, data2: 127)
            let softEnergy = energy(block(soft)), hardEnergy = energy(block(hard))
            check(softEnergy > 0 && softEnergy < hardEnergy * 0.1, "One-Shot MIDI \(note): velocity controls strike volume")
        }

        var filteredSettings = Array(repeating: PadSettings(), count: Pad.count)
        filteredSettings[0].filter = 0.35
        let highFrequency = SampleBuffer(left: (0..<2_048).map { $0 % 4 == 0 ? 0.1 : $0 % 4 == 2 ? -0.1 : 0 },
                                         right: (0..<2_048).map { $0 % 4 == 0 ? -0.1 : $0 % 4 == 2 ? 0.1 : 0 }, sampleRate: rate)
        let filteredKit = KitBuffers(name: "PAD FILTER", samples: Array(repeating: highFrequency, count: Pad.count),
                                     settings: filteredSettings, bassHz: 110)
        check(filteredKit.filterCoefficients[0] > 0 && filteredKit.filterCoefficients[0] < 1 &&
              filteredKit.filterCoefficients.dropFirst().allSatisfy { $0 == 1 }, "per-pad filter coefficients prepare only the selected pad")
        func voice(_ coefficient: Float) -> Voice {
            Voice(sample: highFrequency, pad: 0, rate: 1, reverse: false, gainL: 1, gainR: 1,
                  decayCoef: 1, holdSamples: 0, chokeGroup: 0, age: 0, remaining: Int.max, heldNote: -1,
                  filterCoefficient: coefficient)
        }
        var open = voice(1), filtered = voice(filteredKit.filterCoefficients[0])
        var openEnergy: Float = 0, filteredEnergy: Float = 0
        var finite = true, stereo = true, bypassExact = true
        for _ in 0..<12 {
            var a = [Float](repeating: 0, count: 128), ar = a, b = a, br = a
            a.withUnsafeMutableBufferPointer { l in ar.withUnsafeMutableBufferPointer { r in
                open.render(into: l.baseAddress!, r.baseAddress!, frames: 128, releaseSamples: 128)
            } }
            b.withUnsafeMutableBufferPointer { l in br.withUnsafeMutableBufferPointer { r in
                filtered.render(into: l.baseAddress!, r.baseAddress!, frames: 128, releaseSamples: 128)
            } }
            openEnergy += energy(a)
            filteredEnergy += energy(b)
            finite = finite && b.allSatisfy { $0.isFinite } && br.allSatisfy { $0.isFinite }
            stereo = stereo && zip(b, br).allSatisfy { abs($0.0 + $0.1) < 0.000_001 }
            bypassExact = bypassExact && a.enumerated().allSatisfy {
                $0.element == ($0.offset % 4 == 0 ? 0.1 : $0.offset % 4 == 2 ? -0.1 : 0)
            }
        }
        check(finite && filteredEnergy > 0 && filteredEnergy < openEnergy * 0.05, "per-pad filter attenuates high frequencies across 128-frame boundaries")
        check(stereo, "per-pad filter preserves independent stereo channels")
        check(bypassExact, "open per-pad filter bypass preserves original samples exactly")
        let openKit = KitBuffers(name: "OPEN PAD FILTER", samples: Array(repeating: highFrequency, count: Pad.count),
                                 settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110)
        let openEngine = engine(using: openKit), filteredEngine = engine(using: filteredKit)
        for e in [openEngine, filteredEngine] { e.hostMIDI(offset: 0, status: 0x90, data1: 36, data2: 127) }
        var engineOpenEnergy: Float = 0, engineFilteredEnergy: Float = 0
        for _ in 0..<12 {
            engineOpenEnergy += energy(block(openEngine))
            engineFilteredEnergy += energy(block(filteredEngine))
        }
        check(engineFilteredEnergy > 0 && engineFilteredEnergy < engineOpenEnergy * 0.1,
              "note-on applies the selected pad filter in the production engine")
        let oldPadJSON = Data(#"{"level":0.6,"pan":-0.2,"tune":7,"decay":0.4,"reverse":true}"#.utf8)
        let oldPad = try? JSONDecoder().decode(PadSettings.self, from: oldPadJSON)
        check(oldPad?.filter == 1 && oldPad?.tune == 7 && oldPad?.reverse == true,
              "older pad presets decode with the filter open and original controls intact")
        let filteredData = try? JSONEncoder().encode(filteredSettings[0])
        let filteredBack = filteredData.flatMap { try? JSONDecoder().decode(PadSettings.self, from: $0) }
        check(filteredBack == filteredSettings[0], "per-pad filter round-trips in presets")
    }

    /// Renders a loop through a fresh engine and returns the output.
    private static func render(kit: KitBuffers, style: GrooveStyle, mode: SoundMode, tempo: Double, seconds: Double,
                               tweak: (KnockEngine) -> Void = { _ in }) -> ([Float], [Float]) {
        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        engine.setParam(.soundMode, Float(mode.rawValue))
        engine.setParam(.followDAW, 0)
        engine.setParam(.tempoSync, 0)
        engine.setTempo(tempo)
        tweak(engine)
        engine.kitHandoff.publish(kit)
        engine.patternHandoff.publish(PatternSet(GrooveGenerator.loops(style: style, seed: 1)))
        engine.send(KEvent(kind: .loopPad, a: 0))
        let total = Int(seconds * 48_000)
        var outL = [Float](repeating: 0, count: total), outR = [Float](repeating: 0, count: total)
        var done = 0
        while done < total {
            let n = min(256, total - done)
            outL.withUnsafeMutableBufferPointer { l in
                outR.withUnsafeMutableBufferPointer { r in
                    engine.render(frames: n, left: l.baseAddress! + done, right: r.baseAddress! + done, host: nil)
                }
            }
            done += n
        }
        return (outL, outR)
    }

    static func checkModesAndClipper() {
        let kit = kitBuffers(KitLibrary.modernTrap)
        for mode in SoundMode.allCases {
            let (l, r) = render(kit: kit, style: .trap, mode: mode, tempo: 140, seconds: 4) { e in
                e.setParam(.clipDrive, 1)      // +18 dB into the clipper
                e.setParam(.boost, 1); e.setParam(.punch, 1); e.setParam(.grit, 1); e.setParam(.shine, 1); e.setParam(.noise, 0.6)
            }
            var peak: Float = 0
            var finite = true
            var energy: Double = 0
            for i in 0..<l.count {
                if !l[i].isFinite || !r[i].isFinite { finite = false; break }
                peak = max(peak, abs(l[i]), abs(r[i]))
                energy += Double(l[i] * l[i])
            }
            check(finite, "\(mode.title): finite at full drive")
            check(peak <= MasterBus.ceiling + 0.0005, "\(mode.title): clipper ceiling held (\(peak))")
            check(energy > 100, "\(mode.title): makes sound")
        }
        // Clipper off passes level through (OUTPUT 0 dB, low drive): no clipping applied.
        let (l, _) = render(kit: kit, style: .trap, mode: .modern, tempo: 140, seconds: 2) { e in
            e.setParam(.clipper, 0); e.setParam(.clipDrive, 0)
        }
        check(l.contains { abs($0) > 0.05 }, "clipper off still sounds")
    }

    /// The first kick of each bar must land on the bar line at several tempos.
    static func checkTempoSync() {
        var kick = Array(repeating: PadSettings(), count: Pad.count)
        kick[Pad.kick.rawValue].level = 0.8
        let def = KitLibrary.modernTrap
        // A kit where only the kick sounds, so onsets are easy to find.
        let samples = def.pads.enumerated().map { i, r -> SampleBuffer in
            i == Pad.kick.rawValue ? DrumSynth.render(r, sampleRate: 48_000, seed: 1) : SampleBuffer(left: [0, 0, 0, 0], sampleRate: 48_000)
        }
        let kit = KitBuffers(name: "test", samples: samples, settings: kick, bassHz: def.bassHz)
        for tempo in [72.0, 101.0, 140.0, 172.0] {
            let (l, _) = render(kit: kit, style: .trap, mode: .modern, tempo: tempo, seconds: 60 / tempo * 4 * 2 + 0.2) { e in
                e.setParam(.clipper, 0); e.setParam(.boost, 0)
            }
            let barSamples = 60 / tempo * 4 * 48_000
            for bar in 0..<2 {
                let expected = Int(Double(bar) * barSamples)
                let window = l[max(0, expected - 200)..<min(l.count, expected + 600)]
                let onset = window.firstIndex { abs($0) > 0.02 } ?? -99_999
                // The oversampled clipper path adds 15 samples; allow a few more.
                check(abs(onset - expected) <= 40, "tempo \(Int(tempo)) bar \(bar + 1) kick on the line (\(onset - expected) samples)")
            }
        }
    }

    /// FOLLOW DAW: the loop starts with the host's transport, at the host's bar position.
    static func checkHostTransport() {
        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        engine.setParam(.followDAW, 1)
        engine.setParam(.tempoSync, 1)
        engine.setParam(.playMode, 1)
        engine.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        engine.patternHandoff.publish(PatternSet(GrooveGenerator.loops(style: .trap, seed: 1)))
        var l = [Float](repeating: 0, count: 512), r = [Float](repeating: 0, count: 512)
        var beat = 0.0
        let tempo = 120.0
        var heard = false
        var heardWhileStopped = false
        for block in 0..<400 {
            let playing = block >= 100
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    engine.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!,
                                  host: HostTiming(tempo: tempo, beat: beat, playing: playing))
                }
            }
            let loud = l.contains { abs($0) > 0.01 }
            if playing { if loud { heard = true }; beat += 512 / 48_000 * tempo / 60 } else if loud { heardWhileStopped = true }
        }
        check(!heardWhileStopped, "FOLLOW DAW: silent while the DAW is stopped")
        check(heard, "FOLLOW DAW: plays when the DAW plays")
        check(abs(engine.status[4] - tempo) < 0.01, "TEMPO SYNC: uses the DAW's tempo")
        // BreakBoss's own STOP / PLAY still work while the DAW runs.
        func run(_ blocks: Int) -> Bool {
            var loud = false
            for _ in 0..<blocks {
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        engine.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!,
                                      host: HostTiming(tempo: tempo, beat: beat, playing: true))
                    }
                }
                beat += 512 / 48_000 * tempo / 60
                if l.contains(where: { abs($0) > 0.01 }) { loud = true }
            }
            return loud
        }
        engine.send(KEvent(kind: .stop))
        _ = run(40)
        check(!run(200), "FOLLOW DAW: BreakBoss STOP mutes the pattern while the DAW keeps playing")
        engine.send(KEvent(kind: .play))
        check(run(200), "FOLLOW DAW: BreakBoss PLAY brings the pattern back on the DAW's beat")
    }

    /// Nothing playing: silence (and after a while the chain stops running).
    static func checkSilence() {
        let engine = KnockEngine()
        engine.prepare(sampleRate: 48_000, maxFrames: 512)
        engine.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var l = [Float](repeating: 1, count: 512), r = [Float](repeating: 1, count: 512)
        var maxOut: Float = 0
        for _ in 0..<600 {
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    engine.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
                }
            }
            maxOut = max(maxOut, l.map { abs($0) }.max() ?? 0)
        }
        check(maxOut < 1e-4, "idle is silent (\(maxOut))")
        // A pad hit after idling sounds right away.
        engine.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 1))
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                engine.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
            }
        }
        check(l.contains { abs($0) > 0.05 }, "pad sounds after idle")
        // An empty pattern on the sequencer is silent, even when the other patterns have notes:
        // PLAY and the DAW start the pattern on screen (the cue), not the last one that played.
        let cueEngine = KnockEngine()
        cueEngine.prepare(sampleRate: 48_000, maxFrames: 512)
        cueEngine.setParam(.followDAW, 0)
        cueEngine.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var cueLoops = GrooveGenerator.loops(style: .trap, seed: 1)
        cueLoops[3] = PatternData(name: "EMPTY", lengthTicks: cueLoops[3].lengthTicks, events: [])
        cueEngine.patternHandoff.publish(PatternSet(cueLoops))
        func loud(_ e: KnockEngine, blocks: Int) -> Bool {
            var heard = false
            for _ in 0..<blocks {
                l.withUnsafeMutableBufferPointer { lp in
                    r.withUnsafeMutableBufferPointer { rp in
                        e.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
                    }
                }
                if l.contains(where: { abs($0) > 0.01 }) { heard = true }
            }
            return heard
        }
        cueEngine.send(KEvent(kind: .loopPad, a: 0))
        check(loud(cueEngine, blocks: 100), "cue test: pattern 1 plays")
        cueEngine.send(KEvent(kind: .stop))
        _ = loud(cueEngine, blocks: 40)
        cueEngine.send(KEvent(kind: .cue, a: 3))
        cueEngine.send(KEvent(kind: .play))
        check(!loud(cueEngine, blocks: 200), "an empty pattern on the sequencer plays nothing")
    }

    static func checkFiles() {
        let loops = GrooveGenerator.loops(style: .west90s, seed: 3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest.mid")
        do {
            try MIDIFile.write(loops[0], tempo: 95, bounce: 0, bars: loops[0].bars, to: url)
            let back = MIDIFile.read(url)
            check(back != nil, "MIDI file reads back")
            if let back {
                check(back.events.count == loops[0].events.count, "MIDI round trip keeps every hit (\(back.events.count)/\(loops[0].events.count))")
                check(back.lengthTicks == loops[0].lengthTicks, "MIDI round trip keeps the length")
            }
            let allPads = PatternData(name: "ALL 12 MIDI PADS", lengthTicks: PatternData.ppq * 4,
                                      events: Pad.allCases.map { pad in
                GrooveEvent(tick: Int32(pad.rawValue * 12), pad: Int8(pad.rawValue), velocity: 0.75,
                            length: pad == .bass808 ? 12 : 0)
            })
            try MIDIFile.write(allPads, tempo: 95, bounce: 0, bars: 1, to: url)
            let allPadsBack = MIDIFile.read(url)
            check(allPadsBack?.events.count == Pad.count &&
                  Set(allPadsBack?.events.map { Int($0.pad) } ?? []) == Set(Pad.allCases.map { $0.rawValue }),
                  "MIDI export and import preserve all 12 sequential drum pads")
            let lowBass = PatternData(name: "LOW 808 MIDI", lengthTicks: PatternData.ppq * 4,
                                      events: [GrooveEvent(tick: 0, pad: Int8(Pad.bass808.rawValue), velocity: 1,
                                                           semis: -12, length: 96)])
            try MIDIFile.write(lowBass, tempo: 95, bounce: 0, bars: 1, to: url)
            let bassBack = MIDIFile.read(url)?.events.first
            check(bassBack?.pad == Int8(Pad.bass808.rawValue) && bassBack?.semis == -12 && bassBack?.length == 96,
                  "MIDI export keeps a low 808 on note 48, just above the pads")
            check(lowBass.events[0].semis == -12, "MIDI pitch bounding leaves authored and audio-export bass pitch unchanged")
        } catch {
            check(false, "MIDI file writes: \(error)")
        }
        var s = KnockState()
        s.values["boost"] = 0.3
        s.editedLoops[2] = loops[1]
        let data = try? JSONEncoder().encode(s)
        let decoded = data.flatMap { try? JSONDecoder().decode(KnockState.self, from: $0) }
        check(decoded == s, "saved state round trip")
        // Export renders a seamless loop of the right length
        let kit = kitBuffers(KitLibrary.west90s)
        var params = [Float](repeating: 0, count: KParam.count)
        for p in KParam.allCases { params[p.rawValue] = p.defaultValue }
        let job = Exporter.Job(kit: kit, patterns: PatternSet(loops), loop: 0, params: params, tempo: 95, bars: 2, baseName: "selftest")
        let (l, _) = Exporter.render(job, mask: 0xFFFF)
        check(l.count == Int((Double(2) * 4 * (60 / 95.0 * 48_000)).rounded()), "export length is exactly 2 bars")
        check(l.contains { abs($0) > 0.05 }, "export makes sound")
    }
    private static func renderBlock(_ engine: KnockEngine) {
        var l = [Float](repeating: 0, count: 256), r = l
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                engine.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
            }
        }
    }

    static func checkHeldLoops() {
        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 1)
        e.setParam(.followDAW, 0)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        e.patternHandoff.publish(PatternSet(GrooveGenerator.loops(style: .trap, seed: 1)))
        e.receiveMIDI(status: 0x90, data1: 36, data2: 100, time: 0)
        renderBlock(e)
        check(e.status[0] == 1 && e.status[1] == 0, "MIDI hold starts loop")
        e.receiveMIDI(status: 0x91, data1: 37, data2: 100, time: 0)
        renderBlock(e)
        check(e.status[1] == 1, "last-held note takes priority")
        e.receiveMIDI(status: 0x81, data1: 37, data2: 0, time: 0)
        renderBlock(e)
        check(e.status[0] == 1 && e.status[1] == 0, "release returns to previous held note")
        e.receiveMIDI(status: 0x90, data1: 36, data2: 0, time: 0)
        renderBlock(e)
        check(e.status[0] == 0 && e.status[1] == -1, "zero velocity note-on releases final loop")
        for note in 36...47 {
            e.receiveMIDI(status: 0x90, data1: UInt8(note), data2: 100, time: 0)
            renderBlock(e)
            check(e.status[0] == 1 && e.status[1] == Double(note - 36), "MIDI note \(note) holds full loop \(note - 35)")
            e.receiveMIDI(status: 0x80, data1: UInt8(note), data2: 0, time: 0)
            renderBlock(e)
            check(e.status[0] == 0 && e.status[1] == -1, "releasing MIDI note \(note) stops its held loop")
        }
        e.receiveMIDI(status: 0x90, data1: 47, data2: 127, time: 0)
        renderBlock(e)
        check(e.status[1] == 11, "MIDI reaches loop 12")
        e.receiveMIDI(status: 0xB0, data1: 123, data2: 0, time: 0)
        renderBlock(e)
        check(e.status[0] == 0, "all notes off stops loop sequencing")
        e.setParam(.playMode, 0)
        for pad in Pad.allCases {
            let before = e.padHits[pad.rawValue]
            e.receiveMIDI(status: 0x90, data1: UInt8(pad.midiNote), data2: 100, time: 0)
            renderBlock(e)
            check(e.padHits[pad.rawValue] > before, "MIDI plays pad \(pad.rawValue + 1)")
        }
        let bassBefore = e.padHits[Pad.bass808.rawValue]
        e.receiveMIDI(status: 0x90, data1: 48, data2: 100, time: 0)
        renderBlock(e)
        check(e.padHits[Pad.bass808.rawValue] > bassBefore, "MIDI note 48 plays the lowest chromatic 808 without overlapping pads")
        e.setParam(.playMode, 1)
        for _ in 0..<1200 { e.receiveMIDI(status: 0x90, data1: 36, data2: 100, time: 0) }
        renderBlock(e)
        check(e.status[0] == 0, "queue overflow fails silent instead of stuck loop")
        for i in 0..<40 {
            e.kitHandoff.publish(kitBuffers(i % 2 == 0 ? KitLibrary.modernTrap : KitLibrary.west90s))
            e.send(KEvent(kind: .pad, a: 0, value: 1))
            for _ in 0..<4 { renderBlock(e) }
            e.kitHandoff.collect()
        }
        check(e.status[7] > 0, "rapid kit switches keep rendering")
    }

    static func checkPatternEditor() {
        let bar = PatternData.ppq * 4, cell = PatternData.stepTicks
        var p = PatternData(name: "T", lengthTicks: bar * 2, events: [])
        p = PatternEdit.toggle(p, pad: Pad.snare.rawValue, tick: cell * 4, cell: cell)
        check(p.events.count == 1 && p.events[0].tick == cell * 4 && Int(p.events[0].pad) == Pad.snare.rawValue,
              "editor: tap adds a hit on the step")
        p = PatternEdit.toggle(p, pad: Pad.snare.rawValue, tick: cell * 4, cell: cell)
        check(p.events.isEmpty, "editor: tapping the same step removes it")
        var swung = PatternData(name: "S", lengthTicks: bar, events: [GrooveEvent(tick: cell * 2 + 5, pad: Int8(Pad.hat.rawValue), velocity: 0.4)])
        swung = PatternEdit.toggle(swung, pad: Pad.hat.rawValue, tick: cell * 2, cell: cell)
        check(swung.events.isEmpty, "editor: removing a step also removes a swung hit inside it")
        let kept = PatternEdit.toggle(PatternData(name: "K", lengthTicks: bar, events: [GrooveEvent(tick: 0, pad: 0, velocity: 0.33)]),
                                      pad: Pad.hat.rawValue, tick: cell * 8, cell: cell)
        check(kept.events.contains { $0.tick == 0 && $0.velocity == 0.33 }, "editor: untouched hits keep their velocity")
        let bass = PatternEdit.longBass(PatternData(name: "B", lengthTicks: bar, events: []), from: cell * 2, cells: 6, cell: cell)
        check(bass.events.count == 1 && bass.events[0].length == cell * 6 && Int(bass.events[0].pad) == Pad.bass808.rawValue,
              "editor: dragging on the 808 row draws one long note")
        let edge = PatternEdit.longBass(PatternData(name: "E", lengthTicks: bar, events: []), from: bar - cell * 2, cells: 6, cell: cell)
        check(edge.events.first.map { $0.tick + $0.length <= bar } == true, "editor: long 808 stays inside the loop")
        var source = PatternData(name: "C", lengthTicks: bar * 2, events: [
            GrooveEvent(tick: 0, pad: 0, velocity: 1), GrooveEvent(tick: bar + cell * 4, pad: 1, velocity: 1)])
        source = PatternEdit.copyNext(source, fromBar: 0, bars: 2)
        check(source.bars == 4 && source.events.count == 4 && source.events.contains { $0.tick == bar * 2 } &&
              source.events.contains { $0.tick == bar * 3 + cell * 4 }, "editor: COPY NEXT copies bars 1-2 into 3-4")
        let longer = PatternEdit.setLength(PatternData(name: "L", lengthTicks: bar, events: [GrooveEvent(tick: cell, pad: 0, velocity: 1)]), bars: 4)
        check(longer.bars == 4 && longer.events.map { $0.tick } == [cell, bar + cell, bar * 2 + cell, bar * 3 + cell],
              "editor: longer length repeats the pattern")
        let shorter = PatternEdit.setLength(longer, bars: 1)
        check(shorter.bars == 1 && shorter.events.count == 1, "editor: shorter length drops hits past the end")
        let capped = PatternEdit.copyNext(PatternData(name: "M", lengthTicks: bar * 16, events: [GrooveEvent(tick: bar * 14, pad: 0, velocity: 1)]),
                                          fromBar: 14, bars: 2)
        check(capped.bars == 16 && capped.events.count == 1, "editor: COPY NEXT never goes past 16 bars")
        let sixteen = PatternEdit.setLength(PatternData(name: "X", lengthTicks: bar * 4, events: [GrooveEvent(tick: 0, pad: 0, velocity: 1)]), bars: 16)
        check(sixteen.bars == 16 && sixteen.events.count == 4, "drum roll: 16 bars repeats a 4-bar pattern four times")
        check(PatternEdit.setLength(sixteen, bars: 32).bars == 16, "drum roll: patterns stop at 16 bars")
        var saved16 = KnockState()
        saved16.editedLoops[0] = sixteen
        check(saved16.normalized().editedLoops[0]?.bars == 16, "a 16-bar pattern is saved and restored at full length")
        let mid16 = FileManager.default.temporaryDirectory.appendingPathComponent("selftest-16.mid")
        if (try? MIDIFile.write(sixteen, tempo: 120, bounce: 0, bars: 16, to: mid16)) != nil {
            check(MIDIFile.read(mid16)?.bars == 16, "a 16-bar pattern exports and re-imports as MIDI at full length")
        }
        // Edits reach the engine as a valid loop.
        let set = PatternSet([source])
        check(set.loops[0].count == source.events.count && set.loops[0].lengthTicks == Int(source.lengthTicks),
              "editor: edited pattern loads into the engine unchanged")
    }

    static func checkMIDIPadMap() {
        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 0)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        renderBlock(e)
        func hits(_ note: UInt8) -> [UInt32] {
            let before = (0..<Pad.count).map { e.padHits[$0] }
            e.receiveMIDI(status: 0x90, data1: note, data2: 100, time: 0)
            renderBlock(e)
            e.receiveMIDI(status: 0x80, data1: note, data2: 0, time: 0)
            renderBlock(e)
            return (0..<Pad.count).map { e.padHits[$0] - before[$0] }
        }
        func onlyPad(_ d: [UInt32], _ pad: Int) -> Bool { d.enumerated().allSatisfy { $0.offset == pad ? $0.element > 0 : $0.element == 0 } }
        check(onlyPad(hits(36), 0) && onlyPad(hits(47), 11), "MIDI map: standard notes 36-47 by default")
        // MPC Classic, sent the way the controller sends it.
        e.send(KEvent(kind: .mapNote, a: -1))
        for (pad, note) in MIDIPadMap.mpcClassicNotes.enumerated() { e.send(KEvent(kind: .mapNote, a: Int32(note), value: Double(pad))) }
        renderBlock(e)
        for (pad, note) in MIDIPadMap.mpcClassicNotes.enumerated() {
            check(onlyPad(hits(UInt8(note)), pad), "MIDI map: MPC Classic note \(note) plays pad \(pad + 1)")
        }
        check(hits(39).allSatisfy { $0 == 0 } && hits(41).allSatisfy { $0 == 0 }, "MIDI map: notes not on an MPC pad play nothing")
        let bass808 = hits(60)
        check(bass808[Pad.bass808.rawValue] > 0 && bass808.enumerated().allSatisfy { $0.offset == Pad.bass808.rawValue || $0.element == 0 },
              "MIDI map: the chromatic 808 still plays on notes the map doesn't use")
        let learned = MIDIPadMap.learn(MIDIPadMap.standardNotes, pad: 2, note: 36)
        check(learned[2] == 36 && learned[0] == -1 && learned.count == Pad.count, "MIDI learn moves a note to the new pad only")
        check(MIDIPadMap.clean([200, -5]) == [-1, -1] + Array(repeating: -1, count: Pad.count - 2), "MIDI map cleans bad notes")
        var saved = KnockState()
        saved.midiMap = .mpcClassic
        let round = try? JSONDecoder().decode(KnockState.self, from: JSONEncoder().encode(saved))
        check(round?.midiMap == .mpcClassic, "MIDI map is saved with the session / AUv3 project")
        let old = try? JSONDecoder().decode(KnockState.self, from: JSONEncoder().encode(KnockState()))
        check(old != nil && old?.midiMap == nil, "sessions without a MIDI map still load (standard map)")
        check(e.lastNoteOn.pointee & 0x7F == 60 && e.lastNoteOn.pointee >> 8 > 0, "MIDI learn sees the last note played")
        checkMPKMiniPads()
    }

    /// An Akai MPK Mini (Plus) out of the box: pads send notes 36-43 (bank A) and 44-51 (bank B)
    /// on channel 10. With MIDI OUT on in the multi-out layout (pad 10 owns channel 10) they
    /// still play pads 1-12 in ONE-SHOT, and record into the pattern when RECORD is armed.
    static func checkMPKMiniPads() {
        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 0); e.setParam(.followDAW, 0); e.setParam(.tempoSync, 0); e.setTempo(120)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        for p in 0..<Pad.count { e.send(KEvent(kind: .midiOut, a: Int32(p), value: Double(KnockController.defaultMIDIOutChannels[p] * 128 + KnockController.defaultMIDIOutNotes[p]))) }
        e.send(KEvent(kind: .midiOut, a: -1, value: 1))
        renderBlock(e)
        func hits(_ note: UInt8, host: Bool) -> [UInt32] {
            let before = (0..<Pad.count).map { e.padHits[$0] }
            if host { e.hostMIDI(offset: 0, status: 0x99, data1: note, data2: 100) }
            else { e.receiveMIDI(status: 0x99, data1: note, data2: 100, time: 0) }
            renderBlock(e)
            if host { e.hostMIDI(offset: 0, status: 0x89, data1: note, data2: 0) }
            else { e.receiveMIDI(status: 0x89, data1: note, data2: 0, time: 0) }
            for _ in 0..<12 { renderBlock(e) }          // past MIDI OUT's 50 ms loop-back guard
            return (0..<Pad.count).map { e.padHits[$0] - before[$0] }
        }
        func onlyPad(_ d: [UInt32], _ pad: Int) -> Bool { d.enumerated().allSatisfy { $0.offset == pad ? $0.element > 0 : $0.element == 0 } }
        for pad in 0..<Pad.count {
            check(onlyPad(hits(UInt8(36 + pad), host: false), pad), "MPK Mini: pad note \(36 + pad) on channel 10 plays BB pad \(pad + 1)")
            check(onlyPad(hits(UInt8(36 + pad), host: true), pad), "MPK Mini via the AUv3 host: note \(36 + pad) plays BB pad \(pad + 1)")
        }
        // Recorded into the sequencer like an on-screen tap.
        var loops = Array(repeating: PatternData(name: "E", lengthTicks: Int32(PatternData.ppq) * 4, events: []), count: Pad.count)
        loops[0] = PatternData(name: "R", lengthTicks: Int32(PatternData.ppq) * 4, events: [])
        e.patternHandoff.publish(PatternSet(loops))
        renderBlock(e)
        e.send(KEvent(kind: .recordArm, a: 1))
        e.send(KEvent(kind: .loopPad, a: 0))
        for _ in 0..<10 { renderBlock(e) }
        _ = e.collectRecorded()
        e.receiveMIDI(status: 0x99, data1: 37, data2: 100, time: 0)
        renderBlock(e)
        let rec = e.collectRecorded()
        check(rec.count == 1 && Int(rec[0].pad) == Pad.snare.rawValue && rec[0].semis == 0, "MPK Mini: a pad hit records into the pattern while RECORD is on")
        e.send(KEvent(kind: .recordArm, a: 0))
        e.send(KEvent(kind: .stop))
        renderBlock(e)
    }

    static func checkRecordingTrim() {
        #if canImport(AVFoundation)
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest take.wav")
            try? FileManager.default.removeItem(at: url)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
                                           AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 24,
                                           AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
            buffer.frameLength = 48_000
            let d = buffer.floatChannelData![0]
            for i in 0..<48_000 { d[i] = i < 24_000 ? 0.001 : 0.5 * sinf(Float(i) * 0.05) * expf(-Float(i - 24_000) / 4_000) }
            do {
                let w = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                try w.write(from: buffer)
            }
            let trimmed = try PadRecorder.trimLeadingSilence(url)
            check(trimmed != nil, "record: a take with sound is kept")
            if let trimmed {
                let f = try AVAudioFile(forReading: trimmed)
                check(f.length > 23_000 && f.length < 24_400, "record: silence before the hit is trimmed (\(f.length) frames)")
                let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
                try f.read(into: b)
                check(abs(b.floatChannelData![0][0]) < 0.0001, "record: the trimmed take starts without a click")
                let back = try SampleLoader.load(trimmed)
                check(back.length > 0, "record: the take loads like an imported sample")
                try? FileManager.default.removeItem(at: trimmed)
            }
            let silent = FileManager.default.temporaryDirectory.appendingPathComponent("selftest silent.wav")
            try? FileManager.default.removeItem(at: silent)
            for i in 0..<48_000 { d[i] = 0.0005 }
            do {
                let w = try AVAudioFile(forWriting: silent, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                try w.write(from: buffer)
            }
            check(try PadRecorder.trimLeadingSilence(silent) == nil, "record: a silent take is not put on the pad")
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: silent)
        } catch {
            check(false, "record: trim test ran (\(error.localizedDescription))")
        }
        #endif
    }

    static func checkWorkspaceChannels() {
        let sharedSound = "stock:bb-test-kick.wav"
        let first = WorkspaceChannel(id: UUID(), pad: 0, soundID: sharedSound,
                                     name: "KICK A", category: SoundType.kick.rawValue)
        let second = WorkspaceChannel(id: UUID(), pad: 1, soundID: sharedSound,
                                      name: "KICK B", category: SoundType.kick.rawValue)
        var state = KnockState()
        state.workspaceChannels = [first, second]
        let normalized = state.normalized()
        check(normalized.workspaceChannels?.count == 2 &&
              normalized.workspaceChannels?[0].soundID == normalized.workspaceChannels?[1].soundID &&
              normalized.workspaceChannels?[0].pad != normalized.workspaceChannels?[1].pad,
              "rack: the same library sound may occupy independent engine slots")
        let restored = (try? JSONEncoder().encode(state)).flatMap {
            try? JSONDecoder().decode(KnockState.self, from: $0)
        }
        check(restored?.workspaceChannels == state.workspaceChannels,
              "rack: duplicate sounds and track identity survive project saving")
        state.workspaceChannels?.append(WorkspaceChannel(id: UUID(), pad: 1, soundID: sharedSound,
                                                          name: "DUPLICATE PAD", category: SoundType.kick.rawValue))
        check(state.normalized().workspaceChannels?.count == 2,
              "rack: invalid duplicate audio slots are removed on migration")
        for p in 2..<Pad.count {
            state.workspaceChannels?.append(WorkspaceChannel(id: UUID(), pad: p,
                soundID: "stock:sample-\(p)", name: "SAMPLE \(p)", category: SoundType.perc.rawValue))
        }
        check(state.normalized().workspaceChannels?.count == Pad.count,
              "rack: up to 12 independent sound channels")
        check(KnockState().normalized().workspaceChannels == nil,
              "rack: old sessions open without losing their faceplate or saved pads")
        // The rack mirrors the kit until it's changed: one channel per pad, kit names.
        let rcEngine = KnockEngine(); rcEngine.prepare(sampleRate: 48_000, maxFrames: 512)
        let rc = KnockController(engine: rcEngine, isPlugin: true)
        check(rc.rackChannels.count == Pad.count && rc.rackChannels.map(\.pad) == Array(0..<Pad.count) && rc.rackChannels[0].name == "KICK",
              "rack: starts as the kit's 12 channels")
        if let last = rc.rackChannels.last {
            rc.removeRackChannel(last.id)
            check(rc.rackChannels.count == Pad.count && rc.rackChannels.last?.soundID == "kit",
                  "rack: deleting a channel puts the kit's sound back, all 12 pads stay on screen")
            let sound = LibrarySound(id: "test", url: URL(fileURLWithPath: "/"), name: "TEST SNARE", type: .snare, pack: "TEST", user: true)
            let added = rc.addRackChannel(sound, load: false)
            check(added?.pad == last.pad && rc.rackChannels.count == Pad.count && rc.rackChannels.last?.name == "TEST SNARE",
                  "rack: a dropped sound takes a free kit channel")
            rc.resetRack()
            check(rc.rackChannels.count == Pad.count && rc.rackChannels[0].soundID == "kit", "rack: back to the kit's channels")
            // Face 1 and Face 2 stay in step: every pad is in the rack, a kit fills rack and pads.
            if let preset = PatternBank.all.first(where: { $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } }) {
                rc.removeRackChannel(rc.rackChannels[Pad.kick.rawValue].id)
                check(!rc.loops.contains { $0.events.contains { Int($0.pad) == Pad.kick.rawValue } },
                      "rack: a deleted channel's notes go from every pattern")
                rc.loadPatternPreset(preset)
                _ = rc.addRackChannel(sound, load: false)
                check(rc.rackChannels.map(\.pad) == Array(0..<Pad.count), "rack: always all 12 pads, in pad order")
                rc.selectKit(KitLibrary.factory[2])
                check(rc.rackChannels.allSatisfy { $0.soundID == "kit" }, "rack: a kit loads into the rack as well as the pads")
            }
            rc.setLoop(3, rc.loops[3])
            check(rc.screenPattern == 3, "PLAY on the faceplate plays the pattern the sequencer shows")
            if let preset = PatternBank.all.last {
                rc.loadPatternPreset(preset)
                check(rc.screenPattern == 0, "a new pattern opens on its MAIN A, not the part of the last one on screen")
            }
        }
        var pattern = PatternData(name: "RACK", lengthTicks: PatternEdit.barTicks,
                                  events: [])
        pattern = PatternEdit.toggle(pattern, pad: first.pad, tick: 0, cell: PatternData.stepTicks)
        check(pattern.events.count == 1 && Int(pattern.events[0].pad) == first.pad,
              "rack: first channel has its own sequenced steps")
        pattern = PatternEdit.toggle(pattern, pad: second.pad, tick: 0, cell: PatternData.stepTicks)
        check(pattern.events.count == 2 && Set(pattern.events.map(\.pad)).count == 2,
              "rack: identical sounds never share their MIDI events")
    }

    static func checkDrumRoll() {
        let bar = PatternEdit.barTicks, step = PatternData.stepTicks
        // Note operations.
        var p = PatternData(name: "D", lengthTicks: bar * 2, events: [])
        p = PatternEdit.addNote(p, pad: Pad.kick.rawValue, tick: 0, velocity: 0.9)
        p = PatternEdit.addNote(p, pad: Pad.kick.rawValue, tick: 1, velocity: 0.5)
        check(p.events.count == 1 && p.events[0].velocity == 0.5, "drum roll: drawing on an existing hit replaces it")
        p = PatternEdit.addNote(p, pad: Pad.bass808.rawValue, tick: step * 4, length: step * 6, velocity: 1, semis: 5)
        check(p.events.contains { Int($0.pad) == Pad.bass808.rawValue && $0.length == step * 6 && $0.semis == 5 }, "drum roll: long 808 note with pitch")
        let drums = PatternEdit.addNote(p, pad: Pad.snare.rawValue, tick: step * 4, length: 99, velocity: 1)
        check(drums.events.first { Int($0.pad) == Pad.snare.rawValue }?.length == 0, "drum roll: drum hits have no length")
        let kickKey = NoteKey(p.events.first { Int($0.pad) == Pad.kick.rawValue }!)
        let (moved, movedKeys) = PatternEdit.move(p, [kickKey], by: step * 2)
        check(moved.events.contains { Int($0.pad) == Pad.kick.rawValue && $0.tick == kickKey.tick + step * 2 } && movedKeys.count == 1, "drum roll: move")
        let (clampedMove, _) = PatternEdit.move(p, [kickKey], by: -500)
        check(clampedMove.events.contains { Int($0.pad) == Pad.kick.rawValue && $0.tick == 0 }, "drum roll: notes can't move before the start")
        let bassKey = NoteKey(p.events.first { Int($0.pad) == Pad.bass808.rawValue }!)
        let (resized, _) = PatternEdit.resize(p, bassKey, length: bar * 4)
        check(resized.events.first { Int($0.pad) == Pad.bass808.rawValue }.map { $0.tick + $0.length <= bar * 2 } == true, "drum roll: 808 stretch stays inside")
        let vel = PatternEdit.setVelocity(p, [kickKey], 0.2)
        check(vel.events.first { NoteKey($0) == kickKey }?.velocity == 0.2, "drum roll: velocity lane")
        let (pitched, pitchedKeys) = PatternEdit.setPitch(p, [kickKey], 30)
        check(pitched.events.first { Int($0.pad) == Pad.kick.rawValue }?.semis == 12 && pitchedKeys.count == 1, "drum roll: drum pitch limited to +12")
        let (dup, dupKeys) = PatternEdit.duplicate(p, [kickKey, bassKey])
        check(dupKeys.count == 2 && dup.events.count == p.events.count + 2, "drum roll: DUPLICATE copies the selection")
        let removed = PatternEdit.remove(p, [kickKey])
        check(!removed.events.contains { NoteKey($0) == kickKey } && removed.events.count == p.events.count - 1, "drum roll: erase")
        var loose = PatternData(name: "Q", lengthTicks: bar, events: [GrooveEvent(tick: 29, pad: 0, velocity: 1), GrooveEvent(tick: 383, pad: 1, velocity: 1)])
        loose = PatternEdit.quantize(loose, nil, grid: step)
        check(loose.events.map { $0.tick }.sorted() == [0, 24], "drum roll: quantize (and wrap at the end)")
        let rec = PatternEdit.addRecorded(PatternData(name: "R", lengthTicks: bar, events: []), pad: 2, tick: 47, velocity: 0.6, semis: 0, snap: step)
        check(rec.events.first?.tick == 48, "drum roll: recorded hits snap to the grid")
        // Channel menu (two-finger tap): fill every N.
        let filled = PatternEdit.fill(p, pad: Pad.hat.rawValue, every: PatternData.ppq, velocity: 0.7)
        check(filled.events.filter { Int($0.pad) == Pad.hat.rawValue }.map { $0.tick } == [0, 96, 192, 288, 384, 480, 576, 672],
              "drum roll: fill every 1/4 puts a hit on every beat")
        check(filled.events.filter { Int($0.pad) != Pad.hat.rawValue }.count == p.events.count, "drum roll: fill leaves other channels alone")
        let halfStep = PatternEdit.fill(p, pad: Pad.hat.rawValue, every: step / 2, velocity: 0.7)
        check(halfStep.events.filter { Int($0.pad) == Pad.hat.rawValue }.count == Int(bar * 2 / (step / 2)), "drum roll: fill every 1/2 step")
        let barFill = PatternEdit.fill(p, pad: Pad.bass808.rawValue, every: bar, velocity: 1)
        check(barFill.events.filter { Int($0.pad) == Pad.bass808.rawValue }.map { $0.tick } == [0, bar]
              && barFill.events.allSatisfy { Int($0.pad) != Pad.bass808.rawValue || $0.length > step }, "drum roll: fill every bar (808 holds)")
        check(!PatternEdit.clearChannel(filled, pad: Pad.hat.rawValue).events.contains { Int($0.pad) == Pad.hat.rawValue }, "drum roll: clear channel")
        // Note repeat: hold a step and pull down.
        let hatHit = GrooveEvent(tick: step * 2, pad: Int8(Pad.hat.rawValue), velocity: 0.6, semis: 0)
        let one = PatternData(name: "N", lengthTicks: bar, events: [hatHit, GrooveEvent(tick: step * 3, pad: Int8(Pad.hat.rawValue), velocity: 0.7)])
        let rolled = PatternEdit.repeatStep(one, pad: Pad.hat.rawValue, cellStart: step * 2, cell: step, count: 4, like: hatHit)
        let rollTicks = rolled.events.filter { Int($0.pad) == Pad.hat.rawValue && $0.tick >= step * 2 && $0.tick < step * 3 }.map { $0.tick }
        check(rollTicks == [step * 2, step * 2 + step / 4, step * 2 + step / 2, step * 2 + step * 3 / 4]
              && rolled.events.contains { $0.tick == step * 3 }, "note repeat: four even hits in the step, the next step untouched")
        let back = PatternEdit.repeatStep(rolled, pad: Pad.hat.rawValue, cellStart: step * 2, cell: step, count: 1, like: hatHit)
        check(back.events.count == one.events.count, "note repeat: pulling back up to 1 leaves one hit")
        check(PatternEdit.repeatCounts(cell: step) == [1, 2, 3, 4, 6, 8], "note repeat: the counts a pull steps through")
        // Snap to scale (FL's list).
        let minor = MusicScale.named("Minor (Aeolian)")
        check(MusicScale.all.count == 23 && minor.steps == [0, 2, 3, 5, 7, 8, 10], "scales: FL list and C minor")
        check(minor.snap(61, root: 0) == 60 && minor.snap(64, root: 0) == 63 && minor.snap(66, root: 0) == 65, "scales: snap to nearest (ties go down)")
        check(MusicScale.named("Major (Ionian)").snap(66, root: 7) == 66 && !MusicScale.named("Major (Ionian)").contains(65, root: 7), "scales: G major has F# not F")
        check(MusicScale.midiNote(hz: 55) == 33 && MusicScale.noteName(33) == "A1" && MusicScale.noteName(60) == "C4", "scales: 808 root note names")
        check(MusicScale.all.allSatisfy { sc in (0..<128).allSatisfy { sc.contains(sc.snap($0, root: 3), root: 3) } }, "scales: every snap lands in the scale")
        // Mute / solo.
        var muted = Array(repeating: false, count: Pad.count), solo = muted
        check(KnockController.padMask(muted: muted, solo: solo) == 0x0FFF, "mute/solo: everything plays by default")
        muted[1] = true
        check(KnockController.padMask(muted: muted, solo: solo) == 0x0FFD, "mute/solo: mute silences one channel")
        solo[0] = true; solo[1] = true
        check(KnockController.padMask(muted: muted, solo: solo) == 0x0001, "mute/solo: solo plays only soloed channels, mutes still win")
        // Humanize = the live drummer: repeatable, and it doesn't touch the notes you see.
        var h = PatternData(name: "H", lengthTicks: bar * 4, events: [])
        for b4 in 0..<4 {
            let b0 = Int32(b4) * bar
            h.events += (0..<16).map { GrooveEvent(tick: b0 + Int32($0) * step, pad: Int8(Pad.hat.rawValue), velocity: 0.7) }
            h.events += [GrooveEvent(tick: b0, pad: Int8(Pad.kick.rawValue), velocity: 0.9),
                         GrooveEvent(tick: b0, pad: Int8(Pad.bass808.rawValue), velocity: 0.9, length: 48),
                         GrooveEvent(tick: b0 + 4 * step, pad: Int8(Pad.snare.rawValue), velocity: 0.95),
                         GrooveEvent(tick: b0 + 7 * step, pad: Int8(Pad.snare.rawValue), velocity: 0.35),
                         GrooveEvent(tick: b0 + 12 * step, pad: Int8(Pad.snare.rawValue), velocity: 0.95)]
        }
        h.sort()
        h.humanize = 0.8
        let h1 = PatternSet.humanized(h), h2 = PatternSet.humanized(h)
        check(h1 == h2 && h1.events != h.events, "humanize: same pattern, same feel")
        check(zip(h1.events, h.events).allSatisfy { $0.0.tick == $0.1.tick && $0.0.pad == $0.1.pad && abs($0.0.feel) <= LiveDrummer.maxFeel },
              "humanize: notes stay on their steps, the feel stays small")
        func avg(_ pick: (GrooveEvent) -> Bool, _ value: (GrooveEvent) -> Float) -> Float {
            let x = h1.events.filter(pick).map(value)
            return x.isEmpty ? 0 : x.reduce(0, +) / Float(x.count)
        }
        let hat = Int8(Pad.hat.rawValue), snare = Int8(Pad.snare.rawValue)
        check(avg({ $0.pad == hat && $0.tick % 96 == 0 }, { $0.velocity }) > avg({ $0.pad == hat && $0.tick % 48 == 24 }, { $0.velocity }) + 0.05,
              "humanize: hats on the beat louder than the e / a")
        check(avg({ $0.pad == snare && $0.velocity > 0.6 }, { $0.feel }) > avg({ $0.pad == hat }, { $0.feel }) + 0.3,
              "humanize: backbeats laid back behind the hats")
        check(h1.events.filter { $0.pad == snare && $0.tick % 96 == 72 }.allSatisfy { $0.velocity < 0.45 }
              && h1.events.allSatisfy { $0.velocity <= 0.97 }, "humanize: ghosts stay quiet, peaks under 127")
        check(h1.events.filter { $0.pad == Int8(Pad.bass808.rawValue) }.allSatisfy { b in
                  h1.events.contains { $0.pad == Int8(Pad.kick.rawValue) && $0.tick == b.tick && $0.feel == b.feel } && b.velocity == 0.9 && b.semis == 0 },
              "humanize: the 808 stays locked to the kick")
        let hatPitches = h1.events.filter { $0.pad == hat }.map(\.semis)
        check(Set(hatPitches).count > 8 && hatPitches.allSatisfy { abs($0) < 0.2 }, "humanize: repeated hits a few cents apart")
        h.humanize = nil
        check(PatternSet.humanized(h) == h, "humanize: off plays the pattern as written")
        // Engine: per-hit pitch, mute mask, record ring, playhead.
        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 1)
        e.setParam(.followDAW, 0)
        e.setParam(.tempoSync, 0)
        e.setTempo(120)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var rp = PatternData(name: "REC", lengthTicks: bar, events: [GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1)])
        e.patternHandoff.publish(PatternSet([rp] + Array(repeating: rp, count: Pad.count - 1)))
        renderBlock(e)
        e.send(KEvent(kind: .loopPad, a: 0))
        for _ in 0..<20 { renderBlock(e) }
        check(e.playheadTick.pointee > 0 && e.playheadTick.pointee < Double(bar), "drum roll: playhead follows the pattern")
        e.send(KEvent(kind: .recordArm, a: 1))
        e.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 0.8))
        renderBlock(e)
        let hits = e.collectRecorded()
        check(hits.count == 1 && Int(hits[0].pad) == Pad.snare.rawValue && hits[0].tick > 0 && hits[0].loop == 0,
              "drum roll: RECORD captures a live hit at its place in the pattern")
        e.receiveMIDI(status: 0x90, data1: 38, data2: 100, time: 0)
        renderBlock(e)
        check(Int(e.status[1]) == 0 && e.collectRecorded().count == 1, "drum roll: while recording, MIDI notes play drums instead of switching loops")
        e.send(KEvent(kind: .recordArm, a: 0))
        let kickBefore = e.padHits[Pad.kick.rawValue]
        e.send(KEvent(kind: .padMask, a: Int32(0x0FFF & ~1)))
        e.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 1))
        renderBlock(e)
        check(e.padHits[Pad.kick.rawValue] == kickBefore, "mute: a muted channel doesn't sound")
        e.send(KEvent(kind: .padMask, a: 0x0FFF))
        renderBlock(e)
        rp.events = [GrooveEvent(tick: 0, pad: Int8(Pad.snare.rawValue), velocity: 1, semis: 7)]
        let set = PatternSet([rp])
        check(set.loops[0].events[0].semis == 7, "drum roll: drum hits keep their own pitch for the engine")
        // Metronome: silent kit, playing → clicks; off → silence.
        let m = KnockEngine()
        m.prepare(sampleRate: 48_000, maxFrames: 256)
        m.setParam(.playMode, 1); m.setParam(.followDAW, 0); m.setParam(.tempoSync, 0); m.setTempo(120)
        m.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        m.patternHandoff.publish(PatternSet(Array(repeating: PatternData(name: "E", lengthTicks: bar, events: []), count: Pad.count)))
        renderBlock(m)
        m.send(KEvent(kind: .loopPad, a: 0))
        m.send(KEvent(kind: .metronome, a: 1))
        var clickEnergy: Float = 0
        for _ in 0..<200 {
            var l = [Float](repeating: 0, count: 256), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in m.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil) } }
            clickEnergy += l.reduce(0) { $0 + $1 * $1 }
        }
        check(clickEnergy > 0.5, "metronome clicks while playing (\(clickEnergy))")
        // MIDI out (multi-out): kick on channel 1 note 36, snare on channel 2 note 38, off by default.
        let mo = KnockEngine()
        mo.prepare(sampleRate: 48_000, maxFrames: 256)
        mo.setParam(.playMode, 1); mo.setParam(.followDAW, 0); mo.setParam(.tempoSync, 0); mo.setTempo(120)
        mo.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var loopsMO = Array(repeating: PatternData(name: "E", lengthTicks: bar, events: []), count: Pad.count)
        loopsMO[0] = PatternData(name: "M", lengthTicks: bar, events: [GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1),
                                                                       GrooveEvent(tick: PatternData.ppq, pad: Int8(Pad.snare.rawValue), velocity: 0.5)])
        mo.patternHandoff.publish(PatternSet(loopsMO))
        renderBlock(mo)
        func collect(_ blocks: Int) -> [(Int, UInt8, UInt8, UInt8)] {
            var got: [(Int, UInt8, UInt8, UInt8)] = []
            for _ in 0..<blocks {
                var l = [Float](repeating: 0, count: 256), r = l
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in mo.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil) } }
                mo.forEachMIDIOut { got.append(($0, $1, $2, $3)) }
            }
            return got
        }
        mo.send(KEvent(kind: .loopPad, a: 0))
        check(collect(120).isEmpty, "MIDI out: nothing is sent while it's off")
        mo.send(KEvent(kind: .midiOut, a: Int32(Pad.kick.rawValue), value: 0 * 128 + 36))
        mo.send(KEvent(kind: .midiOut, a: Int32(Pad.snare.rawValue), value: 1 * 128 + 38))
        mo.send(KEvent(kind: .midiOut, a: -1, value: 1))
        let sent = collect(800)          // two full bars at 120 BPM (4.3 s), so every hit comes round again
        check(sent.contains { $0.1 == 0x90 && $0.2 == 36 && $0.3 == 127 }, "MIDI out: kick note on, channel 1, note 36")
        check(sent.contains { $0.1 == 0x91 && $0.2 == 38 && $0.3 == 64 }, "MIDI out: snare on its own channel (2), note 38, velocity")
        check(sent.contains { $0.1 == 0x80 && $0.2 == 36 }, "MIDI out: note off follows")
        check(sent.allSatisfy { $0.0 >= 0 && $0.0 < 256 }, "MIDI out: messages fall inside their buffer")
        mo.send(KEvent(kind: .stop))
        _ = collect(40)
        // Round trip: the DAW playing the recorded part back plays the drum itself (LOOP mode too), no echo.
        mo.hostMIDI(offset: 0, status: 0x91, data1: 38, data2: 100)
        var l3 = [Float](repeating: 0, count: 256), r3 = l3
        l3.withUnsafeMutableBufferPointer { lp in r3.withUnsafeMutableBufferPointer { rp in mo.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil) } }
        var echoed = 0
        mo.forEachMIDIOut { _, _, _, _ in echoed += 1 }
        check(l3.contains { abs($0) > 0.01 }, "MIDI in: the recorded snare (channel 2, note 38) plays the snare in LOOP mode")
        check(echoed == 0, "MIDI in: notes from the DAW don't go back out")
        _ = rp
        checkCountInAndPitchedMIDI()
        checkFeel()
    }

    /// Per-track swing, push / pull, NOTE OFFSET and CHANCE: saved, played, recorded and exported.
    static func checkFeel() {
        let bar = PatternData.ppq * 4, kick = Int8(Pad.kick.rawValue), snare = Int8(Pad.snare.rawValue), hat = Pad.hat.rawValue
        // Older saves (no offset or chance) load on the grid, always playing; new ones round trip.
        let old = #"{"tick":24,"pad":1,"velocity":0.5,"semis":0,"length":0,"glide":false}"#
        let e0 = try? JSONDecoder().decode(GrooveEvent.self, from: Data(old.utf8))
        check(e0?.offset == 0 && e0?.chance == 1 && e0?.tick == 24, "feel: older notes load on their step, always playing")
        var fe = GrooveEvent(tick: 48, pad: snare, velocity: 0.9)
        fe.offset = -5; fe.chance = 0.5
        let back = (try? JSONEncoder().encode(fe)).flatMap { try? JSONDecoder().decode(GrooveEvent.self, from: $0) }
        check(back == fe, "feel: note offset and chance are saved")
        // Where a note plays: a track's own swing, its push / pull and the note's own offset.
        var p = PatternData(name: "F", lengthTicks: bar, events: [GrooveEvent(tick: 24, pad: Int8(hat), velocity: 1),
                                                                   GrooveEvent(tick: 24, pad: kick, velocity: 1), fe])
        p.setSwing(pad: hat, 1)
        p.setShift(pad: Int(snare), -4)
        check(p.playTick(p.events[0], bounce: 0) == 32, "feel: a track's own swing moves its off 16ths with the knob at zero")
        check(p.playTick(p.events[1], bounce: 0) == 24, "feel: the other tracks stay straight")
        check(p.playTick(p.events[2], bounce: 0) == 48 - 4 - 5, "feel: push / pull and note offset add up")
        p.setSwing(pad: hat, -1); p.setShift(pad: Int(snare), 0)
        check(p.trackSwing == nil && p.trackShift == nil, "feel: back to the knob and the grid leaves nothing behind")
        p.setShift(pad: Int(snare), -4)
        let loop = PatternSet([p]).loops[0]
        check(loop.earliest == -9 && (0..<loop.count).contains { loop.events[$0].pad == snare && loop.events[$0].offset == -9 },
              "feel: the engine's copy carries each note's whole offset")
        // RECORD keeps the timing you played as NOTE OFFSET; QUANTIZE clears it.
        let empty = PatternData(name: "R", lengthTicks: bar, events: [])
        let rec = PatternEdit.addRecorded(empty, pad: Int(snare), tick: 99, velocity: 1, semis: 0, snap: 24, keepFeel: true)
        check(rec.events.count == 1 && rec.events[0].tick == 96 && rec.events[0].offset == 3, "feel: RECORD keeps a late hit as +3 on its step")
        var swungEmpty = empty; swungEmpty.setSwing(pad: hat, 1)
        let rec2 = PatternEdit.addRecorded(swungEmpty, pad: hat, tick: 31, velocity: 1, semis: 0, snap: 24, keepFeel: true)
        check(rec2.events.first?.tick == 24 && rec2.events.first?.offset == -1, "feel: RECORD measures from where the swung step plays")
        let plain = PatternEdit.addRecorded(empty, pad: Int(snare), tick: 99, velocity: 1, semis: 0, snap: 24)
        check(plain.events.first?.offset == 0, "feel: RECORD snaps hard unless asked to keep the timing")
        check(PatternEdit.quantize(rec, nil, grid: 24).events.allSatisfy { $0.offset == 0 }, "feel: quantize puts notes back on the grid")
        // CHANCE: the roll is the same on the same pass and changes between passes.
        check(PatternData.chanceRoll(pass: 3, tick: 48, pad: snare) == PatternData.chanceRoll(pass: 3, tick: 48, pad: snare),
              "chance: same pass, same roll")
        let rolls = (0..<400).map { PatternData.chanceRoll(pass: $0, tick: 48, pad: snare) }
        let under = rolls.filter { $0 < 0.5 }.count
        check(under > 150 && under < 250 && rolls.allSatisfy { $0 >= 0 && $0 < 1 }, "chance: 50% plays about half the passes (\(under)/400)")
        // MIDI export plays the feel: the pushed snare lands early, and a 5% note drops out of most bars
        // (8 bars: MIDI import reads back the first 8).
        var ex = PatternData(name: "X", lengthTicks: bar, events: [GrooveEvent(tick: 96, pad: snare, velocity: 1)])
        ex.events[0].offset = -6
        var rare = GrooveEvent(tick: 0, pad: kick, velocity: 1); rare.chance = 0.05
        ex.events.append(rare)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bb-feel-selftest.mid")
        if (try? MIDIFile.write(ex, tempo: 120, bounce: 0, bars: 8, to: url)) != nil, let back = MIDIFile.read(url) {
            let snares = back.events.filter { $0.pad == snare }.map { $0.tick % bar }
            let kicks = back.events.filter { $0.pad == kick }.count
            check(snares.count == 8 && snares.allSatisfy { $0 == 90 }, "feel: MIDI export plays the pushed snare early (\(Set(snares)))")
            check(kicks < 4, "chance: MIDI export drops a 5% note from most bars (\(kicks)/8)")
        } else {
            check(false, "feel: MIDI export with offsets writes and reads back")
        }
        try? FileManager.default.removeItem(at: url)
        // The engine: a 5% note sounds far less often than one that always plays.
        let en = KnockEngine()
        en.prepare(sampleRate: 48_000, maxFrames: 256)
        en.setParam(.playMode, 1); en.setParam(.followDAW, 0); en.setParam(.tempoSync, 0); en.setTempo(240)
        en.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var sure = GrooveEvent(tick: 0, pad: kick, velocity: 1)
        var maybe = GrooveEvent(tick: 48, pad: snare, velocity: 1); maybe.chance = 0.05
        sure.chance = 1
        let one = PatternData(name: "C", lengthTicks: PatternData.ppq, events: [sure, maybe])
        en.patternHandoff.publish(PatternSet(Array(repeating: one, count: Pad.count)))
        renderBlock(en)
        let k0 = en.padHits[Int(kick)], s0 = en.padHits[Int(snare)]
        en.send(KEvent(kind: .loopPad, a: 0))
        for _ in 0..<940 { renderBlock(en) }           // about 5 s at 240 BPM: some 20 passes of a one-beat loop
        let kicksPlayed = Int(en.padHits[Int(kick)] &- k0), snaresPlayed = Int(en.padHits[Int(snare)] &- s0)
        check(kicksPlayed >= 15 && snaresPlayed < kicksPlayed / 3, "chance: the engine skips a 5% note most passes (\(snaresPlayed) of \(kicksPlayed))")
    }

    /// RECORD's count-in, and a drum on its own MIDI channel sending / taking its pitch as the note.
    static func checkCountInAndPitchedMIDI() {
        let bar = Int32(PatternData.ppq) * 4
        let e = KnockEngine()
        e.prepare(sampleRate: 48_000, maxFrames: 256)
        e.setParam(.playMode, 1); e.setParam(.followDAW, 0); e.setParam(.tempoSync, 0); e.setTempo(120)
        e.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var loops = Array(repeating: PatternData(name: "E", lengthTicks: bar, events: []), count: Pad.count)
        loops[0] = PatternData(name: "C", lengthTicks: bar, events: [GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1)])
        e.patternHandoff.publish(PatternSet(loops))
        renderBlock(e)
        let kick0 = e.padHits[Pad.kick.rawValue]
        e.send(KEvent(kind: .recordArm, a: 1))
        e.send(KEvent(kind: .countIn, a: 4, value: 0))           // one bar of count-in at 120 BPM = 2 s = 375 blocks
        var click: Float = 0
        for _ in 0..<300 {
            var l = [Float](repeating: 0, count: 256), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in e.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil) } }
            click += l.reduce(0) { $0 + $1 * $1 }
        }
        check(e.status[0] > 0.5 && e.status[8] > 0 && e.status[8] <= 4, "count-in: the transport runs and counts the beats down (\(e.status[8]) left)")
        check(e.padHits[Pad.kick.rawValue] == kick0, "count-in: the pattern stays silent while counting in")
        check(click > 0.2, "count-in: the metronome clicks through the count-in (\(click))")
        check(e.playheadTick.pointee < 0, "count-in: no playhead until the pattern starts")
        e.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 0.9))
        renderBlock(e)
        check(e.collectRecorded().isEmpty, "count-in: a pad hit during the count-in isn't recorded")
        for _ in 0..<120 { renderBlock(e) }
        check(e.status[8] == 0 && e.padHits[Pad.kick.rawValue] > kick0, "count-in: after the count the pattern plays (\(e.padHits[Pad.kick.rawValue] - kick0) kicks)")
        e.send(KEvent(kind: .pad, a: Int32(Pad.snare.rawValue), value: 0.9))
        renderBlock(e)
        let rec = e.collectRecorded()
        check(rec.count == 1 && Int(rec[0].pad) == Pad.snare.rawValue, "count-in: after the count, pad hits record")
        e.send(KEvent(kind: .recordArm, a: 0))
        e.send(KEvent(kind: .stop))
        renderBlock(e)

        // Pitched MIDI on a channel of its own: snare on channel 2 note 38; a hit pitched +3 goes out as 41,
        // and note 41 coming back in plays the snare 3 semitones up (recorded with its pitch).
        let mo = KnockEngine()
        mo.prepare(sampleRate: 48_000, maxFrames: 256)
        mo.setParam(.playMode, 1); mo.setParam(.followDAW, 0); mo.setParam(.tempoSync, 0); mo.setTempo(120)
        mo.kitHandoff.publish(kitBuffers(KitLibrary.drumMastery))
        var lp = Array(repeating: PatternData(name: "E", lengthTicks: bar, events: []), count: Pad.count)
        lp[0] = PatternData(name: "P", lengthTicks: bar, events: [GrooveEvent(tick: 0, pad: Int8(Pad.snare.rawValue), velocity: 0.8, semis: 3)])
        mo.patternHandoff.publish(PatternSet(lp))
        renderBlock(mo)
        for p in 0..<Pad.count { mo.send(KEvent(kind: .midiOut, a: Int32(p), value: Double(p * 128 + 36 + p))) }
        mo.send(KEvent(kind: .midiOut, a: -1, value: 1))
        mo.send(KEvent(kind: .loopPad, a: 0))
        var got: [(UInt8, UInt8, UInt8)] = []
        for _ in 0..<400 {
            var l = [Float](repeating: 0, count: 256), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in mo.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil) } }
            mo.forEachMIDIOut { got.append(($1, $2, $3)) }
        }
        let snareCh = UInt8(Pad.snare.rawValue)
        check(got.contains { $0.0 == 0x90 | snareCh && $0.1 == 36 + snareCh + 3 }, "MIDI out: a pitched drum on its own channel sends its pitch as the note")
        mo.send(KEvent(kind: .stop))
        for _ in 0..<40 { renderBlock(mo) }
        mo.send(KEvent(kind: .recordArm, a: 1))
        mo.send(KEvent(kind: .loopPad, a: 0))
        for _ in 0..<10 { renderBlock(mo) }
        _ = mo.collectRecorded()
        mo.hostMIDI(offset: 0, status: 0x90 | snareCh, data1: 36 + snareCh + 5, data2: 100)
        var l4 = [Float](repeating: 0, count: 256), r4 = l4
        l4.withUnsafeMutableBufferPointer { lp in r4.withUnsafeMutableBufferPointer { rp in mo.render(frames: 256, left: lp.baseAddress!, right: rp.baseAddress!, host: nil) } }
        let back = mo.collectRecorded()
        check(l4.contains { abs($0) > 0.01 }, "MIDI in: any note on a drum's own channel plays that drum")
        check(back.count == 1 && Int(back[0].pad) == Pad.snare.rawValue && back[0].semis == 5, "MIDI in: the note's pitch is kept (+5) and recorded with the hit")
        mo.send(KEvent(kind: .recordArm, a: 0))
        mo.send(KEvent(kind: .stop))

        // The 12-channel MIDI file: a track per pad, pitch and velocity intact, and it reads back.
        var p12 = PatternData(name: "TWELVE", lengthTicks: bar, events: [
            GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 1),
            GrooveEvent(tick: 48, pad: Int8(Pad.snare.rawValue), velocity: 0.5, semis: -2),
            GrooveEvent(tick: 96, pad: Int8(Pad.bass808.rawValue), velocity: 0.9, semis: 7, length: 72)])
        p12.sort()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("selftest twelve.mid")
        do {
            try MIDIFile.writeChannels(p12, names: (0..<Pad.count).map { "CH \($0 + 1)" }, tempo: 120, bounce: 0, bars: 1, to: url)
            let data = [UInt8]((try? Data(contentsOf: url)) ?? Data())
            check(data.count > 100 && data[9] == 1 && data[11] == UInt8(Pad.count + 1), "MIDI file: 12 channels = a type 1 file with a track per pad")
            check(data.contains(0x90 | UInt8(Pad.snare.rawValue)), "MIDI file: the snare is on its own channel")
            if let back = MIDIFile.read(url) {
                let s = back.events.first { Int($0.pad) == Pad.snare.rawValue }
                let b = back.events.first { Int($0.pad) == Pad.bass808.rawValue }
                check(back.events.count == 3 && s?.semis == -2 && abs((s?.velocity ?? 0) - 0.5) < 0.02, "MIDI file: 12 channels read back with pitch and velocity")
                check(b?.semis == 7 && b?.length == 72, "MIDI file: the 808's note and length come back")
            } else {
                check(false, "MIDI file: the 12-channel file reads back")
            }
            try? FileManager.default.removeItem(at: url)
        } catch {
            check(false, "MIDI file: 12-channel export wrote (\(error))")
        }
    }

    static func checkMigration() {
        var old = KnockState()
        old.pads = Array(repeating: PadSettings(), count: 16)
        old.pads[0].tune = 7
        old.editedLoops = Array(repeating: nil, count: 16)
        old.editedLoops[2] = PatternData(name: "KEEP", lengthTicks: 384, events: [])
        let new = old.normalized()
        check(new.pads.count == 12 && new.pads[0].tune == 7, "16-pad saves migrate to 12 pads without losing pad settings")
        check(new.editedLoops.count == 12 && new.editedLoops[2]?.name == "KEEP", "16-loop saves keep edits on loops 1-12")
        check(KitLibrary.factory.count == 365 && KitLibrary.factory.prefix(42).allSatisfy { $0.name.hasSuffix(" A") || $0.name.hasSuffix(" B") },
              "365 factory kits: the 42 A/B kits, the named ones, the live acoustic ones")
        check(Set(KitLibrary.factory.map(\.name)).count == KitLibrary.factory.count, "every factory kit has its own name")
        for mode in SoundMode.allCases {
            for family in KitLibrary.families {
                let n = KitLibrary.kits(for: mode).filter { $0.family == family }.count
                check(n >= 20, "\(mode.title) kits: \(n) under \(family) (at least 20)")
            }
        }
        check(KitLibrary.kit(id: "trap-a").preferredMode == .modern && KitLibrary.kit(id: "neo-soul-a").preferredMode == .vintage &&
              KitLibrary.kit(id: "amapiano-a").preferredMode == .texture, "the A/B kits stay in their mode banks")
        check(Set(KitLibrary.factory.map { $0.id }).count == KitLibrary.factory.count, "factory kit identifiers unique")
        check(KitLibrary.browserOrder.count == KitLibrary.factory.count, "the kit arrows step through every kit once")
        // The kits before Oct 17 are gone: saves, kits and dice picks that named one open the nearest new kit.
        let ids = Set(KitLibrary.factory.map(\.id))
        check(KitLibrary.retired.count == 98 && KitLibrary.retired.values.allSatisfy { ids.contains($0) } &&
              ids.isDisjoint(with: KitLibrary.retired.keys), "all 98 old kits open a new kit")
        check(KitLibrary.kit(id: "boom-bap").id == "boom-bap-a" && KitLibrary.kit(id: "g-drill-b").id == "drill-a" &&
              KitLibrary.kit(id: "no-such-kit").id == KitLibrary.factory[0].id, "old and unknown kit identifiers open a kit")
        var oldSave = KnockState()
        oldSave.kitID = "cole-world"; oldSave.kitName = "COLE WORLD"
        oldSave.stockPicks = ["detroit", nil, "boom-bap"] + [String?](repeating: nil, count: Pad.count - 3)
        let migrated = oldSave.normalized()
        check(migrated.kitID == "neo-soul-a" && migrated.kitName == "NEO SOUL A" &&
              migrated.stockPicks?[0] == "detroit-2026-a" && migrated.stockPicks?[1] == nil && migrated.stockPicks?[2] == "boom-bap-a",
              "an old save opens the new kit and keeps its dice picks")
        var mine = oldSave; mine.userKit = "MY DRUMS"; mine.kitName = "MY DRUMS"
        check(mine.normalized().kitName == "MY DRUMS" && mine.normalized().kitID == "neo-soul-a", "a saved kit keeps its own name")
        check(Pad.allCases.allSatisfy { Pad.index(forMIDINote: $0.midiNote) == $0.rawValue }, "all pad MIDI mappings round trip")
        check(Pad.count == 12 && Pad.allCases.map { $0.midiNote } == Array(36...47), "12 pads use consecutive MIDI notes 36 through 47")
        check((36...47).allSatisfy { !Pad.bassNoteRange.contains($0) } &&
              Pad.bassNoteRange.allSatisfy { Pad.index(forMIDINote: $0) == nil }, "drum pad and chromatic 808 MIDI ranges do not overlap")
    }

    static func checkFactoryPresetsAndKitIndependence() {
        let presets = PatternBank.all
        check(presets.count >= 150 && Set(presets.map { $0.name }).count == presets.count, "pattern bank loads with unique names (\(presets.count))")
        let wanted = ["Neo Soul", "Dilla Time", "Boom Bap", "90s Rap", "70s Soul", "80s Breaks", "Rock", "Trap", "Alt Trap",
                      "Drill", "UK Drill", "NY Drill", "Detroit 2026", "Bay Area 2026", "RnB", "90s RnB", "UK RnB"]
        check(PatternBank.styles == wanted && presets.count == 170, "170 presets in the 17 research styles, in the genre guide's order")
        for style in wanted { check(PatternBank.presets(in: style).count == 10, "\(style): 10 presets") }
        check(presets.filter { $0.shift != nil || $0.swingLanes != nil || $0.ghostChance != nil }.count >= 60, "the live styles carry their feel")
        for p in presets {
            let pat = p.pattern
            check(!pat.events.isEmpty && pat.events.allSatisfy { $0.tick >= 0 && $0.tick < pat.lengthTicks && Int($0.pad) < Pad.count },
                  "\(p.name): pattern decodes inside its length")
        }
        if let uk = PatternBank.preset(named: "UK DRILL 1 TEMPLATE") {
            let snares = uk.pattern.events.filter { Int($0.pad) == Pad.snare.rawValue }.map { $0.tick / PatternData.stepTicks }
            check(snares == [8, 28] && uk.bpm == 142, "UK drill: snare on beat 3 of bar 1 and beat 4 of bar 2")
        } else {
            check(false, "UK DRILL 1 TEMPLATE is present")
        }
        if let trap = PatternBank.preset(named: "TRAP 2 TRIPLET HATS") {
            let hats = trap.pattern.events.filter { Int($0.pad) == Pad.hat.rawValue }.map { $0.tick }
            check(hats.contains(4 * 24) && hats.contains(4 * 24 + 16) && hats.contains(4 * 24 + 32), "triplet hats decode at 1/3-step spacing")
            check(trap.pattern.events.contains { Int($0.pad) == Pad.bass808.rawValue && $0.length > 24 }, "808 lines decode with their length")
        }
        check(KitLibrary.kits(for: .modern).count >= 6 && KitLibrary.kits(for: .vintage).count >= 6 &&
              KitLibrary.kits(for: .texture).count >= 4, "mode browsers cover six Modern, six Vintage, and four Texture factory kits")
        var source = KnockState()
        source.mode = .texture
        source.playMode = .oneShot
        source.userKit = "USER DRUMS"
        source.presetName = "USER FX"
        source.values[KParam.soundMode.id] = 2
        source.values[KParam.playMode.id] = 0
        source.values[KParam.tempoSync.id] = 1
        source.values[KParam.followDAW.id] = 0
        for p in KParam.allCases where p.isKnob || p == .clipper { source.values[p.id] = p == .clipper ? 0 : 0.91 }
        for i in source.pads.indices {
            source.pads[i].tune = Float(i % 5) - 2
            source.pads[i].decay = 0.4
            source.pads[i].filter = 0.65
            source.pads[i].pan = i % 2 == 0 ? -0.2 : 0.2
            source.pads[i].sampleFile = "custom-\(i).wav"
        }
        source.editedLoops[0] = PatternData(name: "CUSTOM LOOP", lengthTicks: 384, events: [])
        source = source.normalized()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        source.grooveSeed = 777
        source.bpm = 101
        let otherKit = KitLibrary.factory.first { $0.id != source.kitID } ?? KitLibrary.factory[0]
        let changedKit = source.selectingKit(otherKit)
        var expectedPads = source.pads
        for i in expectedPads.indices { expectedPads[i].sampleFile = nil }
        check(changedKit.kitID == otherKit.id && changedKit.kitName == otherKit.name &&
              changedKit.userKit == nil, "switching kits replaces the drum sounds")
        check(changedKit.values == source.values && changedKit.mode == source.mode &&
              changedKit.playMode == source.playMode && changedKit.presetName == source.presetName,
              "switching kits preserves active mode, FX knobs, clipper, transport and preset identity")
        check(changedKit.pads == expectedPads, "switching kits preserves per-pad pitch, decay, filter, level and pan")
        check(changedKit.editedLoops == source.editedLoops && changedKit.grooveSeed == 777 && changedKit.bpm == 101 &&
              changedKit.patternStyle == KitLibrary.kit(id: source.kitID).style,
              "switching kits keeps the pattern, its edits and the tempo")
        let twice = changedKit.selectingKit(KitLibrary.factory[KitLibrary.factory.count - 1])
        check(twice.patternStyle == changedKit.patternStyle, "cycling kits never changes the pattern")

        for preset in presets {
            let state = preset.applying(to: source)
            check(state.kitID == source.kitID && state.mode == source.mode && state.pads == source.pads,
                  "\(preset.name): keeps the current kit, mode and pad sounds")
            for p in KParam.allCases where (p.isKnob || p == .clipper) && p != .bounce {
                check(state.values[p.id] == source.values[p.id], "\(preset.name): keeps \(p.name)")
            }
            check(state.basePattern == preset.pattern && state.editedLoops.allSatisfy { $0 == nil } && state.presetName == preset.name &&
                  abs((state.values[KParam.bounce.id] ?? 0) - preset.bounce) < 0.0001, "\(preset.name): loads its pattern and swing")
            check(state.values[KParam.playMode.id] == 0 && state.values[KParam.tempoSync.id] == 1 &&
                  state.values[KParam.followDAW.id] == 0 && state.bpm == source.bpm,
                  "\(preset.name): preserves player and host transport choices (tempo sync keeps the tempo)")
            let loops = GrooveGenerator.loops(fromMain: preset.pattern, style: preset.grooveStyle, seed: 1)
            check(loops.count == Pad.count && !loops[0].events.isEmpty && loops.allSatisfy { $0.lengthTicks >= PatternData.ppq * 4 },
                  "\(preset.name): 12 loops built from its pattern")
            check(loops[0].events.count >= preset.pattern.events.count, "\(preset.name): MAIN A keeps every authored hit")
        }
        var unsynced = source
        unsynced.values[KParam.tempoSync.id] = 0
        if let first = presets.first { check(first.applying(to: unsynced).bpm == first.bpm, "a preset sets its tempo when not synced") }
        if let first = presets.first { check(first.applying(to: source, hosted: false).bpm == first.bpm, "standalone: a pattern brings its tempo even with TEMPO SYNC on") }
        let old = try? JSONDecoder().decode(KnockState.self, from: encoder.encode(KnockState()))
        check(old?.patternStyle == nil && old?.basePattern == nil, "older saves load and follow their kit's patterns")
        // Randomize stays in style and only touches what it should.
        let r1 = PatternRandomizer.randomPattern(style: "Boom Bap", length: PatternData.ppq * 8, seed: 5)
        let r2 = PatternRandomizer.randomPattern(style: "Boom Bap", length: PatternData.ppq * 8, seed: 5)
        check(r1 == r2 && r1.events.contains { Int($0.pad) == Pad.kick.rawValue }, "randomize: same seed, same pattern, still has a kick")
        if let base = PatternBank.preset(named: "TRAP 1 ATL BOUNCE")?.pattern {
            let changed = PatternRandomizer.randomChannel(base, pad: Pad.hat.rawValue, style: "Trap", seed: 9)
            check(changed.events.filter { Int($0.pad) != Pad.hat.rawValue } == base.events.filter { Int($0.pad) != Pad.hat.rawValue },
                  "channel dice changes only that channel")
        }
    }

    /// No preset pattern plays silent. Every kit's 12 pads are audible (checkKits, checkStockSamples)
    /// and every pattern lane is one of those 12 pads, so what's left is the pattern: each of a preset's
    /// 12 loops has notes (an INTRO with no hats to keep falls back on the groove) and, through a kit,
    /// MAIN A makes sound and every other loop hits its pads.
    static func checkEveryPatternAudible() {
        let kit = kitBuffers(KitLibrary.drumMastery)
        var l = [Float](repeating: 0, count: 512), r = l
        func block(_ e: KnockEngine) -> Float {
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    e.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
                }
            }
            return max(l.map { abs($0) }.max() ?? 0, r.map { abs($0) }.max() ?? 0)
        }
        func hits(_ e: KnockEngine) -> UInt32 { (0..<Pad.count).reduce(0) { $0 + e.padHits[$1] } }
        var silent: [String] = []
        for preset in PatternBank.all {
            let loops = GrooveGenerator.loops(fromMain: preset.pattern, style: preset.grooveStyle, seed: PatternPreset.seed(preset.name))
            for loop in loops where !loop.events.contains(where: { $0.velocity >= 0.3 && (0..<Pad.count).contains(Int($0.pad)) }) {
                silent.append("\(preset.name) \(loop.name) (no notes)")
            }
            let e = KnockEngine()
            e.prepare(sampleRate: 48_000, maxFrames: 512)
            e.setParam(.followDAW, 0)
            e.setTempo(preset.bpm)
            e.kitHandoff.publish(kit)
            e.patternHandoff.publish(PatternSet(loops))
            for (i, loop) in loops.enumerated() {
                let blocks = Int(Double(loop.lengthTicks) / Double(PatternData.ppq) * 60 / preset.bpm * 48_000 / 512) + 2
                e.send(KEvent(kind: .allOff))
                _ = block(e)
                let before = hits(e)
                e.send(KEvent(kind: .play, value: Double(i + 1)))
                var hit = false, loud: Float = 0
                for _ in 0..<blocks {
                    loud = max(loud, block(e))
                    if hits(e) > before && (i > 0 || loud > 0.01) { hit = true; break }
                }
                if !hit { silent.append("\(preset.name) \(loop.name)") }
            }
            e.send(KEvent(kind: .allOff))
        }
        check(silent.isEmpty, "every preset pattern plays in every loop (silent: \(silent.prefix(12).joined(separator: ", ")))")
        // A new pattern opens on its MAIN A, whatever part of the last one was on screen.
        if let preset = PatternBank.preset(named: "BREAKS 1 AMEN STYLE") {
            let loops = GrooveGenerator.loops(fromMain: preset.pattern, style: preset.grooveStyle, seed: 1)
            check(loops[LoopSlot.intro.rawValue].events.contains { Int($0.pad) == Pad.kick.rawValue || Int($0.pad) == Pad.cymbal.rawValue },
                  "a pattern with no hats still has an INTRO")
        }
    }

    static func checkTextureControls() {
        let kit = kitBuffers(KitLibrary.modernTrap)
        for parameter in [KParam.resample, .instability, .textureDelay, .gatedReverb, .drive] {
            let (a, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 120, seconds: 1) { $0.setParam(parameter, 0) }
            let (b, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 120, seconds: 1) { $0.setParam(parameter, 1) }
            var difference: Double = 0
            for i in a.indices { difference += Double(abs(a[i] - b[i])) }
            check(difference > 0.1, "\(parameter.name) changes texture output")
            check(b.allSatisfy { $0.isFinite && abs($0) <= MasterBus.ceiling + 0.001 }, "\(parameter.name) stays finite and clipped")
        }
        // Face 2's Texture knobs (Oct 17): WARP, GLITCH, reverb DECAY / PRE-DELAY and DELAY's tempo lock each change the sound.
        for parameter in [KParam.warp, .glitch, .reverbDecay, .reverbPredelay, .delaySync] {
            let (a, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 90, seconds: 3) { $0.setParam(.textureDelay, 0.8); $0.setParam(.gatedReverb, 0.8); $0.setParam(parameter, 0) }
            let (b, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 90, seconds: 3) { $0.setParam(.textureDelay, 0.8); $0.setParam(.gatedReverb, 0.8); $0.setParam(parameter, 1) }
            var difference: Double = 0
            for i in a.indices { difference += Double(abs(a[i] - b[i])) }
            check(difference > 0.1, "\(parameter.name) changes texture output")
            check(b.allSatisfy { $0.isFinite && abs($0) <= MasterBus.ceiling + 0.001 }, "\(parameter.name) stays finite and clipped")
        }
        // WARP moves the sound bar to bar but stays in level.
        let (warped, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 120, seconds: 8) { $0.setParam(.warp, 1); $0.setParam(.glitch, 1) }
        check(warped.allSatisfy { $0.isFinite && abs($0) <= MasterBus.ceiling + 0.001 }, "WARP stays finite and clipped")
        check(warped[(warped.count - 48_000)...].contains { abs($0) > 0.01 }, "WARP keeps sounding over many scenes")
    }

    /// Turning a channel's LEVEL or PAN while its sound rings: the note keeps playing and glides to
    /// the new level, it isn't cut off (each cut was a click).
    static func checkLevelPanGlide() {
        // Every volume goes to 200%, +12 dB (Tyrone, Oct 18): track LEVEL / VOL and the master OUTPUT.
        var loud = PadSettings(); loud.level = PadSettings.maxLevel
        check(abs(20 * log10f(loud.gain) - 12) < 0.1 && PadSettings.levelText(loud.level) == "200%" && PadSettings.levelText(0.8) == "100%",
              "a track's volume goes to 200% (+12 dB), 100% is unity")
        check(KnockState.normalizedPads([loud])[0].level == PadSettings.maxLevel && KnockState.normalizedPads([PadSettings()])[0].gain == 1,
              "a saved 200% track volume stays 200%, old projects keep their levels")
        check(abs(KnockMath.outputDB(1) - 12) < 0.01 && abs(KnockMath.outputDB(0.75)) < 0.01, "OUTPUT goes to +12 dB, 0.75 stays 0 dB")
        let rate = 48_000.0
        let sine = (0..<96_000).map { Float(sin(Double($0) * 2 * Double.pi * 220 / rate)) * 0.1 }
        let sample = SampleBuffer(left: sine, sampleRate: rate)
        let samples = Array(repeating: sample, count: Pad.count)
        let before = Array(repeating: PadSettings(), count: Pad.count)
        var after = before
        after[Pad.kick.rawValue].level = 0.4
        after[Pad.kick.rawValue].pan = 0.8
        let engine = KnockEngine()
        engine.prepare(sampleRate: rate, maxFrames: 512)
        engine.setParam(.playMode, 0); engine.setParam(.followDAW, 0); engine.setParam(.tempoSync, 0)
        engine.setParam(.boost, 0); engine.setParam(.clipper, 0)
        engine.kitHandoff.publish(KitBuffers(name: "GLIDE", samples: samples, settings: before, bassHz: 110))
        engine.send(KEvent(kind: .pad, a: Int32(Pad.kick.rawValue), value: 1))
        let total = 24_576, swapAt = 8_192
        var left = [Float](repeating: 0, count: total), right = left
        var done = 0
        while done < total {
            if done == swapAt {
                engine.kitHandoff.publish(KitBuffers(name: "GLIDE", samples: samples, settings: after, bassHz: 110))
            }
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    engine.render(frames: 128, left: l.baseAddress! + done, right: r.baseAddress! + done, host: nil)
                }
            }
            done += 128
        }
        func peak(_ x: [Float], _ range: Range<Int>) -> Float { x[range].map { abs($0) }.max() ?? 0 }
        let start = peak(left, (swapAt - 1_024)..<swapAt)
        let justAfter = peak(left, swapAt..<(swapAt + 128))
        let endL = peak(left, (total - 2_048)..<total), endR = peak(right, (total - 2_048)..<total)
        var biggestStep: Float = 0
        for i in 1..<total { biggestStep = max(biggestStep, abs(left[i] - left[i - 1]), abs(right[i] - right[i - 1])) }
        check(start > 0.05, "glide test note sounds (\(start))")
        check(justAfter > start * 0.6, "changing level keeps the ringing note (\(justAfter) vs \(start))")
        check(endL > 0.005 && endL < start * 0.5, "the ringing note glides down to the new level (\(endL))")
        check(endR > endL * 2, "the ringing note glides to the new pan (L \(endL), R \(endR))")
        check(biggestStep < start * 0.08, "level and pan move without a step (\(biggestStep))")
    }

}
