// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - BreakBoss DRUM SEQUENCER (the piano-keys button on the faceplate)
//
// Tyrone's rebuilt sequencer (Oct 16): the only sequencer / piano roll screen in the app.
//   Left:   the SOUND LIBRARY (every factory and imported sound by type, with search), plus
//           GENERATE (a new pattern in any style) and MIDI. Drag a sound onto the rack.
//   Middle: the CHANNEL RACK, up to 12 channels. Dropping a sound on the empty part of the rack
//           adds a channel (its oval pops in); dropping it on a channel swaps that channel's
//           sound. Each row: the ▶ triangle expands the track into its piano roll, the name,
//           LEVEL and PAN knobs, the on/off lamp, and the track's own dice (randomizes only
//           that track's steps).
//   Right:  the STEP GRID (16 steps a bar), the track's piano roll when expanded, and the graph
//           a track's arrow drops down under its steps (VELOCITY / PITCH). DRAW / SELECT /
//           ERASE, undo / redo, TEMPO SYNC / FOLLOW DAW, SNAP, SNAP TO SCALE, SWING and HUMANIZE, pinch to zoom (SNAP follows), 2 / 4 / 8 / 16 bars.
//   Bottom: the slider back to Face 1, the POWER button (sequencer and pads all on or off),
//           PATTERN and KIT pickers with arrows.
// All note changes go through KnockController.setLoop, so the engine, presets, MIDI out and
// MIDI export all see the same pattern. The rack's channels sit on the faceplate's 12 pads.

enum DrumRollStyle {
    static let header = Color(red: 39 / 255, green: 39 / 255, blue: 40 / 255)
    static let toolbar = Color(red: 32 / 255, green: 33 / 255, blue: 35 / 255)
    static let rowA = Color(red: 33 / 255, green: 35 / 255, blue: 37 / 255)
    static let rowB = Color(red: 41 / 255, green: 43 / 255, blue: 46 / 255)
    static let channel = Color(red: 31 / 255, green: 32 / 255, blue: 34 / 255)
    static let lane = Color(red: 28 / 255, green: 29 / 255, blue: 32 / 255)
    static let button = Color(red: 44 / 255, green: 46 / 255, blue: 49 / 255)
    static let border = Color(red: 66 / 255, green: 69 / 255, blue: 73 / 255)
    static let text = Color(red: 222 / 255, green: 224 / 255, blue: 222 / 255)
    static let dim = Color(red: 150 / 255, green: 153 / 255, blue: 155 / 255)
    static let green = Color(red: 181 / 255, green: 232 / 255, blue: 124 / 255)
    static let greenDark = Color(red: 34 / 255, green: 53 / 255, blue: 31 / 255)
    static let orange = Color(red: 255 / 255, green: 178 / 255, blue: 46 / 255)
    static let red = Color(red: 232 / 255, green: 44 / 255, blue: 38 / 255)
    static let barLine = Color(red: 186 / 255, green: 189 / 255, blue: 187 / 255)
    static let beatLine = Color(red: 70 / 255, green: 80 / 255, blue: 82 / 255)
    static let stepLine = Color(red: 48 / 255, green: 52 / 255, blue: 54 / 255)
    static let cell = Color(red: 58 / 255, green: 60 / 255, blue: 63 / 255)
    static let cellBeat = Color(red: 70 / 255, green: 72 / 255, blue: 75 / 255)
}

/// The approved design: a brushed-silver slab (the Platinum plate's material) with dark inset panels,
/// the same in every mode. Dark ink prints on the silver, light ink inside the panels.
struct DrumRollTheme {
    let plate = "DrumRollPlate_platinum"
    let ink = Color(white: 0.13)
    let inkDim = Color(white: 0.36)
    let light = true
    static func forFace(_ key: String) -> DrumRollTheme { DrumRollTheme() }
}

extension Pad {
    /// The rack's channel names.
    var channelTitle: String {
        switch self {
        case .kick: return "KICK"
        case .snare: return "SNARE"
        case .clap: return "CLAP"
        case .rim: return "RIM"
        case .hat: return "HI HATS"
        case .openHat: return "OPEN HAT"
        case .bass808: return "808"
        case .perc1: return "PERC 1"
        case .perc2: return "PERC 2"
        case .tomLow: return "LOW TOM"
        case .tomHigh: return "HIGH TOM"
        case .cymbal: return "CRASH"
        }
    }
}

/// What a library drag carries (the sound's id, found again on the rack).
let soundDragPrefix = "breakboss-sound:"

struct SequencerView: View {
    @ObservedObject var controller: KnockController
    @State var loop: Int
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var sizeClass

