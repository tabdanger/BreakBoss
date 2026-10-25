// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Face 2: drawing the step grid, the piano roll notes and the playhead.
extension SequencerView {
    // MARK: Grid drawing

    func x(_ t: Int32, _ w: CGFloat) -> CGFloat { CGFloat((Double(t) - origin) / Double(pageTicks)) * w }
    func tickAt(_ x: CGFloat, _ w: CGFloat) -> Int32 { Int32((origin + Double(x / w) * Double(pageTicks)).rounded(.down)) }
    func snapped(_ t: Int32) -> Int32 {
        let g = placeTicks
        return max(0, min((t / g) * g, max(pattern.lengthTicks, 1) - 1))
    }
    func cellWidth(_ w: CGFloat) -> CGFloat { w / CGFloat(pageTicks) * CGFloat(cellTicks) }
    func noteWidth(_ e: GrooveEvent, _ w: CGFloat) -> CGFloat {
        if e.length > 0 { return max(6, CGFloat(e.length) / CGFloat(pageTicks) * w - 3) }
        return max(6, cellWidth(w) - 2)
    }
    func noteRect(_ e: GrooveEvent, w: CGFloat, _ L: [RowLayout]) -> CGRect? {
        guard let l = layout(for: Int(e.pad), L) else { return nil }
        if let range = l.pitch {
            // a note above or below the keys showing isn't drawn (its step still lights in the band)
            let s = Int(e.semis.rounded())
            guard range.contains(s) else { return nil }
            let y = l.pitchTop + CGFloat(range.upperBound - s) * l.pitchRowH
            return CGRect(x: x(e.tick, w) + 1.5, y: y + 1.5, width: noteWidth(e, w), height: l.pitchRowH - 3)
        }
        return CGRect(x: x(e.tick, w) + 1, y: l.y + 2, width: noteWidth(e, w), height: l.bandH - 4)
    }
    func visible(_ e: GrooveEvent) -> Bool { e.tick >= pageStart && Double(e.tick) < origin + Double(pageTicks) }

    /// Everything the grid's drawing reads. The grid only redraws when this changes, so the clock
    /// ticking while a pattern plays (and anything else on Face 2) leaves it alone.
    func gridKey(_ L: [RowLayout], w: CGFloat) -> Int {
        var h = Hasher()
        h.combine(finish)     // the grid's lit colours follow the finish
        h.combine(origin); h.combine(pageTicks); h.combine(cellTicks); h.combine(snapTicks); h.combine(pattern.lengthTicks)
        for e in pattern.events {
            h.combine(e.tick); h.combine(e.pad); h.combine(e.velocity); h.combine(e.semis)
            h.combine(e.length); h.combine(e.glide); h.combine(e.offset); h.combine(e.chance)
        }
        h.combine(selection); h.combine(hoverNote)
        for l in L {
            h.combine(l.channel.id); h.combine(l.channel.pad); h.combine(l.y); h.combine(l.height); h.combine(l.bandH)
            h.combine(l.graphH); h.combine(l.pitchTop); h.combine(l.pitchRowH); h.combine(l.pitch?.lowerBound); h.combine(l.pitch?.upperBound)
            if l.pitch != nil { h.combine(controller.baseNote(pad: l.channel.pad)) }
        }
        h.combine(finish); h.combine(controller.mode.rawValue); h.combine(controller.state.scaleName); h.combine(controller.scaleRoot)
        h.combine(tool); h.combine(lane.rawValue)
        switch drag {
        case let .marquee(a, b): h.combine(1); h.combine(a.x); h.combine(a.y); h.combine(b.x); h.combine(b.y)
        case let .noteRepeat(pad, cellStart, _, _, count, _): h.combine(2); h.combine(pad); h.combine(cellStart); h.combine(count)
        default: h.combine(0)
        }
        if let r = traceRect(L, w: w) { h.combine(3); h.combine(r.minX); h.combine(r.minY); h.combine(r.width) }
        return h.finalize()
    }

