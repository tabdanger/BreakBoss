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
        case .hat: return "CLOSED HAT"
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
private let soundDragPrefix = "breakboss-sound:"

struct SequencerView: View {
    @ObservedObject var controller: KnockController
    @State var loop: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

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

    @State private var tool: Tool = .draw
    @State private var snap: Int32 = PatternData.stepTicks   // grid in ticks (0 = none)
    @State private var selectedID: UUID?                      // the track picked (dice, lane, strip)
    @State private var expandedID: UUID?                      // the track opened into its piano roll
    @State private var lane: Lane = .velocity
    @State private var follow = true
    /// Where the grid's visible window starts (ticks): it slides sideways when the pattern is longer
    /// than the screen (drag the beat numbers, or two fingers on the grid).
    @State private var viewStart: Int32 = 0
    @State private var rulerDragStart: Int32?
    @State private var tempoDragStart: Double?
    @State private var twoFinger = false                      // two fingers on the grid: sliding, not drawing
    @State private var panStart: Int32?
    @State private var zoomLevel = 0
    @State private var pinchBase: CGFloat = 1
    @State private var pinching = false
    static let zoomSnaps: [Int32] = [24, 12, 6, 3]
    @State private var selection = Set<NoteKey>()
    @State private var undoStack: [PatternData] = []
    @State private var redoStack: [PatternData] = []
    @State private var rememberedAt: Date?
    /// The grip left of a track header: drag it and the track moves up or down the rack, the others
    /// making room as it passes (no hold, no wiggle). movingTop is where the dragged track sits.
    @State private var movingPad: Int?
    @State private var movingTop: CGFloat = 0
    @State private var movingFrom: CGFloat = 0
    @State private var work: PatternData?
    @State private var drag: GridDrag = .none
    @State private var lastVelocity: Float = 0.78
    @State private var last808Length: Int32 = PatternEdit.default808Length
    @State private var humanizeStart: Float?
    @State private var swingStart: Float?
    @State private var showMenu = false
    @State private var importPad: Int?
    @State private var recordPad: Int?
    @State private var exportURL: URL?
    @State private var tick = Date()
    @State private var newborn = Set<UUID>()
    @State private var settling = Set<UUID>()
    @State private var rackTargeted = false
    @State private var rowTargeted: UUID?
    @State private var section: Panel = .sounds
    @State private var openID: UUID?                          // the track whose arrow is lit: the lane edits it
    @State private var shareMIDI = false
    @State private var updateSounds = false
    @State private var updateTempo = true
    @State private var trackSettingsID: UUID?
    @State private var libraryType: SoundType? = .kick
    @State private var search = ""
    @State private var userSounds: [LibrarySound] = UserSoundLibrary.sounds()
    @State private var importKind: ImportKind?
    @State private var generateStyle: String?
    @State private var libraryNote = ""
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private static let factorySounds: [LibrarySound] = StockSampleLibrary.bundled.librarySounds()

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
        case graph(pad: Int, top: CGFloat, height: CGFloat)
    }

    private typealias S = DrumRollStyle

    // MARK: Pattern and grid maths

    private var pattern: PatternData { work ?? stored }
    private var stored: PatternData {
        controller.loops.indices.contains(loop) ? controller.loops[loop]
            : PatternData(name: "", lengthTicks: PatternEdit.barTicks * 2, events: [])
    }
    private var compact: Bool { sizeClass == .compact }
    private var bars: Int { max(1, pattern.bars) }
    private var barsPerPage: Int { min(2, bars) }
    private var windowTicks: Int32 {
        switch zoomLevel {
        case 0: return Int32(barsPerPage) * PatternEdit.barTicks
        case 1: return PatternEdit.barTicks
        case 2: return PatternEdit.barTicks / 2
        default: return PatternData.ppq
        }
    }
    private var totalTicks: Int32 { Int32(bars) * PatternEdit.barTicks }
    private var maxStart: Int32 { max(0, totalTicks - windowTicks) }
    /// The visible window's first tick, on a step so the step buttons stay put.
    private var pageStart: Int32 {
        let c = max(1, cellTicks)
        return min(maxStart, max(0, viewStart)) / c * c
    }
    private func scroll(to start: Int32) {
        let clamped = min(maxStart, max(0, start))
        if clamped != viewStart { viewStart = clamped }
        follow = false
    }
    private var pageTicks: Int32 { windowTicks }
    private var snapTicks: Int32 { snap }
    /// The step cells drawn on each row: 16ths, finer when zoomed in.
    private var cellTicks: Int32 { zoomLevel == 0 ? PatternData.stepTicks : Self.zoomSnaps[zoomLevel] }

    static let snapChoices: [(section: String, items: [(String, Int32)])] = [
        ("Straight", [("1/2 (half note)", 192), ("Beat (1/4)", 96), ("1/2 Beat (1/8)", 48), ("1/4 Beat (1/16)", 24),
                      ("1/2 Step (1/32)", 12), ("1/4 Step (1/64)", 6), ("1/128", 3)]),
        ("Triplet", [("1/3 Beat (1/8 triplet)", 32), ("1/3 Step (1/16 triplet)", 8), ("1/6 Beat", 16), ("1/6 Step", 4)]),
        ("Off", [("None (free)", 0)])
    ]
    private var snapLabel: String {
        for group in Self.snapChoices { if let hit = group.items.first(where: { $0.1 == snap }) { return hit.0.components(separatedBy: " (").first ?? hit.0 } }
        return "\(snap) TICKS"
    }
    private var placeTicks: Int32 { snapTicks > 0 ? snapTicks : 6 }
    private var theme: DrumRollTheme { DrumRollTheme.forFace(controller.faceKey) }
    private var noteColor: Color { PadView.lightColor(controller.mode) }
    /// Face 2 wears the same finish as Face 1: platinum / black (MODERN), cream (VINTAGE), blue (TEXTURE).
    private var finish: String { controller.faceKey }
    private var plateSprite: String { "SeqPlate_\(finish)" }
    private var rowSprite: String { "SeqRow_\(finish)" }
    /// Printing on the metal: black on the light finishes, white on the black one.
    private var inkColor: Color { finish == "modern" ? Color(white: 0.9) : Color(white: 0.1) }
    private var isThisPlaying: Bool { controller.isPlaying && Int(controller.meters.status[1]) == loop }

    // MARK: Rack rows

    private var channels: [WorkspaceChannel] { controller.rackChannels }
    private var selected: WorkspaceChannel? { channels.first { $0.id == selectedID } }
    private var selectedPad: Int? { selected?.pad }
    private func channel(pad: Int) -> WorkspaceChannel? { channels.first { $0.pad == pad } }
    private func pitchRange(_ pad: Int) -> ClosedRange<Int> { pad == Pad.bass808.rawValue ? -12...24 : -12...12 }

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
    private func graphHeight(_ rowH: CGFloat) -> CGFloat { rowH * 1.5 }
    /// The open track's toolbar between its steps and its keys: the lane switch, then KEY · SCALE · SNAP · FIT.
    private func toolbarH(_ rowH: CGFloat) -> CGFloat { rowH * 1.3 }
    private func layouts(rowH: CGFloat) -> [RowLayout] {
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
    private func layout(for pad: Int, _ L: [RowLayout]) -> RowLayout? { L.first { $0.channel.pad == pad } }
    private func layout(at y: CGFloat, _ L: [RowLayout]) -> RowLayout? { L.first { y >= $0.y && y < $0.y + $0.height } }
    /// The pitch a point in an expanded track means (0 for a collapsed row).
    private func semis(at y: CGFloat, in l: RowLayout) -> Float {
        guard let range = l.pitch else { return 0 }
        let row = Int((max(y, l.pitchTop) - l.pitchTop) / l.pitchRowH)
        return Float((range.upperBound - row).clamped(range.lowerBound, range.upperBound))
    }
    /// The expanded track's step band on top of its piano roll (its own steps, like a closed row).
    private func inBand(_ y: CGFloat, _ l: RowLayout) -> Bool { l.pitch != nil && y < l.y + l.bandH }
    /// The open track's toolbar strip (no notes there).
    private func inToolbar(_ y: CGFloat, _ l: RowLayout) -> Bool { l.pitch != nil && y >= l.y + l.bandH && y < l.pitchTop }
    /// The graph dropped down under the track opened with its arrow.
    private func inGraph(_ y: CGFloat, _ l: RowLayout) -> Bool { l.graphH > 0 && y >= l.graphTop && y < l.y + l.height }

    // MARK: Body — Tyrone's picture is the plate; the live controls sit on it at measured spots

    static let artW: CGFloat = 1536, artH: CGFloat = 1024
    /// Art rectangles (px in the picture): [x0, y0, x1, y1]
    enum A {
        static let tools: [[Double]] = [[305, 194, 393, 239], [397, 194, 485, 239], [489, 194, 576, 239]]
        static let undo: [Double] = [580, 194, 667, 239], redo: [Double] = [672, 194, 760, 239]
        static let stop: [Double] = [792, 193, 845, 240], play: [Double] = [849, 193, 902, 240], rec: [Double] = [904, 193, 957, 240]
        static let bpm: [Double] = [983, 194, 1102, 239], bars: [Double] = [1109, 194, 1222, 239], main: [Double] = [1230, 194, 1351, 239]
        static let gear: [Double] = [1356, 194, 1402, 239], cloud: [Double] = [1430, 193, 1484, 241]
        static let snap: [Double] = [877, 245, 1047, 279], swing: [Double] = [1059, 244, 1219, 279], humanize: [Double] = [1230, 244, 1368, 279]
        static let swingKnob: [Double] = [1188, 247, 1216, 275], humanizeKnob: [Double] = [1337, 247, 1365, 275]
        static let tempoSync: [Double] = [580, 245, 722, 279], followDAW: [Double] = [728, 245, 870, 279]
        static let pageBack: [Double] = [400, 246, 436, 280], pageText: [Double] = [436, 248, 534, 278], pageForward: [Double] = [534, 246, 572, 280]
        static let leftPanel: [Double] = [33, 300, 285, 693]
        /// The grips sit in the strip between the SOUNDS panel and the track headers.
        static let gripX0: Double = 285
        static let rackX0: Double = 298, rackX1: Double = 534, gridX0: Double = 549, gridX1: Double = 1445, panelX1: Double = 1495
        static let rowsY0: Double = 341, rowsY1: Double = 682, rowH: Double = 56.5, labelsY: Double = 325
        static let power: [Double] = [156, 715, 213, 772]
        static let patternBack: [Double] = [602, 732, 640, 772], patternForward: [Double] = [640, 732, 677, 772], patternChip: [Double] = [677, 732, 841, 772]
        static let kitBack: [Double] = [889, 732, 927, 772], kitForward: [Double] = [927, 732, 964, 772], kitChip: [Double] = [964, 732, 1129, 772]
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Self.artW, geo.size.height / Self.artH)
            ZStack(alignment: .topLeading) {
                Image(plateSprite).resizable().frame(width: Self.artW * s, height: Self.artH * s)
                BrandLogo(dark: finish != "modern", tagline: "DRUM SEQUENCER", scale: s).place([62, 182, 276, 274], s)
                topBar(s)
                leftPanel(s)
                editor(s)
                footer(s)
            }
            .frame(width: Self.artW * s, height: Self.artH * s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            // headers, slider, knob rims and control edges in the faceplate's metal
            .environment(\.seqFinish, finish)
        }
        .bbMenuHost()
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .background(spaceBar)
        .onReceive(ticker) { now in
            tick = now
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
        .onChange(of: loop) { _ in viewStart = 0; selection = []; undoStack = []; redoStack = []; controller.showPattern(loop) }
        .onDisappear { if controller.recording { controller.setRecording(false) } }
        .task(id: stored) { exportURL = writeMIDI() }
        .sheet(isPresented: $showMenu) { MenuView(controller: controller) }
        .sheet(isPresented: $shareMIDI) { if let url = exportURL { ShareSheet(items: [url]) } }
        .sheet(item: Binding(get: { trackSettingsID.flatMap { id in channels.first { $0.id == id } } }, set: { trackSettingsID = $0?.id })) { ch in
            VStack(spacing: 0) {
                Text("TRACK SETTINGS").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(S.dim).padding(.top, 16)
                channelStrip(ch).padding(.vertical, 12)
                Spacer()
            }
            .background(S.header.ignoresSafeArea()).preferredColorScheme(.dark).presentationDetents([.height(180)])
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

    @ViewBuilder private var spaceBar: some View {
        if !controller.isPlugin {
            Button("") { controller.togglePlayback(pattern: loop) }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }

    /// An invisible press area over a painted button.
    private func hit(_ r: [Double], _ s: CGFloat, action: @escaping () -> Void) -> some View {
        PressableArea(action: action).place(r, s)
    }
    private func artText(_ text: String, _ r: [Double], _ s: CGFloat, size: CGFloat = 15, weight: Font.Weight = .medium,
                         color: Color = .white, align: Alignment = .center) -> some View {
        Text(text).font(.system(size: size * s, weight: weight)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.6)
            .frame(width: (r[2] - r[0]) * s, height: (r[3] - r[1]) * s, alignment: align)
            .place(r, s)
    }
    /// The picture's knob, turned to the value (drag up or right to turn it up).
    private func artKnob(_ r: [Double], _ s: CGFloat, value: Float, change: @escaping (Float, Bool) -> Void) -> some View {
        ArtKnob(value: value, grip: 10 * s, change: change).place([r[0] - 10, r[1] - 10, r[2] + 10, r[3] + 10], s)
    }

    // MARK: Top bar

    @ViewBuilder private func topBar(_ s: CGFloat) -> some View {
        // DRAW / SELECT / ERASE: real buttons from the picture, the active one lit green
        ForEach(0..<3, id: \.self) { i in
            let t: Tool = [.draw, .select, .erase][i]
            let on = tool == t
            SeqButton("SeqBtnTool", lit: on ? S.green : nil, scale: s, action: { tool = t }) {
                HStack(spacing: 4 * s) {
                    Image(systemName: ["pencil", "rectangle.dashed", "eraser"][i]).font(.system(size: 13 * s, weight: .medium))
                    Text(["DRAW", "SELECT", "ERASE"][i]).font(.system(size: 13 * s, weight: .medium))
                }
                .foregroundColor(on ? S.green : .white)
            }
            .place(A.tools[i], s)
        }
        SeqButton("SeqBtnTool", scale: s, action: { undo() }) {
            HStack(spacing: 4 * s) { Image(systemName: "arrow.uturn.backward").font(.system(size: 13 * s, weight: .medium)); Text("UNDO").font(.system(size: 13 * s, weight: .medium)) }
                .foregroundColor(undoStack.isEmpty ? Color(white: 0.5) : .white)
        }
        .keyboardShortcut("z", modifiers: .command)
        .accessibilityIdentifier("undoButton")
        .place(A.undo, s)
        SeqButton("SeqBtnTool", scale: s, action: { redo() }) {
            HStack(spacing: 4 * s) { Image(systemName: "arrow.uturn.forward").font(.system(size: 13 * s, weight: .medium)); Text("REDO").font(.system(size: 13 * s, weight: .medium)) }
                .foregroundColor(redoStack.isEmpty ? Color(white: 0.5) : .white)
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .accessibilityIdentifier("redoButton")
        .place(A.redo, s)
        // bars pager
        artText(pageLabel, A.pageText, s, size: 17, weight: .medium, color: inkColor).accessibilityIdentifier("pageLabel")
        SeqGlyph(symbol: "chevron.left", scale: s, enabled: pageStart > 0, color: inkColor) { scroll(to: pageStart - windowTicks) }.place(A.pageBack, s)
        SeqGlyph(symbol: "chevron.right", scale: s, enabled: pageStart < maxStart, color: inkColor) { scroll(to: pageStart + windowTicks) }.place(A.pageForward, s)
        // transport
        SeqButton("SeqBtnTransport", scale: s, action: { controller.stopPlayback() }) {
            RoundedRectangle(cornerRadius: 2 * s).fill(Color.white).frame(width: 15 * s, height: 15 * s)
        }
        .place(A.stop, s)
        SeqButton("SeqBtnTransport", lit: isThisPlaying ? S.green : nil, scale: s, action: { controller.playPattern(loop) }) {
            Image(systemName: "play.fill").font(.system(size: 17 * s)).foregroundColor(S.green)
        }
        .place(A.play, s)
        SeqButton("SeqBtnTransport", lit: controller.recording ? S.red : nil, scale: s, action: { if !controller.recording { remember() }; controller.toggleRecordPads(loop: loop) }) {
            if controller.countingIn {
                Text("\(controller.countInBeatsLeft)").font(.system(size: 20 * s, weight: .bold, design: .rounded)).foregroundColor(S.red)
            } else {
                Circle().fill(S.red).frame(width: 17 * s, height: 17 * s).shadow(color: controller.recording ? S.red : .clear, radius: 5 * s)
            }
        }
        .place(A.rec, s)
        // TEMPO SYNC and FOLLOW DAW (the same switches as Face 1's LEDs): lit green when on
        hostSwitch("TEMPO SYNC", .tempoSync, A.tempoSync, s)
        hostSwitch("FOLLOW DAW", .followDAW, A.followDAW, s)
        // tempo, bars, pattern, gear, cloud
        // tempo: slide up for faster, down for slower; a tap opens the tempo panel
        SeqChip(sprite: "SeqChipBpm", text: "\(Int(controller.liveTempo.rounded())) BPM", scale: s, color: tempoDragStart == nil ? .white : S.green)
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10 * s, weight: .bold)).foregroundColor(Color(white: 0.75))
                    .padding(.trailing, 8 * s).allowsHitTesting(false)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 6)
                .onChanged { g in
                    guard !controller.tempoIsExternal else { return }
                    if tempoDragStart == nil { tempoDragStart = controller.state.bpm }
                    let bpm = ((tempoDragStart ?? 120) - Double(g.translation.height) / 3).rounded()
                    if bpm != controller.state.bpm { controller.setBPM(min(280, max(40, bpm))) }
                }
                .onEnded { _ in tempoDragStart = nil })
            .accessibilityIdentifier("tempoChip")
            .bbPanelPlaced(A.bpm, s, title: "Tempo", width: 340) { TempoPanel(controller: controller) }
        SeqChip(sprite: "SeqChipBars", text: "\(bars) BARS", scale: s)
            .accessibilityIdentifier("barsChip")
            .bbMenuPlaced(A.bars, s, title: "Pattern length") {
                [2, 4, 8, 16].map { b in BBMenuItem.item("\(b) BARS", checked: bars == b) { commit(PatternEdit.setLength(pattern, bars: b)) } }
            }
        SeqArt(sprite: "SeqBtnGear", scale: s) { EmptyView() }
            .bbMenuPlaced(A.gear, s, title: "Sequencer", width: 330) { settingsItems() }
        SeqArt(sprite: "SeqBtnCloud", corner: 9, scale: s) { EmptyView() }
            .bbMenuPlaced(A.cloud, s, title: "MIDI", width: 360) {
                [.header("MIDI file"),
                 BBMenuItem.item("Share this pattern as a MIDI file", detail: "12 tracks, one per channel, pitch and velocity", icon: "square.and.arrow.up", enabled: exportURL != nil) { shareMIDI = true },
                 .header("MIDI out")] + midiOutItems()
            }
        // snap, scale, swing, humanize
        SeqChip(sprite: "SeqChipSnap", text: snapLabel, size: 13, leading: 64, trailing: 28, scale: s)
            .bbMenuPlaced(A.snap, s, title: "Snap", width: 300) {
                Self.snapChoices.flatMap { group -> [BBMenuItem] in
                    [.header(group.section)] + group.items.map { item in BBMenuItem.item(item.0, checked: item.1 == snap) { snap = item.1 } }
                }
            }
        // SNAP TO SCALE: a tuning fork on the SNAP chip's left edge (green when on)
        Image(systemName: "tuningfork").font(.system(size: 11 * s, weight: .semibold)).foregroundColor(controller.snapToScale ? S.green : Color(white: 0.45))
            .bbMenu(title: "Snap to scale", width: 300) { scaleItems(selectedPad) }
            .place([A.snap[0] + 2, A.snap[1], A.snap[0] + 22, A.snap[3]], s)
        SeqChip(sprite: "SeqChipSwing", text: swingLabel, size: 13, leading: 76, trailing: 46, scale: s).place(A.swing, s).allowsHitTesting(false)
        PressGlow().bbPanelPlaced([A.swing[0], A.swing[1], A.swingKnob[0] - 4, A.swing[3]], s, title: "Swing", width: 320) {
                BBSlider(value: Double(50 + controller.value(.bounce) * 22), range: 50...72, step: 1, label: { $0 <= 50 ? "OFF" : "\(Int($0))%" }) {
                    controller.set(.bounce, Float(($0 - 50) / 22))
                }
            }
        artKnob(A.swingKnob, s, value: controller.value(.bounce)) { v, ended in
            if swingStart == nil { swingStart = controller.value(.bounce) }
            controller.set(.bounce, v)
            if ended { swingStart = nil }
        }
        SeqArt(sprite: "SeqChipHumanize", scale: s) { EmptyView() }.place(A.humanize, s).allowsHitTesting(false)
        PressGlow().bbPanelPlaced([A.humanize[0], A.humanize[1], A.humanizeKnob[0] - 4, A.humanize[3]], s, title: "Humanize", width: 320) {
                BBSlider(value: Double((pattern.humanize ?? 0) * 100), range: 0...100, step: 1, label: { $0 < 1 ? "OFF" : "\(Int($0))%" }) { v in
                    remember(coalescing: true)
                    var p = pattern
                    p.humanize = v < 1 ? nil : Float(v / 100)
                    controller.setLoop(loop, p)
                }
            }
        artText((pattern.humanize ?? 0) < 0.01 ? "" : "\(Int((pattern.humanize ?? 0) * 100))%", [A.humanize[0] + 96, A.humanize[1], A.humanizeKnob[0] - 2, A.humanize[3]], s, size: 11, color: S.green, align: .trailing)
        artKnob(A.humanizeKnob, s, value: pattern.humanize ?? 0) { v, ended in
            if humanizeStart == nil { humanizeStart = pattern.humanize ?? 0; undoStack.append(pattern); redoStack = [] }
            var p = pattern
            p.humanize = v < 0.01 ? nil : v
            work = p
            if ended { humanizeStart = nil; work = nil; controller.setLoop(loop, p) }
        }
    }

    /// A host transport switch on the top rail: its lamp and name, green when on.
    private func hostSwitch(_ title: String, _ p: KParam, _ r: [Double], _ s: CGFloat) -> some View {
        let on = controller.value(p) > 0.5
        return SeqButton("SeqBtnTool", lit: on ? S.green : nil, scale: s, action: { controller.toggle(p) }) {
            HStack(spacing: 6 * s) {
                Circle().fill(on ? S.green : Color(white: 0.28)).frame(width: 7 * s, height: 7 * s)
                    .shadow(color: on ? S.green : .clear, radius: 3 * s)
                Text(title).font(.system(size: 12 * s, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(on ? S.green : .white)
        }
        .accessibilityIdentifier(p == .tempoSync ? "tempoSyncButton" : "followDAWButton")
        .place(r, s)
    }

    private func settingsItems() -> [BBMenuItem] {
        [
            .item("BreaKing menu…", icon: "line.3.horizontal") { showMenu = true },
            .item("Follow playhead", icon: "arrow.right.to.line", checked: follow) { follow.toggle() },
            .submenu("Loop on screen: \(loop + 1)", icon: "repeat", controller.loops.indices.map { i in
                BBMenuItem.item("\(i + 1)  \(controller.loops[i].name)", checked: i == loop) { loop = i }
            }),
            .item("Metronome", icon: "metronome", checked: controller.metronome) { controller.setMetronome(!controller.metronome) },
            .submenu("Record count-in", icon: "record.circle", [1, 2].map { b in
                BBMenuItem.item("\(b) bar\(b == 1 ? "" : "s")", checked: controller.countInBars == b) { controller.setCountInBars(b) }
            }),
            .item("Record keeps my timing", detail: "hits land on the grid and play as early or late as you played them (NOTE OFFSET)",
                  icon: "hand.tap", checked: controller.recordKeepsFeel) { controller.setRecordKeepsFeel(!controller.recordKeepsFeel) },
            .item("Duplicate \(selection.isEmpty ? "the pattern" : "selection")", icon: "plus.square.on.square") { duplicate() },
            .item("Copy these bars to the next ones", icon: "doc.on.doc") {
                commit(PatternEdit.copyNext(pattern, fromBar: Int(pageStart / PatternEdit.barTicks), bars: max(1, Int(pageTicks / PatternEdit.barTicks))))
            },
            .item("Quantize \(selection.isEmpty ? "all notes" : "selection")", detail: "back on the grid, note offsets cleared", icon: "squareshape.split.3x3") {
                commit(PatternEdit.quantize(pattern, selection.isEmpty ? nil : selection, grid: snapTicks > 0 ? snapTicks : PatternData.stepTicks))
            },
            .item("Back to the preset's pattern", icon: "arrow.uturn.backward") { remember(); controller.useGeneratedLoop(loop); selection = [] },
            .item("Kit's 12 channels back in the rack", icon: "square.grid.3x3") { controller.resetRack(); expandedID = nil; openID = nil; selectedID = nil },
            .item("Clear \(selection.isEmpty ? "the pattern" : "selection")", icon: "trash", destructive: true) { clear() }
        ]
    }

    private var swingLabel: String { controller.value(.bounce) < 0.01 ? "OFF" : "\(Int(50 + controller.value(.bounce) * 22))%" }

    private var pageLabel: String {
        let bar = Int(pageStart / PatternEdit.barTicks) + 1
        if zoomLevel == 0 {
            let last = min(bars, Int((pageStart + windowTicks - 1) / PatternEdit.barTicks) + 1)
            return last == bar ? "BAR \(bar)" : "BARS \(bar)-\(last)"
        }
        let beat = Int((pageStart % PatternEdit.barTicks) / PatternData.ppq) + 1
        return zoomLevel == 1 ? "BAR \(bar) · ZOOM" : "BAR \(bar).\(beat) · ZOOM"
    }


    // MARK: Left panel: GENERAL (the sound library) · GENERATE · MIDI, on the picture's panel

    private var sounds: [LibrarySound] { userSounds + Self.factorySounds }
    private var shownSounds: [LibrarySound] {
        var list = sounds
        if let libraryType { list = list.filter { $0.type == libraryType } }
        if !search.isEmpty {
            let q = search.uppercased()
            list = list.filter { $0.name.uppercased().contains(q) || $0.pack.uppercased().contains(q) }
        }
        return list
    }

    /// A section header: a plate of platinum (the slider knob's metal) the full width of the panel,
    /// square and flush against the well under it. Tap it to slide the panels over.
    private func sectionHeader(_ title: String, open: Bool, _ s: CGFloat) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { section = section == .sounds ? .generate : .sounds }
        } label: {
            ZStack {
                PlatinumPlate()
                HStack {
                    Text(title).font(.system(size: 15 * s, weight: .semibold)).foregroundColor(MetalTone.of(finish).ink).kerning(0.5)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(MetalTone.of(finish).ink)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.leading, 18 * s).padding(.trailing, 18 * s)
            }
            .frame(height: 44 * s)
        }
        .buttonStyle(PlatePress())
        .accessibilityIdentifier(title == "SOUNDS" ? "soundsHeader" : "generateHeader")
    }

    /// The left panel: SOUNDS and GENERATE, each a platinum plate over its dark well. Opening one
    /// slides the GENERATE plate up or down like a piece of metal, closing the other well under it.
    @ViewBuilder private func leftPanel(_ s: CGFloat) -> some View {
        let r = A.leftPanel
        let headerH = 44.0 * s
        let wellH = CGFloat(r[3] - r[1]) * s - 2 * headerH
        VStack(spacing: 0) {
            sectionHeader("SOUNDS", open: section == .sounds, s)
            well(soundsPanel(s), height: wellH, open: section == .sounds, s)
            sectionHeader("GENERATE", open: section == .generate, s)
            well(generatePanel(s), height: wellH, open: section == .generate, s)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8 * s))
        .overlay(RoundedRectangle(cornerRadius: 8 * s).strokeBorder(Color.black.opacity(0.55), lineWidth: 1))
        .place(r, s)
    }

    /// A dark well under a plate: the content keeps its size and the plate below slides over it.
    private func well<Content: View>(_ content: Content, height: CGFloat, open: Bool, _ s: CGFloat) -> some View {
        content
            .frame(height: height, alignment: .top)
            .background(Color(white: 0.04))
            .overlay(alignment: .top) {
                // the plate above throws its shadow into the well
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 6 * s).allowsHitTesting(false)
            }
            .frame(height: open ? height : 0, alignment: .top)
            .clipped()
    }

    /// GENERATE: GENRE, UPDATE SOUNDS, UPDATE TEMPO, Generate, Clear.
    private func generatePanel(_ s: CGFloat) -> some View {
        let line = Rectangle().fill(Color(white: 0.2)).frame(height: 1)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3 * s) {
                Text("GENRE").font(.system(size: 12 * s, weight: .medium)).foregroundColor(S.dim)
                HStack {
                    Text(generateStyle ?? PatternRandomizer.style(for: controller.state.presetName))
                        .font(.system(size: 17 * s)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16 * s).frame(maxWidth: .infinity, minHeight: 70 * s, alignment: .leading)
            .bbMenu(title: "Genre", width: 280) {
                [BBMenuItem.item("This preset's style", checked: generateStyle == nil) { generateStyle = nil }]
                + PatternBank.styles.map { st in BBMenuItem.item(st, checked: generateStyle == st) { generateStyle = st } }
            }
            line
            HStack(spacing: 0) {
                generateSwitch("UPDATE SOUNDS", on: updateSounds, s) { updateSounds.toggle() }
                Rectangle().fill(Color(white: 0.2)).frame(width: 1)
                generateSwitch("UPDATE TEMPO", on: updateTempo, s) { updateTempo.toggle() }
            }
            .frame(height: 70 * s)
            line
            Spacer(minLength: 0)
            HStack(spacing: 8 * s) {
                SeqButton("SeqBtnGenerate", corner: 8, scale: s) { generate() }.frame(width: 125 * s, height: 46 * s)
                Button { clear() } label: {
                    HStack(spacing: 6 * s) {
                        Image(systemName: "xmark").font(.system(size: 15 * s, weight: .medium))
                        Text("Clear").font(.system(size: 15 * s, weight: .medium))
                    }
                    .foregroundColor(.white).frame(width: 84 * s, height: 46 * s)
                    .background(RoundedRectangle(cornerRadius: 8 * s).fill(Color(white: 0.11)).overlay(RoundedRectangle(cornerRadius: 8 * s).stroke(Color(white: 0.3), lineWidth: 1)))
                }
                .buttonStyle(SeqPress())
            }
            .padding(.bottom, 20 * s)
        }
    }

    private func generateSwitch(_ title: String, on: Bool, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(title).font(.system(size: 11 * s, weight: .medium)).foregroundColor(S.dim).lineLimit(1).minimumScaleFactor(0.7)
                Text(on ? "On" : "Off").font(.system(size: 16 * s)).foregroundColor(on ? .white : Color(white: 0.5))
            }
            .padding(.horizontal, 12 * s).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SeqPress())
    }

    /// The sound library (SOUNDS open): type chips, search, the list, import. Drag a sound to the rack.
    private func soundsPanel(_ s: CGFloat) -> some View {
        VStack(spacing: 5 * s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3 * s) {
                    typeChip("ALL", on: libraryType == nil, s) { libraryType = nil }
                    ForEach(SoundType.allCases) { t in typeChip(t.rawValue, on: libraryType == t, s) { libraryType = t } }
                }
            }
            HStack(spacing: 5 * s) {
                Image(systemName: "magnifyingglass").font(.system(size: 11 * s)).foregroundColor(S.dim)
                TextField("Search", text: $search).font(.system(size: 13 * s)).foregroundColor(.white).autocorrectionDisabled()
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12 * s)).foregroundColor(S.dim) } }
            }
            .padding(.horizontal, 8 * s).frame(height: 30 * s).background(RoundedRectangle(cornerRadius: 6 * s).fill(Color(white: 0.12)))
            ScrollView {
                LazyVStack(spacing: 2 * s) {
                    ForEach(shownSounds) { sound in soundRow(sound, s) }
                    if shownSounds.isEmpty { Text("Nothing here yet.").font(.system(size: 12 * s)).foregroundColor(S.dim).padding(16 * s) }
                }
            }
            HStack(spacing: 5 * s) {
                Button { importKind = .sounds } label: { smallLabel("square.and.arrow.down", "SOUNDS", s) }
                Button { importKind = .pack } label: { smallLabel("folder.badge.plus", "PACK", s) }
                if let pad = selectedPad, !controller.isPlugin { Button { recordPad = pad } label: { smallLabel("record.circle", "REC", s) } }
            }
            Text(libraryNote.isEmpty ? "DRAG A SOUND ONTO THE RACK" : libraryNote).font(.system(size: 8 * s, weight: .semibold)).foregroundColor(S.dim).lineLimit(1)
        }
        .padding(.horizontal, 8 * s).padding(.top, 10 * s).padding(.bottom, 8 * s)
    }

    private func soundRow(_ sound: LibrarySound, _ s: CGFloat) -> some View {
        let onSelected = selected?.soundID == sound.id
        return HStack(spacing: 6 * s) {
            Image(systemName: "waveform").font(.system(size: 10 * s)).foregroundColor(onSelected ? S.green : S.dim).frame(width: 14 * s)
            VStack(alignment: .leading, spacing: 0) {
                Text(sound.name).font(.system(size: 12 * s, weight: .medium)).foregroundColor(onSelected ? S.green : .white).lineLimit(1)
                Text(sound.pack).font(.system(size: 8 * s)).foregroundColor(S.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            if sound.user { Text("YOURS").font(.system(size: 7 * s, weight: .bold)).foregroundColor(S.orange) }
            Image(systemName: "line.3.horizontal").font(.system(size: 10 * s)).foregroundColor(S.dim.opacity(0.6))
        }
        .padding(.horizontal, 6 * s).frame(height: 34 * s)
        .background(RoundedRectangle(cornerRadius: 5 * s).fill(onSelected ? S.green.opacity(0.12) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture {
            guard let ch = selected else { return }
            controller.replaceRackSound(ch.id, with: sound)
            let pad = ch.pad
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { controller.auditionPad(pad) }
        }
        .onDrag {
            NSItemProvider(object: (soundDragPrefix + sound.id) as NSString)
        } preview: {
            Text(sound.name).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                .padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(S.green))
        }
    }

    private func typeChip(_ title: String, on: Bool, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 9 * s, weight: .semibold))
                .foregroundColor(on ? .black : .white).padding(.horizontal, 7 * s).frame(height: 22 * s)
                .background(RoundedRectangle(cornerRadius: 4 * s).fill(on ? S.green : Color(white: 0.2)))
        }
    }

    private func smallLabel(_ icon: String, _ title: String, _ s: CGFloat) -> some View {
        HStack(spacing: 3 * s) {
            Image(systemName: icon).font(.system(size: 10 * s, weight: .medium))
            Text(title).font(.system(size: 9 * s, weight: .semibold))
        }
        .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 28 * s)
        .background(RoundedRectangle(cornerRadius: 5 * s).fill(Color(white: 0.2)).overlay(RoundedRectangle(cornerRadius: 5 * s).stroke(Color(white: 0.3), lineWidth: 1)))
    }

    /// Generate: new steps in the chosen genre; UPDATE SOUNDS rolls new sounds on every channel too;
    /// UPDATE TEMPO sets the genre's tempo.
    private func generate() {
        let style = generateStyle ?? PatternRandomizer.style(for: controller.state.presetName)
        remember()
        controller.randomizePattern(style: style)
        if updateSounds { controller.dice() }
        if updateTempo, !controller.tempoIsExternal {
            let bpms = PatternBank.presets(in: style).map(\.bpm)
            if !bpms.isEmpty { controller.setBPM((bpms.reduce(0, +) / Double(bpms.count)).rounded()) }
        }
        selection = []
    }

    // MARK: Track settings (sound, tune, decay, filter, reverse, solo, MIDI): from the channel's menu

    private func channelStrip(_ ch: WorkspaceChannel) -> some View {
        let pad = ch.pad
        let ps = controller.state.pads[pad]
        func set(_ change: (inout PadSettings) -> Void) { var v = controller.state.pads[pad]; change(&v); controller.setPadSettings(pad, v) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ch.name).font(.system(size: 13, weight: .semibold)).foregroundColor(S.green).lineLimit(1)
                    Text(controller.padName(pad).uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(S.dim).lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)
                labelBox("waveform", "SOUND").bbMenu(title: ch.name, width: 320) { channelSampleItems(ch) }
                labelBox("cable.connector", midiOutLabel(pad), lit: controller.midiOutOn && controller.midiOutChannels[pad] >= 0)
                    .bbMenu(title: "MIDI out · \(ch.name)", width: 240) { midiOutChannelItems(pad) }
                divider
                stripKnob("TUNE", ps.tune, -24...24, String(format: "%+.1f", ps.tune)) { v in set { $0.tune = (v * 2).rounded() / 2 } }
                stripKnob("DECAY", ps.decay, 0.05...1, ps.decay >= 0.999 ? "FULL" : String(format: "%.0f%%", ps.decay * 100)) { v in set { $0.decay = v } }
                stripKnob("FILTER", ps.filter, 0...1, ps.filter >= 0.999 ? "OPEN" : String(format: "%.0f Hz", 40 * powf(450, ps.filter))) { v in set { $0.filter = v } }
                Button { set { $0.reverse.toggle() } } label: { labelBox("arrow.left.arrow.right", "REV", lit: ps.reverse) }
                Button { controller.toggleSolo(pad) } label: { labelBox("s.square", "SOLO", lit: controller.soloPads[pad]) }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 64)
        .background(S.channel)
    }

    private func channelSampleItems(_ ch: WorkspaceChannel) -> [BBMenuItem] {
        let pad = ch.pad
        var items: [BBMenuItem] = [.item("Load a sample from Files…", icon: "folder") { importPad = pad }]
        if !controller.isPlugin { items.append(.item("Record to this channel…", icon: "record.circle") { recordPad = pad }) }
        if controller.state.pads[pad].sampleFile != nil {
            items.append(.item("Back to the kit's sound", icon: "arrow.uturn.backward", destructive: true) { controller.revertPad(pad) })
        }
        return items
    }

    private func stripKnob(_ title: String, _ value: Float, _ range: ClosedRange<Float>, _ text: String,
                           set: @escaping (Float) -> Void) -> some View {
        let norm = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return HStack(spacing: 6) {
            DrumRollKnob(value: norm) { v, _ in set(range.lowerBound + v * (range.upperBound - range.lowerBound)) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(S.dim)
                Text(text).font(.system(size: 12, design: .monospaced)).foregroundColor(S.text)
            }
            .frame(width: 58, alignment: .leading)
        }
    }

    // MARK: Editor: the rack and the grid on the picture's panels

    @ViewBuilder private func editor(_ s: CGFloat) -> some View {
        let rowH = A.rowH * s
        let gridW = (A.gridX1 - A.gridX0) * s
        let L = layouts(rowH: rowH)
        // room under the last track for the next sound (the drop slot), plus a little to scroll past it
        let contentH = max((L.last.map { $0.y + $0.height } ?? 0) + (channels.count < Pad.count ? rowH : 0) + 12 * s, (A.rowsY1 - A.rowsY0) * s)
        // beat numbers
        ruler(width: gridW).place([A.gridX0, A.labelsY - 14, A.gridX1, A.rowsY0 - 1], s)
        // the rows: rack column and the grid, scrolling together
        ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: (A.panelX1 - A.gripX0) * s, height: contentH).id("rackTop")
                rackColumn(L, rowH: rowH, s: s).frame(width: (A.rackX1 - A.gripX0) * s, height: contentH, alignment: .top)
                grid(L, width: gridW, rowH: rowH).frame(width: gridW, height: contentH)
                    .offset(x: (A.gridX0 - A.gripX0) * s)
                // the dice at the end of every track: that track's steps only
                ForEach(L, id: \.channel.id) { l in
                    // dice: new steps for this track only; ✕: clear this track in one tap
                    VStack(spacing: 3 * s) {
                        Button { selectedID = l.channel.id; remember(); controller.randomizeChannel(loop: loop, pad: l.channel.pad); selection = [] } label: {
                            Image(systemName: "dice").font(.system(size: 12 * s)).foregroundColor(Color(white: 0.8))
                                .frame(width: 30 * s, height: 24 * s).background(RoundedRectangle(cornerRadius: 5 * s).fill(Color(white: 0.14)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(SeqPress())
                        Button { selectedID = l.channel.id; commit(PatternEdit.clearChannel(pattern, pad: l.channel.pad)); selection = [] } label: {
                            Image(systemName: "xmark").font(.system(size: 11 * s, weight: .bold)).foregroundColor(Color(white: 0.8))
                                .frame(width: 30 * s, height: 24 * s).background(RoundedRectangle(cornerRadius: 5 * s).fill(Color(white: 0.14)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(SeqPress())
                    }
                    .offset(x: (A.gridX1 + 10 - A.gripX0) * s, y: l.y + (min(l.height, rowH) - 51 * s) / 2)
                }
            }
        }
        .onAppear { proxy.scrollTo("rackTop", anchor: .top) }      // the first row at the top, always
        }
        .frame(width: (A.panelX1 - A.gripX0) * s, height: (A.rowsY1 - A.rowsY0) * s)
        .position(x: (A.gripX0 + A.panelX1) / 2 * s, y: (A.rowsY0 + A.rowsY1) / 2 * s)
        .onDrop(of: [.plainText, .fileURL, .audio], isTargeted: $rackTargeted) { providers in dropOnRack(providers, channel: nil) }
        if rackTargeted {
            RoundedRectangle(cornerRadius: 8 * s).stroke(S.green, lineWidth: 2 * s).place([A.rackX0, A.rowsY0 - 4, A.rackX1, A.rowsY1], s).allowsHitTesting(false)
        }
    }

    /// The graph dropped down under the open track: velocity bars, or pitch bars either side of a centre line.
    private func drawGraph(_ ctx: GraphicsContext, _ l: RowLayout, width: CGFloat) {
        let top = l.graphTop, h = l.graphH
        let pad = l.channel.pad
        ctx.fill(Path(CGRect(x: 0, y: top, width: width, height: h)), with: .color(S.lane))
        for frac in [0.0, 0.5, 1.0] {
            ctx.fill(Path(CGRect(x: 0, y: top + 4 + CGFloat(frac) * (h - 8), width: width, height: 1)), with: .color(S.stepLine))
        }
        var lt = ((pageStart + PatternData.ppq - 1) / PatternData.ppq) * PatternData.ppq
        while lt <= pageStart + pageTicks {
            let bx = CGFloat(lt - pageStart) / CGFloat(pageTicks) * width
            ctx.fill(Path(CGRect(x: bx, y: top, width: lt % PatternEdit.barTicks == 0 ? 1.5 : 1, height: h)), with: .color(lt % PatternEdit.barTicks == 0 ? S.beatLine : S.stepLine))
            lt += PatternData.ppq
        }
        for m in lane.marks {
            let y = top + 4 + (1 - m.1) * (h - 8)
            ctx.draw(Text(m.0).font(.system(size: 9, design: .monospaced)).foregroundColor(Color.white.opacity(0.5)),
                     at: CGPoint(x: width - 4, y: m.1 == 1 ? y + 2 : (m.1 == 0 ? y - 2 : y)), anchor: m.1 == 1 ? .topTrailing : (m.1 == 0 ? .bottomTrailing : .trailing))
        }
        let mid = top + 4 + 0.5 * (h - 8)
        for e in pattern.events where visible(e) && Int(e.pad) == pad {
            let sel = selection.contains(NoteKey(e))
            let bx = x(e.tick, width) + 2
            let color = (sel ? Color.white : noteColor).opacity(selection.isEmpty || sel ? 0.95 : 0.35)
            let y = top + 4 + (1 - lane.value(e)) * (h - 8)
            if !lane.centred {
                ctx.fill(Path(roundedRect: CGRect(x: bx, y: y, width: 6, height: top + h - 4 - y), cornerRadius: 1.5), with: .color(color))
            } else {
                let r = CGRect(x: bx, y: min(y, mid), width: 6, height: max(3, abs(mid - y)))
                ctx.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(color))
                if let label = lane.label(e) {
                    ctx.draw(Text(label).font(.system(size: 8, weight: .bold)).foregroundColor(.white),
                             at: CGPoint(x: bx + 3, y: y < mid ? y - 6 : y + 6))
                }
            }
        }
    }

    /// The beat numbers over the grid (bar.beat). Drag them sideways to slide along a long pattern.
    private func ruler(width: CGFloat) -> some View {
        Canvas { ctx, size in
            let px = { (t: Int32) in CGFloat(t - pageStart) / CGFloat(pageTicks) * size.width }
            var t = (pageStart + PatternData.ppq - 1) / PatternData.ppq * PatternData.ppq
            while t < pageStart + pageTicks {
                let bar = t / PatternEdit.barTicks + 1, beat = (t % PatternEdit.barTicks) / PatternData.ppq + 1
                let label = beat == 1 ? "\(bar)" : "\(bar).\(beat)"
                ctx.draw(Text(label).font(.system(size: size.height * 0.46, weight: beat == 1 ? .bold : .medium)).foregroundColor(beat == 1 ? .white : Color(white: 0.75)),
                         at: CGPoint(x: px(t) + size.height * 0.5, y: size.height * 0.42))
                t += PatternData.ppq
            }
            // where the window sits in the whole pattern
            if totalTicks > windowTicks {
                let x0 = CGFloat(pageStart) / CGFloat(totalTicks) * size.width
                let w = max(24, CGFloat(windowTicks) / CGFloat(totalTicks) * size.width)
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: size.height - 3, width: size.width, height: 3), cornerRadius: 1.5), with: .color(Color.white.opacity(0.12)))
                ctx.fill(Path(roundedRect: CGRect(x: x0, y: size.height - 3, width: w, height: 3), cornerRadius: 1.5), with: .color(noteColor))
            }
            _ = tick
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { g in
                if rulerDragStart == nil { rulerDragStart = pageStart }
                scroll(to: (rulerDragStart ?? 0) - Int32(g.translation.width / max(1, width) * CGFloat(windowTicks)))
            }
            .onEnded { _ in rulerDragStart = nil })
        .accessibilityElement()
        .accessibilityIdentifier("ruler")
    }

    // MARK: Channel rack (the picture's rows)

    private func rackColumn(_ L: [RowLayout], rowH: CGFloat, s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(L, id: \.channel.id) { l in
                let moving = movingPad == l.channel.pad
                HStack(alignment: .top, spacing: 0) {
                    trackGrip(l, s: s).frame(width: (A.rackX0 - A.gripX0) * s, height: l.bandH)
                    channelRow(l, rowH: rowH, s: s)
                }
                .scaleEffect(moving ? 1.03 : 1)
                .shadow(color: .black.opacity(moving ? 0.6 : 0), radius: 8 * s, y: 4 * s)
                .offset(y: moving ? movingTop : l.y)
                .zIndex(moving ? 1 : 0)
            }
            if channels.count < Pad.count {
                let y = (L.last.map { $0.y + $0.height } ?? 0)
                VStack(spacing: 3 * s) {
                    Image(systemName: "plus.circle.dashed").font(.system(size: 16 * s)).foregroundColor(rackTargeted ? S.green : Color(white: 0.45))
                    Text(rackTargeted ? "DROP FOR A NEW CHANNEL" : "DROP A SOUND HERE").font(.system(size: 8 * s, weight: .semibold)).foregroundColor(rackTargeted ? S.green : Color(white: 0.45))
                }
                .frame(width: (A.rackX1 - A.rackX0) * s, height: rowH).offset(x: (A.rackX0 - A.gripX0) * s, y: y)
            }
        }
    }

    /// Where a dragged track lands: after every other track whose middle is above its middle.
    private func dropIndex(pad: Int, centre: CGFloat, _ L: [RowLayout]) -> Int {
        L.filter { $0.channel.pad != pad && $0.y + $0.height / 2 < centre }.count
    }

    /// The pull tab left of a track header: brushed silver with three grooves, like the reorder bars
    /// of an iPad list. Drag it up or down and the track goes with your finger straight away; the
    /// other tracks (and their steps) slide out of its way, and it settles where you let go.
    private func trackGrip(_ l: RowLayout, s: CGFloat) -> some View {
        let pad = l.channel.pad
        let moving = movingPad == pad
        return ZStack {
            RoundedRectangle(cornerRadius: 3 * s)
                .fill(LinearGradient(colors: [Color(white: 0.93), Color(white: 0.72), Color(white: 0.84)], startPoint: .leading, endPoint: .trailing))
                .overlay(RoundedRectangle(cornerRadius: 3 * s).stroke(moving ? noteColor : Color(white: 0.45), lineWidth: (moving ? 1.4 : 0.8) * s))
                .shadow(color: moving ? noteColor.opacity(0.7) : .black.opacity(0.35), radius: (moving ? 4 : 1.5) * s, y: moving ? 0 : 1 * s)
                .frame(width: 11 * s, height: 40 * s)
            VStack(spacing: 3.5 * s) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(spacing: 0) {
                        Rectangle().fill(Color(white: 0.3)).frame(height: 1.2 * s)
                        Rectangle().fill(Color.white.opacity(0.85)).frame(height: 0.8 * s)
                    }
                    .frame(width: 7 * s)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { g in
                if movingPad != pad {
                    movingPad = pad; movingFrom = l.y; movingTop = l.y
                    selectedID = l.channel.id
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                movingTop = movingFrom + g.translation.height
                // the others make room as soon as the track passes their middle
                let to = dropIndex(pad: pad, centre: movingTop + l.bandH / 2, layouts(rowH: A.rowH * s))   // where the tracks are now
                if to != controller.rackOrder.firstIndex(of: pad) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { controller.moveRackChannel(pad: pad, to: to) }
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { movingPad = nil }
            })
        .accessibilityElement()
        .accessibilityLabel("Move \(l.channel.name) up or down")
        .accessibilityIdentifier("trackGrip\(pad)")
    }

    private func channelRow(_ l: RowLayout, rowH: CGFloat, s: CGFloat) -> some View {
        let ch = l.channel, pad = ch.pad
        // a SOLO on another track silences this one too: its lamp goes dark the same as a mute
        let soloedOut = controller.soloPads.contains(true) && !controller.soloPads[pad]
        let muted = controller.mutedPads[pad] || soloedOut
        let isSel = selectedID == ch.id
        let ps = controller.state.pads[pad]
        func set(_ change: (inout PadSettings) -> Void) { var v = controller.state.pads[pad]; change(&v); controller.setPadSettings(pad, v) }
        // art offsets inside the row sprite (298, 334): triangle 303-312, oval 321-524, name 335-425, knobs 440 / 478, lamp 509
        let X = { (ax: Double) in CGFloat(ax - A.rackX0) * s }
        return ZStack(alignment: .topLeading) {
            Image(rowSprite).resizable().frame(width: 240 * s, height: 58 * s)
                .opacity(newborn.contains(ch.id) ? 0 : 1)
            // a dropped sound: a dot in the faceplate's colour grows into the track's oval, then settles
            if newborn.contains(ch.id) || settling.contains(ch.id) {
                Capsule().fill(noteColor)
                    .frame(width: (newborn.contains(ch.id) ? 45 : 203) * s, height: 45 * s)
                    .shadow(color: noteColor.opacity(0.8), radius: 8 * s)
                    .opacity(settling.contains(ch.id) && !newborn.contains(ch.id) ? 0.0 : 1)
                    .offset(x: X(321), y: 5 * s)
                    .allowsHitTesting(false)
            }
            // the lit oval of the selected track
            if isSel {
                Capsule().stroke(noteColor, lineWidth: 1.5 * s).shadow(color: noteColor.opacity(0.6), radius: 3 * s)
                    .frame(width: 203 * s, height: 45 * s).offset(x: X(321), y: 5 * s).allowsHitTesting(false)
            }
            Text(ch.name).font(.system(size: 13 * s, weight: .semibold)).foregroundColor(muted ? Color(white: 0.5) : (isSel ? noteColor : .white)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 92 * s, height: 45 * s, alignment: .leading).offset(x: X(335), y: 5 * s)
                .allowsHitTesting(false)
            // the oval: tap selects the track, hold for its menu (the grip on its left moves it)
            Color.clear.contentShape(Capsule()).frame(width: 105 * s, height: 45 * s).offset(x: X(321), y: 5 * s)
                .bbLongPressMenu(title: ch.name, width: 270, tap: { selectedID = ch.id }) { channelMenu(ch) }
                .accessibilityIdentifier("trackHeader\(pad)")
            ArtKnob(value: ps.level, reset: 0.8) { v, _ in set { $0.level = v } }.frame(width: 30 * s, height: 30 * s).offset(x: X(425), y: 13 * s)
            ArtKnob(value: (ps.pan + 1) / 2, reset: 0.5) { v, _ in let p = v * 2 - 1; set { $0.pan = abs(p) < 0.03 ? 0 : p } }.frame(width: 30 * s, height: 30 * s).offset(x: X(463), y: 13 * s)
            // the lamp: on / off
            if muted { Circle().fill(Color(white: 0.12)).frame(width: 9 * s, height: 9 * s).offset(x: X(504.5), y: 23.5 * s).allowsHitTesting(false) }
            Button { if soloedOut { controller.clearSolos() } else { controller.toggleMute(pad) } } label: { Color.clear.frame(width: 22 * s, height: 30 * s).contentShape(Rectangle()) }
                .buttonStyle(SeqPress()).offset(x: X(498), y: 13 * s)
            // the arrow: opens and closes this track's VELOCITY graph (or its PITCH piano roll) under its steps
            let isOpen = openID == ch.id
            Button { toggleOpen(ch) } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4 * s).fill(isOpen ? noteColor.opacity(0.25) : Color(red: 0.86, green: 0.86, blue: 0.87))
                        .overlay(RoundedRectangle(cornerRadius: 4 * s).stroke(isOpen ? noteColor : Color(white: 0.55), lineWidth: 1.2 * s))
                        .frame(width: 26 * s, height: 38 * s)
                    Image(systemName: "triangle.fill").font(.system(size: 14 * s, weight: .bold)).foregroundColor(isOpen ? noteColor : Color(white: 0.2))
                        .rotationEffect(.degrees(isOpen ? 180 : 90))
                        .shadow(color: isOpen ? noteColor.opacity(0.8) : .clear, radius: 3 * s)
                }
                .frame(width: 34 * s, height: rowH).contentShape(Rectangle())
            }
            .buttonStyle(SeqPress())
            .accessibilityIdentifier("trackArrow\(pad)")
            .accessibilityLabel(isOpen ? "Close \(ch.name)'s graph" : "Open \(ch.name)'s graph")
            if l.pitch != nil {
                scaleToolbar(l, s: s).offset(y: rowH)
                pitchKeys(l, s: s).offset(y: rowH + toolbarH(rowH))
            }
            if l.graphH > 0 {
                // the graph's header: VELOCITY | PITCH | OFFSET | CHANCE (PITCH opens the piano roll); the dice gives new velocities
                // (four lanes take the track's width, so the hint and the dice share the line under them)
                VStack(alignment: .leading, spacing: 6 * s) {
                    laneSwitch(ch, s: s)
                    HStack(spacing: 6 * s) {
                        Text(lane.hint).font(.system(size: 7 * s, weight: .semibold, design: .monospaced)).foregroundColor(Color(white: 0.45)).lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            commit(PatternEdit.randomizeVelocity(pattern, pad: pad, keys: selection, seed: UInt64.random(in: 1...UInt64.max)))
                        } label: {
                            Image(systemName: "dice.fill").font(.system(size: 12 * s)).foregroundColor(.white)
                                .frame(width: 36 * s, height: 26 * s).background(RoundedRectangle(cornerRadius: 6 * s).fill(Color(white: 0.1)).overlay(RoundedRectangle(cornerRadius: 6 * s).stroke(Color(white: 0.3), lineWidth: 1)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(SeqPress())
                    }
                }
                .padding(.horizontal, 10 * s)
                .frame(width: (A.rackX1 - A.rackX0) * s, height: l.graphH, alignment: .leading)
                .background(Color(white: 0.06))
                .offset(y: rowH)
            }
        }
        .frame(width: (A.rackX1 - A.rackX0) * s, height: l.height, alignment: .topLeading)
        .background(rowTargeted == ch.id ? S.green.opacity(0.25) : Color.clear)
        .onDrop(of: [.plainText, .fileURL, .audio], isTargeted: Binding(get: { rowTargeted == ch.id }, set: { rowTargeted = $0 ? ch.id : nil })) { providers in
            dropOnRack(providers, channel: ch)
        }
    }

    /// The arrow: open this track (closing any other), or close it.
    private func toggleOpen(_ ch: WorkspaceChannel) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if openID == ch.id {
                openID = nil; expandedID = nil
            } else {
                openID = ch.id; expandedID = lane == .pitch ? ch.id : nil
            }
        }
        selectedID = ch.id
    }

    /// VELOCITY, OFFSET and CHANCE show the bars graph under the steps; PITCH shows the notes on a piano roll.
    private func setLane(_ l: Lane, _ ch: WorkspaceChannel) {
        withAnimation(.easeInOut(duration: 0.22)) {
            lane = l
            openID = ch.id
            expandedID = l == .pitch ? ch.id : nil
        }
        selectedID = ch.id
    }

    private func laneSwitch(_ ch: WorkspaceChannel, s: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(Lane.allCases, id: \.self) { l in
                let on = lane == l && openID == ch.id
                Button { setLane(l, ch) } label: {
                    Text(l.short).font(.system(size: 9.5 * s, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundColor(on ? .black : .white)
                        .frame(width: 54 * s, height: 30 * s)
                        .background(on ? noteColor : Color(white: 0.12))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SeqPress())
                .accessibilityIdentifier(l.testID)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6 * s))
        .overlay(RoundedRectangle(cornerRadius: 6 * s).stroke(Color(white: 0.35), lineWidth: 1))
    }

    /// KEY · SCALE · SNAP · FIT for the open track's piano roll.
    private func scaleToolbar(_ l: RowLayout, s: CGFloat) -> some View {
        let pad = l.channel.pad
        let h = toolbarH(A.rowH * s)
        func chip<Content: View>(_ w: CGFloat, lit: Bool = false, @ViewBuilder _ c: () -> Content) -> some View {
            c().font(.system(size: 9 * s, weight: .semibold)).foregroundColor(lit ? .black : .white).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: w * s, height: A.rowH * s * 0.62 - 6 * s)
                .background(RoundedRectangle(cornerRadius: 5 * s).fill(lit ? noteColor : Color(white: 0.14)))
                .overlay(RoundedRectangle(cornerRadius: 5 * s).stroke(lit ? noteColor : Color(white: 0.3), lineWidth: 1))
                .contentShape(Rectangle())
        }
        return VStack(alignment: .leading, spacing: 5 * s) {
        laneSwitch(l.channel, s: s)
        HStack(spacing: 4 * s) {
            chip(56) { Text("KEY \(MusicScale.noteNames[controller.scaleRoot])") }
                .bbMenu(title: "Key", width: 200) { MusicScale.noteNames.enumerated().map { i, n in BBMenuItem.item(n, checked: controller.scaleRoot == i) { controller.setScale(root: i) } } }
            chip(78) { Text(controller.scale.name.components(separatedBy: " ").first ?? controller.scale.name) }
                .bbMenu(title: "Scale", width: 260) { MusicScale.all.map { sc in BBMenuItem.item(sc.name, checked: controller.scale.name == sc.name) { controller.setScale(name: sc.name) } } }
            Button { controller.setScale(snap: !controller.snapToScale) } label: { chip(44, lit: controller.snapToScale) { Text("SNAP") } }.buttonStyle(SeqPress())
            Button {
                let base = controller.baseNote(pad: pad)
                let top: Float = pad == Pad.bass808.rawValue ? 24 : 12
                var p = pattern
                for i in p.events.indices where Int(p.events[i].pad) == pad {
                    let n = controller.scale.snap(base + Int(p.events[i].semis.rounded()), root: controller.scaleRoot)
                    p.events[i].semis = Float(n - base).clamped(-12, top)
                }
                commit(p)
            } label: { chip(36) { Text("FIT") } }.buttonStyle(SeqPress())
        }
        .frame(height: A.rowH * s * 0.62)
        }
        .padding(.leading, 6 * s)
        .frame(width: (A.rackX1 - A.rackX0) * s, height: h, alignment: .leading)
        .background(Color(white: 0.06))
    }

    private func pitchKeys(_ l: RowLayout, s: CGFloat) -> some View {
        let range = l.pitch ?? 0...0
        let base = controller.baseNote(pad: l.channel.pad)
        return VStack(spacing: 0) {
            ForEach(Array(range.reversed()), id: \.self) { sm in
                let note = base + sm
                let inScale = controller.scale.contains(note, root: controller.scaleRoot)
                let isRoot = (note - controller.scaleRoot) % 12 == 0
                HStack {
                    Spacer()
                    Text(MusicScale.noteName(note)).font(.system(size: 9 * s, design: .monospaced))
                        .foregroundColor(isRoot ? S.green : (inScale ? Color(white: 0.15) : Color(white: 0.5)))
                    Text(sm == 0 ? "·" : (sm > 0 ? "+\(sm)" : "\(sm)")).font(.system(size: 8 * s, design: .monospaced)).foregroundColor(Color(white: 0.4)).frame(width: 22 * s, alignment: .trailing)
                }
                .padding(.trailing, 12 * s).frame(height: l.pitchRowH)
                .background(isRoot ? S.green.opacity(0.25) : (inScale ? Color.clear : Color.black.opacity(0.12)))
            }
        }
        .frame(width: (A.rackX1 - A.rackX0) * s, height: CGFloat(range.count) * l.pitchRowH, alignment: .top)
    }


    /// Drop from the library (or a file from Files) onto the rack.
    private func dropOnRack(_ providers: [NSItemProvider], channel: WorkspaceChannel?) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: NSString.self) {
            _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                guard let text = (obj as? NSString).map({ String($0) }), text.hasPrefix(soundDragPrefix) else { return }
                let id = String(text.dropFirst(soundDragPrefix.count))
                DispatchQueue.main.async {
                    guard let sound = sounds.first(where: { $0.id == id }) else { return }
                    place(sound, on: channel)
                }
            }
            return true
        }
        // a file from the Files app: it becomes a library sound first
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
            let pad = channel?.pad ?? (0..<Pad.count).first { p in !channels.contains { $0.pad == p } }
            guard let pad else { controller.notice = "The rack is full (12 channels)."; return false }
            if channel == nil {
                let placeholder = LibrarySound(id: "file:\(UUID())", url: URL(fileURLWithPath: "/"), name: "NEW SOUND", type: .fx, pack: "IMPORTED", user: true)
                if let row = controller.addRackChannel(placeholder, load: false) { animateIn(row.id); selectedID = row.id }
            }
            _ = controller.importDropped(providers, toPad: pad)
            return true
        }
        return false
    }

    private func place(_ sound: LibrarySound, on channel: WorkspaceChannel?) {
        if let channel {
            controller.replaceRackSound(channel.id, with: sound)
            selectedID = channel.id
        } else if let row = controller.addRackChannel(sound) {
            selectedID = row.id
            animateIn(row.id)
        }
        userSounds = UserSoundLibrary.sounds()
    }

    private func animateIn(_ id: UUID) {
        newborn.insert(id)
        settling.insert(id)
        DispatchQueue.main.async {
            // 1. the dot grows into the oval  2. the glow fades, the real row is underneath
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { _ = newborn.remove(id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.35)) { _ = settling.remove(id) }
            }
        }
    }

    /// Long-press menu on a channel: fills, clear, randomize, rename, delete.
    private func channelMenu(_ ch: WorkspaceChannel) -> [BBMenuItem] {
        let pad = ch.pad
        let step = PatternData.stepTicks
        let fills: [(String, Int32)] = [("Fill every step", step), ("Fill every 2 steps", step * 2), ("Fill every 4 steps (beat)", step * 4),
                                        ("Fill every 8 steps (1/2 bar)", step * 8), ("Fill every bar", PatternEdit.barTicks),
                                        ("Fill every 1/2 step (1/32)", step / 2)]
        var items: [BBMenuItem] = fills.map { f in
            BBMenuItem.item(f.0, icon: "square.grid.4x3.fill") { commit(PatternEdit.fill(pattern, pad: pad, every: f.1, velocity: lastVelocity)) }
        }
        items.append(.header("This channel"))
        items.append(BBMenuItem.item("Randomize its steps", icon: "dice") { remember(); controller.randomizeChannel(loop: loop, pad: pad) })
        items += feelItems(pad)
        items.append(.header("Track"))
        items.append(BBMenuItem.item("Track settings… (tune, decay, filter, MIDI)", icon: "slider.horizontal.3") { selectedID = ch.id; trackSettingsID = ch.id })
        items.append(BBMenuItem.item(controller.soloPads[pad] ? "Solo off" : "Solo", icon: "s.square", checked: controller.soloPads[pad]) { controller.toggleSolo(pad) })
        items.append(BBMenuItem.item("Load a sample from Files…", icon: "folder") { importPad = pad })
        items.append(BBMenuItem.item("Clear its steps", icon: "xmark", destructive: true) { commit(PatternEdit.clearChannel(pattern, pad: pad)) })
        items.append(BBMenuItem.item("Delete channel", icon: "trash", destructive: true) {
            if expandedID == ch.id { expandedID = nil }
            if openID == ch.id { openID = nil }
            if selectedID == ch.id { selectedID = nil }
            controller.removeRackChannel(ch.id)
        })
        return items
    }

    // MARK: Feel: a track's own swing, push / pull and chance

    private func trackSwingLabel(_ pad: Int) -> String {
        let v = pattern.swing(pad: pad)
        return v < 0 ? "SWING knob" : "\(Int((50 + v * 22).rounded()))%"
    }

    /// Ticks as the ear hears them at this tempo.
    private func ticksLabel(_ t: Float) -> String {
        guard t != 0 else { return "On the grid" }
        let ms = Int((abs(t) * 60_000 / Float(max(controller.state.bpm, 1)) / Float(PatternData.ppq)).rounded())
        return "\(Int(abs(t))) ticks \(t < 0 ? "early" : "late") (≈ \(ms) ms)"
    }

    private func feelItems(_ pad: Int) -> [BBMenuItem] {
        let own = pattern.swing(pad: pad), shift = pattern.shift(pad: pad)
        func edit(_ change: (inout PatternData) -> Void) { var p = pattern; change(&p); commit(p) }
        let swings = [BBMenuItem.item("Follow the SWING knob", checked: own < 0) { edit { $0.setSwing(pad: pad, -1) } }]
            + [50, 54, 56, 58, 60, 62, 64, 66, 70].map { pct -> BBMenuItem in
                let v = Float(pct - 50) / 22
                return BBMenuItem.item(pct == 50 ? "50% (straight)" : "\(pct)%", checked: own >= 0 && abs(own - v) < 0.01) { edit { $0.setSwing(pad: pad, v) } }
            }
        let shifts = [-12, -8, -6, -4, -2, 0, 2, 4, 6, 8, 12].map { t in
            BBMenuItem.item(ticksLabel(Float(t)), checked: shift == Float(t)) { edit { $0.setShift(pad: pad, Float(t)) } }
        }
        let chances = [100, 90, 75, 50, 25].map { c in
            BBMenuItem.item("\(c)%") { commit(PatternEdit.setChance(pattern, [], pad: pad, Float(c) / 100)) }
        }
        return [.header("Feel"),
                .submenu("Swing: \(trackSwingLabel(pad))", icon: "metronome", swings),
                .submenu("Push / pull: \(ticksLabel(shift).lowercased())", icon: "arrow.left.and.right", shifts),
                .submenu("Chance for all its notes", icon: "dice", chances)]
    }

    // MARK: MIDI out

    private func midiOutLabel(_ pad: Int) -> String {
        let ch = controller.midiOutChannels[pad]
        return ch < 0 ? "MIDI OFF" : "MIDI \(ch + 1)"
    }

    private func midiOutItems() -> [BBMenuItem] {
        var items: [BBMenuItem] = [
            BBMenuItem.item(controller.midiOutOn ? "MIDI out is ON" : "Turn MIDI out on", icon: "power", checked: controller.midiOutOn) {
                controller.setMIDIOut(!controller.midiOutOn)
            },
            .header("Routing"),
            BBMenuItem.item("Multi-out: each channel on its own MIDI channel (1–12)", icon: "square.stack.3d.down.right") { controller.setMIDIOutLayout(multi: true) },
            BBMenuItem.item("All drums on MIDI channel 10 (GM), the 808 on 7", icon: "10.circle") { controller.setMIDIOutLayout(multi: false) },
            .header("Channels"),
        ]
        for ch in channels {
            items.append(.submenu("\(ch.name)  ·  \(midiOutLabel(ch.pad))  ·  \(MusicScale.noteName(controller.midiOutNotes[ch.pad]))", midiOutChannelItems(ch.pad)))
        }
        return items
    }

    private func midiOutChannelItems(_ pad: Int) -> [BBMenuItem] {
        var items: [BBMenuItem] = [BBMenuItem.item("Don't send this channel", checked: controller.midiOutChannels[pad] < 0) { controller.setMIDIOutChannel(pad: pad, -1) }]
        items += (0..<16).map { ch in
            BBMenuItem.item("MIDI channel \(ch + 1)", checked: controller.midiOutChannels[pad] == ch) {
                controller.setMIDIOutChannel(pad: pad, ch)
                if !controller.midiOutOn { controller.setMIDIOut(true) }
            }
        }
        items.append(.submenu("Note: \(MusicScale.noteName(controller.midiOutNotes[pad]))", icon: "pianokeys", (24...84).map { n in
            BBMenuItem.item(MusicScale.noteName(n), detail: "\(n)", checked: controller.midiOutNotes[pad] == n) { controller.setMIDIOutNote(pad: pad, n) }
        }))
        return items
    }

    // MARK: Grid drawing

    private func x(_ t: Int32, _ w: CGFloat) -> CGFloat { CGFloat(t - pageStart) / CGFloat(pageTicks) * w }
    private func tickAt(_ x: CGFloat, _ w: CGFloat) -> Int32 { pageStart + Int32((x / w * CGFloat(pageTicks)).rounded(.down)) }
    private func snapped(_ t: Int32) -> Int32 {
        let g = placeTicks
        return max(0, min((t / g) * g, max(pattern.lengthTicks, 1) - 1))
    }
    private func cellWidth(_ w: CGFloat) -> CGFloat { w / CGFloat(pageTicks) * CGFloat(cellTicks) }
    private func noteWidth(_ e: GrooveEvent, _ w: CGFloat) -> CGFloat {
        if e.length > 0 { return max(6, CGFloat(e.length) / CGFloat(pageTicks) * w - 3) }
        return max(6, cellWidth(w) - 2)
    }
    private func noteRect(_ e: GrooveEvent, w: CGFloat, _ L: [RowLayout]) -> CGRect? {
        guard let l = layout(for: Int(e.pad), L) else { return nil }
        if let range = l.pitch {
            let s = Int(e.semis.rounded()).clamped(range.lowerBound, range.upperBound)
            let y = l.pitchTop + CGFloat(range.upperBound - s) * l.pitchRowH
            return CGRect(x: x(e.tick, w) + 1.5, y: y + 1.5, width: noteWidth(e, w), height: l.pitchRowH - 3)
        }
        return CGRect(x: x(e.tick, w) + 1, y: l.y + 2, width: noteWidth(e, w), height: l.bandH - 4)
    }
    private func visible(_ e: GrooveEvent) -> Bool { e.tick >= pageStart && e.tick < pageStart + pageTicks }

    private func grid(_ L: [RowLayout], width w: CGFloat, rowH: CGFloat) -> some View {
        Canvas { ctx, size in
            let cw = cellWidth(size.width)
            let cells = Int(pageTicks / cellTicks)
            for (i, l) in L.enumerated() {
                if let range = l.pitch {
                    // the band: the track's steps, lit where it has notes (any pitch)
                    ctx.fill(Path(CGRect(x: 0, y: l.y, width: size.width, height: l.pitchTop - l.y)), with: .color(S.greenDark.opacity(0.5)))
                    ctx.fill(Path(CGRect(x: 0, y: l.y + l.bandH, width: size.width, height: l.pitchTop - l.y - l.bandH)), with: .color(Color(white: 0.06)))
                    drawMetalCells(ctx, (0..<cells).map { CGRect(x: CGFloat($0) * cw + 1, y: l.y, width: cw - 2, height: l.bandH) })
                    for c in 0..<cells {
                        let at = pageStart + Int32(c) * cellTicks
                        let lit = pattern.events.contains { Int($0.pad) == l.channel.pad && $0.tick >= at && $0.tick < at + cellTicks }
                        let r = CGRect(x: CGFloat(c) * cw + 1, y: l.y, width: cw - 2, height: l.bandH)
                        if (Int(at / PatternData.ppq) % 2) == 1 { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.32))) }
                        if lit { ctx.fill(Path(roundedRect: r.insetBy(dx: 1, dy: 2), cornerRadius: 3), with: .color(noteColor.opacity(0.8))) }
                    }
                    // the piano roll: a stripe per semitone (scale notes lighter, the root greener)
                    let base = controller.baseNote(pad: l.channel.pad)
                    for (k, s) in range.reversed().enumerated() {
                        let note = base + s
                        let inScale = controller.scale.contains(note, root: controller.scaleRoot)
                        let isRoot = (note - controller.scaleRoot) % 12 == 0
                        let y = l.pitchTop + CGFloat(k) * l.pitchRowH
                        // the key's notes are lit (the root greener), the notes outside it are dark
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: l.pitchRowH)),
                                 with: .color(isRoot ? S.green.opacity(0.1) : (inScale ? (k % 2 == 0 ? S.rowA : S.rowB) : Color.black.opacity(0.35))))
                        if inScale && !isRoot { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: l.pitchRowH)), with: .color(noteColor.opacity(0.07))) }
                        if s == 0 { ctx.fill(Path(CGRect(x: 0, y: y + l.pitchRowH - 1, width: size.width, height: 1)), with: .color(S.dim.opacity(0.5))) }
                    }
                    ctx.fill(Path(CGRect(x: 0, y: l.y, width: size.width, height: 1)), with: .color(S.green.opacity(0.5)))
                    ctx.fill(Path(CGRect(x: 0, y: l.y + l.height - 1, width: size.width, height: 1)), with: .color(S.green.opacity(0.5)))
                } else {
                    // the step buttons (the picture's)
                    drawMetalCells(ctx, (0..<cells).map { CGRect(x: CGFloat($0) * cw + 1, y: l.y, width: cw - 2, height: l.bandH) })
                    for c in 0..<cells {
                        let at = pageStart + Int32(c) * cellTicks
                        let r = CGRect(x: CGFloat(c) * cw + 1, y: l.y, width: cw - 2, height: l.bandH)
                        // every other beat's buttons are the darker grey (Tyrone's picture)
                        if (Int(at / PatternData.ppq) % 2) == 1 { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.32))) }
                        if at >= pattern.lengthTicks { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.55))) }
                    }
                    if l.graphH > 0 { drawGraph(ctx, l, width: size.width) }
                }
            }
            // the bar line
            var t = pageStart
            while t <= pageStart + pageTicks {
                if t % PatternEdit.barTicks == 0 && t > pageStart && t < pageStart + pageTicks {
                    ctx.fill(Path(CGRect(x: x(t, size.width) - 0.5, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.25)))
                }
                t += PatternData.ppq
            }
            if snapTicks > 0 && snapTicks < cellTicks {      // a finer SNAP than the cells: its lines
                var st = pageStart
                while st < pageStart + pageTicks { ctx.fill(Path(CGRect(x: x(st, size.width), y: 0, width: 1, height: size.height)), with: .color(S.stepLine)); st += snapTicks }
            }
            // the notes: silver buttons that glow the mode's colour. The shadow under them and the glow
            // are one blurred layer each, so the canvas blurs twice however many notes are on screen.
            // Step rows: a step button lights when it holds any hit (a roll's hits share one button,
            // a mark each in its slot). The piano roll's notes are drawn one by one.
            let shown = pattern.events.filter(visible)
            var steps: [StepKey: [GrooveEvent]] = [:]
            var notes: [(GrooveEvent, CGRect)] = []
            for e in shown {
                guard let l = layout(for: Int(e.pad), L) else { continue }
                if l.pitch == nil {
                    steps[StepKey(pad: Int(e.pad), cell: Int((e.tick - pageStart) / max(1, cellTicks))), default: []].append(e)
                } else if let r = noteRect(e, w: size.width, L) {
                    notes.append((e, r))
                }
            }
            let lit: [(StepKey, CGRect, [GrooveEvent])] = steps.compactMap { key, hits in
                guard let l = layout(for: key.pad, L) else { return nil }
                return (key, CGRect(x: CGFloat(key.cell) * cw + 1, y: l.y, width: cw - 2, height: l.bandH), hits.sorted { $0.tick < $1.tick })
            }
            // the glow: one blurred layer for every lit slot (and every piano-roll note)
            ctx.drawLayer { g in
                g.addFilter(.shadow(color: glowColor, radius: 7))
                for (_, r, hits) in lit {
                    let sel = hits.contains { selection.contains(NoteKey($0)) }
                    let v = Double(hits.map(\.velocity).max() ?? 0.8)
                    g.fill(Path(roundedRect: Self.slot(in: r).insetBy(dx: -1, dy: -1), cornerRadius: 2), with: .color((sel ? Color.white : glowColor).opacity(0.5 + 0.5 * v)))
                }
                for (e, r) in notes {
                    g.fill(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color((selection.contains(NoteKey(e)) ? Color.white : glowColor).opacity(0.3 + 0.4 * Double(e.velocity))))
                }
            }
            for (_, r, hits) in lit {
                let sel = hits.contains { selection.contains(NoteKey($0)) }
                let v = Double(hits.map(\.velocity).max() ?? 0.8)
                drawLitStep(ctx, r, glow: sel ? Color.white : glowColor, level: 0.55 + 0.45 * v, hits: hits.count)
                if sel { ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.white), lineWidth: 1.5) }
                if hits.contains(where: { $0.chance < 1 }) {
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(glowColor.opacity(0.9)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                if let e = hits.first, e.semis != 0, r.width > 14 {
                    ctx.draw(Text(e.semis > 0 ? "+\(Int(e.semis))" : "\(Int(e.semis))").font(.system(size: 9, weight: .bold)).foregroundColor(.black),
                             at: CGPoint(x: r.midX, y: r.midY + r.height * 0.12))
                }
                // NOTE OFFSET: a thin line where each hit really plays
                for e in hits where e.offset != 0 {
                    let px = x(e.tick + Int32(e.offset), size.width)
                    ctx.fill(Path(CGRect(x: px - 0.75, y: r.minY + r.height * 0.35, width: 1.5, height: r.height * 0.5)), with: .color(Color.black.opacity(0.6)))
                }
            }
            for (e, r) in notes {
                let sel = selection.contains(NoteKey(e))
                drawMetalNote(ctx, r, tint: sel ? Color.white : glowColor, level: 0.55 + 0.45 * Double(e.velocity))
                if sel { ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.white), lineWidth: 1.5) }
                if sel && tool == .select {
                    ctx.fill(Path(roundedRect: CGRect(x: r.maxX - 4, y: r.minY + 2, width: 3, height: max(2, r.height - 4)), cornerRadius: 1.5),
                             with: .color(Color.black.opacity(0.55)))
                }
                if e.offset != 0 {
                    let px = x(e.tick + Int32(e.offset), size.width)
                    ctx.fill(Path(CGRect(x: px - 0.75, y: r.minY + 2, width: 1.5, height: max(2, r.height - 4))), with: .color(Color.white.opacity(0.85)))
                }
                if e.chance < 1 {
                    ctx.stroke(Path(roundedRect: r.insetBy(dx: 1, dy: 1), cornerRadius: 3), with: .color(glowColor.opacity(0.9)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            if case let .marquee(a, b) = drag {
                let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                ctx.fill(Path(rect), with: .color(S.orange.opacity(0.12)))
                ctx.stroke(Path(rect), with: .color(S.orange), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            if isThisPlaying, let t = controller.playheadTick {
                let px = x(Int32(t), size.width)
                if px >= 0 && px <= size.width {
                    ctx.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: size.height)), with: .color(noteColor))
                }
            }
            _ = tick
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityIdentifier("grid")
        .accessibilityValue("\(pattern.events.count) notes")
        .highPriorityGesture(DragGesture(minimumDistance: 0)
            .onChanged { g in if !pinching && !twoFinger { gridChanged(g, w: w, L: L) } }
            .onEnded { g in
                if pinching || twoFinger { drag = .none; work = nil; twoFinger = false } else { gridEnded(g, w: w, L: L) }
            })
        .simultaneousGesture(pinch)
        .background(GridScrollHook(
            began: { trackpad in
                panStart = pageStart
                if trackpad { return }
                switch drag {
                case .paint, .erase, .graph: _ = undoStack.popLast()
                default: break
                }
                drag = .none; work = nil; laneOrigin = nil
                twoFinger = true
            },
            sideways: { dx in scroll(to: (panStart ?? pageStart) - Int32(dx / max(1, w) * CGFloat(windowTicks))) },
            ended: { panStart = nil }))
    }

    /// The slot near the top of a step button (Tyrone's picture): dark when off, a glowing bar when lit.
    static func slot(in r: CGRect) -> CGRect {
        CGRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.15, width: r.width * 0.68, height: max(3, r.height * 0.1))
    }

    /// The lit slot's colour: the mode's light (VINTAGE glows yellow rather than its cream).
    private var glowColor: Color { controller.mode == .vintage ? Color(red: 1, green: 0.8, blue: 0.25) : noteColor }

    private struct StepKey: Hashable { let pad: Int; let cell: Int }

    /// A row of step buttons in brushed steel: bevelled, each with its dark slot near the top. One
    /// fill per layer for the whole row; a lit button is drawn over its own.
    private func drawMetalCells(_ ctx: GraphicsContext, _ rects: [CGRect]) {
        guard let first = rects.first else { return }
        let top = CGPoint(x: 0, y: first.minY), bottom = CGPoint(x: 0, y: first.maxY)
        var body = Path(), slots = Path()
        for r in rects {
            body.addRoundedRect(in: r, cornerSize: CGSize(width: 3, height: 3))
            let sl = Self.slot(in: r)
            slots.addRoundedRect(in: sl.insetBy(dx: -1, dy: -1), cornerSize: CGSize(width: 2, height: 2))
        }
        ctx.fill(body, with: .linearGradient(Gradient(stops: [
            .init(color: Color(white: 0.8), location: 0), .init(color: Color(white: 0.66), location: 0.2),
            .init(color: Color(white: 0.5), location: 0.6), .init(color: Color(white: 0.58), location: 1)]), startPoint: top, endPoint: bottom))
        var c = ctx
        c.clip(to: body)
        var grain = Path()
        var y = first.minY + 1
        let x0 = rects.map(\.minX).min() ?? 0, x1 = rects.map(\.maxX).max() ?? 0
        while y < first.maxY { grain.addRect(CGRect(x: x0, y: y, width: x1 - x0, height: 0.5)); y += 1.8 }
        c.fill(grain, with: .color(Color.black.opacity(0.08)))
        var bevel = Path()
        for r in rects { bevel.addRoundedRect(in: r.insetBy(dx: 0.6, dy: 0.6), cornerSize: CGSize(width: 2.5, height: 2.5)) }
        ctx.stroke(bevel, with: .linearGradient(Gradient(stops: [
            .init(color: Color.white.opacity(0.8), location: 0), .init(color: Color.white.opacity(0), location: 0.35),
            .init(color: Color.black.opacity(0), location: 0.65), .init(color: Color.black.opacity(0.55), location: 1)]), startPoint: top, endPoint: bottom), lineWidth: 1.1)
        ctx.stroke(body, with: .color(Color.black.opacity(0.6)), lineWidth: 0.7)
        ctx.fill(slots, with: .color(Color.black.opacity(0.7)))
    }

    /// A lit step button: the same silver button, its slot lit as a bright bar of the mode's light
    /// (a roll's hits split the bar, a mark each). The metal stays silver in every mode.
    private func drawLitStep(_ ctx: GraphicsContext, _ r: CGRect, glow: Color, level: Double, hits: Int) {
        let sl = Self.slot(in: r)
        ctx.fill(Path(roundedRect: sl.insetBy(dx: -1, dy: -1), cornerRadius: 2), with: .color(Color.black.opacity(0.8)))
        let n = max(1, min(hits, 4)), gap: CGFloat = n > 1 ? 1.5 : 0
        let w = (sl.width - gap * CGFloat(n - 1)) / CGFloat(n)
        for i in 0..<n {
            let bar = CGRect(x: sl.minX + CGFloat(i) * (w + gap), y: sl.minY, width: w, height: sl.height)
            ctx.fill(Path(roundedRect: bar, cornerRadius: min(2, bar.height / 2)), with: .linearGradient(Gradient(colors: [glow.opacity(level), glow.opacity(level * 0.8)]),
                                                                                                startPoint: CGPoint(x: bar.midX, y: bar.minY), endPoint: CGPoint(x: bar.midX, y: bar.maxY)))
            // the hot core of the light
            ctx.fill(Path(roundedRect: bar.insetBy(dx: min(2, bar.width * 0.15), dy: bar.height * 0.3), cornerRadius: 1), with: .color(Color.white.opacity(0.55 * level)))
        }
        // a faint wash of the light on the button's edge
        ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: .color(glow.opacity(0.35 * level)), lineWidth: 1)
    }

    /// A piano-roll note as a brushed-silver bar tinted with the mode's light.
    private func drawMetalNote(_ ctx: GraphicsContext, _ r: CGRect, tint: Color, level: Double) {
        let shape = Path(roundedRect: r, cornerRadius: 3)
        let top = CGPoint(x: r.midX, y: r.minY), bottom = CGPoint(x: r.midX, y: r.maxY)
        ctx.fill(shape, with: .linearGradient(Gradient(stops: [
            .init(color: Color(white: 0.97), location: 0), .init(color: Color(white: 0.82), location: 0.18),
            .init(color: Color(white: 0.6), location: 0.55), .init(color: Color(white: 0.7), location: 0.8),
            .init(color: Color(white: 0.86), location: 1)]), startPoint: top, endPoint: bottom))
        var c = ctx
        c.clip(to: shape)
        c.fill(Path(r), with: .color(tint.opacity(0.25 + 0.3 * level)))
        ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 2.5), with: .linearGradient(Gradient(stops: [
            .init(color: Color.white.opacity(0.95), location: 0), .init(color: Color.white.opacity(0), location: 0.4),
            .init(color: Color.black.opacity(0), location: 0.6), .init(color: Color.black.opacity(0.5), location: 1)]), startPoint: top, endPoint: bottom), lineWidth: 1.2)
        ctx.stroke(shape, with: .color(tint.opacity(0.5 + 0.4 * level)), lineWidth: 1)
    }

    private func setZoom(_ level: Int) {
        let newLevel = max(0, min(Self.zoomSnaps.count - 1, level))
        guard newLevel != zoomLevel else { return }
        let center = pageStart + pageTicks / 2
        zoomLevel = newLevel
        viewStart = max(0, center - windowTicks / 2)
        snap = Self.zoomSnaps[newLevel]
        follow = false
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                guard expandedID != nil else { return }      // zoom belongs to the piano roll
                if !pinching {
                    pinching = true
                    switch drag {
                    case .paint, .erase: _ = undoStack.popLast()
                    default: break
                    }
                    drag = .none; work = nil
                }
                let r = scale / pinchBase
                if r > 1.3 { setZoom(zoomLevel + 1); pinchBase = scale }
                else if r < 0.77 { setZoom(zoomLevel - 1); pinchBase = scale }
            }
            .onEnded { _ in pinchBase = 1; pinching = false; drag = .none; work = nil }
    }

    // MARK: Grid gestures

    private func noteAt(_ p: CGPoint, w: CGFloat, L: [RowLayout]) -> GrooveEvent? {
        guard let l = layout(at: p.y, L) else { return nil }
        let pad = l.channel.pad
        return pattern.events.last { e in
            Int(e.pad) == pad && visible(e) && (noteRect(e, w: w, L)?.insetBy(dx: -4, dy: l.pitch == nil ? -4 : -1).contains(p) ?? false)
        }
    }

    private func gridChanged(_ g: DragGesture.Value, w: CGFloat, L: [RowLayout]) {
        if case .none = drag {
            let start = g.startLocation
            guard let l = layout(at: start.y, L) else { return }
            if inBand(start.y, l) { selectedID = l.channel.id; return }
            if inToolbar(start.y, l) { return }
            if inGraph(start.y, l) {
                // the dropped-down graph: drag the bars (velocity or pitch, whichever is showing)
                laneOrigin = pattern; undoStack.append(pattern); redoStack = []
                drag = .graph(pad: l.channel.pad, top: l.graphTop, height: l.graphH)
                selectedID = l.channel.id
                graphChanged(g, w: w)
                return
            }
            let pad = l.channel.pad
            let sem = controller.scaleSnapped(semis(at: start.y, in: l), pad: pad)
            let hit = noteAt(start, w: w, L: L)
            switch tool {
            case .draw:
                if let hit {
                    let r = noteRect(hit, w: w, L) ?? .zero
                    if Int(hit.pad) == Pad.bass808.rawValue && start.x > r.maxX - 14 {
                        drag = .resize(key: NoteKey(hit), origin: pattern)
                    } else {
                        drag = .tapOnNote(key: NoteKey(hit))
                    }
                    lastVelocity = hit.velocity
                } else if pad == Pad.bass808.rawValue {
                    drag = .long808(start: snapped(tickAt(start.x, w)), semis: sem)
                } else {
                    let t = snapped(tickAt(start.x, w))
                    undoStack.append(pattern); redoStack = []
                    work = PatternEdit.addNote(pattern, pad: pad, tick: t, velocity: lastVelocity, semis: sem)
                    drag = .paint(pad: pad, semis: sem, lastCell: Int(t / placeTicks))
                }
                selectedID = l.channel.id
            case .select:
                if let hit, start.x > (noteRect(hit, w: w, L)?.maxX ?? 0) - 12 {
                    if !selection.contains(NoteKey(hit)) { selection = [NoteKey(hit)] }
                    drag = .trim(keys: selection, origin: pattern, startTick: tickAt(start.x, w))
                } else if let hit {
                    if !selection.contains(NoteKey(hit)) { selection = [NoteKey(hit)] }
                    drag = .move(keys: selection, origin: pattern, startTick: tickAt(start.x, w), startSemis: Int(sem.rounded()), followSelection: true)
                } else {
                    drag = .marquee(start: start, current: start)
                }
            case .erase:
                undoStack.append(pattern); redoStack = []
                drag = .erase
            }
        }
        switch drag {
        case .graph:
            graphChanged(g, w: w)
        case .tapOnNote(let key):
            if hypot(g.translation.width, g.translation.height) > 8 {
                let inSelection = selection.contains(key)
                let l = layout(at: g.startLocation.y, L)
                let s0 = l.map { Int(semis(at: g.startLocation.y, in: $0).rounded()) } ?? 0
                drag = .move(keys: inSelection ? selection : [key], origin: pattern,
                             startTick: tickAt(g.startLocation.x, w), startSemis: s0, followSelection: inSelection)
                gridChanged(g, w: w, L: L)
            }
        case .paint(let pad, let sem, let lastCell):
            let t = snapped(tickAt(g.location.x, w))
            let cell = Int(t / placeTicks)
            // painting inside an open piano roll follows the finger's pitch
            let l = layout(for: pad, L)
            let s = l?.pitch != nil ? controller.scaleSnapped(semis(at: g.location.y, in: l!), pad: pad) : sem
            if (cell != lastCell || s != sem) && t >= pageStart && t < pageStart + pageTicks {
                work = PatternEdit.addNote(pattern, pad: pad, tick: t, velocity: lastVelocity, semis: s)
                drag = .paint(pad: pad, semis: s, lastCell: cell)
            }
        case .long808:
            break
        case .move(let keys, let origin, let startTick, let startSemis, let followSelection):
            let raw = tickAt(g.location.x, w) - startTick
            let d = snapTicks > 0 ? (raw / snapTicks) * snapTicks : raw
            var (moved, newKeys) = PatternEdit.move(origin, keys, by: d)
            // inside an open piano roll a vertical drag changes the pitch
            if let l = layout(at: g.location.y, L), l.pitch != nil, keys.allSatisfy({ Int($0.pad) == l.channel.pad }) {
                let ds = Int(semis(at: g.location.y, in: l).rounded()) - startSemis
                if ds != 0 {
                    var p = moved; var k2 = Set<NoteKey>()
                    for i in p.events.indices where newKeys.contains(NoteKey(p.events[i])) {
                        let range = pitchRange(Int(p.events[i].pad))
                        let base = Int(p.events[i].semis.rounded()) + ds
                        p.events[i].semis = controller.scaleSnapped(Float(base.clamped(range.lowerBound, range.upperBound)), pad: Int(p.events[i].pad))
                        k2.insert(NoteKey(p.events[i]))
                    }
                    moved = p; newKeys = k2
                }
            }
            work = moved
            if followSelection { selection = newKeys }
        case .trim(let keys, let origin, let startTick):
            let raw = tickAt(g.location.x, w) - startTick
            let unit = snapTicks > 0 ? snapTicks : Int32(6)
            let d = (raw / unit) * unit
            let (trimmed, newKeys) = PatternEdit.trim(origin, keys, by: d, minLength: min(unit, PatternData.stepTicks / 2))
            work = trimmed
            selection = newKeys
        case .resize(let key, let origin):
            guard let e = origin.events.first(where: { NoteKey($0) == key }) else { return }
            let end = snapped(tickAt(g.location.x, w) + placeTicks / 2)
            let (resized, _) = PatternEdit.resize(origin, key, length: max(placeTicks, end - e.tick))
            work = resized
        case .marquee(let a, _):
            drag = .marquee(start: a, current: g.location)
        case .erase:
            if let hit = noteAt(g.location, w: w, L: L) {
                work = PatternEdit.remove(pattern, [NoteKey(hit)])
                selection.remove(NoteKey(hit))
            }
        case .none:
            break
        }
    }

    private func gridEnded(_ g: DragGesture.Value, w: CGFloat, L: [RowLayout]) {
        defer { drag = .none }
        switch drag {
        case .tapOnNote(let key):
            commit(PatternEdit.remove(pattern, [key]))
            selection.remove(key)
        case .long808(let start, let sem):
            let end = snapped(tickAt(g.location.x, w))
            let length = max(placeTicks, (end > start ? end - start : 0) + placeTicks)
            let len = abs(g.translation.width) < 6 ? last808Length : length
            last808Length = len
            commit(PatternEdit.addNote(pattern, pad: Pad.bass808.rawValue, tick: start, length: len, velocity: lastVelocity, semis: sem))
        case .paint, .erase:
            if let p = work { work = nil; controller.setLoop(loop, p) }
            else { _ = undoStack.popLast() }
        case .graph:
            if let p = work { work = nil; controller.setLoop(loop, p) } else { _ = undoStack.popLast() }
            laneOrigin = nil
        case .move, .resize, .trim:
            if let p = work { commit(p) } else { work = nil }
        case .marquee(let a, let b):
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            if rect.width < 4 && rect.height < 4 {
                selection = []
                if let l = layout(at: a.y, L) { selectedID = l.channel.id }
            } else {
                selection = Set(pattern.events.filter { visible($0) && (noteRect($0, w: w, L).map { rect.intersects($0) } ?? false) }.map(NoteKey.init))
            }
        case .none:
            break
        }
    }

    // MARK: The graph under the open track

    @State private var laneOrigin: PatternData?

    /// A drag in the graph under the open track.
    private func graphChanged(_ g: DragGesture.Value, w: CGFloat) {
        guard case let .graph(pad, top, h) = drag else { return }
        let v = Float(1 - (g.location.y - top - 4) / (h - 8)).clamped(0, 1)
        let keys = Set(pattern.events.filter { e in
            visible(e) && Int(e.pad) == pad && abs(x(e.tick, w) + 5 - g.location.x) <= 8 && (selection.isEmpty || selection.contains(NoteKey(e)))
        }.map(NoteKey.init))
        guard !keys.isEmpty else { return }
        apply(graphValue: v, to: keys, pad: pad)
    }

    /// Sets velocity, pitch, note offset or chance (whichever graph is showing) on the notes under the finger.
    private func apply(graphValue v: Float, to keys: Set<NoteKey>, pad: Int) {
        switch lane {
        case .velocity:
            let value = max(0.05, v)
            work = PatternEdit.setVelocity(pattern, keys, value)
            lastVelocity = value
        case .pitch:
            let raw = (v * 24 - 12).rounded()
            let (p, newKeys) = PatternEdit.setPitch(pattern, keys, controller.scaleSnapped(raw, pad: pad))
            work = p
            if !selection.isEmpty { selection = selection.subtracting(keys).union(newKeys) }
        case .offset:
            // a small dead zone around the centre line so a note goes back on its step easily
            let m = Float(PatternData.maxOffset)
            var ticks = ((v * 2 - 1) * m).rounded()
            if abs(ticks) < 1 { ticks = 0 }
            work = PatternEdit.setOffset(pattern, keys, Int8(ticks))
        case .chance:
            work = PatternEdit.setChance(pattern, keys, (v * 20).rounded() / 20)
        }
    }

    // MARK: Footer (pattern, kit)

    private var orderedKits: [KitDefinition] { KitLibrary.browserOrder }

    @ViewBuilder private func footer(_ s: CGFloat) -> some View {
        // pads / sequencer switch: the pad button goes back to the faceplate
        // the way back to Face 1: slide the platinum knob (the sequencer's 9 squares) to the right
        FaceSlider(scale: s, color: noteColor) { dismiss() }.place([38, 715, 147, 772], s)
        // power: the sequencer and pads all the way on or off
        PowerButton(on: controller.powerOn, scale: s, color: S.green) { controller.togglePower() }.place(A.power, s)
        // PATTERN
        SeqButton("SeqArrowBack", corner: 8, scale: s) { cycleLoop(-1) }.place(A.patternBack, s)
        SeqButton("SeqArrowFwd", corner: 0, scale: s) { cycleLoop(1) }.place(A.patternForward, s)
        SeqChip(sprite: "SeqChipPattern", text: controller.state.presetName, size: 14, leading: 6, trailing: 30, scale: s)
            .bbMenuPlaced(A.patternChip, s, title: "Presets", width: 340) { presetItems() }
        // KIT
        SeqButton("SeqArrowBack", corner: 8, scale: s) { cycleKit(-1) }.place(A.kitBack, s)
        SeqButton("SeqArrowFwd", corner: 0, scale: s) { cycleKit(1) }.place(A.kitForward, s)
        SeqChip(sprite: "SeqChipKit", text: controller.state.kitName, size: 14, leading: 6, trailing: 30, scale: s)
            .bbMenuPlaced(A.kitChip, s, title: "Kits · drum sounds", width: 320) { kitItems() }
    }

    /// PRESETS: every preset pattern by style, and your own.
    private func presetItems() -> [BBMenuItem] {
        // one vertical list: every style's patterns under its name
        var items: [BBMenuItem] = []
        for style in PatternBank.styles {
            items.append(.header(style))
            for p in PatternBank.presets(in: style) {
                items.append(BBMenuItem.item(p.name, detail: "\(Int(p.bpm)) BPM\(p.swing > 50.5 ? " · \(Int(p.swing))% SWING" : "")",
                                             checked: controller.state.presetName == p.name) { controller.loadPatternPreset(p); loop = 0; selection = [] })
            }
        }
        if !controller.userPresets.isEmpty {
            items.append(.header("My presets"))
            for name in controller.userPresets {
                items.append(BBMenuItem.item(name, checked: controller.state.presetName == name) { controller.loadUserPreset(name); selection = [] })
            }
        }
        return items
    }

    private func kitItems() -> [BBMenuItem] {
        // one vertical list: each genre's kits under its name (MODERN, then VINTAGE, then TEXTURE), your kits
        var items: [BBMenuItem] = []
        for mode in SoundMode.allCases {
            for g in KitLibrary.genreGroups(for: mode) {
                items.append(.header("\(g.genre) · \(mode.title)"))
                for def in g.kits {
                    items.append(BBMenuItem.item(def.name, detail: "\(Int(def.tempo)) BPM", checked: def.id == controller.state.kitID && controller.state.userKit == nil) { controller.selectKit(def) })
                }
            }
        }
        if !controller.userKits.isEmpty {
            items.append(.header("My kits"))
            for name in controller.userKits {
                items.append(BBMenuItem.item(name, checked: controller.state.userKit == name) { controller.selectUserKit(name) })
            }
        }
        return items
    }


    private func cycleKit(_ step: Int) {
        let kits = orderedKits
        guard !kits.isEmpty else { return }
        let i = kits.firstIndex { $0.id == controller.state.kitID } ?? 0
        controller.selectKit(kits[(i + step + kits.count) % kits.count])
    }

    private func cycleLoop(_ step: Int) {
        let all = PatternBank.all
        guard !all.isEmpty else { return }
        let i = all.firstIndex { $0.name == controller.state.presetName } ?? -1
        controller.loadPatternPreset(all[(i + step + all.count) % all.count]); loop = 0; selection = []
    }

    private func duplicate() {
        if selection.isEmpty {
            commit(PatternEdit.copyNext(pattern, fromBar: 0, bars: bars))
        } else {
            let (p, keys) = PatternEdit.duplicate(pattern, selection)
            commit(p)
            selection = keys
        }
    }

    private func clear() {
        if selection.isEmpty {
            var p = pattern; p.events = []; commit(p)
        } else {
            commit(PatternEdit.remove(pattern, selection))
            selection = []
        }
    }

    private func writeMIDI() -> URL? {
        let name = (controller.loops.indices.contains(loop) ? controller.loops[loop].name : "PATTERN").replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BreaKing \(controller.state.kitName) \(name).mid")
        do {
            // Twelve channels, one per pad (the same layout as MIDI OUT), each note's pitch and velocity intact.
            let names = (0..<Pad.count).map { pad in channels.first { $0.pad == pad }?.name ?? (Pad(rawValue: pad)?.channelTitle ?? "PAD \(pad + 1)") }
            try MIDIFile.writeChannels(stored, names: names, tempo: controller.liveTempo, bounce: controller.value(.bounce), bars: bars, to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Undo, follow

    private func commit(_ p: PatternData) {
        work = nil
        guard p != stored else { return }
        undoStack.append(stored)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
        controller.setLoop(loop, p)
    }

    /// Keeps the pattern as it is now so UNDO brings it back: for changes made outside the grid (the dice,
    /// generate, recording, the presets' pattern). A slider coalesces its moves into one undo.
    private func remember(coalescing: Bool = false) {
        let now = Date()
        defer { rememberedAt = coalescing ? now : nil }
        if coalescing, let at = rememberedAt, now.timeIntervalSince(at) < 1 { return }
        undoStack.append(stored)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(pattern)
        controller.setLoop(loop, last)
        selection = []
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(pattern)
        controller.setLoop(loop, next)
        selection = []
    }

    private func followPlayhead() {
        guard follow, isThisPlaying, let t = controller.playheadTick, case .none = drag else { return }
        let t32 = Int32(t)
        if t32 < pageStart || t32 >= pageStart + pageTicks { viewStart = min(maxStart, t32 / pageTicks * pageTicks) }
    }

    // MARK: Small pieces

    private func box(lit: Bool, color: Color = S.green) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(lit ? (color == S.green ? S.greenDark : color.opacity(0.25)) : S.button)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(lit ? color.opacity(0.9) : S.border, lineWidth: lit ? 1.5 : 1))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }

    private var divider: some View { Rectangle().fill(S.border).frame(width: 1, height: 30) }

    private func iconBox(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 16, weight: .medium)).foregroundColor(S.text)
            .frame(width: 40, height: 40).background(box(lit: false))
    }

    private func chip(_ text: String, width: CGFloat) -> some View {
        HStack {
            Text(text).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(S.text).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(S.text)
        }
        .padding(.horizontal, 12).frame(width: width, height: 40).background(box(lit: false))
    }

    /// SNAP TO SCALE (FL Studio's scales): on / off, the key, the scale, and fitting a track's notes.
    private func scaleItems(_ pad: Int?) -> [BBMenuItem] {
        var items: [BBMenuItem] = [
            BBMenuItem.item(controller.snapToScale ? "Snap to scale: ON" : "Snap to scale: OFF", icon: "tuningfork",
                            checked: controller.snapToScale) { controller.setScale(snap: !controller.snapToScale) },
            BBMenuItem.submenu("Key: \(MusicScale.noteNames[controller.scaleRoot])", icon: "music.note",
                MusicScale.noteNames.enumerated().map { i, n in BBMenuItem.item(n, checked: controller.scaleRoot == i) { controller.setScale(root: i) } }),
            BBMenuItem.submenu("Scale: \(controller.scale.name)", icon: "music.note.list",
                MusicScale.all.map { sc in BBMenuItem.item(sc.name, checked: controller.scale.name == sc.name) { controller.setScale(name: sc.name) } })
        ]
        if let pad, let ch = channel(pad: pad) {
            items.append(.header("Notes already drawn"))
            items.append(BBMenuItem.item("Fit \(ch.name)'s notes to the scale", icon: "wand.and.stars") {
                let base = controller.baseNote(pad: pad)
                let top: Float = pad == Pad.bass808.rawValue ? 24 : 12
                var p = pattern
                for i in p.events.indices where Int(p.events[i].pad) == pad {
                    let n = controller.scale.snap(base + Int(p.events[i].semis.rounded()), root: controller.scaleRoot)
                    p.events[i].semis = Float(n - base).clamped(-12, top)
                }
                commit(p)
            })
        }
        return items
    }

    private func labelBox(_ icon: String?, _ title: String?, lit: Bool = false, enabled: Bool = true) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 15, weight: .medium)) }
            if let title { Text(title).font(.system(size: 13, weight: .medium, design: .monospaced)) }
        }
        .foregroundColor(lit ? S.green : (enabled ? S.text : S.dim))
        .padding(.horizontal, 12).frame(height: 40).background(box(lit: lit))
    }
}