    /// Face 2's parts live in the Sequencer*.swift files beside this one, as extensions that share
    /// this state.
    init(controller: KnockController, loop: Int) {
        self.controller = controller
        _loop = State(initialValue: loop)
    }

    enum Tool { case draw, select, erase }
    /// The lane's header: what the graph under the open track edits. VELOCITY and CHANCE are bars up
    /// from the floor; PITCH and NOTE OFFSET (early below the centre line, late above) go either side of it.
    enum Lane: String, CaseIterable {
        case velocity = "VELOCITY", pitch = "PITCH", offset = "NOTE OFFSET", chance = "CHANCE"

        var icon: String {
            switch self {
            case .velocity: return "waveform.path"
            case .pitch: return "arrow.up.and.down"
            case .offset: return "arrow.left.and.right"
            case .chance: return "dice"
            }
        }
        var detail: String {
            switch self {
            case .velocity: return "how hard each hit plays"
            case .pitch: return "each hit's pitch, ±12 semitones"
            case .offset: return "each hit early or late of its step (push and pull)"
            case .chance: return "how often each hit plays, 5–100%"
            }
        }
        var hint: String {
            switch self {
            case .velocity: return "DRAG A BAR UP OR DOWN"
            case .pitch: return "DRAG A BAR: ±12 SEMITONES"
            case .offset: return "DOWN = EARLY · UP = LATE"
            case .chance: return "DRAG A BAR: HOW OFTEN IT PLAYS"
            }
        }
        /// The switch's label (four have to fit across a track).
        var short: String {
            switch self {
            case .velocity: return "VELOCITY"
            case .pitch: return "PITCH"
            case .offset: return "OFFSET"
            case .chance: return "CHANCE"
            }
        }
        var testID: String {
            switch self {
            case .velocity: return "laneVelocity"
            case .pitch: return "lanePitch"
            case .offset: return "laneOffset"
            case .chance: return "laneChance"
            }
        }
        /// Bars either side of a centre line rather than up from the floor.
        var centred: Bool { self == .pitch || self == .offset }
        var marks: [(String, CGFloat)] {
            switch self {
            case .velocity: return [("127", 1), ("64", 0.5), ("0", 0)]
            case .pitch: return [("+12", 1), ("0", 0.5), ("-12", 0)]
            case .offset: return [("LATE", 1), ("0", 0.5), ("EARLY", 0)]
            case .chance: return [("100%", 1), ("50%", 0.5), ("0", 0)]
            }
        }
        /// A note's value on the graph, 0...1 (0.5 is the centre line).
        func value(_ e: GrooveEvent) -> CGFloat {
            switch self {
            case .velocity: return CGFloat(e.velocity)
            case .pitch: return CGFloat((e.semis.clamped(-12, 12) + 12) / 24)
            case .offset: return CGFloat((Float(e.offset) / Float(PatternData.maxOffset) + 1) / 2)
            case .chance: return CGFloat(e.chance)
            }
        }
        /// The number written on a centred bar (none on the centre line).
        func label(_ e: GrooveEvent) -> String? {
            switch self {
            case .pitch: return e.semis == 0 ? nil : (e.semis > 0 ? "+\(Int(e.semis))" : "\(Int(e.semis))")
            case .offset: return e.offset == 0 ? nil : (e.offset > 0 ? "+\(e.offset)" : "\(e.offset)")
            default: return nil
            }
        }
    }
    enum Panel { case sounds, generate }

