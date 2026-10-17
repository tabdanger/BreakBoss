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
    private(set) var meters = MeterSnapshot()

    @Published private(set) var state = KnockState()
    @Published var readout: Readout?
    @Published private(set) var userKits: [String] = []
    @Published private(set) var userPresets: [String] = []
    /// The 12 pad sounds as loaded (for the pad editor's waveform).
    @Published private(set) var kitSamples: [SampleBuffer] = []
    /// Names for successfully loaded factory samples; these never become device-local imports.
    @Published private(set) var stockSampleNames: [Int: String] = [:]
    @Published private(set) var loadingKit = false
    /// A short message for the screen (errors, "saved", ...).
    @Published var notice: String?
    /// True while there's sound (plus a second to let the trace settle). The screen only
    /// animates while it's true, so a silent app doesn't redraw it 60 times a second.
    @Published private(set) var scopeActive = false
    private var lastSound = Date.distantPast

    /// The 12 loops as the engine has them (generated, with your edits on top).
    @Published private(set) var loops: [PatternData] = []

    /// AUv3: a control changed on the faceplate (tell the host so it can record automation).
    var onParameterChanged: ((KParam, Float) -> Void)?
    /// AUv3: many controls changed at once (preset, undo): the host should re-read them all.
    var onStateReplaced: (() -> Void)?

    private let kitQueue = DispatchQueue(label: "breakboss.kit", qos: .userInitiated)
    private let stockLibrary = StockSampleLibrary.bundled
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
            s = saved.normalized()
        } else {
            // a fresh start is silent: blank loops until a pattern is loaded or drawn
            s.editedLoops = (0..<Pad.count).map { i in PatternData(name: "LOOP \(i + 1)", lengthTicks: PatternData.ppq * 4 * 2, events: []) }
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
        // RECORD (MPC style): finger-played pad hits land in the playing pattern, on the
        // record grid, from the faceplate as well as the drum roll.
        let rec = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.recording else { return }
            self.mergeRecorded(snap: self.recordSnap)
        }
        RunLoop.main.add(rec, forMode: .common)
        timers.append(rec)
        let metering = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.meters = self.engine.meters.snapshot()
            let m = self.meters
            if m.status[0] > 0.5 || m.scope.contains(where: { abs($0) > 0.0003 }) { self.lastSound = Date() }
            // Knob / pad readouts on the screen need the clock to fade out too.
            let showingReadout = self.readout.map { Date().timeIntervalSince($0.time) < 2.0 } ?? false
            let active = showingReadout || Date().timeIntervalSince(self.lastSound) < 1.0
            if active != self.scopeActive { self.scopeActive = active }
        }
        RunLoop.main.add(metering, forMode: .common)
        timers.append(metering)
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
        var v = v.isFinite ? v : p.defaultValue
        if let steps = p.steps { v = Float(Int(v.rounded()).clamped(0, steps - 1)) } else { v = v.clamped(0, 1) }
        if state.values[p.id] == v { return }
        state.values[p.id] = v
        engine.setParam(p, v)
        if p == .soundMode { state.mode = mode }
        if p == .playMode { state.playMode = playMode; engine.send(KEvent(kind: .allOff)) }
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
        engine.setTempo(state.bpm)
        pushMIDIMap()
        pushPadMask()
        pushMIDIOut()
    }

    // MARK: MIDI pad map (hardware controllers such as an MPC)

    var midiMap: MIDIPadMap { state.midiMap ?? .standard }
    var midiPadNotes: [Int] { MIDIPadMap.notes(midiMap, custom: state.midiCustomNotes) }

    func setMIDIMap(_ map: MIDIPadMap) {
        if map == .custom && state.midiCustomNotes == nil { state.midiCustomNotes = midiPadNotes }
        state.midiMap = map
        pushMIDIMap()
        scheduleSave()
    }

    /// MIDI learn: the next note becomes this pad's note (switches to the custom map).
    func learnMIDINote(pad: Int, note: Int) {
        state.midiCustomNotes = MIDIPadMap.learn(midiPadNotes, pad: pad, note: note)
        state.midiMap = .custom
        pushMIDIMap()
        scheduleSave()
    }

    /// The last note-on the engine received: (counter, note).
    var lastMIDINoteOn: (count: Int32, note: Int) {
        let v = engine.lastNoteOn.pointee
        return (v >> 8, Int(v & 0x7F))
    }

    private func pushMIDIMap() {
        engine.send(KEvent(kind: .mapNote, a: -1))
        for (pad, note) in midiPadNotes.enumerated() where note >= 0 {
            engine.send(KEvent(kind: .mapNote, a: Int32(note), value: Double(pad)))
        }
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

    var liveTempo: Double { meters.status[4] > 0 ? meters.status[4] : state.bpm }

    /// True when the tempo comes from the DAW or MIDI clock (the display can't be dragged).
    var tempoIsExternal: Bool {
        (value(.tempoSync) > 0.5 || value(.followDAW) > 0.5) && (meters.status[5] > 0 || meters.status[6] > 0)
    }

    func setBPM(_ bpm: Double) {
        let b = (bpm * 10).rounded() / 10
        state.bpm = b.clamped(40, 240)
        engine.setTempo(state.bpm)
        scheduleSave()
    }

    // MARK: Pads and transport

    func padDown(_ pad: Int, velocity: Float) {
        guard pad >= 0 && pad < Pad.count else { return }
        guard powerOn else { readout = Readout(title: "POWER", value: "OFF", time: Date()); return }
        if playMode == .loop {
            screenPattern = pad
            engine.send(KEvent(kind: .loopPad, a: Int32(pad), value: Double(velocity)))
            let title = pad < loops.count ? loops[pad].name : LoopSlot(rawValue: pad)?.title ?? ""
            readout = Readout(title: "LOOP \(pad + 1)", value: title, time: Date())
        } else {
            engine.send(KEvent(kind: .pad, a: Int32(pad), value: Double(velocity)))
            readout = Readout(title: "PAD \(pad + 1)", value: padName(pad).uppercased(), time: Date())
        }
    }

    // MARK: Drum roll

    /// Plays a pad's sound in any mode (drum roll ▶ buttons, previews). While RECORD is armed
    /// and the pattern runs, the engine also writes the hit into the pattern.
    func auditionPad(_ pad: Int, velocity: Float = 0.85, semis: Float = 0) {
        guard pad >= 0 && pad < Pad.count else { return }
        if pad == Pad.bass808.rawValue {
            engine.send(KEvent(kind: .bass, a: Int32(semis.rounded()), value: Double(velocity)))
        } else {
            engine.send(KEvent(kind: .pad, a: Int32(pad), value: Double(velocity)))
        }
    }

    var mutedPads: [Bool] { state.mutedPads ?? Array(repeating: false, count: Pad.count) }
    var soloPads: [Bool] { state.soloPads ?? Array(repeating: false, count: Pad.count) }

    func toggleMute(_ pad: Int) {
        guard (0..<Pad.count).contains(pad) else { return }
        var m = mutedPads; m[pad].toggle(); state.mutedPads = m
        pushPadMask(); scheduleSave()
    }

    func toggleSolo(_ pad: Int) {
        guard (0..<Pad.count).contains(pad) else { return }
        var m = soloPads; m[pad].toggle(); state.soloPads = m
        pushPadMask(); scheduleSave()
    }

    /// Every track back in (a dark lamp on a track another SOLO silenced).
    func clearSolos() {
        state.soloPads = nil
        pushPadMask(); scheduleSave()
    }

    /// FL-style: with any solo on, only soloed channels sound; mutes always silence.
    static func padMask(muted: [Bool], solo: [Bool]) -> UInt16 {
        let anySolo = solo.contains(true)
        var mask: UInt16 = 0
        for pad in 0..<Pad.count {
            let audible = (anySolo ? (pad < solo.count && solo[pad]) : true) && !(pad < muted.count && muted[pad])
            if audible { mask |= 1 << UInt16(pad) }
        }
        return mask
    }

    // MARK: MIDI out (multi-out)

    static let defaultMIDIOutChannels = Array(0..<Pad.count)          // pad n on MIDI channel n + 1
    static let defaultMIDIOutNotes = Array(36..<(36 + Pad.count))      // C1 up, like the input map
    /// On by default in the plug-in, so a DAW's armed MIDI track records the pads and pattern.
    var midiOutOn: Bool { state.midiOut ?? isPlugin }
    var midiOutChannels: [Int] { (state.midiOutChannels ?? KnockController.defaultMIDIOutChannels).count == Pad.count ? state.midiOutChannels ?? KnockController.defaultMIDIOutChannels : KnockController.defaultMIDIOutChannels }
    var midiOutNotes: [Int] { (state.midiOutNotes ?? KnockController.defaultMIDIOutNotes).count == Pad.count ? state.midiOutNotes ?? KnockController.defaultMIDIOutNotes : KnockController.defaultMIDIOutNotes }

    func setMIDIOut(_ on: Bool) { state.midiOut = on; pushMIDIOut(); scheduleSave() }
    func setMIDIOutChannel(pad: Int, _ channel: Int) {
        var ch = midiOutChannels; guard ch.indices.contains(pad) else { return }
        ch[pad] = max(-1, min(15, channel)); state.midiOutChannels = ch; pushMIDIOut(); scheduleSave()
    }
    func setMIDIOutNote(pad: Int, _ note: Int) {
        var n = midiOutNotes; guard n.indices.contains(pad) else { return }
        n[pad] = max(0, min(127, note)); state.midiOutNotes = n; pushMIDIOut(); scheduleSave()
    }
    /// Quick setups: every channel on its own MIDI channel, or all on channel 10 (GM drums).
    func setMIDIOutLayout(multi: Bool) {
        // One channel: the drums on channel 10 (GM drum notes); the 808 keeps its own channel (7)
        // so its pitches never land on a drum note.
        var one = Array(repeating: 9, count: Pad.count); one[Pad.bass808.rawValue] = Pad.bass808.rawValue
        state.midiOutChannels = multi ? KnockController.defaultMIDIOutChannels : one
        state.midiOutNotes = multi ? KnockController.defaultMIDIOutNotes : [36, 38, 39, 37, 42, 46, 35, 56, 54, 45, 50, 49]
        pushMIDIOut(); scheduleSave()
    }

    func pushMIDIOut() {
        let ch = midiOutChannels, notes = midiOutNotes
        for pad in 0..<Pad.count {
            engine.send(KEvent(kind: .midiOut, a: Int32(pad), value: ch[pad] < 0 ? -1 : Double(ch[pad] * 128 + notes[pad])))
        }
        engine.send(KEvent(kind: .midiOut, a: -1, value: midiOutOn ? 1 : 0))
    }

    private func pushPadMask() {
        let mask = powerOn ? KnockController.padMask(muted: mutedPads, solo: soloPads) : 0
        engine.send(KEvent(kind: .padMask, a: Int32(mask)))
    }

    /// Face 2's power button: off stops the pattern and silences every pad (taps, MIDI in, the
    /// sequencer and MIDI out) until it's pressed again. Not saved: the app always opens powered on.
    @Published private(set) var powerOn = true
    func togglePower() {
        powerOn.toggle()
        if !powerOn {
            if recording { setRecording(false) }
            stopPlayback()
            engine.send(KEvent(kind: .allOff))
        }
        pushPadMask()
        readout = Readout(title: "POWER", value: powerOn ? "ON" : "OFF", time: Date())
    }

    @Published private(set) var recording = false
    @Published private(set) var metronome = false

    /// Platinum: Modern's alternate faceplate (free while testing; will be a paid unlock).
    @Published private(set) var platinumFace: Bool = UserDefaults.standard.bool(forKey: "breakboss.platinumFace")
    func setPlatinumFace(_ on: Bool) {
        platinumFace = on
        UserDefaults.standard.set(on, forKey: "breakboss.platinumFace")
    }
    /// Which faceplate is showing: Platinum replaces Modern only.
    var faceKey: String { mode == .modern && platinumFace ? "platinum" : mode.assetSuffix }

    /// Drum roll metronome: a click on every beat while the pattern plays.
    func setMetronome(_ on: Bool) {
        metronome = on
        engine.send(KEvent(kind: .metronome, a: on ? 1 : 0))
    }

    /// Record quantize (ticks; 0 = as played). 1/16 by default, like an MPC's TC 16.
    var recordSnap: Int32 = PatternData.stepTicks
    /// RECORD keeps your timing: hits land on the grid with how early or late you played them as NOTE OFFSET.
    @Published private(set) var recordKeepsFeel: Bool = UserDefaults.standard.bool(forKey: "breakboss.recordKeepsFeel")
    func setRecordKeepsFeel(_ on: Bool) {
        recordKeepsFeel = on
        UserDefaults.standard.set(on, forKey: "breakboss.recordKeepsFeel")
    }

    /// RECORD's count-in, in bars (1 or 2), with the metronome clicking.
    @Published private(set) var countInBars: Int = max(1, min(2, UserDefaults.standard.integer(forKey: "breakboss.countInBars") == 0 ? 1 : UserDefaults.standard.integer(forKey: "breakboss.countInBars")))
    func setCountInBars(_ bars: Int) {
        countInBars = max(1, min(2, bars))
        UserDefaults.standard.set(countInBars, forKey: "breakboss.countInBars")
    }
    /// Beats of count-in still to go (0 when the pattern is running or stopped).
    var countInBeatsLeft: Int { Int(meters.status.count > 8 ? meters.status[8].rounded(.up) : 0) }
    var countingIn: Bool { recording && countInBeatsLeft > 0 }

    /// RECORD (faceplate and sequencer): a 1- or 2-bar metronome count-in, then the pattern plays
    /// and every pad you play lands in it, on that pad's own channel. Press again to stop
    /// recording (the pattern keeps playing). If the pattern is already running, recording just
    /// starts on the next hit, no count-in.
    func toggleRecordPads(loop: Int? = nil) {
        guard powerOn || recording else { readout = Readout(title: "POWER", value: "OFF", time: Date()); return }
        if recording {
            setRecording(false)
            readout = Readout(title: "RECORD", value: "OFF", time: Date())
            return
        }
        setRecording(true)
        if isPlaying {
            readout = Readout(title: "RECORD", value: "PLAY THE PADS", time: Date())
            return
        }
        let target = loop ?? (Int(meters.status[1]) >= 0 ? Int(meters.status[1]) : 0)
        engine.send(KEvent(kind: .countIn, a: Int32(countInBars * 4), value: Double(target)))
        readout = Readout(title: "RECORD", value: "COUNT-IN \(countInBars) BAR\(countInBars == 1 ? "" : "S")", time: Date())
    }

    func setRecording(_ on: Bool) {
        recording = on
        engine.send(KEvent(kind: .recordArm, a: on ? 1 : 0))
        _ = engine.collectRecorded()   // drop anything older
    }

    /// The pattern both faces work on: the one last played (a LOOP pad, the sequencer's PLAY) or
    /// edited in the sequencer. Face 1's PLAY plays it and the sequencer opens on it, so an empty
    /// sequencer means an empty pattern is what plays.
    private(set) var screenPattern = 0 {
        didSet { if screenPattern != oldValue { engine.send(KEvent(kind: .cue, a: Int32(screenPattern))) } }
    }

    /// The sequencer switched the pattern on screen ("Loop on screen").
    func showPattern(_ i: Int) { if loops.indices.contains(i) { screenPattern = i } }

    /// Plays the given pattern from its start (or keeps it going if it's already the one playing).
    func playPattern(_ loop: Int) {
        guard loops.indices.contains(loop) else { return }
        guard powerOn else { readout = Readout(title: "POWER", value: "OFF", time: Date()); return }
        screenPattern = loop
        if isPlaying && Int(meters.status[1]) == loop { return }
        if isPlaying { engine.send(KEvent(kind: .stop)) }
        engine.send(KEvent(kind: .loopPad, a: Int32(loop)))
    }

    func stopPlayback() { engine.send(KEvent(kind: .stop)) }

    /// Space bar / play button: start the pattern on screen, or stop.
    func togglePlayback(pattern: Int) {
        if isPlaying { stopPlayback() } else { playPattern(pattern) }
    }

    /// Where the playing pattern is, in ticks (nil when stopped).
    var playheadTick: Double? {
        let t = engine.playheadTick.pointee
        return t >= 0 ? t : nil
    }

    /// Moves recorded hits into their patterns (snapped when `snap` > 0). Returns how many.
    @discardableResult
    func mergeRecorded(snap: Int32) -> Int {
        let hits = engine.collectRecorded()
        guard !hits.isEmpty else { return 0 }
        var touched: [Int: PatternData] = [:]
        for h in hits {
            let loop = Int(h.loop)
            guard loops.indices.contains(loop) else { continue }
            var p = touched[loop] ?? loops[loop]
            p = PatternEdit.addRecorded(p, pad: Int(h.pad), tick: h.tick, velocity: h.velocity, semis: h.semis, snap: snap,
                                        keepFeel: recordKeepsFeel, bounce: Double(value(.bounce)))
            touched[loop] = p
        }
        for (loop, p) in touched { storeLoop(loop, p) }
        return hits.count
    }

    func gateDown(_ pad: Int, velocity: Float) {
        guard (0..<Pad.count).contains(pad) else { return }
        if playMode == .loop {
            engine.send(KEvent(kind: .loopGateOn, a: Int32(2048 + pad), value: Double(velocity)))
        } else { padDown(pad, velocity: velocity) }
    }

    func gateUp(_ pad: Int) {
        engine.send(KEvent(kind: .loopGateOff, a: Int32(2048 + pad)))
    }

    func previewLoop(_ index: Int) {
        guard loops.indices.contains(index) else { return }
        engine.send(KEvent(kind: .loopPad, a: Int32(index)))
    }

    func panic() { engine.send(KEvent(kind: .allOff)) }

    var isPlaying: Bool { meters.status[0] > 0.5 }

    func playPressed() {
        // PLAY starts the pattern the sequencer shows (value: pattern + 1).
        engine.send(isPlaying ? KEvent(kind: .stop) : KEvent(kind: .play, value: Double(screenPattern + 1)))
    }

    // MARK: Dice

    /// LOOP mode: new grooves for this kit. ONE-SHOT mode: new variations of the kit's sounds.
    /// The kit whose stock sound this pad plays after a dice roll (nil = the kit's own).
    static func stockPick(_ s: KnockState, pad: Int) -> String? {
        guard let picks = s.stockPicks, picks.indices.contains(pad) else { return nil }
        return picks[pad]
    }

    /// Home-screen dice (any mode): every pad gets a random sound of its own kind from all the
    /// stock sounds (every kit's kicks for the kick pad, and so on). The 808 only picks 808s tuned
    /// to this kit's root, so it stays in key. Pads holding your own samples are left alone.
    func dice() {
        var picks = state.stockPicks ?? Array(repeating: nil, count: Pad.count)
        while picks.count < Pad.count { picks.append(nil) }
        let root = kitDefinition.bassHz
        for pad in 0..<Pad.count where state.pads[pad].sampleFile == nil {
            var pool = stockLibrary.kits(withPad: pad)
            if pad == Pad.bass808.rawValue { pool = pool.filter { abs(KitLibrary.kit(id: $0).bassHz - root) < 0.5 } }
            pool.removeAll { $0 == (picks[pad] ?? state.kitID) }          // always a change
            if let pick = pool.randomElement() { picks[pad] = pick }
        }
        state.stockPicks = picks
        rebuildKit()
        readout = Readout(title: "DICE", value: "NEW SOUNDS", time: Date())
        scheduleSave()
    }

    // MARK: Kits

    var kitDisplayName: String { "\(state.kitName) - \(mode.title)" }

    func selectKit(_ def: KitDefinition) {
        state = state.selectingKit(def)
        engine.setTempo(state.bpm)
        rebuildKit()
        rebuildLoops()
        readout = Readout(title: "KIT", value: def.name, time: Date())
        scheduleSave()
    }

    func selectUserKit(_ name: String) {
        guard let kit = KnockStore.loadUserKit(name) else { notice = "Couldn't open the kit \(name)."; return }
        if state.patternStyle == nil { state.patternStyle = kitDefinition.style }   // sounds change, the pattern stays
        let def = KitLibrary.kit(id: kit.baseKitID)
        state.kitID = def.id
        state.kitName = kit.name.uppercased()
        state.userKit = kit.name
        state.soundSeed = kit.soundSeed
        state.pads = KnockState.normalizedPads(kit.pads)
        state.workspaceChannels = nil          // the rack shows the kit's sounds, the same as the pads
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
            scheduleSave()
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
        let stock = stockLibrary
        let rate = engine.sampleRate > 0 ? engine.sampleRate : 48_000
        loadingKit = true
        stockSampleNames = [:]
        kitQueue.async { [weak self] in
            var samples: [SampleBuffer] = []
            var failed: [String] = []
            var stockNames: [Int: String] = [:]
            for pad in 0..<Pad.count {
                if let file = s.pads[pad].sampleFile {
                    if let buffer = try? SampleLoader.load(SampleLoader.urlInSamples(file)) {
                        samples.append(buffer)
                        continue
                    }
                    failed.append(file)
                } else if let sample = KnockController.stockPick(s, pad: pad).flatMap({ stock.sample(kitID: $0, pad: pad) })
                            ?? stock.sample(kitID: def.id, pad: pad) {
                    if let buffer = try? SampleLoader.load(sample.url) {
                        samples.append(buffer)
                        stockNames[pad] = sample.displayName
                        continue
                    }
                    failed.append(sample.displayName)
                }
                var recipe = def.pads[pad]
                if s.soundSeed > 1 {
                    var rng = KRandom(seed: s.soundSeed &* 2_654_435_761 &+ UInt32(pad * 977))
                    recipe = recipe.varied(&rng)
                }
                samples.append(DrumSynth.render(recipe, sampleRate: rate, seed: s.soundSeed &+ UInt32(pad)))
            }
            DispatchQueue.main.async { [weak self, samples, failed, stockNames] in
                guard let self, generation == self.kitGeneration else { return }
                self.kitSamples = samples
                self.stockSampleNames = stockNames
                self.republishKit() // Apply edits made while decoding the kit.
                self.loadingKit = false
                if !failed.isEmpty {
                    self.notice = "Samples unavailable: \(failed.joined(separator: ", ")). Using synthesized sounds."
                } else if let failure = stock.failure {
                    self.notice = "\(failure) Using synthesized sounds."
                }
            }
        }
    }

    /// Same sounds, new pad settings (level, pan, tune, decay, filter, reverse): instant.
    private func republishKit() {
        guard kitSamples.count == Pad.count else { rebuildKit(); return }
        let kit = KitBuffers(name: state.kitName, samples: kitSamples, settings: state.pads,
                             bassHz: kitDefinition.bassHz, renderSampleRate: engine.sampleRate)
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
        let generation = kitGeneration
        kitQueue.async { [weak self] in
            do {
                let name = try SampleLoader.copyIntoSamples(url)
                let buffer = try SampleLoader.load(SampleLoader.urlInSamples(name))
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.kitGeneration == generation else { return }
                    self.state.pads[pad].sampleFile = name
                    self.stockSampleNames[pad] = nil
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
                DispatchQueue.main.async { [weak self] in self?.notice = error.localizedDescription }
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
        guard (0..<Pad.count).contains(pad) else { return "" }
        if let f = state.pads[pad].sampleFile { return (f as NSString).deletingPathExtension }
        if let name = stockSampleNames[pad] { return name }
        return kitDefinition.pads[pad].label
    }

    // MARK: Channel rack (the sequencer screen's channels; the faceplate's 12 pads underneath)

    /// The rack's channels: always all 12 pads, in pad order, so every sound that can play is on
    /// screen (Tyrone, Oct 17). A pad you haven't given a library sound shows the kit's sound.
    var rackChannels: [WorkspaceChannel] {
        let custom = state.workspaceChannels ?? []
        return rackOrder.map { pad in custom.first { $0.pad == pad } ?? kitChannel(pad) }
    }

    /// The rack's top-to-bottom order of pads: pad order until a track is dragged somewhere else.
    var rackOrder: [Int] {
        guard let order = state.rackOrder, order.count == Pad.count, Set(order) == Set(0..<Pad.count) else { return Array(0..<Pad.count) }
        return order
    }

    /// Drag a track up or down the rack: it lands at `index` (counted without it).
    func moveRackChannel(pad: Int, to index: Int) {
        var order = rackOrder
        guard let from = order.firstIndex(of: pad) else { return }
        order.remove(at: from)
        order.insert(pad, at: max(0, min(order.count, index)))
        state.rackOrder = order == Array(0..<Pad.count) ? nil : order
        scheduleSave()
    }

    private func kitChannel(_ pad: Int) -> WorkspaceChannel {
        WorkspaceChannel(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", pad)) ?? UUID(), pad: pad, soundID: "kit",
                         name: Pad(rawValue: pad)?.channelTitle ?? "PAD \(pad + 1)", category: SoundType.forPad(pad).rawValue)
    }

    /// Drop a library sound on the rack: it takes the last channel that still has the kit's sound
    /// and no notes in any pattern (the rack is always the 12 pads).
    @discardableResult
    func addRackChannel(_ sound: LibrarySound, load: Bool = true) -> WorkspaceChannel? {
        var rows = state.workspaceChannels ?? []
        let custom = Set(rows.map(\.pad))
        let playing = Set(loops.flatMap { $0.events.map { Int($0.pad) } })
        guard let pad = (0..<Pad.count).reversed().first(where: { !custom.contains($0) && !playing.contains($0) }) else {
            notice = "Every channel is in use. Drop the sound on a channel to replace it, or clear one first."
            return nil
        }
        let row = WorkspaceChannel(id: UUID(), pad: pad, soundID: sound.id, name: sound.name, category: sound.type.rawValue)
        rows.append(row)
        state.workspaceChannels = rows
        for i in loops.indices where loops[i].events.contains(where: { Int($0.pad) == pad }) {   // a fresh channel starts empty
            var p = loops[i]; p.events.removeAll { Int($0.pad) == pad }; storeLoop(i, p)
        }
        if load { importSample(sound.url, toPad: pad) }
        scheduleSave()
        return row
    }

    /// Drop a sound on a channel: that channel plays it from now on (its steps stay).
    func replaceRackSound(_ id: UUID, with sound: LibrarySound) {
        guard let current = rackChannels.first(where: { $0.id == id }) else { return }
        var rows = (state.workspaceChannels ?? []).filter { $0.pad != current.pad }
        rows.append(WorkspaceChannel(id: current.id, pad: current.pad, soundID: sound.id, name: sound.name, category: sound.type.rawValue))
        state.workspaceChannels = rows
        importSample(sound.url, toPad: current.pad)
        scheduleSave()
    }

    func renameRackChannel(_ id: UUID, _ name: String) {
        guard var row = rackChannels.first(where: { $0.id == id }) else { return }
        row.name = name.uppercased()
        var rows = (state.workspaceChannels ?? []).filter { $0.pad != row.pad }
        rows.append(row)
        state.workspaceChannels = rows
        scheduleSave()
    }

    /// Delete a channel: its steps go from every pattern and the pad goes back to the kit's sound
    /// (the row stays: the rack always shows all 12 pads).
    func removeRackChannel(_ id: UUID) {
        guard let pad = rackChannels.first(where: { $0.id == id })?.pad else { return }
        let rows = (state.workspaceChannels ?? []).filter { $0.pad != pad }
        state.workspaceChannels = rows.isEmpty ? nil : rows
        // From every pattern at once, then one rebuild.
        for k in loops.indices where k < state.editedLoops.count && loops[k].events.contains(where: { Int($0.pad) == pad }) {
            var p = loops[k]; p.events.removeAll { Int($0.pad) == pad }; state.editedLoops[k] = p
        }
        rebuildLoops()
        revertPad(pad)
        scheduleSave()
    }

    /// Back to the kit's own 12 channels.
    func resetRack() {
        state.workspaceChannels = nil
        for pad in 0..<Pad.count where state.pads[pad].sampleFile != nil { state.pads[pad] = PadSettings() }
        rebuildKit()
        scheduleSave()
    }

    /// GENERATE: a new pattern in a chosen style (the preset's style when nil).
    func randomizePattern(style chosen: String? = nil) {
        let style = chosen ?? PatternRandomizer.style(for: state.presetName)
        let length = loops.first?.lengthTicks ?? PatternData.ppq * 8
        let seed = UInt32.random(in: 2...UInt32.max)
        var s = state
        s.basePattern = PatternRandomizer.randomPattern(style: style, length: max(length, PatternData.ppq * 8), seed: seed)
        s.patternStyle = PatternBank.presets(in: style).first?.grooveStyle ?? patternStyle
        s.grooveSeed = seed
        s.editedLoops = Array(repeating: nil, count: Pad.count)
        state = s
        rebuildLoops()
        scheduleSave()
        readout = Readout(title: "GENERATE", value: "NEW \(style.uppercased()) PATTERN", time: Date())
    }

    // MARK: Loops

    /// The groove family the patterns come from (PRESETS set it; KITS don't).
    var patternStyle: GrooveStyle { state.patternStyle ?? kitDefinition.style }

    func rebuildLoops() {
        let generated = state.basePattern.map { GrooveGenerator.loops(fromMain: $0, style: patternStyle, seed: state.grooveSeed) }
            ?? GrooveGenerator.loops(style: patternStyle, seed: state.grooveSeed)
        var merged = generated
        for i in 0..<min(merged.count, state.editedLoops.count) {
            if let edit = state.editedLoops[i] { merged[i] = edit }
        }
        loops = merged
        engine.patternHandoff.publish(PatternSet(merged))
    }

    func setLoop(_ index: Int, _ data: PatternData?) {
        guard index >= 0 && index < Pad.count else { return }
        screenPattern = index
        storeLoop(index, data)
    }

    /// setLoop without making it the pattern on screen (recording, rack changes across every pattern).
    private func storeLoop(_ index: Int, _ data: PatternData?) {
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
        let fresh = GrooveGenerator.loops(style: patternStyle, seed: UInt32.random(in: 2...UInt32.max))
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
        for i in state.pads.indices {
            let file = state.pads[i].sampleFile
            state.pads[i] = PadSettings()
            state.pads[i].sampleFile = file
        }
        republishKit()
        state.presetName = "INIT"
        // INIT is silent: every loop starts blank until a pattern is loaded or drawn (Tyrone, Oct 16)
        state.basePattern = nil
        state.editedLoops = (0..<Pad.count).map { i in PatternData(name: "LOOP \(i + 1)", lengthTicks: PatternData.ppq * 4 * 2, events: []) }
        rebuildLoops()
        onStateReplaced?()
        readout = Readout(title: "PRESET", value: "INIT", time: Date())
    }

    /// PRESETS: load a pattern (and its tempo and swing). Sounds, mode and knobs stay.
    /// A new pattern opens on its MAIN A, the whole groove: left on a part of the last one (the
    /// INTRO or TOPS a LOOP pad picked) it played only some of its drums, or none.
    func loadPatternPreset(_ preset: PatternPreset) {
        let playingLoop = Int(meters.status[1])
        restore(preset.applying(to: state), keepPlaying: true)   // the beat carries on with the new pattern
        screenPattern = 0
        if !isPlaying { engine.send(KEvent(kind: .cue, a: 0)) }
        else if playingLoop != 0 { engine.send(KEvent(kind: .loopPad, a: 0)) }   // over to MAIN A at the bar
        readout = Readout(title: "PATTERN", value: preset.name, time: Date())
    }

    // MARK: Snap to scale (piano roll)

    func setScale(root: Int? = nil, name: String? = nil, snap: Bool? = nil) {
        if let root { state.scaleRoot = ((root % 12) + 12) % 12 }
        if let name { state.scaleName = name; if snap == nil { state.snapToScale = true } }   // picking a scale turns snap on, like FL
        if let snap { state.snapToScale = snap }
        scheduleSave()
    }

    // MARK: Randomize


    /// New notes for one channel of one loop; every other channel stays as it is.
    func randomizeChannel(loop: Int, pad: Int) {
        guard loops.indices.contains(loop) else { return }
        let style = PatternRandomizer.style(for: state.presetName)
        setLoop(loop, PatternRandomizer.randomChannel(loops[loop], pad: pad, style: style, seed: UInt32.random(in: 2...UInt32.max)))
    }

    func savePreset(as name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var s = state
        s.presetName = clean.uppercased()
        if KnockStore.saveUserPreset(UserPreset(name: clean, state: s)) {
            state.presetName = clean.uppercased()
            refreshLists()
            scheduleSave()
            readout = Readout(title: "PRESET SAVED", value: clean.uppercased(), time: Date())
        } else {
            notice = "Couldn't save the preset."
        }
    }

    func loadUserPreset(_ name: String) {
        guard let preset = KnockStore.loadUserPreset(name) else { notice = "Couldn't open the preset \(name)."; return }
        var s = preset.state
        s.midiMap = state.midiMap          // the MIDI controller setup isn't part of a sound preset
        s.midiCustomNotes = state.midiCustomNotes
        s.midiOut = state.midiOut               // MIDI out routing is a studio setting too
        s.midiOutChannels = state.midiOutChannels
        s.midiOutNotes = state.midiOutNotes
        restore(s, keepPlaying: true)
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

    /// keepPlaying: switching presets swaps the pattern under the running transport instead of stopping it.
    func restore(_ s: KnockState, keepPlaying: Bool = false) {
        let s = s.normalized()
        if !keepPlaying { engine.send(KEvent(kind: .allOff)) }
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
        let current = Int(meters.status[1])
        return current >= 0 && current < loops.count ? current : 0
    }

    func export(loop: Int, bars: Int, midi: Bool, mix: Bool, stems: Bool,
                completion: @escaping (Result<Exporter.Output, Error>) -> Void) {
        guard !loadingKit, kitSamples.count == Pad.count, loop >= 0, loop < loops.count else {
            completion(.failure(NSError(domain: "BreakBoss", code: 1, userInfo: [NSLocalizedDescriptionKey: "The kit is still loading."])))
            return
        }
        let exportRate: Double = 48_000
        let kit = KitBuffers(name: state.kitName, samples: kitSamples, settings: state.pads,
                             bassHz: kitDefinition.bassHz, renderSampleRate: exportRate)
        let patterns = PatternSet(loops)
        var params = [Float](repeating: 0, count: KParam.count)
        for p in KParam.allCases { params[p.rawValue] = value(p) }
        let tempo = liveTempo
        let name = "BreaKing \(state.kitName) \(loops[loop].name) \(Int(tempo.rounded()))BPM"
        let job = Exporter.Job(kit: kit, patterns: patterns, loop: loop, params: params,
                               tempo: tempo, bars: bars, sampleRate: exportRate, baseName: name)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Exporter.run(job, midi: midi, mix: mix, stems: stems) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