/// The tempo slider panel (header BPM). Follows the DAW / MIDI clock when TEMPO SYNC has one.
struct TempoPanel: View {
    @ObservedObject var controller: KnockController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.tempoIsExternal {
                Text("Tempo follows the DAW / MIDI clock: \(Int(controller.liveTempo.rounded())) BPM")
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(BBMenuStyle.dim)
            } else {
                BBSlider(value: controller.state.bpm, range: 40...280, step: 1, label: { "\(Int($0)) BPM" }) { controller.setBPM($0) }
                HStack(spacing: 6) {
                    ForEach([80, 90, 100, 120, 140, 150, 160, 170], id: \.self) { b in
                        Button { controller.setBPM(Double(b)) } label: {
                            Text("\(b)").font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(Int(controller.state.bpm) == b ? .black : BBMenuStyle.text)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Int(controller.state.bpm) == b ? BBMenuStyle.accent : BBMenuStyle.row))
                        }
                    }
                }
            }
        }
    }
}

/// The picture's knob, turned to its value: drag up or right to turn it up.
struct ArtKnob: View {
    let value: Float
    /// Extra touchable margin round the knob (it's small in the picture).
    var grip: CGFloat = 0
    /// A double tap puts the knob back here (pan: centre).
    var reset: Float? = nil
    let change: (Float, Bool) -> Void
    @State private var start: Float?