    @State var tool: Tool = .draw
    @State var snap: Int32 = PatternData.stepTicks   // grid in ticks (0 = none)
    @State var selectedID: UUID?                      // the track picked (dice, lane, strip)
    @State var expandedID: UUID?                      // the track opened into its piano roll
    @State var lane: Lane = .velocity
    @State var follow = true
    /// Where the grid's visible window starts (ticks): it slides sideways when the pattern is longer
    /// than the screen (drag the beat numbers, or two fingers on the grid).
    /// In ticks, fractional, so the grid glides under a finger instead of jumping a step at a time.
    @State var viewStart: Double = 0
    @State var rulerDragStart: Double?
    @State var tempoDragStart: Double?
    @State var twoFinger = false                      // two fingers on the grid: sliding, not drawing
    @State var panStart: Double?
    @State var zoomLevel = 0
    @State var pinchBase: CGFloat = 1
    @State var pinching = false
    static let zoomSnaps: [Int32] = [24, 12, 6, 3]
    @State var selection = Set<NoteKey>()
    /// The lowest key each track's piano roll shows (a C, MIDI note); ⊕ and ⊖ move it an octave.
    @State var rollBottoms: [Int: Int] = [:]
    /// The note whose octave glyphs are showing (a two-finger tap or right-click on it).
    @State var octaveNote: NoteKey?
    /// The grid's right-click menu, and the notes it copied (ticks counted from the first one).
    @State var gridMenuOpener = BBMenuOpener()
    @State var noteClipboard: [GrooveEvent] = []
    /// When the finger went down on the grid (draw mode: a quick drag selects, a held one paints).
    @State var touchDown = Date.distantPast
    /// Where the finger is while it draws a note in the piano roll (Tyrone, Oct 21): a shadow of the
    /// note follows it until the finger lifts.
    @State var trace: Trace?
    struct Trace { var from: CGPoint; var at: CGPoint }
    /// The library's Search field has the keyboard (its Delete key edits the text, not the notes).
    @FocusState var searchFocused: Bool
    /// One UNDO step: the pattern and the rack's track order as they were (a track move undoes too).
    struct UndoStep { var pattern: PatternData; var rack: [Int] }
    @State var undoStack: [UndoStep] = []
    @State var redoStack: [UndoStep] = []
    @State var rememberedAt: Date?
    /// The two studs left of a track's arrow (Tyrone, Oct 19): grab them and the track follows the
    /// finger up or down the rack, the others sliding out of its way. movingTop is where the dragged
    /// track sits; grabY where the finger went down; grabOrder the order before the move (for UNDO).
    @State var movingPad: Int?
    @State var movingTop: CGFloat = 0
    @State var movingFrom: CGFloat = 0
    @State var grabY: CGFloat = 0
    @State var grabOrder: [Int] = []
    @State var work: PatternData?
    @State var drag: GridDrag = .none
    @State var lastVelocity: Float = 0.78
    @State var last808Length: Int32 = PatternEdit.default808Length
    @State var humanizeStart: Float?
    @State var swingStart: Float?
    @State var showMenu = false
    @State var importPad: Int?
    @State var recordPad: Int?
    @State var exportURL: URL?
    /// The engine's clock for the few things that show it (PLAY, the count-in, a host's tempo). A class
    /// held in @State: its ticks redraw those alone, never all of Face 2.
    @State var engineTick = EngineTick()
    @State var clock = ClockState()
    final class ClockState { var wasLive = false; var wasPlaying = false }
    @State var newborn = Set<UUID>()
    @State var settling = Set<UUID>()
    @State var rackTargeted = false
    @State var rowTargeted: UUID?
    @State var section: Panel = .sounds
    @State var openID: UUID?                          // the track whose arrow is lit: the lane edits it
    @State var shareMIDI = false
    @State var updateSounds = false
    @State var updateTempo = true
    @State var trackSettingsID: UUID?
    /// The track whose SAMPLER window is open, and whether it's tucked away (minimized).
    @State var samplerPad: Int?
    @State var samplerMinimized = false
    /// The SAMPLER window floats over the sequencer: where it sits and how wide it is (kept between opens).
    @AppStorage("samplerWindowX") var samplerX: Double = -1
    @AppStorage("samplerWindowY") var samplerY: Double = -1
    @AppStorage("samplerWindowW") var samplerW: Double = 0
    /// The library's preview volume (KnockController.previewVolume reads the same key).
    @AppStorage(KnockController.previewVolumeKey) var previewVolume: Double = 1
    /// The SAMPLER window's drag in progress (only the window's placement watches it).
    @State var samplerDrag = SamplerWindowDrag()
    @State var libraryType: SoundType? = .kick
    @State var search = ""
    /// The library sound picked by a first tap; tapping it again plays it (Tyrone, Oct 20).
    @State var libraryPick: String?
    @State var libraryPreviews = 0
    @State var userSounds: [LibrarySound] = UserSoundLibrary.sounds()
    @State var importKind: ImportKind?
    @State var generateStyle: String?
    @State var libraryNote = ""
    @State var fxTurning: KParam?
    @State var laneOrigin: PatternData?
    let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    static let factorySounds: [LibrarySound] = StockSampleLibrary.bundled.librarySounds()

    enum ImportKind: Identifiable { case sounds, pack; var id: Int { self == .sounds ? 0 : 1 } }

    enum GridDrag {
        case none
        case paint(pad: Int, semis: Float, lastCell: Int)
        case long808(start: Int32, semis: Float)
        case move(keys: Set<NoteKey>, origin: PatternData, startTick: Int32, startSemis: Int, followSelection: Bool)
        case resize(key: NoteKey, origin: PatternData)
        case trim(keys: Set<NoteKey>, origin: PatternData, startTick: Int32)
        case marquee(start: CGPoint, current: CGPoint)
        case erase
        case tapOnNote(key: NoteKey)
        /// Hold a step and pull down: the step plays `count` even hits (note repeat).
        case noteRepeat(pad: Int, cellStart: Int32, like: GrooveEvent, origin: PatternData, count: Int, fromPaint: Bool)
        case graph(pad: Int, top: CGFloat, height: CGFloat)
        /// A tap on a note's ⊕ or ⊖ (done when the finger lands; the rest of the touch does nothing).
        case octave
    }

