// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import SwiftUI

/// What the screen shows for a moment after you touch something.
struct Readout: Equatable {
    var title: String
    var value: String
    var time: Date
}

/// Everything the faceplate does, on the main thread. The engine does the sound; this keeps the
/// saved state, builds kits and loops, and talks to the host (AUv3) or the app.
final class KnockController: ObservableObject {
    let engine: KnockEngine
    let isPlugin: Bool

    @Published private(set) var state = KnockState()
    @Published var readout: Readout?
    @Published private(set) var userKits: [String] = []
    @Published private(set) var userPresets: [String] = []
    /// The 12 pad sounds as loaded (for the pad editor's waveform).
    @Published private(set) var kitSamples: [SampleBuffer] = []
    @Published private(set) var loadingKit = false
    /// A short message for the screen (errors, "saved", ...).
    @Published var notice: String?

    /// The 12 loops as the engine has them (generated, with your edits on top).
    @Published private(set) var loops: [PatternData] = []

    /// AUv3: a control changed on the faceplate (tell the host so it can record automation).
    var onParameterChanged: ((KParam, Float) -> Void)?
    /// AUv3: many controls changed at once (preset, undo): the host should re-read them all.
    var onStateReplaced: (() -> Void)?

    private let kitQueue = DispatchQueue(label: "breakboss.kit", qos: .userInitiated)
    private var kitGeneration = 0
    private var timers: [Timer] = []
    private var saveWork: DispatchWorkItem?

