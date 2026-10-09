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
            case .unreadable(let name): return "\(name) isn't an audio file BreakBoss can read."
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
        return SampleBuffer(left: left, right: right, sampleRate: format.sampleRate)
    }

    /// Copies a file into the Samples folder (if it isn't there already) and returns its name.
    static func copyIntoSamples(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let folder = KnockFolders.samples
        if url.deletingLastPathComponent().standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path) {
            return url.path.replacingOccurrences(of: folder.standardizedFileURL.path + "/", with: "")
        }
        var dest = folder.appendingPathComponent(url.lastPathComponent)
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
    /// One track, channel 10. Pads are notes 36-47; the 808 plays notes 48-84 (60 = its tuning),
    /// so a file dragged back onto a BreakBoss loop pad plays the same.
    static func write(_ pattern: PatternData, tempo: Double, bounce: Float, bars: Int, to url: URL) throws {
        let ppq = Int(PatternData.ppq)
        var events: [(tick: Int, bytes: [UInt8])] = []
        let loopLen = Int(pattern.lengthTicks)
        let repeats = max(1, Int(ceil(Double(bars * ppq * 4) / Double(loopLen))))
        let total = bars * ppq * 4
        for r in 0..<repeats {
            for e in pattern.events {
                var t = r * loopLen + Int(e.tick) + Int(swing(tick: Int(e.tick), pad: Int(e.pad), bounce: bounce).rounded())
                t = max(0, t)
                guard t < total else { continue }
                let isBass = Int(e.pad) == Pad.bass808.rawValue
                let note = isBass ? UInt8(clamping: Pad.bassRootNote + Int(e.semis.rounded())) : UInt8(Pad.firstNote + Int(e.pad))
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
        let name = Array("BreakBoss".utf8)
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

    /// Reads a MIDI file into a loop. Notes 36-47 land on the pads, 48-84 on the 808.
    static func read(_ url: URL) -> PatternData? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url), d.count > 14 else { return nil }
        let bytes = [UInt8](d)
        guard String(bytes: bytes[0..<4], encoding: .ascii) == "MThd" else { return nil }
        let division = Int(bytes[12]) << 8 | Int(bytes[13])
        guard division > 0 && division < 0x8000 else { return nil }
        var pos = 8 + (Int(bytes[4]) << 24 | Int(bytes[5]) << 16 | Int(bytes[6]) << 8 | Int(bytes[7]))
        var ons: [(tick: Int, note: Int, vel: Int)] = []
        var offs: [(tick: Int, note: Int)] = []
        while pos + 8 <= bytes.count {
            let id = String(bytes: bytes[pos..<pos + 4], encoding: .ascii)
            let len = Int(bytes[pos + 4]) << 24 | Int(bytes[pos + 5]) << 16 | Int(bytes[pos + 6]) << 8 | Int(bytes[pos + 7])
            pos += 8
            let end = min(bytes.count, pos + len)
            if id == "MTrk" {
                var p = pos, tick = 0, running: UInt8 = 0
                while p < end {
                    var delta = 0
                    while p < end { let b = bytes[p]; p += 1; delta = delta << 7 | Int(b & 0x7F); if b & 0x80 == 0 { break } }
                    tick += delta
                    guard p < end else { break }
                    var st = bytes[p]
                    if st & 0x80 != 0 { p += 1; if st < 0xF0 { running = st } } else { st = running }
                    if st == 0xFF {
                        guard p + 1 < end else { break }
                        p += 1
                        var l = 0
                        while p < end { let b = bytes[p]; p += 1; l = l << 7 | Int(b & 0x7F); if b & 0x80 == 0 { break } }
                        p += l
                    } else if st == 0xF0 || st == 0xF7 {
                        var l = 0
                        while p < end { let b = bytes[p]; p += 1; l = l << 7 | Int(b & 0x7F); if b & 0x80 == 0 { break } }
                        p += l
                    } else {
                        let kind = st & 0xF0
                        let size = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
                        guard p + size <= end else { break }
                        let d1 = Int(bytes[p]), d2 = size > 1 ? Int(bytes[p + 1]) : 0
                        p += size
                        if kind == 0x90 && d2 > 0 { ons.append((tick, d1, d2)) }
                        else if kind == 0x80 || kind == 0x90 { offs.append((tick, d1)) }
                    }
                }
            }
            pos = end
        }
        guard !ons.isEmpty else { return nil }
        let scale = Double(PatternData.ppq) / Double(division)
        var events: [GrooveEvent] = []
        var lastTick = 0
        for on in ons {
            let t = Int((Double(on.tick) * scale).rounded())
            lastTick = max(lastTick, t)
            if on.note >= Pad.firstNote && on.note < Pad.firstNote + Pad.count {
                events.append(GrooveEvent(tick: Int32(t), pad: Int8(on.note - Pad.firstNote), velocity: Float(on.vel) / 127))
            } else if Pad.bassNoteRange.contains(on.note) {
                let off = offs.first { $0.note == on.note && $0.tick > on.tick }
                let len = off.map { Int((Double($0.tick - on.tick) * scale).rounded()) } ?? Int(PatternData.ppq)
                events.append(GrooveEvent(tick: Int32(t), pad: Int8(Pad.bass808.rawValue), velocity: Float(on.vel) / 127,
                                          semis: Float(on.note - Pad.bassRootNote), length: Int32(len)))
            }
        }
        guard !events.isEmpty else { return nil }
        let bar = Int(PatternData.ppq) * 4
        let bars = min(8, max(1, Int(ceil(Double(lastTick + 1) / Double(bar)))))
        var p = PatternData(name: url.deletingPathExtension().lastPathComponent.uppercased(), lengthTicks: Int32(bars * bar), events: events)
        let limit = p.lengthTicks
        p.events.removeAll { $0.tick >= limit }
        p.sort()
        return p
    }

    static func swing(tick: Int, pad: Int, bounce: Float) -> Double {
        guard bounce > 0.001 else { return 0 }
        let b = Double(bounce)
        var o: Double = 0
        if abs(tick % 48 - 24) <= 2 { o += b * 8 }
        if pad == Pad.kick.rawValue { o += b * b * 4 }
        if pad == Pad.snare.rawValue || pad == Pad.clap.rawValue { o -= b * b * 3 }
        return o
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