    typealias S = DrumRollStyle

    // MARK: Pattern and grid maths

    var pattern: PatternData { work ?? stored }
    var stored: PatternData {
        controller.loops.indices.contains(loop) ? controller.loops[loop]
            : PatternData(name: "", lengthTicks: PatternEdit.barTicks * 2, events: [])
    }
    var compact: Bool { sizeClass == .compact }
    var bars: Int { max(1, pattern.bars) }
    var barsPerPage: Int { min(2, bars) }
    var windowTicks: Int32 {
        switch zoomLevel {
        case 0: return Int32(barsPerPage) * PatternEdit.barTicks
        case 1: return PatternEdit.barTicks
        case 2: return PatternEdit.barTicks / 2
        default: return PatternData.ppq
        }
    }
    var totalTicks: Int32 { Int32(bars) * PatternEdit.barTicks }
    var maxStart: Int32 { max(0, totalTicks - windowTicks) }
    /// The tick at the grid's left edge (fractional: the window slides smoothly).
    var origin: Double { min(Double(maxStart), max(0, viewStart)) }
    /// The first step cell on screen (it can be partly off the left edge while sliding).
    var pageStart: Int32 {
        let c = max(1, cellTicks)
        return Int32(origin) / c * c
    }
    func scroll(to start: Double) {
        let clamped = min(Double(maxStart), max(0, start))
        if clamped != viewStart { viewStart = clamped }
        follow = false
    }
    func scroll(to start: Int32) { scroll(to: Double(start)) }
    var pageTicks: Int32 { windowTicks }
    var snapTicks: Int32 { snap }
    /// The step cells drawn on each row: 16ths, finer when zoomed in.
    var cellTicks: Int32 { zoomLevel == 0 ? PatternData.stepTicks : Self.zoomSnaps[zoomLevel] }

    static let snapChoices: [(section: String, items: [(String, Int32)])] = [
        ("Straight", [("1/2 (half note)", 192), ("Beat (1/4)", 96), ("1/2 Beat (1/8)", 48), ("1/4 Beat (1/16)", 24),
                      ("1/2 Step (1/32)", 12), ("1/4 Step (1/64)", 6), ("1/128", 3)]),
        ("Triplet", [("1/3 Beat (1/8 triplet)", 32), ("1/3 Step (1/16 triplet)", 8), ("1/6 Beat", 16), ("1/6 Step", 4)]),
        ("Off", [("None (free)", 0)])
    ]
    var snapLabel: String {
        for group in Self.snapChoices { if let hit = group.items.first(where: { $0.1 == snap }) { return hit.0.components(separatedBy: " (").first ?? hit.0 } }
        return "\(snap) TICKS"
    }
    var placeTicks: Int32 { snapTicks > 0 ? snapTicks : 6 }
    var theme: DrumRollTheme { DrumRollTheme.forFace(controller.faceKey) }
    var noteColor: Color { PadView.lightColor(controller.mode) }
    /// Face 2 wears the same finish as Face 1: platinum / black (MODERN), cream (VINTAGE), blue (TEXTURE).
    var finish: String { controller.faceKey }
    var plateSprite: String { "SeqPlate_\(finish)" }
    var rowSprite: String { "SeqRow_\(finish)" }
    /// Printing on the metal: black on platinum and cream, white on black and blue (Tyrone's renders).
    var inkColor: Color { finish == "modern" || finish == "texture" ? Color(white: 0.93) : Color(white: 0.1) }
    /// What lights up on each face (Tyrone's Face 2 renders, Oct 17): the tools, PLAY, the power ring,
    /// the type chip and the track lamps. Platinum and black red (Tyrone, Oct 18: no lime green on
    /// Platinum), vintage amber, texture blue.
    var accent: Color {
        switch finish {
        case "vintage": return Color(red: 1, green: 0.74, blue: 0.2)
        case "texture": return Color(red: 0.25, green: 0.6, blue: 1)
        default: return Color(red: 1, green: 0.2, blue: 0.16)
        }
    }
    /// The panels' lit colour (selected rows, the root note, lit boxes): each mode's own accent
    /// (Tyrone, Oct 18: red only on Platinum and Black, the other modes their own colour, no lime).
    var lit: Color { accent }
    var litDark: Color {
        switch finish {
        case "vintage": return Color(red: 0.24, green: 0.17, blue: 0.04)
        case "texture": return Color(red: 0.05, green: 0.13, blue: 0.24)
        default: return Color(red: 0.24, green: 0.05, blue: 0.04)
        }
    }
    /// The selected track (red in every render) and the open graph's lane chip (blue on Texture).
    var selectColor: Color { Color(red: 1, green: 0.22, blue: 0.16) }
    var laneColor: Color { finish == "texture" ? Color(red: 0.25, green: 0.6, blue: 1) : selectColor }
    var isThisPlaying: Bool { controller.isPlaying && Int(controller.meters.status[1]) == loop }

