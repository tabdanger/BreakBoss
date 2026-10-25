// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Face 2: touches on the grid, and the graph (lane) under the open track.
extension SequencerView {
    // MARK: Grid gestures

    func noteAt(_ p: CGPoint, w: CGFloat, L: [RowLayout]) -> GrooveEvent? {
        guard let l = layout(at: p.y, L) else { return nil }
        let pad = l.channel.pad
        if l.pitch == nil {
            // a step row: the step button under the finger, the same cell the grid lights (a longer note
            // or a hit just past a step's edge never answers for the step beside it)
            let at = stepStart(at: p.x, w)
            return pattern.events.last { Int($0.pad) == pad && visible($0) && $0.tick >= at && $0.tick < at + cellTicks }
        }
        return pattern.events.last { e in
            Int(e.pad) == pad && visible(e) && (noteRect(e, w: w, L)?.insetBy(dx: -4, dy: l.pitch == nil ? -4 : -1).contains(p) ?? false)
        }
    }

    /// The first tick of the step button under x (the cells the grid draws, gaps belong to the step left of them).
    func stepStart(at x: CGFloat, _ w: CGFloat) -> Int32 {
        let c = max(1, cellTicks)
        let cell = Int(((x - self.x(pageStart, w)) / max(1, cellWidth(w))).rounded(.down))
        return pageStart + Int32(max(0, cell)) * c
    }
    /// Where a new note goes for a touch at x: the SNAP grid, kept inside the step button pressed in a
    /// step row, so a coarse SNAP (a beat, 1/8, triplets) never lights the step beside the finger.
    func placeTick(at x: CGFloat, _ w: CGFloat, _ l: RowLayout?) -> Int32 {
        let t = snapped(tickAt(x, w))
        guard let l, l.pitch == nil else { return t }
        let at = stepStart(at: x, w)
        guard at < pattern.lengthTicks else { return t }
        return min(max(t, at), at + max(1, cellTicks) - 1, max(pattern.lengthTicks, 1) - 1)
    }