    var body: some View {
        MetalKnob().aspectRatio(1, contentMode: .fit)
            .rotationEffect(.degrees(KnobControl.angle(value)))
            .animation(.easeOut(duration: 0.15), value: value)
            .padding(grip)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if let reset { change(reset, true) } }
            // high priority: the rack's knobs turn instead of scrolling the rack
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if start == nil { start = value }
                    let d = Float((-g.translation.height + g.translation.width * 0.6) / 180)
                    change(((start ?? value) + d).clamped(0, 1), false)
                }
                .onEnded { g in
                    let d = Float((-g.translation.height + g.translation.width * 0.6) / 180)
                    change(((start ?? value) + d).clamped(0, 1), true)
                    start = nil
                })
    }
}

/// A small knob (the track settings): drag up or right to turn it up.
struct DrumRollKnob: View {
    let value: Float
    var size: CGFloat = 36
    let change: (Float, Bool) -> Void
    @State private var start: Float?

    var body: some View {
        ZStack {
            MetalKnob(pointer: false)
            Capsule().fill(Color(white: 0.12)).frame(width: 2.5, height: size * 0.22)
                .offset(y: -size * 0.2)
                .rotationEffect(.degrees(KnobControl.angle(value)))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { g in
                if start == nil { start = value }
                let d = Float((-g.translation.height + g.translation.width * 0.6) / 180)
                change(((start ?? value) + d).clamped(0, 1), false)
            }
            .onEnded { g in
                let d = Float((-g.translation.height + g.translation.width * 0.6) / 180)
                change(((start ?? value) + d).clamped(0, 1), true)
                start = nil
            })
    }
}

