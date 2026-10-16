// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

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
//   Right:  the STEP GRID (16 steps a bar), the track's piano roll when expanded, the velocity
//           lane under it. DRAW / SELECT / ERASE, undo / redo, SNAP, SNAP TO SCALE, SWING and
//           HUMANIZE, pinch to zoom (SNAP follows), 2 / 4 / 8 / 16 bars.
//   Bottom: PATTERN and KIT pickers with arrows.
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
    enum Lane: String, CaseIterable { case velocity = "VELOCITY", pitch = "PITCH" }
    enum Panel { case general, generate, midi }

    @State private var tool: Tool = .draw
    @State private var snap: Int32 = PatternData.stepTicks   // grid in ticks (0 = none)
    @State private var selectedID: UUID?                      // the track picked (dice, lane, strip)
    @State private var expandedID: UUID?                      // the track opened into its piano roll
    @State private var lane: Lane = .velocity
    @State private var follow = true
    @State private var page = 0
    @State private var zoomLevel = 0
    @State private var pinchBase: CGFloat = 1
    @State private var pinching = false
    static let zoomSnaps: [Int32] = [24, 12, 6, 3]
    @State private var selection = Set<NoteKey>()
    @State private var undoStack: [PatternData] = []
    @State private var redoStack: [PatternData] = []
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
    @State private var rackTargeted = false
    @State private var rowTargeted: UUID?
    @State private var showLibrary = false      // iPhone: the library slides over the rack
    @State private var section: Panel = .general
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
    private var pages: Int { max(1, Int((Int32(bars) * PatternEdit.barTicks + windowTicks - 1) / windowTicks)) }
    private var pageStart: Int32 { Int32(min(page, pages - 1)) * windowTicks }
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
    struct RowLayout { let channel: WorkspaceChannel; let y: CGFloat; let height: CGFloat; let pitch: ClosedRange<Int>?; let pitchRowH: CGFloat; let pitchTop: CGFloat }
    private func layouts(rowH: CGFloat) -> [RowLayout] {
        let pitchRowH = rowH * 0.3
        var y: CGFloat = 0
        var out: [RowLayout] = []
        for ch in channels {
            if ch.id == expandedID {
                let range = pitchRange(ch.pad)
                let h = rowH + CGFloat(range.count) * pitchRowH
                out.append(RowLayout(channel: ch, y: y, height: h, pitch: range, pitchRowH: pitchRowH, pitchTop: y + rowH)); y += h
            } else {
                out.append(RowLayout(channel: ch, y: y, height: rowH, pitch: nil, pitchRowH: pitchRowH, pitchTop: y)); y += rowH
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
    private func inBand(_ y: CGFloat, _ l: RowLayout) -> Bool { l.pitch != nil && y < l.pitchTop }

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
        static let pageBack: [Double] = [400, 246, 436, 280], pageText: [Double] = [436, 248, 534, 278], pageForward: [Double] = [534, 246, 572, 280]
        static let leftPanel: [Double] = [33, 300, 285, 693]
        static let rackX0: Double = 298, rackX1: Double = 534, gridX0: Double = 549, gridX1: Double = 1445, panelX1: Double = 1495
        static let rowsY0: Double = 341, rowsY1: Double = 594, rowH: Double = 56.5, labelsY: Double = 325
        static let laneY0: Double = 600, laneY1: Double = 682
        static let padsButton: [Double] = [97, 725, 137, 760], gridButton: [Double] = [47, 727, 87, 760]
        static let drumTrack: [Double] = [158, 715, 348, 768], drumCircle: [Double] = [164, 719, 212, 767]
        static let patternBack: [Double] = [602, 732, 640, 772], patternForward: [Double] = [640, 732, 677, 772], patternChip: [Double] = [677, 732, 841, 772]
        static let kitBack: [Double] = [889, 732, 927, 772], kitForward: [Double] = [927, 732, 964, 772], kitChip: [Double] = [964, 732, 1129, 772]
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Self.artW, geo.size.height / Self.artH)
            ZStack(alignment: .topLeading) {
                Image("SeqPlate").resizable().frame(width: Self.artW * s, height: Self.artH * s)
                topBar(s)
                leftPanel(s)
                editor(s)
                footer(s)
            }
            .frame(width: Self.artW * s, height: Self.artH * s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
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
        .onChange(of: loop) { _ in page = 0; selection = []; undoStack = []; redoStack = [] }
        .onDisappear { if controller.recording { controller.setRecording(false) } }
        .task(id: stored) { exportURL = writeMIDI() }
        .sheet(isPresented: $showMenu) { MenuView(controller: controller) }
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
    private func litRing(_ r: [Double], _ s: CGFloat, color: Color = S.green) -> some View {
        RoundedRectangle(cornerRadius: 7 * s).stroke(color, lineWidth: 1.5 * s)
            .background(RoundedRectangle(cornerRadius: 7 * s).fill(color.opacity(0.12)))
            .place(r, s).allowsHitTesting(false)
    }
    /// The picture's knob, turned to the value (drag up or right to turn it up).
    private func artKnob(_ r: [Double], _ s: CGFloat, value: Float, change: @escaping (Float, Bool) -> Void) -> some View {
        ArtKnob(value: value, change: change).place(r, s)
    }

    // MARK: Top bar

    @ViewBuilder private func topBar(_ s: CGFloat) -> some View {
        // DRAW / SELECT / ERASE
        ForEach(0..<3, id: \.self) { i in
            let t: Tool = [.draw, .select, .erase][i]
            let on = tool == t
            if on { litRing(A.tools[i], s) }
            HStack(spacing: 4 * s) {
                Image(systemName: ["pencil", "rectangle.dashed", "eraser"][i]).font(.system(size: 13 * s, weight: .medium))
                Text(["DRAW", "SELECT", "ERASE"][i]).font(.system(size: 13 * s, weight: .medium))
            }
            .foregroundColor(on ? S.green : .white).place(A.tools[i], s).allowsHitTesting(false)
            hit(A.tools[i], s) { tool = t }
        }
        HStack(spacing: 4 * s) { Image(systemName: "arrow.uturn.backward").font(.system(size: 13 * s, weight: .medium)); Text("UNDO").font(.system(size: 13 * s, weight: .medium)) }
            .foregroundColor(undoStack.isEmpty ? Color(white: 0.5) : .white).place(A.undo, s).allowsHitTesting(false)
        hit(A.undo, s) { undo() }
        HStack(spacing: 4 * s) { Image(systemName: "arrow.uturn.forward").font(.system(size: 13 * s, weight: .medium)); Text("REDO").font(.system(size: 13 * s, weight: .medium)) }
            .foregroundColor(redoStack.isEmpty ? Color(white: 0.5) : .white).place(A.redo, s).allowsHitTesting(false)
        hit(A.redo, s) { redo() }
        // bars pager
        artText(pageLabel, A.pageText, s, size: 17, weight: .medium, color: Color(white: 0.1))
        hit(A.pageBack, s) { page = max(0, page - 1); follow = false }
        hit(A.pageForward, s) { page = min(pages - 1, page + 1); follow = false }
        // transport
        RoundedRectangle(cornerRadius: 2 * s).fill(Color.white).frame(width: 15 * s, height: 15 * s).place([806, 205, 831, 228], s).allowsHitTesting(false)
        hit(A.stop, s) { controller.stopPlayback() }
        if isThisPlaying { litRing(A.play, s) }
        Image(systemName: "play.fill").font(.system(size: 17 * s)).foregroundColor(S.green).place(A.play, s).allowsHitTesting(false)
        hit(A.play, s) { controller.playPattern(loop) }
        if controller.recording { litRing(A.rec, s, color: S.red) }
        Circle().fill(S.red).frame(width: 17 * s, height: 17 * s).shadow(color: controller.recording ? S.red : .clear, radius: 5 * s)
            .place(A.rec, s).allowsHitTesting(false)
        hit(A.rec, s) {
            let on = !controller.recording
            controller.setRecording(on)
            if on && !isThisPlaying { controller.playPattern(loop) }
        }
        // tempo, bars, pattern, gear, cloud
        artText("\(Int(controller.liveTempo.rounded())) BPM", [A.bpm[0] + 10, A.bpm[1], A.bpm[2] - 26, A.bpm[3]], s, size: 15, align: .leading)
        PressGlow().bbPanelPlaced(A.bpm, s, title: "Tempo", width: 340) { TempoPanel(controller: controller) }
        artText("\(bars) BARS", [A.bars[0] + 10, A.bars[1], A.bars[2] - 26, A.bars[3]], s, size: 15, align: .leading)
        PressGlow().bbMenuPlaced(A.bars, s, title: "Pattern length") {
            [2, 4, 8, 16].map { b in BBMenuItem.item("\(b) BARS", checked: bars == b) { commit(PatternEdit.setLength(pattern, bars: b)) } }
        }
        artText(controller.loops.indices.contains(loop) ? controller.loops[loop].name : "PATTERN", [A.main[0] + 10, A.main[1], A.main[2] - 26, A.main[3]], s, size: 15, align: .leading)
        PressGlow().bbMenuPlaced(A.main, s, title: "Patterns in this preset", width: 260) {
            controller.loops.indices.map { i in BBMenuItem.item("\(i + 1)  \(controller.loops[i].name)", checked: i == loop) { loop = i } }
        }
        PressGlow().bbMenuPlaced(A.gear, s, title: "Sequencer", width: 330) { settingsItems() }
        if let url = exportURL {
            ShareLink(item: url) { Color.clear.contentShape(Rectangle()) }.place(A.cloud, s)
        }
        // snap, scale, swing, humanize
        artText(snapLabel, [A.snap[0] + 64, A.snap[1], A.snap[2] - 28, A.snap[3]], s, size: 13, align: .leading)
        PressGlow().bbMenuPlaced(A.snap, s, title: "Snap", width: 300) {
            Self.snapChoices.flatMap { group -> [BBMenuItem] in
                [.header(group.section)] + group.items.map { item in BBMenuItem.item(item.0, checked: item.1 == snap) { snap = item.1 } }
            }
        }
        // SNAP TO SCALE: a tuning fork on the SNAP chip's left edge (green when on)
        Image(systemName: "tuningfork").font(.system(size: 11 * s, weight: .semibold)).foregroundColor(controller.snapToScale ? S.green : Color(white: 0.45))
            .bbMenu(title: "Snap to scale", width: 300) { scaleItems(selectedPad) }
            .place([A.snap[0] + 2, A.snap[1], A.snap[0] + 22, A.snap[3]], s)
        artText(controller.value(.bounce) < 0.01 ? "OFF" : "\(Int(50 + controller.value(.bounce) * 22))%", [A.swing[0] + 76, A.swing[1], A.swing[2] - 46, A.swing[3]], s, size: 13, align: .leading)
        artKnob(A.swingKnob, s, value: controller.value(.bounce)) { v, ended in
            if swingStart == nil { swingStart = controller.value(.bounce) }
            controller.set(.bounce, v)
            if ended { swingStart = nil }
        }
        artKnob(A.humanizeKnob, s, value: pattern.humanize ?? 0) { v, ended in
            if humanizeStart == nil { humanizeStart = pattern.humanize ?? 0; undoStack.append(pattern); redoStack = [] }
            var p = pattern
            p.humanize = v < 0.01 ? nil : v
            work = p
            if ended { humanizeStart = nil; work = nil; controller.setLoop(loop, p) }
        }
    }

    private func settingsItems() -> [BBMenuItem] {
        [
            .item("BreakBoss menu…", icon: "line.3.horizontal") { showMenu = true },
            .item("Follow playhead", icon: "arrow.right.to.line", checked: follow) { follow.toggle() },
            .item("Metronome", icon: "metronome", checked: controller.metronome) { controller.setMetronome(!controller.metronome) },
            .item("Duplicate \(selection.isEmpty ? "the pattern" : "selection")", icon: "plus.square.on.square") { duplicate() },
            .item("Copy these bars to the next ones", icon: "doc.on.doc") {
                commit(PatternEdit.copyNext(pattern, fromBar: Int(pageStart / PatternEdit.barTicks), bars: max(1, Int(pageTicks / PatternEdit.barTicks))))
            },
            .item("Quantize \(selection.isEmpty ? "all notes" : "selection")", icon: "squareshape.split.3x3") {
                commit(PatternEdit.quantize(pattern, selection.isEmpty ? nil : selection, grid: snapTicks > 0 ? snapTicks : PatternData.stepTicks))
            },
            .item("Back to the preset's pattern", icon: "arrow.uturn.backward") { controller.useGeneratedLoop(loop); selection = [] },
            .item("Kit's 12 channels back in the rack", icon: "square.grid.3x3") { controller.resetRack(); expandedID = nil; selectedID = nil },
            .item("Clear \(selection.isEmpty ? "the pattern" : "selection")", icon: "trash", destructive: true) { clear() }
        ]
    }

    private var pageLabel: String {
        let bar = Int(pageStart / PatternEdit.barTicks) + 1
        if zoomLevel == 0 {
            let last = min(bars, bar + barsPerPage - 1)
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

    @ViewBuilder private func leftPanel(_ s: CGFloat) -> some View {
        let x0 = 33.0, x1 = 284.0, bx0 = 41.0, bx1 = 274.0
        let top = 320.0, midiBottom = 686.0
        // section headers (the picture's own), stacked by what's open
        let headerH = 44.0, genHeaderH = 51.0, gap = 9.0
        let generalBottom = top + headerH
        switch section {
        case .generate:
            Image("SeqSectionGeneral").resizable().place([x0, top, x1, generalBottom], s)
            hit([x0, top, x1, generalBottom], s) { withAnimation(.easeInOut(duration: 0.22)) { section = .general } }
            Image("SeqSectionGenerate").resizable().place([bx0, 375, bx1, 632], s)
            generateOverlay([bx0, 375, bx1, 632], s)
            Image("SeqSectionMidi").resizable().place([x0, 642, x1, midiBottom], s)
            hit([x0, 642, x1, midiBottom], s) { withAnimation(.easeInOut(duration: 0.22)) { section = .midi } }
        case .general:
            Image("SeqSectionGeneral").resizable().place([x0, top, x1, generalBottom], s)
            Image(systemName: "chevron.up").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(.white).place([x1 - 44, top, x1 - 20, generalBottom], s).allowsHitTesting(false)
            let genTop = 642 - gap - genHeaderH
            soundsPanel([bx0, generalBottom + gap, bx1, genTop - gap], s)
            Image("SeqGenerateHeader").resizable().place([bx0, genTop, bx1, genTop + genHeaderH], s)
            Image(systemName: "chevron.down").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(.white).place([bx1 - 40, genTop, bx1 - 16, genTop + genHeaderH], s).allowsHitTesting(false)
            hit([bx0, genTop, bx1, genTop + genHeaderH], s) { withAnimation(.easeInOut(duration: 0.22)) { section = .generate } }
            Image("SeqSectionMidi").resizable().place([x0, 642, x1, midiBottom], s)
            hit([x0, 642, x1, midiBottom], s) { withAnimation(.easeInOut(duration: 0.22)) { section = .midi } }
        case .midi:
            Image("SeqSectionGeneral").resizable().place([x0, top, x1, generalBottom], s)
            hit([x0, top, x1, generalBottom], s) { withAnimation(.easeInOut(duration: 0.22)) { section = .general } }
            let genTop = generalBottom + gap
            Image("SeqGenerateHeader").resizable().place([bx0, genTop, bx1, genTop + genHeaderH], s)
            Image(systemName: "chevron.down").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(.white).place([bx1 - 40, genTop, bx1 - 16, genTop + genHeaderH], s).allowsHitTesting(false)
            hit([bx0, genTop, bx1, genTop + genHeaderH], s) { withAnimation(.easeInOut(duration: 0.22)) { section = .generate } }
            let midiTop = genTop + genHeaderH + gap
            Image("SeqSectionMidi").resizable().place([x0, midiTop, x1, midiTop + headerH], s)
            Image(systemName: "chevron.up").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(.white).place([x1 - 44, midiTop, x1 - 20, midiTop + headerH], s).allowsHitTesting(false)
            hit([x0, midiTop, x1, midiTop + headerH], s) { withAnimation(.easeInOut(duration: 0.22)) { section = .generate } }
            midiPanel([bx0, midiTop + headerH + gap, bx1, midiBottom], s)
        }
    }

    /// The GENERATE box's live parts: GENRE, UPDATE SOUNDS, UPDATE TEMPO, Generate, Clear.
    @ViewBuilder private func generateOverlay(_ r: [Double], _ s: CGFloat) -> some View {
        let x0 = r[0], x1 = r[2]
        // GENRE value (the picture says "House"): covered with the box's black, then the live genre
        Rectangle().fill(Color(white: 0.04)).place([x0 + 12, 458, x1 - 40, 484], s).allowsHitTesting(false)
        artText(generateStyle ?? PatternRandomizer.style(for: controller.state.presetName), [x0 + 14, 458, x1 - 40, 484], s, size: 17, weight: .regular, align: .leading)
        PressGlow().bbMenuPlaced([x0, 436, x1, 490], s, title: "Genre", width: 280) {
            [BBMenuItem.item("This preset's style", checked: generateStyle == nil) { generateStyle = nil }]
            + PatternBank.styles.map { st in BBMenuItem.item(st, checked: generateStyle == st) { generateStyle = st } }
        }
        Rectangle().fill(Color(white: 0.04)).place([x0 + 12, 526, x0 + 60, 548], s).allowsHitTesting(false)
        artText(updateSounds ? "On" : "Off", [x0 + 14, 526, x0 + 60, 548], s, size: 16, weight: .regular, color: updateSounds ? .white : Color(white: 0.5), align: .leading)
        hit([x0, 500, x0 + 116, 556], s) { updateSounds.toggle() }
        Rectangle().fill(Color(white: 0.04)).place([x0 + 128, 526, x0 + 176, 548], s).allowsHitTesting(false)
        artText(updateTempo ? "On" : "Off", [x0 + 130, 526, x0 + 176, 548], s, size: 16, weight: .regular, color: updateTempo ? .white : Color(white: 0.5), align: .leading)
        hit([x0 + 118, 500, x1, 556], s) { updateTempo.toggle() }
        hit([x0 + 12, 570, x0 + 140, 616], s) { generate() }
        hit([x0 + 146, 570, x1 - 8, 616], s) { clear() }
    }

    /// The sound library (GENERAL open): type chips, search, the list, import. Drag a sound to the rack.
    private func soundsPanel(_ r: [Double], _ s: CGFloat) -> some View {
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
        .padding(8 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s).fill(Color(white: 0.04)).overlay(RoundedRectangle(cornerRadius: 12 * s).stroke(Color(white: 0.2), lineWidth: 1)))
        .place(r, s)
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
        controller.randomizePattern(style: style)
        if updateSounds { controller.dice() }
        if updateTempo, !controller.tempoIsExternal {
            let bpms = PatternBank.presets(in: style).map(\.bpm)
            if !bpms.isEmpty { controller.setBPM((bpms.reduce(0, +) / Double(bpms.count)).rounded()) }
        }
        selection = []
    }

    private func midiPanel(_ r: [Double], _ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            Button { controller.setMIDIOut(!controller.midiOutOn) } label: {
                HStack(spacing: 6 * s) {
                    Circle().fill(controller.midiOutOn ? S.green : Color(white: 0.3)).frame(width: 8 * s, height: 8 * s)
                    Text(controller.midiOutOn ? "MIDI OUT ON" : "MIDI OUT OFF").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(.white)
                }
                .frame(maxWidth: .infinity).frame(height: 32 * s).background(RoundedRectangle(cornerRadius: 6 * s).fill(Color(white: 0.2)))
            }
            HStack {
                Text("ROUTING").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 11 * s, weight: .semibold)).foregroundColor(.white)
            }
            .padding(.horizontal, 10 * s).frame(height: 32 * s).background(RoundedRectangle(cornerRadius: 6 * s).fill(Color(white: 0.2)))
            .contentShape(Rectangle()).bbMenu(title: "MIDI out", width: 340) { midiOutItems() }
            Text(controller.isPlugin ? "Route the plug-in's MIDI output in your DAW. Each channel sends on its own MIDI channel; the 808 is pitched on channel 7."
                                     : "Other apps see \"BreakBoss Out\" as a MIDI source.")
                .font(.system(size: 9 * s)).foregroundColor(S.dim)
            Spacer(minLength: 0)
        }
        .padding(8 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s).fill(Color(white: 0.04)).overlay(RoundedRectangle(cornerRadius: 12 * s).stroke(Color(white: 0.2), lineWidth: 1)))
        .place(r, s)
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

    // MARK: Editor: the rack and the grid on the picture's panels, the velocity lane under them

    @ViewBuilder private func editor(_ s: CGFloat) -> some View {
        let rowH = A.rowH * s
        let gridW = (A.gridX1 - A.gridX0) * s
        let L = layouts(rowH: rowH)
        let contentH = max(L.last.map { $0.y + $0.height } ?? 0, (A.rowsY1 - A.rowsY0) * s)
        // beat numbers
        ruler(width: gridW).place([A.gridX0, A.labelsY - 10, A.gridX1, A.labelsY + 10], s)
        // the rows: rack column and the grid, scrolling together
        ScrollView(.vertical, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Color.clear.frame(width: (A.panelX1 - A.rackX0) * s, height: contentH)
                rackColumn(L, rowH: rowH, s: s).frame(width: (A.rackX1 - A.rackX0) * s, height: contentH, alignment: .top)
                grid(L, width: gridW, rowH: rowH).frame(width: gridW, height: contentH)
                    .offset(x: (A.gridX0 - A.rackX0) * s)
                // the dice at the end of every track: that track's steps only
                ForEach(L, id: \.channel.id) { l in
                    Button { selectedID = l.channel.id; controller.randomizeChannel(loop: loop, pad: l.channel.pad); selection = [] } label: {
                        Image(systemName: "dice").font(.system(size: 13 * s)).foregroundColor(Color(white: 0.75))
                            .frame(width: 30 * s, height: 30 * s).background(RoundedRectangle(cornerRadius: 5 * s).fill(Color(white: 0.14)))
                    }
                    .offset(x: (A.gridX1 + 10 - A.rackX0) * s, y: l.y + (min(l.height, rowH) - 30 * s) / 2)
                }
            }
        }
        .frame(width: (A.panelX1 - A.rackX0) * s, height: (A.rowsY1 - A.rowsY0) * s)
        .position(x: (A.rackX0 + A.panelX1) / 2 * s, y: (A.rowsY0 + A.rowsY1) / 2 * s)
        .onDrop(of: [.plainText, .fileURL, .audio], isTargeted: $rackTargeted) { providers in dropOnRack(providers, channel: nil) }
        if rackTargeted {
            RoundedRectangle(cornerRadius: 8 * s).stroke(S.green, lineWidth: 2 * s).place([A.rackX0, A.rowsY0 - 4, A.rackX1, A.rowsY1], s).allowsHitTesting(false)
        }
        // the velocity lane
        laneHeader(s).place([A.rackX0 + 4, A.laneY0, A.rackX1, A.laneY1], s)
        laneView(width: gridW, height: (A.laneY1 - A.laneY0) * s).place([A.gridX0, A.laneY0, A.gridX1, A.laneY1], s)
    }

    private func ruler(width: CGFloat) -> some View {
        Canvas { ctx, size in
            let px = { (t: Int32) in CGFloat(t - pageStart) / CGFloat(pageTicks) * size.width }
            var t = pageStart
            while t < pageStart + pageTicks {
                if t % PatternData.ppq == 0 {
                    let beat = (t - pageStart) / PatternData.ppq + 1
                    let label = zoomLevel == 0 ? "\(beat)" : "\(t / PatternEdit.barTicks + 1).\((t % PatternEdit.barTicks) / PatternData.ppq + 1)"
                    ctx.draw(Text(label).font(.system(size: size.height * 0.65, weight: .medium)).foregroundColor(.white), at: CGPoint(x: px(t) + size.height * 0.5, y: size.height / 2))
                }
                t += PatternData.ppq
            }
            _ = tick
        }
    }

    // MARK: Channel rack (the picture's rows)

    private func rackColumn(_ L: [RowLayout], rowH: CGFloat, s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(L, id: \.channel.id) { l in
                channelRow(l, rowH: rowH, s: s).offset(y: l.y)
            }
            if channels.count < Pad.count {
                let y = (L.last.map { $0.y + $0.height } ?? 0)
                VStack(spacing: 3 * s) {
                    Image(systemName: "plus.circle.dashed").font(.system(size: 16 * s)).foregroundColor(rackTargeted ? S.green : Color(white: 0.45))
                    Text(rackTargeted ? "DROP FOR A NEW CHANNEL" : "DROP A SOUND HERE").font(.system(size: 8 * s, weight: .semibold)).foregroundColor(rackTargeted ? S.green : Color(white: 0.45))
                }
                .frame(width: (A.rackX1 - A.rackX0) * s, height: rowH).offset(y: y)
            }
        }
    }

    private func channelRow(_ l: RowLayout, rowH: CGFloat, s: CGFloat) -> some View {
        let ch = l.channel, pad = ch.pad
        let muted = controller.mutedPads[pad]
        let isSel = selectedID == ch.id
        let ps = controller.state.pads[pad]
        func set(_ change: (inout PadSettings) -> Void) { var v = controller.state.pads[pad]; change(&v); controller.setPadSettings(pad, v) }
        // art offsets inside the row sprite (298, 334): triangle 303-312, oval 321-524, name 335-425, knobs 440 / 478, lamp 509
        let X = { (ax: Double) in CGFloat(ax - A.rackX0) * s }
        return ZStack(alignment: .topLeading) {
            Image("SeqRow").resizable().frame(width: 240 * s, height: 58 * s)
                .scaleEffect(newborn.contains(ch.id) ? 0.3 : 1).opacity(newborn.contains(ch.id) ? 0 : 1)
            // the lit oval of the selected track
            if isSel {
                Capsule().stroke(S.green, lineWidth: 1.5 * s).frame(width: 203 * s, height: 45 * s).offset(x: X(321), y: 5 * s).allowsHitTesting(false)
            }
            Text(ch.name).font(.system(size: 13 * s, weight: .semibold)).foregroundColor(muted ? Color(white: 0.5) : .white).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 92 * s, height: 45 * s, alignment: .leading).offset(x: X(335), y: 5 * s)
                .allowsHitTesting(false)
            // the triangle opens the piano roll
            if expandedID == ch.id {
                Image(systemName: "triangle.fill").font(.system(size: 8 * s)).foregroundColor(S.green).rotationEffect(.degrees(180))
                    .frame(width: 18 * s, height: 20 * s).background(Color(red: 0.86, green: 0.86, blue: 0.87)).offset(x: X(300), y: 17 * s).allowsHitTesting(false)
            }
            PressableArea { withAnimation(.easeInOut(duration: 0.2)) { expandedID = expandedID == ch.id ? nil : ch.id }; selectedID = ch.id }
                .frame(width: 24 * s, height: 45 * s).offset(x: X(298), y: 5 * s)
            // tap the name: select; long-press: the channel menu
            Color.clear.contentShape(Rectangle()).frame(width: 105 * s, height: 45 * s).offset(x: X(321), y: 5 * s)
                .bbLongPressMenu(title: ch.name, width: 270, tap: { selectedID = ch.id }) { channelMenu(ch) }
            ArtKnob(value: ps.level) { v, _ in set { $0.level = v } }.frame(width: 30 * s, height: 30 * s).offset(x: X(425), y: 13 * s)
            ArtKnob(value: (ps.pan + 1) / 2) { v, _ in let p = v * 2 - 1; set { $0.pan = abs(p) < 0.03 ? 0 : p } }.frame(width: 30 * s, height: 30 * s).offset(x: X(463), y: 13 * s)
            // the lamp: on / off
            if muted { Circle().fill(Color(white: 0.12)).frame(width: 9 * s, height: 9 * s).offset(x: X(504.5), y: 23.5 * s).allowsHitTesting(false) }
            PressableArea { controller.toggleMute(pad) }.frame(width: 22 * s, height: 30 * s).offset(x: X(498), y: 13 * s)
            if l.pitch != nil { pitchKeys(l, s: s).offset(y: rowH) }
        }
        .frame(width: (A.rackX1 - A.rackX0) * s, height: l.height, alignment: .topLeading)
        .background(rowTargeted == ch.id ? S.green.opacity(0.25) : Color.clear)
        .onDrop(of: [.plainText, .fileURL, .audio], isTargeted: Binding(get: { rowTargeted == ch.id }, set: { rowTargeted = $0 ? ch.id : nil })) { providers in
            dropOnRack(providers, channel: ch)
        }
    }

    private func pitchKeys(_ l: RowLayout, s: CGFloat) -> some View {
        let range = l.pitch ?? 0...0
        let base = controller.baseNote(pad: l.channel.pad)
        return VStack(spacing: 0) {
            ForEach(Array(range.reversed()), id: \.self) { sm in
                let note = base + sm
                let inScale = !controller.snapToScale || controller.scale.contains(note, root: controller.scaleRoot)
                let isRoot = controller.snapToScale && (note - controller.scaleRoot) % 12 == 0
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
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { _ = newborn.remove(id) }
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
        items.append(BBMenuItem.item("Randomize its steps", icon: "dice") { controller.randomizeChannel(loop: loop, pad: pad) })
        items.append(BBMenuItem.item(expandedID == ch.id ? "Close the piano roll" : "Open the piano roll", icon: "pianokeys") {
            withAnimation { expandedID = expandedID == ch.id ? nil : ch.id }
        })
        items.append(BBMenuItem.item("Track settings… (tune, decay, filter, MIDI)", icon: "slider.horizontal.3") { selectedID = ch.id; trackSettingsID = ch.id })
        items.append(BBMenuItem.item(controller.soloPads[pad] ? "Solo off" : "Solo", icon: "s.square", checked: controller.soloPads[pad]) { controller.toggleSolo(pad) })
        items.append(BBMenuItem.item("Load a sample from Files…", icon: "folder") { importPad = pad })
        items.append(BBMenuItem.item("Clear its steps", icon: "xmark", destructive: true) { commit(PatternEdit.clearChannel(pattern, pad: pad)) })
        items.append(BBMenuItem.item("Delete channel", icon: "trash", destructive: true) {
            if expandedID == ch.id { expandedID = nil }
            if selectedID == ch.id { selectedID = nil }
            controller.removeRackChannel(ch.id)
        })
        return items
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
        return CGRect(x: x(e.tick, w) + 1, y: l.y + 2, width: noteWidth(e, w), height: l.height - 4)
    }
    private func visible(_ e: GrooveEvent) -> Bool { e.tick >= pageStart && e.tick < pageStart + pageTicks }

    private func grid(_ L: [RowLayout], width w: CGFloat, rowH: CGFloat) -> some View {
        Canvas { ctx, size in
            let cell = ctx.resolve(Image("SeqCell"))
            let cw = cellWidth(size.width)
            let cells = Int(pageTicks / cellTicks)
            for (i, l) in L.enumerated() {
                if let range = l.pitch {
                    // the band: the track's steps, lit where it has notes (any pitch)
                    ctx.fill(Path(CGRect(x: 0, y: l.y, width: size.width, height: l.pitchTop - l.y)), with: .color(S.greenDark.opacity(0.5)))
                    for c in 0..<cells {
                        let at = pageStart + Int32(c) * cellTicks
                        let lit = pattern.events.contains { Int($0.pad) == l.channel.pad && $0.tick >= at && $0.tick < at + cellTicks }
                        let r = CGRect(x: CGFloat(c) * cw + 1, y: l.y, width: cw - 2, height: l.pitchTop - l.y)
                        ctx.draw(cell, in: r)
                        if (Int(at / PatternData.ppq) % 2) == 1 { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.32))) }
                        if lit { ctx.fill(Path(roundedRect: r.insetBy(dx: 1, dy: 2), cornerRadius: 3), with: .color(noteColor.opacity(0.8))) }
                    }
                    // the piano roll: a stripe per semitone (scale notes lighter, the root greener)
                    let base = controller.baseNote(pad: l.channel.pad)
                    for (k, s) in range.reversed().enumerated() {
                        let note = base + s
                        let inScale = !controller.snapToScale || controller.scale.contains(note, root: controller.scaleRoot)
                        let isRoot = controller.snapToScale && (note - controller.scaleRoot) % 12 == 0
                        let y = l.pitchTop + CGFloat(k) * l.pitchRowH
                        ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: l.pitchRowH)),
                                 with: .color(isRoot ? S.green.opacity(0.1) : (inScale ? (k % 2 == 0 ? S.rowA : S.rowB) : Color.black.opacity(0.35))))
                        if s == 0 { ctx.fill(Path(CGRect(x: 0, y: y + l.pitchRowH - 1, width: size.width, height: 1)), with: .color(S.dim.opacity(0.5))) }
                    }
                    ctx.fill(Path(CGRect(x: 0, y: l.y, width: size.width, height: 1)), with: .color(S.green.opacity(0.5)))
                    ctx.fill(Path(CGRect(x: 0, y: l.y + l.height - 1, width: size.width, height: 1)), with: .color(S.green.opacity(0.5)))
                } else {
                    // the step buttons (the picture's)
                    for c in 0..<cells {
                        let at = pageStart + Int32(c) * cellTicks
                        let r = CGRect(x: CGFloat(c) * cw + 1, y: l.y, width: cw - 2, height: l.height)
                        ctx.draw(cell, in: r)
                        // every other beat's buttons are the darker grey (Tyrone's picture)
                        if (Int(at / PatternData.ppq) % 2) == 1 { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.32))) }
                        if at >= pattern.lengthTicks { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.55))) }
                    }
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
            for e in pattern.events where visible(e) {
                guard let r = noteRect(e, w: size.width, L) else { continue }
                let sel = selection.contains(NoteKey(e))
                let base = sel ? Color.white : noteColor
                let shade = 0.55 + 0.45 * Double(e.velocity)
                if layout(for: Int(e.pad), L)?.pitch == nil {
                    // A step button keeps its shape: the inner slot lights up in the faceplate's colour
                    // (MODERN red, VINTAGE cream, TEXTURE blue) and the button body takes a tint.
                    ctx.fill(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: .color(base.opacity(0.14 + 0.16 * Double(e.velocity))))
                    let slot = CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.09, width: r.width * 0.76, height: max(3, r.height * 0.14))
                    ctx.fill(Path(roundedRect: slot.insetBy(dx: -2, dy: -2), cornerRadius: 4), with: .color(base.opacity(0.35 * shade)))
                    ctx.fill(Path(roundedRect: slot, cornerRadius: slot.height / 2), with: .color(base.opacity(shade)))
                    ctx.fill(Path(roundedRect: CGRect(x: slot.minX + 1, y: slot.minY + 1, width: slot.width - 2, height: max(1, slot.height * 0.35)), cornerRadius: 1), with: .color(Color.white.opacity(0.3)))
                } else {
                    ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(base.opacity(shade)))
                    ctx.fill(Path(roundedRect: CGRect(x: r.minX + 2, y: r.minY + 2, width: r.width - 4, height: max(2, r.height * 0.12)), cornerRadius: 1.5), with: .color(Color.white.opacity(0.35)))
                }
                if sel { ctx.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.white), lineWidth: 1.5) }
                if sel && tool == .select {
                    ctx.fill(Path(roundedRect: CGRect(x: r.maxX - 4, y: r.minY + 2, width: 3, height: max(2, r.height - 4)), cornerRadius: 1.5),
                             with: .color(Color.black.opacity(0.55)))
                }
                if e.semis != 0 && r.width > 14 && layout(for: Int(e.pad), L)?.pitch == nil {
                    ctx.draw(Text(e.semis > 0 ? "+\(Int(e.semis))" : "\(Int(e.semis))").font(.system(size: 9, weight: .bold)).foregroundColor(.black),
                             at: CGPoint(x: r.midX, y: r.midY))
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
        .highPriorityGesture(DragGesture(minimumDistance: 0)
            .onChanged { g in if !pinching { gridChanged(g, w: w, L: L) } }
            .onEnded { g in if pinching { drag = .none; work = nil } else { gridEnded(g, w: w, L: L) } })
        .simultaneousGesture(pinch)
    }

    private func setZoom(_ level: Int) {
        let newLevel = max(0, min(Self.zoomSnaps.count - 1, level))
        guard newLevel != zoomLevel else { return }
        let center = pageStart + pageTicks / 2
        zoomLevel = newLevel
        page = max(0, min(pages - 1, Int(center / windowTicks)))
        snap = Self.zoomSnaps[newLevel]
        follow = false
    }

    private var pinch: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
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

    // MARK: Velocity / pitch lane

    private func laneHeader(_ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4 * s) {
            HStack(spacing: 6 * s) {
                HStack {
                    Text(lane.rawValue).font(.system(size: 12 * s, weight: .medium)).foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10 * s, weight: .semibold)).foregroundColor(.white)
                }
                .padding(.horizontal, 10 * s).frame(width: 150 * s, height: 36 * s)
                .background(RoundedRectangle(cornerRadius: 6 * s).fill(Color(white: 0.1)).overlay(RoundedRectangle(cornerRadius: 6 * s).stroke(Color(white: 0.3), lineWidth: 1)))
                .contentShape(Rectangle())
                .bbMenu(title: "Lane", width: 200) { Lane.allCases.map { l in BBMenuItem.item(l.rawValue, checked: lane == l) { lane = l } } }
                // velocity dice: new velocities only (selected notes, or the selected track, or all)
                Button {
                    commit(PatternEdit.randomizeVelocity(pattern, pad: selectedPad, keys: selection, seed: UInt64.random(in: 1...UInt64.max)))
                } label: {
                    Image(systemName: "dice.fill").font(.system(size: 14 * s)).foregroundColor(.white)
                        .frame(width: 40 * s, height: 36 * s).background(RoundedRectangle(cornerRadius: 6 * s).fill(Color(white: 0.1)).overlay(RoundedRectangle(cornerRadius: 6 * s).stroke(Color(white: 0.3), lineWidth: 1)))
                }
            }
            if let ch = selected { Text(ch.name).font(.system(size: 9 * s, design: .monospaced)).foregroundColor(Color(white: 0.25)).lineLimit(1) }
            Spacer(minLength: 0)
        }
        .padding(.top, 6 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }


    private func laneView(width w: CGFloat, height h: CGFloat) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(S.lane))
            for frac in [0.0, 0.5, 1.0] {
                ctx.fill(Path(CGRect(x: 0, y: CGFloat(frac) * (size.height - 8) + 4, width: size.width, height: 1)), with: .color(S.stepLine))
            }
            var lt = ((pageStart + PatternData.ppq - 1) / PatternData.ppq) * PatternData.ppq
            while lt <= pageStart + pageTicks {
                let bx = CGFloat(lt - pageStart) / CGFloat(pageTicks) * size.width
                let bar = lt % PatternEdit.barTicks == 0
                ctx.fill(Path(CGRect(x: bx, y: 0, width: bar ? 1.5 : 1, height: size.height)), with: .color(bar ? S.beatLine : S.stepLine))
                lt += PatternData.ppq
            }
            let marks: [(String, CGFloat, UnitPoint)] = lane == .velocity
                ? [("127", 1, .topTrailing), ("64", 0.5, .trailing), ("0", 0, .bottomTrailing)]
                : [("+12", 1, .topTrailing), ("0", 0.5, .trailing), ("-12", 0, .bottomTrailing)]
            for m in marks {
                let y = 4 + (1 - m.1) * (size.height - 8)
                ctx.draw(Text(m.0).font(.system(size: 10, design: .monospaced)).foregroundColor(Color.white.opacity(0.55)),
                         at: CGPoint(x: size.width - 4, y: m.1 == 1 ? y + 2 : (m.1 == 0 ? y - 2 : y)), anchor: m.2)
            }
            for e in pattern.events where visible(e) && (selectedPad == nil || Int(e.pad) == selectedPad) {
                let sel = selection.contains(NoteKey(e))
                let v: CGFloat = lane == .velocity ? CGFloat(e.velocity) : CGFloat((e.semis.clamped(-12, 12) + 12) / 24)
                let bx = x(e.tick, size.width) + 3
                let top = 4 + (1 - v) * (size.height - 8)
                ctx.fill(Path(CGRect(x: bx, y: top, width: 5, height: size.height - 4 - top)),
                         with: .color((sel ? Color.white : noteColor).opacity(selection.isEmpty || sel ? 0.95 : 0.35)))
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in laneChanged(g, w: w, h: h) }
            .onEnded { _ in
                if let p = work { work = nil; controller.setLoop(loop, p) } else if laneOrigin != nil { _ = undoStack.popLast() }
                laneOrigin = nil
            })
    }

    @State private var laneOrigin: PatternData?

    private func laneChanged(_ g: DragGesture.Value, w: CGFloat, h: CGFloat) {
        if laneOrigin == nil { laneOrigin = pattern; undoStack.append(pattern); redoStack = [] }
        let v = Float(1 - (g.location.y - 4) / (h - 8)).clamped(0, 1)
        let keys = Set(pattern.events.filter { e in
            visible(e) && abs(x(e.tick, w) + 5 - g.location.x) <= 8 && (selection.isEmpty || selection.contains(NoteKey(e)))
                && (selectedPad == nil || Int(e.pad) == selectedPad)
        }.map(NoteKey.init))
        guard !keys.isEmpty else { return }
        if lane == .velocity {
            let value = max(0.05, v)
            work = PatternEdit.setVelocity(pattern, keys, value)
            lastVelocity = value
        } else {
            let raw = (v * 24 - 12).rounded()
            let (p, newKeys) = PatternEdit.setPitch(pattern, keys, selectedPad.map { controller.scaleSnapped(raw, pad: $0) } ?? raw)
            work = p
            if !selection.isEmpty { selection = selection.subtracting(keys).union(newKeys) }
        }
    }

    // MARK: Footer (pattern, kit)

    private var orderedKits: [KitDefinition] { SoundMode.allCases.flatMap { KitLibrary.kits(for: $0) } + KitLibrary.genres }

    @ViewBuilder private func footer(_ s: CGFloat) -> some View {
        // pads / sequencer switch: the pad button goes back to the faceplate
        hit(A.padsButton, s) { dismiss() }
        // Drum Track: MPC-style pad recording
        if controller.recording {
            Circle().stroke(S.red, lineWidth: 3 * s).shadow(color: S.red, radius: 6 * s).place(A.drumCircle, s).allowsHitTesting(false)
            Circle().fill(S.red).frame(width: 12 * s, height: 12 * s).place(A.drumCircle, s).allowsHitTesting(false)
        }
        hit(A.drumTrack, s) { controller.toggleRecordPads() }
        // PATTERN
        artText(controller.state.presetName, [A.patternChip[0] + 6, A.patternChip[1], A.patternChip[2] - 30, A.patternChip[3]], s, size: 14, align: .leading)
        PressGlow().bbMenuPlaced(A.patternChip, s, title: "Presets", width: 340) { presetItems() }
        hit(A.patternBack, s) { cycleLoop(-1) }
        hit(A.patternForward, s) { cycleLoop(1) }
        // KIT
        artText(controller.state.kitName, [A.kitChip[0] + 6, A.kitChip[1], A.kitChip[2] - 30, A.kitChip[3]], s, size: 14, align: .leading)
        PressGlow().bbMenuPlaced(A.kitChip, s, title: "Kits · drum sounds", width: 320) { kitItems() }
        hit(A.kitBack, s) { cycleKit(-1) }
        hit(A.kitForward, s) { cycleKit(1) }
    }

    /// PRESETS: every preset pattern by style, and your own.
    private func presetItems() -> [BBMenuItem] {
        var items: [BBMenuItem] = []
        for style in PatternBank.styles {
            items.append(.submenu(style, icon: "music.note.list",
                PatternBank.presets(in: style).map { p in
                    BBMenuItem.item(p.name, detail: "\(Int(p.bpm)) BPM\(p.swing > 50.5 ? " · \(Int(p.swing))% SWING" : "")",
                                    checked: controller.state.presetName == p.name) { controller.loadPatternPreset(p); selection = [] }
                }))
        }
        if !controller.userPresets.isEmpty {
            items.append(.submenu("My presets", icon: "person.crop.square", controller.userPresets.map { name in
                BBMenuItem.item(name) { controller.loadUserPreset(name); selection = [] }
            }))
        }
        return items
    }

    private func kitItems() -> [BBMenuItem] {
        SoundMode.allCases.map { mode in
            BBMenuItem.submenu("\(mode.title) kits", icon: "square.grid.3x3", KitLibrary.kits(for: mode).map { def in
                BBMenuItem.item(def.name, checked: def.id == controller.state.kitID) { controller.selectKit(def) }
            })
        } + [BBMenuItem.submenu("Genre kits", icon: "music.note.list", KitLibrary.genreGroups.map { g in
            BBMenuItem.submenu(g.genre, icon: "square.grid.3x3", g.kits.map { def in
                BBMenuItem.item(def.name, checked: def.id == controller.state.kitID) { controller.selectKit(def) }
            })
        })]
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
        controller.loadPatternPreset(all[(i + step + all.count) % all.count]); selection = []
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
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BreakBoss \(controller.state.kitName) \(name).mid")
        do {
            try MIDIFile.write(stored, tempo: controller.liveTempo, bounce: controller.value(.bounce), bars: bars, to: url)
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
        let target = min(pages - 1, Int(t) / Int(pageTicks))
        if target != page { page = target }
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
                BBSlider(value: controller.state.bpm, range: 40...240, step: 1, label: { "\(Int($0)) BPM" }) { controller.setBPM($0) }
                HStack(spacing: 6) {
                    ForEach([70, 90, 100, 120, 140, 160], id: \.self) { b in
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
    let change: (Float, Bool) -> Void
    @State private var start: Float?

    var body: some View {
        Image("SeqKnob").resizable().aspectRatio(contentMode: .fit)
            .rotationEffect(.degrees(KnobControl.angle(value)))
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

/// A small knob (the track settings): drag up or right to turn it up.
struct DrumRollKnob: View {
    let value: Float
    var size: CGFloat = 36
    let change: (Float, Bool) -> Void
    @State private var start: Float?

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
            Circle().stroke(Color.black, lineWidth: 2)
            Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2.5, height: size * 0.28)
                .offset(y: -size * 0.25)
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
