// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import Combine

// MARK: - Pattern editor (the piano-keys button next to EXPORT)
//
// A step sequencer for the 12 loops, laid out like DRUMFLX's MIDI editor: pattern, grid,
// length, bar pages, FOLLOW, undo / redo, BLANK PATTERN and COPY NEXT, one row per pad.
// It only edits notes. Every change goes through KnockController.setLoop, the same path the
// hold-a-pad editor and MIDI import use, so presets, exports and the engine all see the edit.

struct PatternEditorView: View {
    @ObservedObject var controller: KnockController
    @State var loop: Int
    @Environment(\.dismiss) private var dismiss

    @State private var division = 16          // cells per bar: 8, 16 or 32
    @State private var page = 0               // which pair of bars is on screen
    @State private var follow = true
    @State private var undoStack: [PatternData] = []
    @State private var redoStack: [PatternData] = []
    @State private var dragStart: (row: Int, col: Int)?
    @State private var refresh = Date()   // redraws PLAY / STOP while the sheet is open

    private let barsPerPage = 2
    private let rowHeight: CGFloat = 30
    private let labelWidth: CGFloat = 104
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var accent: Color { PadView.lightColor(controller.mode) }
    private var pattern: PatternData {
        controller.loops.indices.contains(loop) ? controller.loops[loop]
            : PatternData(name: "", lengthTicks: PatternData.ppq * 8, events: [])
    }
    private var cellTicks: Int32 { PatternData.ppq * 4 / Int32(division) }
    private var bars: Int { max(1, pattern.bars) }
    private var pages: Int { max(1, (bars + barsPerPage - 1) / barsPerPage) }
    private var pageBars: Int { min(barsPerPage, bars - page * barsPerPage) }
    private var pageStartTick: Int32 { Int32(page * barsPerPage) * PatternData.ppq * 4 }
    private var columns: Int { max(1, pageBars) * division }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 10) {
                topBar
                secondBar
                grid
                Text("Tap a square to add or remove a hit. On the 808 row, drag across squares to draw a long note. Velocity and feel are kept on hits you don't touch.")
                    .font(.footnote).foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .padding()
            .background(Color(white: 0.07).ignoresSafeArea())
            .navigationTitle("Pattern Editor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .onReceive(ticker) { now in refresh = now; followPlayhead() }
        .onChange(of: loop) { _ in page = 0; undoStack = []; redoStack = [] }
        .onChange(of: bars) { _ in page = min(page, pages - 1) }
    }

    // MARK: Bars of buttons

    private var topBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(0..<min(Pad.count, controller.loops.count), id: \.self) { i in
                        Button("PATTERN \(String(format: "%02d", i + 1))  \(controller.loops[i].name)") { loop = i }
                    }
                } label: { chip("PATTERN \(String(format: "%02d", loop + 1)) ▾", wide: true) }
                Text("\(controller.kitDisplayName) / \(pattern.name)")
                    .font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary).lineLimit(1)
                Spacer(minLength: 12)
                Button { controller.previewLoop(loop) } label: { chip(isThisLoopPlaying ? "■ STOP" : "▶ PLAY", lit: isThisLoopPlaying) }
                Button { undo() } label: { chip("UNDO") }.disabled(undoStack.isEmpty)
                Button { redo() } label: { chip("REDO") }.disabled(redoStack.isEmpty)
            }
        }
    }

    private var secondBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    ForEach([8, 16, 32], id: \.self) { d in Button("1/\(d)") { division = d } }
                } label: { chip("1/\(division) ▾") }
                Button { blankPattern() } label: { chip("BLANK PATTERN") }
                Button { copyNext() } label: { chip("COPY NEXT") }
                Menu {
                    ForEach([1, 2, 4, 8], id: \.self) { b in Button("\(b) BAR\(b == 1 ? "" : "S")") { setLength(bars: b) } }
                } label: { chip("\(bars) BAR\(bars == 1 ? "" : "S") ▾") }
                Button { follow.toggle() } label: { chip("FOLLOW", lit: follow) }
                Button { page = max(0, page - 1); follow = false } label: { chip("<") }.disabled(page == 0)
                Text(pageBars > 1 ? "BARS \(page * barsPerPage + 1)-\(page * barsPerPage + pageBars)" : "BAR \(page * barsPerPage + 1)")
                    .font(.system(size: 12, design: .monospaced)).frame(minWidth: 76)
                Button { page = min(pages - 1, page + 1); follow = false } label: { chip(">") }.disabled(page >= pages - 1)
            }
        }
    }

    private func chip(_ text: String, wide: Bool = false, lit: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(lit ? .black : .white)
            .padding(.horizontal, wide ? 12 : 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 4).fill(lit ? accent : Color(white: 0.17)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.3), lineWidth: 1))
    }

    // MARK: Grid

    private var grid: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(spacing: 0) {
                ForEach(rowsTopDown, id: \.self) { pad in
                    Text(controller.padName(pad).uppercased())
                        .font(.system(size: 11, design: .monospaced)).lineLimit(1)
                        .frame(width: labelWidth, height: rowHeight, alignment: .leading)
                        .padding(.leading, 6)
                        .background(Color(white: 0.12))
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                }
            }
            GeometryReader { geo in
                let cellW = max(14, geo.size.width / CGFloat(columns))
                ScrollView(.horizontal, showsIndicators: cellW * CGFloat(columns) > geo.size.width + 1) {
                    let width = cellW * CGFloat(columns)
                    TimelineView(.periodic(from: .now, by: 1.0 / 30)) { _ in
                        Canvas { ctx, size in draw(ctx, size: size, cellW: cellW) }
                    }
                    .frame(width: width, height: rowHeight * CGFloat(Pad.count))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if dragStart == nil { dragStart = cell(at: g.startLocation, cellW: cellW) }
                        }
                        .onEnded { g in
                            defer { dragStart = nil }
                            guard let start = dragStart ?? cell(at: g.startLocation, cellW: cellW) else { return }
                            let end = cell(at: g.location, cellW: cellW)
                            if rowsTopDown[start.row] == Pad.bass808.rawValue, let end, end.col != start.col {
                                draw808(from: min(start.col, end.col), to: max(start.col, end.col))
                            } else if abs(g.translation.width) < cellW && abs(g.translation.height) < rowHeight {
                                toggle(row: start.row, col: start.col)
                            }
                        })
                }
            }
            .frame(height: rowHeight * CGFloat(Pad.count))
        }
    }

    private var rowsTopDown: [Int] { Array((0..<Pad.count).reversed()) }

    private func cell(at p: CGPoint, cellW: CGFloat) -> (row: Int, col: Int)? {
        let row = Int(p.y / rowHeight), col = Int(p.x / cellW)
        guard row >= 0, row < Pad.count, col >= 0, col < columns else { return nil }
        return (row, col)
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, cellW: CGFloat) {
        let p = pattern
        let start = pageStartTick
        let end = start + Int32(columns) * cellTicks
        // Background cells: every beat a little lighter, every bar a bright line.
        for c in 0..<columns {
            let beatShade = (c / max(1, division / 4)) % 2 == 0 ? 0.15 : 0.12
            for r in 0..<Pad.count {
                let rect = CGRect(x: CGFloat(c) * cellW, y: CGFloat(r) * rowHeight, width: cellW, height: rowHeight)
                ctx.fill(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(Color(white: beatShade)))
            }
            if c % division == 0 && c > 0 {
                ctx.fill(Path(CGRect(x: CGFloat(c) * cellW - 1, y: 0, width: 2, height: size.height)), with: .color(Color(white: 0.55)))
            }
        }
        // Hits.
        for e in p.events where e.tick >= start - cellTicks / 4 && e.tick < end {
            guard let row = rowsTopDown.firstIndex(of: Int(e.pad)) else { continue }
            let col = Int((e.tick - start + cellTicks / 4) / cellTicks)
            guard col >= 0 && col < columns else { continue }
            var span: CGFloat = 1
            if Int(e.pad) == Pad.bass808.rawValue && e.length > 0 {
                span = max(1, CGFloat(e.length) / CGFloat(cellTicks))
            }
            let rect = CGRect(x: CGFloat(col) * cellW + 2, y: CGFloat(row) * rowHeight + 3,
                              width: min(span * cellW, CGFloat(columns - col) * cellW) - 4, height: rowHeight - 6)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2),
                     with: .color(Color.white.opacity(0.55 + 0.45 * Double(e.velocity))))
        }
        // Playhead.
        if isThisLoopPlaying, let tick = playheadTick, tick >= start && tick < end {
            let x = CGFloat(tick - start) / CGFloat(cellTicks) * cellW
            ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(accent))
        }
    }

    // MARK: Playhead and FOLLOW

    private var isThisLoopPlaying: Bool {
        controller.meters.status[0] > 0.5 && Int(controller.meters.status[1]) == loop
    }

    private var playheadTick: Int32? {
        let len = Double(max(pattern.lengthTicks, PatternData.ppq))
        let beat = controller.meters.status[3]
        guard beat.isFinite else { return nil }
        return Int32((beat * Double(PatternData.ppq)).truncatingRemainder(dividingBy: len))
    }

    private func followPlayhead() {
        guard follow, isThisLoopPlaying, let tick = playheadTick else { return }
        let target = min(pages - 1, Int(tick / (PatternData.ppq * 4)) / barsPerPage)
        if target != page { page = target }
    }

    // MARK: Edits (all through controller.setLoop)

    private func commit(_ p: PatternData) {
        undoStack.append(pattern)
        if undoStack.count > 64 { undoStack.removeFirst() }
        redoStack.removeAll()
        var sorted = p
        sorted.sort()
        controller.setLoop(loop, sorted)
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(pattern)
        controller.setLoop(loop, last)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(pattern)
        controller.setLoop(loop, next)
    }

    private func toggle(row: Int, col: Int) {
        commit(PatternEdit.toggle(pattern, pad: rowsTopDown[row], tick: pageStartTick + Int32(col) * cellTicks, cell: cellTicks))
    }

    private func draw808(from c0: Int, to c1: Int) {
        commit(PatternEdit.longBass(pattern, from: pageStartTick + Int32(c0) * cellTicks,
                                    cells: c1 - c0 + 1, cell: cellTicks))
    }

    private func blankPattern() {
        var p = pattern
        p.events = []
        commit(p)
    }

    private func copyNext() {
        let p = PatternEdit.copyNext(pattern, fromBar: page * barsPerPage, bars: pageBars)
        guard p != pattern else { return }
        commit(p)
        page = min(page + 1, max(1, (p.bars + barsPerPage - 1) / barsPerPage) - 1)
    }

    private func setLength(bars newBars: Int) {
        let p = PatternEdit.setLength(pattern, bars: newBars)
        if p != pattern { commit(p) }
    }
}

