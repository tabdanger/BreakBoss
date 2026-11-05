// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import AVFoundation
import UIKit

// MARK: - Self-test: Recording, audio formats, workspace channels, menus, drum roll, feel and migration

extension KnockSelfTest {
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

    /// Every kind of audio file loads (Tyrone, Oct 27: "BK needs to be able to accept ALL audio file type"),
    /// and a file that really isn't audio is named as it is on the iPad.
    static func checkAudioFormats() {
        #if canImport(AVFoundation)
        check(["wav", "AIFF", "aif", "caf", "mp3", "m4a", "aac", "flac", "ogg", "opus", "w64"].allSatisfy { AudioFormats.isAudio(ext: $0) }
              && !AudioFormats.isAudio(ext: "txt") && !AudioFormats.isAudio(ext: ""), "audio files: every audio extension is taken in")
        let tmp = FileManager.default.temporaryDirectory
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410)!
        tone.frameLength = 4_410
        for c in 0..<2 { for i in 0..<4_410 { tone.floatChannelData![c][i] = 0.5 * sinf(Float(i) * 0.06) } }
        // name, settings, must it load (the encoders for compressed kinds may be missing on a simulator)
        func lpcm(_ bits: Int, float: Bool = false, big: Bool = false) -> [String: Any] {
            var d: [String: Any] = [:]
            d[AVFormatIDKey] = kAudioFormatLinearPCM
            d[AVLinearPCMBitDepthKey] = bits
            d[AVLinearPCMIsFloatKey] = float
            d[AVLinearPCMIsBigEndianKey] = big
            return d
        }
        func coded(_ id: AudioFormatID) -> [String: Any] {
            var d: [String: Any] = [:]
            d[AVFormatIDKey] = id
            if id == kAudioFormatAppleLossless { d[AVEncoderBitDepthHintKey] = 16 }
            return d
        }
        var pcm: [(String, [String: Any], Bool)] = []
        pcm.append(("8bit.wav", lpcm(8), false))
        pcm.append(("16bit.wav", lpcm(16), true))
        pcm.append(("24bit.wav", lpcm(24), true))
        pcm.append(("float.wav", lpcm(32, float: true), true))
        pcm.append(("bigendian.aiff", lpcm(16, big: true), true))
        pcm.append(("24bit.caf", lpcm(24), true))
        pcm.append(("aac.m4a", coded(kAudioFormatMPEG4AAC), false))
        pcm.append(("alac.m4a", coded(kAudioFormatAppleLossless), false))
        pcm.append(("lossless.flac", coded(kAudioFormatFLAC), false))
        for (name, extra, required) in pcm {
            let url = tmp.appendingPathComponent("selftest format " + name)
            try? FileManager.default.removeItem(at: url)
            var settings = extra
            settings[AVSampleRateKey] = 44_100
            settings[AVNumberOfChannelsKey] = 2
            let written: Bool = {
                guard let w = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) else { return false }
                return (try? w.write(from: tone)) != nil
            }()
            // the simulator's FLAC encoder can write a file even Apple's reader can't open: that's the test file, not the loader
            let readable = required || (try? AVAudioFile(forReading: url)).map { $0.length > 1_000 } ?? false
            if !written || !readable { check(!required, "audio files: \(name) could be written for the test"); continue }
            let loaded = try? SampleLoader.load(url)
            check(loaded.map { $0.length > 1_000 && $0.sampleRate > 0 } ?? false, "audio files: \(name) loads")
            try? FileManager.default.removeItem(at: url)
        }
        // WAVs the iPad's reader may turn down: data size 0 (a recorder that stopped early), µ-law
        func wav(_ tag: UInt16, bits: UInt16, dataSize: UInt32, body: [UInt8]) -> Data {
            func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)] }
            func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
            let align = bits / 8
            var d: [UInt8] = Array("RIFF".utf8) + le32(0) + Array("WAVE".utf8)
            d += Array("fmt ".utf8) + le32(16) + le16(tag) + le16(1) + le32(48_000) + le32(48_000 * UInt32(align)) + le16(align) + le16(bits)
            d += Array("data".utf8) + le32(dataSize) + body
            return Data(d)
        }
        var pcm24: [UInt8] = []
        for i in 0..<4_800 {
            let v = Int32(4_000_000 * sinf(Float(i) * 0.06))
            pcm24 += [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v >> 16)]
        }
        let ulaw = (0..<4_800).map { UInt8(truncatingIfNeeded: $0 & 0x7F) }
        for (name, data) in [("no data size.wav", wav(1, bits: 24, dataSize: 0, body: pcm24)),
                             ("mulaw.wav", wav(7, bits: 8, dataSize: UInt32(ulaw.count), body: ulaw))] {
            let url = tmp.appendingPathComponent("selftest format " + name)
            try? data.write(to: url)
            let loaded = try? SampleLoader.load(url)
            check(loaded?.length == 4_800, "audio files: \(name) loads (\(loaded?.length ?? 0) frames)")
            try? FileManager.default.removeItem(at: url)
        }
        let junk = tmp.appendingPathComponent("selftest not audio.wav")
        try? Data("this is not a sound".utf8).write(to: junk)
        do {
            _ = try SampleLoader.load(junk)
            check(false, "audio files: a file that isn't audio is turned down")
        } catch {
            check(error.localizedDescription.hasPrefix("selftest not audio.wav "), "audio files: the notice names the file as it is (\(error.localizedDescription))")
        }
        try? FileManager.default.removeItem(at: junk)
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
        let rackNames: [String] = rc.rackChannels.map(\.name)
        let loadOrder: [String] = ["808", "KICK", "CLAP", "SNARE", "HI HATS", "OPEN HAT", "RIM", "LOW TOM", "HIGH TOM"]
        check(rc.rackChannels.map(\.pad) == Pad.rackOrder && Array(rackNames.prefix(loadOrder.count)) == loadOrder,
              "rack: starts as the kit's 12 channels, 808 first then kick, clap, snare, hats, rim, toms (\(rackNames))")
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
            // The grab studs (Oct 19): a track moved from row 1 to row 4 takes its steps, mute and MIDI
            // channel with it (they belong to its pad), and UNDO's setRackOrder puts the rack back.
            if let preset = PatternBank.all.first(where: { $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } }) {
                rc.loadPatternPreset(preset)
                rc.toggleMute(Pad.kick.rawValue)
                let loopsBefore = rc.loops, mutes = rc.mutedPads, midi = rc.midiOutChannels
                rc.moveRackChannel(pad: Pad.kick.rawValue, to: 3)
                check(rc.rackOrder == [6, 2, 1, 0] + Array(Pad.rackOrder.dropFirst(4)) && rc.rackChannels[3].name == "KICK",
                      "rack: the kick dragged from row 2 to row 4 sits on row 4 (\(rc.rackOrder))")
                check(rc.loops == loopsBefore && rc.mutedPads == mutes && rc.midiOutChannels == midi,
                      "rack: a moved track keeps its steps, its mute and its MIDI channel")
                rc.setRackOrder(Pad.rackOrder)
                check(rc.rackOrder == Pad.rackOrder && rc.state.rackOrder == nil, "rack: UNDO puts the rack order back")
                rc.toggleMute(Pad.kick.rawValue)
            }
            // Face 1 and Face 2 stay in step: every pad is in the rack, a kit fills rack and pads.
            if let preset = PatternBank.all.first(where: { $0.pattern.events.contains { Int($0.pad) == Pad.kick.rawValue } }) {
                rc.removeRackChannel(rc.rackChannels.first { $0.pad == Pad.kick.rawValue }!.id)
                check(!rc.loops.contains { $0.events.contains { Int($0.pad) == Pad.kick.rawValue } },
                      "rack: a deleted channel's notes go from every pattern")
                rc.loadPatternPreset(preset)
                _ = rc.addRackChannel(sound, load: false)
                check(rc.rackChannels.map(\.pad) == Pad.rackOrder, "rack: always all 12 pads, 808 first")
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

    /// The note menu's STEPS (Tyrone, Oct 21; moved from the track menu Oct 23): fills on steps 1, 1+N, 1+2N... across the whole pattern,
    /// hits already on those steps keep their velocity and offset, other tracks untouched.
    static func checkTrackMenuFills(_ p: PatternData, bar: Int32, step: Int32) {
        let hat = Pad.hat.rawValue
        var long = p
        long.lengthTicks = bar * 4
        // a soft, late hit on step 5 (stays for every 1, 2 and 4) and one on step 2 (only every 1 keeps it)
        long.events.append(GrooveEvent(tick: step * 4, pad: Int8(hat), velocity: 0.31, offset: 3))
        long.events.append(GrooveEvent(tick: step, pad: Int8(hat), velocity: 0.44))
        long.sort()
        let others = long.events.filter { Int($0.pad) != hat }
        let total = Int(long.lengthTicks / step)
        for n in [1, 2, 4, 8] {
            let f = PatternEdit.fillKeeping(long, pad: hat, every: step * Int32(n), cell: step, velocity: 0.78)
            let ticks = f.events.filter { Int($0.pad) == hat }.map(\.tick)
            check(ticks == stride(from: 0, to: total, by: n).map { Int32($0) * step },
                  "note menu: Fill Every \(n) puts hits on steps 1, \(1 + n), \(1 + 2 * n)... through all \(total) steps")
            check(f.events.filter { Int($0.pad) != hat } == others, "note menu: Fill Every \(n) leaves the other tracks alone")
            let kept = f.events.first { Int($0.pad) == hat && $0.tick == step * 4 }
            if n <= 4 { check(kept?.velocity == 0.31 && kept?.offset == 3, "note menu: Fill Every \(n) keeps an existing hit's velocity and offset") }
            check(f.events.first { Int($0.pad) == hat && $0.tick == step * 8 }.map { n > 8 || $0.velocity == 0.78 } ?? (n > 8),
                  "note menu: Fill Every \(n) draws new hits at the draw velocity")
        }
        check(!PatternEdit.fillKeeping(long, pad: hat, every: step * 2, cell: step, velocity: 0.78).events.contains { Int($0.pad) == hat && $0.tick == step },
              "note menu: Fill Every 2 drops the track's hits between its steps")
        let cleared = PatternEdit.clearChannel(long, pad: hat)
        check(!cleared.events.contains { Int($0.pad) == hat } && cleared.events.filter { Int($0.pad) != hat } == others,
              "note menu: Clear Steps empties only that track")
    }

    /// The hardware menus stay inside the view they open in, at every edge and at small plug-in sizes.
    static func checkHardwarePanelPlacement() {
        let sizes = [CGSize(width: 1366, height: 1024), CGSize(width: 1180, height: 820), CGSize(width: 700, height: 420), CGSize(width: 420, height: 300)]
        var inside = true, roomy = true
        for b in sizes {
            let fit = BBPanelMetrics.fit(b)
            let panel = CGSize(width: fit.width, height: fit.maxHeight)
            roomy = roomy && fit.maxHeight <= b.height * BBPanelMetrics.heightShare + 0.5 || b.height < 300
            let anchors = [CGRect(x: 0, y: 0, width: 80, height: 40), CGRect(x: b.width - 80, y: 0, width: 80, height: 40),
                           CGRect(x: 0, y: b.height - 40, width: 80, height: 40), CGRect(x: b.width - 80, y: b.height - 40, width: 80, height: 40),
                           CGRect(x: b.width / 2 - 40, y: b.height / 2 - 20, width: 80, height: 40)]
            for a in anchors {
                for placement in [BBPanelPlacement.above, .beside] {
                    let o = BBPanelMetrics.origin(anchor: a, size: panel, bounds: b, placement: placement)
                    let r = CGRect(origin: o, size: panel)
                    if r.minX < BBPanelMetrics.inset - 0.5 || r.minY < BBPanelMetrics.inset - 0.5
                        || r.maxX > b.width - BBPanelMetrics.inset + 0.5 || r.maxY > b.height - BBPanelMetrics.inset + 0.5 { inside = false }
                }
            }
        }
        check(inside, "menus: KITS, PATTERNS and the track menu stay inside the app / plug-in view at every edge and size")
        check(roomy, "menus: a panel takes at most about 68% of the view's height")
        // a bottom-rail control with room above: the panel opens upward, clear of the control
        let rail = CGRect(x: 500, y: 900, width: 200, height: 40)
        let up = BBPanelMetrics.origin(anchor: rail, size: CGSize(width: 340, height: 600), bounds: CGSize(width: 1366, height: 1024), placement: .above)
        check(up.y + 600 <= rail.minY, "menus: KITS and PATTERNS open upward from the bottom rail")
        // a track header with room to its right: the panel sits beside it
        let header = CGRect(x: 300, y: 400, width: 260, height: 52)
        let side = BBPanelMetrics.origin(anchor: header, size: CGSize(width: 340, height: 560), bounds: CGSize(width: 1366, height: 1024), placement: .beside)
        check(side.x >= header.maxX, "menus: the track menu opens beside its track")
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
        checkTrackMenuFills(p, bar: bar, step: step)
        checkHardwarePanelPlacement()
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
        // Each genre's drummer (Tyrone, Oct 26): presets load at their genre's HUMANIZE and play its pocket;
        // the grooves learned from his own loops (BK Editions, West Coast, Bay Area) stay exactly as they were.
        h.humanize = 0.8
        h.genre = "Dilla Time"
        let dilla = PatternSet.humanized(h)
        func mean(_ p: PatternData, _ pick: (GrooveEvent) -> Bool) -> Float {
            let x = p.events.filter(pick).map(\.feel)
            return x.isEmpty ? 0 : x.reduce(0, +) / Float(x.count)
        }
        check(mean(dilla) { $0.pad == snare && $0.velocity > 0.6 } < mean(dilla) { $0.pad == Int8(Pad.kick.rawValue) } - 1,
              "genre feel: Dilla's snare rushes ahead of a dragging kick")
        h.genre = "Trap"
        check(PatternSet.humanized(h).events.allSatisfy { abs($0.feel) < 1 }, "genre feel: trap stays on the grid")
        h.genre = "RnB"
        let rnbFeel = PatternSet.humanized(h)
        check(mean(rnbFeel) { $0.pad == snare && $0.velocity > 0.6 } > mean(rnbFeel) { $0.pad == hat } + 0.8,
              "genre feel: the R&B snare lays back")
        check(["BK Editions Vol 1", "BK Editions Vol 4", "West Coast", "Bay Area"].allSatisfy { group in
                  GenreFeel.of(group) == nil && PatternBank.presets(in: group).allSatisfy { $0.pattern.humanize == nil && $0.pattern.genre == group } },
              "genre feel: the grooves learned from Tyrone's loops load as they were")
        check(PatternBank.presets(in: "Neo Soul").allSatisfy { $0.pattern.humanize == GenreFeel.neoSoul.amount }
              && PatternBank.presets(in: "Trap").allSatisfy { $0.pattern.humanize == GenreFeel.machine.amount },
              "genre feel: a preset loads with its genre's HUMANIZE on the knob")
        check(PatternBank.styles.allSatisfy { GenreFeel.of($0) != nil || $0.hasPrefix("BK Editions") || $0 == "West Coast" || $0 == "Bay Area" },
              "genre feel: every PATTERNS genre has its drummer")
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
        // ONE TRACK: the pattern's kick and snare both go out on channel 1, on their pad notes 36 and 37.
        for p in 0..<Pad.count {
            mo.send(KEvent(kind: .midiOut, a: Int32(p), value: Double(KnockController.oneTrackMIDIOutChannels[p] * 128 + KnockController.defaultMIDIOutNotes[p])))
        }
        for _ in 0..<12 { renderBlock(mo) }
        mo.send(KEvent(kind: .loopPad, a: 0))
        let oneTrack = collect(800)
        check(oneTrack.contains { $0.1 == 0x90 && $0.2 == 36 } && oneTrack.contains { $0.1 == 0x90 && $0.2 == 37 },
              "MIDI out ONE TRACK: kick (36) and snare (37) on channel 1")
        check(oneTrack.allSatisfy { $0.1 & 0x0F == 0 }, "MIDI out ONE TRACK: nothing leaves channel 1")
        mo.send(KEvent(kind: .stop))
        _ = collect(40)
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
        check(KitLibrary.factory.count == 438 && KitLibrary.factory.prefix(42).allSatisfy { $0.name.hasSuffix(" A") || $0.name.hasSuffix(" B") },
              "438 factory kits: the 42 A/B kits, the named ones, the live acoustic ones, BK DRUM KIT, BK EDITIONS KIT, BK DANGER KIT, 20 West Coast kits, 50 Bay Area kits")
        check(Set(KitLibrary.factory.map(\.name)).count == KitLibrary.factory.count, "every factory kit has its own name")
        for mode in SoundMode.allCases {
            for family in KitLibrary.families where !(mode == .vintage && KitLibrary.vintageHiddenFamilies.contains(family)) {
                let n = KitLibrary.kits(for: mode).filter { $0.family == family }.count
                let least = mode == .vintage ? 17 : 20       // Vintage's drum-machine-era kits moved to their own folder (Oct 29)
                check(n >= least, "\(mode.title) kits: \(n) under \(family) (at least \(least))")
            }
        }
        // Vintage is acoustic only (Tyrone, Oct 29): no Vintage trap or West Coast kits in any menu or arrow,
        // and in Vintage mode the KITS menu and arrows hold only the Vintage bank.
        let vintageKits: [KitDefinition] = KitLibrary.browserOrder(for: .vintage)
        let noVintageTrapOrWest: Bool = KitLibrary.browserOrder.allSatisfy { !($0.preferredMode == .vintage && ["TRAP", "WEST COAST"].contains($0.family)) }
        let vintageOwnBank: Bool = vintageKits.allSatisfy { $0.preferredMode == .vintage } && vintageKits.count == KitLibrary.kits(for: .vintage).count
        let othersEveryBank: Bool = KitLibrary.browserOrder(for: .modern).count == KitLibrary.browserOrder.count &&
            KitLibrary.browserOrder(for: .texture).count == KitLibrary.browserOrder.count
        let machineEra: [KitDefinition] = KitLibrary.machineEraKits
        let machineEraOut: Bool = machineEra.count == 8 && !vintageKits.contains { KitLibrary.machineEraGenres.contains($0.genre) } &&
            machineEra.allSatisfy { k in KitLibrary.browserOrder(for: .modern).contains { $0.id == k.id } && KitLibrary.browserOrder(for: .texture).contains { $0.id == k.id } }
        check(machineEraOut, "New Jack Swing, Digital Dancehall, Kwaito, 2000s R&B and 80s Pop kits: out of Vintage, in their own DRUM MACHINE ERA folder in the other modes")
        check(noVintageTrapOrWest && vintageOwnBank && othersEveryBank,
              "Vintage hides its trap and West Coast kits and browses only its acoustic bank; Modern and Texture browse every bank")
        let vintageStyles: [String] = PatternBank.styles(for: .vintage)
        let vintageWalk: [PatternPreset] = PatternBank.browserOrder(for: .vintage)
        let onlyLive: Bool = Set(vintageStyles) == PatternBank.vintageStyles && vintageWalk.allSatisfy { PatternBank.vintageStyles.contains($0.style) } &&
            vintageWalk.count == 50 * PatternBank.vintageStyles.count
        let noElectronic: Bool = !vintageStyles.contains { $0.contains("Trap") || $0.contains("Drill") || $0 == "West Coast" || $0 == "Bay Area" || $0 == "Phonk" || $0 == "80s Pop" }
        let othersEveryStyle: Bool = PatternBank.browserOrder(for: .modern).count == PatternBank.browserOrder.count && PatternBank.styles(for: .texture) == PatternBank.styles
        check(onlyLive && noElectronic && othersEveryStyle,
              "Vintage PATTERNS: only the 13 live-drummer styles (no trap, drill, West Coast or Bay Area); Modern and Texture keep every style")
        check(KitLibrary.kit(id: "trap-a").preferredMode == .modern && KitLibrary.kit(id: "neo-soul-a").preferredMode == .vintage &&
              KitLibrary.kit(id: "amapiano-a").preferredMode == .texture, "the A/B kits stay in their mode banks")
        check(Set(KitLibrary.factory.map { $0.id }).count == KitLibrary.factory.count, "factory kit identifiers unique")
        check(KitLibrary.browserOrder.count == KitLibrary.factory.filter { !KitLibrary.hidden($0) }.count && Set(KitLibrary.browserOrder.map(\.id)).count == KitLibrary.browserOrder.count,
              "the kit arrows step through every shown kit once")
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
}
