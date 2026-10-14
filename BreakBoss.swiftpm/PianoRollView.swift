// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - Channel piano roll (drum roll › tap a channel › Piano roll)
//
// One channel's notes on a pitch grid, like FL Studio's piano roll for a channel: tap to add
// at a pitch, tap a note to delete it, drag a note to move it in time and pitch, drag the end
// of an 808 note to stretch it, and set velocities in the lane underneath. Drums take
// -12...+12 semitones per hit, the 808 -12...+24. Changes go through setLoop like the drum roll.

struct PianoRollView: View {
    @ObservedObject var controller: KnockController
    let loop: Int
    let pad: Int
    @Environment(\.dismiss) private var dismiss

    @State private var snap = 16
    @State private var undoStack: [PatternData] = []
    @State private var redoStack: [PatternData] = []
    @State private var work: PatternData?
    @State private var drag: Drag = .none
    @State private var lastVelocity: Float = 0.78
    @State private var page = 0

    enum Drag {
        case none
        case tap(key: NoteKey)
        case move(key: NoteKey, origin: PatternData, startTick: Int32, startSemis: Float)
        case resize(key: NoteKey, origin: PatternData)
        case lane(origin: PatternData)
    }

    private typealias S = DrumRollStyle

    private var isBass: Bool { pad == Pad.bass808.rawValue }
    private var topSemis: Int { isBass ? 24 : 12 }
    private var rows: Int { topSemis + 12 + 1 }
    private var stored: PatternData {
        controller.loops.indices.contains(loop) ? controller.loops[loop] : PatternData(name: "", lengthTicks: PatternEdit.barTicks, events: [])
    }
    private var pattern: PatternData { work ?? stored }
    private var bars: Int { max(1, pattern.bars) }
    private var barsPerPage: Int { min(2, bars) }
    private var pages: Int { max(1, (bars + barsPerPage - 1) / barsPerPage) }
    private var pageStart: Int32 { Int32(min(page, pages - 1) * barsPerPage) * PatternEdit.barTicks }
    private var pageTicks: Int32 { Int32(barsPerPage) * PatternEdit.barTicks }
    private var grid: Int32 { snap > 0 ? PatternEdit.barTicks / Int32(snap) : 6 }
    private var notes: [GrooveEvent] { pattern.events.filter { Int($0.pad) == pad && $0.tick >= pageStart && $0.tick < pageStart + pageTicks } }

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let keysW: CGFloat = 52
                let laneH: CGFloat = 110
                let gridW = geo.size.width - keysW
                let rowH = max(14, (geo.size.height - laneH - 10) / CGFloat(rows))
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        keyboard(rowH: rowH).frame(width: keysW)
                        noteGrid(w: gridW, rowH: rowH).frame(width: gridW, height: rowH * CGFloat(rows))
                    }
                    Rectangle().fill(Color.black).frame(height: 10)
                    HStack(spacing: 0) {
                        Text("VEL").font(.system(size: 11, design: .monospaced)).foregroundColor(S.dim).frame(width: keysW)
                        lane(w: gridW, h: laneH).frame(width: gridW, height: laneH)
                    }
                }
            }
            .background(S.toolbar)
            .navigationTitle("\(Pad(rawValue: pad)?.channelTitle ?? "") · PIANO ROLL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(undoStack.isEmpty)
                    Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(redoStack.isEmpty)
                    Text("SNAP 1/\(snap)").foregroundColor(DrumRollStyle.green)
                        .bbMenu(title: "Snap", width: 200) { [4, 8, 16, 32, 64].map { d in BBMenuItem.item("1/\(d)", checked: snap == d) { snap = d } } }
                    Text("KEY \(MusicScale.noteNames[controller.scaleRoot])").foregroundColor(DrumRollStyle.green)
                        .bbMenu(title: "Key", width: 160) {
                            MusicScale.noteNames.enumerated().map { i, n in BBMenuItem.item(n, checked: controller.scaleRoot == i) { controller.setScale(root: i) } }
                        }
                    Text(controller.scale.name.uppercased()).foregroundColor(DrumRollStyle.green).lineLimit(1)
                        .bbMenu(title: "Scale", width: 260) { scaleMenu() }
                    Button { controller.setScale(snap: !controller.snapToScale) } label: {
                        Text(controller.snapToScale ? "SCALE SNAP ON" : "SCALE SNAP OFF")
                            .foregroundColor(controller.snapToScale ? .black : DrumRollStyle.green)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(controller.snapToScale ? DrumRollStyle.green : Color.clear))
                    }
                }
                ToolbarItemGroup(placement: .confirmationAction) {
                    Button { page = max(0, page - 1) } label: { Image(systemName: "chevron.left") }.disabled(page == 0)
                    Button { page = min(pages - 1, page + 1) } label: { Image(systemName: "chevron.right") }.disabled(page >= pages - 1)
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .bbMenuHost()
    }

    // MARK: Scale

    private func scaleMenu() -> [BBMenuItem] {
        var items = MusicScale.all.map { sc in
            BBMenuItem.item(sc.name, checked: controller.scale.name == sc.name) { controller.setScale(name: sc.name) }
        }
        items.append(.header("Notes already drawn"))
        items.append(BBMenuItem.item("Fit this channel's notes to the scale", icon: "tuningfork") { fitToScale() })
        return items
    }

    /// FL's "snap notes to scale": moves every note of this channel to the nearest scale note.
    private func fitToScale() {
        let base = controller.baseNote(pad: pad)
        var p = stored
        for i in p.events.indices where Int(p.events[i].pad) == pad {
            let n = controller.scale.snap(base + Int(p.events[i].semis.rounded()), root: controller.scaleRoot)
            p.events[i].semis = Float(n - base).clamped(-12, Float(topSemis))
        }
        commit(p)
    }

    // MARK: Drawing

    private func y(_ semis: Float, _ rowH: CGFloat) -> CGFloat { CGFloat(Float(topSemis) - semis.rounded()) * rowH }
    private func semisAt(_ y: CGFloat, _ rowH: CGFloat) -> Float { inKey(Float(topSemis - Int(y / rowH))) }
    /// SNAP TO SCALE: the nearest pitch in the chosen key and scale (when snap is on), kept on the grid.
    private func inKey(_ semis: Float) -> Float {
        let s = semis.clamped(-12, Float(topSemis))
        let snapped = controller.scaleSnapped(s, pad: pad)
        if snapped >= -12 && snapped <= Float(topSemis) { return snapped }
        return controller.scaleSnapped(s + (snapped < -12 ? 1 : -1), pad: pad).clamped(-12, Float(topSemis))
    }
    private func note(_ semis: Int) -> Int { controller.baseNote(pad: pad) + semis }
    private func inScale(_ semis: Int) -> Bool { controller.scale.contains(note(semis), root: controller.scaleRoot) }
    private func isRoot(_ semis: Int) -> Bool { (((note(semis) - controller.scaleRoot) % 12) + 12) % 12 == 0 }
    private func x(_ t: Int32, _ w: CGFloat) -> CGFloat { CGFloat(t - pageStart) / CGFloat(pageTicks) * w }
    private func tickAt(_ x: CGFloat, _ w: CGFloat) -> Int32 { pageStart + Int32((x / w * CGFloat(pageTicks)).rounded(.down)) }
    private func snapped(_ t: Int32) -> Int32 { max(0, min((t / grid) * grid, max(pattern.lengthTicks, 1) - 1)) }
    private func rect(_ e: GrooveEvent, w: CGFloat, rowH: CGFloat) -> CGRect {
        let len = e.length > 0 ? e.length : PatternData.stepTicks
        return CGRect(x: x(e.tick, w) + 1, y: y(e.semis, rowH) + 1, width: max(6, CGFloat(len) / CGFloat(pageTicks) * w - 2), height: rowH - 2)
    }

    private func keyboard(rowH: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { r in
                let semis = topSemis - r
                let n = note(semis)
                let black = [1, 3, 6, 8, 10].contains(((n % 12) + 12) % 12)
                let out = controller.snapToScale && !inScale(semis)
                Button { controller.auditionPad(pad, velocity: lastVelocity, semis: Float(semis)) } label: {
                    // Real note names (C2, F#1 …) so the 808 can be tuned to the song's key.
                    Text(rowH >= 15 || n % 12 == 0 ? MusicScale.noteName(n) : "")
                        .font(.system(size: 9, weight: isRoot(semis) && controller.snapToScale ? .bold : .regular, design: .monospaced))
                        .foregroundColor(black ? .white : .black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, 4)
                        .background(black ? Color(white: 0.12) : Color(white: semis == 0 ? 0.95 : 0.82))
                        .overlay(controller.snapToScale && isRoot(semis) ? S.green.opacity(0.35) : out ? Color.black.opacity(0.45) : Color.clear)
                        .overlay(Rectangle().fill(Color.black.opacity(0.4)).frame(height: 0.5), alignment: .bottom)
                }
                .frame(height: rowH)
            }
        }
    }

    private func noteGrid(w: CGFloat, rowH: CGFloat) -> some View {
        Canvas { ctx, size in
            for r in 0..<rows {
                let semis = topSemis - r
                let black = [1, 3, 6, 8, 10].contains(((note(semis) % 12) + 12) % 12)
                let rowRect = Path(CGRect(x: 0, y: CGFloat(r) * rowH, width: size.width, height: rowH))
                if controller.snapToScale {
                    // FL-style scale highlighting: the key's notes lit, the root tinted, the rest dark.
                    ctx.fill(rowRect, with: .color(inScale(semis) ? S.rowB : S.rowA.opacity(0.6)))
                    if isRoot(semis) { ctx.fill(rowRect, with: .color(S.green.opacity(0.12))) }
                } else {
                    ctx.fill(rowRect, with: .color(semis == 0 ? S.rowB.opacity(1) : black ? S.rowA : S.rowB.opacity(0.8)))
                }
            }
            let steps = Int(pageTicks / grid)
            for s in 0...steps {
                let t = Int32(s) * grid
                let lx = CGFloat(t) / CGFloat(pageTicks) * size.width
                let isBar = t % PatternEdit.barTicks == 0, isBeat = t % PatternData.ppq == 0
                ctx.fill(Path(CGRect(x: lx, y: 0, width: isBar ? 1.5 : 1, height: size.height)),
                         with: .color(isBar ? S.barLine : isBeat ? S.beatLine : S.stepLine))
            }
            for e in notes {
                ctx.fill(Path(roundedRect: rect(e, w: size.width, rowH: rowH), cornerRadius: 3),
                         with: .color(S.green.opacity(0.55 + 0.45 * Double(e.velocity))))
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in changed(g, w: w, rowH: rowH) }
            .onEnded { g in ended(g, w: w, rowH: rowH) })
    }

    private func lane(w: CGFloat, h: CGFloat) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(S.lane))
            for e in notes {
                let top = 4 + (1 - CGFloat(e.velocity)) * (size.height - 8)
                ctx.fill(Path(CGRect(x: x(e.tick, size.width) + 2, y: top, width: 5, height: size.height - 4 - top)), with: .color(S.green))
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                if case .none = drag { drag = .lane(origin: stored) }
                let v = max(0.05, Float(1 - (g.location.y - 4) / (h - 8)).clamped(0, 1))
                let keys = Set(notes.filter { abs(x($0.tick, w) + 4 - g.location.x) <= 8 }.map(NoteKey.init))
                if !keys.isEmpty { work = PatternEdit.setVelocity(pattern, keys, v); lastVelocity = v }
            }
            .onEnded { _ in
                if let p = work { commit(p) }
                drag = .none
            })
    }

    // MARK: Gestures

    private func noteAt(_ p: CGPoint, w: CGFloat, rowH: CGFloat) -> GrooveEvent? {
        notes.last { rect($0, w: w, rowH: rowH).insetBy(dx: -4, dy: -2).contains(p) }
    }

    private func changed(_ g: DragGesture.Value, w: CGFloat, rowH: CGFloat) {
        if case .none = drag {
            if let hit = noteAt(g.startLocation, w: w, rowH: rowH) {
                let r = rect(hit, w: w, rowH: rowH)
                lastVelocity = hit.velocity
                drag = isBass && g.startLocation.x > r.maxX - 12 ? .resize(key: NoteKey(hit), origin: stored) : .tap(key: NoteKey(hit))
            } else {
                let t = snapped(tickAt(g.startLocation.x, w)), semis = semisAt(g.startLocation.y, rowH)
                commit(PatternEdit.addNote(pattern, pad: pad, tick: t, length: isBass ? PatternEdit.default808Length : 0,
                                           velocity: lastVelocity, semis: semis))
                controller.auditionPad(pad, velocity: lastVelocity, semis: semis)
                if let e = pattern.events.first(where: { Int($0.pad) == pad && $0.tick == t && $0.semis == semis }) {
                    drag = isBass ? .resize(key: NoteKey(e), origin: stored) : .move(key: NoteKey(e), origin: stored, startTick: t, startSemis: semis)
                }
                return
            }
        }
        switch drag {
        case .tap(let key):
            if hypot(g.translation.width, g.translation.height) > 8 {
                drag = .move(key: key, origin: stored, startTick: key.tick, startSemis: key.semis)
                changed(g, w: w, rowH: rowH)
            }
        case .move(let key, let origin, let startTick, let startSemis):
            let dt = snapped(tickAt(g.location.x, w)) - snapped(tickAt(g.startLocation.x, w))
            let (moved, keys) = PatternEdit.move(origin, [key], by: dt)
            let semis = inKey(startSemis + Float((g.startLocation.y - g.location.y) / rowH).rounded())
            work = PatternEdit.setPitch(moved, keys, semis).0
            _ = startTick
        case .resize(let key, let origin):
            guard let e = origin.events.first(where: { NoteKey($0) == key }) else { return }
            let end = snapped(tickAt(g.location.x, w) + grid / 2)
            work = PatternEdit.resize(origin, key, length: max(grid, end - e.tick)).0
        default:
            break
        }
    }

    private func ended(_ g: DragGesture.Value, w: CGFloat, rowH: CGFloat) {
        defer { drag = .none }
        switch drag {
        case .tap(let key):
            commit(PatternEdit.remove(pattern, [key]))
        case .move(_, let origin, _, _), .resize(_, let origin):
            if let p = work {
                work = nil
                if p != origin { undoStack.append(origin); redoStack = []; controller.setLoop(loop, p) }
            }
        default:
            break
        }
    }

    private func commit(_ p: PatternData) {
        work = nil
        guard p != stored else { return }
        undoStack.append(stored)
        redoStack = []
        controller.setLoop(loop, p)
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(stored)
        controller.setLoop(loop, last)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(stored)
        controller.setLoop(loop, next)
    }
}