/// The editor's note operations, kept out of the view so the self-test can check them.
enum PatternEdit {
    static let barTicks = PatternData.ppq * 4

    /// Adds a hit at `tick`, or removes the pad's hits already in that cell.
    static func toggle(_ pattern: PatternData, pad: Int, tick: Int32, cell: Int32) -> PatternData {
        var p = pattern
        let lo = tick - cell / 4, hi = tick + cell * 3 / 4
        let before = p.events.count
        p.events.removeAll { Int($0.pad) == pad && $0.tick >= lo && $0.tick < hi }
        if p.events.count == before {
            if pad == Pad.bass808.rawValue {
                p.events.append(GrooveEvent(tick: tick, pad: Int8(pad), velocity: 0.9, semis: 0,
                                            length: max(cell, PatternData.stepTicks * 2)))
            } else {
                p.events.append(GrooveEvent(tick: tick, pad: Int8(pad), velocity: pad == Pad.hat.rawValue ? 0.7 : 0.9))
            }
        }
        p.sort()
        return p
    }

    /// One 808 note held across `cells` cells, replacing the 808 hits under it.
    static func longBass(_ pattern: PatternData, from tick: Int32, cells: Int, cell: Int32) -> PatternData {
        var p = pattern
        let lo = tick - cell / 4, hi = tick + Int32(cells) * cell - cell / 4
        p.events.removeAll { Int($0.pad) == Pad.bass808.rawValue && $0.tick >= lo && $0.tick < hi }
        let length = min(Int32(cells) * cell, max(p.lengthTicks, cell) - tick)
        p.events.append(GrooveEvent(tick: tick, pad: Int8(Pad.bass808.rawValue), velocity: 0.9, semis: 0, length: length))
        p.sort()
        return p
    }