    func grid(_ L: [RowLayout], width w: CGFloat, rowH: CGFloat) -> some View {
        EquatableCanvas(key: gridKey(L, w: w)) { ctx, size in
            ctx.clip(to: Path(CGRect(x: 0, y: -20, width: size.width, height: size.height + 40)))
            let cw = cellWidth(size.width)
            // one more cell than fits: while sliding, the first and last are partly on screen
            let cells = Int(pageTicks / cellTicks) + 1
            for (i, l) in L.enumerated() {
                if let range = l.pitch {
                    // the band: the track's steps, lit where it has notes (any pitch)
                    ctx.fill(Path(CGRect(x: 0, y: l.y, width: size.width, height: l.pitchTop - l.y)), with: .color(litDark.opacity(0.5)))
                    ctx.fill(Path(CGRect(x: 0, y: l.y + l.bandH, width: size.width, height: l.pitchTop - l.y - l.bandH)), with: .color(Color(white: 0.06)))
                    drawMetalCells(ctx, (0..<cells).map { cellRect($0, cw, l, size.width) })
                    for c in 0..<cells {
                        let at = pageStart + Int32(c) * cellTicks
                        let lit = pattern.events.contains { Int($0.pad) == l.channel.pad && $0.tick >= at && $0.tick < at + cellTicks }
                        let r = cellRect(c, cw, l, size.width)
                        if (Int(at / PatternData.ppq) % 2) == 1 { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.32))) }
                        if lit { ctx.fill(Path(roundedRect: r.insetBy(dx: 1, dy: 2), cornerRadius: 3), with: .color(glowColor.opacity(0.8))) }
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
                                 with: .color(isRoot ? lit.opacity(0.1) : (inScale ? (k % 2 == 0 ? S.rowA : S.rowB) : Color.black.opacity(0.35))))
                        if inScale && !isRoot { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: l.pitchRowH)), with: .color(noteColor.opacity(0.07))) }
                        if s == 0 { ctx.fill(Path(CGRect(x: 0, y: y + l.pitchRowH - 1, width: size.width, height: 1)), with: .color(S.dim.opacity(0.5))) }
                    }
                    ctx.fill(Path(CGRect(x: 0, y: l.y, width: size.width, height: 1)), with: .color(lit.opacity(0.5)))
                    ctx.fill(Path(CGRect(x: 0, y: l.y + l.height - 1, width: size.width, height: 1)), with: .color(lit.opacity(0.5)))
                } else {
                    // the step buttons (the picture's)
                    drawMetalCells(ctx, (0..<cells).map { cellRect($0, cw, l, size.width) })
                    for c in 0..<cells {
                        let at = pageStart + Int32(c) * cellTicks
                        let r = cellRect(c, cw, l, size.width)
                        // every other beat's buttons are the darker grey (Tyrone's picture)
                        if (Int(at / PatternData.ppq) % 2) == 1 { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.32))) }
                        if at >= pattern.lengthTicks { ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.55))) }
                    }
                    if l.graphH > 0 { drawGraph(ctx, l, width: size.width) }
                }
            }
            // the bar line
            var t = pageStart
            while Double(t) <= origin + Double(pageTicks) {
                if t % PatternEdit.barTicks == 0 && Double(t) > origin && Double(t) < origin + Double(pageTicks) {
                    ctx.fill(Path(CGRect(x: x(t, size.width) - 0.5, y: 0, width: 1, height: size.height)), with: .color(Color.white.opacity(0.25)))
                }
                t += PatternData.ppq
            }
            if snapTicks > 0 && snapTicks < cellTicks {      // a finer SNAP than the cells: its lines
                var st = pageStart / snapTicks * snapTicks
                while Double(st) < origin + Double(pageTicks) { ctx.fill(Path(CGRect(x: x(st, size.width), y: 0, width: 1, height: size.height)), with: .color(S.stepLine)); st += snapTicks }
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
                return (key, cellRect(key.cell, cw, l, size.width), hits.sorted { $0.tick < $1.tick })
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
            for (_, r0, hits) in lit {
                let sel = hits.contains { selection.contains(NoteKey($0)) }
                let v = Double(hits.map(\.velocity).max() ?? 0.8)
                // under the pointer the step lifts a little off the plate; a selected one sits back down
                let lifted = !sel && hoverNote.map { h in hits.contains { NoteKey($0) == h } } == true
                let r = lifted ? liftNote(ctx, r0) : r0
                if lifted { drawMetalCells(ctx, [r]) }
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
            for (e, r0) in notes {
                let sel = selection.contains(NoteKey(e))
                let r = !sel && hoverNote == NoteKey(e) ? liftNote(ctx, r0) : r0
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
            // the note being drawn: its shadow under the finger, lit at the edge in the mode's colour
            if let r = traceRect(L, w: size.width) {
                ctx.drawLayer { g in
                    g.addFilter(.shadow(color: Color.black.opacity(0.8), radius: 5, y: 2))
                    g.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.45)))
                }
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(glowColor.opacity(0.22)))
                ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3), with: .color(glowColor.opacity(0.85)), lineWidth: 1)
            }
            if case let .marquee(a, b) = drag {
                let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
                ctx.fill(Path(rect), with: .color(S.orange.opacity(0.12)))
                ctx.stroke(Path(rect), with: .color(S.orange), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            // note repeat: the count over the step while the finger pulls down
            if case let .noteRepeat(pad, cellStart, _, _, count, _) = drag, let l = layout(for: pad, L) {
                let r = cellRect(Int((cellStart - pageStart) / max(1, cellTicks)), cw, l, size.width)
                let badge = CGRect(x: r.midX - 15, y: r.maxY + 3, width: 30, height: 18)
                ctx.fill(Path(roundedRect: badge, cornerRadius: 5), with: .color(Color.black.opacity(0.85)))
                ctx.stroke(Path(roundedRect: badge, cornerRadius: 5), with: .color(glowColor), lineWidth: 1)
                ctx.draw(Text("×\(count)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white),
                         at: CGPoint(x: badge.midX, y: badge.midY))
            }
        }
        .equatable()
        // the playhead runs on its own layer at the display's rate, so the grid never redraws for it
        .overlay(playhead(width: w).allowsHitTesting(false))
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityIdentifier("grid")
        .accessibilityValue("\(pattern.events.count) notes, \(selection.count) selected" + (SamplerWindow.probing ? rowsProbe(L) : ""))
        .bbMenuOpener(gridMenuOpener)
        .onContinuousHover { phase in
            // a trackpad or mouse pointer over a note lifts it (Tyrone, Oct 25)
            var over: NoteKey?
            if case .active(let p) = phase, drag.isIdle, let e = noteAt(p, w: w, L: L) { over = NoteKey(e) }
            if over != hoverNote { hoverNote = over }
        }
        .highPriorityGesture(DragGesture(minimumDistance: 0)
            .onChanged { g in if !pinching && !twoFinger { gridChanged(g, w: w, L: L) } }
            .onEnded { g in
                if pinching || twoFinger { drag = .none; work = nil; twoFinger = false } else { gridEnded(g, w: w, L: L) }
            })
        .simultaneousGesture(pinch)
        .background(GridScrollHook(
            began: { trackpad in
                panStart = origin
                if trackpad { return }
                switch drag {
                case .paint, .erase, .graph: _ = undoStack.popLast()
                default: break
                }
                drag = .none; work = nil; laneOrigin = nil
                twoFinger = true
            },
            sideways: { dx in scroll(to: (panStart ?? origin) - Double(dx / max(1, w)) * Double(windowTicks)) },
            ended: { panStart = nil },
            twoFingerTap: { points in
                // a two-finger tap or a right-click: the grid's menu (select all, copy, paste, octave up / down)
                // the tap is over: the next touch on the grid draws again even if no drag ended
                twoFinger = false; drag = .none; work = nil
                let hit = points.lazy.compactMap({ noteAt($0, w: w, L: L) }).first
                guard let p = points.first(where: { noteAt($0, w: w, L: L) != nil }) ?? points.first else { return }
                openGridMenu(at: p, hit: hit, w: w, L: L)
            }))
    }

    /// Right-click (or two-finger tap) on the grid (Tyrone, Oct 19): Select all, Copy, Paste, Octave up,
    /// Octave down, Delete (Oct 21), then the clicked track's STEPS (Oct 23, moved here from the track
    /// menu): Fill Every Step / 2 / 4 / 8 Steps and Clear Steps, each one undo. On a note that isn't
    /// selected, the note becomes the selection; an octave move leaves the note's ⊕ / ⊖ on it for more moves. Paste goes in at the clicked step, on the clicked track
    /// when the copied notes are all one track's.
    func openGridMenu(at p: CGPoint, hit: GrooveEvent?, w: CGFloat, L: [RowLayout]) {
        guard let l = layout(at: p.y, L) else { return }
        let pad = l.channel.pad
        selectedID = l.channel.id
        octaveNote = nil
        if let hit, !selection.contains(NoteKey(hit)) { selection = [NoteKey(hit)] }
        let keys = selection
        let limits = { (pad: Int) in controller.pitchLimits(pad: pad) }
        let canMove = { (by: Int) in !keys.isEmpty && PatternEdit.transpose(pattern, keys, by: by, limits: limits) != nil }
        let at = snapped(tickAt(p.x, w))
        func octave(_ by: Int) {
            if let hit { moveOctave(NoteKey(hit), by: by); return }
            guard let moved = PatternEdit.transpose(pattern, keys, by: 12 * by, limits: limits) else { return }
            commit(moved.0)
            selection = moved.1
        }
        var items: [BBMenuItem] = [
            .item("Select all", icon: "checkmark.rectangle.stack") {
                selection = Set(pattern.events.filter { Int($0.pad) == pad }.map(NoteKey.init))
            },
            .item("Copy", icon: "doc.on.doc", enabled: !keys.isEmpty) {
                let picked = pattern.events.filter { keys.contains(NoteKey($0)) }
                let first = picked.map(\.tick).min() ?? 0
                noteClipboard = picked.map { var e = $0; e.tick -= first; return e }
            },
            .item("Paste", icon: "doc.on.clipboard", enabled: !noteClipboard.isEmpty) {
                let onePad = Set(noteClipboard.map(\.pad)).count == 1
                let (pasted, newKeys) = PatternEdit.paste(pattern, noteClipboard, at: at, pad: onePad ? pad : nil)
                commit(pasted)
                selection = newKeys
            },
            .item("Octave up", icon: "arrow.up", enabled: canMove(12)) { octave(1) },
            .item("Octave down", icon: "arrow.down", enabled: canMove(-12)) { octave(-1) },
            .item("Delete", icon: "trash", enabled: !keys.isEmpty) { deleteSelection() },
        ]
        items.append(.header("Steps"))
        for (n, icon) in [(1, "square.grid.4x3.fill"), (2, "square.grid.3x3"), (4, "square.grid.2x2"), (8, "square")] {
            items.append(.item(n == 1 ? "Fill Every Step" : "Fill Every \(n) Steps", icon: icon) {
                // steps 1, 1+n, 1+2n... across the whole pattern; hits already on those steps keep their feel
                commit(PatternEdit.fillKeeping(pattern, pad: pad, every: PatternData.stepTicks * Int32(n), cell: PatternData.stepTicks, velocity: lastVelocity))
            })
        }
        items.append(.item("Clear Steps", icon: "xmark.square") { commit(PatternEdit.clearChannel(pattern, pad: pad)) })
        gridMenuOpener.show(at: p, title: l.channel.name, width: 240, items: items)
    }

    /// The playhead: a line moved every display frame from the engine's own clock (like Logic's),
    /// so it glides with the music and the grid never redraws for it. When it runs off the window
    /// while following, the window catches up with it at once.
    func playhead(width w: CGFloat) -> some View {
        let start = origin, ticks = Double(pageTicks)
        let controller = controller, loop = loop
        let length = Double(max(pattern.lengthTicks, 1))
        return PlayheadLine(color: UIColor(glowColor), clock: {
            guard controller.isPlaying, Int(controller.meters.status[1]) == loop, let t = controller.playheadTick else { return nil }
            return (t, controller.liveTempo / 60 * Double(PatternData.ppq), length)
        }, place: { t in CGFloat((t - start) / ticks) }, offScreen: { followPlayhead() })
    }

    /// The slot near the top of a step button (Tyrone's picture): dark when off, a glowing bar when lit.
    static func slot(in r: CGRect) -> CGRect {
        CGRect(x: r.minX + r.width * 0.16, y: r.minY + r.height * 0.15, width: r.width * 0.68, height: max(3, r.height * 0.1))
    }

    /// A step button inside its cell: gaps between the steps and between the rows, as in the render.
    func cellRect(_ c: Int, _ cw: CGFloat, _ l: RowLayout, _ w: CGFloat) -> CGRect {
        let gx = min(2.5, cw * 0.09), gy = l.bandH * 0.05
        return CGRect(x: x(pageStart, w) + CGFloat(c) * cw + gx, y: l.y + gy, width: cw - 2 * gx, height: l.bandH - 1.6 * gy)
    }

    /// The ON notes' glow (Tyrone, Oct 17): Platinum and Modern Black red, Vintage yellow, Texture blue.
    /// The buttons themselves stay silver on every face.
    var glowColor: Color {
        switch finish {
        case "vintage": return Color(red: 1, green: 0.82, blue: 0.22)
        case "texture": return Color(red: 0.25, green: 0.62, blue: 1)
        default: return Color(red: 1, green: 0.2, blue: 0.14)
        }
    }

    struct StepKey: Hashable { let pad: Int; let cell: Int }

    /// A row of step buttons in brushed steel: bevelled, each with its dark slot near the top. One
    /// fill per layer for the whole row; a lit button is drawn over its own.
    func drawMetalCells(_ ctx: GraphicsContext, _ rects: [CGRect]) {
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

    /// A note lifted off the plate under the pointer: its shadow on the plate, and where it now sits.
    func liftNote(_ ctx: GraphicsContext, _ r: CGRect) -> CGRect {
        ctx.drawLayer { g in
            g.addFilter(.shadow(color: Color.black.opacity(0.75), radius: 3, y: 2))
            g.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(Color.black.opacity(0.5)))
        }
        return r.offsetBy(dx: 0, dy: -1.5)
    }

    /// A lit step button: the same silver button, its slot lit as a bright bar of the mode's light
    /// (a roll's hits split the bar, a mark each). The metal stays silver in every mode.
    func drawLitStep(_ ctx: GraphicsContext, _ r: CGRect, glow: Color, level: Double, hits: Int) {
        let sl = Self.slot(in: r)
        ctx.fill(Path(roundedRect: sl.insetBy(dx: -1, dy: -1), cornerRadius: 2), with: .color(Color.black.opacity(0.8)))
        let n = max(1, min(hits, 8)), gap: CGFloat = n > 4 ? 0.8 : (n > 1 ? 1.5 : 0)
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
    func drawMetalNote(_ ctx: GraphicsContext, _ r: CGRect, tint: Color, level: Double) {
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

    func setZoom(_ level: Int) {
        let newLevel = max(0, min(Self.zoomSnaps.count - 1, level))
        guard newLevel != zoomLevel else { return }
        let center = origin + Double(pageTicks) / 2
        zoomLevel = newLevel
        viewStart = max(0, center - Double(windowTicks) / 2)
        snap = Self.zoomSnaps[newLevel]
        follow = false
    }

    var pinch: some Gesture {
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
}