    init(engine: KnockEngine, isPlugin: Bool) {
        self.engine = engine
        self.isPlugin = isPlugin
        var s = KnockState()
        for p in KParam.allCases { s.values[p.id] = p.defaultValue }
        if !isPlugin, let data = UserDefaults.standard.data(forKey: KnockController.sessionKey),
           let saved = try? JSONDecoder().decode(KnockState.self, from: data) {
            s = saved
        }
        state = s
        pushAllToEngine()
        refreshLists()
        rebuildKit()
        rebuildLoops()

        // Hand old kits / loops back to the main thread to be freed; follow host automation.
        let collect = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.engine.kitHandoff.collect()
            self?.engine.patternHandoff.collect()
        }
        RunLoop.main.add(collect, forMode: .common)
        timers.append(collect)
        if isPlugin {
            let follow = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.followEngineParams() }
            RunLoop.main.add(follow, forMode: .common)
            timers.append(follow)
        }
    }

    deinit { timers.forEach { $0.invalidate() } }

    static let sessionKey = "breakboss.session"

    // MARK: Controls

    func value(_ p: KParam) -> Float { state.values[p.id] ?? p.defaultValue }

    var mode: SoundMode { SoundMode(rawValue: Int(value(.soundMode).rounded())) ?? .modern }
    var playMode: PlayMode { value(.playMode) > 0.5 ? .loop : .oneShot }
    var kitDefinition: KitDefinition { KitLibrary.kit(id: state.kitID) }

    /// Sets a control from the faceplate (or from the host when `fromHost`).
    func set(_ p: KParam, _ v: Float, fromHost: Bool = false, show: Bool = true) {
        var v = v
        if let steps = p.steps { v = Float(Int(v.rounded()).clamped(0, steps - 1)) } else { v = v.clamped(0, 1) }
        if state.values[p.id] == v { return }
        state.values[p.id] = v
        engine.setParam(p, v)
        if p == .soundMode { state.mode = mode }
        if p == .playMode { state.playMode = playMode }
        if !fromHost { onParameterChanged?(p, v) }
        if show && p.isKnob { readout = Readout(title: p.name.uppercased(), value: p.text(v), time: Date()) }
        scheduleSave()
    }

    func selectMode(_ m: SoundMode) {
        set(.soundMode, Float(m.rawValue), show: false)
        readout = Readout(title: "MODE", value: m.title, time: Date())
    }

    func selectPlayMode(_ m: PlayMode) {
        set(.playMode, Float(m.rawValue), show: false)
        readout = Readout(title: m == .loop ? "LOOP" : "ONE-SHOT", value: m == .loop ? "PADS PLAY GROOVES" : "PADS PLAY DRUMS", time: Date())
    }

    func toggle(_ p: KParam) {
        set(p, value(p) > 0.5 ? 0 : 1, show: false)
        readout = Readout(title: p.name.uppercased(), value: p.text(value(p)), time: Date())
    }

    func resetKnob(_ p: KParam) { set(p, p.defaultValue) }

    private func pushAllToEngine() {
        for p in KParam.allCases { engine.setParam(p, value(p)) }
        engine.displayBPM.pointee = state.bpm
    }

    /// AUv3: host automation writes the engine directly; bring the faceplate along.
    private func followEngineParams() {
        var changed = false
        for p in KParam.allCases {
            let e = engine.param(p)
            if abs((state.values[p.id] ?? p.defaultValue) - e) > 0.0005 {
                state.values[p.id] = e
                changed = true
            }
        }
        if changed {
            state.mode = mode
            state.playMode = playMode
        }
    }

    // MARK: Tempo

    var liveTempo: Double { engine.status[4] > 0 ? engine.status[4] : state.bpm }

    /// True when the tempo comes from the DAW or MIDI clock (the display can't be dragged).
    var tempoIsExternal: Bool {
        (value(.tempoSync) > 0.5 || value(.followDAW) > 0.5) && (engine.status[5] > 0 || engine.status[6] > 0)
    }

    func setBPM(_ bpm: Double) {
        let b = (bpm * 10).rounded() / 10
        state.bpm = b.clamped(40, 240)
        engine.displayBPM.pointee = state.bpm
        scheduleSave()
    }

    // MARK: Pads and transport

    func padDown(_ pad: Int, velocity: Float) {
        guard pad >= 0 && pad < Pad.count else { return }
        if playMode == .loop {
            engine.send(KEvent(kind: .loopPad, a: Int32(pad), value: Double(velocity)))
            let title = pad < loops.count ? loops[pad].name : LoopSlot(rawValue: pad)?.title ?? ""
            readout = Readout(title: "LOOP \(pad + 1)", value: title, time: Date())
        } else {
            engine.send(KEvent(kind: .pad, a: Int32(pad), value: Double(velocity)))
            let name = state.pads[pad].sampleFile.map { ($0 as NSString).deletingPathExtension.uppercased() }
                ?? kitDefinition.pads[pad].label
            readout = Readout(title: "PAD \(pad + 1)", value: name, time: Date())
        }
    }

    var isPlaying: Bool { engine.status[0] > 0.5 }

    func playPressed() {
        if value(.followDAW) > 0.5 && engine.status[5] > 0 {
            readout = Readout(title: "FOLLOW DAW", value: "START IT FROM THE DAW", time: Date())
            return
        }
        engine.send(KEvent(kind: isPlaying ? .stop : .play))
    }

    // MARK: Dice

    /// LOOP mode: new grooves for this kit. ONE-SHOT mode: new variations of the kit's sounds.
    func dice() {
        let seed = UInt32.random(in: 2...UInt32.max)
        if playMode == .loop {
            state.grooveSeed = seed
            rebuildLoops()
            readout = Readout(title: "DICE", value: "NEW GROOVES", time: Date())
        } else {
            state.soundSeed = seed
            rebuildKit()
            readout = Readout(title: "DICE", value: "NEW SOUNDS", time: Date())
        }
        scheduleSave()
    }

    // MARK: Kits

    var kitDisplayName: String { "\(state.kitName) - \(mode.title)" }

    func selectKit(_ def: KitDefinition) {
        state.kitID = def.id
        state.kitName = def.name
        state.userKit = nil
        state.soundSeed = 1
        state.grooveSeed = 1
        state.pads = Array(repeating: PadSettings(), count: Pad.count)
        state.editedLoops = Array(repeating: nil, count: Pad.count)
        if value(.tempoSync) < 0.5 { setBPM(def.tempo) }
        rebuildKit()
        rebuildLoops()
        readout = Readout(title: "KIT", value: def.name, time: Date())
        scheduleSave()
    }

    func selectUserKit(_ name: String) {
        guard let kit = KnockStore.loadUserKit(name) else { notice = "Couldn't open the kit \(name)."; return }
        let def = KitLibrary.kit(id: kit.baseKitID)
        state.kitID = def.id
        state.kitName = kit.name.uppercased()
        state.userKit = kit.name
        state.soundSeed = kit.soundSeed
        state.pads = kit.pads.count == Pad.count ? kit.pads : Array(repeating: PadSettings(), count: Pad.count)
        if value(.tempoSync) < 0.5 { setBPM(def.tempo) }
        rebuildKit()
        rebuildLoops()
        readout = Readout(title: "KIT", value: state.kitName, time: Date())
        scheduleSave()
    }

    func saveKit(as name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let kit = UserKit(name: clean, baseKitID: state.kitID, soundSeed: state.soundSeed, pads: state.pads)
        if KnockStore.saveUserKit(kit) {
            state.kitName = clean.uppercased()
            state.userKit = clean
            refreshLists()
            readout = Readout(title: "KIT SAVED", value: clean.uppercased(), time: Date())
        } else {
            notice = "Couldn't save the kit."
        }
    }

    func deleteUserKit(_ name: String) {
        KnockStore.deleteUserKit(name)
        refreshLists()
    }

    func refreshLists() {
        userKits = KnockStore.userKitNames()
        userPresets = KnockStore.userPresetNames()
    }

    /// Renders the kit's sounds (off the main thread) and hands them to the engine.
    func rebuildKit() {
        kitGeneration += 1
        let generation = kitGeneration
        let s = state
        let def = KitLibrary.kit(id: s.kitID)
        let rate = engine.sampleRate > 0 ? engine.sampleRate : 48_000
        loadingKit = true
        kitQueue.async { [weak self] in
            var samples: [SampleBuffer] = []
            var failed: [String] = []
            for pad in 0..<Pad.count {
                if let file = s.pads[pad].sampleFile {
                    if let buffer = try? SampleLoader.load(SampleLoader.urlInSamples(file)) {
                        samples.append(buffer)
                        continue
                    }
                    failed.append(file)
                }
                var recipe = def.pads[pad]
                if s.soundSeed > 1 {
                    var rng = KRandom(seed: s.soundSeed &* 2_654_435_761 &+ UInt32(pad * 977))
                    recipe = recipe.varied(&rng)
                }
                samples.append(DrumSynth.render(recipe, sampleRate: rate, seed: s.soundSeed &+ UInt32(pad)))
            }
            let kit = KitBuffers(name: s.kitName, samples: samples, settings: s.pads, bassHz: def.bassHz)
            DispatchQueue.main.async {
                guard let self, generation == self.kitGeneration else { return }
                self.engine.kitHandoff.publish(kit)
                self.kitSamples = samples
                self.loadingKit = false
                if !failed.isEmpty { self.notice = "Missing sample: \(failed.joined(separator: ", "))" }
            }
        }
    }

    /// Same sounds, new pad settings (level, pan, tune, decay, reverse): instant.
    private func republishKit() {
        guard kitSamples.count == Pad.count else { rebuildKit(); return }
        let kit = KitBuffers(name: state.kitName, samples: kitSamples, settings: state.pads, bassHz: kitDefinition.bassHz)
        engine.kitHandoff.publish(kit)
    }

    // MARK: Pad editor

    func setPadSettings(_ pad: Int, _ settings: PadSettings) {
        guard pad >= 0 && pad < Pad.count else { return }
        let needsReload = settings.sampleFile != state.pads[pad].sampleFile
        state.pads[pad] = settings
        if needsReload { rebuildKit() } else { republishKit() }
        scheduleSave()
    }

    /// Puts an audio file on a pad (it's copied into the Samples folder first).
    func importSample(_ url: URL, toPad pad: Int) {
        guard pad >= 0 && pad < Pad.count else { return }
        kitQueue.async { [weak self] in
            do {
                let name = try SampleLoader.copyIntoSamples(url)
                let buffer = try SampleLoader.load(SampleLoader.urlInSamples(name))
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.state.pads[pad].sampleFile = name
                    if self.kitSamples.count == Pad.count {
                        var samples = self.kitSamples
                        samples[pad] = buffer
                        self.kitSamples = samples
                        self.republishKit()
                    } else {
                        self.rebuildKit()
                    }
                    self.readout = Readout(title: "PAD \(pad + 1)", value: (name as NSString).deletingPathExtension.uppercased(), time: Date())
                    self.scheduleSave()
                }
            } catch {
                DispatchQueue.main.async { self?.notice = error.localizedDescription }
            }
        }
    }

    func revertPad(_ pad: Int) {
        guard pad >= 0 && pad < Pad.count else { return }
        state.pads[pad] = PadSettings()
        rebuildKit()
        scheduleSave()
    }

    func padName(_ pad: Int) -> String {
        if let f = state.pads[pad].sampleFile { return (f as NSString).deletingPathExtension }
        return kitDefinition.pads[pad].label
    }

    // MARK: Loops

    func rebuildLoops() {
        let generated = GrooveGenerator.loops(style: kitDefinition.style, seed: state.grooveSeed)
        var merged = generated
        for i in 0..<min(merged.count, state.editedLoops.count) {
            if let edit = state.editedLoops[i] { merged[i] = edit }
        }
        loops = merged
        engine.patternHandoff.publish(PatternSet(merged))
    }

    func setLoop(_ index: Int, _ data: PatternData?) {
        guard index >= 0 && index < Pad.count else { return }
        state.editedLoops[index] = data
        rebuildLoops()
        scheduleSave()
    }

    /// Step editor: adds a hit, or removes the ones already in that step.
    func toggleStep(loop: Int, pad: Int, step: Int) {
        guard loop >= 0 && loop < loops.count else { return }
        var p = loops[loop]
        let lo = Int32(step) * PatternData.stepTicks - 6
        let hi = Int32(step) * PatternData.stepTicks + 18
        let before = p.events.count
        p.events.removeAll { Int($0.pad) == pad && $0.tick >= lo && $0.tick < hi }
        if p.events.count == before {
            let tick = Int32(step) * PatternData.stepTicks
            if pad == Pad.bass808.rawValue {
                p.events.append(GrooveEvent(tick: tick, pad: Int8(pad), velocity: 0.9, semis: 0, length: PatternData.stepTicks * 2))
            } else {
                p.events.append(GrooveEvent(tick: tick, pad: Int8(pad), velocity: pad == Pad.hat.rawValue ? 0.7 : 0.9))
            }
        }
        p.sort()
        setLoop(loop, p)
    }

    func clearLoop(_ index: Int) {
        guard index >= 0 && index < loops.count else { return }
        var p = loops[index]
        p.events = []
        setLoop(index, p)
    }

    func regenerateLoop(_ index: Int) {
        let fresh = GrooveGenerator.loops(style: kitDefinition.style, seed: UInt32.random(in: 2...UInt32.max))
        guard index >= 0 && index < fresh.count else { return }
        setLoop(index, fresh[index])
    }

    func useGeneratedLoop(_ index: Int) { setLoop(index, nil) }

    func importMIDI(_ url: URL, toLoop index: Int) {
        guard let p = MIDIFile.read(url) else { notice = "No drum notes in \(url.lastPathComponent)."; return }
        setLoop(index, p)
        readout = Readout(title: "LOOP \(index + 1)", value: "MIDI IMPORTED", time: Date())
    }

    // MARK: Presets

    func loadInit() {
        let keepMode = mode
        for p in KParam.allCases where p != .soundMode { set(p, p.defaultValue, show: false) }
        set(.soundMode, Float(keepMode.rawValue), show: false)
        state.presetName = "INIT"
        onStateReplaced?()
        readout = Readout(title: "PRESET", value: "INIT", time: Date())
    }

    func loadFactoryPreset(_ fp: FactoryPreset) {
        for p in KParam.allCases where p.isKnob || p == .clipper { set(p, fp.values[p] ?? p.defaultValue, show: false) }
        set(.soundMode, Float(fp.mode.rawValue), show: false)
        if state.kitID != fp.kitID || state.userKit != nil { selectKit(KitLibrary.kit(id: fp.kitID)) }
        state.presetName = fp.name
        onStateReplaced?()
        readout = Readout(title: "PRESET", value: fp.name, time: Date())
        scheduleSave()
    }

    func savePreset(as name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var s = state
        s.presetName = clean.uppercased()
        if KnockStore.saveUserPreset(UserPreset(name: clean, state: s)) {
            state.presetName = clean.uppercased()
            refreshLists()
            readout = Readout(title: "PRESET SAVED", value: clean.uppercased(), time: Date())
        } else {
            notice = "Couldn't save the preset."
        }
    }

    func loadUserPreset(_ name: String) {
        guard let preset = KnockStore.loadUserPreset(name) else { notice = "Couldn't open the preset \(name)."; return }
        restore(preset.state)
        readout = Readout(title: "PRESET", value: preset.state.presetName, time: Date())
    }

    func deleteUserPreset(_ name: String) {
        KnockStore.deleteUserPreset(name)
        refreshLists()
    }

    // MARK: Whole state (app session, AUv3 project)

    func stateData() -> Data? { try? JSONEncoder().encode(state) }

    func restore(_ data: Data) {
        guard let s = try? JSONDecoder().decode(KnockState.self, from: data) else { return }
        restore(s)
    }

    func restore(_ s: KnockState) {
        var s = s
        for p in KParam.allCases where s.values[p.id] == nil { s.values[p.id] = p.defaultValue }
        if s.pads.count != Pad.count { s.pads = Array(repeating: PadSettings(), count: Pad.count) }
        if s.editedLoops.count != Pad.count { s.editedLoops = Array(repeating: nil, count: Pad.count) }
        state = s
        pushAllToEngine()
        rebuildKit()
        rebuildLoops()
        onStateReplaced?()
        scheduleSave()
    }

    private func scheduleSave() {
        guard !isPlugin else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let data = self.stateData() else { return }
            UserDefaults.standard.set(data, forKey: KnockController.sessionKey)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: Export

    /// The loop export uses: the one playing, or the last one picked, or MAIN A.
    var exportLoopIndex: Int {
        let current = Int(engine.status[1])
        return current >= 0 && current < loops.count ? current : 0
    }

    func export(loop: Int, bars: Int, midi: Bool, mix: Bool, stems: Bool,
                completion: @escaping (Result<Exporter.Output, Error>) -> Void) {
        guard kitSamples.count == Pad.count, loop >= 0, loop < loops.count else {
            completion(.failure(NSError(domain: "BreakBoss", code: 1, userInfo: [NSLocalizedDescriptionKey: "The kit is still loading."])))
            return
        }
        let kit = KitBuffers(name: state.kitName, samples: kitSamples, settings: state.pads, bassHz: kitDefinition.bassHz)
        let patterns = PatternSet(loops)
        var params = [Float](repeating: 0, count: KParam.count)
        for p in KParam.allCases { params[p.rawValue] = value(p) }
        let tempo = liveTempo
        let name = "BreakBoss \(state.kitName) \(loops[loop].name) \(Int(tempo.rounded()))BPM"
        let job = Exporter.Job(kit: kit, patterns: patterns, loop: loop, params: params, tempo: tempo, bars: bars, baseName: name)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Exporter.run(job, midi: midi, mix: mix, stems: stems) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
