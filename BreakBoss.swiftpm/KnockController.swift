// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import SwiftUI
import AVFoundation

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
    /// All preallocated audio slots (unused rows share a silent buffer).
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
    /// The instrument always keeps its twelve physical pads; only the open rack gates empty rows.
    private var rackWorkspaceIsOpen = false
    private var kitGeneration = 0
    private var sampleRequests: [Int: UUID] = [:]
    private let decodedBudget = RackDecodedBudget()
    private var loadedSources: [Int: String] = [:]
    private var kitBuildCancellation: RackBuildCancellation?
    private static let silentSample = SampleBuffer(left: [0], sampleRate: 48_000)
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
        }
        state = s.normalized()
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

    deinit { kitBuildCancellation?.cancel(); timers.forEach { $0.invalidate() } }

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
        if playMode == .loop {
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
        auditionChannel(slot: pad, velocity: velocity, semis: semis)
    }

    var mutedPads: [Bool] { Self.channelFlags(state.mutedPads) }
    var soloPads: [Bool] { Self.channelFlags(state.soloPads) }

    private static func channelFlags(_ flags: [Bool]?) -> [Bool] {
        Array(((flags ?? []) + Array(repeating: false, count: RackLimits.maxChannels)).prefix(RackLimits.maxChannels))
    }

    func toggleMute(_ pad: Int) {
        guard rackChannels.contains(where: { $0.slot == pad }) else { return }
        var m = mutedPads; m[pad].toggle(); state.mutedPads = m
        pushPadMask(); scheduleSave()
    }

    func toggleSolo(_ pad: Int) {
        guard rackChannels.contains(where: { $0.slot == pad }) else { return }
        var m = soloPads; m[pad].toggle(); state.soloPads = m
        pushPadMask(); scheduleSave()
    }

    /// FL-style: with any solo on, only soloed channels sound; mutes always silence.
    static func padMask(muted: [Bool], solo: [Bool]) -> UInt64 {
        let anySolo = solo.contains(true)
        var mask: UInt64 = 0
        for pad in 0..<min(RackLimits.maxChannels, max(muted.count, solo.count)) {
            let audible = (anySolo ? (pad < solo.count && solo[pad]) : true) && !(pad < muted.count && muted[pad])
            if audible { mask |= UInt64(1) << UInt64(pad) }
        }
        return mask
    }

    // MARK: MIDI out (multi-out)

    static let defaultMIDIOutChannels = Array(0..<Pad.count) + Array(repeating: -1, count: RackLimits.maxChannels - Pad.count)
    static let defaultMIDIOutNotes = Array(36..<(36 + Pad.count)) + Array(repeating: 60, count: RackLimits.maxChannels - Pad.count)
    /// On by default in the plug-in, so a DAW's armed MIDI track records the pads and pattern.
    var midiOutOn: Bool { state.midiOut ?? isPlugin }
    var midiOutChannels: [Int] { Self.midiRoutes(state.midiOutChannels, defaults: Self.defaultMIDIOutChannels, range: -1...15) }
    var midiOutNotes: [Int] { Self.midiRoutes(state.midiOutNotes, defaults: Self.defaultMIDIOutNotes, range: 0...127) }

    private static func midiRoutes(_ source: [Int]?, defaults: [Int], range: ClosedRange<Int>) -> [Int] {
        var routes = defaults
        for (i, value) in (source ?? []).prefix(RackLimits.maxChannels).enumerated() {
            routes[i] = max(range.lowerBound, min(range.upperBound, value))
        }
        return routes
    }

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
        var one = Array(repeating: -1, count: RackLimits.maxChannels)
        for pad in 0..<Pad.count { one[pad] = 9 }
        one[Pad.bass808.rawValue] = Pad.bass808.rawValue
        state.midiOutChannels = multi ? KnockController.defaultMIDIOutChannels : one
        state.midiOutNotes = multi ? KnockController.defaultMIDIOutNotes : [36, 38, 39, 37, 42, 46, 35, 56, 54, 45, 50, 49] + Array(repeating: 60, count: RackLimits.maxChannels - Pad.count)
        pushMIDIOut(); scheduleSave()
    }

    func pushMIDIOut() {
        let ch = midiOutChannels, notes = midiOutNotes
        for pad in 0..<RackLimits.maxChannels {
            let usesInstrumentFallback = !rackWorkspaceIsOpen && !rackChannels.contains(where: { $0.slot == pad })
            let channel = usesInstrumentFallback ? Self.defaultMIDIOutChannels[pad] : ch[pad]
            let note = usesInstrumentFallback ? Self.defaultMIDIOutNotes[pad] : notes[pad]
            engine.send(KEvent(kind: .midiOut, a: Int32(pad), value: channel < 0 ? -1 : Double(channel * 128 + note)))
        }
        engine.send(KEvent(kind: .midiOut, a: -1, value: midiOutOn ? 1 : 0))
    }

    private func pushPadMask() {
        var mask = Self.padMask(muted: mutedPads, solo: soloPads)
        if rackWorkspaceIsOpen {
            let active = rackChannels.reduce(UInt64(0)) { $0 | (UInt64(1) << UInt64($1.slot)) }
            mask &= active
        }
        engine.send(KEvent(kind: .padMask, mask: mask))
    }

    func setRackWorkspaceOpen(_ open: Bool) {
        rackWorkspaceIsOpen = open
        pushPadMask()
        pushMIDIOut()
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

    /// Faceplate: hold PLAY to record pads like an MPC (starts the pattern if it isn't playing);
    /// hold it again to stop recording. Works in ONE-SHOT and LOOP mode.
    func toggleRecordPads() {
        if recording {
            setRecording(false)
            readout = Readout(title: "RECORD", value: "OFF", time: Date())
        } else {
            setRecording(true)
            if !isPlaying { playPressed() }
            readout = Readout(title: "RECORD", value: "PLAY THE PADS", time: Date())
        }
    }

    func setRecording(_ on: Bool) {
        recording = on
        engine.send(KEvent(kind: .recordArm, a: on ? 1 : 0))
        _ = engine.collectRecorded()   // drop anything older
    }

    /// Plays the given pattern from its start (or keeps it going if it's already the one playing).
    func playPattern(_ loop: Int) {
        guard loops.indices.contains(loop) else { return }
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
                                       role: channelRole(Int(h.pad)))
            touched[loop] = p
        }
        for (loop, p) in touched { setLoop(loop, p) }
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
        engine.send(KEvent(kind: isPlaying ? .stop : .play))
    }

    // MARK: Dynamic channel rack

    var rackChannels: [RackChannel] { state.rackChannels ?? RackChannel.legacy }
    var rackChannelCount: Int { rackChannels.count }

    func channelRole(_ slot: Int) -> Int {
        rackChannels.first(where: { $0.slot == slot })?.role ?? slot.clamped(0, Pad.count - 1)
    }

    func channelName(_ slot: Int) -> String { padName(slot) }

    func channelBassHz(_ slot: Int) -> Float {
        rackChannels.first(where: { $0.slot == slot })?.sourceBassHz ?? kitDefinition.bassHz
    }

    func auditionChannel(slot: Int, velocity: Float = 0.85, semis: Float = 0) {
        guard (0..<Pad.count).contains(slot),
              !rackWorkspaceIsOpen || rackChannels.contains(where: { $0.slot == slot }) else { return }
        engine.send(KEvent(kind: .pad, a: Int32(slot), value: Double(velocity.clamped(0, 1)), semis: semis))
    }

    /// Reserves the row synchronously. The UI can spring its capsule open while audio decodes.
    @discardableResult
    func addBlankRackChannel(name: String = "EMPTY", role: Int = 0) -> Int? {
        guard let slot = RackChannel.availableSlot(in: rackChannels) else {
            notice = "The channel rack is full (12 sounds). Remove a channel or start a new empty rack to add another sound."
            return nil
        }
        var channels = rackChannels
        channels.append(RackChannel(slot: slot, name: name, role: role.clamped(0, Pad.count - 1), followsKit: false))
        state.rackChannels = channels
        state.pads[slot] = PadSettings()
        var mute = mutedPads; mute[slot] = false; state.mutedPads = mute
        var solo = soloPads; solo[slot] = false; state.soloPads = solo
        var routes = midiOutChannels; routes[slot] = -1; state.midiOutChannels = routes
        var notes = midiOutNotes; notes[slot] = 60; state.midiOutNotes = notes
        if state.stockPicks?.indices.contains(slot) == true { state.stockPicks![slot] = nil }
        stockSampleNames[slot] = nil
        loadedSources[slot] = nil
        if kitSamples.count == RackLimits.maxChannels { kitSamples[slot] = Self.silentSample }
        if kitSamples.count == RackLimits.maxChannels && !loadingKit { republishKit() }
        else { rebuildKit() }
        pushPadMask(); pushMIDIOut(); scheduleSave()
        return slot
    }

    @discardableResult
    func appendRackSound(_ sound: LibrarySound) -> Int? {
        guard let slot = addBlankRackChannel(name: sound.name, role: RackChannel.role(for: sound.type)) else { return nil }
        replaceRackSound(sound, slot: slot)
        return slot
    }

    @discardableResult
    func appendRackImport(_ url: URL) -> Int? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let slot = addBlankRackChannel(name: name, role: RackChannel.role(for: .guess(url.path))) else { return nil }
        importSample(url, toPad: slot)
        return slot
    }

    func replaceRackSound(_ sound: LibrarySound, slot: Int) {
        guard var channels = state.rackChannels,
              let index = channels.firstIndex(where: { $0.slot == slot }) else {
            if !rackWorkspaceIsOpen { loadRackSample(sound.url, toPad: slot) }
            return
        }
        channels[index].name = sound.name
        channels[index].role = RackChannel.role(for: sound.type)
        channels[index].libraryID = sound.id
        channels[index].stockFileName = sound.user ? nil : sound.url.lastPathComponent
        channels[index].sourceBassHz = sound.type == .bass && !sound.user
            ? KitLibrary.factory.first(where: { $0.name == sound.pack })?.bassHz : nil
        loadRackSample(sound.url, toPad: slot, metadata: channels[index])
    }

    func removeRackChannel(slot: Int) {
        guard rackChannels.contains(where: { $0.slot == slot }) else { return }
        engine.send(KEvent(kind: .channelOff, a: Int32(slot)))
        sampleRequests[slot] = nil
        // Materialise every loop before freeing the slot; a later row cannot inherit old notes.
        var edits = loops
        for i in edits.indices { edits[i].events.removeAll { Int($0.pad) == slot } }
        state.editedLoops = edits.map(Optional.some)
        state.basePattern?.events.removeAll { Int($0.pad) == slot }
        state.rackChannels = rackChannels.filter { $0.slot != slot }
        state.pads[slot] = PadSettings()
        var mute = mutedPads; mute[slot] = false; state.mutedPads = mute
        var solo = soloPads; solo[slot] = false; state.soloPads = solo
        var routes = midiOutChannels; routes[slot] = -1; state.midiOutChannels = routes
        var notes = midiOutNotes; notes[slot] = 60; state.midiOutNotes = notes
        if state.stockPicks?.indices.contains(slot) == true { state.stockPicks![slot] = nil }
        stockSampleNames[slot] = nil
        loadedSources[slot] = nil
        pushPadMask(); pushMIDIOut()
        rebuildKit()
        rebuildLoops()
        scheduleSave()
    }

    /// An explicit fresh start for the rack. Opening an existing project never removes sounds.
    /// Every pattern is cleared before slots can be reused, so newly dropped sounds start clean.
    func clearRackChannels() {
        resetRackChannels(to: [])
    }

    /// Restores the selected kit's twelve original sounds as a clean rack. Kept separate from
    /// switching kits, which deliberately preserves manually added sounds and existing notes.
    func restoreFactoryRackChannels() {
        resetRackChannels(to: RackChannel.legacy)
    }

    private func resetRackChannels(to channels: [RackChannel]) {
        setRecording(false)
        sampleRequests.removeAll()
        for channel in rackChannels { engine.send(KEvent(kind: .channelOff, a: Int32(channel.slot))) }
        var edits = loops
        for index in edits.indices { edits[index].events.removeAll() }
        state.editedLoops = edits.map(Optional.some)
        state.basePattern?.events.removeAll()
        state.rackChannels = channels
        state.pads = Array(repeating: PadSettings(), count: RackLimits.maxChannels)
        state.mutedPads = Array(repeating: false, count: RackLimits.maxChannels)
        state.soloPads = Array(repeating: false, count: RackLimits.maxChannels)
        state.midiOutChannels = channels.isEmpty ? Array(repeating: -1, count: RackLimits.maxChannels) : Self.defaultMIDIOutChannels
        state.midiOutNotes = channels.isEmpty ? Array(repeating: 60, count: RackLimits.maxChannels) : Self.defaultMIDIOutNotes
        state.stockPicks = Array(repeating: nil, count: RackLimits.maxChannels)
        stockSampleNames.removeAll()
        loadedSources.removeAll()
        kitSamples = Array(repeating: Self.silentSample, count: RackLimits.maxChannels)
        pushPadMask(); pushMIDIOut()
        rebuildKit()
        rebuildLoops()
        scheduleSave()
    }

    func moveRackChannel(from offsets: IndexSet, to destination: Int) {
        var channels = rackChannels
        let valid = IndexSet(offsets.filter { channels.indices.contains($0) })
        guard !valid.isEmpty else { return }
        channels.move(fromOffsets: valid, toOffset: destination.clamped(0, channels.count))
        state.rackChannels = channels
        scheduleSave()
    }

    private var kitRoles: [Int] {
        var roles = Array(0..<RackLimits.maxChannels)
        for channel in rackChannels { roles[channel.slot] = channel.role }
        return roles
    }

    private var kitChannelNames: [String] { (0..<RackLimits.maxChannels).map(channelName) }

    /// GENERATE affects the sequence on screen; its toggles independently opt in sounds/tempo.
    func generateRackPattern(loop: Int, style: String, updateSounds: Bool, updateTempo: Bool) {
        guard loops.indices.contains(loop), let preset = PatternBank.presets(in: style).randomElement() else { return }
        let length = loops[loop].lengthTicks
        if updateSounds,
           let kit = KitLibrary.factory.filter({ $0.style == preset.grooveStyle }).randomElement() { selectKit(kit) }
        let source = preset.pattern
        var events: [GrooveEvent] = []
        var start: Int32 = 0
        while start < length {
            for channel in rackChannels {
                for event in source.events where Int(event.pad) == channel.role && event.tick + start < length {
                    var mapped = event
                    mapped.pad = Int8(channel.slot)
                    mapped.tick += start
                    mapped.length = min(mapped.length, length - mapped.tick)
                    events.append(mapped)
                }
            }
            start += max(1, source.lengthTicks)
        }
        var pattern = PatternData(name: preset.name, lengthTicks: length, events: Array(events.prefix(4096)), humanize: loops[loop].humanize)
        pattern.sort()
        setLoop(loop, pattern)
        if updateTempo && !tempoIsExternal { setBPM(preset.bpm) }
        set(.bounce, preset.bounce, show: false)
        readout = Readout(title: "GENERATE", value: preset.name, time: Date())
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
        for channel in rackChannels where channel.usesKitSound { sampleRequests[channel.slot] = nil }
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
        let savedPads = KnockState.normalizedPads(kit.pads)
        var channels = rackChannels
        let savedChannels = RackChannel.normalized(kit.rackChannels)
        // A sound-only kit switch keeps added rows and their existing notes/settings intact.
        for channel in channels where channel.usesKitSound {
            sampleRequests[channel.slot] = nil
            if let saved = savedChannels.first(where: { $0.slot == channel.slot }) {
                state.pads[channel.slot] = savedPads[saved.slot]
                if let index = channels.firstIndex(where: { $0.slot == channel.slot }) {
                    channels[index].name = saved.name
                    channels[index].role = saved.role
                    channels[index].libraryID = saved.libraryID
                    channels[index].stockFileName = saved.stockFileName
                    channels[index].sourceBassHz = saved.sourceBassHz
                }
            }
        }
        // Bring back saved additional rows if the slot is free; never overwrite current extras.
        for channel in savedChannels where !channel.usesKitSound && !channels.contains(where: { $0.slot == channel.slot }) {
            channels.append(channel)
            state.pads[channel.slot] = savedPads[channel.slot]
        }
        state.rackChannels = RackChannel.normalized(channels)
        if let picks = kit.stockPicks { state.stockPicks = Array((picks + Array(repeating: nil, count: RackLimits.maxChannels)).prefix(RackLimits.maxChannels)) }
        pushPadMask(); pushMIDIOut()
        rebuildKit()
        rebuildLoops()
        readout = Readout(title: "KIT", value: state.kitName, time: Date())
        scheduleSave()
    }

    func saveKit(as name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let kit = UserKit(name: clean, baseKitID: state.kitID, soundSeed: state.soundSeed, pads: state.pads,
                          rackChannels: rackChannels, stockPicks: state.stockPicks)
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

    /// Renders changed sounds off the main thread; unchanged channels reuse immutable PCM.
    func rebuildKit() {
        synchronizeDecodedBudget()
        kitGeneration += 1
        let generation = kitGeneration
        kitBuildCancellation?.cancel()
        let cancellation = RackBuildCancellation()
        kitBuildCancellation = cancellation
        let s = state
        let def = KitLibrary.kit(id: s.kitID)
        let stock = stockLibrary
        let rate = engine.sampleRate > 0 ? engine.sampleRate : 48_000
        let previousSamples = kitSamples
        let previousSources = loadedSources
        let budget = decodedBudget
        loadingKit = true
        kitQueue.async { [weak self] in
            var samples = Array(repeating: KnockController.silentSample, count: RackLimits.maxChannels)
            var failed: [String] = []
            var stockNames: [Int: String] = [:]
            var sources: [Int: String] = [:]
            var reservations: [UUID] = []
            let activeChannels = RackChannel.normalized(s.rackChannels)
            // Empty rack slots still hold the selected kit for the original instrument surface.
            // Only visible rows are sequenced/gated while the rack is open.
            let audioChannels = (0..<RackLimits.maxChannels).map { slot in
                activeChannels.first(where: { $0.slot == slot })
                    ?? RackChannel(id: RackChannel.legacyID(slot: slot), slot: slot, role: slot, followsKit: true)
            }
            for channel in audioChannels {
                if cancellation.isCancelled {
                    for request in reservations { budget.cancel(request) }
                    return
                }
                let pad = channel.slot
                let role = channel.role
                let file = s.pads[pad].sampleFile
                let factorySample = channel.usesKitSound
                    ? KnockController.stockPick(s, pad: pad).flatMap({ stock.sample(kitID: $0, pad: role) })
                        ?? stock.sample(kitID: def.id, pad: role) : nil
                let source = file.map { "file:" + $0 }
                    ?? factorySample.map { "stock:" + $0.url.path }
                    ?? "synth:\(def.id):\(role):\(s.soundSeed):\(rate)"
                let url = file.map(SampleLoader.urlInSamples) ?? factorySample?.url
                do {
                    var buffer: SampleBuffer?
                    if previousSources[pad] == source && previousSamples.indices.contains(pad) {
                        buffer = previousSamples[pad]
                    }
                    if !channel.usesKitSound, buffer != nil || url != nil {
                        let request = UUID()
                        let bytes: Int
                        if let buffer { bytes = buffer.length * 2 * MemoryLayout<Float>.size }
                        else { bytes = try KnockController.decodedBytes(at: url!) }
                        guard budget.reserve(request: request, channel: channel.id, bytes: bytes) else {
                            throw RackSampleError.memoryBudget
                        }
                        reservations.append(request)
                    }
                    if buffer == nil, let url { buffer = try SampleLoader.load(url) }
                    if let buffer {
                        samples[pad] = buffer
                        sources[pad] = source
                        if file == nil, let factorySample { stockNames[pad] = factorySample.displayName }
                        continue
                    }
                } catch {
                    failed.append(file ?? factorySample?.displayName ?? channel.name ?? "Channel \(pad + 1)")
                }
                guard channel.usesKitSound else { continue }
                var recipe = def.pads[role]
                if s.soundSeed > 1 {
                    var rng = KRandom(seed: s.soundSeed &* 2_654_435_761 &+ UInt32(pad * 977))
                    recipe = recipe.varied(&rng)
                }
                samples[pad] = DrumSynth.render(recipe, sampleRate: rate, seed: s.soundSeed &+ UInt32(pad))
                sources[pad] = "synth:\(def.id):\(role):\(s.soundSeed):\(rate)"
            }
            DispatchQueue.main.async { [weak self, samples, failed, stockNames, sources, reservations] in
                defer { for request in reservations { budget.cancel(request) } }
                guard let self, generation == self.kitGeneration else { return }
                self.kitSamples = samples
                self.loadedSources = sources
                self.stockSampleNames = stockNames
                self.republishKit() // Apply edits made while decoding the kit.
                self.loadingKit = false
                if !failed.isEmpty {
                    self.notice = "Samples unavailable or beyond the 64 MiB added-channel budget: \(failed.joined(separator: ", ")). Added rows stay silent; original factory rows use backups."
                } else if let failure = stock.failure {
                    self.notice = "\(failure) Using synthesized sounds."
                }
            }
        }
    }

    private enum RackSampleError: LocalizedError {
        case memoryBudget
        var errorDescription: String? {
            "This sound would exceed the 64 MiB decoded-audio budget for added channels. Remove a sound or use a shorter sample."
        }
    }

    /// Read only the file header before reserving space; SampleLoader performs full validation.
    private static func decodedBytes(at url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let audio = try AVAudioFile(forReading: url)
        guard audio.length > 0, audio.length <= Int64(RackLimits.extraDecodedByteLimit / 8) else {
            throw RackSampleError.memoryBudget
        }
        return Int(audio.length) * 2 * MemoryLayout<Float>.size
    }

    private func synchronizeDecodedBudget() {
        var costs: [UUID: Int] = [:]
        for channel in rackChannels where !channel.usesKitSound && kitSamples.indices.contains(channel.slot) {
            let sample = kitSamples[channel.slot]
            if sample.length > 1 { costs[channel.id] = sample.length * 2 * MemoryLayout<Float>.size }
        }
        decodedBudget.synchronize(costs)
    }

    /// Same sounds, new pad settings (level, pan, tune, decay, filter, reverse): instant.
    private func republishKit() {
        guard kitSamples.count == RackLimits.maxChannels else { rebuildKit(); return }
        synchronizeDecodedBudget()
        let kit = KitBuffers(name: state.kitName, samples: kitSamples, settings: state.pads,
                             bassHz: kitDefinition.bassHz, renderSampleRate: engine.sampleRate,
                             roles: kitRoles, channelNames: kitChannelNames)
        engine.kitHandoff.publish(kit)
    }

    // MARK: Pad editor

    func setPadSettings(_ pad: Int, _ settings: PadSettings) {
        guard state.pads.indices.contains(pad),
              !rackWorkspaceIsOpen || rackChannels.contains(where: { $0.slot == pad }) else { return }
        let needsReload = settings.sampleFile != state.pads[pad].sampleFile
        state.pads[pad] = settings
        if needsReload { rebuildKit() } else { republishKit() }
        scheduleSave()
    }

    /// Puts an audio file on a channel (copied into Samples before publication).
    func importSample(_ url: URL, toPad pad: Int) { loadRackSample(url, toPad: pad) }

    private func loadRackSample(_ url: URL, toPad pad: Int, metadata: RackChannel? = nil) {
        guard state.pads.indices.contains(pad) else { return }
        let active = rackChannels.first(where: { $0.slot == pad })
        guard active != nil || !rackWorkspaceIsOpen else { return }
        let channel = active ?? RackChannel(id: RackChannel.legacyID(slot: pad), slot: pad, role: pad, followsKit: true)
        let request = UUID()
        sampleRequests[pad] = request
        let budget = decodedBudget
        kitQueue.async { [weak self] in
            do {
                let name = try SampleLoader.copyIntoSamples(url)
                let localURL = SampleLoader.urlInSamples(name)
                if !channel.usesKitSound {
                    let bytes = try KnockController.decodedBytes(at: localURL)
                    guard budget.reserve(request: request, channel: channel.id, bytes: bytes) else {
                        throw RackSampleError.memoryBudget
                    }
                }
                let buffer = try SampleLoader.load(localURL)
                DispatchQueue.main.async { [weak self] in
                    defer { budget.cancel(request) }
                    guard let self, self.sampleRequests[pad] == request else { return }
                    let index = self.state.rackChannels?.firstIndex(where: { $0.slot == pad && $0.id == channel.id })
                    // A home-pad import may finish with no rack row. It must never overwrite a
                    // newly dropped row that claimed the same slot while decoding was in flight.
                    guard active != nil ? index != nil : !self.rackChannels.contains(where: { $0.slot == pad }) else { return }
                    self.sampleRequests[pad] = nil
                    self.state.pads[pad].sampleFile = name
                    if let index, let metadata { self.state.rackChannels![index] = metadata }
                    else if let index {
                        self.state.rackChannels![index].name = (name as NSString).deletingPathExtension
                        self.state.rackChannels![index].libraryID = nil
                        self.state.rackChannels![index].stockFileName = nil
                        self.state.rackChannels![index].sourceBassHz = nil
                    }
                    self.stockSampleNames[pad] = nil
                    self.loadedSources[pad] = "file:" + name
                    if self.kitSamples.count != RackLimits.maxChannels {
                        self.kitSamples = Array(repeating: Self.silentSample, count: RackLimits.maxChannels)
                    }
                    self.kitSamples[pad] = buffer
                    self.synchronizeDecodedBudget()
                    if self.loadingKit { self.rebuildKit() }
                    else { self.republishKit() }
                    self.readout = Readout(title: "CHANNEL \(pad + 1)", value: self.channelName(pad).uppercased(), time: Date())
                    self.scheduleSave()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    defer { budget.cancel(request) }
                    guard let self, self.sampleRequests[pad] == request else { return }
                    self.sampleRequests[pad] = nil
                    if self.state.pads[pad].sampleFile == nil,
                       let index = self.state.rackChannels?.firstIndex(where: { $0.slot == pad && $0.id == channel.id }),
                       !channel.usesKitSound {
                        self.state.rackChannels![index].name = "LOAD FAILED · " + (metadata?.name ?? channel.name ?? url.lastPathComponent)
                    }
                    self.notice = error.localizedDescription
                }
            }
        }
    }

    func revertPad(_ pad: Int) {
        guard state.pads.indices.contains(pad) else { return }
        let index = state.rackChannels?.firstIndex(where: { $0.slot == pad })
        guard index != nil || !rackWorkspaceIsOpen else { return }
        sampleRequests[pad] = nil
        state.pads[pad] = PadSettings()
        if let index {
            state.rackChannels![index].name = nil
            state.rackChannels![index].libraryID = nil
            state.rackChannels![index].stockFileName = nil
            state.rackChannels![index].sourceBassHz = nil
        }
        rebuildKit()
        scheduleSave()
    }

    func padName(_ pad: Int) -> String {
        guard state.pads.indices.contains(pad) else { return "EMPTY" }
        let channel = rackChannels.first(where: { $0.slot == pad })
        if let name = channel?.name, !name.isEmpty { return name }
        if let f = state.pads[pad].sampleFile { return (f as NSString).deletingPathExtension }
        if let name = stockSampleNames[pad] { return name }
        guard let channel else { return kitDefinition.pads[pad].label }
        return channel.usesKitSound ? kitDefinition.pads[channel.role].label : "EMPTY"
    }

    // MARK: Loops

    /// The groove family the patterns come from (PRESETS set it; KITS don't).
    var patternStyle: GrooveStyle { state.patternStyle ?? kitDefinition.style }

    /// Factory patterns describe instrument roles; the rack is free to put those instruments
    /// in any slot (and to use the same role more than once). Edited patterns already contain
    /// stable audio slots and are applied after this mapping.
    private func mappingPatternToRack(_ source: PatternData) -> PatternData {
        let channels = rackChannels
        if channels.count == Pad.count && channels.allSatisfy({ $0.slot == $0.role }) { return source }
        var mapped = source
        mapped.events = channels.flatMap { channel in
            source.events.filter { Int($0.pad) == channel.role }.map { event in
                var event = event
                event.pad = Int8(channel.slot)
                return event
            }
        }
        mapped.sort()
        return mapped
    }

    func rebuildLoops() {
        let generated = state.basePattern.map { GrooveGenerator.loops(fromMain: $0, style: patternStyle, seed: state.grooveSeed) }
            ?? GrooveGenerator.loops(style: patternStyle, seed: state.grooveSeed)
        var merged = generated.map(mappingPatternToRack)
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
        guard loop >= 0 && loop < loops.count, rackChannels.contains(where: { $0.slot == pad }) else { return }
        var p = loops[loop]
        let lo = Int32(step) * PatternData.stepTicks - 6
        let hi = Int32(step) * PatternData.stepTicks + 18
        let before = p.events.count
        p.events.removeAll { Int($0.pad) == pad && $0.tick >= lo && $0.tick < hi }
        if p.events.count == before {
            let tick = Int32(step) * PatternData.stepTicks
            if channelRole(pad) == Pad.bass808.rawValue {
                p.events.append(GrooveEvent(tick: tick, pad: Int8(pad), velocity: 0.9, semis: 0, length: PatternData.stepTicks * 2))
            } else {
                p.events.append(GrooveEvent(tick: tick, pad: Int8(pad), velocity: channelRole(pad) == Pad.hat.rawValue ? 0.7 : 0.9))
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
        setLoop(index, mappingPatternToRack(fresh[index]))
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
        onStateReplaced?()
        readout = Readout(title: "PRESET", value: "INIT", time: Date())
    }

    /// PRESETS: load a pattern (and its tempo and swing). Sounds, mode and knobs stay.
    func loadPatternPreset(_ preset: PatternPreset) {
        restore(preset.applying(to: state), keepPlaying: true)   // the beat carries on with the new pattern
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

    /// A new pattern in the current preset's style, built from that style's presets.
    func randomizePattern() {
        let style = PatternRandomizer.style(for: state.presetName)
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
        readout = Readout(title: "RANDOMIZE", value: "NEW \(style.uppercased()) PATTERN", time: Date())
    }

    /// New notes for one channel of one loop; every other channel stays as it is.
    func randomizeChannel(loop: Int, pad: Int) {
        guard loops.indices.contains(loop), rackChannels.contains(where: { $0.slot == pad }) else { return }
        let style = PatternRandomizer.style(for: state.presetName)
        let role = channelRole(pad)
        let source = PatternData(name: loops[loop].name, lengthTicks: loops[loop].lengthTicks, events: [])
        let fresh = PatternRandomizer.randomChannel(source, pad: role, style: style, seed: UInt32.random(in: 2...UInt32.max))
        var pattern = loops[loop]
        pattern.events.removeAll { Int($0.pad) == pad }
        pattern.events += fresh.events.map { event in var event = event; event.pad = Int8(pad); return event }
        pattern.sort()
        setLoop(loop, pattern)
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
        sampleRequests.removeAll()
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
        guard !loadingKit, kitSamples.count == RackLimits.maxChannels, loop >= 0, loop < loops.count else {
            completion(.failure(NSError(domain: "BreakBoss", code: 1, userInfo: [NSLocalizedDescriptionKey: "The kit is still loading."])))
            return
        }
        let exportRate: Double = 48_000
        let kit = KitBuffers(name: state.kitName, samples: kitSamples, settings: state.pads,
                             bassHz: kitDefinition.bassHz, renderSampleRate: exportRate,
                             roles: kitRoles, channelNames: kitChannelNames)
        let patterns = PatternSet(loops)
        var params = [Float](repeating: 0, count: KParam.count)
        for p in KParam.allCases { params[p.rawValue] = value(p) }
        let tempo = liveTempo
        let name = "BreakBoss \(state.kitName) \(loops[loop].name) \(Int(tempo.rounded()))BPM"
        let job = Exporter.Job(kit: kit, patterns: patterns, loop: loop, params: params,
                               tempo: tempo, bars: bars, sampleRate: exportRate, baseName: name)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Exporter.run(job, midi: midi, mix: mix, stems: stems) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
