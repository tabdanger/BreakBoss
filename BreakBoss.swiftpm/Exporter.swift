// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - Export: raw MIDI, the full stereo mix, or one file per drum
//
// Audio is rendered offline by a second engine with the same kit, loop and knobs, so it sounds
// exactly like what you hear (Modern / Vintage / Texture chain and the master clipper
// included). The loop is played through once first, so delay and reverb tails from the end
// wrap into the start and the file loops seamlessly.

enum Exporter {
    struct Job {
        var kit: KitBuffers
        var patterns: PatternSet
        var loop: Int
        var params: [Float]
        var tempo: Double
        var bars: Int
        var sampleRate: Double = 48_000
        var baseName: String
    }

    struct Stem: Hashable {
        var name: String
        var url: URL
    }

    struct Output {
        var midi: URL?
        var mix: URL?
        var stems: [Stem] = []
    }

    static func run(_ job: Job, midi: Bool, mix: Bool, stems: Bool) throws -> Output {
        var out = Output()
        let folder = KnockFolders.exports
        let base = KnockFolders.safe(job.baseName)
        let pattern = job.patterns.data[job.loop]
        let bounce = job.params[KParam.bounce.rawValue]
        if midi {
            let url = folder.appendingPathComponent(base).appendingPathExtension("mid")
            try MIDIFile.write(pattern, tempo: job.tempo, bounce: bounce, bars: job.bars, to: url)
            out.midi = url
        }
        if mix {
            let (l, r) = render(job, mask: 0xFFFF)
            let url = folder.appendingPathComponent(base).appendingPathExtension("wav")
            try WavWriter.write(left: l, right: r, sampleRate: job.sampleRate, to: url)
            out.mix = url
        }
        if stems {
            let used = Set(pattern.events.map { Int($0.pad) })
            for pad in Pad.allCases where used.contains(pad.rawValue) {
                let (l, r) = render(job, mask: UInt16(1) << UInt16(pad.rawValue))
                let name = "\(base) - \(pad.label.replacingOccurrences(of: " / ", with: "-"))"
                let url = folder.appendingPathComponent(KnockFolders.safe(name)).appendingPathExtension("wav")
                try WavWriter.write(left: l, right: r, sampleRate: job.sampleRate, to: url)
                out.stems.append(Stem(name: pad.label, url: url))
            }
        }
        return out
    }

    /// Renders `bars` bars of the loop (after one silent pass for the tails).
    static func render(_ job: Job, mask: UInt16) -> ([Float], [Float]) {
        let engine = KnockEngine()
        engine.prepare(sampleRate: job.sampleRate, maxFrames: 4_096)
        for p in KParam.allCases where p.rawValue < job.params.count { engine.setParam(p, job.params[p.rawValue]) }
        engine.setParam(.followDAW, 0)
        engine.setParam(.tempoSync, 0)
        engine.displayBPM.pointee = job.tempo
        engine.padMask = mask
        engine.kitHandoff.publish(job.kit)
        engine.patternHandoff.publish(job.patterns)
        engine.send(KEvent(kind: .loopPad, a: Int32(job.loop)))

        let loopTicks = Double(job.patterns.loops[job.loop].lengthTicks)
        let samplesPerBeat = 60 / job.tempo * job.sampleRate
        let prime = Int((loopTicks / Double(PatternData.ppq) * samplesPerBeat).rounded())
        let total = Int((Double(job.bars) * 4 * samplesPerBeat).rounded())

        let block = 1_024
        var l = [Float](repeating: 0, count: block), r = [Float](repeating: 0, count: block)
        var outL = [Float](), outR = [Float]()
        outL.reserveCapacity(total)
        outR.reserveCapacity(total)
        var primed = 0
        while primed < prime {
            let n = min(block, prime - primed)
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    engine.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
                }
            }
            primed += n
        }
        var made = 0
        while made < total {
            let n = min(block, total - made)
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    engine.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!, host: nil)
                }
            }
            outL.append(contentsOf: l[0..<n])
            outR.append(contentsOf: r[0..<n])
            made += n
        }
        engine.kitHandoff.collect()
        engine.patternHandoff.collect()
        return (outL, outR)
    }
}
