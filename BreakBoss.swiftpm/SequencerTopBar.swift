// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Face 2: the top bar (tools, UNDO/REDO, transport, BPM, BARS, SNAP, SWING, HUMANIZE, TEMPO SYNC).
extension SequencerView {
    // MARK: Top bar

    @ViewBuilder func topBar(_ s: CGFloat) -> some View {
        // DRAW / SELECT / ERASE: real buttons from the picture, the active one lit in the face's colour
        ForEach(0..<3, id: \.self) { i in
            let t: Tool = [.draw, .select, .erase][i]
            let on = tool == t
            SeqButton("SeqBtnTool", lit: on ? accent : nil, corner: 8, scale: s, action: { tool = t }) {
                HStack(spacing: 6 * s) {
                    Image(systemName: ["pencil", "rectangle.dashed", "eraser"][i]).font(.system(size: 16 * s, weight: .medium))
                    Text(["DRAW", "SELECT", "ERASE"][i]).font(.system(size: 16 * s, weight: .medium))
                }
                .foregroundColor(on ? accent : .white)
            }
            .place(A.tools[i], s)
        }
        SeqButton("SeqBtnTool", corner: 8, scale: s, action: { undo() }) {
            HStack(spacing: 6 * s) { Image(systemName: "arrow.uturn.backward").font(.system(size: 16 * s, weight: .medium)); Text("UNDO").font(.system(size: 16 * s, weight: .medium)) }
                .foregroundColor(undoStack.isEmpty ? Color(white: 0.5) : .white)
        }
        .keyboardShortcut("z", modifiers: .command)
        .accessibilityIdentifier("undoButton")
        .place(A.undo, s)
        SeqButton("SeqBtnTool", corner: 8, scale: s, action: { redo() }) {
            HStack(spacing: 6 * s) { Image(systemName: "arrow.uturn.forward").font(.system(size: 16 * s, weight: .medium)); Text("REDO").font(.system(size: 16 * s, weight: .medium)) }
                .foregroundColor(redoStack.isEmpty ? Color(white: 0.5) : .white)
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
        .accessibilityIdentifier("redoButton")
        .place(A.redo, s)
        // bars pager
        artText(pageLabel, A.pageText, s, size: 21, weight: .medium, color: inkColor).accessibilityIdentifier("pageLabel")
        SeqGlyph(symbol: "chevron.left", size: 21, scale: s, enabled: origin > 0, color: inkColor) { scroll(to: (origin - Double(windowTicks)).rounded(.down)) }.place(A.pageBack, s)
        SeqGlyph(symbol: "chevron.right", size: 21, scale: s, enabled: origin < Double(maxStart), color: inkColor) { scroll(to: (origin + Double(windowTicks)).rounded(.down)) }.place(A.pageForward, s)
        // transport
        SeqButton("SeqBtnTransport", corner: 8, scale: s, action: { controller.stopPlayback() }) {
            RoundedRectangle(cornerRadius: 2 * s).fill(Color(white: 0.92)).frame(width: 21 * s, height: 21 * s)
        }
        .place(A.stop, s)
        EngineTicking(tick: engineTick) {
            SeqButton("SeqBtnTransport", lit: isThisPlaying ? accent : nil, corner: 8, scale: s, action: { controller.playPattern(loop) }) {
                Image(systemName: "play.fill").font(.system(size: 24 * s)).foregroundColor(isThisPlaying ? accent : Color(white: 0.92))
                    .shadow(color: isThisPlaying ? accent : .clear, radius: 5 * s)
            }
        }
        .place(A.play, s)
        EngineTicking(tick: engineTick) {
            SeqButton("SeqBtnTransport", lit: controller.recording ? S.red : nil, corner: 8, scale: s, action: { if !controller.recording { remember() }; controller.toggleRecordPads(loop: loop) }) {
                if controller.countingIn {
                    Text("\(controller.countInBeatsLeft)").font(.system(size: 24 * s, weight: .bold, design: .rounded)).foregroundColor(S.red)
                } else {
                    Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.35, blue: 0.3), S.red], center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 14 * s))
                        .frame(width: 25 * s, height: 25 * s).shadow(color: controller.recording ? S.red : .clear, radius: 6 * s)
                }
            }
        }
        .place(A.rec, s)
        // TEMPO SYNC and FOLLOW DAW (the same switches as Face 1's LEDs): lit when on
        hostSwitch("TEMPO SYNC", .tempoSync, A.tempoSync, s)
        hostSwitch("FOLLOW DAW", .followDAW, A.followDAW, s)
        // tempo, bars, gear, cloud
        // tempo: slide up for faster, down for slower; a tap opens the tempo panel
        EngineTicking(tick: engineTick) {
            SeqChip(sprite: "SeqChipBpm", text: "\(Int((controller.tempoIsExternal ? controller.liveTempo : controller.state.bpm).rounded())) BPM", size: 17, leading: 24, trailing: 52, scale: s, color: tempoDragStart == nil ? .white : accent)
        }
            .accessibilityIdentifier("tempoChip")
            .bbPanelPlaced(A.bpm, s, title: "Tempo", width: 340) { TempoPanel(controller: controller) }
            // the slide sits outside the tap's button (inside it, the button kept the drag and the tempo never moved)
            .highPriorityGesture(DragGesture(minimumDistance: 6)
                .onChanged { g in
                    guard !controller.tempoIsExternal else { return }
                    if tempoDragStart == nil { tempoDragStart = controller.state.bpm }
                    let bpm = ((tempoDragStart ?? 120) - Double(g.translation.height) / 3).rounded()
                    if bpm != controller.state.bpm { controller.setBPM(min(280, max(40, bpm))) }
                }
                .onEnded { _ in tempoDragStart = nil })
        SeqChip(sprite: "SeqChipBars", text: "\(bars) BARS", size: 17, leading: 18, trailing: 52, scale: s)
            .accessibilityIdentifier("barsChip")
            .bbMenuPlaced(A.bars, s, title: "Pattern length") {
                [2, 4, 8, 16].map { b in BBMenuItem.item("\(b) BARS", checked: bars == b) { commit(PatternEdit.setLength(pattern, bars: b)) } }
            }
        SeqArt(sprite: "SeqBtnGear", corner: 8, scale: s) { EmptyView() }
            .bbMenuPlaced(A.gear, s, title: "Sequencer", width: 330) { settingsItems() }
        SeqArt(sprite: "SeqBtnCloud", corner: 9, scale: s) { EmptyView() }
            .bbMenuPlaced(A.cloud, s, title: "MIDI", width: 360) {
                [.header("MIDI file"),
                 BBMenuItem.item("Share this pattern as a MIDI file", detail: "12 tracks, one per channel, pitch and velocity", icon: "square.and.arrow.up", enabled: exportURL != nil) { shareMIDI = true },
                 .header("MIDI out")] + midiOutItems()
            }
        // snap, scale, swing, humanize
        SeqChip(sprite: "SeqChipSnap", text: snapLabel, size: 16, leading: 87, trailing: 44, scale: s)
            .bbMenuPlaced(A.snap, s, title: "Snap", width: 300) {
                Self.snapChoices.flatMap { group -> [BBMenuItem] in
                    [.header(group.section)] + group.items.map { item in BBMenuItem.item(item.0, checked: item.1 == snap) { snap = item.1 } }
                }
            }
        // SNAP TO SCALE: a tuning fork on the SNAP chip's left end (lit when on)
        Image(systemName: "tuningfork").font(.system(size: 14 * s, weight: .semibold)).foregroundColor(controller.snapToScale ? accent : Color(white: 0.55))
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .bbMenu(title: "Snap to scale", width: 300) { scaleItems(selectedPad) }
            .place(A.snapScale, s)
        SeqChip(sprite: "SeqChipSwing", text: swingLabel, size: 16, leading: 89, trailing: 52, scale: s).place(A.swing, s).allowsHitTesting(false)
        PressGlow().bbPanelPlaced([A.swing[0], A.swing[1], A.swingKnob[0] - 4, A.swing[3]], s, title: "Swing", width: 320) {
                BBSlider(value: Double(50 + controller.value(.bounce) * 22), range: 50...72, step: 1, label: { $0 <= 50 ? "OFF" : "\(Int($0))%" }) {
                    controller.set(.bounce, Float(($0 - 50) / 22))
                }
            }
        artKnob(A.swingKnob, s, value: controller.value(.bounce), hud: KnobHUD(title: "SWING", value: swingLabel)) { v, ended in
            if swingStart == nil { swingStart = controller.value(.bounce) }
            controller.set(.bounce, v)
            if ended { swingStart = nil }
        }
        SeqArt(sprite: "SeqChipHumanize", corner: 8, scale: s) { EmptyView() }.place(A.humanize, s).allowsHitTesting(false)
        PressGlow().bbPanelPlaced([A.humanize[0], A.humanize[1], A.humanizeKnob[0] - 4, A.humanize[3]], s, title: "Humanize", width: 320) {
                BBSlider(value: Double((pattern.humanize ?? 0) * 100), range: 0...100, step: 1, label: { $0 < 1 ? "OFF" : "\(Int($0))%" }) { v in
                    remember(coalescing: true)
                    var p = pattern
                    p.humanize = v < 1 ? nil : Float(v / 100)
                    controller.setLoop(loop, p)
                }
            }
        artText((pattern.humanize ?? 0) < 0.01 ? "" : "\(Int((pattern.humanize ?? 0) * 100))%", [A.humanizeKnob[0] - 22, A.humanize[1], A.humanizeKnob[0] - 2, A.humanize[3]], s, size: 10, color: accent, align: .trailing)
        artKnob(A.humanizeKnob, s, value: pattern.humanize ?? 0,
                hud: KnobHUD(title: "HUMANIZE", value: (pattern.humanize ?? 0) < 0.01 ? "OFF" : "\(Int((pattern.humanize ?? 0) * 100))%")) { v, ended in
            if humanizeStart == nil { humanizeStart = pattern.humanize ?? 0; undoStack.append(step(pattern)); redoStack = [] }
            var p = pattern
            p.humanize = v < 0.01 ? nil : v
            work = p
            if ended { humanizeStart = nil; work = nil; controller.setLoop(loop, p) }
        }
    }

    /// A host transport switch on the top rail: its lamp and name, green when on.
    func hostSwitch(_ title: String, _ p: KParam, _ r: [Double], _ s: CGFloat) -> some View {
        let on = controller.value(p) > 0.5
        return SeqButton("SeqBtnHost", lit: on ? accent : nil, corner: 8, scale: s, action: { controller.toggle(p) }) {
            HStack(spacing: 7 * s) {
                Circle().fill(on ? accent : Color(white: 0.42)).frame(width: 9 * s, height: 9 * s)
                    .overlay(Circle().stroke(Color(white: 0.65), lineWidth: on ? 0 : 1 * s))
                    .shadow(color: on ? accent : .clear, radius: 3 * s)
                Text(title).font(.system(size: 15 * s, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundColor(on ? accent : .white)
        }
        .accessibilityIdentifier(p == .tempoSync ? "tempoSyncButton" : "followDAWButton")
        .place(r, s)
    }

    func settingsItems() -> [BBMenuItem] {
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

    var swingLabel: String { controller.value(.bounce) < 0.01 ? "OFF" : "\(Int(50 + controller.value(.bounce) * 22))%" }

    var pageLabel: String {
        let bar = Int(pageStart / PatternEdit.barTicks) + 1
        if zoomLevel == 0 {
            let last = min(bars, Int((pageStart + windowTicks - 1) / PatternEdit.barTicks) + 1)
            return last == bar ? "BAR \(bar)" : "BARS \(bar)-\(last)"
        }
        let beat = Int((pageStart % PatternEdit.barTicks) / PatternData.ppq) + 1
        return zoomLevel == 1 ? "BAR \(bar) · ZOOM" : "BAR \(bar).\(beat) · ZOOM"
    }
}