    func gridChanged(_ g: DragGesture.Value, w: CGFloat, L: [RowLayout]) {
        defer {
            switch drag {
            case .paint, .long808: trace = Trace(from: g.startLocation, at: g.location)
            default: if trace != nil { trace = nil }
            }
        }
        if case .none = drag {
            // the note's ⊕ / ⊖ are drawn over the grid; the grid's own touch takes them
            if let key = octaveNote, let up = octaveGlyphHit(g.startLocation, key, w: w, L: L) {
                drag = .octave
                moveOctave(key, by: up ? 1 : -1)
                return
            }
            if octaveNote != nil { octaveNote = nil }
            touchDown = g.time
            let start = g.startLocation
            guard let l = layout(at: start.y, L) else { return }
            if inBand(start.y, l) { selectedID = l.channel.id; return }
            if inToolbar(start.y, l) { return }
            if inGraph(start.y, l) {
                // the dropped-down graph: drag the bars (velocity or pitch, whichever is showing)
                laneOrigin = pattern; undoStack.append(step(pattern)); redoStack = []
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
                    drag = .long808(start: placeTick(at: start.x, w, l), semis: sem)
                } else {
                    let t = placeTick(at: start.x, w, l)
                    undoStack.append(step(pattern)); redoStack = []
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
                undoStack.append(step(pattern)); redoStack = []
                drag = .erase
            }
        }
        switch drag {
        case .graph:
            graphChanged(g, w: w)
        case .tapOnNote(let key):
            if let l = layout(at: g.startLocation.y, L), pullsDown(g, l), let hit = pattern.events.first(where: { NoteKey($0) == key }) {
                startRepeat(pad: l.channel.pad, like: hit, fromPaint: false)
                gridChanged(g, w: w, L: L)
            } else if hypot(g.translation.width, g.translation.height) > 8 {
                let inSelection = selection.contains(key)
                let l = layout(at: g.startLocation.y, L)
                let s0 = l.map { Int(semis(at: g.startLocation.y, in: $0).rounded()) } ?? 0
                drag = .move(keys: inSelection ? selection : [key], origin: pattern,
                             startTick: tickAt(g.startLocation.x, w), startSemis: s0, followSelection: inSelection)
                gridChanged(g, w: w, L: L)
            }
        case .paint(let pad, let sem, let lastCell):
            // pressed an empty step and pulled straight down: the new note repeats
            let startCell = Int(placeTick(at: g.startLocation.x, w, layout(for: pad, L)) / placeTicks)
            if let l = layout(for: pad, L), l.pitch == nil, lastCell == startCell, pullsDown(g, l),
               let hit = noteAt(g.startLocation, w: w, L: L) {
                startRepeat(pad: pad, like: hit, fromPaint: true)
                gridChanged(g, w: w, L: L)
                return
            }
            // a quick drag from an empty spot draws a selection box, as in SELECT (Tyrone, Oct 19); hold the
            // finger still a moment first to paint a run of notes instead. On a step row a sideways swipe
            // fills the steps it crosses at once (swipe-to-fill, Tyrone, Oct 25)
            let swipe = layout(for: pad, L)?.pitch == nil && abs(g.translation.width) > abs(g.translation.height)
            if lastCell == startCell, !swipe, hypot(g.translation.width, g.translation.height) > 8,
               g.time.timeIntervalSince(touchDown) < 0.35 {
                work = nil
                _ = undoStack.popLast()
                drag = .marquee(start: g.startLocation, current: g.location)
                return
            }
            // painting inside an open piano roll follows the finger's pitch
            let l = layout(for: pad, L)
            // a step that only rolls or drifts as the finger lifts stays the one step pressed; painting a
            // run of steps starts once the finger really moves
            if l?.pitch == nil, lastCell == startCell, hypot(g.translation.width, g.translation.height) <= 10 { return }
            let t = placeTick(at: g.location.x, w, l)
            let cell = Int(t / placeTicks)
            let s = l?.pitch != nil ? controller.scaleSnapped(semis(at: g.location.y, in: l!), pad: pad) : sem
            if (cell != lastCell || s != sem) && Double(t) >= origin && Double(t) < origin + Double(pageTicks) {
                var p = pattern
                // a fast swipe along a step row skips steps between two touches: they fill too
                if l?.pitch == nil, abs(cell - lastCell) > 1 {
                    for c in stride(from: lastCell + (cell > lastCell ? 1 : -1), to: cell, by: cell > lastCell ? 1 : -1) {
                        let ct = Int32(c) * placeTicks
                        if ct < p.lengthTicks && Double(ct) >= origin { p = PatternEdit.addNote(p, pad: pad, tick: ct, velocity: lastVelocity, semis: s) }
                    }
                }
                work = PatternEdit.addNote(p, pad: pad, tick: t, velocity: lastVelocity, semis: s)
                drag = .paint(pad: pad, semis: s, lastCell: cell)
            }
        case .long808:
            break
        case .noteRepeat(let pad, let cellStart, let like, let origin, let count, let fromPaint):
            let counts = PatternEdit.repeatCounts(cell: cellTicks)
            let have = origin.events.filter { Int($0.pad) == pad && $0.tick >= cellStart && $0.tick < cellStart + cellTicks }.count
            let at = counts.lastIndex { $0 <= max(1, have) } ?? 0
            let notch = max(14, (layout(for: pad, L)?.bandH ?? 40) * 0.3)
            let steps = Int(((g.translation.height - 6) / notch).rounded(.down)) + 1
            let n = counts[max(0, min(counts.count - 1, at + steps))]
            if n != count || work == nil {
                work = PatternEdit.repeatStep(origin, pad: pad, cellStart: cellStart, cell: cellTicks, count: n, like: like)
                drag = .noteRepeat(pad: pad, cellStart: cellStart, like: like, origin: origin, count: n, fromPaint: fromPaint)
            }
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
        case .none, .octave:
            break
        }
    }

    /// A finger that went down on a step and is heading straight down (more down than sideways).
    func pullsDown(_ g: DragGesture.Value, _ l: RowLayout) -> Bool {
        guard l.pitch == nil, g.startLocation.y < l.y + l.bandH else { return false }
        return g.translation.height > 6 && g.translation.height > abs(g.translation.width) * 1.3
    }

