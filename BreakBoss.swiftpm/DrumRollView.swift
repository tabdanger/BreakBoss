// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - BreakBoss channel rack
//
// Tyrone's DRUM ROLL design, working like FL Studio's channel rack / piano roll:
// DRAW (tap to add, tap a note to delete, drag a note to move, drag the end of an 808 to
// stretch it, drag along a row to paint), SELECT (drag a box, then move / duplicate /
// delete), ERASE (wipe over notes), a velocity / pitch lane under the grid, per-channel
// mute / solo / preview, loading or recording a sample straight onto a channel, and a
// piano roll for each channel. All note changes go through KnockController.setLoop, so the
// engine, presets and MIDI export all see the same pattern. Kits only change the sounds.

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
}

struct DrumRollView: View {
    @ObservedObject var controller: KnockController
    @State var loop: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var library: RackSoundLibrary
    @State private var showLibrary = true
    @State private var confirmEmptyRack = false
    @State private var confirmFactoryRack = false
    private let onDone: (() -> Void)?
    @State private var showGeneral = false
    @State private var showExport = false
    @State private var showLane = true
    @State private var genre = "Trap"
    @State private var updateSounds = true
    @State private var updateTempo = false
    @State private var generalExpanded = false
    @State private var generateExpanded = true
    @State private var midiExpanded = false
    @State private var rackTargeted = false
    @State private var knownChannels = Set<UUID>()
    @State private var bubbleChannels = Set<UUID>()

    init(controller: KnockController, loop: Int, library: RackSoundLibrary? = nil, onDone: (() -> Void)? = nil) {
        self.onDone = onDone
        self.controller = controller
        _loop = State(initialValue: loop)
        _library = StateObject(wrappedValue: library ?? RackSoundLibrary())
    }

    enum Tool { case draw, select, erase }
    enum Lane: String, CaseIterable { case velocity = "VELOCITY", pitch = "PITCH" }

    @State private var tool: Tool = .draw
    @State private var snap: Int32 = PatternData.stepTicks   // grid in ticks (0 = none)
    @State private var selectedPad: Int?                      // channel picked for its own edits
    @State private var lane: Lane = .velocity
    @State private var follow = true
    @State private var page = 0
    /// Pinch zoom: 0 = the normal view, 1 = one bar, 2 = half a bar, 3 = one beat. SNAP follows it.
    @State private var zoomLevel = 0
    @State private var pinchBase: CGFloat = 1
    @State private var pinching = false
    static let zoomSnaps: [Int32] = [24, 12, 6, 3]
    @State private var selection = Set<NoteKey>()
    @State private var undoStack: [PatternData] = []
    @State private var redoStack: [PatternData] = []
    @State private var work: PatternData?      // live copy while a finger is down
    @State private var drag: GridDrag = .none
    @State private var lastVelocity: Float = 0.78
    @State private var last808Length: Int32 = PatternEdit.default808Length
    @State private var humanizeStart: Float?
    @State private var swingStart: Float?
    @State private var showMenu = false
    @State private var importPad: Int?
    @State private var soundPad: Int?
    @State private var recordPad: Int?
    @State private var pianoRollPad: Int?
    @State private var exportURL: URL?
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    enum GridDrag {
        case none
        case paint(pad: Int, lastCell: Int)
        case long808(pad: Int, start: Int32)
        case move(keys: Set<NoteKey>, origin: PatternData, startTick: Int32, followSelection: Bool)
        case resize(key: NoteKey, origin: PatternData)
        case trim(keys: Set<NoteKey>, origin: PatternData, startTick: Int32)
        case marquee(start: CGPoint, current: CGPoint)
        case erase
        case tapOnNote(key: NoteKey)
    }

    private typealias S = DrumRollStyle

    // MARK: Pattern and grid maths

    private var pattern: PatternData { work ?? stored }
    /// The pattern as saved (without a drag in progress).
    private var stored: PatternData {
        controller.loops.indices.contains(loop) ? controller.loops[loop]
            : PatternData(name: "", lengthTicks: PatternEdit.barTicks * 2, events: [])
    }
    private var compact: Bool { sizeClass == .compact }
    private var bars: Int { max(1, pattern.bars) }
    private var barsPerPage: Int { min(2, bars) }
    /// The visible stretch of the pattern at this zoom.
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
    /// Grid step in ticks for the SNAP setting (0 = free, placed on 1/64ths).
    private var snapTicks: Int32 { snap }