    // MARK: Rack rows

    var channels: [WorkspaceChannel] { controller.rackChannels }
    var selected: WorkspaceChannel? { channels.first { $0.id == selectedID } }
    var selectedPad: Int? { selected?.pad }
    func channel(pad: Int) -> WorkspaceChannel? { channels.first { $0.pad == pad } }
    /// The open piano roll's keys, in semitones from the track's base note: two octaves (the 808
    /// three) somewhere between C1 and C8.
    func pitchRange(_ pad: Int) -> ClosedRange<Int> {
        let low = rollBottom(pad) - controller.baseNote(pad: pad)
        return low...(low + rollSpan(pad))
    }
    func rollSpan(_ pad: Int) -> Int { pad == Pad.bass808.rawValue ? 36 : 24 }
    /// The piano roll's lowest key: where ⊕ / ⊖ left it, else the C under the track's lowest note
    /// (or under its base note when that is lower).
    func rollBottom(_ pad: Int) -> Int {
        if let b = rollBottoms[pad] { return b }
        let base = controller.baseNote(pad: pad)
        let lowest = pattern.events.filter { Int($0.pad) == pad }.map { base + Int($0.semis.rounded()) }.min() ?? base
        return clampedBottom(octaveC(min(base, lowest)), pad)
    }
    func octaveC(_ note: Int) -> Int { note - ((note % 12) + 12) % 12 }
    func clampedBottom(_ b: Int, _ pad: Int) -> Int { b.clamped(MusicScale.lowestNote, MusicScale.highestNote - rollSpan(pad)) }
    /// The open piano roll keeps its keys while notes are drawn and erased.
    func pinRoll() {
        guard let id = expandedID, let pad = channels.first(where: { $0.id == id })?.pad, rollBottoms[pad] == nil else { return }
        rollBottoms[pad] = rollBottom(pad)
    }
    func shiftRoll(_ pad: Int, octaves: Int) {
        rollBottoms[pad] = clampedBottom(rollBottom(pad) + 12 * octaves, pad)
    }

    /// ⊕ / ⊖ on a note: it (with the rest of the selection when it's selected) goes up or down an
    /// octave, inside C1 to C8, and the open piano roll follows it.
    func moveOctave(_ key: NoteKey, by octaves: Int) {
        let keys = selection.contains(key) ? selection : [key]
        guard let moved = PatternEdit.transpose(pattern, keys, by: 12 * octaves, limits: { controller.pitchLimits(pad: $0) }) else { return }
        let (p, newKeys) = moved
        commit(p)
        if selection.contains(key) { selection = newKeys }
        let newKey = NoteKey(tick: key.tick, pad: key.pad, semis: Float(Int(key.semis.rounded()) + 12 * octaves))
        octaveNote = newKey
        let pad = Int(key.pad)
        let note = controller.baseNote(pad: pad) + Int(newKey.semis)
        let bottom = rollBottom(pad)
        if note < bottom || note > bottom + rollSpan(pad) {
            rollBottoms[pad] = clampedBottom(octaveC(note) - (octaves > 0 ? rollSpan(pad) - 12 : 0), pad)
        }
    }

