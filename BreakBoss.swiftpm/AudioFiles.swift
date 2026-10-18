// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import AVFoundation
import Foundation

// MARK: - Reading your samples

enum SampleLoader {
    enum LoadError: LocalizedError {
        case unreadable(String)
        case tooLong
        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "\(name) isn't an audio file BreaKing can read."
            case .tooLong: return "That sample is longer than 30 seconds."
            }
        }
    }

    /// Decodes any audio file iPadOS can read (WAV, AIFF, CAF, MP3, M4A, FLAC) into a stereo
    /// SampleBuffer at the file's own sample rate. Pads play it back at the right speed.
    static func load(_ url: URL) throws -> SampleBuffer {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw LoadError.unreadable(url.lastPathComponent) }
        let format = file.processingFormat
        guard file.length > 0, file.length <= Int64(UInt32.max), format.sampleRate.isFinite,
              format.sampleRate > 0, format.channelCount > 0,
              file.length <= 16_000_000 / Int64(format.channelCount) else { throw LoadError.unreadable(url.lastPathComponent) }
        guard Double(file.length) / format.sampleRate <= 30 else { throw LoadError.tooLong }
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0 else { throw LoadError.unreadable(url.lastPathComponent) }
        guard Double(frames) / format.sampleRate <= 30 else { throw LoadError.tooLong }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw LoadError.unreadable(url.lastPathComponent)
        }
        do { try file.read(into: buffer) } catch { throw LoadError.unreadable(url.lastPathComponent) }
        guard let data = buffer.floatChannelData else { throw LoadError.unreadable(url.lastPathComponent) }
        let n = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        let left = Array(UnsafeBufferPointer(start: data[0], count: n))
        let right = channels > 1 ? Array(UnsafeBufferPointer(start: data[1], count: n)) : left
        let sample = SampleBuffer(left: left, right: right, sampleRate: format.sampleRate)
        // MP3, AAC and 24-bit sources are converted to 32 bit on loading (as in FL's sampler readout)
        let bits = file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int ?? 0
        let isFloat = file.fileFormat.commonFormat == .pcmFormatFloat32 || file.fileFormat.commonFormat == .pcmFormatFloat64
        sample.bitDepth = bits == 16 && !isFloat ? 16 : 32
        sample.stereo = channels > 1
        let marks = markers(url, rate: format.sampleRate)
        sample.cues = marks.cues.filter { $0 > 0 && $0 < n }
        if let r = marks.region, r.lowerBound >= 0, r.upperBound < n, r.count > 32 { sample.region = r }
        return sample
    }

    /// A WAV file's cue points (slice markers) and first 'smpl' loop (its region), in frames.
    static func markers(_ url: URL, rate: Double) -> (cues: [Int], region: ClosedRange<Int>?) {
        let ext = url.pathExtension.lowercased()
        guard ext == "wav" || ext == "wave", let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count > 12 else { return ([], nil) }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> ([Int], ClosedRange<Int>?) in
            let count = raw.count
            func u32(_ o: Int) -> Int {
                guard o >= 0, o + 4 <= count else { return 0 }
                return Int(raw[o]) | Int(raw[o + 1]) << 8 | Int(raw[o + 2]) << 16 | Int(raw[o + 3]) << 24
            }
            func tag(_ o: Int) -> String {
                guard o + 4 <= count else { return "" }
                return String(bytes: [raw[o], raw[o + 1], raw[o + 2], raw[o + 3]], encoding: .ascii) ?? ""
            }
            guard tag(0) == "RIFF", tag(8) == "WAVE" else { return ([], nil) }
            var cues: [Int] = []
            var region: ClosedRange<Int>?
            var o = 12
            while o + 8 <= count {
                let id = tag(o), size = u32(o + 4), body = o + 8
                if id == "cue " {
                    let n = min(u32(body), 512)
                    for i in 0..<n { cues.append(u32(body + 4 + i * 24 + 20)) }
                } else if id == "smpl", u32(body + 28) > 0 {
                    let start = u32(body + 36 + 8), end = u32(body + 36 + 12)
                    if end > start { region = start...end }
                }
                o = body + size + (size & 1)
            }
            return (Array(Set(cues)).sorted(), region)
        }
    }

    /// Copies a file into the Samples folder (if it isn't there already) and returns its name.
    static func copyIntoSamples(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let folder = KnockFolders.samples
        if url.deletingLastPathComponent().standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") || url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
            return url.path.replacingOccurrences(of: folder.standardizedFileURL.path + "/", with: "")
        }
        var dest = folder.appendingPathComponent(url.lastPathComponent)
        // The same sound again (a library pick, say): reuse the copy that's already there, if it is the
        // same audio (a copy of a levelled stock sound has the same size but not the same sound).
        let size = { (u: URL) in (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }
        if FileManager.default.fileExists(atPath: dest.path) && size(dest) == size(url),
           let a = try? Data(contentsOf: dest), let b = try? Data(contentsOf: url), a == b { return dest.lastPathComponent }
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = url.deletingPathExtension().lastPathComponent
            dest = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(url.pathExtension)
            n += 1
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest.lastPathComponent
    }

    static func urlInSamples(_ name: String) -> URL { KnockFolders.samples.appendingPathComponent(name) }

    /// Copies of stock sounds in Samples (every library pick copies its sound there, they're MY SOUNDS)
    /// go back to the bundled original when they differ from it: builds 74-82 levelled the stock sounds
    /// and Tyrone wants the originals (Oct 18). Only a file of the same name and size is replaced (the
    /// levelling kept every length), so your own sounds are never touched. Returns how many were reset.
    @discardableResult
    static func restoreStockCopies(_ stock: [URL]) -> Int {
        let fm = FileManager.default
        var n = 0
        for url in stock {
            let dest = KnockFolders.samples.appendingPathComponent(url.lastPathComponent)
            guard fm.fileExists(atPath: dest.path) else { continue }
            let size = { (u: URL) in (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }
            guard size(dest) == size(url), let original = try? Data(contentsOf: url),
                  let copy = try? Data(contentsOf: dest), copy != original else { continue }
            if (try? original.write(to: dest, options: .atomic)) != nil { n += 1 }
        }
        return n
    }
}

