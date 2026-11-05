// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation

// MARK: - A loaded kit (the engine's sounds)

/// A multisampled pad (the acoustic drums): velocity layers, softest first, each with its round robins.
/// Made off the audio thread; `source` is the pad's main sample it belongs to.
final class VelocityLayers {
    let source: SampleBuffer
    let tops: [Float]
    let hits: [[SampleBuffer]]

    init?(source: SampleBuffer, tops: [Float], hits: [[SampleBuffer]]) {
        guard !tops.isEmpty, tops.count == hits.count, hits.allSatisfy({ !$0.isEmpty }) else { return nil }
        self.source = source
        self.tops = tops
        self.hits = hits
    }

    /// The layer a hit this hard (0...1) plays.
    @inline(__always)
    func layer(for velocity: Float) -> Int {
        var i = 0
        while i < tops.count - 1 && velocity > tops[i] { i += 1 }
        return i
    }
}

/// The sounds on the 12 pads, ready for the audio thread (read-only once published).
final class KitBuffers {
    let name: String
    let samples: [SampleBuffer]
    /// Pads that play a multisampled sound (nil: the pad's one sample plays every hit).
    let layers: [VelocityLayers?]
    let settings: [PadSettings]
    let bassHz: Float
    /// One-pole coefficients prepared on the control plane, never at note-on or render time.
    let filterCoefficients: [Float]
    /// Each pad's LEVEL and PAN as left / right gains (equal-power pan). Notes that are already
    /// sounding glide to these, so turning a channel's volume or pan never steps the gain.
    let mixL: [Float]
    let mixR: [Float]
    /// Each track's sampler as the audio thread plays it (envelopes, LFOs, filter, loop).
    let sampler: [SamplerRT]
    /// Each track's own FX insert (Face 2), per mode: index pad * 3 + mode.
    let inserts: [TrackFX.Insert]
    /// Pads with no sound (an EMPTY kit pad is one silent frame): a hit there starts no voice and
    /// chokes nothing (Tyrone, Oct 26: an EMPTY pad or track plays nothing at all).
    let silent: [Bool]

    init(name: String, samples: [SampleBuffer], settings: [PadSettings], bassHz: Float,
         renderSampleRate: Double = 48_000, layers: [VelocityLayers?] = []) {
        self.name = name
        self.samples = samples
        self.layers = layers
        self.settings = settings
        self.bassHz = bassHz
        let rate = renderSampleRate.isFinite && renderSampleRate > 0 ? renderSampleRate : 48_000
        filterCoefficients = settings.map { pad in
            let amount = pad.filter.isFinite ? pad.filter.clamped(0, 1) : 1
            guard amount < 0.999_999 else { return 1 }
            let cutoff = min(40 * pow(450, Double(amount)), rate * 0.45)
            return Float(1 - exp(-2 * Double.pi * cutoff / rate))
        }
        mixL = settings.map { $0.gain * cosf(($0.pan.clamped(-1, 1) + 1) * .pi / 4) * 1.414 }
        mixR = settings.map { $0.gain * sinf(($0.pan.clamped(-1, 1) + 1) * .pi / 4) * 1.414 }
        sampler = settings.map { SamplerRT($0.sampler) }
        inserts = settings.flatMap { pad in SoundMode.allCases.map { TrackFX.insert(pad, $0) } }
        silent = samples.indices.map { pad in samples[pad].length <= 1 && (pad >= layers.count || layers[pad] == nil) }
    }

    @inline(__always)
    func insert(_ pad: Int, _ mode: SoundMode) -> TrackFX.Insert? {
        let i = pad * 3 + mode.rawValue
        return pad >= 0 && i < inserts.count ? inserts[i] : nil
    }
}