    /// Copies `bars` bars starting at `fromBar` into the bars right after (up to 8 bars long).
    static func copyNext(_ pattern: PatternData, fromBar: Int, bars: Int) -> PatternData {
        var p = pattern
        let span = Int32(bars) * barTicks
        let from = Int32(fromBar) * barTicks, to = from + span
        let needed = min(8, fromBar + bars * 2)
        if needed > p.bars { p.lengthTicks = Int32(needed) * barTicks }
        let destEnd = min(to + span, p.lengthTicks)
        guard to < p.lengthTicks else { return pattern }
        p.events.removeAll { $0.tick >= to && $0.tick < destEnd }
        p.events += p.events.filter { $0.tick >= from && $0.tick < to }.compactMap { e in
            var c = e
            c.tick += span
            return c.tick < destEnd ? c : nil
        }
        p.sort()
        return p
    }

    /// Longer repeats what's there; shorter drops the hits past the new end.
    static func setLength(_ pattern: PatternData, bars: Int) -> PatternData {
        var p = pattern
        let oldLen = max(p.lengthTicks, barTicks), newLen = Int32(max(1, min(8, bars))) * barTicks
        guard newLen != p.lengthTicks else { return pattern }
        if newLen > oldLen {
            let source = p.events
            var offset = oldLen
            while offset < newLen {
                p.events += source.compactMap { e in
                    var c = e
                    c.tick += offset
                    return c.tick < newLen ? c : nil
                }
                offset += oldLen
            }
        } else {
            p.events.removeAll { $0.tick >= newLen }
            for i in p.events.indices where p.events[i].length > 0 {
                p.events[i].length = min(p.events[i].length, newLen - p.events[i].tick)
            }
        }
        p.lengthTicks = newLen
        p.sort()
        return p
    }
}
