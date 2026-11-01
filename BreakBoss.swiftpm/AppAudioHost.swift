// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import AVFoundation
import CoreMIDI
import Foundation
import UIKit

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
    // No virtual MIDI source (Tyrone, Nov 1): the old "BreaKing Out" port let every MIDI app on the
    // iPad hear BreaKing's pads and patterns and play along. The app's notes stay inside BreaKing;
    // only the AUv3 sends MIDI out, through its host's MIDI output (Logic).
    private var observers: [NSObjectProtocol] = []
    private var hostTicksToSeconds: Double = 1e-9
    /// The app in the background lets controller MIDI go (Tyrone, Oct 20): with BreaKing open in a host
    /// as well, both copies used to play every note, one with the old sound. Read on the MIDI thread.
    private let midiQuiet = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

    private init() {
        midiQuiet.initialize(to: false)
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        hostTicksToSeconds = Double(info.numer) / Double(info.denom) / 1e9
    }

    private var started = false
    private var restarting = false
    private var connectedSources: Set<MIDIEndpointRef> = []

    /// True only in the simulator self-test (BREAKBOSS_SELFTEST=1): the live output is left off.
    static var skipLiveAudio: Bool {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["BREAKBOSS_SELFTEST"] == "1"
        #else
        return false
        #endif
    }

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
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
            if AVAudioSession.InterruptionType(rawValue: raw) == .began {
                self?.engine.send(KEvent(kind: .allOff))
            } else if AVAudioSession.InterruptionType(rawValue: raw) == .ended {
                self?.restart()
            }
        })
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.midiQuiet.pointee = true
            self.engine.send(KEvent(kind: .allOff))   // notes held when it went quiet never get their note off
        })
        observers.append(center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.midiQuiet.pointee = false
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
        try? session.setPreferredIOBufferDuration(AppAudioHost.padBufferSeconds)
        try? session.setActive(true)
        // Asked again once active: iPadOS can keep the old (512-frame, 10.7 ms) buffer when the ask only
        // came before activation, and every frame of buffer is a frame between a pad tap and its sound.
        try? session.setPreferredIOBufferDuration(AppAudioHost.padBufferSeconds)
        BugLog.shared.note(String(format: "Audio %.0f Hz, buffer %.1f ms, output latency %.1f ms",
                                  session.sampleRate, session.ioBufferDuration * 1000, session.outputLatency * 1000))
    }

    /// The pads' buffer: 128 frames at 48 kHz (2.7 ms), the shortest the engine stays click-free at.
    static let padBufferSeconds = 128.0 / 48_000

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
        do { try audio.start() }
        catch { controller.notice = "Audio could not start: " + error.localizedDescription }
        // Kits are made at the engine's rate; remake them if the hardware rate changed.
        controller.rebuildKit()
    }

    private func restart() {
        guard !restarting else { return }
        restarting = true
        defer { restarting = false }
        audio.stop()
        configureSession()
        buildGraph()
    }

    // MARK: MIDI

    private func startMIDI() {
        let notify: MIDINotifyBlock = { [weak self] message in
            if message.pointee.messageID == .msgSetupChanged { DispatchQueue.main.async { self?.connectSources() } }
        }
        guard MIDIClientCreateWithBlock("BreaKing" as CFString, &midiClient, notify) == noErr else { return }
        let engine = self.engine
        let toSeconds = hostTicksToSeconds
        let quiet = midiQuiet
        let status = MIDIInputPortCreateWithProtocol(midiClient, "BreaKing In" as CFString, ._1_0, &midiPort) { list, _ in
            if quiet.pointee { return }
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

    private func isOwnSource(_ endpoint: MIDIEndpointRef) -> Bool {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr, let n = name?.takeRetainedValue() else { return false }
        return (n as String) == "BreaKing Out"
    }

    private func connectSources() {
        guard midiPort != 0 else { return }
        let available = Set((0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) })
        if !connectedSources.subtracting(available).isEmpty { engine.send(KEvent(kind: .allOff)) }
        connectedSources.formIntersection(available)
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            // Never listen to an old "BreaKing Out" port (an older build still running): its hits
            // would retrigger the pads / loops and turn the beat into a buzzing tone.
            if isOwnSource(endpoint) { continue }
            if !connectedSources.contains(endpoint), MIDIPortConnectSource(midiPort, endpoint, nil) == noErr {
                connectedSources.insert(endpoint)
            }
        }
    }
}