    /// Where every row sits in the grid: collapsed rows are one step row; the expanded track is one
    /// row per semitone (its piano roll).
    /// An expanded track keeps its step row (the band) on top; its piano roll's pitch rows start at pitchTop.
    struct RowLayout {
        let channel: WorkspaceChannel; let y: CGFloat; let height: CGFloat; let pitch: ClosedRange<Int>?; let pitchRowH: CGFloat; let pitchTop: CGFloat
        /// The step row's height (an open track keeps its step row on top; its toolbar sits under it).
        let bandH: CGFloat
        /// The graph that drops down under the track opened with its arrow (0 = closed).
        var graphH: CGFloat = 0
        var graphTop: CGFloat { y + bandH }
    }
    /// Three boxes of the old height (Tyrone, Oct 19: one more box than the two it had).
    func graphHeight(_ rowH: CGFloat) -> CGFloat { rowH * 2.25 - 4 }
    /// The open track's toolbar between its steps and its keys: the lane switch, then KEY · SCALE · SNAP · FIT.
    func toolbarH(_ rowH: CGFloat) -> CGFloat { rowH * 1.3 }
    func layouts(rowH: CGFloat) -> [RowLayout] {
        let pitchRowH = rowH * 0.3
        var y: CGFloat = 0
        var out: [RowLayout] = []
        for ch in channels {
            if ch.id == expandedID {
                let range = pitchRange(ch.pad)
                let h = rowH + toolbarH(rowH) + CGFloat(range.count) * pitchRowH
                out.append(RowLayout(channel: ch, y: y, height: h, pitch: range, pitchRowH: pitchRowH, pitchTop: y + rowH + toolbarH(rowH), bandH: rowH)); y += h
            } else if ch.id == openID {
                let g = graphHeight(rowH)
                out.append(RowLayout(channel: ch, y: y, height: rowH + g, pitch: nil, pitchRowH: pitchRowH, pitchTop: y, bandH: rowH, graphH: g)); y += rowH + g
            } else {
                out.append(RowLayout(channel: ch, y: y, height: rowH, pitch: nil, pitchRowH: pitchRowH, pitchTop: y, bandH: rowH)); y += rowH
            }
        }
        return out
    }
    func layout(for pad: Int, _ L: [RowLayout]) -> RowLayout? { L.first { $0.channel.pad == pad } }
    func layout(at y: CGFloat, _ L: [RowLayout]) -> RowLayout? { L.first { y >= $0.y && y < $0.y + $0.height } }
    /// The pitch a point in an expanded track means (0 for a collapsed row).
    func semis(at y: CGFloat, in l: RowLayout) -> Float {
        guard let range = l.pitch else { return 0 }
        let row = Int((max(y, l.pitchTop) - l.pitchTop) / l.pitchRowH)
        return Float((range.upperBound - row).clamped(range.lowerBound, range.upperBound))
    }
    /// The expanded track's step band on top of its piano roll (its own steps, like a closed row).
    func inBand(_ y: CGFloat, _ l: RowLayout) -> Bool { l.pitch != nil && y < l.y + l.bandH }
    /// The open track's toolbar strip (no notes there).
    func inToolbar(_ y: CGFloat, _ l: RowLayout) -> Bool { l.pitch != nil && y >= l.y + l.bandH && y < l.pitchTop }
    /// The graph dropped down under the track opened with its arrow.
    func inGraph(_ y: CGFloat, _ l: RowLayout) -> Bool { l.graphH > 0 && y >= l.graphTop && y < l.y + l.height }

    // MARK: Body — Tyrone's picture is the plate; the live controls sit on it at measured spots

