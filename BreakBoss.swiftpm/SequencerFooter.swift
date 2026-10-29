// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Face 2: the bottom rail (PATTERN, KIT, FX knobs), UNDO and follow, and small shared pieces.
extension SequencerView {
    // MARK: Footer (pattern, kit)

    var orderedKits: [KitDefinition] { KitLibrary.browserOrder(for: controller.mode) }

    @ViewBuilder func footer(_ s: CGFloat) -> some View {
        // the way back to Face 1: slide the knob (the pads' squares) to the right
        FaceSlider(scale: s, color: accent) { dismiss() }.place(A.slider, s)
        // power: the sequencer and pads all the way on or off
        PowerButton(on: controller.powerOn, scale: s, color: accent) { controller.togglePower() }.place(A.power, s)
        // PATTERN (moved left, Oct 17; the label and dividers are printed on the plate)
        SeqButton("SeqArrowBack", corner: 7, scale: s) { cycleLoop(-1) }.place(A.patternBack, s)
        SeqButton("SeqArrowFwd", corner: 7, scale: s) { cycleLoop(1) }.place(A.patternForward, s)
        SeqChip(sprite: "SeqChipPattern", text: controller.state.presetName, size: 17, leading: 16, trailing: 44, scale: s)
            .bbHardwarePlaced(A.patternChip, s, title: "Patterns", finish: finish, id: "patternChip") {
                PatternBrowserPanel(controller: controller) { loop = 0; selection = [] }
            }
        // KIT
        SeqButton("SeqArrowBack", corner: 7, scale: s) { cycleKit(-1) }.place(A.kitBack, s)
        SeqButton("SeqArrowFwd", corner: 7, scale: s) { cycleKit(1) }.place(A.kitForward, s)
        SeqChip(sprite: "SeqChipKit", text: controller.state.kitName, size: 17, leading: 16, trailing: 44, scale: s)
            .bbHardwarePlaced(A.kitChip, s, title: "Kits", finish: finish, id: "kitChip") { KitBrowserPanel(controller: controller) }
        fxKnobs(s)
    }

    /// The FX knobs on the bottom rail. They morph with the mode (Tyrone, Oct 17; TrackFX.params).
    /// DELAY's double tap locks it to the tempo or frees it. With a track selected on the rack
    /// they turn that track's own FX (Tyrone, Oct 19); Face 1's knobs stay the main chain's.
    static func fxParams(_ mode: SoundMode) -> [KParam] { TrackFX.params(mode) }

    /// A double tap on DELAY: locked to the tempo (a dotted 1/8) or free (300 ms).
    func toggleDelaySync() {
        controller.set(.delaySync, controller.value(.delaySync) > 0.5 ? 0 : 1, show: false)
    }

    static func fxLabel(_ p: KParam) -> String {
        switch p {
        case .analogEQ: return "ANALOG EQ"
        case .textureDelay: return "DELAY"
        case .gatedReverb: return "REVERB"
        case .reverbDecay: return "DECAY"
        case .reverbPredelay: return "PRE-DELAY"
        default: return p.name.uppercased()
        }
    }

    @ViewBuilder func fxKnobs(_ s: CGFloat) -> some View {
        let params = Self.fxParams(controller.mode)
        // the selected track's own knobs; none selected: the main chain's, as on Face 1
        let track = selected
        let value: (KParam) -> Float = { p in track.map { controller.trackFX($0.pad, p) } ?? controller.value(p) }
        let slot = (A.fxX1 - A.fxX0) / 8
        let x0 = A.fxX0 + Double(8 - params.count) * slot / 2          // seven knobs sit centred in the eight places
        ForEach(Array(params.enumerated()), id: \.element.rawValue) { i, p in
            let cx = x0 + slot * (Double(i) + 0.5)
            let turning = fxTurning == p
            let synced = controller.value(.delaySync) > 0.5
            HStack(spacing: 4 * s) {
                if p == .textureDelay {
                    // DELAY's tempo lamp: lit while it's locked to the tempo (double tap the knob)
                    Circle().fill(synced ? accent : Color(white: 0.3)).frame(width: 6 * s, height: 6 * s)
                        .shadow(color: synced ? accent : .clear, radius: 2 * s)
                }
                Text(turning ? p.text(value(p)) : Self.fxLabel(p))
                    .font(.system(size: 12 * s, weight: .semibold)).foregroundColor(turning ? accent : inkColor)
                    .lineLimit(1).minimumScaleFactor(0.55)
            }
            .frame(width: (slot - 2) * s, height: (A.fxLabelY1 - A.fxLabelY0) * s)
            .place([cx - slot / 2 + 1, A.fxLabelY0, cx + slot / 2 - 1, A.fxLabelY1], s)
            .allowsHitTesting(false)
            let h = A.fxKnobY1 - A.fxKnobY0
            ArtKnob(value: value(p), grip: 8 * s,
                    doubleTap: p == .textureDelay ? toggleDelaySync : nil,
                    hud: KnobHUD(title: track.map { "\($0.name) · \(Self.fxLabel(p))" } ?? "MAIN · \(Self.fxLabel(p))", value: p.text(value(p)))) { v, ended in
                fxTurning = ended ? nil : p
                if let track { controller.setTrackFX(track.pad, p, v) } else { controller.set(p, v) }
            }
            .place([cx - h / 2 - 8, A.fxKnobY0 - 8, cx + h / 2 + 8, A.fxKnobY1 + 8], s)
            .accessibilityElement()
            .accessibilityLabel(Self.fxLabel(p))
            .accessibilityValue(p.text(value(p)))
            .accessibilityIdentifier("fx_\(p.id)")
        }
    }