// MARK: - Writing audio

enum WavWriter {
    /// Writes 24-bit stereo WAV.
    static func write(left: [Float], right: [Float], sampleRate: Double, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 24,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(left.count)),
              let ch = buffer.floatChannelData else { return }
        buffer.frameLength = AVAudioFrameCount(left.count)
        for i in 0..<left.count {
            ch[0][i] = left[i]
            ch[1][i] = right[i]
        }
        try file.write(from: buffer)
    }
}

// MARK: - MIDI files

enum MIDIFile {
    /// One track, channel 10. Pads are notes 36...47; chromatic 808 notes are 48...84
    /// (60 = its tuning). MIDI export bounds bass pitches to that chromatic range so they
    /// cannot be mistaken for drum pads on import; audio rendering keeps the full pitch.
    static func write(_ source: PatternData, tempo: Double, bounce: Float, bars: Int, to url: URL) throws {
        // The file carries what you hear: HUMANIZE's played feel included.
        let pattern = PatternSet.humanized(source)
        let ppq = Int(PatternData.ppq)
        var events: [(tick: Int, bytes: [UInt8])] = []
        let loopLen = max(1, Int(pattern.lengthTicks))
        let repeats = max(1, Int(ceil(Double(bars * ppq * 4) / Double(loopLen))))
        let total = bars * ppq * 4
        for r in 0..<repeats {
            for e in pattern.events {
                // CHANCE: each pass of the loop drops the notes the engine would drop on that pass.
                if e.chance < 1 && PatternData.chanceRoll(pass: r, tick: e.tick, pad: e.pad) >= e.chance { continue }
                var t = r * loopLen + Int(pattern.playTick(e, bounce: Double(bounce)).rounded())
                t = max(0, t)
                guard t < total else { continue }
                let isBass = Int(e.pad) == Pad.bass808.rawValue
                let bassNote = (Pad.bassRootNote + Int(e.semis.rounded())).clamped(Pad.bassNoteRange.lowerBound, Pad.bassNoteRange.upperBound)
                let note = isBass ? UInt8(bassNote) : UInt8(Pad(rawValue: Int(e.pad))?.midiNote ?? 36)
                let vel = UInt8(clamping: max(1, Int((e.velocity * 127).rounded())))
                var len = isBass ? Int(e.length) : 12
                if len <= 0 { len = ppq }
                events.append((t, [0x99, note, vel]))
                events.append((min(t + len, total), [0x89, note, 0]))
            }
        }
        events.sort { $0.tick == $1.tick ? $0.bytes[0] < $1.bytes[0] : $0.tick < $1.tick }  // note-offs first
        var track: [UInt8] = []
        // Tempo and 4/4
        let usPerQuarter = Int(60_000_000 / max(tempo, 1))
        track += [0x00, 0xFF, 0x51, 0x03, UInt8(usPerQuarter >> 16 & 0xFF), UInt8(usPerQuarter >> 8 & 0xFF), UInt8(usPerQuarter & 0xFF)]
        track += [0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]
        let name = Array("BreaKing".utf8)
        track += [0x00, 0xFF, 0x03, UInt8(name.count)] + name
        var last = 0
        for e in events {
            track += varLen(e.tick - last)
            track += e.bytes
            last = e.tick
        }
        track += varLen(max(0, total - last)) + [0xFF, 0x2F, 0x00]
        var data: [UInt8] = Array("MThd".utf8) + be32(6) + be16(0) + be16(1) + be16(UInt16(ppq))
        data += Array("MTrk".utf8) + be32(UInt32(track.count)) + track
        try Data(data).write(to: url, options: .atomic)
    }