    static let artW: CGFloat = 1672, artH: CGFloat = 941
    /// Art rectangles (px in Tyrone's Face 2 renders, Oct 17 2026, the locked design): [x0, y0, x1, y1].
    /// The same numbers are in tools/sequencer_art/face2/rects.py, which cuts the plates and buttons.
    enum A {
        static let tools: [[Double]] = [[325, 94, 427, 150], [430, 94, 529, 150], [532, 94, 630, 150]]
        static let undo: [Double] = [633, 94, 730, 150], redo: [Double] = [732, 94, 830, 150]
        static let stop: [Double] = [858, 94, 925, 150], play: [Double] = [928, 94, 995, 150], rec: [Double] = [997, 94, 1064, 150]
        static let bpm: [Double] = [1082, 94, 1238, 150], bars: [Double] = [1242, 94, 1382, 150]
        static let gear: [Double] = [1465, 95, 1528, 150], cloud: [Double] = [1542, 93, 1605, 152]
        static let snap: [Double] = [957, 159, 1171, 205], swing: [Double] = [1183, 161, 1369, 205], humanize: [Double] = [1375, 161, 1530, 205]
        static let snapScale: [Double] = [960, 163, 988, 201]
        static let swingKnob: [Double] = [1327, 165, 1358, 196], humanizeKnob: [Double] = [1490, 165, 1521, 196]
        static let tempoSync: [Double] = [636, 160, 790, 205], followDAW: [Double] = [796, 160, 950, 205]
        static let pageBack: [Double] = [432, 162, 466, 202], pageText: [Double] = [466, 164, 594, 200], pageForward: [Double] = [592, 162, 626, 202]
        static let leftPanel: [Double] = [45, 218, 334, 707]
        static let headerH: Double = 46
        /// The track headers (silver tab + dark body), the steps, and the per-track buttons' column.
        static let rackX0: Double = 347, rackX1: Double = 607, gridX0: Double = 626, gridX1: Double = 1576, panelX1: Double = 1622
        static let rowsY0: Double = 266, rowsY1: Double = 690, rowH: Double = 62.5, labelsY: Double = 247
        static let slider: [Double] = [67, 728, 184, 790], power: [Double] = [197, 726, 263, 792]
        // PATTERN and KIT moved left (Tyrone, Oct 17); their labels and dividers are printed on the plate
        static let patternBack: [Double] = [312, 741, 361, 785], patternForward: [Double] = [361, 741, 410, 785], patternChip: [Double] = [411, 740, 641, 785]
        static let kitBack: [Double] = [690, 741, 738, 785], kitForward: [Double] = [738, 741, 787, 785], kitChip: [Double] = [789, 740, 1004, 785]
        /// The FX knobs on the right of the bottom rail: 8 places, labels over the knobs.
        static let fxX0: Double = 1045, fxX1: Double = 1598, fxLabelY0: Double = 709, fxLabelY1: Double = 733, fxKnobY0: Double = 740, fxKnobY1: Double = 786
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Self.artW, geo.size.height / Self.artH)
            ZStack(alignment: .topLeading) {
                // the plate carries the BreaKing logo, as in the renders
                Image(plateSprite).resizable().frame(width: Self.artW * s, height: Self.artH * s)
                Rectangle().fill(Color.white.opacity(0.001)).place([92, 88, 296, 190], s)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore).accessibilityLabel(BrandLogo.name).accessibilityIdentifier("brandLogo")
                // each part erased to a plain view: written out in full, Face 2's type nests so deep the
                // TestFlight app can run out of stack opening it (the SAMPLER window's b120 crash)
                ZStack(alignment: .topLeading) { topBar(s) }.erased()
                ZStack(alignment: .topLeading) { leftPanel(s) }.erased()
                ZStack(alignment: .topLeading) { editor(s) }.erased()
                ZStack(alignment: .topLeading) { footer(s) }.erased()
                // the tutorial's Face 2 steps (Tyrone, Oct 20)
                TutorialOverlay(surface: .face2, art: CGSize(width: Self.artW, height: Self.artH), scale: s, finish: finish) { $0.face2 }
            }
            .frame(width: Self.artW * s, height: Self.artH * s)
            // the value of the knob being turned, in a lit readout over it (Tyrone, Oct 19)
            .overlayPreferenceValue(KnobHUDKey.self) { entries in
                GeometryReader { g in
                    ForEach(entries.indices, id: \.self) { i in
                        let r = g[entries[i].anchor]
                        KnobHUDView(hud: entries[i].hud, accent: accent, scale: s)
                            .position(x: min(max(r.midX, 80 * s), g.size.width - 80 * s), y: max(r.minY - 30 * s, 26 * s))
                    }
                }
                .allowsHitTesting(false)
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            // headers, slider, knob rims and control edges in the faceplate's metal
            .environment(\.seqFinish, finish)
            // Face 2's menus check their items in the mode's own colour, not lime
            .environment(\.bbMenuAccent, accent)
        }
        .overlay { samplerOverlay.erased() }
        .bbMenuHost()
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .background(spaceBar)
        .background(deleteKey)
        .onReceive(ticker) { now in
            // the clock only redraws PLAY, the count-in and the tempo, while something plays (and once
            // more as it stops): redrawing all of Face 2 ten times a second made the playhead, the rack
            // and the SAMPLER window stutter
            let live = controller.isPlaying || controller.recording
            if live || clock.wasLive { engineTick.now = now }
            clock.wasLive = live
            // pressing play (here, on Face 1 or in the host) follows the playhead again, like Logic
            if controller.isPlaying && !clock.wasPlaying && !follow { follow = true }
            clock.wasPlaying = controller.isPlaying
            if controller.recording { controller.mergeRecorded(snap: snapTicks) }
            followPlayhead()
        }
        .onAppear {
            if selectedID == nil { selectedID = channels.first?.id }
            // A fresh project opens with a blank grid: steps only light up when you press them
            // (patterns come in from the PATTERN chip).
            if controller.state.presetName == "INIT", loop < controller.state.editedLoops.count,
               controller.state.editedLoops[loop] == nil, loop < controller.loops.count {
                controller.setLoop(loop, PatternData(name: "LOOP \(loop + 1)", lengthTicks: controller.loops[loop].lengthTicks, events: []))
            }
        }
        .modifier(SpaceBarKey { controller.togglePlayback(pattern: loop) })
        .onChange(of: loop) { _ in viewStart = 0; selection = []; undoStack = []; redoStack = []; controller.showPattern(loop); rollBottoms = [:]; octaveNote = nil; pinRoll() }
        .onChange(of: expandedID) { _ in octaveNote = nil; pinRoll() }
        // a new pattern or kit: the open piano roll finds its notes again
        .onChange(of: controller.state.presetName) { _ in rollBottoms = [:]; octaveNote = nil; pinRoll() }
        .onChange(of: controller.state.kitName) { _ in rollBottoms = [:]; octaveNote = nil; pinRoll() }
        .onDisappear { if controller.recording { controller.setRecording(false) } }
        .task(id: stored) { exportURL = writeMIDI() }
        .sheet(isPresented: $showMenu) { MenuView(controller: controller) }
        .sheet(isPresented: $shareMIDI) { if let url = exportURL { ShareSheet(items: [url]) } }
        .sheet(item: Binding(get: { trackSettingsID.flatMap { id in channels.first { $0.id == id } } }, set: { trackSettingsID = $0?.id })) { ch in
            VStack(spacing: 0) {
                Text("TRACK SETTINGS").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(S.dim).padding(.top, 16)
                    .accessibilityIdentifier("trackSettingsSheet")
                channelStrip(ch).padding(.vertical, 12)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(S.header.ignoresSafeArea())
            // a sheet is its own window: the SOUND and MIDI menus need a menu layer of their own here
            .bbMenuHost()
            .preferredColorScheme(.dark).presentationDetents([.height(180), .medium])
        }
        .sheet(item: Binding(get: { recordPad.map { PadID(pad: $0) } }, set: { recordPad = $0?.pad })) { target in
            ChannelRecordSheet(controller: controller, pad: target.pad)
        }
        .fileImporter(isPresented: Binding(get: { importPad != nil || importKind != nil }, set: { if !$0 { importPad = nil; importKind = nil } }),
                      allowedContentTypes: importKind == .pack ? [.folder] : [.audio],
                      allowsMultipleSelection: importKind == .sounds) { result in
            defer { importPad = nil; importKind = nil }
            guard case .success(let urls) = result else { return }
            if let pad = importPad, let url = urls.first { controller.importSample(url, toPad: pad); return }
            let n = importKind == .pack ? urls.reduce(0) { $0 + UserSoundLibrary.importPack($1) } : UserSoundLibrary.importSounds(urls)
            userSounds = UserSoundLibrary.sounds()
            if importKind == .pack, let first = urls.first { search = KnockFolders.safe(first.deletingPathExtension().lastPathComponent); libraryType = nil }
            libraryNote = n == 0 ? "No audio files found there." : "Imported \(n) sound\(n == 1 ? "" : "s")."
        }
    }

    struct PadID: Identifiable { let pad: Int; var id: Int { pad } }

    /// Space bar = play / stop (hardware keyboard, standalone and plug-in on iOS 17+).
    struct SpaceBarKey: ViewModifier {
        let toggle: () -> Void
        func body(content: Content) -> some View {
            if #available(iOS 17.0, *) {
                content.focusable().focusEffectDisabled().onKeyPress(.space) { toggle(); return .handled }
            } else {
                content
            }
        }
    }

    @ViewBuilder var spaceBar: some View {
        if !controller.isPlugin {
            Button("") { controller.togglePlayback(pattern: loop) }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }

    /// Delete / Backspace on a hardware keyboard deletes the selected notes (Tyrone, Oct 21).
    @ViewBuilder var deleteKey: some View {
        let off = selection.isEmpty || searchFocused
        ZStack {
            Button("") { deleteSelection() }.keyboardShortcut(.delete, modifiers: [])
            Button("") { deleteSelection() }.keyboardShortcut(.deleteForward, modifiers: [])
        }
        .disabled(off)
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    /// The selected notes go, as one UNDO step.
    func deleteSelection() {
        let keys = selection
        guard !keys.isEmpty, pattern.events.contains(where: { keys.contains(NoteKey($0)) }) else { selection = []; return }
        commit(PatternEdit.remove(pattern, keys))
        selection = []
        octaveNote = nil
    }

    /// An invisible press area over a painted button.
    func hit(_ r: [Double], _ s: CGFloat, action: @escaping () -> Void) -> some View {
        PressableArea(action: action).place(r, s)
    }
    func artText(_ text: String, _ r: [Double], _ s: CGFloat, size: CGFloat = 15, weight: Font.Weight = .medium,
                         color: Color = .white, align: Alignment = .center) -> some View {
        Text(text).font(.system(size: size * s, weight: weight)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: (r[2] - r[0]) * s, height: (r[3] - r[1]) * s, alignment: align)
            .place(r, s)
    }
    /// The picture's knob, turned to the value (drag up or right to turn it up).
    func artKnob(_ r: [Double], _ s: CGFloat, value: Float, hud: KnobHUD? = nil, change: @escaping (Float, Bool) -> Void) -> some View {
        ArtKnob(value: value, grip: 10 * s, hud: hud, change: change).place([r[0] - 10, r[1] - 10, r[2] + 10, r[3] + 10], s)
    }

}