    func cycleKit(_ step: Int) {
        let kits = orderedKits
        guard !kits.isEmpty else { return }
        let i = kits.firstIndex { $0.id == controller.state.kitID } ?? 0
        controller.selectKit(kits[(i + step + kits.count) % kits.count])
    }

    func cycleLoop(_ step: Int) {
        let all = PatternBank.browserOrder(for: controller.mode)      // the arrows walk the PATTERNS menu, genre by genre
        guard !all.isEmpty else { return }
        let i = all.firstIndex { $0.name == controller.state.presetName } ?? -1
        controller.loadPatternPreset(all[(i + step + all.count) % all.count]); loop = 0; selection = []
    }

    func duplicate() {
        if selection.isEmpty {
            commit(PatternEdit.copyNext(pattern, fromBar: 0, bars: bars))
        } else {
            let (p, keys) = PatternEdit.duplicate(pattern, selection)
            commit(p)
            selection = keys
        }
    }

    func clear() {
        if selection.isEmpty {
            var p = pattern; p.events = []; commit(p)
        } else {
            commit(PatternEdit.remove(pattern, selection))
            selection = []
        }
    }

    func writeMIDI() -> URL? {
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

    /// UI tests (BREAKBOSS_UI_PROBE): the grid's lanes top to bottom as the grid lays them out, each
    /// "pad:notes@y" (the notes drawn in that lane, its top in points), so a test can see a track's
    /// steps go with it when it moves.
    func rowsProbe(_ L: [RowLayout]) -> String {
        "; rows " + L.map { l in "\(l.channel.pad):\(pattern.events.filter { Int($0.pad) == l.channel.pad }.count)@\(Int(l.y))" }.joined(separator: " ") + "; grab" + TrackGrabStrip.trace
    }

    // MARK: Undo, follow

    func commit(_ p: PatternData) {
        work = nil
        guard p != stored else { return }
        undoStack.append(step(stored))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
        controller.setLoop(loop, p)
    }

    /// Keeps the pattern as it is now so UNDO brings it back: for changes made outside the grid (the dice,
    /// generate, recording, the presets' pattern). A slider coalesces its moves into one undo.
    func remember(coalescing: Bool = false) {
        let now = Date()
        defer { rememberedAt = coalescing ? now : nil }
        if coalescing, let at = rememberedAt, now.timeIntervalSince(at) < 1 { return }
        undoStack.append(step(stored))
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }

    func step(_ p: PatternData) -> UndoStep { UndoStep(pattern: p, rack: controller.rackOrder) }

    func restore(_ u: UndoStep) {
        if u.pattern != stored { controller.setLoop(loop, u.pattern) }
        if u.rack != controller.rackOrder {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { controller.setRackOrder(u.rack) }
        }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(step(pattern))
        restore(last)
        selection = []
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(step(pattern))
        restore(next)
        selection = []
    }

    func followPlayhead() {
        guard follow, isThisPlaying, let t = controller.playheadTick, case .none = drag else { return }
        let t32 = Int32(t)
        if Double(t32) < origin || Double(t32) >= origin + Double(pageTicks) { viewStart = Double(min(maxStart, t32 / pageTicks * pageTicks)) }
    }

    // MARK: Small pieces

    func box(lit: Bool, color: Color? = nil) -> some View {
        let color = color ?? self.lit
        return RoundedRectangle(cornerRadius: 6)
            .fill(lit ? (color == self.lit ? litDark : color.opacity(0.25)) : S.button)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(lit ? color.opacity(0.9) : S.border, lineWidth: lit ? 1.5 : 1))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
    }

    var divider: some View { Rectangle().fill(S.border).frame(width: 1, height: 30) }

    func iconBox(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 16, weight: .medium)).foregroundColor(S.text)
            .frame(width: 40, height: 40).background(box(lit: false))
    }

    func chip(_ text: String, width: CGFloat) -> some View {
        HStack {
            Text(text).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(S.text).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundColor(S.text)
        }
        .padding(.horizontal, 12).frame(width: width, height: 40).background(box(lit: false))
    }

    /// SNAP TO SCALE (FL Studio's scales): on / off, the key, the scale, and fitting a track's notes.
    func scaleItems(_ pad: Int?) -> [BBMenuItem] {
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
                let limits = controller.pitchLimits(pad: pad)
                var p = pattern
                for i in p.events.indices where Int(p.events[i].pad) == pad {
                    let n = controller.scale.snap(base + Int(p.events[i].semis.rounded()), root: controller.scaleRoot)
                    p.events[i].semis = Float((n - base).clamped(limits.lowerBound, limits.upperBound))
                }
                commit(p)
            })
        }
        return items
    }

    func labelBox(_ icon: String?, _ title: String?, lit: Bool = false, enabled: Bool = true) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).font(.system(size: 15, weight: .medium)) }
            if let title { Text(title).font(.system(size: 13, weight: .medium, design: .monospaced)) }
        }
        .foregroundColor(lit ? self.lit : (enabled ? S.text : S.dim))
        .padding(.horizontal, 12).frame(height: 40).background(box(lit: lit))
    }
}