/// Record from the mic straight onto one channel (standalone app).
struct ChannelRecordSheet: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = PadRecorder()

    var body: some View {
        NavigationView {
            VStack(spacing: 22) {
                Text(controller.rackChannels.first(where: { $0.pad == pad })?.name ?? Pad(rawValue: pad)?.channelTitle ?? "PAD").font(.system(.title2, design: .monospaced))
                if recorder.isRecording {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 0.2))
                            Capsule().fill(DrumRollStyle.red).frame(width: g.size.width * CGFloat(recorder.level))
                        }
                    }
                    .frame(height: 10)
                    Text(String(format: "%.1f s", recorder.seconds)).font(.system(.title3, design: .monospaced))
                    Button {
                        if let url = recorder.stop() {
                            controller.importSample(url, toPad: pad)
                            dismiss()
                        }
                    } label: { Label("Stop and use it", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DrumRollStyle.red)
                } else {
                    Button { recorder.start() } label: { Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DrumRollStyle.red)
                    Text("Make your sound when you're ready. The silence before it is trimmed, so the channel hits right away.")
                        .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                if let m = recorder.message { Text(m).font(.footnote).foregroundColor(DrumRollStyle.red) }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Record to channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { recorder.cancel(); dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .onDisappear { if recorder.isRecording { recorder.cancel() } }
    }
}
