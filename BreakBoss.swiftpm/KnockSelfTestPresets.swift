// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import AVFoundation
import UIKit

// MARK: - Self-test: Factory presets, CPU, sample edits, patterns, Texture, FX sections, glides and octaves

extension KnockSelfTest {
    static func checkFactoryPresetsAndKitIndependence() {
        let presets = PatternBank.all
        check(presets.count >= 150 && Set(presets.map { $0.name }).count == presets.count, "pattern bank loads with unique names (\(presets.count))")
        let wanted = ["Neo Soul", "Dilla Time", "Boom Bap", "90s Rap", "70s Soul", "80s Breaks", "Rock", "Trap", "Alt Trap",
                      "Drill", "UK Drill", "NY Drill", "Detroit 2026", "West Coast", "RnB", "90s RnB", "UK RnB"]
        let learnedStyles = ["BK Editions Vol 1", "BK Editions Vol 2", "BK Editions Vol 3", "BK Editions Vol 4"]
        // Oct 24: Tyrone's genre list, after the BK Editions so older presets keep their AUv3 preset numbers
        let added = ["Trapsoul", "Dark Trap", "Phonk", "ATL Trap", "Memphis", "Toronto R&B", "Vintage R&B", "2000s R&B", "Live Soul",
                     "East Coast", "Lo-fi", "Afrobeats", "Bouncy", "80s Pop", "Live Pop", "Dark Experimental", "World & Latin"]
        check(PatternBank.styles == wanted + learnedStyles + added + ["Bay Area"] && presets.filter { !learnedStyles.contains($0.style) }.count == 1750,
              "1750 presets: the 17 research styles in the genre guide's order, BK Editions Vol 1 to 4, Tyrone's 17 Oct 24 genres, then Bay Area")
        // Oct 28 (Tyrone: "each pattern bank should have a total of atleast 20 different patterns"): presets 11 to 20 of
        // every genre come after every older preset, Bay Area included, so no AUv3 factory preset number moves
        // Later on Oct 28 ("lets total each pattern category to 50 patterns per category"): presets 21 to 50 after those
        func number(_ p: PatternPreset) -> Int { p.name.split(separator: " ").compactMap { Int($0) }.first { $0 < 100 } ?? 0 }   // DETROIT 2026 11: the 11
        let newer = presets.dropLast(1020).suffix(330), newest = presets.suffix(1020)
        check(newer.allSatisfy { (11...20).contains(number($0)) && $0.style != "Bay Area" && !learnedStyles.contains($0.style) } &&
              newest.allSatisfy { (21...50).contains(number($0)) && $0.style != "Bay Area" && !learnedStyles.contains($0.style) } &&
              presets.dropLast(1350).suffix(50).allSatisfy { $0.style == "Bay Area" },
              "every genre's presets 11 to 20, then 21 to 50, come after Bay Area, so older presets keep their AUv3 numbers")
        let walk: [PatternPreset] = PatternBank.browserOrder
        let walkStyles: [String] = walk.map(\.style)
        var turns = 0
        for i in walk.indices.dropFirst() where walkStyles[i] != walkStyles[i - 1] { turns += 1 }
        let sameOrder = PatternBank.styles.allSatisfy { st in walk.filter { $0.style == st }.map(\.name) == PatternBank.presets(in: st).map(\.name) }
        check(walk.count == presets.count && sameOrder && turns == PatternBank.styles.count - 1,
              "the pattern arrows walk the PATTERNS menu: each genre's folder in turn, 1 to 50")
        // Bay Area (Oct 25): 50 grooves learned from Tyrone's Bay Area loops, last so older presets keep their AUv3 numbers
        let bay = PatternBank.presets(in: "Bay Area")
        check(bay.count == 50 && bay.allSatisfy { $0.pattern.bars == 4 && $0.grooveStyle == .westBounce && $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } } &&
              PatternBank.all.dropLast(1350).suffix(50).allSatisfy { $0.style == "Bay Area" },
              "Bay Area: 50 presets learned from Tyrone's Bay Area loops, 4 bars, each with its kick, after every older preset")
        for style in added + wanted { check(PatternBank.presets(in: style).count == 50, "\(style): 50 presets") }
        // West Coast (Oct 20): 20 grooves from Tyrone's West Coast loops in place of the 10 Bay Area 2026 presets;
        // a save made with a Bay Area preset keeps its notes and randomizes in West Coast. Oct 28: 30 more built from them (21 to 50).
        let west = PatternBank.presets(in: "West Coast")
        check(west.count == 50 && west.allSatisfy { $0.pattern.bars == 4 && $0.grooveStyle == .westBounce && $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } } &&
              PatternRandomizer.style(for: "BAY AREA 1 SLAP") == "West Coast",
              "West Coast: 20 presets learned from Tyrone's West Coast loops and 30 built from them, 4 bars, each with its kick; old Bay Area saves randomize as West Coast")
        let westKits = KitLibrary.factory.dropLast(50).suffix(20)
        check(westKits.allSatisfy { $0.family == "WEST COAST" && $0.preferredMode == .modern }, "20 West Coast kits in the Modern bank's WEST COAST tab")
        // Tyrone, Oct 20: each holds only the sounds its loop plays (the pads its preset plays), the rest EMPTY
        let stock = StockSampleLibrary.bundled
        check(zip(westKits, west).allSatisfy { kit, preset in
            let played = Set(preset.pattern.events.map { Int($0.pad) })
            return Pad.allCases.allSatisfy { pad in
                played.contains(pad.rawValue) ? stock.sample(kitID: kit.id, pad: pad.rawValue) != nil : stock.isEmpty(kitID: kit.id, pad: pad.rawValue)
            }
        }, "West Coast kits: a sound on each pad its preset plays, every other pad EMPTY")
        // Bay Area (Oct 25, Tyrone picked "Patterns + 50 matching kits"): kit n plays only Bay Area preset n's pads,
        // plus (Oct 27, Tyrone) the Go2Spinz 808 on every kit's 808 pad
        let bayKits = KitLibrary.factory.suffix(50)
        check(bayKits.allSatisfy { $0.family == "WEST COAST" && $0.genre == "BAY AREA" && $0.preferredMode == .modern } &&
              zip(bayKits, bay).allSatisfy { kit, preset in
            let played = Set(preset.pattern.events.map { Int($0.pad) }).union([Pad.bass808.rawValue])
            return Pad.allCases.allSatisfy { pad in
                played.contains(pad.rawValue) ? stock.sample(kitID: kit.id, pad: pad.rawValue) != nil : stock.isEmpty(kitID: kit.id, pad: pad.rawValue)
            } && stock.sample(kitID: kit.id, pad: Pad.bass808.rawValue)?.url.lastPathComponent == "bb_808_d1_08.wav"
        }, "50 Bay Area kits in the WEST COAST tab: a sound on each pad its preset plays and the Go2Spinz 808 on the 808 pad, every other pad EMPTY")
        let learned = PatternBank.presets(in: "BK Editions Vol 1")
        check(learned.count >= 19 && learned.allSatisfy { [4, 8].contains($0.pattern.bars) && $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } },
              "BK Editions Vol 1: the grooves learned from Tyrone's loops, 4 or 8 bars, each with its kick (\(learned.count))")
        let rnb = PatternBank.presets(in: "BK Editions Vol 2")
        check(rnb.count >= 10 && rnb.allSatisfy { [4, 8].contains($0.pattern.bars) && $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } && $0.grooveStyle == .rnb },
              "BK Editions Vol 2: Tyrone's R&B loops, 4 or 8 bars, each with its kick, R&B fills (\(rnb.count))")
        let vol3 = PatternBank.presets(in: "BK Editions Vol 3")
        check(vol3.count == 20 && vol3.allSatisfy { [1, 2, 4, 8].contains($0.pattern.bars) && $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } },
              "BK Editions Vol 3: 20 grooves from Tyrone's Drum Loops, 1 to 8 bars, each with its kick (\(vol3.count))")
        let vol4 = PatternBank.presets(in: "BK Editions Vol 4")
        check(vol4.count == 5 && vol4.allSatisfy { $0.pattern.bars == 4 && $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } && $0.grooveStyle == .westBounce },
              "BK Editions Vol 4: Tyrone's 5 danger drum loops, 4 bars, each with its kick (\(vol4.count))")
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
        let expectedPads = Array(repeating: PadSettings(), count: Pad.count)
        check(changedKit.kitID == otherKit.id && changedKit.kitName == otherKit.name &&
              changedKit.userKit == nil, "switching kits replaces the drum sounds")
        check(changedKit.values == source.values && changedKit.mode == source.mode &&
              changedKit.playMode == source.playMode && changedKit.presetName == source.presetName,
              "switching kits preserves active mode, FX knobs, clipper, transport and preset identity")
        check(changedKit.pads == expectedPads, "switching kits brings every pad in as the kit's own sound: original pitch, level, centered, sampler untouched")
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
    /// How hard the audio thread works at a 128-frame buffer (Tyrone, Oct 20: "like 1% CPU at 128"):
    /// a busy pattern plays in each mode for 20 s of audio, rendered in 128-frame blocks as the
    /// audio thread would, timed against real time. Printed for the record; the check only catches
    /// a gross slowdown (the simulator's core is shared and noisier than an iPad's).
    static func checkAudioCPU() {
        guard let preset = PatternBank.all.max(by: { $0.pattern.events.count < $1.pattern.events.count }) else { return }
        let kit = kitBuffers(KitLibrary.drumMastery)
        let loops = GrooveGenerator.loops(fromMain: preset.pattern, style: preset.grooveStyle, seed: PatternPreset.seed(preset.name))
        var l = [Float](repeating: 0, count: 128), r = l
        var report: [String] = []
        for mode in SoundMode.allCases {
            let e = KnockEngine()
            e.prepare(sampleRate: 48_000, maxFrames: 128)
            e.setParam(.followDAW, 0)
            e.setParam(.soundMode, Float(mode.rawValue))
            e.setTempo(preset.bpm)
            e.kitHandoff.publish(kit)
            e.patternHandoff.publish(PatternSet(loops))
            e.send(KEvent(kind: .play, value: Double(LoopSlot.mainA.rawValue + 1)))
            func run(_ blocks: Int) {
                for _ in 0..<blocks {
                    l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                        e.render(frames: 128, left: lp.baseAddress!, right: rp.baseAddress!, host: nil) } }
                }
            }
            run(375)   // 1 s to settle (kit and pattern picked up, voices going)
            let blocks = 7_500   // 20 s of audio
            let started = CFAbsoluteTimeGetCurrent()
            run(blocks)
            let seconds = CFAbsoluteTimeGetCurrent() - started
            let percent = seconds / (Double(blocks) * 128 / 48_000) * 100
            report.append(String(format: "%@ %.2f%%", mode.title, percent))
            check(percent < 25, String(format: "\(mode.title): audio at 128 frames takes %.2f%% of real time (\(preset.name))", percent))
            e.send(KEvent(kind: .allOff))
        }
        log("BreakBoss audio CPU at 128 frames, 48 kHz, \(preset.name): " + report.joined(separator: ", "))
    }

    /// The SAMPLER's edit bar (Tyrone, Oct 20: every tool above the waveform works): cut / delete take
    /// the selection out, copy + paste (insert, replace, mix into what's there) put it back, trim cuts
    /// the silence at the ends, fade in / out shape only the selection. Worked on a ramp so every frame
    /// can be told apart.
    static func checkSampleEdits() {
        let n = 1_000
        let ramp = (0..<n).map { Float($0) / Float(n) * 0.5 }
        let sound = SampleBuffer(left: ramp, right: ramp.map { -$0 }, sampleRate: 48_000)
        let sel = 200..<400
        let clip = SampleEditor.clip(sound, sel)
        check(clip.count == 200 && clip.left.first == ramp[200] && clip.right.last == -ramp[399], "COPY takes exactly the selection")
        let cut = SampleEditor.apply(.delete(sel), to: sound)
        check(cut.left.count == 800 && cut.left[199] == ramp[199] && cut.left[200] == ramp[400], "CUT / DELETE take out exactly the selection")
        check(cut.map(0.1) == 0.125 && cut.map(0.3) == nil, "CUT moves the points after it and drops the ones inside")
        let inserted = SampleEditor.apply(.insert(clip, at: 0), to: sound)
        check(inserted.left.count == 1_200 && inserted.left[0] == ramp[200] && inserted.left[200] == ramp[0], "PASTE insert puts the clip in and keeps everything")
        let replaced = SampleEditor.apply(.replace(clip, over: 600..<700), to: sound)
        check(replaced.left.count == 1_100 && replaced.left[600] == ramp[200] && replaced.left[800] == ramp[700], "PASTE replace swaps the selection for the clip")
        let mixed = SampleEditor.apply(.mix(clip, at: 500), to: sound)
        check(mixed.left.count == n && abs(mixed.left[500] - (ramp[500] + ramp[200])) < 1e-6 && mixed.left[499] == ramp[499]
              && abs(mixed.right[699] - (-ramp[699] - ramp[399])) < 1e-6 && mixed.left[700] == ramp[700],
              "PASTE mix adds the clip onto what's there, both channels, nothing else touched")
        let longer = SampleEditor.apply(.mix(clip, at: 900), to: sound)
        check(longer.left.count == 1_100 && abs(longer.left[950] - (ramp[950] + ramp[250])) < 1e-6 && longer.left[1_050] == ramp[350],
              "PASTE mix past the end makes the sound longer")
        let fadedIn = SampleEditor.apply(.fadeIn(sel), to: sound)
        check(fadedIn.left[200] == 0 && fadedIn.left[199] == ramp[199] && fadedIn.left[400] == ramp[400]
              && fadedIn.left[300] < ramp[300] && fadedIn.left[300] > 0, "FADE IN rises from silence across the selection only")
        let fadedOut = SampleEditor.apply(.fadeOut(sel), to: sound)
        check(fadedOut.left[200] == ramp[200] && fadedOut.left[399] < ramp[399] * 0.01 && fadedOut.left[400] == ramp[400],
              "FADE OUT falls to silence across the selection only")
        var padded = [Float](repeating: 0, count: 4_800) + ramp.map { $0 + 0.1 } + [Float](repeating: 0, count: 4_800)
        padded[0] = 0
        let quiet = SampleBuffer(left: padded, sampleRate: 48_000)
        let trimmed = SampleEditor.apply(.trimSilence, to: quiet)
        check(trimmed.left.count == n + 96 && trimmed.left[96] == ramp[0] + 0.1, "TRIM cuts the silence at both ends (2 ms kept before the sound)")
    }

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
                let beats: Double = Double(loop.lengthTicks) / Double(PatternData.ppq)
                let seconds: Double = beats * 60 / preset.bpm
                let blocks = Int(seconds * 48_000 / 512) + 2
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
        // DELAY's tempo lock (a double tap) still changes the sound.
        do {
            let (a, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 90, seconds: 3) { $0.setParam(.textureDelay, 0.8); $0.setParam(.gatedReverb, 0.8); $0.setParam(.delaySync, 0) }
            let (b, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 90, seconds: 3) { $0.setParam(.textureDelay, 0.8); $0.setParam(.gatedReverb, 0.8); $0.setParam(.delaySync, 1) }
            var difference: Double = 0
            for i in a.indices { difference += Double(abs(a[i] - b[i])) }
            check(difference > 0.1, "Delay Sync changes texture output")
        }
        // INSTABILITY warps and stutters too (Oct 24): moves the sound bar to bar but stays in level.
        let (warped, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 120, seconds: 8) { $0.setParam(.instability, 1) }
        check(warped.allSatisfy { $0.isFinite && abs($0) <= MasterBus.ceiling + 0.001 }, "INSTABILITY's warp stays finite and clipped")
        check(warped[(warped.count - 48_000)...].contains { abs($0) > 0.01 }, "INSTABILITY's warp keeps sounding over many scenes")
    }

    /// Texture's reverb is a drum plate (Tyrone, Oct 28): bright, dense, smooth tails that don't
    /// muddy the lows, and nothing at all while REVERB is at 0%. Rendered through the main chain.
    static func checkTexturePlate() {
        let rate: Float = 48_000
        // a snare-like hit: a 180 Hz body under a noise burst, plus a 60 Hz thump for the low end
        var rng = KRandom(seed: 0x51A7E)
        let length = Int(rate * 2.5)
        var hit = [Float](repeating: 0, count: length)
        for i in 0..<Int(rate * 0.25) {
            let t = Float(i) / rate
            let body: Float = 0.5 * sinf(2 * Float.pi * 180 * t) * expf(-t * 30)
            let crack: Float = 0.35 * rng.bipolar() * expf(-t * 22)
            let thump: Float = 0.4 * sinf(2 * Float.pi * 60 * t) * expf(-t * 18)
            hit[i] = body + crack + thump
        }
        func run(reverb: Float, decay: Float = 0.5) -> ([Float], [Float]) {
            let bus = BusProcessor()
            bus.prepare(sampleRate: Double(rate))
            var s = BusProcessor.Settings()
            s.mode = .texture; s.reverb = reverb; s.reverbDecay = decay
            var l = hit, r = hit
            var at = 0
            while at < length {
                let n = min(128, length - at)
                l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                    bus.process(lp.baseAddress! + at, rp.baseAddress! + at, count: n, s)
                } }
                at += n
            }
            return (l, r)
        }
        func energy(_ x: [Float], _ from: Float, _ to: Float) -> Double {
            var e: Double = 0
            for i in Int(from * rate)..<min(x.count, Int(to * rate)) { e += Double(x[i] * x[i]) }
            return e
        }
        /// share of a signal's energy under about 100 Hz (two one-poles at 100 Hz)
        func lowShare(_ x: [Float]) -> Double {
            var lp1 = OnePole(), lp2 = OnePole(); lp1.setCutoff(100, sr: rate); lp2.setCutoff(100, sr: rate)
            var low: Double = 0, all: Double = 0
            for v in x { let y = lp2.lowPass(lp1.lowPass(v)); low += Double(y * y); all += Double(v * v) }
            return low / max(all, 1e-12)
        }
        let (dryL, _) = run(reverb: 0)
        let (wetL, wetR) = run(reverb: 1)
        let tail = zip(wetL, dryL).map { $0 - $1 }
        // at 0% REVERB the plate adds nothing
        let (zeroL, _) = run(reverb: 0)
        check(zip(dryL, zeroL).allSatisfy { $0 == $1 } && energy(dryL, 0.6, 2.5) < 1e-9,
              "Texture plate: REVERB at 0% adds nothing, the hit ends dry")
        // a smooth plate tail, not a gate: still ringing a second after the hit and dying away evenly
        let early = energy(tail, 0.25, 0.5), mid = energy(tail, 0.75, 1.0), late = energy(tail, 1.5, 1.75)
        check(mid > early * 0.02 && mid < early && late < mid && late > 0,
              "Texture plate: a smooth tail that rings past a second and fades evenly (\(String(format: "%.3g %.3g %.3g", early, mid, late)))")
        // never mud: the reverb's share of lows well under the dry hit's
        let wetLow = lowShare(tail), dryLow = lowShare(dryL)
        check(wetLow < dryLow * 0.25, "Texture plate: high-passed, no low-end mud (lows \(String(format: "%.3f", wetLow)) vs dry \(String(format: "%.3f", dryLow)))")
        // dense and wide: left and right tails are different
        var lr: Double = 0, ll: Double = 0, rr: Double = 0
        for i in Int(0.3 * rate)..<Int(1.2 * rate) {
            let a = Double(wetL[i] - dryL[i]), b = Double(wetR[i] - dryL[i])
            lr += a * b; ll += a * a; rr += b * b
        }
        let correlation = lr / max(sqrt(ll * rr), 1e-12)
        check(abs(correlation) < 0.6, "Texture plate: a wide stereo tail (L/R correlation \(String(format: "%.2f", correlation)))")
        // DECAY lengthens it; everything stays finite and in level
        let (longL, _) = run(reverb: 1, decay: 1)
        check(energy(longL, 1.5, 2.5) > energy(wetL, 1.5, 2.5), "Texture plate: a longer DECAY rings longer")
        check((wetL + wetR + longL).allSatisfy { $0.isFinite && abs($0) < 4 }, "Texture plate: stays finite")
    }

    /// Each mode's FX section (Tyrone, Oct 24): Face 1's bottom row and Face 2's rail show the mode's
    /// own seven knobs, in his order; every one of them changes the sound, and a knob outside the
    /// mode's section (left turned in another mode) changes nothing, so the labels match the sound.
    static func checkFXSections() {
        check(TrackFX.params(.vintage) == [.drive, .punch, .analogEQ, .grit, .shine, .tighten, .noise]
              && TrackFX.params(.texture) == [.drive, .resample, .instability, .textureDelay, .shine, .gatedReverb, .noise]
              && TrackFX.params(.modern) == [.boost, .punch, .analogEQ, .tighten, .grit, .shine, .noise],
              "FX sections: Vintage DRIVE PUNCH ANALOG EQ GRIT SHINE TIGHTEN NOISE; Texture DRIVE RESAMPLE INSTABILITY DELAY SHINE REVERB NOISE; Modern unchanged")
        check(SoundMode.allCases.allSatisfy { m in TrackFX.face1Places.map { TrackFX.face1($0, m) } == (m == .modern ? TrackFX.face1Places : TrackFX.params(m)) },
              "FX sections: Face 1's bottom row turns the knobs its plate prints, in order")
        let kit = kitBuffers(KitLibrary.modernTrap)
        func moved(_ mode: SoundMode, _ p: KParam, from v0: Float = 0, to v1: Float = 1) -> Double {
            let base: (KnockEngine) -> Void = { $0.setParam(.textureDelay, 0); $0.setParam(.gatedReverb, 0); $0.setParam(.clipper, 0) }
            let (a, _) = render(kit: kit, style: .trap, mode: mode, tempo: 120, seconds: 1.5) { base($0); $0.setParam(p, v0) }
            let (b, _) = render(kit: kit, style: .trap, mode: mode, tempo: 120, seconds: 1.5) { base($0); $0.setParam(p, v1) }
            var difference: Double = 0
            for i in a.indices { difference += Double(abs(a[i] - b[i])) }
            return difference
        }
        for mode in SoundMode.allCases {
            // two identical renders: how far apart "no change" can be
            let same = moved(mode, .punch, from: 0, to: 0)
            for p in TrackFX.params(mode) {
                let d = moved(mode, p)
                check(d > 0.1, "FX sections \(mode.title): \(p.name) changes the sound (\(String(format: "%.2f", d)))")
            }
            // Oct 26 (Tyrone): only Texture carries reverb and delay; in Modern and Vintage those knobs (and
            // Texture's lo-fi) do nothing even if left turned up.
            let outside = [KParam.boost, .punch, .analogEQ, .grit, .tighten, .drive, .warp, .glitch, .reverbDecay, .reverbPredelay,
                           .textureDelay, .gatedReverb, .resample, .instability]
                .filter { !TrackFX.params(mode).contains($0) }
            for p in outside {
                let d = moved(mode, p)
                check(d <= same * 1.000_1 + 1e-6, "FX sections \(mode.title): \(p.name), not in this mode's section, leaves the sound alone (\(d))")
            }
        }
        // Tyrone, Oct 26: every FX knob (CLIP DRIVE too) loads at 0% and each mode keeps its own sound there.
        let fxKnobs = Set(SoundMode.allCases.flatMap { TrackFX.params($0) } + [.clipDrive, .warp, .glitch])
        check(fxKnobs.allSatisfy { $0.defaultValue == 0 }, "FX knobs: every mode's FX knobs and CLIP DRIVE start at 0%")
        func difference(_ a: [Float], _ b: [Float]) -> Double { zip(a, b).reduce(0) { $0 + Double(abs($1.0 - $1.1)) } }
        // Oct 26 (Tyrone): Modern and Vintage are dry at 0% (Vintage's tape rides on DRIVE, it used to lift
        // every room tail like a reverb). Oct 28 (Tyrone): Texture too, its effects come only from its knobs.
        let (modernZero, _) = render(kit: kit, style: .trap, mode: .modern, tempo: 120, seconds: 1.5)
        let (vintageZero, _) = render(kit: kit, style: .trap, mode: .vintage, tempo: 120, seconds: 1.5)
        let (textureZero, _) = render(kit: kit, style: .trap, mode: .texture, tempo: 120, seconds: 1.5)
        let (modernAgain, _) = render(kit: kit, style: .trap, mode: .modern, tempo: 120, seconds: 1.5)
        let vd = difference(vintageZero, modernZero), td = difference(textureZero, modernZero)
        let same = difference(modernAgain, modernZero)
        check(vd <= same * 1.000_1 + 1e-3, "FX knobs at 0%: Vintage is dry like Modern, no built-in tape or room lift (\(String(format: "%.4f", vd)))")
        check(td <= same * 1.000_1 + 1e-3, "FX knobs at 0%: Texture is dry like Modern, nothing built in plays on its own (\(String(format: "%.4f", td)))")
        let (vintageDrive, _) = render(kit: kit, style: .trap, mode: .vintage, tempo: 120, seconds: 1.5) { $0.setParam(.drive, 1) }
        check(difference(vintageDrive, vintageZero) > 0.1, "Vintage DRIVE brings the tape in")
        var old = KnockState(); old.version = 3
        old.values = [KParam.boost.id: 0.42, KParam.clipDrive.id: 0.25, KParam.textureDelay.id: 0.32, KParam.resample.id: 0.75,
                      KParam.instability.id: 0.5, KParam.grit.id: 0.3]
        let migrated = old.normalized().values
        check(migrated[KParam.boost.id] == 0 && migrated[KParam.clipDrive.id] == 0 && migrated[KParam.textureDelay.id] == 0
              && migrated[KParam.instability.id] == 0 && abs((migrated[KParam.resample.id] ?? 0) - 0.5) < 0.001 && migrated[KParam.grit.id] == 0.3,
              "FX knobs: an old project's untouched knobs come back at 0%, turned ones keep their sound")
    }

    /// Turning a channel's LEVEL or PAN while its sound rings: the note keeps playing and glides to
    /// the new level, it isn't cut off (each cut was a click).
    static func checkLevelPanGlide() {
        // Tyrone, Oct 19: every volume outside the SAMPLER window stops at 100% (0 dB), down to −12 dB (50%)
        var loud = PadSettings(); loud.level = 1.6
        check(KnockState.normalizedPads([loud])[0].level == 0.8 && KnockState.normalizedPads([PadSettings()])[0].gain == 1
              && PadSettings.levelText(PadSettings.maxLevel) == "100%",
              "a track's volume stops at 100%: a saved 200% comes back at 100%")
        check(abs(KnockMath.outputDB(1)) < 0.01 && abs(KnockMath.outputDB(0) + 12) < 0.01 && KParam.output.defaultValue == 1
              && abs(KnockMath.outputFromOld(0.75) - 1) < 0.001 && abs(KnockMath.outputFromOld(1) - 1) < 0.001
              && abs(KnockMath.outputDB(KnockMath.outputFromOld(0.375)) + 6) < 0.01,
              "OUTPUT goes from −12 dB to 0 dB; an old project's OUTPUT keeps its level, anything over 0 dB stops at 0 dB")
        // Tyrone, Oct 31: "output volume should always be max at 10 for every preset"
        let outEngine = KnockEngine(); outEngine.prepare(sampleRate: 48_000, maxFrames: 512)
        var atMax = false
        let outputCheck = {
            let outRC = KnockController(engine: outEngine, isPlugin: true)
            atMax = outRC.value(.output) == 1
            outRC.set(.output, 0.3); if let preset = PatternBank.all.first { outRC.loadPatternPreset(preset) }
            atMax = atMax && outRC.value(.output) == 1
            outRC.set(.output, 0.3); if let kit = KitLibrary.factory.dropFirst().first { outRC.selectKit(kit) }
            atMax = atMax && outRC.value(.output) == 1
            outRC.set(.output, 0.3); outRC.selectMode(.texture)
            atMax = atMax && outRC.value(.output) == 1
            var lowState = outRC.state; lowState.values[KParam.output.id] = 0.2
            outRC.restore(lowState)
            atMax = atMax && outRC.value(.output) == 1 && abs(KnockMath.outputDB(outRC.value(.output))) < 0.01
            outRC.selectMode(.modern)
        }
        if Thread.isMainThread { outputCheck() } else { DispatchQueue.main.sync(execute: outputCheck) }
        check(atMax, "OUTPUT is at max (0 dB, knob at the top) at launch and after every preset, kit, mode and saved song")
        var old = KnockState(); old.version = 2; old.values[KParam.output.id] = 0.375
        let migrated = old.normalized()
        check(abs(KnockMath.outputDB(migrated.values[KParam.output.id] ?? 0) + 6) < 0.01 && migrated.normalized() == migrated,
              "an old project's OUTPUT is moved to the new scale once")
        var low = PadSettings(); low.level = PadSettings.level(knob: 0)
        check(abs(20 * log10f(low.gain) + 12) < 0.1 && PadSettings.level(knob: 1) == 0.8
              && abs(PadSettings.knob(level: 0.8) - 1) < 0.001 && PadSettings.levelText(low.level) == "50%",
              "the volume knobs go from −12 dB (50%) to 0 dB (100%) at the top")
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

    /// The piano roll reaches C1 to C8 and ⊕ / ⊖ move notes by octaves (Tyrone, Oct 18).
    static func checkPianoRollOctaves() {
        check(MusicScale.noteName(MusicScale.lowestNote) == "C1" && MusicScale.noteName(MusicScale.highestNote) == "C8", "piano roll: keys C1 to C8")
        // a drum counts from C4 (60): C1 is 36 below, C8 48 above
        let drum = { (_: Int) in (MusicScale.lowestNote - 60)...(MusicScale.highestNote - 60) }
        var p = PatternData(name: "OCT", lengthTicks: PatternEdit.barTicks, events: [])
        p = PatternEdit.addNote(p, pad: Pad.kick.rawValue, tick: 0, velocity: 0.9)
        var key = NoteKey(p.events[0])
        var semis: [Int] = []
        while let up = PatternEdit.transpose(p, [key], by: 12, limits: drum) { p = up.0; key = up.1.first!; semis.append(Int(key.semis)) }
        check(semis == [12, 24, 36, 48], "piano roll: ⊕ takes a C4 drum note up to C8 and no further (\(semis))")
        semis = []
        while let down = PatternEdit.transpose(p, [key], by: -12, limits: drum) { p = down.0; key = down.1.first!; semis.append(Int(key.semis)) }
        check(semis == [36, 24, 12, 0, -12, -24, -36], "piano roll: ⊖ takes it down to C1 and no further (\(semis))")
        var two = PatternData(name: "OCT", lengthTicks: PatternEdit.barTicks, events: [])
        two = PatternEdit.addNote(two, pad: Pad.kick.rawValue, tick: 0, velocity: 0.9)
        two = PatternEdit.addNote(two, pad: Pad.kick.rawValue, tick: 96, velocity: 0.9, semis: 44)
        check(PatternEdit.transpose(two, Set(two.events.map(NoteKey.init)), by: 12, limits: drum) == nil,
              "piano roll: a selection that can't all go up an octave stays put (keeps its intervals)")
        check(PatternEdit.addNote(two, pad: Pad.kick.rawValue, tick: 192, velocity: 0.9, semis: 48).events.contains { $0.semis == 48 },
              "piano roll: a note drawn at C8 keeps its pitch")
        var saved = KnockState()
        saved.editedLoops = Array(repeating: nil, count: Pad.count)
        saved.editedLoops[0] = PatternData(name: "HIGH", lengthTicks: 384, events: [GrooveEvent(tick: 0, pad: Int8(Pad.kick.rawValue), velocity: 0.9, semis: 48),
                                                                                  GrooveEvent(tick: 24, pad: Int8(Pad.kick.rawValue), velocity: 0.9, semis: -36)])
        check(saved.normalized().editedLoops[0]?.events.map(\.semis) == [48, -36], "piano roll: C8 and C1 notes survive saving")

        // the engine plays them at those pitches: a 220 Hz tone three octaves up and down
        let rate = 48_000.0
        let sine = (0..<96_000).map { Float(sin(Double($0) * 2 * Double.pi * 220 / rate)) * 0.2 }
        let samples = Array(repeating: SampleBuffer(left: sine, sampleRate: rate), count: Pad.count)
        func crossings(semis: Int, frames: Int) -> Int {
            let engine = KnockEngine()
            engine.prepare(sampleRate: rate, maxFrames: 512)
            engine.setParam(.playMode, 0); engine.setParam(.followDAW, 0); engine.setParam(.tempoSync, 0)
            engine.setParam(.boost, 0); engine.setParam(.clipper, 0)
            engine.kitHandoff.publish(KitBuffers(name: "OCT", samples: samples, settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: 110))
            engine.send(KEvent(kind: .padPitched, a: Int32(Pad.kick.rawValue + 128 * (semis + 64)), value: 1))
            var left = [Float](repeating: 0, count: frames), right = left
            var done = 0
            while done < frames {
                left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in
                    engine.render(frames: 128, left: l.baseAddress! + done, right: r.baseAddress! + done, host: nil) } }
                done += 128
            }
            // skip the attack, count sign changes of the steady tone
            var n = 0
            for i in 1_025..<frames {
                let a: Float = left[i - 1], b: Float = left[i]
                if (a < 0) != (b < 0) && abs(a - b) > 1e-6 { n += 1 }
            }
            return n
        }
        // up: 8 192 frames (the tone, 8x faster, lasts 12 000); down: 32 768 frames for enough 27.5 Hz cycles
        let base = crossings(semis: 0, frames: 9_216), high = crossings(semis: 36, frames: 9_216)
        let longBase = crossings(semis: 0, frames: 33_792), low = crossings(semis: -36, frames: 33_792)
        let upRatio = Double(high) / Double(max(base, 1)), downRatio = Double(low) / Double(max(longBase, 1))
        check(base > 50 && abs(upRatio - 8) < 0.8, "piano roll: a note three octaves up plays 8x the pitch (\(base) -> \(high) crossings)")
        check(abs(downRatio - 0.125) < 0.03, "piano roll: a note three octaves down plays 1/8 the pitch (\(longBase) -> \(low) crossings)")
    }
}
