// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Face 2: the SAMPLER window over the sequencer, the lane switch, the piano roll's toolbar and keys, MIDI out.
extension SequencerView {
    // MARK: The SAMPLER window

    func openSampler(_ pad: Int) {
        if let ch = channel(pad: pad) { selectedID = ch.id }
        withAnimation(.easeOut(duration: 0.2)) { samplerPad = pad; samplerMinimized = false }
    }

    /// The open track's SAMPLER window over Face 2 (or, minimized, a tab in the corner that brings it back).
    @ViewBuilder var samplerOverlay: some View {
        if let pad = samplerPad {
            if samplerMinimized {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { withAnimation(.easeOut(duration: 0.2)) { samplerMinimized = false } } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "waveform")
                                Text(String(format: "SAMPLER  CH %02d", (controller.rackOrder.firstIndex(of: pad) ?? pad) + 1))
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(MetalTone.of(finish).ink)
                            .padding(.horizontal, 14).frame(height: 36)
                            .background(SamplerMetal(tone: MetalTone.of(finish), corner: 8))
                        }
                        .buttonStyle(SeqPress())
                        .accessibilityIdentifier("samplerRestore")
                    }
                }
                .padding(16)
                .transition(.opacity)
            } else {
                // a window over the sequencer (Tyrone, Oct 18): drag the title bar to move it, the corner to resize it
                GeometryReader { g in
                    let aspect = SamplerWindow.artW / SamplerWindow.artH
                    let maxW = max(320, min(g.size.width - 16, (g.size.height - 16) * aspect))
                    let minW = min(480, maxW)
                    let w = (samplerW > 0 ? CGFloat(samplerW) : g.size.width * 0.62).clamped(minW, maxW)
                    let h = w / aspect
                    let x0 = samplerX >= 0 ? CGFloat(samplerX) : (g.size.width - w) / 2
                    let y0 = samplerY >= 0 ? CGFloat(samplerY) : (g.size.height - h) / 2
                    let drag = samplerDrag
                    // where the window lands with the drag in it (the title bar stays on screen)
                    let spot = { SamplerWindowPlacement.spot(x0: x0, y0: y0, width: w, minWidth: minW, maxWidth: maxW, bounds: g.size, drag: drag) }
                    SamplerWindow(controller: controller, pad: pad, finish: finish,
                                  close: { withAnimation(.easeIn(duration: 0.15)) { samplerPad = nil } },
                                  minimize: { withAnimation(.easeIn(duration: 0.15)) { samplerMinimized = true } },
                                  switchTo: { openSampler($0) },
                                  importFile: { importPad = pad },
                                  drop: { dropOnRack($0, channel: channel(pad: pad)) },
                                  swing: pattern.swing(pad: pad), shift: pattern.shift(pad: pad),
                                  setFeel: { sw, sh, _ in
                                      // MISC's SWING / SHIFT: the track's own swing and push / pull, one undo per turn
                                      var p = pattern
                                      if let sw { p.setSwing(pad: pad, sw) }
                                      if let sh { p.setShift(pad: pad, sh) }
                                      guard p != pattern else { return }
                                      remember(coalescing: true)
                                      work = nil
                                      controller.setLoop(loop, p)
                                  },
                                  move: { t, done in
                                      drag.move = t
                                      guard done else { return }
                                      let p = spot()
                                      samplerX = Double(p.x)
                                      samplerY = Double(p.y)
                                      drag.move = .zero
                                  })
                        .id(pad)
                        .frame(width: w, height: h)
                        .overlay(alignment: .bottomTrailing) {
                            SamplerResizeGrip(tone: MetalTone.of(finish))
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { v in drag.grow = max(v.translation.width, v.translation.height * aspect) }
                                    .onEnded { v in
                                        drag.grow = max(v.translation.width, v.translation.height * aspect)
                                        let p = spot()
                                        samplerW = Double(p.width)
                                        if samplerX < 0 { samplerX = Double(p.x); samplerY = Double(p.y) }
                                        drag.grow = 0
                                    })
                                .accessibilityIdentifier("samplerResize")
                        }
                        .modifier(SamplerWindowPlacement(drag: drag, x0: x0, y0: y0, width: w, minWidth: minW, maxWidth: maxW, bounds: g.size))
                }
                .environment(\.seqFinish, finish)
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
    }

    /// The arrow: open this track (closing any other), or close it.
    func toggleOpen(_ ch: WorkspaceChannel) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if openID == ch.id {
                openID = nil; expandedID = nil
            } else {
                openID = ch.id; expandedID = lane == .pitch ? ch.id : nil
            }
        }
        selectedID = ch.id
    }

    /// VELOCITY, OFFSET and CHANCE show the bars graph under the steps; PITCH shows the notes on a piano roll.
    func setLane(_ l: Lane, _ ch: WorkspaceChannel) {
        withAnimation(.easeInOut(duration: 0.22)) {
            lane = l
            openID = ch.id
            expandedID = l == .pitch ? ch.id : nil
        }
        selectedID = ch.id
    }

    func laneSwitch(_ ch: WorkspaceChannel, s: CGFloat) -> some View {
        HStack(spacing: 5 * s) {
            ForEach(Lane.allCases, id: \.self) { l in
                let on = lane == l && openID == ch.id
                Button { setLane(l, ch) } label: {
                    Text(l.short).font(.system(size: 11 * s, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundColor(on ? .black : .white)
                        .frame(width: 55 * s, height: 26 * s)
                        .background(RoundedRectangle(cornerRadius: 4 * s).fill(on ? laneColor : Color(white: 0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 4 * s).stroke(on ? laneColor : Color(white: 0.38), lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SeqPress())
                .accessibilityIdentifier(l.testID)
            }
        }
    }

    /// KEY · SCALE · SNAP · FIT for the open track's piano roll.
    func scaleToolbar(_ l: RowLayout, s: CGFloat) -> some View {
        let pad = l.channel.pad
        let h = toolbarH(A.rowH * s)
        func chip<Content: View>(_ w: CGFloat, lit: Bool = false, @ViewBuilder _ c: () -> Content) -> some View {
            c().font(.system(size: 9 * s, weight: .semibold)).foregroundColor(lit ? .black : .white).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: w * s, height: A.rowH * s * 0.62 - 6 * s)
                .background(RoundedRectangle(cornerRadius: 5 * s).fill(lit ? glowColor : Color(white: 0.14)))
                .overlay(RoundedRectangle(cornerRadius: 5 * s).stroke(lit ? glowColor : Color(white: 0.3), lineWidth: 1))
                .contentShape(Rectangle())
        }
        return VStack(alignment: .leading, spacing: 5 * s) {
        laneSwitch(l.channel, s: s)
        HStack(spacing: 4 * s) {
            chip(56) { Text("KEY \(MusicScale.noteNames[controller.scaleRoot])") }
                .bbMenu(title: "Key", width: 200) { MusicScale.noteNames.enumerated().map { i, n in BBMenuItem.item(n, checked: controller.scaleRoot == i) { controller.setScale(root: i) } } }
            chip(78) { Text(controller.scale.name.components(separatedBy: " ").first ?? controller.scale.name) }
                .bbMenu(title: "Scale", width: 260) { MusicScale.all.map { sc in BBMenuItem.item(sc.name, checked: controller.scale.name == sc.name) { controller.setScale(name: sc.name) } } }
            Button { controller.setScale(snap: !controller.snapToScale) } label: { chip(44, lit: controller.snapToScale) { Text("SNAP") } }.buttonStyle(SeqPress())
            Button {
                let base = controller.baseNote(pad: pad)
                let limits = controller.pitchLimits(pad: pad)
                var p = pattern
                for i in p.events.indices where Int(p.events[i].pad) == pad {
                    let n = controller.scale.snap(base + Int(p.events[i].semis.rounded()), root: controller.scaleRoot)
                    p.events[i].semis = Float((n - base).clamped(limits.lowerBound, limits.upperBound))
                }
                commit(p)
            } label: { chip(36) { Text("FIT") } }.buttonStyle(SeqPress())
        }
        .frame(height: A.rowH * s * 0.62)
        }
        .padding(.leading, 6 * s)
        .frame(width: (A.rackX1 - A.rackX0) * s, height: h, alignment: .leading)
        .background(Color(white: 0.06))
    }

    func pitchKeys(_ l: RowLayout, s: CGFloat) -> some View {
        let range = l.pitch ?? 0...0
        let base = controller.baseNote(pad: l.channel.pad)
        return VStack(spacing: 0) {
            ForEach(Array(range.reversed()), id: \.self) { sm in
                let note = base + sm
                let inScale = controller.scale.contains(note, root: controller.scaleRoot)
                let isRoot = (note - controller.scaleRoot) % 12 == 0
                HStack {
                    Spacer()
                    Text(MusicScale.noteName(note)).font(.system(size: 9 * s, design: .monospaced))
                        .foregroundColor(isRoot ? lit : (inScale ? Color(white: 0.15) : Color(white: 0.5)))
                    Text(sm == 0 ? "·" : (sm > 0 ? "+\(sm)" : "\(sm)")).font(.system(size: 8 * s, design: .monospaced)).foregroundColor(Color(white: 0.4)).frame(width: 22 * s, alignment: .trailing)
                }
                .padding(.trailing, 12 * s).frame(height: l.pitchRowH)
                .background(isRoot ? lit.opacity(0.25) : (inScale ? Color.clear : Color.black.opacity(0.12)))
            }
        }
        .frame(width: (A.rackX1 - A.rackX0) * s, height: CGFloat(range.count) * l.pitchRowH, alignment: .top)
        // ⊕ / ⊖: the keys up or down an octave, C1 to C8
        .overlay(alignment: .topLeading) {
            let pad = l.channel.pad, bottom = rollBottom(pad), keys = "\(MusicScale.noteName(bottom)) to \(MusicScale.noteName(bottom + rollSpan(pad)))"
            VStack(spacing: 6 * s) {
                octaveGlyph(true, size: 30 * s, enabled: bottom + rollSpan(pad) < MusicScale.highestNote) { shiftRoll(pad, octaves: 1) }
                    .accessibilityLabel("Keys up an octave").accessibilityValue(keys).accessibilityIdentifier("rollOctaveUp")
                octaveGlyph(false, size: 30 * s, enabled: bottom > MusicScale.lowestNote) { shiftRoll(pad, octaves: -1) }
                    .accessibilityLabel("Keys down an octave").accessibilityValue(keys).accessibilityIdentifier("rollOctaveDown")
            }
            .padding(.leading, 40 * s).padding(.top, 6 * s)
        }
    }

    /// A plus or minus in a see-through circle (Tyrone, Oct 18): the piano roll's octave buttons.
    func octaveGlyph(_ up: Bool, size: CGFloat, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) { octaveCircle(up, size: size).contentShape(Circle()) }
            .buttonStyle(SeqPress())
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.35)
    }
    func octaveCircle(_ up: Bool, size: CGFloat) -> some View {
        Image(systemName: up ? "plus" : "minus").font(.system(size: size * 0.48, weight: .bold)).foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(0.1)))
            .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.6), radius: 2)
    }
    /// The note's ⊕ / ⊖: the picture, a button to VoiceOver and tests; touches go to the grid under it.
    func octaveGlyphFace(_ up: Bool, size: CGFloat, enabled: Bool) -> some View {
        octaveCircle(up, size: size)
            .opacity(enabled ? 1 : 0.35)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
    }


    /// Drop from the library (or a file from Files) onto the rack.
    func dropOnRack(_ providers: [NSItemProvider], channel: WorkspaceChannel?) -> Bool {
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

    func place(_ sound: LibrarySound, on channel: WorkspaceChannel?) {
        if let channel {
            controller.replaceRackSound(channel.id, with: sound)
            selectedID = channel.id
        } else if let row = controller.addRackChannel(sound) {
            selectedID = row.id
            animateIn(row.id)
        }
        userSounds = UserSoundLibrary.sounds()
    }

    func animateIn(_ id: UUID) {
        newborn.insert(id)
        settling.insert(id)
        DispatchQueue.main.async {
            // 1. the dot grows into the oval  2. the glow fades, the real row is underneath
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { _ = newborn.remove(id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.35)) { _ = settling.remove(id) }
            }
        }
    }

    /// The track's menu (Tyrone's mockup, Oct 21): Track Settings, Open Sample Editor, Solo, Load
    /// Sample, Clear Sample. The STEPS fills live in the grid's right-click menu (Oct 23).
    func trackMenu(_ ch: WorkspaceChannel) -> TrackMenuPanel {
        let pad = ch.pad
        return TrackMenuPanel(
            controller: controller, pad: pad,
            settings: { selectedID = ch.id; trackSettingsID = ch.id },
            openEditor: { openSampler(pad) },
            loadSample: { importPad = pad },
            clearSample: {
                // only the loaded sample goes: the track keeps its notes, level, pan and sampler settings
                var ps = controller.state.pads[pad]; ps.sampleFile = nil; controller.setPadSettings(pad, ps)
            })
    }

    // MARK: MIDI out

    func midiOutLabel(_ pad: Int) -> String {
        let ch = controller.midiOutChannels[pad]
        return ch < 0 ? "MIDI OFF" : "MIDI \(ch + 1)"
    }

    func midiOutItems() -> [BBMenuItem] {
        var items: [BBMenuItem] = [
            BBMenuItem.item(controller.midiOutOn ? "MIDI out is ON" : "Turn MIDI out on", icon: "power", checked: controller.midiOutOn) {
                controller.setMIDIOut(!controller.midiOutOn)
            },
            .header("Routing"),
            BBMenuItem.item("One track: every channel on MIDI channel 1, notes 36–47", icon: "1.circle") { controller.setMIDIOutOneTrack() },
            BBMenuItem.item("Multi-out: each channel on its own MIDI channel (1–12)", icon: "square.stack.3d.down.right") { controller.setMIDIOutLayout(multi: true) },
            BBMenuItem.item("All drums on MIDI channel 10 (GM), the 808 on 7", icon: "10.circle") { controller.setMIDIOutLayout(multi: false) },
            .header("Channels"),
        ]
        for ch in channels {
            items.append(.submenu("\(ch.name)  ·  \(midiOutLabel(ch.pad))  ·  \(MusicScale.noteName(controller.midiOutNotes[ch.pad]))", midiOutChannelItems(ch.pad)))
        }
        return items
    }

    func midiOutChannelItems(_ pad: Int) -> [BBMenuItem] {
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
}