    /// Twelve channels: a track per pad, pad n on MIDI channel n + 1 (the same layout as MIDI OUT's
    /// multi-out), every note around C3 (60 = the pad's own pitch, the 808's tuning) so a DAW's
    /// piano roll has full control of each hit's pitch and velocity. Tracks carry the channel names.
    static func writeChannels(_ source: PatternData, names: [String], tempo: Double, bounce: Float, bars: Int, to url: URL) throws {
        // The file carries what you hear: HUMANIZE's played feel included.
        let pattern = PatternSet.humanized(source)
        let ppq = Int(PatternData.ppq)
        let loopLen = max(1, Int(pattern.lengthTicks))
        let repeats = max(1, Int(ceil(Double(bars * ppq * 4) / Double(loopLen))))
        let total = bars * ppq * 4
        var tracks: [[UInt8]] = []
        // Track 0: tempo, time signature, the name
        var meta: [UInt8] = []
        let usPerQuarter = Int(60_000_000 / max(tempo, 1))
        meta += [0x00, 0xFF, 0x51, 0x03, UInt8(usPerQuarter >> 16 & 0xFF), UInt8(usPerQuarter >> 8 & 0xFF), UInt8(usPerQuarter & 0xFF)]
        meta += [0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]
        let title = Array("BreaKing".utf8)
        meta += [0x00, 0xFF, 0x03, UInt8(title.count)] + title
        meta += varLen(total) + [0xFF, 0x2F, 0x00]
        tracks.append(meta)
        for pad in 0..<Pad.count {
            var events: [(tick: Int, bytes: [UInt8])] = []
            let ch = UInt8(pad & 0x0F)
            for r in 0..<repeats {
                for e in pattern.events where Int(e.pad) == pad {
                    if e.chance < 1 && PatternData.chanceRoll(pass: r, tick: e.tick, pad: e.pad) >= e.chance { continue }
                    var tk = r * loopLen + Int(pattern.playTick(e, bounce: Double(bounce)).rounded())
                    tk = max(0, tk)
                    guard tk < total else { continue }
                    let note = UInt8((Pad.bassRootNote + Int(e.semis.rounded())).clamped(0, 127))
                    let vel = UInt8(clamping: max(1, Int((e.velocity * 127).rounded())))
                    var len = Int(e.length)
                    if len <= 0 { len = pad == Pad.bass808.rawValue ? ppq : 12 }
                    events.append((tk, [0x90 | ch, note, vel]))
                    events.append((min(tk + len, total), [0x80 | ch, note, 0]))
                }
            }
            events.sort { $0.tick == $1.tick ? $0.bytes[0] < $1.bytes[0] : $0.tick < $1.tick }
            var track: [UInt8] = []
            let name = Array((pad < names.count ? names[pad] : "PAD \(pad + 1)").prefix(60).utf8)
            track += [0x00, 0xFF, 0x03, UInt8(name.count)] + name
            var last = 0
            for e in events {
                track += varLen(e.tick - last)
                track += e.bytes
                last = e.tick
            }
            track += varLen(max(0, total - last)) + [0xFF, 0x2F, 0x00]
            tracks.append(track)
        }
        var data: [UInt8] = Array("MThd".utf8) + be32(6) + be16(1) + be16(UInt16(tracks.count)) + be16(UInt16(ppq))
        for track in tracks { data += Array("MTrk".utf8) + be32(UInt32(track.count)) + track }
        try Data(data).write(to: url, options: .atomic)
    }