    /// Hold a step and pull down (Logic's Drum Machine Designer note repeat): the further down, the
    /// more even hits share the step, and its slot shows a light for each.
    func startRepeat(pad: Int, like: GrooveEvent, fromPaint: Bool) {
        let c = max(1, cellTicks)
        let cellStart = like.tick / c * c
        drag = .noteRepeat(pad: pad, cellStart: cellStart, like: like, origin: pattern, count: 0, fromPaint: fromPaint)
        work = nil
        selectedID = channels.first { $0.pad == pad }?.id ?? selectedID
    }

    /// The 808 note a held draw makes: from where the finger went down to the step under it now, at the
    /// pitch under it in the piano roll (its trace shows the same note). A tap gives the last length.
    func long808Note(start: Int32, semis sem: Float, from a: CGPoint, at p: CGPoint, w: CGFloat, L: [RowLayout]) -> (Int32, Float) {
        let end = snapped(tickAt(p.x, w))
        let length = max(placeTicks, (end > start ? end - start : 0) + placeTicks)
        let len = abs(p.x - a.x) < 6 ? last808Length : length
        let pad = Pad.bass808.rawValue
        guard let l = layout(for: pad, L), l.pitch != nil, p.y >= l.pitchTop, p.y < l.y + l.height else { return (len, sem) }
        return (len, controller.scaleSnapped(semis(at: p.y, in: l), pad: pad))
    }

    /// Where the shadow of the note being drawn sits: in the piano roll, the step and key under the
    /// finger; on the 808, the whole note from where the finger went down.
    func traceRect(_ L: [RowLayout], w: CGFloat) -> CGRect? {
        guard let tr = trace else { return nil }
        let e: GrooveEvent
        switch drag {
        case .paint(let pad, _, _):
            guard let l = layout(for: pad, L), l.pitch != nil, tr.at.y >= l.pitchTop, tr.at.y < l.y + l.height else { return nil }
            e = GrooveEvent(tick: snapped(tickAt(tr.at.x, w)), pad: Int8(pad), velocity: lastVelocity,
                            semis: controller.scaleSnapped(semis(at: tr.at.y, in: l), pad: pad))
        case .long808(let start, let sem):
            let (len, s) = long808Note(start: start, semis: sem, from: tr.from, at: tr.at, w: w, L: L)
            e = GrooveEvent(tick: start, pad: Int8(Pad.bass808.rawValue), velocity: lastVelocity, semis: s, length: len)
        default:
            return nil
        }
        guard visible(e) else { return nil }
        return noteRect(e, w: w, L)
    }

    func gridEnded(_ g: DragGesture.Value, w: CGFloat, L: [RowLayout]) {
        defer { drag = .none; trace = nil }
        switch drag {
        case .tapOnNote(let key):
            commit(PatternEdit.remove(pattern, [key]))
            selection.remove(key)
        case .long808(let start, let sem):
            let (len, s) = long808Note(start: start, semis: sem, from: g.startLocation, at: g.location, w: w, L: L)
            last808Length = len
            commit(PatternEdit.addNote(pattern, pad: Pad.bass808.rawValue, tick: start, length: len, velocity: lastVelocity, semis: s))
        case .paint, .erase:
            if let p = work { work = nil; controller.setLoop(loop, p) }
            else { _ = undoStack.popLast() }
        case .noteRepeat(_, _, _, _, _, let fromPaint):
            // from an empty step the undo was kept when the note went in
            if fromPaint { if let p = work { work = nil; controller.setLoop(loop, p) } }
            else if let p = work { commit(p) } else { work = nil }
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
        case .none, .octave:
            break
        }
    }

    // MARK: The graph under the open track


    /// A drag in the graph under the open track.
    func graphChanged(_ g: DragGesture.Value, w: CGFloat) {
        guard case let .graph(pad, top, h) = drag else { return }
        let v = Float(1 - (g.location.y - top - 4) / (h - 8)).clamped(0, 1)
        let keys = Set(pattern.events.filter { e in
            visible(e) && Int(e.pad) == pad && abs(x(e.tick, w) + 5 - g.location.x) <= 8 && (selection.isEmpty || selection.contains(NoteKey(e)))
        }.map(NoteKey.init))
        guard !keys.isEmpty else { return }
        apply(graphValue: v, to: keys, pad: pad)
    }

    /// Sets velocity, pitch, note offset or chance (whichever graph is showing) on the notes under the finger.
    func apply(graphValue v: Float, to keys: Set<NoteKey>, pad: Int) {
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
}
