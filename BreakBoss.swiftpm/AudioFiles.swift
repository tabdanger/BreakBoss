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
        return SampleBuffer(left: left, right: right, sampleRate: format.sampleRate)
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
        // Reuse an identical sound only. Different audio can share both filename and size;
        // Foundation compares file contents on this control-plane import path.
        let size = { (u: URL) in (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1 }
        if FileManager.default.fileExists(atPath: dest.path), size(dest) == size(url),
           FileManager.default.contentsEqual(atPath: dest.path, andPath: url.path) { return dest.lastPathComponent }
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
    /// One track. The original pads keep channel 10 notes 36...47 and the chromatic
    /// 808 range 48...84 (60 = its tuning). Reassigned rows have distinct notes on channel 1.
    /// Matching BBCR metadata retains per-hit tuning, duration, glide, and rack identity.
    static func write(_ pattern: PatternData, tempo: Double, bounce: Float, bars: Int, to url: URL, roles: [Int]? = nil) throws {
        let ppq = Int(PatternData.ppq)
        var events: [(tick: Int, bytes: [UInt8])] = []
        let loopLen = max(1, Int(pattern.lengthTicks))
        let repeats = max(1, Int(ceil(Double(bars * ppq * 4) / Double(loopLen))))
        let total = bars * ppq * 4
        for r in 0..<repeats {
            for e in pattern.events {
                let slot = Int(e.pad)
                guard (0..<RackLimits.maxChannels).contains(slot), e.velocity.isFinite, e.semis.isFinite else { continue }
                let role = roles.flatMap { slot < $0.count ? $0[slot] : nil } ?? slot
                var t = r * loopLen + Int(e.tick) + Int(swing(tick: Int(e.tick), pad: role, bounce: bounce).rounded())
                t = max(0, t)
                guard t < total else { continue }
                let isBass = role == Pad.bass808.rawValue
                let bassNote = (Pad.bassRootNote + Int(e.semis.rounded())).clamped(Pad.bassNoteRange.lowerBound, Pad.bassNoteRange.upperBound)
                // Keep the established channel-10 map for unchanged factory roles. Added
                // or reassigned rows use their own slot note on channel 1, preventing two
                // independent 808 rows from collapsing onto the same channel/pitch route.
                // BBCR metadata never changes unrelated imported channel-1 note mappings.
                let legacyRoute = slot < Pad.count && role == slot
                let channel: UInt8 = legacyRoute ? 9 : 0
                let note = legacyRoute ? (isBass ? UInt8(bassNote) : UInt8(Pad(rawValue: slot)?.midiNote ?? 36)) : UInt8(slot)
                let vel = UInt8(clamping: max(1, Int((e.velocity.clamped(0, 1) * 127).rounded())))
                var len = isBass ? Int(e.length) : 12
                if len <= 0 { len = ppq }
                let metadata: [UInt8] = Array("BBCR".utf8) + [1, channel, note, UInt8(slot)] +
                    be32(e.semis.bitPattern) + be32(UInt32(max(0, e.length))) + [e.glide ? 1 : 0]
                events.append((t, [0xFF, 0x7F] + varLen(metadata.count) + metadata + [0] + [0x90 | channel, note, vel]))
                events.append((min(t + len, total), [0x80 | channel, note, 0]))
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

    /// Reads standard notes 36...47 as pads and 48...84 as the 808. BBCR metadata is
    /// applied only to matching actual note-ons, so DAW note edits remain authoritative.
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
        var ons: [(tick: Int, channel: Int, note: Int, vel: Int)] = []
        var offs: [(tick: Int, channel: Int, note: Int)] = []
        var rackNotes: [String: GrooveEvent] = [:]
        // A DAW can move notes without moving sequencer-specific metadata. Keep its
        // declared routes, while per-hit pitch/glide still require an exact note match.
        var rackRoutes: [Int: (pad: Int8, gated: Bool)] = [:]
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
                        let metaType = bytes[p]
                        p += 1
                        var l = 0
                        var lengthBytes = 0
                        while p < end {
                            lengthBytes += 1; guard lengthBytes <= 4 else { return nil }
                            let b = bytes[p]; p += 1; l = l << 7 | Int(b & 0x7F)
                            if b & 0x80 == 0 { break }
                        }
                        guard l <= end - p else { return nil }
                        if metaType == 0x7F, l == 17,
                           Array(bytes[p..<p + 4]) == Array("BBCR".utf8), bytes[p + 4] == 1 {
                            let channel = Int(bytes[p + 5]), note = Int(bytes[p + 6]), slot = Int(bytes[p + 7])
                            func word(_ start: Int) -> UInt32 {
                                UInt32(bytes[start]) << 24 | UInt32(bytes[start + 1]) << 16 | UInt32(bytes[start + 2]) << 8 | UInt32(bytes[start + 3])
                            }
                            let semis = Float(bitPattern: word(p + 8)), length = word(p + 12)
                            guard rackNotes.count < 32768 else { return nil }
                            if (0..<RackLimits.maxChannels).contains(slot), channel < 16, note < 128,
                               semis.isFinite, abs(semis) <= 48, length <= UInt32(PatternEdit.barTicks * Int32(PatternEdit.maxBars)) {
                                rackNotes["\(tick):\(channel):\(note)"] = GrooveEvent(tick: 0, pad: Int8(slot), velocity: 1,
                                    semis: semis, length: Int32(length), glide: bytes[p + 16] == 1)
                                if channel == 0 && note == slot {
                                    let key = channel * 128 + note
                                    rackRoutes[key] = (Int8(slot), length > 0 || rackRoutes[key]?.gated == true)
                                }
                            }
                        }
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
                        if kind == 0x90 && d2 > 0 { ons.append((tick, Int(st & 0x0F), d1, d2)) }
                        else if kind == 0x80 || kind == 0x90 { offs.append((tick, Int(st & 0x0F), d1)) }
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
        for on in ons {
            let t = Int((Double(on.tick) * scale).rounded())
            guard t >= 0 && t < PatternEdit.maxBars * Int(PatternData.ppq) * 4 else { continue }
            lastTick = max(lastTick, t)
            if var event = rackNotes["\(on.tick):\(on.channel):\(on.note)"] {
                event.tick = Int32(t)
                event.velocity = Float(on.vel) / 127
                if event.length > 0 {
                    let off = offs.first { $0.channel == on.channel && $0.note == on.note && $0.tick > on.tick }
                    if let off { event.length = Int32(Int((Double(off.tick - on.tick) * scale).rounded()).clamped(0, Int(PatternEdit.barTicks) * PatternEdit.maxBars)) }
                }
                events.append(event)
            } else if let route = rackRoutes[on.channel * 128 + on.note] {
                let off = offs.first { $0.channel == on.channel && $0.note == on.note && $0.tick > on.tick }
                let length = route.gated ? (off.map { Int((Double($0.tick - on.tick) * scale).rounded()) } ?? Int(PatternData.ppq)) : 0
                events.append(GrooveEvent(tick: Int32(t), pad: route.pad, velocity: Float(on.vel) / 127,
                                          length: Int32(length.clamped(0, Int(PatternEdit.barTicks) * PatternEdit.maxBars))))
            } else if let pad = Pad.index(forMIDINote: on.note) {
                events.append(GrooveEvent(tick: Int32(t), pad: Int8(pad), velocity: Float(on.vel) / 127))
            } else if Pad.bassNoteRange.contains(on.note) {
                let off = offs.first { $0.channel == on.channel && $0.note == on.note && $0.tick > on.tick }
                let len = off.map { Int((Double($0.tick - on.tick) * scale).rounded()) } ?? Int(PatternData.ppq)
                events.append(GrooveEvent(tick: Int32(t), pad: Int8(Pad.bass808.rawValue), velocity: Float(on.vel) / 127,
                                          semis: Float(on.note - Pad.bassRootNote), length: Int32(len.clamped(0, Int(PatternEdit.barTicks) * PatternEdit.maxBars))))
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