    /// Reads a MIDI file into a loop. A BreakBoss 12-channel file (notes on channels other than
    /// 10) puts channel n + 1 on pad n, pitched around C3; otherwise notes 36...47 land on the
    /// pads and 48...84 on the 808 (channel 10, GM style).
    static func read(_ url: URL) -> PatternData? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 4 * 1024 * 1024,
              let d = try? Data(contentsOf: url), d.count > 14 else { return nil }
        let bytes = [UInt8](d)
        guard String(bytes: bytes[0..<4], encoding: .ascii) == "MThd" else { return nil }
        let division = Int(bytes[12]) << 8 | Int(bytes[13])
        guard division > 0 && division < 0x8000 else { return nil }
        var pos = 8 + (Int(bytes[4]) << 24 | Int(bytes[5]) << 16 | Int(bytes[6]) << 8 | Int(bytes[7]))
        var ons: [(tick: Int, note: Int, vel: Int, ch: Int)] = []
        var offs: [(tick: Int, note: Int, ch: Int)] = []
        var trackEndTick = 0
        while pos + 8 <= bytes.count {
            let id = String(bytes: bytes[pos..<pos + 4], encoding: .ascii)
            let len = Int(bytes[pos + 4]) << 24 | Int(bytes[pos + 5]) << 16 | Int(bytes[pos + 6]) << 8 | Int(bytes[pos + 7])
            pos += 8
            let end = min(bytes.count, pos + len)
            if id == "MTrk" {
                var p = pos, tick = 0, running: UInt8 = 0
                while p < end {
                    var delta = 0
                    var deltaBytes = 0
                    while p < end {
                        deltaBytes += 1; guard deltaBytes <= 4 else { return nil }
                        let b = bytes[p]; p += 1; delta = delta << 7 | Int(b & 0x7F)
                        if b & 0x80 == 0 { break }
                    }
                    tick += delta
                    guard tick <= 100_000_000 else { return nil }
                    guard p < end else { break }
                    var st = bytes[p]
                    if st & 0x80 != 0 { p += 1; if st < 0xF0 { running = st } } else { st = running }
                    if st == 0xFF {
                        guard p + 1 < end else { break }
                        p += 1
                        var l = 0
                        var lengthBytes = 0
                        while p < end {
                            lengthBytes += 1; guard lengthBytes <= 4 else { return nil }
                            let b = bytes[p]; p += 1; l = l << 7 | Int(b & 0x7F)
                            if b & 0x80 == 0 { break }
                        }
                        guard l <= end - p else { return nil }
                        p += l
                    } else if st == 0xF0 || st == 0xF7 {
                        var l = 0
                        var lengthBytes = 0
                        while p < end {
                            lengthBytes += 1; guard lengthBytes <= 4 else { return nil }
                            let b = bytes[p]; p += 1; l = l << 7 | Int(b & 0x7F)
                            if b & 0x80 == 0 { break }
                        }
                        guard l <= end - p else { return nil }
                        p += l
                    } else {
                        guard st >= 0x80 && st < 0xF0 else { return nil }
                        let kind = st & 0xF0
                        let size = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
                        guard p + size <= end else { break }
                        let d1 = Int(bytes[p]), d2 = size > 1 ? Int(bytes[p + 1]) : 0
                        p += size
                        guard ons.count + offs.count < 32768, d1 < 128, d2 < 128 else { return nil }
                        if kind == 0x90 && d2 > 0 { ons.append((tick, d1, d2, Int(st & 0x0F))) }
                        else if kind == 0x80 || kind == 0x90 { offs.append((tick, d1, Int(st & 0x0F))) }
                    }
                }
                // Keep the declared timeline, including note releases and a silent tail
                // before End of Track. The last note-on alone can shorten an authored loop.
                trackEndTick = max(trackEndTick, tick)
            }
            pos = end
        }
        guard !ons.isEmpty else { return nil }
        let scale = Double(PatternData.ppq) / Double(division)
        var events: [GrooveEvent] = []
        var lastTick = 0
        let maxLen = Int(PatternEdit.barTicks) * PatternEdit.maxBars
        let multiChannel = ons.contains { $0.ch != 9 }      // BreakBoss's 12-channel export (or any multi-channel part)
        for on in ons {
            let t = Int((Double(on.tick) * scale).rounded())
            guard t >= 0 && t < 8 * Int(PatternData.ppq) * 4 else { continue }
            lastTick = max(lastTick, t)
            if multiChannel {
                guard on.ch < Pad.count else { continue }
                let pad = on.ch
                let off = offs.first { $0.note == on.note && $0.ch == on.ch && $0.tick > on.tick }
                let len = off.map { Int((Double($0.tick - on.tick) * scale).rounded()) } ?? (pad == Pad.bass808.rawValue ? Int(PatternData.ppq) : 0)
                let semis = (on.note - Pad.bassRootNote).clamped(-24, 24)
                events.append(GrooveEvent(tick: Int32(t), pad: Int8(pad), velocity: Float(on.vel) / 127, semis: Float(semis),
                                          length: Int32((pad == Pad.bass808.rawValue || len > 12 ? len : 0).clamped(0, maxLen))))
            } else if let pad = Pad.index(forMIDINote: on.note) {
                events.append(GrooveEvent(tick: Int32(t), pad: Int8(pad), velocity: Float(on.vel) / 127))
            } else if Pad.bassNoteRange.contains(on.note) {
                let off = offs.first { $0.note == on.note && $0.tick > on.tick }
                let len = off.map { Int((Double($0.tick - on.tick) * scale).rounded()) } ?? Int(PatternData.ppq)
                events.append(GrooveEvent(tick: Int32(t), pad: Int8(Pad.bass808.rawValue), velocity: Float(on.vel) / 127,
                                          semis: Float(on.note - Pad.bassRootNote), length: Int32(len.clamped(0, maxLen))))
            }
        }
        guard !events.isEmpty else { return nil }
        let bar = Int(PatternData.ppq) * 4
        let endTick = max(lastTick + 1, Int((Double(trackEndTick) * scale).rounded()))
        let bars = min(PatternEdit.maxBars, max(1, Int(ceil(Double(endTick) / Double(bar)))))
        var p = PatternData(name: url.deletingPathExtension().lastPathComponent.uppercased(), lengthTicks: Int32(bars * bar), events: events)
        let limit = p.lengthTicks
        p.events.removeAll { $0.tick >= limit }
        p.sort()
        return p
    }

    private static func varLen(_ value: Int) -> [UInt8] {
        var v = max(0, value)
        var out: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            out.insert(UInt8(v & 0x7F) | 0x80, at: 0)
            v >>= 7
        }
        return out
    }

    private static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    private static func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
}
