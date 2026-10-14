// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drum roll (the piano-keys button next to EXPORT)
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

    enum Tool { case draw, select, erase }
    enum Lane: String, CaseIterable { case velocity = "VELOCITY", pitch = "PITCH" }

    @State private var tool: Tool = .draw
    @State private var snap: Int32 = PatternData.stepTicks   // grid in ticks (0 = none)
    @State private var selectedPad: Int?                      // channel picked for its own edits
    @State private var lane: Lane = .velocity
    @State private var follow = true
    @State private var page = 0
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
    @State private var recordPad: Int?
    @State private var pianoRollPad: Int?
    @State private var exportURL: URL?
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    enum GridDrag {
        case none
        case paint(pad: Int, lastCell: Int)
        case long808(start: Int32)
        case move(keys: Set<NoteKey>, origin: PatternData, startTick: Int32, followSelection: Bool)
        case resize(key: NoteKey, origin: PatternData)
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
    private var barsPerPage: Int { min(compact ? 2 : 4, bars) }
    private var pages: Int { max(1, (bars + barsPerPage - 1) / barsPerPage) }
    private var pageStart: Int32 { Int32(min(page, pages - 1) * barsPerPage) * PatternEdit.barTicks }
    private var pageTicks: Int32 { Int32(barsPerPage) * PatternEdit.barTicks }
    /// Grid step in ticks for the SNAP setting (0 = free, placed on 1/64ths).
    private var snapTicks: Int32 { snap }

    /// SNAP values, FL Studio style (96 ticks per beat, a step is a 16th).
    static let snapChoices: [(section: String, items: [(String, Int32)])] = [
        ("Straight", [("1/2 (half note)", 192), ("Beat (1/4)", 96), ("1/2 Beat (1/8)", 48), ("1/4 Beat (1/16)", 24),
                      ("Step (1/16)", 24), ("1/2 Step (1/32)", 12), ("1/4 Step (1/64)", 6),
                      ("1/16", 24), ("1/32", 12), ("1/64", 6)]),
        ("Triplet", [("1/3 Beat (1/8 triplet)", 32), ("1/3 Step (1/16 triplet)", 8), ("1/6 Beat", 16), ("1/6 Step", 4)]),
        ("Off", [("None (free)", 0)])
    ]
    private var snapLabel: String {
        for group in Self.snapChoices { if let hit = group.items.first(where: { $0.1 == snap }) { return hit.0.components(separatedBy: " (").first ?? hit.0 } }
        return "\(snap) TICKS"
    }
    private var placeTicks: Int32 { snapTicks > 0 ? snapTicks : 6 }
    private var isThisPlaying: Bool { controller.isPlaying && Int(controller.meters.status[1]) == loop }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                wood
                VStack(spacing: 0) {
                    header
                    toolbar
                    if let pad = selectedPad { channelStrip(pad) }
                    editor
                    footer
                }
                .background(S.toolbar)
                wood
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
        .onChange(of: loop) { _ in page = 0; selection = []; undoStack = []; redoStack = [] }
        .onDisappear { if controller.recording { controller.setRecording(false) } }
        .task(id: stored) { exportURL = writeMIDI() }
        .sheet(isPresented: $showMenu) { MenuView(controller: controller) }
        .sheet(item: Binding(get: { pianoRollPad.map { PadID(pad: $0) } }, set: { pianoRollPad = $0?.pad })) { target in
            PianoRollView(controller: controller, loop: loop, pad: target.pad)
        }
        .sheet(item: Binding(get: { recordPad.map { PadID(pad: $0) } }, set: { recordPad = $0?.pad })) { target in
            ChannelRecordSheet(controller: controller, pad: target.pad)
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

    private var wood: some View {
        Image("DrumRollWood").resizable().frame(width: compact ? 8 : 14).ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: compact ? 6 : 10) {
            Button { showMenu = true } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 20, weight: .regular)).foregroundColor(S.text)
                    .frame(width: 36, height: 36)
            }
            if !compact {
                Image("DrumRollLogo").resizable().scaledToFit().frame(height: 26)
                Text("D R U M   R O L L").font(.system(size: 13, weight: .medium)).foregroundColor(S.text).lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            transport
            Spacer(minLength: 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    bpmMenu
                    barsMenu
                    patternMenu
                    settingsMenu
                }
            }
            .frame(maxWidth: compact ? 170 : 470)
            Button { dismiss() } label: { iconBox("xmark") }
        }
        .padding(.horizontal, 10)
        .frame(height: compact ? 56 : 70)
        .background(S.header)
    }

    private var transport: some View {
        HStack(spacing: 6) {
            Button { controller.stopPlayback() } label: {
                RoundedRectangle(cornerRadius: 3).fill(S.text).frame(width: 18, height: 18).frame(width: 46, height: 40)
                    .background(box(lit: false))
            }
            Button { controller.playPattern(loop) } label: {
                Image(systemName: "play.fill").font(.system(size: 22)).foregroundColor(S.green)
                    .frame(width: 46, height: 40).background(box(lit: isThisPlaying))
            }
            Button { controller.setMetronome(!controller.metronome) } label: {
                Image(systemName: "metronome.fill").font(.system(size: 18)).foregroundColor(controller.metronome ? S.green : S.text)
                    .frame(width: 46, height: 40).background(box(lit: controller.metronome))
            }
            Button {
                let on = !controller.recording
                controller.setRecording(on)
                if on && !isThisPlaying { controller.playPattern(loop) }
            } label: {
                Circle().fill(controller.recording ? S.red : S.red.opacity(0.75)).frame(width: 20, height: 20)
                    .shadow(color: controller.recording ? S.red : .clear, radius: 6)
                    .frame(width: 46, height: 40).background(box(lit: controller.recording, color: S.red))
            }
        }
    }

    private var bpmMenu: some View {
        chip("\(Int(controller.liveTempo.rounded())) BPM", width: 112)
            .bbPanel(title: "Tempo", width: 340) { TempoPanel(controller: controller) }
    }

    private var barsMenu: some View {
        chip("\(bars) BAR\(bars == 1 ? "" : "S")", width: 104)
            .bbMenu(title: "Pattern length") {
                [4, 8, 16].map { b in BBMenuItem.item("\(b) BARS", checked: bars == b) { commit(PatternEdit.setLength(pattern, bars: b)) } }
            }
    }

    private var patternMenu: some View {
        chip(controller.loops.indices.contains(loop) ? controller.loops[loop].name : "PATTERN", width: 132)
            .bbMenu(title: "Loop") {
                controller.loops.indices.map { i in BBMenuItem.item("\(i + 1)  \(controller.loops[i].name)", checked: i == loop) { loop = i } }
            }
    }

    private var settingsMenu: some View {
        iconBox("gearshape.fill").bbMenu(title: "Drum roll", width: 320) {
            [
                .item("Follow playhead", icon: "arrow.right.to.line", checked: follow) { follow.toggle() },
                .item("Metronome", icon: "metronome", checked: controller.metronome) { controller.setMetronome(!controller.metronome) },
                .submenu("MIDI out (external gear)", icon: "cable.connector", midiOutItems()),
                .item("Copy these bars to the next ones", icon: "doc.on.doc") {
                    commit(PatternEdit.copyNext(pattern, fromBar: Int(pageStart / PatternEdit.barTicks), bars: barsPerPage))
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

    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                toolButton(.draw, "pencil", "DRAW")
                toolButton(.select, "rectangle.dashed", "SELECT")
                toolButton(.erase, "eraser", "ERASE")
                divider
                Button { undo() } label: { labelBox("arrow.uturn.backward", "UNDO", enabled: !undoStack.isEmpty) }
                    .disabled(undoStack.isEmpty)
                Button { redo() } label: { labelBox("arrow.uturn.forward", "REDO", enabled: !redoStack.isEmpty) }
                    .disabled(redoStack.isEmpty)
                divider
                chip("SNAP  \(snapLabel)", width: 190)
                    .bbMenu(title: "Snap", width: 300) {
                        Self.snapChoices.flatMap { group -> [BBMenuItem] in
                            [.header(group.section)] + group.items.map { item in BBMenuItem.item(item.0, checked: item.1 == snap && item.0.hasPrefix(snapLabel)) { snap = item.1 } }
                        }
                    }
                divider
                knobBlock(title: "SWING", value: controller.value(.bounce),
                          text: controller.value(.bounce) < 0.01 ? "OFF" : "\(Int(50 + controller.value(.bounce) * 22))%",
                          menu: AnyView(swingMenu)) { v, ended in
                    if swingStart == nil { swingStart = controller.value(.bounce) }
                    controller.set(.bounce, v)
                    if ended { swingStart = nil }
                }
                knobBlock(title: "HUMANIZE", value: pattern.humanize ?? 0, text: nil, menu: nil) { v, ended in
                    if humanizeStart == nil { humanizeStart = pattern.humanize ?? 0; undoStack.append(pattern); redoStack = [] }
                    var p = pattern
                    p.humanize = v < 0.01 ? nil : v
                    work = p
                    if ended {
                        humanizeStart = nil
                        work = nil
                        controller.setLoop(loop, p)
                    }
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: compact ? 52 : 64)
        .background(S.toolbar)
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
                .font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(S.text).fixedSize()
            if let menu { menu }
            DrumRollKnob(value: value, change: change)
        }
        .padding(.horizontal, 12).frame(height: 44)
        .background(box(lit: false))
    }

    // MARK: Editor (channels, ruler, grid, lane)

    private var editor: some View {
        GeometryReader { geo in
            let stripW: CGFloat = compact ? 132 : 228
            let rulerH: CGFloat = 34
            let laneH: CGFloat = max(90, min(150, geo.size.height * 0.22))
            let rowH = max(30, (geo.size.height - rulerH - laneH - 8) / CGFloat(Pad.count))
            let gridW = max(100, geo.size.width - stripW)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    pageControl.frame(width: stripW, height: rulerH).background(S.channel)
                    ruler(width: gridW).frame(width: gridW, height: rulerH)
                }
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(0..<Pad.count, id: \.self) { pad in channelRow(pad, height: rowH) }
                    }
                    .frame(width: stripW)
                    grid(width: gridW, rowH: rowH)
                        .frame(width: gridW, height: rowH * CGFloat(Pad.count))
                }
                Rectangle().fill(Color.black.opacity(0.6)).frame(height: 8)
                HStack(spacing: 0) {
                    laneHeader.frame(width: stripW, height: laneH)
                    laneView(width: gridW, height: laneH).frame(width: gridW, height: laneH)
                }
            }
        }
    }

    /// The selected channel's own controls: its sound, level, pan, tune, decay, filter,
    /// reverse, piano roll and dice. Nothing here touches the other channels.
    private func channelStrip(_ pad: Int) -> some View {
        let ps = controller.state.pads[pad]
        func set(_ change: (inout PadSettings) -> Void) { var v = controller.state.pads[pad]; change(&v); controller.setPadSettings(pad, v) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Pad(rawValue: pad)?.channelTitle ?? "").font(.system(size: 14, weight: .semibold)).foregroundColor(S.green)
                    Text(controller.padName(pad).uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(S.dim).lineLimit(1)
                }
                .frame(width: 120, alignment: .leading)
                labelBox("waveform", compact ? nil : "SAMPLE")
                    .bbMenu(title: controller.padName(pad), width: 320) { channelSampleItems(pad) }
                Button { pianoRollPad = pad } label: { labelBox("pianokeys", compact ? nil : "PIANO ROLL") }
                Button { controller.randomizeChannel(loop: loop, pad: pad) } label: { labelBox("dice", nil) }
                labelBox("cable.connector", midiOutLabel(pad), lit: controller.midiOutOn && controller.midiOutChannels[pad] >= 0)
                    .bbMenu(title: "MIDI out · \(Pad(rawValue: pad)?.channelTitle ?? "")", width: 240) { midiOutChannelItems(pad) }
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
        var items: [BBMenuItem] = [.item("Load a sample from Files…", icon: "folder") { importPad = pad }]
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

    private var pageControl: some View {
        HStack(spacing: 6) {
            Button { page = max(0, page - 1); follow = false } label: {
                Image(systemName: "chevron.left").foregroundColor(page > 0 ? S.text : S.dim)
            }.disabled(page == 0)
            Text(barsPerPage == 1 ? "BAR \(page * barsPerPage + 1)" : "BARS \(page * barsPerPage + 1)–\(min(bars, (page + 1) * barsPerPage))")
                .font(.system(size: 11, design: .monospaced)).foregroundColor(S.dim).lineLimit(1)
            Button { page = min(pages - 1, page + 1); follow = false } label: {
                Image(systemName: "chevron.right").foregroundColor(page < pages - 1 ? S.text : S.dim)
            }.disabled(page >= pages - 1)
        }
    }

    private func ruler(width: CGFloat) -> some View {
        Canvas { ctx, size in
            let firstBar = Int(pageStart / PatternEdit.barTicks)
            let perBar = size.width / CGFloat(barsPerPage)
            for b in 0..<barsPerPage {
                let x = CGFloat(b) * perBar
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1.5, height: size.height)), with: .color(S.barLine))
                ctx.draw(Text("\(firstBar + b + 1)").font(.system(size: 13, weight: .medium)).foregroundColor(S.text),
                         at: CGPoint(x: x + 10, y: 11))
                for s in 1..<16 {
                    let sx = x + perBar * CGFloat(s) / 16
                    let h: CGFloat = s % 4 == 0 ? 12 : 6
                    ctx.fill(Path(CGRect(x: sx, y: size.height - h, width: 1, height: h)), with: .color(S.dim.opacity(0.7)))
                }
            }
            ctx.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(S.border))
        }
        .background(S.channel)
    }

    private func channelRow(_ pad: Int, height: CGFloat) -> some View {
        let muted = controller.mutedPads[pad], solo = controller.soloPads[pad]
        let custom = controller.state.pads[pad].sampleFile != nil
        return HStack(spacing: compact ? 4 : 8) {
            Button { controller.auditionPad(pad, velocity: lastVelocity) } label: {
                Image(systemName: "play.fill").font(.system(size: 13)).foregroundColor(S.text)
                    .frame(width: 30, height: 28).background(box(lit: false))
            }
            // Tap selects the channel; long-press (or right-click) opens its fill menu.
            VStack(alignment: .leading, spacing: 1) {
                Text(Pad(rawValue: pad)?.channelTitle ?? "PAD \(pad + 1)")
                    .font(.system(size: compact ? 11 : 14, weight: .medium))
                    .foregroundColor(selectedPad == pad ? S.green : (muted ? S.dim : S.text)).lineLimit(1)
                if !compact && height > 40 {
                    Text(controller.padName(pad).uppercased())
                        .font(.system(size: 9, design: .monospaced)).foregroundColor(custom ? S.green : S.dim).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .bbLongPressMenu(title: Pad(rawValue: pad)?.channelTitle ?? "Channel", width: 260,
                             tap: { selectedPad = selectedPad == pad ? nil : pad }) { channelMenu(pad) }
            Button { controller.randomizeChannel(loop: loop, pad: pad) } label: {
                Image(systemName: "dice").font(.system(size: 12)).foregroundColor(S.text)
                    .frame(width: compact ? 24 : 28, height: 28).background(box(lit: false))
            }
            Button { controller.toggleMute(pad) } label: { smallToggle("M", on: muted, color: S.orange) }
            Button { controller.toggleSolo(pad) } label: { smallToggle("S", on: solo, color: S.green) }
        }
        .padding(.horizontal, compact ? 4 : 8)
        .frame(height: height)
        .background(selectedPad == pad ? S.greenDark : (pad % 2 == 0 ? S.channel : S.channel.opacity(0.85)))
        .overlay(Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1), alignment: .bottom)
        .onDrop(of: [UTType.fileURL, UTType.audio], isTargeted: nil) { providers in dropSample(providers, pad: pad) }
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
            BBMenuItem.item("Multi-out: each channel on its own MIDI channel (1–12)", icon: "square.stack.3d.down.right") { controller.setMIDIOutLayout(multi: true) },
            BBMenuItem.item("All channels on MIDI channel 10 (GM drums)", icon: "10.circle") { controller.setMIDIOutLayout(multi: false) },
            .header("Channels"),
        ]
        for pad in 0..<Pad.count {
            items.append(.submenu("\(Pad(rawValue: pad)?.channelTitle ?? "PAD \(pad + 1)")  ·  \(midiOutLabel(pad))  ·  \(MusicScale.noteName(controller.midiOutNotes[pad]))",
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
        let fills: [(String, Int32)] = [("Fill every bar", PatternEdit.barTicks), ("Fill every 1/2 bar", PatternEdit.barTicks / 2),
                                        ("Fill every 1/4 (beat)", PatternData.ppq), ("Fill every 1/8", PatternData.ppq / 2),
                                        ("Fill every step (1/16)", PatternData.stepTicks), ("Fill every 1/2 step (1/32)", PatternData.stepTicks / 2)]
        var items: [BBMenuItem] = fills.map { f in
            BBMenuItem.item(f.0, icon: "square.grid.4x3.fill") { commit(PatternEdit.fill(pattern, pad: pad, every: f.1, velocity: lastVelocity)) }
        }
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
        if Int(e.pad) == Pad.bass808.rawValue && e.length > 0 { return max(step * 0.6, CGFloat(e.length) / CGFloat(pageTicks) * w - 2) }
        return max(6, min(step * 0.72, 30))
    }
    private func noteRect(_ e: GrooveEvent, w: CGFloat, rowH: CGFloat) -> CGRect {
        let h = min(rowH * 0.56, 24)
        return CGRect(x: x(e.tick, w) + 1, y: CGFloat(e.pad) * rowH + (rowH - h) / 2, width: noteWidth(e, w), height: h)
    }
    private func visible(_ e: GrooveEvent) -> Bool { e.tick >= pageStart && e.tick < pageStart + pageTicks }

    private func grid(width w: CGFloat, rowH: CGFloat) -> some View {
        Canvas { ctx, size in
            for r in 0..<Pad.count {
                ctx.fill(Path(CGRect(x: 0, y: CGFloat(r) * rowH, width: size.width, height: rowH)),
                         with: .color(r % 2 == 0 ? S.rowA : S.rowB))
            }
            // Lines: SNAP grid, beats, bars.
            let steps = Int(pageTicks / max(1, snapTicks > 0 ? snapTicks : PatternData.stepTicks))
            for s in 0...steps {
                let t = Int32(s) * (snapTicks > 0 ? snapTicks : PatternData.stepTicks)
                let lx = CGFloat(t) / CGFloat(pageTicks) * size.width
                let isBar = t % PatternEdit.barTicks == 0, isBeat = t % PatternData.ppq == 0
                ctx.fill(Path(CGRect(x: lx, y: 0, width: isBar ? 1.5 : 1, height: size.height)),
                         with: .color(isBar ? S.barLine : isBeat ? S.beatLine : S.stepLine))
            }
            // Past the end of a short pattern.
            let endX = x(max(pattern.lengthTicks, 1), size.width)
            if endX < size.width {
                ctx.fill(Path(CGRect(x: endX, y: 0, width: size.width - endX, height: size.height)), with: .color(Color.black.opacity(0.45)))
            }
            for e in pattern.events where visible(e) {
                let r = noteRect(e, w: size.width, rowH: rowH)
                let sel = selection.contains(NoteKey(e))
                let base = sel ? S.orange : S.green
                let shade = 0.55 + 0.45 * Double(e.velocity)
                if sel { ctx.fill(Path(roundedRect: r.insetBy(dx: -2, dy: -2), cornerRadius: 5), with: .color(S.orange.opacity(0.3))) }
                ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(base.opacity(shade)))
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
                    ctx.fill(Path(CGRect(x: px - 1, y: 0, width: 2, height: size.height)), with: .color(S.green))
                }
            }
            _ = tick   // redraw the playhead with the ticker
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in gridChanged(g, w: w, rowH: rowH) }
            .onEnded { g in gridEnded(g, w: w, rowH: rowH) })
    }

    // MARK: Grid gestures

    private func noteAt(_ p: CGPoint, w: CGFloat, rowH: CGFloat) -> GrooveEvent? {
        let row = Int(p.y / rowH)
        return pattern.events.last { e in
            Int(e.pad) == row && visible(e) && noteRect(e, w: w, rowH: rowH).insetBy(dx: -6, dy: -6).contains(p)
        }
    }

    private func gridChanged(_ g: DragGesture.Value, w: CGFloat, rowH: CGFloat) {
        if case .none = drag {
            let start = g.startLocation
            let startRow = Int(start.y / rowH)
            guard (0..<Pad.count).contains(startRow) else { return }
            let hit = noteAt(start, w: w, rowH: rowH)
            switch tool {
            case .draw:
                if let hit {
                    let r = noteRect(hit, w: w, rowH: rowH)
                    if Int(hit.pad) == Pad.bass808.rawValue && start.x > r.maxX - 14 {
                        drag = .resize(key: NoteKey(hit), origin: pattern)
                    } else {
                        drag = .tapOnNote(key: NoteKey(hit))
                    }
                    lastVelocity = hit.velocity
                } else if startRow == Pad.bass808.rawValue {
                    drag = .long808(start: snapped(tickAt(start.x, w)))
                } else {
                    let t = snapped(tickAt(start.x, w))
                    undoStack.append(pattern); redoStack = []
                    // Drawing is silent: a new note sounds only when the playhead reaches it.
                    work = PatternEdit.addNote(pattern, pad: startRow, tick: t, velocity: lastVelocity)
                    drag = .paint(pad: startRow, lastCell: Int(t / placeTicks))
                }
            case .select:
                if let hit, selection.contains(NoteKey(hit)) {
                    drag = .move(keys: selection, origin: pattern, startTick: tickAt(start.x, w), followSelection: true)
                } else if let hit {
                    selection = [NoteKey(hit)]
                    drag = .move(keys: selection, origin: pattern, startTick: tickAt(start.x, w), followSelection: true)
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
                work = PatternEdit.addNote(pattern, pad: pad, tick: t, velocity: lastVelocity)
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
        case .resize(let key, let origin):
            guard let e = origin.events.first(where: { NoteKey($0) == key }) else { return }
            let end = snapped(tickAt(g.location.x, w) + placeTicks / 2)
            let (resized, _) = PatternEdit.resize(origin, key, length: max(placeTicks, end - e.tick))
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
        case .long808(let start):
            let end = snapped(tickAt(g.location.x, w))
            let length = max(placeTicks, (end > start ? end - start : 0) + placeTicks)
            let len = abs(g.translation.width) < 6 ? last808Length : length
            last808Length = len
            commit(PatternEdit.addNote(pattern, pad: Pad.bass808.rawValue, tick: start, length: len, velocity: lastVelocity))
        case .paint, .erase:
            if let p = work { work = nil; controller.setLoop(loop, p) }   // the undo point was pushed when the finger went down
            else { _ = undoStack.popLast() }                             // nothing changed
        case .move(_, _, _, _), .resize(_, _):
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
        Button { controller.randomizePattern(); selection = [] } label: { iconBox("dice.fill") }
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
                Text(Pad(rawValue: pad)?.channelTitle ?? "").font(.system(size: 10, design: .monospaced)).foregroundColor(S.green)
            }
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .trailing) {
                    Text(lane == .velocity ? "127" : "+12").font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Text(lane == .velocity ? "64" : "0").font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Text(lane == .velocity ? "0" : "-12").font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(S.dim)
                .padding(.trailing, 6)
            }
        }
        .padding(8)
        .background(S.lane)
    }

    private func laneView(width w: CGFloat, height h: CGFloat) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(S.lane))
            for frac in [0.0, 0.5, 1.0] {
                ctx.fill(Path(CGRect(x: 0, y: CGFloat(frac) * (size.height - 8) + 4, width: size.width, height: 1)), with: .color(S.stepLine))
            }
            for b in 0...barsPerPage {
                let bx = CGFloat(b) / CGFloat(barsPerPage) * size.width
                ctx.fill(Path(CGRect(x: bx, y: 0, width: 1.5, height: size.height)), with: .color(S.beatLine))
            }
            for e in pattern.events where visible(e) && (selectedPad == nil || Int(e.pad) == selectedPad) {
                let sel = selection.contains(NoteKey(e))
                let v: CGFloat
                if lane == .velocity { v = CGFloat(e.velocity) } else { v = CGFloat((e.semis.clamped(-12, 12) + 12) / 24) }
                let bx = x(e.tick, size.width) + 3
                let top = 4 + (1 - v) * (size.height - 8)
                ctx.fill(Path(CGRect(x: bx, y: top, width: 5, height: size.height - 4 - top)),
                         with: .color((sel ? S.orange : S.green).opacity(selection.isEmpty || sel ? 0.95 : 0.35)))
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

    // MARK: Footer

    private var orderedKits: [KitDefinition] { SoundMode.allCases.flatMap { KitLibrary.kits(for: $0) } }

    private var footer: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Image(systemName: "square.grid.3x3.fill").font(.system(size: 16)).foregroundColor(S.text)
                    .frame(width: 46, height: 44).background(S.button)
                HStack {
                    Text(controller.state.kitName).font(.system(size: compact ? 13 : 17, weight: .medium)).foregroundColor(S.text).lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down").foregroundColor(S.text)
                }
                .padding(.horizontal, 12).frame(width: compact ? 150 : 190, height: 44)
            }
            .background(box(lit: false))
            .bbMenu(title: "Kits · drum sounds", width: 320) {
                SoundMode.allCases.map { mode in
                    BBMenuItem.submenu("\(mode.title) kits", icon: "square.grid.3x3", KitLibrary.kits(for: mode).map { def in
                        BBMenuItem.item(def.name, checked: def.id == controller.state.kitID) { controller.selectKit(def) }
                    })
                }
            }
            Button { cycleKit(-1) } label: { iconBox("chevron.left") }
            Button { cycleKit(1) } label: { iconBox("chevron.right") }
            Spacer(minLength: 6)
            Button { duplicate() } label: { labelBox("plus.square.on.square", compact ? nil : "DUPLICATE") }
            Button { clear() } label: { labelBox("trash", compact ? nil : "CLEAR") }
            if let url = exportURL {
                ShareLink(item: url) { labelBox("square.and.arrow.up", compact ? nil : "EXPORT MIDI") }
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: compact ? 58 : 72)
        .background(S.header)
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
            try MIDIFile.write(stored, tempo: controller.liveTempo, bounce: controller.value(.bounce), bars: bars, to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Undo, follow, samples

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

    private func dropSample(_ providers: [NSItemProvider], pad: Int) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { controller.importSample(url, toPad: pad) } }
            }
            return true
        }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _ in
            guard let url else { return }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: url, to: copy)
            DispatchQueue.main.async { controller.importSample(copy, toPad: pad) }
        }
        return true
    }

    // MARK: Small pieces

    private func box(lit: Bool, color: Color = S.green) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(lit ? (color == S.green ? S.greenDark : color.opacity(0.25)) : S.button)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(lit ? color.opacity(0.9) : S.border, lineWidth: lit ? 1.5 : 1))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }

    private func iconBox(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 17, weight: .medium)).foregroundColor(S.text)
            .frame(width: 44, height: 40).background(box(lit: false))
    }

    private func chip(_ text: String, width: CGFloat) -> some View {
        HStack {
            Text(text).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundColor(S.text).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(S.text)
        }
        .padding(.horizontal, 12).frame(width: width, height: 40).background(box(lit: false))
    }

    private func labelBox(_ icon: String?, _ title: String?, lit: Bool = false, enabled: Bool = true) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 15, weight: .medium)) }
            if let title { Text(title).font(.system(size: 13, weight: .medium, design: .monospaced)) }
        }
        .foregroundColor(lit ? S.green : (enabled ? S.text : S.dim))
        .padding(.horizontal, 14).frame(height: 44).background(box(lit: lit))
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
                Text(Pad(rawValue: pad)?.channelTitle ?? "PAD").font(.system(.title2, design: .monospaced))
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
    /// The drum roll's channel names (Tyrone's DRUM ROLL design).
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
