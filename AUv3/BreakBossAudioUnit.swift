// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import AudioToolbox
import AVFoundation
import CoreAudioKit

// MARK: - BreakBoss as an AUv3 instrument (Logic Pro, GarageBand, Cubasis, AUM, Drambo...)
//
// Built on GitHub from the Xcode project in xcode/ (Swift Playgrounds can't build plug-ins).
// It uses the very same engine, kits, grooves and faceplate as the app. In a host:
//   - MIDI from the track plays the pads (C1-B1) or picks the loops in LOOP mode, and C2 and up
//     play the 808; it's sample-accurate.
//   - TEMPO SYNC uses the DAW's tempo, FOLLOW DAW starts / stops the loops with the DAW's
//     transport at the DAW's bar position.
//   - Every knob and switch is an automatable parameter, the factory presets show in the host's
//     preset menu, and the whole faceplate (kit, your pads, edited loops) is saved with the project.

public final class BreakBossAudioUnit: AUAudioUnit {
    let engine: KnockEngine
    let controller: KnockController

    private let outputBus: AUAudioUnitBus
    private var outputBusArray: AUAudioUnitBusArray!
    private var tree: AUParameterTree!
    private var factory: [AUAudioUnitPreset] = []
    private var chosenPreset: AUAudioUnitPreset?
    private let ownBuffers = KnockOwnBuffers()
    private static let stateKey = "breakboss.state"

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        let core = BreakBossAudioUnit.onMain { () -> (KnockEngine, KnockController) in
            let engine = KnockEngine()
            let controller = KnockController(engine: engine, isPlugin: true)
            return (engine, controller)
        }
        engine = core.0
        controller = core.1
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FormatNotSupported))
        }
        outputBus = try AUAudioUnitBus(format: format)
        outputBus.maximumChannelCount = 2
        try super.init(componentDescription: componentDescription, options: options)

        outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
        tree = Self.makeParameterTree()
        let engine = self.engine
        tree.implementorValueObserver = { parameter, value in
            guard let p = KParam(rawValue: Int(parameter.address)) else { return }
            engine.setParam(p, value)        // the faceplate follows on its own timer
        }
        tree.implementorValueProvider = { parameter in
            guard let p = KParam(rawValue: Int(parameter.address)) else { return parameter.value }
            return engine.param(p)
        }
        tree.implementorStringFromValueCallback = { parameter, valuePointer in
            guard let p = KParam(rawValue: Int(parameter.address)) else { return "" }
            return p.text(valuePointer?.pointee ?? parameter.value)
        }
        factory = FactoryPresets.all.enumerated().map { index, preset in
            let item = AUAudioUnitPreset()
            item.number = index
            item.name = preset.name
            return item
        }
        maximumFramesToRender = 4_096

        controller.onParameterChanged = { [weak self] p, value in
            self?.tree.parameter(withAddress: AUParameterAddress(p.rawValue))?.setValue(value, originator: nil)
        }
        controller.onStateReplaced = { [weak self] in
            self?.willChangeValue(forKey: "allParameterValues")
            self?.didChangeValue(forKey: "allParameterValues")
        }
    }

    // MARK: Busses, parameters, presets

    public override var outputBusses: AUAudioUnitBusArray { outputBusArray }

    public override var parameterTree: AUParameterTree? {
        get { tree }
        set { if let newValue { tree = newValue } }
    }

    /// No audio inputs; stereo or mono out.
    public override var channelCapabilities: [NSNumber]? { [0, 2, 0, 1] }

    public override var factoryPresets: [AUAudioUnitPreset]? { factory }

    public override var supportsUserPresets: Bool { true }

    public override var currentPreset: AUAudioUnitPreset? {
        get { chosenPreset }
        set {
            chosenPreset = newValue
            guard let preset = newValue else { return }
            let controller = self.controller
            if preset.number >= 0 {
                Self.onMain {
                    guard FactoryPresets.all.indices.contains(preset.number) else { return }
                    controller.loadFactoryPreset(FactoryPresets.all[preset.number])
                }
            } else if let state = try? presetState(for: preset), let data = state[Self.stateKey] as? Data {
                Self.onMain { controller.restore(data) }
            }
        }
    }

    public override var fullState: [String: Any]? {
        get {
            var state = super.fullState ?? [:]
            let controller = self.controller
            if let data = Self.onMain({ controller.stateData() }) { state[Self.stateKey] = data }
            return state
        }
        set {
            guard let newValue else { return }
            if let data = newValue[Self.stateKey] as? Data {
                let controller = self.controller
                Self.onMain { controller.restore(data) }
            } else {
                super.fullState = newValue
            }
        }
    }

    // MARK: Rendering

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        let format = outputBus.format
        ownBuffers.prepare(format: format, frames: maximumFramesToRender)
        let rate = format.sampleRate
        let changed = abs(engine.sampleRate - rate) > 1
        engine.prepare(sampleRate: rate, maxFrames: Int(maximumFramesToRender))
        if changed {
            let controller = self.controller
            Self.onMain { controller.rebuildKit() }
        }
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let engine = self.engine
        let own = ownBuffers
        let musical = musicalContextBlock
        let transport = transportStateBlock
        return { _, timestamp, frameCount, _, outputData, events, _ in
            own.fillIfEmpty(outputData, frames: frameCount)
            let list = UnsafeMutableAudioBufferListPointer(outputData)
            guard list.count > 0, let l = list[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let r = list.count > 1 ? (list[1].mData?.assumingMemoryBound(to: Float.self) ?? l) : l

            // Host MIDI and automation for this buffer.
            let start = timestamp.pointee.mSampleTime
            var event = events
            while let e = event {
                switch e.pointee.head.eventType {
                case .MIDI:
                    let m = e.pointee.MIDI
                    let offset = max(0, Int(Double(m.eventSampleTime) - start))
                    let bytes = m.data
                    engine.hostMIDI(offset: offset, status: bytes.0, data1: bytes.1, data2: bytes.2)
                case .parameter, .parameterRamp:
                    let p = e.pointee.parameter
                    if let k = KParam(rawValue: Int(p.parameterAddress)) { engine.setParam(k, p.value) }
                default:
                    break
                }
                event = UnsafePointer(e.pointee.head.next)
            }

            // Where the DAW is.
            var host = HostTiming()
            var tempo = 0.0, beat = 0.0
            if let musical, musical(&tempo, nil, nil, &beat, nil, nil) {
                host.tempo = tempo
                host.beat = beat
            }
            var flags = AUHostTransportStateFlags()
            if let transport, transport(&flags, nil, nil, nil) {
                host.playing = flags.contains(.moving)
            }
            if mono(list) {
                engine.render(frames: Int(frameCount), left: l, right: own.scratch(frames: frameCount), host: host)
            } else {
                engine.render(frames: Int(frameCount), left: l, right: r, host: host)
            }
            return noErr
        }
    }

    // MARK: Helpers

    @discardableResult
    static func onMain<T>(_ work: () -> T) -> T {
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }

    static func makeParameterTree() -> AUParameterTree {
        let parameters: [AUParameter] = KParam.allCases.map { p in
            let address = AUParameterAddress(p.rawValue)
            if let steps = p.steps {
                let strings = (0..<steps).map { p.text(Float($0)) }
                return AUParameterTree.createParameter(
                    withIdentifier: p.id, name: p.name, address: address,
                    min: 0, max: AUValue(steps - 1), unit: .indexed, unitName: nil,
                    flags: [.flag_IsReadable, .flag_IsWritable], valueStrings: strings, dependentParameters: nil)
            }
            return AUParameterTree.createParameter(
                withIdentifier: p.id, name: p.name, address: address,
                min: 0, max: 1, unit: .generic, unitName: nil,
                flags: [.flag_IsReadable, .flag_IsWritable, .flag_CanRamp], valueStrings: nil, dependentParameters: nil)
        }
        let tree = AUParameterTree.createTree(withChildren: parameters)
        for p in KParam.allCases { tree.parameter(withAddress: AUParameterAddress(p.rawValue))?.value = p.defaultValue }
        return tree
    }
}