    /// SNAP values, FL Studio style (96 ticks per beat, a step is a 16th).
    static let snapChoices: [(section: String, items: [(String, Int32)])] = [
        ("Straight", [("1/2 (half note)", 192), ("Beat (1/4)", 96), ("1/2 Beat (1/8)", 48), ("1/4 Beat (1/16)", 24),
                      ("Step (1/16)", 24), ("1/2 Step (1/32)", 12), ("1/4 Step (1/64)", 6),
                      ("1/16", 24), ("1/32", 12), ("1/64", 6), ("1/128", 3)]),
        ("Triplet", [("1/3 Beat (1/8 triplet)", 32), ("1/3 Step (1/16 triplet)", 8), ("1/6 Beat", 16), ("1/6 Step", 4)]),
        ("Off", [("None (free)", 0)])
    ]
    private var snapLabel: String {
        for group in Self.snapChoices { if let hit = group.items.first(where: { $0.1 == snap }) { return hit.0.components(separatedBy: " (").first ?? hit.0 } }
        return "\(snap) TICKS"
    }
    private var placeTicks: Int32 { snapTicks > 0 ? snapTicks : 6 }
    private var noteColor: Color { S.green }
    private var channels: [RackChannel] { controller.rackChannels }
    private var channelSlots: [Int] { channels.map(\.slot) }
    private func isBass(_ slot: Int) -> Bool { controller.channelRole(slot) == Pad.bass808.rawValue }
    private func rowIndex(_ slot: Int) -> Int? { channelSlots.firstIndex(of: slot) }
    private func slotAt(_ row: Int) -> Int? { channelSlots.indices.contains(row) ? channelSlots[row] : nil }
    private var ink: Color { Color(white: 0.12) }
    private var inkDim: Color { Color(white: 0.33) }
    private var isThisPlaying: Bool { controller.isPlaying && Int(controller.meters.status[1]) == loop }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 1050
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                header
                if let notice = controller.notice {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundColor(S.orange)
                        Text(notice).font(.system(size: 11)).foregroundColor(S.text).frame(maxWidth: .infinity, alignment: .leading)
                        Button { controller.notice = nil } label: { Image(systemName: "xmark").frame(width: 36, height: 36).foregroundColor(S.text) }
                            .accessibilityLabel("Dismiss message")
                    }
                    .padding(.horizontal, 12).frame(minHeight: 42).background(Color(white: 0.11))
                    .accessibilityElement(children: .contain)
                }
                if let pad = selectedPad, channelSlots.contains(pad) { channelStrip(pad) }
                HStack(spacing: 8) {
                    if wide { generalPanel.frame(width: 184) }
                    editor
                    if wide || (landscape && showLibrary) {
                        RackSoundBrowser(controller: controller, library: library, onAdd: addSound,
                                         onClose: wide ? nil : { showLibrary = false })
                            .frame(width: wide ? min(260, geo.size.width * 0.21) : 230)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.7), lineWidth: 2))
                    }
                }
                .padding(.horizontal, landscape ? 10 : 6)
                .padding(.vertical, 7)
                if !wide && !landscape && showLibrary {
                    RackSoundBrowser(controller: controller, library: library, onAdd: addSound, onClose: { showLibrary = false })
                        .frame(height: min(360, geo.size.height * 0.43))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 8).padding(.bottom, 7)
                }
                footer
            }
            .background(RackMetal())
            .clipShape(RoundedRectangle(cornerRadius: landscape ? 26 : 20))
            .overlay(RoundedRectangle(cornerRadius: landscape ? 26 : 20).stroke(LinearGradient(colors: [.white.opacity(0.95), Color(white: 0.3), .white.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
            .padding(landscape ? 8 : 4)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .bbMenuHost()
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .background(spaceBar)
        .onReceive(ticker) { now in
            if isThisPlaying { tick = now }
            if controller.recording { controller.mergeRecorded(snap: snapTicks) }
            followPlayhead()
        }
        .onAppear {
            controller.setRackWorkspaceOpen(true)
            knownChannels = Set(channels.map(\.id))
            genre = PatternRandomizer.style(for: controller.state.presetName)
        }
        .onChange(of: channels.map(\.id)) { ids in
            let current = Set(ids)
            if current != knownChannels {
                // Undo snapshots refer to audio slots. A removed slot may be reused by a new
                // UUID; neither an old drag nor old undo notes may cross that boundary.
                work = nil; drag = .none; selection = []
                undoStack = []; redoStack = []; laneOrigin = nil; humanizeStart = nil
            }
            bubbleChannels.formUnion(current.subtracting(knownChannels))
            bubbleChannels.formIntersection(current)
            knownChannels = current
            if let pad = selectedPad, !channelSlots.contains(pad) { selectedPad = nil }
        }
        .onChange(of: showLibrary) { if $0 { library.refresh() } }
        .onChange(of: loop) { _ in page = 0; selection = []; undoStack = []; redoStack = [] }
        .onDisappear {
            controller.setRackWorkspaceOpen(false)
            if controller.recording { controller.setRecording(false) }
        }
        .task(id: stored) { exportURL = writeMIDI() }
        .confirmationDialog("Start a new empty channel rack?", isPresented: $confirmEmptyRack, titleVisibility: .visible) {
            Button("Clear channels and start empty", role: .destructive) {
                controller.clearRackChannels()
                selectedPad = nil
                selection = []
                showLibrary = true
            }
        } message: {
            Text("This removes the current rack's sounds and notes from all 12 patterns. Save a preset first if you want to keep this rack.")
        }
        .confirmationDialog("Restore the kit's 12 channels?", isPresented: $confirmFactoryRack, titleVisibility: .visible) {
            Button("Restore kit channels and clear notes", role: .destructive) { controller.restoreFactoryRackChannels() }
        } message: {
            Text("This replaces the current rack with the selected kit's original sounds and clears the notes from all 12 patterns.")
        }
        .sheet(isPresented: $showMenu) { MenuView(controller: controller) }
        .sheet(isPresented: $showExport) { ExportView(controller: controller) }
        .sheet(isPresented: $showGeneral) {
            ScrollView { generalPanel.padding(18) }.background(RackMetal())
                .presentationDetents([.medium, .large])
        }
        .sheet(item: Binding(get: { pianoRollPad.map { PadID(pad: $0) } }, set: { pianoRollPad = $0?.pad })) { target in
            PianoRollView(controller: controller, loop: loop, pad: target.pad)
        }
        .sheet(item: Binding(get: { recordPad.map { PadID(pad: $0) } }, set: { recordPad = $0?.pad })) { target in
            ChannelRecordSheet(controller: controller, pad: target.pad)
        }
        .fullScreenCover(item: Binding(get: { soundPad.map { PadID(pad: $0) } }, set: { soundPad = $0?.pad })) { target in
            SoundLibraryView(controller: controller, pad: target.pad) { soundPad = nil }
        }
        .fileImporter(isPresented: Binding(get: { importPad != nil }, set: { if !$0 { importPad = nil } }),
                      allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first, let pad = importPad { controller.importSample(url, toPad: pad) }
            importPad = nil
        }
    }

    struct PadID: Identifiable { let pad: Int; var id: Int { pad } }

    /// Space bar (hardware keyboard): play / stop. Standalone only; in a DAW the space bar is the DAW's.
    @ViewBuilder private var spaceBar: some View {
        if !controller.isPlugin {
            Button("") { controller.togglePlayback(pattern: loop) }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }

    // MARK: Brushed-metal control bridge

    private var header: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 1050
            VStack(spacing: 5) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { if let onDone { onDone() } else { dismiss() } } label: { iconBox("chevron.left") }
                            .accessibilityLabel("Return to instrument")
                        if wide { brand.frame(width: 160) }
                        HStack(spacing: 5) {
                            toolButton(.draw, "pencil", "DRAW")
                            toolButton(.select, "rectangle.dashed", "SELECT")
                            toolButton(.erase, "eraser", "ERASE")
                            Button { undo() } label: { labelBox("arrow.uturn.backward", "UNDO", enabled: !undoStack.isEmpty) }.disabled(undoStack.isEmpty)
                            Button { redo() } label: { labelBox("arrow.uturn.forward", "REDO", enabled: !redoStack.isEmpty) }.disabled(redoStack.isEmpty)
                        }
                        divider
                        transport
                        bpmMenu
                        barsMenu
                        variationMenu
                        settingsMenu
                        Button { showMenu = true } label: { iconBox("cloud") }.accessibilityLabel("Projects, sounds and settings")
                    }
                    .padding(.horizontal, 12)
                }
                HStack(spacing: 8) {
                    if !wide {
                        if geo.size.width > 590 { Text("BreakBoss").font(.system(size: 18, weight: .black)).foregroundColor(ink) }
                        Button { showGeneral = true } label: { compactMetalButton("slider.horizontal.3", "GENERATE") }
                        Spacer(minLength: 0)
                    } else { pageControl.frame(width: 184) }
                    if !wide { pageControl }
                    if wide {
                        snapMenu
                        swingBlock
                        humanizeBlock
                    }
                    Button { showLibrary.toggle() } label: { compactMetalButton("waveform", wide ? "SOUNDS" : nil) }
                        .accessibilityLabel(showLibrary ? "Hide sound library" : "Open sound library")
                }
                .padding(.horizontal, 12)
            }
            .padding(.top, 9)
        }
        .frame(height: 111)
        .overlay(Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1), alignment: .bottom)
    }

    private var brand: some View {
        VStack(spacing: 0) {
            Image(systemName: "crown.fill").font(.system(size: 16, weight: .black))
            Text("BreakBoss").font(.system(size: 28, weight: .black)).tracking(-1.5)
            Text("D R U M  S E Q U E N C E R").font(.system(size: 7, weight: .bold))
        }
        .foregroundColor(ink)
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        HStack(spacing: 5) {
            Button { controller.stopPlayback() } label: { iconBox("stop.fill") }.accessibilityLabel("Stop")
            Button { controller.togglePlayback(pattern: loop) } label: {
                Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold)).foregroundColor(S.green)
                    .shadow(color: isThisPlaying ? S.green.opacity(0.6) : .clear, radius: 5)
                    .frame(width: 44, height: 44).background(box(lit: isThisPlaying))
            }.accessibilityLabel(isThisPlaying ? "Pause sequence" : "Play sequence")
            Button {
                let on = !controller.recording
                controller.setRecording(on)
                if on && !isThisPlaying { controller.playPattern(loop) }
            } label: {
                Circle().fill(S.red).frame(width: 18, height: 18)
                    .shadow(color: controller.recording ? S.red : .clear, radius: 5)
                    .frame(width: 44, height: 44).background(box(lit: controller.recording, color: S.red))
            }.accessibilityLabel(controller.recording ? "Stop recording notes" : "Record notes")
        }
    }

    private var variationMenu: some View {
        chip(LoopSlot(rawValue: loop)?.title.uppercased() ?? "MAIN A", width: 110)
            .bbMenu(title: "Sequence", width: 260) {
                controller.loops.indices.map { i in .item(LoopSlot(rawValue: i)?.title ?? "Sequence \(i + 1)", checked: loop == i) { loop = i } }
            }
    }

    private func compactMetalButton(_ icon: String, _ title: String?) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
            if let title { Text(title).font(.system(size: 10, weight: .bold)) }
        }
        .foregroundColor(ink).frame(minWidth: 40, minHeight: 36).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.2)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.22), lineWidth: 1))
    }

    private var bpmMenu: some View {
        chip("\(Int(controller.liveTempo.rounded())) BPM", width: 112)
            .bbPanel(title: "Tempo", width: 340) { TempoPanel(controller: controller) }
    }

    private var barsMenu: some View {
        chip("\(bars) BAR\(bars == 1 ? "" : "S")", width: 104)
            .bbMenu(title: "Pattern length") {
                [2, 4, 8, 16].map { b in BBMenuItem.item("\(b) BARS", checked: bars == b) { commit(PatternEdit.setLength(pattern, bars: b)) } }
            }
    }

    /// PRESETS area (bottom, next to the kits): which of the 12 patterns you're editing, and every
    /// preset pattern by style. Loading a preset keeps the beat playing and the kit as it is.
    private var patternMenu: some View {
        chip(controller.loops.indices.contains(loop) ? controller.loops[loop].name : "PATTERN", width: compact ? 120 : 170)
            .bbMenu(title: "Patterns · presets", width: 340) {
                var items: [BBMenuItem] = [.header("This preset's patterns")]
                items += controller.loops.indices.map { i in BBMenuItem.item("\(i + 1)  \(controller.loops[i].name)", checked: i == loop) { loop = i } }
                items.append(.header("Presets · \(controller.state.presetName)"))
                for style in PatternBank.styles {
                    items.append(.submenu(style, icon: style == "Danger Patterns" ? "bolt.fill" : "music.note.list",
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
    }

    private var settingsMenu: some View {
        iconBox("gearshape.fill").bbMenu(title: "Drum roll", width: 320) {
            [
                .item("Follow playhead", icon: "arrow.right.to.line", checked: follow) { follow.toggle() },
                .item("Metronome", icon: "metronome", checked: controller.metronome) { controller.setMetronome(!controller.metronome) },
                .item("Randomize all sounds and patterns", icon: "dice.fill") { controller.dice(); controller.randomizePattern(); selection = [] },
                .item("Show event lane", icon: "slider.vertical.3", checked: showLane) { showLane.toggle() },
                .submenu("MIDI out (external gear)", icon: "cable.connector", midiOutItems()),
                .item("Copy these bars to the next ones", icon: "doc.on.doc") {
                    commit(PatternEdit.copyNext(pattern, fromBar: Int(pageStart / PatternEdit.barTicks), bars: max(1, Int(pageTicks / PatternEdit.barTicks))))
                },
                .item("Quantize \(selection.isEmpty ? "all notes" : "selection")", icon: "squareshape.split.3x3") {
                    commit(PatternEdit.quantize(pattern, selection.isEmpty ? nil : selection, grid: snapTicks > 0 ? snapTicks : PatternData.stepTicks))
                },
                .item("Back to the preset's pattern", icon: "arrow.uturn.backward") { controller.useGeneratedLoop(loop); selection = [] },
                .item("Blank pattern", icon: "trash", destructive: true) { var p = pattern; p.events = []; commit(p); selection = [] }
            ]
        }
    }

    // MARK: Toolbar

    private var snapMenu: some View {
        chip("SNAP  \(snapLabel)", width: 180)
            .bbMenu(title: "Snap", width: 300) {
                Self.snapChoices.flatMap { group -> [BBMenuItem] in
                    [.header(group.section)] + group.items.map { item in
                        BBMenuItem.item(item.0, checked: item.1 == snap && item.0.hasPrefix(snapLabel)) { snap = item.1 }
                    }
                }
            }
    }

    private var swingBlock: some View {
        knobBlock(title: "SWING", value: controller.value(.bounce),
                  text: controller.value(.bounce) < 0.01 ? "OFF" : "\(Int(50 + controller.value(.bounce) * 22))%",
                  menu: AnyView(swingMenu)) { value, _ in controller.set(.bounce, value) }
    }

    private var humanizeBlock: some View {
        knobBlock(title: "HUMANIZE", value: pattern.humanize ?? 0, text: nil, menu: nil) { value, ended in
            if humanizeStart == nil { humanizeStart = pattern.humanize ?? 0; pushUndo(pattern) }
            var edited = pattern
            edited.humanize = value < 0.01 ? nil : value
            work = edited
            if ended { humanizeStart = nil; work = nil; controller.setLoop(loop, edited) }
        }
    }

    private var generalPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                panelHeading("GENERAL", expanded: $generalExpanded)
                if generalExpanded {
                    VStack(spacing: 8) {
                        snapMenu
                        swingBlock
                        humanizeBlock
                        Button { controller.setMetronome(!controller.metronome) } label: {
                            labelBox("metronome", "METRONOME", lit: controller.metronome)
                        }
                        Button { showLane.toggle() } label: { labelBox("slider.vertical.3", "EVENT LANE", lit: showLane) }
                        Button { setZoom(0) } label: { labelBox("arrow.up.left.and.arrow.down.right", "RESET ZOOM") }
                    }.padding(.bottom, 10)
                }
                VStack(spacing: 0) {
                    panelHeading("GENERATE", expanded: $generateExpanded, dark: true)
                    if generateExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("GENRE").font(.system(size: 10, weight: .medium)).foregroundColor(S.dim)
                            chip(genre, width: 152).bbMenu(title: "Generate by genre", width: 280) {
                                PatternBank.styles.map { style in .item(style, checked: genre == style) { genre = style } }
                            }
                            HStack(spacing: 0) {
                                generateToggle("UPDATE SOUNDS", value: $updateSounds)
                                Rectangle().fill(S.border).frame(width: 1, height: 38)
                                generateToggle("UPDATE TEMPO", value: $updateTempo)
                            }
                            HStack(spacing: 4) {
                                Button {
                                    pushUndo(pattern)
                                    controller.generateRackPattern(loop: loop, style: genre, updateSounds: updateSounds, updateTempo: updateTempo)
                                    selection = []
                                } label: {
                                    Label("Generate", systemImage: "dice.fill")
                                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color(red: 0.8, green: 0.02, blue: 0.04), Color(red: 0.47, green: 0, blue: 0.01)], startPoint: .top, endPoint: .bottom)))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.2), lineWidth: 1))
                                }
                                Button { clear() } label: {
                                    Image(systemName: "xmark").font(.system(size: 15)).foregroundColor(S.text).frame(width: 34, height: 44)
                                }.accessibilityLabel("Clear sequence or selected notes")
                            }
                        }
                        .padding(10)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.055)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.25), lineWidth: 1))
                .padding(.horizontal, 8)
                panelHeading("MIDI", expanded: $midiExpanded)
                if midiExpanded {
                    VStack(spacing: 5) {
                        labelBox("cable.connector", "MIDI ROUTING", lit: controller.midiOutOn)
                            .bbMenu(title: "MIDI out", width: 300) { midiOutItems() }
                        Button { showExport = true } label: { labelBox("square.and.arrow.up", "EXPORT") }
                        Text("Draw notes, record pads, or send each channel to external gear.")
                            .font(.system(size: 10)).foregroundColor(inkDim).padding(10)
                    }
                }
            }
        }
        .background(RackMetal(dark: true))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.black.opacity(0.8), lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.75), lineWidth: 1).padding(2))
    }

    private func panelHeading(_ text: String, expanded: Binding<Bool>, dark: Bool = false) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack {
                Text(text).font(.system(size: 12, weight: .semibold))
                Spacer()
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down").font(.system(size: 12))
            }
            .foregroundColor(dark ? S.text : ink).padding(.horizontal, 16).frame(minHeight: 52)
        }
        .accessibilityValue(expanded.wrappedValue ? "Expanded" : "Collapsed")
    }

    private func generateToggle(_ label: String, value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.system(size: 7, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                Text(value.wrappedValue ? "On" : "Off").font(.system(size: 12))
            }.foregroundColor(S.text).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .accessibilityLabel(label).accessibilityValue(value.wrappedValue ? "On" : "Off")
    }

    private var swingMenu: some View {
        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(S.text)
            .frame(width: 22, height: 30)
            .bbMenu(title: "Swing", width: 220) {
                [0, 54, 56, 58, 62, 66, 72].map { pct in
                    BBMenuItem.item(pct == 0 ? "Off" : "\(pct)%") { controller.set(.bounce, pct == 0 ? 0 : Float(pct - 50) / 22) }
                }
            }
    }

    private var divider: some View { Rectangle().fill(S.border).frame(width: 1, height: 30) }

    private func toolButton(_ t: Tool, _ icon: String, _ title: String) -> some View {
        Button { tool = t } label: { labelBox(icon, title, lit: tool == t) }
    }

    private func knobBlock(title: String, value: Float, text: String?, menu: AnyView?,
                           change: @escaping (Float, Bool) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text.map { "\(title)  \($0)" } ?? title)
                .font(.system(size: 10, weight: .medium)).foregroundColor(S.text).fixedSize()
            if let menu { menu }
            DrumRollKnob(value: value, change: change)
        }
        .padding(.horizontal, 8).frame(height: 36)
        .background(box(lit: false))
    }

    // MARK: Editor (channels, ruler, grid, lane)

    private var editor: some View {
        GeometryReader { geo in
            let stripW: CGFloat = geo.size.width < 600 ? 194 : 216
            let gridW = max(512, geo.size.width - stripW - 12)
            let rowH: CGFloat = 52
            let rowsH = CGFloat(channels.count) * rowH
            ScrollViewReader { reader in
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Text("CHANNEL RACK").font(.system(size: 10, weight: .bold)).tracking(1)
                        Text("\(channels.count)/\(RackLimits.maxChannels)").font(.system(size: 9, design: .monospaced))
                            .foregroundColor(rackFull ? Color(red: 0.63, green: 0.06, blue: 0.03) : inkDim)
                            .accessibilityLabel("\(channels.count) of \(RackLimits.maxChannels) channels")
                        Spacer(minLength: 0)
                        Button {
                            if rackFull { confirmEmptyRack = true } else { showLibrary = true }
                        } label: { compactMetalButton(rackFull ? "doc.badge.plus" : "plus", rackFull ? "NEW" : "SOUND") }
                            .accessibilityLabel(rackFull ? "Start a new empty rack" : "Add a sound")
                        compactMetalButton("ellipsis", nil)
                            .bbMenu(title: "Channel rack", width: 290) {
                                var items: [BBMenuItem] = [
                                    .item("New empty rack…", icon: "doc.badge.plus", destructive: true) { confirmEmptyRack = true }
                                ]
                                if channels.count < RackLimits.maxChannels {
                                    items.append(.item("Restore the kit's 12 channels", icon: "arrow.uturn.backward") { confirmFactoryRack = true })
                                }
                                return items
                            }
                            .accessibilityLabel("Channel rack options")
                    }
                    .foregroundColor(ink).padding(.horizontal, 12).frame(height: 43)
                    .onDrop(of: [RackSoundDrag.type, UTType.fileURL, UTType.audio], isTargeted: nil) { dropIntoRack($0) }
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                HStack {
                                    Text("SOUND").font(.system(size: 9, weight: .bold))
                                    Spacer()
                                    Text("LEVEL  PAN").font(.system(size: 8, weight: .medium))
                                }.foregroundColor(inkDim).padding(.horizontal, 18).frame(width: stripW, height: 28)
                                ruler(width: gridW).frame(width: gridW, height: 28)
                            }
                            ScrollView(.vertical, showsIndicators: true) {
                                VStack(spacing: 0) {
                                    HStack(spacing: 0) {
                                        VStack(spacing: 0) {
                                            ForEach(channels) { channel in
                                                channelRow(channel.slot, height: rowH).id(channel.id)
                                            }
                                        }.frame(width: stripW)
                                        grid(width: gridW, rowH: rowH).frame(width: gridW, height: rowsH)
                                            .onDrop(of: [RackSoundDrag.type, UTType.fileURL, UTType.audio], isTargeted: nil) { dropIntoRack($0) }
                                    }
                                    addChannelTarget.frame(width: stripW + gridW, height: 62).id("rack-drop-target")
                                }
                            }
                            .frame(maxHeight: .infinity)
                            if showLane && geo.size.height > 300 {
                                HStack(spacing: 0) {
                                    laneHeader.frame(width: stripW, height: 84)
                                    laneView(width: gridW, height: 84).frame(width: gridW, height: 84)
                                }
                                .overlay(Rectangle().fill(.black.opacity(0.7)).frame(height: 4), alignment: .top)
                            }
                        }
                        .frame(width: stripW + gridW)
                    }
                }
                .onChange(of: channels.map(\.id)) { ids in
                    guard let inserted = ids.last(where: { !knownChannels.contains($0) }) ?? ids.last,
                          bubbleChannels.contains(inserted) || ids.count > knownChannels.count else { return }
                    if reduceMotion { reader.scrollTo(inserted, anchor: .center) }
                    else { withAnimation(.easeOut(duration: 0.25)) { reader.scrollTo(inserted, anchor: .center) } }
                }
            }
        }
        .background(RackMetal())
        .clipShape(RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.black.opacity(0.8), lineWidth: 3))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.5), lineWidth: 1).padding(3))
    }

    private var rackFull: Bool { channels.count >= RackLimits.maxChannels }

    private var addChannelTarget: some View {
        Button { if rackFull { confirmEmptyRack = true } else { showLibrary = true } } label: {
            HStack(spacing: 10) {
                Image(systemName: rackFull ? "info.circle" : "plus.circle").font(.system(size: 21, weight: .light))
                Text(rackFull ? "12 CHANNELS · REMOVE ONE OR START A NEW EMPTY RACK" : (rackTargeted ? "DROP TO ADD CHANNEL" : "DRAG A SOUND HERE TO ADD A CHANNEL"))
                    .font(.system(size: 10, weight: .semibold)).tracking(0.5)
            }
            .foregroundColor(rackTargeted ? S.green : S.dim)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: rackTargeted ? 0.12 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(rackTargeted ? S.green : .white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4])).padding(8))
        }
        .onDrop(of: [RackSoundDrag.type, UTType.fileURL, UTType.audio], isTargeted: $rackTargeted) { providers in
            dropIntoRack(providers)
        }
        .accessibilityLabel(rackFull ? "Rack is full. Start a new empty rack" : "Add a sound as a new channel")
        .accessibilityHint(rackFull ? "Remove a channel from its menu, or activate to start a new empty rack." : "Drop a library sound or audio file, or activate to open the sound library")
    }

    /// The selected channel's own controls: its sound, level, pan, tune, decay, filter,
    /// reverse, piano roll and dice. Nothing here touches the other channels.
    private func channelStrip(_ pad: Int) -> some View {
        let ps = controller.state.pads[pad]
        func set(_ change: (inout PadSettings) -> Void) { var v = controller.state.pads[pad]; change(&v); controller.setPadSettings(pad, v) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.channelName(pad)).font(.system(size: 14, weight: .semibold)).foregroundColor(S.green)
                    Text(controller.padName(pad).uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(S.dim).lineLimit(1)
                }
                .frame(width: 120, alignment: .leading)
                labelBox("waveform", compact ? nil : "SAMPLE")
                    .bbMenu(title: controller.padName(pad), width: 320) { channelSampleItems(pad) }
                // SNAP TO SCALE (replaces the piano roll button): key, scale, snap on/off, fit notes
                labelBox("tuningfork", compact ? nil : (controller.snapToScale
                         ? "\(MusicScale.noteNames[controller.scaleRoot]) \(controller.scale.name.uppercased())" : "SNAP TO SCALE"),
                         lit: controller.snapToScale)
                    .bbMenu(title: "Snap to scale", width: 300) { scaleItems(pad) }
                Button { pianoRollPad = pad } label: { labelBox("pianokeys", "PIANO ROLL") }
                Button { controller.randomizeChannel(loop: loop, pad: pad) } label: { labelBox("dice", nil) }
                labelBox("cable.connector", midiOutLabel(pad), lit: controller.midiOutOn && controller.midiOutChannels[pad] >= 0)
                    .bbMenu(title: "MIDI out · \(controller.channelName(pad))", width: 240) { midiOutChannelItems(pad) }
                divider
                stripKnob("LEVEL", ps.level, 0...1, String(format: "%.0f%%", ps.level / 0.8 * 100)) { v in set { $0.level = v } }
                stripKnob("PAN", ps.pan, -1...1, ps.pan == 0 ? "C" : String(format: "%@%.0f", ps.pan < 0 ? "L" : "R", abs(ps.pan) * 100)) { v in set { $0.pan = abs(v) < 0.03 ? 0 : v } }
                stripKnob("TUNE", ps.tune, -24...24, String(format: "%+.1f", ps.tune)) { v in set { $0.tune = (v * 2).rounded() / 2 } }
                stripKnob("DECAY", ps.decay, 0.05...1, ps.decay >= 0.999 ? "FULL" : String(format: "%.0f%%", ps.decay * 100)) { v in set { $0.decay = v } }
                stripKnob("FILTER", ps.filter, 0...1, ps.filter >= 0.999 ? "OPEN" : String(format: "%.0f Hz", 40 * powf(450, ps.filter))) { v in set { $0.filter = v } }
                Button { set { $0.reverse.toggle() } } label: { labelBox("arrow.left.arrow.right", "REV", lit: ps.reverse) }
                Button { selectedPad = nil } label: { iconBox("xmark") }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 58)
        .background(S.channel)
        .overlay(Rectangle().fill(S.green.opacity(0.6)).frame(height: 1), alignment: .bottom)
    }

    private func channelSampleItems(_ pad: Int) -> [BBMenuItem] {
        var items: [BBMenuItem] = [.item("Sound library…", icon: "square.and.arrow.down") { soundPad = pad },
                                   .item("Load a sample from Files…", icon: "folder") { importPad = pad }]
        if !controller.isPlugin { items.append(.item("Record to this channel…", icon: "record.circle") { recordPad = pad }) }
        let files = KnockFolders.sampleFiles()
        if !files.isEmpty {
            items.append(.submenu("Your samples", icon: "tray.full", files.map { url in
                BBMenuItem.item(url.deletingPathExtension().lastPathComponent) { controller.importSample(url, toPad: pad) }
            }))
        }
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

    private var pageLabel: String {
        let bar = Int(pageStart / PatternEdit.barTicks) + 1
        if zoomLevel == 0 {
            let last = min(bars, bar + barsPerPage - 1)
            return last == bar ? "BAR \(bar)" : "BARS \(bar)–\(last)"
        }
        let beat = Int((pageStart % PatternEdit.barTicks) / PatternData.ppq) + 1
        return zoomLevel == 1 ? "BAR \(bar) · ZOOM" : "BAR \(bar).\(beat) · ZOOM"
    }

    /// Two-finger spread / pinch (touch or trackpad): one zoom level per clear spread, around the
    /// middle of what's on screen. SNAP gets finer as you zoom in (1/16, 1/32, 1/64, 1/128).
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
                    // a finger that landed first may have started drawing: undo that
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

    private var pageControl: some View {
        HStack(spacing: 6) {
            Button { page = max(0, page - 1); follow = false } label: {
                Image(systemName: "chevron.left").foregroundColor(page > 0 ? ink : inkDim).frame(width: 28, height: 36)
            }.disabled(page == 0)
            Text(pageLabel)
                .font(.system(size: 11, weight: .semibold)).foregroundColor(ink).lineLimit(1)
            Button { page = min(pages - 1, page + 1); follow = false } label: {
                Image(systemName: "chevron.right").foregroundColor(page < pages - 1 ? ink : inkDim).frame(width: 28, height: 36)
            }.disabled(page >= pages - 1)
        }
    }

    private func ruler(width: CGFloat) -> some View {
        Canvas { ctx, size in
            let px = { (t: Int32) in CGFloat(t - pageStart) / CGFloat(pageTicks) * size.width }
            let fine: Int32 = zoomLevel >= 2 ? 6 : PatternData.stepTicks
            var t = pageStart
            while t <= pageStart + pageTicks {
                let x = px(t)
                if t % PatternData.ppq == 0 {
                    let isBar = t % PatternEdit.barTicks == 0
                    ctx.fill(Path(CGRect(x: x, y: size.height - 5, width: isBar ? 1.5 : 1, height: 5)), with: .color(S.dim.opacity(0.5)))
                    if t < pageStart + pageTicks {
                        let label = zoomLevel == 0 ? "\(t / PatternData.ppq + 1)"
                            : "\(t / PatternEdit.barTicks + 1).\((t % PatternEdit.barTicks) / PatternData.ppq + 1)"
                        ctx.draw(Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(S.text), at: CGPoint(x: x + 10, y: 12))
                    }
                }
                t += fine
            }
            ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(S.border))
        }
        .background(S.channel)
    }

    private func channelRow(_ pad: Int, height: CGFloat) -> some View {
        let muted = controller.mutedPads[pad]
        let solo = controller.soloPads[pad]
        let settings = controller.state.pads[pad]
        let identity = channels.first(where: { $0.slot == pad })?.id
        return HStack(spacing: 2) {
            Button { controller.auditionPad(pad) } label: {
                Image(systemName: "play.fill").font(.system(size: 12)).foregroundColor(inkDim)
                    .frame(width: 23, height: 44)
            }.accessibilityLabel("Preview \(controller.channelName(pad))")
            RackBubbleHeader(animateInsertion: identity.map { bubbleChannels.contains($0) } ?? false, selected: selectedPad == pad) {
                HStack(spacing: 0) {
                    Text(controller.channelName(pad).uppercased())
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(muted ? S.dim : S.text)
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .bbLongPressMenu(title: controller.channelName(pad), width: 300,
                                         tap: { selectedPad = selectedPad == pad ? nil : pad }) { channelMenu(pad) }
                    RackChromeKnob(title: "\(controller.channelName(pad)) level", value: settings.level.clamped(0, 1)) { value in
                        var edited = controller.state.pads[pad]; edited.level = value; controller.setPadSettings(pad, edited)
                    }
                    RackChromeKnob(title: "\(controller.channelName(pad)) pan", value: (settings.pan + 1) * 0.5) { value in
                        var edited = controller.state.pads[pad]; let pan = value * 2 - 1
                        edited.pan = abs(pan) < 0.035 ? 0 : pan; controller.setPadSettings(pad, edited)
                    }
                    Button { controller.toggleMute(pad) } label: {
                        Circle().fill(muted ? Color(white: 0.2) : (solo ? S.orange : S.green))
                            .frame(width: 7, height: 7).shadow(color: muted ? .clear : S.green.opacity(0.7), radius: 4)
                            .frame(width: 22, height: 44)
                    }.accessibilityLabel(muted ? "Unmute \(controller.channelName(pad))" : "Mute \(controller.channelName(pad))")
                }
            }
        }
        .padding(.trailing, 9)
        .frame(height: height)
        .onDrop(of: [RackSoundDrag.type, UTType.fileURL, UTType.audio], isTargeted: nil) { providers in
            // A drop anywhere in the rack creates an independent channel. Replacing a
            // channel's sound is explicit in its Sample menu and never consumes a drop.
            dropIntoRack(providers)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: MIDI out (multi-out)

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
            BBMenuItem.item("Multi-out: channel routing (1–16)", icon: "square.stack.3d.down.right") { controller.setMIDIOutLayout(multi: true) },
            BBMenuItem.item("All channels on MIDI channel 10 (GM drums)", icon: "10.circle") { controller.setMIDIOutLayout(multi: false) },
            .header("Channels"),
        ]
        for pad in channelSlots {
            items.append(.submenu("\(controller.channelName(pad))  ·  \(midiOutLabel(pad))  ·  \(MusicScale.noteName(controller.midiOutNotes[pad]))",
                                  midiOutChannelItems(pad)))
        }
        items.append(.header(controller.isPlugin ? "Plug-in: route the plug-in's MIDI output in your DAW" : "App: other apps see \"BreakBoss Out\" as a MIDI source"))
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

    /// Long-press menu on a channel: FL-style fills, clear, randomize.
    private func channelMenu(_ pad: Int) -> [BBMenuItem] {
        let step = PatternData.stepTicks
        let fills: [(String, Int32)] = [("Fill every step", step), ("Fill every 2 steps", step * 2), ("Fill every 4 steps (beat)", step * 4),
                                        ("Fill every 8 steps (1/2 bar)", step * 8), ("Fill every bar", PatternEdit.barTicks),
                                        ("Fill every 1/2 step (1/32)", step / 2)]
        var items: [BBMenuItem] = fills.map { f in
            BBMenuItem.item(f.0, icon: "square.grid.4x3.fill") { commit(PatternEdit.fill(pattern, pad: pad, every: f.1, velocity: lastVelocity, role: controller.channelRole(pad))) }
        }
        items.insert(.item("Channel controls", icon: "slider.horizontal.3") { selectedPad = pad }, at: 0)
        items.insert(.item("Piano roll", icon: "pianokeys") { pianoRollPad = pad }, at: 1)
        items.insert(.submenu("Sample", icon: "waveform", channelSampleItems(pad)), at: 2)
        items.insert(.item(controller.soloPads[pad] ? "Unsolo channel" : "Solo channel", icon: "headphones", checked: controller.soloPads[pad]) { controller.toggleSolo(pad) }, at: 3)
        if let index = channels.firstIndex(where: { $0.slot == pad }) {
            if index > 0 { items.append(.item("Move channel up", icon: "arrow.up") { controller.moveRackChannel(from: IndexSet(integer: index), to: index - 1) }) }
            if index + 1 < channels.count { items.append(.item("Move channel down", icon: "arrow.down") { controller.moveRackChannel(from: IndexSet(integer: index), to: index + 2) }) }
        }
        items.append(.item("Remove channel", icon: "minus.circle", destructive: true) { controller.removeRackChannel(slot: pad); selectedPad = nil })
        items.append(BBMenuItem.item("Randomize channel", icon: "dice") { controller.randomizeChannel(loop: loop, pad: pad) })
        items.append(BBMenuItem.item("Clear channel", icon: "trash", destructive: true) { commit(PatternEdit.clearChannel(pattern, pad: pad)) })
        return items
    }

    private func smallToggle(_ t: String, on: Bool, color: Color) -> some View {
        Text(t).font(.system(size: 12, weight: .semibold)).foregroundColor(on ? .black : S.text)
            .frame(width: compact ? 24 : 30, height: 28)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? color : S.button))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(S.border, lineWidth: 1))
    }

    // MARK: Grid drawing

    private func x(_ t: Int32, _ w: CGFloat) -> CGFloat { CGFloat(t - pageStart) / CGFloat(pageTicks) * w }
    private func tickAt(_ x: CGFloat, _ w: CGFloat) -> Int32 { pageStart + Int32((x / w * CGFloat(pageTicks)).rounded(.down)) }
    private func snapped(_ t: Int32) -> Int32 {
        let g = placeTicks
        return max(0, min((t / g) * g, max(pattern.lengthTicks, 1) - 1))
    }
    private func noteWidth(_ e: GrooveEvent, _ w: CGFloat) -> CGFloat {
        let step = w / CGFloat(pageTicks) * CGFloat(PatternData.stepTicks)
        if isBass(Int(e.pad)) && e.length > 0 { return max(step * 0.6, CGFloat(e.length) / CGFloat(pageTicks) * w - 2) }
        if e.length > 0 { return max(6, CGFloat(e.length) / CGFloat(pageTicks) * w - 2) }     // trimmed drum note
        return max(6, step - 4)
    }
    private func noteRect(_ e: GrooveEvent, w: CGFloat, rowH: CGFloat) -> CGRect {
        let h = min(rowH * 0.70, 36)
        return CGRect(x: x(e.tick, w) + 1, y: CGFloat(rowIndex(Int(e.pad)) ?? -1) * rowH + (rowH - h) / 2, width: noteWidth(e, w), height: h)
    }
    private func visible(_ e: GrooveEvent) -> Bool { e.tick >= pageStart && e.tick < pageStart + pageTicks }

    private func grid(width w: CGFloat, rowH: CGFloat) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.065)))
            // FL-style step switches. Every group of four changes shade; at two bars the
            // rack shows 32 switches without creating thousands of individual SwiftUI views.
            let unit = max(1, zoomLevel > 0 && snapTicks > 0 ? snapTicks : PatternData.stepTicks)
            let columns = max(1, Int(pageTicks / unit))
            let cellW = size.width / CGFloat(columns)
            for row in channels.indices {
                for step in 0..<columns {
                    let absoluteStep = Int(pageStart / unit) + step
                    let light = (absoluteStep / 4).isMultiple(of: 2)
                    let rect = CGRect(x: CGFloat(step) * cellW + 2,
                                      y: CGFloat(row) * rowH + 8,
                                      width: max(3, cellW - 4), height: rowH - 16)
                    let shape = Path(roundedRect: rect, cornerRadius: 2)
                    ctx.fill(shape, with: .linearGradient(Gradient(colors: light
                             ? [Color(white: 0.67), Color(white: 0.43)]
                             : [Color(white: 0.32), Color(white: 0.22)]),
                             startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
                    ctx.stroke(shape, with: .color(.black.opacity(0.8)), lineWidth: 0.7)
                    let notch = CGRect(x: rect.minX + 2, y: rect.minY + 6, width: max(1, rect.width - 4), height: 3)
                    ctx.fill(Path(notch), with: .color(.black.opacity(0.64)))
                    ctx.fill(Path(CGRect(x: rect.minX + 1, y: rect.minY + 1, width: max(1, rect.width - 2), height: 1)), with: .color(.white.opacity(0.18)))
                }
            }
            // Past the end of a short pattern.
            let endX = x(max(pattern.lengthTicks, 1), size.width)
            if endX < size.width {
                ctx.fill(Path(CGRect(x: endX, y: 0, width: size.width - endX, height: size.height)), with: .color(Color.black.opacity(0.45)))
            }
            for e in pattern.events where visible(e) && rowIndex(Int(e.pad)) != nil {
                let r = noteRect(e, w: size.width, rowH: rowH)
                let sel = selection.contains(NoteKey(e))
                let base = sel ? Color.white : noteColor
                let shade = 0.55 + 0.45 * Double(e.velocity)
                ctx.fill(Path(roundedRect: r.insetBy(dx: -1, dy: -1), cornerRadius: 3), with: .color(base.opacity(sel ? 0.3 : 0.12)))
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .linearGradient(Gradient(colors: [base.opacity(shade), base.opacity(shade * 0.65)]), startPoint: CGPoint(x: 0, y: r.minY), endPoint: CGPoint(x: 0, y: r.maxY)))
                ctx.fill(Path(CGRect(x: r.minX + 2, y: r.minY + 6, width: max(1, r.width - 4), height: 3)), with: .color(.black.opacity(0.5)))
                if sel && tool == .select {      // trim handle: drag the right edge
                    ctx.fill(Path(roundedRect: CGRect(x: r.maxX - 4, y: r.minY + 3, width: 3, height: r.height - 6), cornerRadius: 1.5),
                             with: .color(Color.black.opacity(0.55)))
                }
                if e.semis != 0 && r.width > 14 {
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
            _ = tick   // redraw the playhead with the ticker
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in if !pinching { gridChanged(g, w: w, rowH: rowH) } }
            .onEnded { g in if pinching { drag = .none; work = nil } else { gridEnded(g, w: w, rowH: rowH) } })
        .simultaneousGesture(pinch)
    }

    // MARK: Grid gestures

    private func noteAt(_ p: CGPoint, w: CGFloat, rowH: CGFloat) -> GrooveEvent? {
        guard let slot = slotAt(Int(p.y / rowH)) else { return nil }
        return pattern.events.last { e in
            Int(e.pad) == slot && visible(e) && noteRect(e, w: w, rowH: rowH).insetBy(dx: -6, dy: -6).contains(p)
        }
    }

    private func gridChanged(_ g: DragGesture.Value, w: CGFloat, rowH: CGFloat) {
        if case .none = drag {
            let start = g.startLocation
            guard let startRow = slotAt(Int(start.y / rowH)) else { return }
            let hit = noteAt(start, w: w, rowH: rowH)
            switch tool {
            case .draw:
                if let hit {
                    let r = noteRect(hit, w: w, rowH: rowH)
                    if isBass(Int(hit.pad)) && start.x > r.maxX - 14 {
                        drag = .resize(key: NoteKey(hit), origin: pattern)
                    } else {
                        drag = .tapOnNote(key: NoteKey(hit))
                    }
                    lastVelocity = hit.velocity
                } else if isBass(startRow) {
                    drag = .long808(pad: startRow, start: snapped(tickAt(start.x, w)))
                } else {
                    let t = snapped(tickAt(start.x, w))
                    pushUndo(pattern)
                    // Drawing is silent: a new note sounds only when the playhead reaches it.
                    work = PatternEdit.addNote(pattern, pad: startRow, tick: t, velocity: lastVelocity, role: controller.channelRole(startRow))
                    drag = .paint(pad: startRow, lastCell: Int(t / placeTicks))
                }
            case .select:
                if let hit, start.x > noteRect(hit, w: w, rowH: rowH).maxX - 12 {
                    // The right edge: trim (longer / shorter), the whole selection together.
                    if !selection.contains(NoteKey(hit)) { selection = [NoteKey(hit)] }
                    drag = .trim(keys: selection, origin: pattern, startTick: tickAt(start.x, w))
                } else if let hit, selection.contains(NoteKey(hit)) {
                    drag = .move(keys: selection, origin: pattern, startTick: tickAt(start.x, w), followSelection: true)
                } else if let hit {
                    selection = [NoteKey(hit)]
                    drag = .move(keys: selection, origin: pattern, startTick: tickAt(start.x, w), followSelection: true)
                } else {
                    drag = .marquee(start: start, current: start)
                }
            case .erase:
                pushUndo(pattern)
                drag = .erase
            }
        }
        switch drag {
        case .tapOnNote(let key):
            // Draw tool: a drag that starts on a note moves it (and the selection with it).
            if hypot(g.translation.width, g.translation.height) > 8 {
                let inSelection = selection.contains(key)
                drag = .move(keys: inSelection ? selection : [key], origin: pattern,
                             startTick: tickAt(g.startLocation.x, w), followSelection: inSelection)
                gridChanged(g, w: w, rowH: rowH)
            }
        case .paint(let pad, let lastCell):
            let t = snapped(tickAt(g.location.x, w))
            let cell = Int(t / placeTicks)
            if cell != lastCell && t >= pageStart && t < pageStart + pageTicks {
                work = PatternEdit.addNote(pattern, pad: pad, tick: t, velocity: lastVelocity, role: controller.channelRole(pad))
                drag = .paint(pad: pad, lastCell: cell)
            }
        case .long808:
            break
        case .move(let keys, let origin, let startTick, let followSelection):
            let raw = tickAt(g.location.x, w) - startTick
            let d = snapTicks > 0 ? (raw / snapTicks) * snapTicks : raw
            let (moved, newKeys) = PatternEdit.move(origin, keys, by: d)
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
            let (resized, _) = PatternEdit.resize(origin, key, length: max(placeTicks, end - e.tick), role: controller.channelRole(Int(e.pad)))
            work = resized
        case .marquee(let a, _):
            drag = .marquee(start: a, current: g.location)
        case .erase:
            if let hit = noteAt(g.location, w: w, rowH: rowH) {
                work = PatternEdit.remove(pattern, [NoteKey(hit)])
                selection.remove(NoteKey(hit))
            }
        case .none:
            break
        }
    }

    private func gridEnded(_ g: DragGesture.Value, w: CGFloat, rowH: CGFloat) {
        defer { drag = .none }
        switch drag {
        case .tapOnNote(let key):
            // Draw tool tap on a note deletes it (FL's right-click).
            commit(PatternEdit.remove(pattern, [key]))
            selection.remove(key)
        case .long808(let pad, let start):
            let end = snapped(tickAt(g.location.x, w))
            let length = max(placeTicks, (end > start ? end - start : 0) + placeTicks)
            let len = abs(g.translation.width) < 6 ? last808Length : length
            last808Length = len
            commit(PatternEdit.addNote(pattern, pad: pad, tick: start, length: len, velocity: lastVelocity, role: controller.channelRole(pad)))
        case .paint, .erase:
            if let p = work { work = nil; controller.setLoop(loop, p) }   // the undo point was pushed when the finger went down
            else { _ = undoStack.popLast() }                             // nothing changed
        case .move(_, _, _, _), .resize(_, _), .trim(_, _, _):
            if let p = work { commit(p) } else { work = nil }
        case .marquee(let a, let b):
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            if rect.width < 4 && rect.height < 4 {
                selection = []
            } else {
                selection = Set(pattern.events.filter { visible($0) && rect.intersects(noteRect($0, w: w, rowH: rowH)) }.map(NoteKey.init))
            }
        case .none:
            break
        }
    }

    // MARK: Velocity / pitch lane

    private var laneChip: some View {
        chip(lane.rawValue, width: compact ? 110 : 140)
            .bbMenu(title: "Lane", width: 200) { Lane.allCases.map { l in BBMenuItem.item(l.rawValue, checked: lane == l) { lane = l } } }
    }

    private var diceButton: some View {
        // Velocity dice: new velocities only (the selected notes, or the selected channel, or every note).
        Button {
            commit(PatternEdit.randomizeVelocity(pattern, pad: selectedPad, keys: selection, seed: UInt64.random(in: 1...UInt64.max)))
        } label: { iconBox("dice.fill") }
    }

    private var laneHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Randomize the whole pattern sits beside the lane picker (moved here from the footer);
            // on a narrow iPhone strip it drops under it.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { laneChip; diceButton }
                VStack(alignment: .leading, spacing: 6) { laneChip; diceButton }
            }
            if let pad = selectedPad {
                Text(controller.channelName(pad)).font(.system(size: 10, design: .monospaced)).foregroundColor(ink)
            }
            Spacer()
        }
        .padding(8)
    }

    private var lanePitchTop: Float { selectedPad.map { isBass($0) ? 24 : 12 } ?? 24 }

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
                if bar || zoomLevel > 0 {
                    ctx.fill(Path(CGRect(x: bx, y: 0, width: bar ? 1.5 : 1, height: size.height)), with: .color(bar ? S.beatLine : S.stepLine))
                }
                lt += PatternData.ppq
            }
            // The scale sits on the lane's own lines: 127 on the top line (full), 64 in the middle, 0 at the bottom.
            let marks: [(String, CGFloat, UnitPoint)] = lane == .velocity
                ? [("127", 1, .topTrailing), ("64", 0.5, .trailing), ("0", 0, .bottomTrailing)]
                : [("+\(Int(lanePitchTop))", 1, .topTrailing), ("0", CGFloat(12 / (lanePitchTop + 12)), .trailing), ("-12", 0, .bottomTrailing)]
            for m in marks {
                let y = 4 + (1 - m.1) * (size.height - 8)
                ctx.draw(Text(m.0).font(.system(size: 10, design: .monospaced)).foregroundColor(Color.white.opacity(0.55)),
                         at: CGPoint(x: size.width - 4, y: m.1 == 1 ? y + 2 : (m.1 == 0 ? y - 2 : y)), anchor: m.2)
            }
            for e in pattern.events where visible(e) && (selectedPad == nil || Int(e.pad) == selectedPad) {
                let sel = selection.contains(NoteKey(e))
                let v: CGFloat
                if lane == .velocity { v = CGFloat(e.velocity) } else { v = CGFloat((e.semis.clamped(-12, lanePitchTop) + 12) / (lanePitchTop + 12)) }
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

    /// FL event editing: drag over the bars to set them (only the selection, when there is one).
    private func laneChanged(_ g: DragGesture.Value, w: CGFloat, h: CGFloat) {
        if laneOrigin == nil { laneOrigin = pattern; pushUndo(pattern) }
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
            let raw = (v * (lanePitchTop + 12) - 12).rounded()
            var edited = pattern
            var newKeys = Set<NoteKey>()
            let grouped = Dictionary(grouping: keys, by: { Int($0.pad) })
            for (slot, channelKeys) in grouped {
                let semis = controller.scaleSnapped(raw, pad: slot)
                let result = PatternEdit.setPitch(edited, Set(channelKeys), semis, role: controller.channelRole(slot))
                edited = result.0
                newKeys.formUnion(result.1)
            }
            work = edited
            if !selection.isEmpty { selection = selection.subtracting(keys).union(newKeys) }
        }
    }

    // MARK: Footer

    private var orderedKits: [KitDefinition] { SoundMode.allCases.flatMap { KitLibrary.kits(for: $0) } + KitLibrary.genres }

    private var footer: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Button { showGeneral = true } label: { iconBox("square.grid.3x3.fill") }.accessibilityLabel("Sequencer general controls")
                    Button { showLane.toggle() } label: { iconBox(showLane ? "slider.vertical.3" : "square") }.accessibilityLabel("Show or hide event lane")
                }
                HStack(spacing: 8) {
                    Text("\(channels.count)").font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(S.red).frame(width: 38, height: 38)
                        .overlay(Circle().stroke(S.red, lineWidth: 2))
                    Text("Drum Track").font(.system(size: 10, weight: .medium)).foregroundColor(S.text)
                }.padding(.horizontal, 8).frame(height: 44).background(Capsule().fill(Color(white: 0.12)))
                divider
                VStack(alignment: .leading, spacing: 2) {
                    Text("PATTERN").font(.system(size: 8, weight: .semibold)).foregroundColor(inkDim)
                    HStack(spacing: 3) {
                        Button { loop = (loop - 1 + controller.loops.count) % max(1, controller.loops.count) } label: { iconBox("chevron.left") }
                        Button { loop = (loop + 1) % max(1, controller.loops.count) } label: { iconBox("chevron.right") }
                        patternMenu
                    }
                }
                divider
                VStack(alignment: .leading, spacing: 2) {
                    Text("KIT").font(.system(size: 8, weight: .semibold)).foregroundColor(inkDim)
                    HStack(spacing: 3) {
                        Button { cycleKit(-1) } label: { iconBox("chevron.left") }
                        Button { cycleKit(1) } label: { iconBox("chevron.right") }
                        chip(controller.state.kitName, width: 170).bbMenu(title: "Kits · drum sounds", width: 320) { kitItems() }
                    }
                }
                Button { duplicate() } label: { iconBox("plus.square.on.square") }.accessibilityLabel("Duplicate selected notes or pattern")
                Button { clear() } label: { iconBox("trash") }.accessibilityLabel("Clear selected notes or pattern")
                if let url = exportURL {
                    ShareLink(item: url) { iconBox("doc.badge.arrow.up") }
                        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                        .accessibilityLabel("Share or drag MIDI sequence")
                }
                Button { showExport = true } label: { iconBox("square.and.arrow.up") }.accessibilityLabel("Export audio, stems and MIDI")
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .frame(height: 75)
        .overlay(Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1), alignment: .top)
    }

    private func kitItems() -> [BBMenuItem] {
        SoundMode.allCases.map { mode in
            .submenu("\(mode.title) kits", icon: "square.grid.3x3", KitLibrary.kits(for: mode).map { definition in
                .item(definition.name, checked: definition.id == controller.state.kitID) { controller.selectKit(definition) }
            })
        } + [.submenu("Genre kits", icon: "music.note.list", KitLibrary.genreGroups.map { group in
            .submenu(group.genre, group.kits.map { definition in
                .item(definition.name, checked: definition.id == controller.state.kitID) { controller.selectKit(definition) }
            })
        })]
    }

    private func cycleKit(_ step: Int) {
        let kits = orderedKits
        guard !kits.isEmpty else { return }
        let i = kits.firstIndex { $0.id == controller.state.kitID } ?? 0
        controller.selectKit(kits[(i + step + kits.count) % kits.count])
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
        let name = (controller.loops.indices.contains(loop) ? controller.loops[loop].name : "PATTERN")
            .replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BreakBoss \(controller.state.kitName) \(name).mid")
        do {
            try MIDIFile.write(stored, tempo: controller.liveTempo, bounce: controller.value(.bounce), bars: bars, to: url, roles: (0..<RackLimits.maxChannels).map { controller.channelRole($0) })
            return url
        } catch {
            return nil
        }
    }

    // MARK: Undo, follow, samples

    private func commit(_ p: PatternData) {
        work = nil
        guard p != stored else { return }
        pushUndo(stored)
        controller.setLoop(loop, p)
    }

    private func pushUndo(_ value: PatternData) {
        undoStack.append(value)
        if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
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
        let target = min(pages - 1, Int(t) / Int(pageTicks))
        if target != page { page = target }
    }

    private func addSound(_ sound: LibrarySound) {
        _ = controller.appendRackSound(sound)
    }

    private func dropIntoRack(_ providers: [NSItemProvider]) -> Bool {
        guard !rackFull else {
            controller.notice = "The rack holds 12 sounds. Remove a channel or start a new empty rack to add another sound."
            return false
        }
        if providers.contains(where: { $0.hasItemConformingToTypeIdentifier(RackSoundDrag.type.identifier) }) {
            return RackSoundDrag.load(providers) { id in
                guard let id, let sound = library.sound(id: id) else { return }
                addSound(sound)
            }
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                let url: URL?
                if let direct = item as? URL { url = direct }
                else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = nil }
                guard let url, url.isFileURL else {
                    DispatchQueue.main.async { controller.notice = error?.localizedDescription ?? "The dropped file could not be opened." }
                    return
                }
                DispatchQueue.main.async { _ = controller.appendRackImport(url) }
            }
            return true
        }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier) }) else { return false }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, error in
            guard let url else {
                DispatchQueue.main.async { controller.notice = error?.localizedDescription ?? "The dropped audio could not be opened." }
                return
            }
            // The provider's temporary URL expires when this callback returns. Copy it into
            // the app's library here, then let the controller decode on its sample queue.
            do {
                let relative = try SampleLoader.copyIntoSamples(url)
                let local = SampleLoader.urlInSamples(relative)
                DispatchQueue.main.async { _ = controller.appendRackImport(local); library.refresh() }
            } catch { DispatchQueue.main.async { controller.notice = error.localizedDescription } }
        }
        return true
    }

    // MARK: Small pieces

    private func box(lit: Bool, color: Color = S.green) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: lit ? [color.opacity(0.17), Color(white: 0.045)] : [Color(white: 0.18), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(lit ? color.opacity(0.9) : S.border, lineWidth: lit ? 1.5 : 1))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }

    private func iconBox(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 17, weight: .medium)).foregroundColor(S.text)
            .frame(width: 44, height: 44).background(box(lit: false))
    }

    private func chip(_ text: String, width: CGFloat) -> some View {
        HStack {
            Text(text).font(.system(size: 11, weight: .medium)).foregroundColor(S.text).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(S.text)
        }
        .padding(.horizontal, 12).frame(width: width, height: 44).background(box(lit: false))
    }

    /// SNAP TO SCALE menu (FL Studio's scales): turns snap on/off, picks the key and scale, and can fit
    /// the notes already drawn on this channel to the scale.
    private func scaleItems(_ pad: Int) -> [BBMenuItem] {
        var items: [BBMenuItem] = [
            BBMenuItem.item(controller.snapToScale ? "Snap to scale: ON" : "Snap to scale: OFF", icon: "tuningfork",
                            checked: controller.snapToScale) { controller.setScale(snap: !controller.snapToScale) },
            BBMenuItem.submenu("Key: \(MusicScale.noteNames[controller.scaleRoot])", icon: "music.note",
                MusicScale.noteNames.enumerated().map { i, n in BBMenuItem.item(n, checked: controller.scaleRoot == i) { controller.setScale(root: i) } }),
            BBMenuItem.submenu("Scale: \(controller.scale.name)", icon: "music.note.list",
                MusicScale.all.map { sc in BBMenuItem.item(sc.name, checked: controller.scale.name == sc.name) { controller.setScale(name: sc.name) } })
        ]
        items.append(.header("Notes already drawn"))
        items.append(BBMenuItem.item("Fit this channel's notes to the scale", icon: "wand.and.stars") {
            let base = controller.baseNote(pad: pad)
            let top: Float = isBass(pad) ? 24 : 12
            var p = pattern
            for i in p.events.indices where Int(p.events[i].pad) == pad {
                let n = controller.scale.snap(base + Int(p.events[i].semis.rounded()), root: controller.scaleRoot)
                p.events[i].semis = Float(n - base).clamped(-12, top)
            }
            commit(p)
        })
        return items
    }

    private func labelBox(_ icon: String?, _ title: String?, lit: Bool = false, enabled: Bool = true) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 12, weight: .medium)) }
            if let title { Text(title).font(.system(size: 10, weight: .medium)) }
        }
        .foregroundColor(lit ? S.green : (enabled ? S.text : S.dim))
        .padding(.horizontal, 9).frame(height: 44).background(box(lit: lit))
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
                            Text("\(b)").font(.system(size: 10, weight: .medium))
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

/// The SWING / HUMANIZE knob: drag up or right to turn it up.
struct DrumRollKnob: View {
    let value: Float
    let change: (Float, Bool) -> Void
    @State private var start: Float?

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
            Circle().stroke(Color.black, lineWidth: 2)
            Rectangle().fill(Color.white.opacity(0.9)).frame(width: 2.5, height: 10)
                .offset(y: -9)
                .rotationEffect(.degrees(KnobControl.angle(value)))
        }
        .frame(width: 36, height: 36)
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

/// Record from the mic straight onto one drum roll channel (standalone app).
struct ChannelRecordSheet: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = PadRecorder()

    var body: some View {
        NavigationView {
            VStack(spacing: 22) {
                Text(controller.channelName(pad)).font(.system(.title2, design: .monospaced))
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

extension Pad {
    /// Traditional role names, shared with the channel piano roll and MIDI editor.
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
