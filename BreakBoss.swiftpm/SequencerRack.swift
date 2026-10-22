// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Face 2: the editor area and the channel rack (track headers and rows).
extension SequencerView {
    // MARK: Editor: the rack and the grid on the picture's panels

    @ViewBuilder func editor(_ s: CGFloat) -> some View {
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
                Color.clear.frame(width: (A.panelX1 - A.rackX0) * s, height: contentH).id("rackTop")
                rackColumn(L, rowH: rowH, s: s).erased().frame(width: (A.rackX1 - A.rackX0) * s, height: contentH, alignment: .top)
                grid(L, width: gridW, rowH: rowH).erased().frame(width: gridW, height: contentH)
                    .offset(x: (A.gridX0 - A.rackX0) * s)
                // the dice at the end of every track: that track's steps only
                ForEach(L, id: \.channel.id) { l in trackButtons(l, rowH: rowH, s: s).erased() }
                noteOctaveGlyphs(L, gridW: gridW, s: s)
            }
        }
        .onAppear { proxy.scrollTo("rackTop", anchor: .top) }      // the first row at the top, always
        }
        .frame(width: (A.panelX1 - A.rackX0) * s, height: (A.rowsY1 - A.rowsY0) * s)
        .position(x: (A.rackX0 + A.panelX1) / 2 * s, y: (A.rowsY0 + A.rowsY1) / 2 * s)
        .onDrop(of: [.plainText, .fileURL, .audio], isTargeted: $rackTargeted) { providers in dropOnRack(providers, channel: nil) }
        if rackTargeted {
            RoundedRectangle(cornerRadius: 8 * s).stroke(accent, lineWidth: 2 * s).place([A.rackX0, A.rowsY0 - 4, A.rackX1, A.rowsY1], s).allowsHitTesting(false)
        }
    }

    /// The square buttons at the end of a track (the render's): dice = new steps for this track
    /// only, ✕ = clear this track in one tap.
    func trackButtons(_ l: RowLayout, rowH: CGFloat, s: CGFloat) -> some View {
        VStack(spacing: 3 * s) {
            SeqButton("SeqRowBtn", corner: 6, scale: s, action: { selectedID = l.channel.id; remember(); controller.randomizeChannel(loop: loop, pad: l.channel.pad); selection = [] }) {
                Image(systemName: "dice").font(.system(size: 15 * s)).foregroundColor(Color(white: 0.9))
            }
            .frame(width: 30 * s, height: 29 * s)
            .accessibilityIdentifier("trackDice\(l.channel.pad)")
            SeqButton("SeqRowBtn", corner: 6, scale: s, action: { selectedID = l.channel.id; commit(PatternEdit.clearChannel(pattern, pad: l.channel.pad)); selection = [] }) {
                Image(systemName: "xmark").font(.system(size: 14 * s, weight: .semibold)).foregroundColor(Color(white: 0.9))
            }
            .frame(width: 30 * s, height: 29 * s)
        }
        .offset(x: (A.gridX1 + 9 - A.rackX0) * s, y: l.y + (min(l.height, rowH) - 61 * s) / 2)
    }

    /// Where a note's ⊕ (over it) and ⊖ (under it) sit, in grid points, and their size.
    func octaveGlyphCenters(_ r: CGRect, gridW: CGFloat) -> (up: CGPoint, down: CGPoint, size: CGFloat) {
        let d = 30 * gridW / CGFloat(A.gridX1 - A.gridX0)
        return (CGPoint(x: r.midX, y: r.minY - d * 0.65), CGPoint(x: r.midX, y: r.maxY + d * 0.65), d)
    }
    /// True for a touch on the note's ⊕, false for its ⊖, nil for neither.
    func octaveGlyphHit(_ p: CGPoint, _ key: NoteKey, w: CGFloat, L: [RowLayout]) -> Bool? {
        guard let e = pattern.events.first(where: { NoteKey($0) == key }), visible(e), let r = noteRect(e, w: w, L) else { return nil }
        let c = octaveGlyphCenters(r, gridW: w), reach = c.size * 0.65
        if hypot(p.x - c.up.x, p.y - c.up.y) <= reach { return true }
        if hypot(p.x - c.down.x, p.y - c.down.y) <= reach { return false }
        return nil
    }

    /// ⊕ over the note and ⊖ under it after a two-finger tap (or a right-click) on it: the note goes
    /// up or down an octave, C1 to C8.
    @ViewBuilder func noteOctaveGlyphs(_ L: [RowLayout], gridW: CGFloat, s: CGFloat) -> some View {
        if let key = octaveNote, let e = pattern.events.first(where: { NoteKey($0) == key }), visible(e), let r = noteRect(e, w: gridW, L) {
            let c = octaveGlyphCenters(r, gridW: gridW), x0 = (A.gridX0 - A.rackX0) * s
            let keys = selection.contains(key) ? selection : [key]
            let canMove = { (by: Int) in PatternEdit.transpose(pattern, keys, by: by, limits: { controller.pitchLimits(pad: $0) }) != nil }
            let name = MusicScale.noteName(controller.baseNote(pad: Int(key.pad)) + Int(key.semis.rounded()))
            // pictures only: the grid's touch handles them (octaveGlyphHit), so a tap can't land on both
            octaveGlyphFace(true, size: c.size, enabled: canMove(12))
                .accessibilityLabel("Note up an octave").accessibilityValue(name).accessibilityIdentifier("noteOctaveUp")
                .position(x: x0 + c.up.x, y: c.up.y)
            octaveGlyphFace(false, size: c.size, enabled: canMove(-12))
                .accessibilityLabel("Note down an octave").accessibilityValue(name).accessibilityIdentifier("noteOctaveDown")
                .position(x: x0 + c.down.x, y: c.down.y)
        }
    }

    /// The graph dropped down under the open track: velocity bars, or pitch bars either side of a centre line.
    func drawGraph(_ ctx: GraphicsContext, _ l: RowLayout, width: CGFloat) {
        let top = l.graphTop, h = l.graphH
        let pad = l.channel.pad
        ctx.fill(Path(CGRect(x: 0, y: top, width: width, height: h)), with: .color(S.lane))
        for frac in [0.0, 1.0 / 3, 2.0 / 3, 1.0] {
            ctx.fill(Path(CGRect(x: 0, y: top + 4 + CGFloat(frac) * (h - 8), width: width, height: 1)), with: .color(S.stepLine))
        }
        var lt = ((pageStart + PatternData.ppq - 1) / PatternData.ppq) * PatternData.ppq
        while Double(lt) <= origin + Double(pageTicks) {
            let bx = x(lt, width)
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
            let color = (sel ? Color.white : glowColor).opacity(selection.isEmpty || sel ? 0.95 : 0.35)
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
    func ruler(width: CGFloat) -> some View {
        Canvas { ctx, size in
            ctx.clip(to: Path(CGRect(x: 0, y: -20, width: size.width, height: size.height + 40)))
            let px = { (t: Int32) in x(t, size.width) }
            var t = pageStart / PatternData.ppq * PatternData.ppq
            while Double(t) < origin + Double(pageTicks) {
                let bar = t / PatternEdit.barTicks + 1, beat = (t % PatternEdit.barTicks) / PatternData.ppq + 1
                let label = beat == 1 ? "\(bar)" : "\(bar).\(beat)"
                ctx.draw(Text(label).font(.system(size: size.height * 0.46, weight: beat == 1 ? .bold : .medium)).foregroundColor(beat == 1 ? .white : Color(white: 0.75)),
                         at: CGPoint(x: px(t) + size.height * 0.5, y: size.height * 0.42))
                t += PatternData.ppq
            }
            // where the window sits in the whole pattern
            if totalTicks > windowTicks {
                let x0 = CGFloat(origin / Double(totalTicks)) * size.width
                let w = max(24, CGFloat(windowTicks) / CGFloat(totalTicks) * size.width)
                ctx.fill(Path(roundedRect: CGRect(x: 0, y: size.height - 3, width: size.width, height: 3), cornerRadius: 1.5), with: .color(Color.white.opacity(0.12)))
                ctx.fill(Path(roundedRect: CGRect(x: x0, y: size.height - 3, width: w, height: 3), cornerRadius: 1.5), with: .color(glowColor))
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { g in
                if rulerDragStart == nil { rulerDragStart = origin }
                scroll(to: (rulerDragStart ?? 0) - Double(g.translation.width / max(1, width)) * Double(windowTicks))
            }
            .onEnded { _ in rulerDragStart = nil })
        .accessibilityElement()
        .accessibilityIdentifier("ruler")
    }

    // MARK: Channel rack (the picture's rows)

    func rackColumn(_ L: [RowLayout], rowH: CGFloat, s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // in pad order, not rack order: the rows keep their place in the view tree while a track
            // moves (each one sits at its own y), so nothing is torn down under the finger
            ForEach(L.sorted { $0.channel.pad < $1.channel.pad }, id: \.channel.id) { l in
                let moving = movingPad == l.channel.pad
                channelRow(l, rowH: rowH, s: s)
                .scaleEffect(moving ? 1.03 : 1)
                .shadow(color: .black.opacity(moving ? 0.6 : 0), radius: 8 * s, y: 4 * s)
                .offset(y: moving ? movingTop : l.y)
                .zIndex(moving ? 1 : 0)
            }
            if channels.count < Pad.count {
                let y = (L.last.map { $0.y + $0.height } ?? 0)
                VStack(spacing: 3 * s) {
                    Image(systemName: "plus.circle.dashed").font(.system(size: 18 * s)).foregroundColor(rackTargeted ? accent : inkColor.opacity(0.55))
                    Text(rackTargeted ? "DROP FOR A NEW CHANNEL" : "DROP A SOUND HERE").font(.system(size: 9 * s, weight: .semibold)).foregroundColor(rackTargeted ? accent : inkColor.opacity(0.55))
                }
                .frame(width: (A.rackX1 - A.rackX0) * s, height: rowH).offset(y: y)
            }
            // the grab strip over every track's studs: one UIKit view that never moves, so the grab
            // holds while the rows shift and the rack scrolls under the finger
            TrackGrabStrip(
                grip: { y in
                    let L = layouts(rowH: A.rowH * s)
                    guard let l = layout(at: y, L), y - l.y >= 4 * s, y - l.y < 56 * s else { return nil }
                    return l.channel.pad
                },
                began: { pad, y in grabBegan(pad, y: y, s: s) },
                moved: { y in grabMoved(y, s: s) },
                ended: { grabEnded() })
                .frame(width: Self.gripW * s, height: max(L.last.map { $0.y + $0.height } ?? 0, 1))
                .offset(x: 1 * s)
                .zIndex(2)
        }
    }

    /// The studs' touch area on the left of each tab (art x 1 to 15); the arrow has the rest.
    static let gripW: CGFloat = 14

    /// Where a dragged track lands: after every other track whose middle is above its middle.
    func dropIndex(pad: Int, centre: CGFloat, _ L: [RowLayout]) -> Int {
        L.filter { $0.channel.pad != pad && $0.y + $0.height / 2 < centre }.count
    }

    func grabBegan(_ pad: Int, y: CGFloat, s: CGFloat) {
        guard let l = layout(for: pad, layouts(rowH: A.rowH * s)) else { return }
        grabOrder = controller.rackOrder
        grabY = y
        movingFrom = l.y; movingTop = l.y
        movingPad = pad
        selectedID = l.channel.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// The track under the finger; the others make room as soon as it passes their middle.
    func grabMoved(_ y: CGFloat, s: CGFloat) {
        guard let pad = movingPad else { return }
        let L = layouts(rowH: A.rowH * s)
        guard let l = layout(for: pad, L) else { return }
        let bottom = L.map { $0.y + $0.height }.max() ?? 0
        movingTop = (movingFrom + y - grabY).clamped(0, max(0, bottom - l.height))
        let to = dropIndex(pad: pad, centre: movingTop + l.bandH / 2, L)
        if to != controller.rackOrder.firstIndex(of: pad) {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { controller.moveRackChannel(pad: pad, to: to) }
        }
    }

    /// Let go: the track settles into its slot, and UNDO puts the old order back.
    func grabEnded() {
        guard movingPad != nil else { return }
        if controller.rackOrder != grabOrder {
            undoStack.append(UndoStep(pattern: stored, rack: grabOrder))
            if undoStack.count > 100 { undoStack.removeFirst() }
            redoStack = []
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { movingPad = nil }
    }

    /// The silver tab on the left of a track header (Tyrone's Face 2 render): its ▶ opens the track's
    /// VELOCITY graph (or its piano roll). The two studs left of the arrow are the grab handle
    /// (SeqGrip_<face>, tools/sequencer_art/face2/build_grip.py); TrackGrabStrip takes their touches.
    func trackTab(_ l: RowLayout, s: CGFloat) -> some View {
        let ch = l.channel, pad = ch.pad
        let moving = movingPad == pad
        let isOpen = openID == ch.id || expandedID == ch.id
        return ZStack(alignment: .topLeading) {
            Image(systemName: "play.fill").font(.system(size: 17 * s, weight: .bold))
                .foregroundColor(isOpen ? selectColor : Color(white: 0.1))
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .shadow(color: isOpen ? selectColor.opacity(0.8) : .clear, radius: 3 * s)
                .offset(x: -3.5 * s)   // centred at x 21 of the row, just right of the studs
                .frame(width: (33 - Self.gripW) * s, height: 52 * s)
                .contentShape(Rectangle())
                .onTapGesture { toggleOpen(ch) }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(isOpen ? "Close \(ch.name)'s graph" : "Open \(ch.name)'s graph")
                .accessibilityIdentifier("trackArrow\(pad)")
                .accessibilityAction { toggleOpen(ch) }
                .offset(x: Self.gripW * s)
            Image("SeqGrip_\(finish)").resizable().frame(width: 10 * s, height: 24 * s)
                .offset(x: 2 * s, y: 13.5 * s)
                .shadow(color: moving ? selectColor.opacity(0.9) : .clear, radius: 3 * s)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel("Move \(ch.name)")
                .accessibilityIdentifier("trackGrip\(pad)")
            if moving {
                RoundedRectangle(cornerRadius: 6 * s).stroke(selectColor, lineWidth: 1.5 * s).shadow(color: selectColor.opacity(0.7), radius: 4 * s)
                    .frame(width: 33 * s, height: 52 * s)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 33 * s, height: 52 * s, alignment: .topLeading)
    }

    func channelRow(_ l: RowLayout, rowH: CGFloat, s: CGFloat) -> some View {
        let ch = l.channel, pad = ch.pad
        // a SOLO on another track silences this one too: its lamp goes dark the same as a mute
        let soloedOut = controller.soloPads.contains(true) && !controller.soloPads[pad]
        let muted = controller.mutedPads[pad] || soloedOut
        let isSel = selectedID == ch.id
        let ps = controller.state.pads[pad]
        func set(_ change: (inout PadSettings) -> Void) { var v = controller.state.pads[pad]; change(&v); controller.setPadSettings(pad, v) }
        // spots inside the row sprite (260 x 59, from the render's CLAP row): tab 1-33, dark body 33-259
        // (y 4-56), name from 43, LEVEL knob at 153, PAN knob at 202, lamp at 238 (all centred on y 29.5)
        return ZStack(alignment: .topLeading) {
            Image(rowSprite).resizable().frame(width: 260 * s, height: 59 * s)
                .opacity(newborn.contains(ch.id) ? 0 : 1)
                .allowsHitTesting(false)
            // a dropped sound: a pill in the face's colour grows into the track's body, then settles
            if newborn.contains(ch.id) || settling.contains(ch.id) {
                RoundedRectangle(cornerRadius: 7 * s).fill(accent)
                    .frame(width: (newborn.contains(ch.id) ? 52 : 226) * s, height: 52 * s)
                    .shadow(color: accent.opacity(0.8), radius: 8 * s)
                    .opacity(settling.contains(ch.id) && !newborn.contains(ch.id) ? 0.0 : 1)
                    .offset(x: 33 * s, y: 4 * s)
                    .allowsHitTesting(false)
            }
            // the selected track: lit all round (red, as in the renders)
            if isSel {
                RoundedRectangle(cornerRadius: 7 * s).stroke(selectColor, lineWidth: 1.6 * s).shadow(color: selectColor.opacity(0.7), radius: 4 * s)
                    .frame(width: 258 * s, height: 53 * s).offset(x: 1 * s, y: 3.5 * s).allowsHitTesting(false)
            }
            Text(ch.name).font(.system(size: 16 * s, weight: .medium)).foregroundColor(muted ? Color(white: 0.5) : (isSel ? selectColor : .white)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 89 * s, height: 52 * s, alignment: .leading).offset(x: 43 * s, y: 4 * s)
                .allowsHitTesting(false)
            // the body: tap selects the track; a right-click opens its menu beside the track (the studs on
            // its left move it)
            // (the offset stays inside the menu's button, as before #61: outside it the header wasn't hittable)
            Color.clear.contentShape(Rectangle()).frame(width: 100 * s, height: 52 * s).offset(x: 33 * s, y: 4 * s)
                // tapping the track that's already selected plays its sound (Tyrone, Oct 18)
                .bbTrackMenu(title: ch.name, finish: finish, extraWidth: 160 * s, tap: {
                    if selectedID == ch.id { controller.auditionPad(pad) }
                    selectedID = ch.id
                }) { trackMenu(ch) }
                .accessibilityIdentifier("trackHeader\(pad)")
            // the volume knob, bigger (Tyrone, Oct 19): −12 dB … 0 dB (100%) at the top; past 100% only in the SAMPLER
            ArtKnob(value: PadSettings.knob(level: ps.level), reset: 1,
                    hud: KnobHUD(title: "\(ch.name) · VOLUME", value: KnobHUD.volume(ps.level))) { v, _ in set { $0.level = PadSettings.level(knob: v) } }.frame(width: 46 * s, height: 46 * s)
                .accessibilityElement().accessibilityLabel("\(ch.name) volume").accessibilityValue(KnobHUD.volume(ps.level)).accessibilityIdentifier("trackVolume\(pad)")
                .offset(x: 130 * s, y: 6.5 * s)
            // the pan knob the same size as the volume knob (Tyrone, Oct 19: every header knob one size)
            ArtKnob(value: (ps.pan + 1) / 2, reset: 0.5,
                    hud: KnobHUD(title: "\(ch.name) · PAN", value: KnobHUD.pan(ps.pan))) { v, _ in let p = v * 2 - 1; set { $0.pan = abs(p) < 0.03 ? 0 : p } }.frame(width: 46 * s, height: 46 * s)
                .accessibilityElement().accessibilityLabel("\(ch.name) pan").accessibilityValue(KnobHUD.pan(ps.pan)).accessibilityIdentifier("trackPan\(pad)")
                .offset(x: 179 * s, y: 6.5 * s)
            // the lamp: on / off
            if muted { Circle().fill(Color(white: 0.12)).overlay(Circle().stroke(Color.black, lineWidth: 1)).frame(width: 13 * s, height: 13 * s).offset(x: 231.5 * s, y: 23 * s).allowsHitTesting(false) }
            Button { if soloedOut { controller.clearSolos() } else { controller.toggleMute(pad) } } label: { Color.clear.frame(width: 30 * s, height: 40 * s).contentShape(Rectangle()) }
                .buttonStyle(SeqPress()).offset(x: 223 * s, y: 9.5 * s)
            // the tab: ▶ opens and closes this track's VELOCITY graph (or its PITCH piano roll); its studs move the track
            trackTab(l, s: s).frame(width: 33 * s, height: 52 * s).offset(x: 1 * s, y: 4 * s)
            if l.pitch != nil {
                scaleToolbar(l, s: s).offset(y: rowH)
                pitchKeys(l, s: s).offset(y: rowH + toolbarH(rowH))
            }
            if l.graphH > 0 {
                // the graph's header: VELOCITY | PITCH | OFFSET | CHANCE (PITCH opens the piano roll); the dice gives new velocities
                VStack(alignment: .leading, spacing: 10 * s) {
                    laneSwitch(ch, s: s)
                    HStack(spacing: 6 * s) {
                        Text(lane.hint).font(.system(size: 9 * s, weight: .medium)).foregroundColor(Color(white: 0.55)).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        SeqButton("SeqRowBtn", corner: 6, scale: s, action: {
                            commit(PatternEdit.randomizeVelocity(pattern, pad: pad, keys: selection, seed: UInt64.random(in: 1...UInt64.max)))
                        }) {
                            Image(systemName: "dice.fill").font(.system(size: 14 * s)).foregroundColor(.white)
                        }
                        .frame(width: 36 * s, height: 30 * s)
                    }
                }
                .padding(.horizontal, 10 * s)
                .frame(width: 260 * s, height: l.graphH - 6 * s, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7 * s).fill(Color(white: 0.04))
                    .overlay(RoundedRectangle(cornerRadius: 7 * s).stroke(Color(white: 0.3), lineWidth: 1)))
                .offset(y: rowH)
            }
        }
        .frame(width: (A.rackX1 - A.rackX0) * s, height: l.height, alignment: .topLeading)
        .background(rowTargeted == ch.id ? accent.opacity(0.25) : Color.clear)
        .onDrop(of: [.plainText, .fileURL, .audio], isTargeted: Binding(get: { rowTargeted == ch.id }, set: { rowTargeted = $0 ? ch.id : nil })) { providers in
            dropOnRack(providers, channel: ch)
        }
    }
}
