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
    /// The multisampled pads of the loaded kit (each tied to the kitSamples buffer it was loaded with).
    private var kitLayers: [VelocityLayers?] = []
    /// What the engine plays: the kit's sounds with each track's SAMPLER page computed in.
    @Published private(set) var playedSamples: [SampleBuffer] = []
    /// Each track's computed sound, and what it was computed from.
    private var samplerCache: [Int: (raw: SampleBuffer, key: SamplerOffline, buffer: SampleBuffer)] = [:]
    private var samplerWorking = false
    /// Run once the kit being decoded is in the engine (a sound picked while a kit was loading).
    private var afterKitLoad: [() -> Void] = []
    /// Counts each pad's sound picks, so only the latest one loads.
    private var padPicks = [UInt32](repeating: 0, count: Pad.count)
    /// Names for successfully loaded factory samples; these never become device-local imports.
    @Published private(set) var stockSampleNames: [Int: String] = [:]
    /// The kit's EMPTY pads that have no sound of their own (silent, shown as EMPTY).
    @Published private(set) var emptyPads: Set<Int> = []
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
        engine.standalone = !isPlugin
        var s = KnockState()
        for p in KParam.allCases { s.values[p.id] = p.defaultValue }
        if !isPlugin, let data = UserDefaults.standard.data(forKey: KnockController.sessionKey),
           let saved = try? JSONDecoder().decode(KnockState.self, from: data) {
            s = saved.normalized()
            s.values[KParam.output.id] = KParam.output.defaultValue   // Tyrone, Oct 31: OUTPUT is always at max (0 dB)
            // Tyrone, Oct 19: every volume back to 100% once, now that only the SAMPLER's VOL goes past it
            let reset = "breakboss.volumesAtUnity"
            if !UserDefaults.standard.bool(forKey: reset) {
                for i in s.pads.indices { s.pads[i].level = 0.8 }
                s.values[KParam.output.id] = KParam.output.defaultValue
                UserDefaults.standard.set(true, forKey: reset)
            }
        } else {
            // a fresh start is silent: blank loops until a pattern is loaded or drawn
            s.editedLoops = (0..<Pad.count).map { i in PatternData(name: "LOOP \(i + 1)", lengthTicks: PatternData.ppq * 4 * 2, events: []) }
        }
        state = s
        pushAllToEngine()
        refreshLists()
        // Once: MY SOUNDS copies of the levelled stock sounds go back to the originals (before the kit loads).
        let restoreKey = "restoredStockCopies83"
        if !UserDefaults.standard.bool(forKey: restoreKey) {
            let stock = stockLibrary.allSounds.map(\.url)
            kitQueue.async {
                let n = SampleLoader.restoreStockCopies(stock)
                if n > 0 { BugLog.shared.note("Reset \(n) saved copies of stock sounds to the originals") }
                UserDefaults.standard.set(true, forKey: restoreKey)
            }
        }
        rebuildKit()
        rebuildLoops()

        // Hand old kits / loops back to the main thread to be freed; follow host automation.
        let collect = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.engine.kitHandoff.collect()
            self?.engine.patternHandoff.collect()
            self?.engine.previewHandoff.collect()
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
        outputToMax()
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

    /// Tyrone, Oct 31: "output volume should always be max at 10 for every preset". Every preset,
    /// kit, mode change and launch puts OUTPUT back at the top (0 dB), knob and sound together.
    func outputToMax() { set(.output, KParam.output.defaultValue, show: false) }

    /// A track's own FX knob on Face 2 (in the current mode): its insert, not the main chain.
    func trackFX(_ pad: Int, _ p: KParam) -> Float {
        guard state.pads.indices.contains(pad) else { return TrackFX.neutral(p) }
        return state.pads[pad].fxValue(p, mode)
    }

    func setTrackFX(_ pad: Int, _ p: KParam, _ v: Float) {
        guard state.pads.indices.contains(pad) else { return }
        var settings = state.pads[pad]
        settings.setFX(p, mode, v)
        guard settings != state.pads[pad] else { return }
        setPadSettings(pad, settings)
    }

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
    /// Only the AUv3 inside a DAW follows a host; the standalone app keeps its own tempo.
    var tempoIsExternal: Bool {
        isPlugin && (value(.tempoSync) > 0.5 || value(.followDAW) > 0.5) && (meters.status[5] > 0 || meters.status[6] > 0)
    }

    func setBPM(_ bpm: Double) {
        let b = (bpm * 10).rounded() / 10
        state.bpm = b.clamped(40, 240)
        engine.setTempo(state.bpm)
        // a sampler stretched to the tempo (TIME: Project tempo, beats, bars) is stretched again
        if state.pads.contains(where: { $0.sampler?.offline(bpm: 0).map { $0.stretch != .resample && $0.time.followsTempo } ?? false }) { republishKit() }
        scheduleSave()
    }

    // MARK: Pads and transport

    /// `held`: a finger that stays on the pad until padRelease (Face 1's pads), so the pad's NOTE
    /// REPEAT can run while it's down. Buttons that just play the pad leave it false.
    func padDown(_ pad: Int, velocity: Float, held: Bool = false) {
        guard pad >= 0 && pad < Pad.count else { return }
        guard powerOn else { readout = Readout(title: "POWER", value: "OFF", time: Date()); return }
        if playMode == .loop {
            screenPattern = pad
            engine.send(KEvent(kind: .loopPad, a: Int32(pad), value: Double(velocity)))
            let title = pad < loops.count ? loops[pad].name : LoopSlot(rawValue: pad)?.title ?? ""
            readout = Readout(title: "LOOP \(pad + 1)", value: title, time: Date())
        } else {
            engine.send(KEvent(kind: held ? .padHold : .pad, a: Int32(pad), value: Double(velocity)))
            readout = Readout(title: "PAD \(pad + 1)", value: padName(pad).uppercased(), time: Date())
        }
    }

    // MARK: Drum roll

    /// Plays a pad's sound in any mode (drum roll ▶ buttons, previews). While RECORD is armed
    /// and the pattern runs, the engine also writes the hit into the pattern.
    func auditionPad(_ pad: Int, velocity: Float = 0.85, semis: Float = 0, gain: Float = 1) {
        guard pad >= 0 && pad < Pad.count else { return }
        if pad == Pad.bass808.rawValue {
            engine.send(KEvent(kind: .bass, a: Int32(semis.rounded()), value: Double(velocity), gain: gain))
        } else {
            engine.send(KEvent(kind: .pad, a: Int32(pad), value: Double(velocity), gain: gain))
        }
    }

    /// The sound library's preview volume (0…1, 1 = as loud as the track plays): how loud a sound
    /// picked in the library is heard. Kept on this device.
    static let previewVolumeKey = "libraryPreviewVolume"
    var previewVolume: Float {
        get { UserDefaults.standard.object(forKey: Self.previewVolumeKey) == nil ? 1 : UserDefaults.standard.float(forKey: Self.previewVolumeKey).clamped(0, 1) }
        set { UserDefaults.standard.set(newValue.clamped(0, 1), forKey: Self.previewVolumeKey) }
    }

    /// A library preview: the track's sound at the preview volume.
    func previewPad(_ pad: Int) { auditionPad(pad, gain: previewVolume) }

    /// The sound last previewed from the library (the preview fader plays it again at its new level).
    private(set) var previewedSound: SampleBuffer?
    private var previewedURL: URL?
    /// A tap on the picked sound in the library (Tyrone, Oct 20): hear it at the preview volume without
    /// putting it on any track (dragging it onto the rack does that). Each tap plays it again from the
    /// top; the same sound is not loaded twice.
    func previewSound(_ sound: LibrarySound) {
        let url = sound.url
        if url == previewedURL, let buffer = previewedSound {
            engine.previewHandoff.publish(PreviewSound(buffer, gain: previewVolume))
            return
        }
        kitQueue.async { [weak self] in
            guard let buffer = try? SampleLoader.load(url) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.previewedSound = buffer
                self.previewedURL = url
                self.engine.previewHandoff.publish(PreviewSound(buffer, gain: self.previewVolume))
            }
        }
    }
    /// The preview fader let go: the last previewed sound again at the new level, or the selected track.
    func previewAgain(orPad pad: Int?) {
        if let buffer = previewedSound { engine.previewHandoff.publish(PreviewSound(buffer, gain: previewVolume)) }
        else if let pad { previewPad(pad) }
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
    /// ONE TRACK: every pad on MIDI channel 1, pads 1-12 on notes 36-47 (the 808 chromatic on 48-84),
    /// so the whole kit records onto one DAW track and a note drawn on a row plays that row's pad.
    static let oneTrackMIDIOutChannels = Array(repeating: 0, count: Pad.count)
    /// On by default in the plug-in, so a DAW's armed MIDI track records the pads and pattern.
    var midiOutOn: Bool { state.midiOut ?? isPlugin }
    /// The plug-in starts on ONE TRACK (Tyrone, Oct 26: record everything onto the one Logic track);
    /// the app keeps multi-out on its MIDI port.
    private var midiOutDefaultChannels: [Int] { isPlugin ? KnockController.oneTrackMIDIOutChannels : KnockController.defaultMIDIOutChannels }
    var midiOutChannels: [Int] { (state.midiOutChannels ?? midiOutDefaultChannels).count == Pad.count ? state.midiOutChannels ?? midiOutDefaultChannels : midiOutDefaultChannels }
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
    func setMIDIOutOneTrack() {
        state.midiOutChannels = KnockController.oneTrackMIDIOutChannels
        state.midiOutNotes = KnockController.defaultMIDIOutNotes
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
        } else { padDown(pad, velocity: velocity, held: true) }
    }

    func gateUp(_ pad: Int) {
        engine.send(KEvent(kind: .loopGateOff, a: Int32(2048 + pad)))
        padRelease(pad)
    }

    /// The finger came off a pad (or the touch was cancelled): its NOTE REPEAT stops. Safe to send
    /// for a pad that isn't repeating.
    func padRelease(_ pad: Int) {
        guard (0..<Pad.count).contains(pad) else { return }
        engine.send(KEvent(kind: .padLift, a: Int32(pad)))
    }

    /// True when holding this pad repeats it (ONE-SHOT with the pad's NOTE REPEAT on), so the hold
    /// doesn't open the pad's window.
    func padRepeats(_ pad: Int) -> Bool {
        playMode != .loop && state.pads.indices.contains(pad) && state.pads[pad].noteRepeat
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
            if let pick = pool.randomElement() {
                picks[pad] = pick
                state.pads[pad] = state.pads[pad].freshSound()             // a new sound comes in as itself
            }
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
        outputToMax()
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
        state.stockPicks = nil                 // a saved kit plays its own sounds, not the last dice roll's (an 808 in another key)
        state.workspaceChannels = nil          // the rack shows the kit's sounds, the same as the pads
        outputToMax()
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
            var layers: [VelocityLayers?] = Array(repeating: nil, count: Pad.count)
            var failed: [String] = []
            var stockNames: [Int: String] = [:]
            var empties: Set<Int> = []
            for pad in 0..<Pad.count {
                if let file = s.pads[pad].sampleFile {
                    if let buffer = try? SampleLoader.load(SampleLoader.urlInSamples(file)) {
                        samples.append(KnockController.centered(buffer, pad: pad))
                        continue
                    }
                    failed.append(file)
                } else if let sample = KnockController.stockPick(s, pad: pad).flatMap({ stock.sample(kitID: $0, pad: pad) })
                            ?? stock.sample(kitID: def.id, pad: pad) {
                    if let loaded = try? SampleLoader.load(sample.url) {
                        let buffer = KnockController.centered(loaded, pad: pad)
                        samples.append(buffer)
                        stockNames[pad] = sample.displayName
                        if let spec = stock.layers(for: sample) {
                            // Every layer or none: a file that won't load leaves the pad on its one sample.
                            let hits = spec.map { layer in layer.urls.compactMap { (try? SampleLoader.load($0)).map { KnockController.centered($0, pad: pad) } } }
                            if zip(hits, spec).allSatisfy({ $0.0.count == $0.1.urls.count }) {
                                layers[pad] = VelocityLayers(source: buffer, tops: spec.map(\.top), hits: hits)
                            }
                        }
                        continue
                    }
                    failed.append(sample.displayName)
                }
                // an EMPTY factory pad plays nothing: one silent frame, not a synthesized stand-in
                // (also when an old dice pick names a kit with no sound there: it stays EMPTY, Tyrone, Oct 26)
                if s.pads[pad].sampleFile == nil, stock.isEmpty(kitID: def.id, pad: pad) {
                    samples.append(SampleBuffer(left: [0], sampleRate: rate))
                    empties.insert(pad)
                    continue
                }
                var recipe = def.pads[pad]
                if s.soundSeed > 1 {
                    var rng = KRandom(seed: s.soundSeed &* 2_654_435_761 &+ UInt32(pad * 977))
                    recipe = recipe.varied(&rng)
                }
                samples.append(KnockController.centered(DrumSynth.render(recipe, sampleRate: rate, seed: s.soundSeed &+ UInt32(pad)), pad: pad))
            }
            DispatchQueue.main.async { [weak self, samples, layers, failed, stockNames, empties] in
                guard let self, generation == self.kitGeneration else { return }
                self.kitSamples = samples
                self.kitLayers = layers
                self.stockSampleNames = stockNames
                self.emptyPads = empties
                self.republishKit() // Apply edits made while decoding the kit.
                self.loadingKit = false
                let waiting = self.afterKitLoad
                self.afterKitLoad = []
                waiting.forEach { $0() }
                if !failed.isEmpty {
                    self.notice = "Samples unavailable: \(failed.joined(separator: ", ")). Using synthesized sounds."
                } else if let failure = stock.failure {
                    self.notice = "\(failure) Using synthesized sounds."
                }
            }
        }
    }

    /// The multisampled pads that play their layers: a pad still on the sample its layers came
    /// with, and with no SAMPLER page edits (an edited sound is that one sample).
    private var playedLayers: [VelocityLayers?] {
        (0..<Pad.count).map { pad in
            guard pad < kitLayers.count, pad < kitSamples.count, let layers = kitLayers[pad],
                  layers.source === kitSamples[pad], state.pads[pad].sampleFile == nil,
                  state.pads[pad].sampler?.offline(bpm: state.bpm) == nil else { return nil }
            return layers
        }
    }

    /// Same sounds, new pad settings (level, pan, tune, decay, filter, reverse): instant. A track
    /// whose SAMPLER page changed keeps its last computed sound until the new one is ready.
    private func republishKit() {
        guard kitSamples.count == Pad.count else { rebuildKit(); return }
        var samples = kitSamples
        var todo: [(pad: Int, raw: SampleBuffer, key: SamplerOffline)] = []
        for pad in 0..<Pad.count {
            guard let key = state.pads[pad].sampler?.offline(bpm: state.bpm) else { samplerCache[pad] = nil; continue }
            let raw = kitSamples[pad]
            if let c = samplerCache[pad], c.raw === raw {
                samples[pad] = c.buffer
                if c.key == key { continue }
            }
            todo.append((pad, raw, key))
        }
        playedSamples = samples
        let kit = KitBuffers(name: state.kitName, samples: samples, settings: state.pads,
                             bassHz: kitDefinition.bassHz, renderSampleRate: engine.sampleRate, layers: playedLayers)
        engine.kitHandoff.publish(kit)
        if !todo.isEmpty { computeSamplers(todo) }
    }

    /// Computes the SAMPLER pages (declick, tools, trims, fades, stretching) off the main thread, one
    /// batch at a time; the next publish picks up anything that changed meanwhile.
    private func computeSamplers(_ todo: [(pad: Int, raw: SampleBuffer, key: SamplerOffline)]) {
        guard !samplerWorking else { return }
        samplerWorking = true
        let rate = engine.sampleRate > 0 ? engine.sampleRate : 48_000
        kitQueue.async { [weak self] in
            let done = todo.map { job in (job.pad, job.raw, job.key, SamplerProcessor.process(job.raw, job.key, engineRate: rate)) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.samplerWorking = false
                for d in done { self.samplerCache[d.0] = (raw: d.1, key: d.2, buffer: d.3) }
                self.republishKit()
            }
        }
    }

    // MARK: The SAMPLER window (one per track)

    /// A track's sampler: the defaults until something on it is changed.
    func sampler(_ pad: Int) -> SamplerSettings {
        guard (0..<Pad.count).contains(pad) else { return SamplerSettings() }
        return state.pads[pad].sampler ?? SamplerSettings()
    }

    func setSampler(_ pad: Int, _ settings: SamplerSettings) {
        guard (0..<Pad.count).contains(pad) else { return }
        var ps = state.pads[pad]
        ps.sampler = settings
        setPadSettings(pad, ps)
    }

    /// The sound the track plays now (with its SAMPLE page applied).
    func playedSample(_ pad: Int) -> SampleBuffer? {
        if playedSamples.indices.contains(pad) { return playedSamples[pad] }
        return kitSamples.indices.contains(pad) ? kitSamples[pad] : nil
    }

    /// The sampler's keyboard: the track's sound `semis` from its root note.
    func auditionPitched(_ pad: Int, semis: Int, velocity: Float = 0.85) {
        guard (0..<Pad.count).contains(pad) else { return }
        let st = semis.clamped(-60, 60)
        if pad == Pad.bass808.rawValue {
            engine.send(KEvent(kind: .bass, a: Int32(st), value: Double(velocity)))
        } else {
            engine.send(KEvent(kind: .padPitched, a: Int32(pad + 128 * (st + 64)), value: Double(velocity)))
        }
    }

    /// One hit of the track as it plays now (its sound, PAN / VOL, the SAMPLER page), rendered offline
    /// in a quiet engine: what the UI tests read to hear whether a control changed the sound.
    /// (A pad hit: with the Volume envelope on, its release starts after a 16th.)
    func probeTrack(_ pad: Int) -> String {
        guard (0..<Pad.count).contains(pad) else { return "" }
        let rate = 48_000.0
        let samples = playedSamples.count == Pad.count ? playedSamples : kitSamples
        guard samples.count == Pad.count else { return "no kit" }
        let e = KnockEngine()
        e.prepare(sampleRate: rate, maxFrames: 128)
        let quiet: [(KParam, Float)] = [(.playMode, 0), (.followDAW, 0), (.tempoSync, 0), (.velocity, 0), (.boost, 0), (.clipper, 0),
                                        (.clipDrive, 0), (.gatedReverb, 0), (.textureDelay, 0), (.tighten, 0), (.pitch, 0.5), (.tune, 0.5)]
        for (p, v) in quiet { e.setParam(p, v) }
        e.kitHandoff.publish(KitBuffers(name: "PROBE", samples: samples, settings: state.pads, bassHz: kitDefinition.bassHz,
                                        renderSampleRate: rate, layers: playedLayers))
        e.send(KEvent(kind: .padPitched, a: Int32(pad + 128 * 64), value: 1))
        let blocks = Int(1.5 * rate / 128)
        var l2: Double = 0, r2: Double = 0, early: Double = 0, late: Double = 0, diff: Double = 0, quarter: Double = 0
        var crossings = 0, last: Float = 0
        var left = [Float](repeating: 0, count: 128), right = left
        for b in 0..<blocks {
            for i in 0..<128 { left[i] = 0; right[i] = 0 }
            left.withUnsafeMutableBufferPointer { l in right.withUnsafeMutableBufferPointer { r in e.render(frames: 128, left: l.baseAddress!, right: r.baseAddress!, host: nil) } }
            for i in 0..<128 {
                let x = Double(left[i]), y = Double(right[i])
                l2 += x * x; r2 += y * y
                if b < blocks / 8 { early += x * x + y * y } else if b > blocks / 2 { late += x * x + y * y }
                // crossings and brightness on the mono sum, so a hard-panned sound still counts
                let m = (left[i] + right[i]) * 0.5
                if b < blocks / 4 {
                    if (m >= 0) != (last >= 0) { crossings += 1 }
                    diff += Double((m - last) * (m - last))
                    quarter += Double(m * m)
                }
                last = m
            }
        }
        // what the engine was given, so a probe that didn't change can be told from a setting that didn't arrive
        let sm = state.pads.indices.contains(pad) ? state.pads[pad].sampler : nil
        let lv = sm?.lfo(.volume), ev = sm?.envelope(.volume)
        let given = String(format: " lfoV=%.2f/%d/%.2f envV=%d/%d/%.2f max=%d cut=%d", lv?.amount ?? 0, lv?.shape ?? 0, lv?.speed ?? 0,
                           (ev?.on ?? false) ? 1 : 0, (ev?.tempo ?? false) ? 1 : 0, ev?.attack ?? 0, sm?.polyMax ?? -1, sm?.cutGroup ?? -1)
        return String(format: "L=%.4f R=%.4f early=%.4f late=%.4f zc=%d hf=%.6f", l2, r2, early, late, crossings, diff / max(quarter, 1e-12)) + given
    }

    /// Audio copied in a SAMPLER window's waveform (any track can paste it).
    @Published var sampleClipboard: SampleClip?
    /// A waveform edit is being saved.
    @Published var sampleEditing = false

    /// Edits the sound the track plays now and loads the result: a new WAV in Samples/Edits (the
    /// SAMPLE page's computed settings are in it, so they go back to neutral; the loop points and
    /// markers move with the audio). `done` gets the file's name, or nil if it couldn't be saved.
    func editSample(_ pad: Int, _ edit: SampleEdit, done: ((String?) -> Void)? = nil) {
        guard (0..<Pad.count).contains(pad), !sampleEditing, let source = playedSample(pad) else { done?(nil); return }
        sampleEditing = true
        let base = (padName(pad) as NSString).lastPathComponent
        let generation = kitGeneration
        kitQueue.async { [weak self] in
            let (l, r, map) = SampleEditor.apply(edit, to: source)
            var name: String?
            var buffer: SampleBuffer?
            if !l.isEmpty {
                let folder = KnockFolders.samples.appendingPathComponent("Edits", isDirectory: true)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let stem = base.replacingOccurrences(of: #" edit \d+$"#, with: "", options: .regularExpression)
                var k = 1
                var url = folder.appendingPathComponent("\(stem) edit \(k).wav")
                while FileManager.default.fileExists(atPath: url.path) { k += 1; url = folder.appendingPathComponent("\(stem) edit \(k).wav") }
                if (try? WavWriter.write(left: l, right: r, sampleRate: source.sampleRate, to: url)) != nil,
                   let loaded = try? SampleLoader.load(url) {
                    name = "Edits/" + url.lastPathComponent
                    buffer = KnockController.centered(loaded, pad: pad)
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.sampleEditing = false
                guard let name, let buffer, generation == self.kitGeneration, self.kitSamples.count == Pad.count else {
                    if name == nil { self.notice = "That edit couldn't be saved." }
                    done?(nil); return
                }
                var ps = self.state.pads[pad]
                ps.sampleFile = name
                if var sm = ps.sampler { sm.baked(map); ps.sampler = sm }
                self.state.pads[pad] = ps
                self.stockSampleNames[pad] = nil
                self.emptyPads.remove(pad)
                var samples = self.kitSamples
                samples[pad] = buffer
                self.kitSamples = samples
                self.republishKit()
                self.scheduleSave()
                done?(name)
            }
        }
    }

    /// Puts a track back as it was before an edit (the window's UNDO).
    func restorePad(_ pad: Int, _ settings: PadSettings) { setPadSettings(pad, settings) }

    // MARK: Pad editor

    func setPadSettings(_ pad: Int, _ settings: PadSettings) {
        guard pad >= 0 && pad < Pad.count else { return }
        let needsReload = settings.sampleFile != state.pads[pad].sampleFile
        state.pads[pad] = settings
        if needsReload { rebuildKit() } else { republishKit() }
        scheduleSave()
    }

    /// Puts an audio file on a pad (it's copied into the Samples folder first).
    /// `loaded` runs once the engine has the new sound (the screen auditions it then, not before).
    func importSample(_ url: URL, toPad pad: Int, loaded: (() -> Void)? = nil) {
        guard pad >= 0 && pad < Pad.count else { return }
        let generation = kitGeneration
        // The pick that's wanted: a newer pick on this pad, or a kit / rack change, cancels it.
        padPicks[pad] &+= 1
        let pick = padPicks[pad]
        let row = state.workspaceChannels?.first { $0.pad == pad }?.soundID
        let kit = (state.kitID, state.userKit)
        kitQueue.async { [weak self] in
            do {
                let name = try SampleLoader.copyIntoSamples(url)
                let buffer = try KnockController.centered(SampleLoader.load(SampleLoader.urlInSamples(name)), pad: pad)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.padPicks[pad] == pick, self.state.kitID == kit.0, self.state.userKit == kit.1,
                          self.state.workspaceChannels?.first(where: { $0.pad == pad })?.soundID == row else { return }
                    // A new sound comes in as itself: its own pitch and volume, centered, the SAMPLER at
                    // its defaults. The last sound's settings (SMP START, LENGTH, root note, tune, level...)
                    // used to stay on the track and change the new one (Tyrone, Oct 19).
                    var fresh = self.state.pads[pad].freshSound()
                    fresh.sampleFile = name
                    self.state.pads[pad] = fresh
                    self.stockSampleNames[pad] = nil
                    self.emptyPads.remove(pad)
                    if self.kitGeneration == generation, self.kitSamples.count == Pad.count {
                        var samples = self.kitSamples
                        samples[pad] = buffer
                        self.kitSamples = samples
                        self.republishKit()
                        loaded?()
                    } else {
                        // The kit was reloaded meanwhile (a pattern, the audio route): the sound used to be
                        // dropped here while the rack kept its new name (Tyrone, Oct 18). Load it into the kit.
                        if let loaded { self.afterKitLoad.append(loaded) }
                        self.rebuildKit()
                    }
                    self.readout = Readout(title: "PAD \(pad + 1)", value: KnockFolders.soundName(name), time: Date())
                    self.scheduleSave()
                }
            } catch {
                DispatchQueue.main.async { [weak self] in self?.notice = error.localizedDescription }
            }
        }
    }

    func revertPad(_ pad: Int) {
        guard pad >= 0 && pad < Pad.count else { return }
        state.pads[pad] = state.pads[pad].freshSound()
        rebuildKit()
        scheduleSave()
    }

    /// The kick and the 808 always sit in the middle (Tyrone, Oct 19): a stereo file that leans to one
    /// side (the acoustic kicks' room mics lean left up to ~5 dB) has its two sides evened out, same
    /// loudness overall and the same stereo width. Every other pad is left exactly as it was.
    static func centered(_ buffer: SampleBuffer, pad: Int) -> SampleBuffer {
        guard pad == Pad.kick.rawValue || pad == Pad.bass808.rawValue, buffer.length > 1 else { return buffer }
        var el: Double = 0, er: Double = 0
        for i in 0..<buffer.length { el += Double(buffer.left[i] * buffer.left[i]); er += Double(buffer.right[i] * buffer.right[i]) }
        guard el > 1e-12, er > 1e-12, abs(10 * log10(el / er)) > 0.05 else { return buffer }
        let mean = (el + er) / 2
        let gl = Float((mean / el).squareRoot()), gr = Float((mean / er).squareRoot())
        let l = (0..<buffer.length).map { buffer.left[$0] * gl }
        let r = (0..<buffer.length).map { buffer.right[$0] * gr }
        let out = SampleBuffer(left: l, right: r, sampleRate: buffer.sampleRate)
        out.bitDepth = buffer.bitDepth
        out.stereo = buffer.stereo
        out.loopStart = buffer.loopStart
        out.loopEnd = buffer.loopEnd
        out.cues = buffer.cues
        out.region = buffer.region
        out.fadeMarks = buffer.fadeMarks
        return out
    }

    func padName(_ pad: Int) -> String {
        guard (0..<Pad.count).contains(pad) else { return "" }
        if let f = state.pads[pad].sampleFile { return KnockFolders.soundName(f) }
        if let name = stockSampleNames[pad] { return name }
        if emptyPads.contains(pad) { return "EMPTY" }
        return kitDefinition.pads[pad].label
    }

    // MARK: Channel rack (the sequencer screen's channels; the faceplate's 12 pads underneath)

    /// The rack's channels: always all 12 pads, in rack order (808 first), so every sound that can play is on
    /// screen (Tyrone, Oct 17). A pad you haven't given a library sound shows the kit's sound.
    var rackChannels: [WorkspaceChannel] {
        let custom = state.workspaceChannels ?? []
        return rackOrder.map { pad in custom.first { $0.pad == pad }.map(Self.currentName) ?? kitChannel(pad) }
    }

    /// The rack's top-to-bottom order of pads: Pad.rackOrder (808 first) until a track is dragged somewhere else.
    var rackOrder: [Int] {
        guard let order = state.rackOrder, order.count == Pad.count, Set(order) == Set(0..<Pad.count) else { return Pad.rackOrder }
        return order
    }

    /// The rack in this order (UNDO / REDO of a track move).
    func setRackOrder(_ order: [Int]) {
        guard order.count == Pad.count, Set(order) == Set(0..<Pad.count) else { return }
        state.rackOrder = order == Pad.rackOrder ? nil : order
        scheduleSave()
    }

    /// Drag a track up or down the rack: it lands at `index` (counted without it).
    func moveRackChannel(pad: Int, to index: Int) {
        var order = rackOrder
        guard let from = order.firstIndex(of: pad) else { return }
        order.remove(at: from)
        order.insert(pad, at: max(0, min(order.count, index)))
        state.rackOrder = order == Pad.rackOrder ? nil : order
        scheduleSave()
    }

    /// A saved track shows its sound's name now, not the one it was saved with ("!GO2SPINZ" -> "BK NO 5 808").
    private static func currentName(_ row: WorkspaceChannel) -> WorkspaceChannel {
        var row = row
        if row.soundID.hasPrefix("user:") { row.name = KnockFolders.soundName(String(row.soundID.dropFirst(5))) }
        else if row.soundID.hasPrefix("stock:"), let now = KnockFolders.stockSoundName(String(row.soundID.dropFirst(6))) { row.name = now }
        return row
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
    /// `loaded` runs once the engine plays the new sound.
    func replaceRackSound(_ id: UUID, with sound: LibrarySound, loaded: (() -> Void)? = nil) {
        guard let current = rackChannels.first(where: { $0.id == id }) else { return }
        var rows = (state.workspaceChannels ?? []).filter { $0.pad != current.pad }
        rows.append(WorkspaceChannel(id: current.id, pad: current.pad, soundID: sound.id, name: sound.name, category: sound.type.rawValue))
        state.workspaceChannels = rows
        importSample(sound.url, toPad: current.pad, loaded: loaded)
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
        for pad in 0..<Pad.count where state.pads[pad].sampleFile != nil { state.pads[pad] = state.pads[pad].freshSound() }
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
        restore(preset.applying(to: state, hosted: isPlugin), keepPlaying: true)   // the beat carries on with the new pattern
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
        var s = s.normalized()
        s.values[KParam.output.id] = KParam.output.defaultValue   // every preset loads with OUTPUT at max
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
        let kit = KitBuffers(name: state.kitName, samples: playedSamples.count == Pad.count ? playedSamples : kitSamples, settings: state.pads,
                             bassHz: kitDefinition.bassHz, renderSampleRate: exportRate, layers: playedLayers)
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
