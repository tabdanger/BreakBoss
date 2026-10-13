// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import AVFoundation
import SwiftUI

// MARK: - Record straight to a pad (standalone app; hold a pad > Record)
//
// Records the mic to a WAV with AVAudioRecorder, away from the drum engine's render callback.
// When you stop, the silence before the first sound is trimmed (so the pad hits right away),
// then the file goes through KnockController.importSample like any file from Files.

@MainActor
final class PadRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var seconds: Double = 0
    @Published private(set) var level: Float = 0      // 0...1 for the meter
    @Published var message: String?

    static let maxSeconds: Double = 20
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func start() {
        let handler: @Sendable (Bool) -> Void = { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.message = "BreakBoss needs the microphone to record. Turn it on in Settings › Privacy & Security › Microphone."
                    return
                }
                self.begin()
            }
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: handler)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(handler)
        }
    }

    private func begin() {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothA2DP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Recording \(PadRecorder.stamp()).wav")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.isMeteringEnabled = true
            guard r.record(forDuration: PadRecorder.maxSeconds) else { throw CocoaError(.fileWriteUnknown) }
            recorder = r
            fileURL = url
            isRecording = true
            seconds = 0
            message = nil
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
        } catch {
            restoreSession()
            message = "Couldn't start recording (\(error.localizedDescription))."
        }
    }

    private func tick() {
        guard let r = recorder else { return }
        if !r.isRecording { finishTimer(); isRecording = false; return }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0)
        level = max(0, min(1, (db + 50) / 50))
        seconds = r.currentTime
    }

    /// Stops and returns the trimmed take, ready to import (nil if nothing was heard).
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        finishTimer()
        isRecording = false
        level = 0
        restoreSession()
        guard let url = fileURL else { return nil }
        fileURL = nil
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            guard let trimmed = try PadRecorder.trimLeadingSilence(url) else {
                message = "Didn't hear anything. Try again a little closer to the mic."
                return nil
            }
            return trimmed
        } catch {
            message = "Couldn't save the recording (\(error.localizedDescription))."
            return nil
        }
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        fileURL = nil
        finishTimer()
        isRecording = false
        level = 0
        restoreSession()
    }

    private func finishTimer() { timer?.invalidate(); timer = nil }

    /// Back to the app's normal playback session (the same settings AppAudioHost starts with).
    private func restoreSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmmss"
        return f.string(from: Date())
    }

    /// Cuts everything before the first sound louder than -40 dB (keeping 4 ms), with a 2 ms
    /// fade-in so there's no click. Returns nil when the take is silent.
    nonisolated static func trimLeadingSilence(_ url: URL) throws -> URL? {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else { return nil }
        let channels = Int(format.channelCount), count = Int(buffer.frameLength)
        let threshold: Float = 0.01   // -40 dB
        var first = -1
        outer: for i in 0..<count {
            for c in 0..<channels where abs(data[c][i]) > threshold { first = i; break outer }
        }
        guard first >= 0 else { return nil }
        let rate = format.sampleRate
        let start = max(0, first - Int(rate * 0.004))
        let length = count - start
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length)),
              let outData = out.floatChannelData else { return nil }
        out.frameLength = AVAudioFrameCount(length)
        let fade = max(1, Int(rate * 0.002))
        for c in 0..<channels {
            for i in 0..<length {
                let g: Float = i < fade ? Float(i) / Float(fade) : 1
                outData[c][i] = data[c][start + i] * g
            }
        }
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + " trimmed.wav")
        try? FileManager.default.removeItem(at: dest)
        let writer = try AVAudioFile(forWriting: dest, settings: file.fileFormat.settings,
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        try writer.write(from: out)
        // Name the pad's sample after the take, not "trimmed".
        let named = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent.replacingOccurrences(of: ".wav", with: " take.wav"))
        try? FileManager.default.removeItem(at: named)
        try FileManager.default.moveItem(at: dest, to: named)
        return named
    }
}
