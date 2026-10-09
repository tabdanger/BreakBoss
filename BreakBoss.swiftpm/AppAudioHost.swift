// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import AVFoundation
import CoreMIDI
import Foundation

// MARK: - The standalone app's audio and MIDI
//
// The engine runs inside an AVAudioSourceNode at the hardware's sample rate with a short
// buffer (128 frames asked for). MIDI keyboards and pad controllers plugged into the iPad (or
// on the network / Bluetooth) play the pads; MIDI clock, start and stop drive TEMPO SYNC and
// FOLLOW DAW. In the AUv3 plug-in none of this is used: the host does it.

final class AppAudioHost {
    static let shared = AppAudioHost()

    let engine = KnockEngine()
    lazy var controller = KnockController(engine: engine, isPlugin: false)

    private let audio = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var midiClient = MIDIClientRef()
    private var midiPort = MIDIPortRef()
    private var observers: [NSObjectProtocol] = []
    private var hostTicksToSeconds: Double = 1e-9

    private init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        hostTicksToSeconds = Double(info.numer) / Double(info.denom) / 1e9
    }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        configureSession()
        buildGraph()
        startMIDI()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main) { [weak self] _ in
            self?.restart()
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.restart()
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.configureSession()
            self?.restart()
        })
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(128.0 / 48_000)
        try? session.setActive(true)
    }

    private func buildGraph() {
        let output = audio.outputNode
        let hw = output.outputFormat(forBus: 0)
        let rate = hw.sampleRate > 0 ? hw.sampleRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        engine.prepare(sampleRate: rate, maxFrames: 4_096)
        let engine = self.engine
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(bufferList)
            guard list.count >= 2,
                  let l = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = list[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            engine.render(frames: Int(frameCount), left: l, right: r, host: nil)
            return noErr
        }
        if let old = source { audio.detach(old) }
        audio.attach(node)
        audio.connect(node, to: audio.mainMixerNode, format: format)
        source = node
        audio.prepare()
        try? audio.start()
        // Kits are made at the engine's rate; remake them if the hardware rate changed.
        controller.rebuildKit()
    }

    private func restart() {
        audio.stop()
        configureSession()
        buildGraph()
    }

    // MARK: MIDI

    private func startMIDI() {
        let notify: MIDINotifyBlock = { [weak self] message in
            if message.pointee.messageID == .msgSetupChanged { DispatchQueue.main.async { self?.connectSources() } }
        }
        guard MIDIClientCreateWithBlock("BreakBoss" as CFString, &midiClient, notify) == noErr else { return }
        let engine = self.engine
        let toSeconds = hostTicksToSeconds
        let status = MIDIInputPortCreateWithProtocol(midiClient, "BreakBoss In" as CFString, ._1_0, &midiPort) { list, _ in
            for packet in list.unsafeSequence() {
                let time = packet.pointee.timeStamp > 0 ? Double(packet.pointee.timeStamp) * toSeconds
                                                        : ProcessInfo.processInfo.systemUptime
                let count = min(Int(packet.pointee.wordCount), 64)
                let offset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words) ?? 12
                let words = UnsafeRawPointer(packet).advanced(by: offset).assumingMemoryBound(to: UInt32.self)
                for w in 0..<count {
                    let word = words[w]
                    let type = word >> 28
                    let st = UInt8((word >> 16) & 0xFF)
                    let d1 = UInt8((word >> 8) & 0x7F)
                    let d2 = UInt8(word & 0x7F)
                    if type == 0x2 || type == 0x1 {      // MIDI 1.0 channel voice / system
                        engine.receiveMIDI(status: st, data1: d1, data2: d2, time: time)
                    }
                }
            }
        }
        guard status == noErr else { return }
        connectSources()
    }

    private func connectSources() {
        guard midiPort != 0 else { return }
        for i in 0..<MIDIGetNumberOfSources() {
            MIDIPortConnectSource(midiPort, MIDIGetSource(i), nil)
        }
    }
}