@inline(__always)
private func mono(_ list: UnsafeMutableAudioBufferListPointer) -> Bool { list.count == 1 }

/// Buffers made when rendering starts, never on the audio thread: for hosts that pass empty
/// buffers (allowed by the AU rules), and the spare right channel when the track is mono.
final class KnockOwnBuffers {
    private var buffer: AVAudioPCMBuffer?
    private var spare: UnsafeMutablePointer<Float>?
    private var spareSize = 0

    func prepare(format: AVAudioFormat, frames: AUAudioFrameCount) {
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, 4_096))
        spare?.deallocate()
        spareSize = Int(max(frames, 4_096))
        spare = .allocate(capacity: spareSize)
        spare?.initialize(repeating: 0, count: spareSize)
    }

    deinit { spare?.deallocate() }

    /// Audio thread.
    func fillIfEmpty(_ outputData: UnsafeMutablePointer<AudioBufferList>, frames: AUAudioFrameCount) {
        let list = UnsafeMutableAudioBufferListPointer(outputData)
        guard list.count > 0, list[0].mData == nil, let buffer else { return }
        let own = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let bytes = frames * UInt32(MemoryLayout<Float>.size)
        for index in 0..<list.count where index < own.count {
            list[index].mData = own[index].mData
            list[index].mDataByteSize = bytes
        }
    }

    /// Audio thread: a throw-away right channel for mono output.
    func scratch(frames: AUAudioFrameCount) -> UnsafeMutablePointer<Float> {
        spare!   // made in prepare(), always big enough (maximumFramesToRender)
    }
}
