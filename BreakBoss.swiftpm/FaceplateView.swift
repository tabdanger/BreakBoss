// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - The faceplate
//
// The three approved faceplate images are the design (MODERN, VINTAGE, TEXTURE); pressing a
// mode button swaps the whole plate. Nothing is redrawn in a different style: the plates carry
// every label, button and pad, and this view only adds what has to move (knob pointers, the
// screen, the BPM digits, kit / preset names, lit / unlit buttons, pad flashes) and the touch
// areas. Positions come from Resources/KnockLayout.json, measured from the images.

struct FaceplateView: View {
    @ObservedObject var controller: KnockController
    /// Used by build-machine snapshots; normal app presentation follows the device idiom.
    var deviceOverride: FaceplateLayout.Device? = nil

    /// Build machine only: the offscreen renderer can't draw drop-down menus, so snapshots leave
    /// them out (they're invisible tap areas on the iPad anyway).
    static var snapshotMode = false

    @State private var editor: EditorTarget?
    @State private var showExport = false
    @State private var showMenu = false
    @State private var patternEditor: PatternTarget?
    @State private var browser: BrowserView.Kind?
    @State private var namePrompt: NamePrompt?
    @State private var nameText = ""

    struct EditorTarget: Identifiable {
        let pad: Int
        let loop: Bool
        var id: Int { pad * 2 + (loop ? 1 : 0) }
    }

    struct PatternTarget: Identifiable {
        let loop: Int
        var id: Int { loop }
    }

    enum NamePrompt: Identifiable {
        case preset, kit
        var id: Int { self == .preset ? 0 : 1 }
    }

    var body: some View {
        GeometryReader { geo in
            let mode = controller.mode
            let device = deviceOverride ?? (UIDevice.current.userInterfaceIdiom == .phone ? .phone : .tablet)
            if let layout = FaceplateLayout.forFace(controller.faceKey, device: device) ?? FaceplateLayout.forMode(mode, device: device) {
                if layout.isPhone && geo.size.width > geo.size.height {
                    // Keep the portrait instrument large enough to use after rotation.
                    // The artwork stays proportional and every row remains reachable.
                    let s = min(geo.size.width, max(360, geo.size.height * 1.05)) / layout.width
                    ScrollView(.vertical) {
                        plate(layout, mode: mode, s: s)
                            .frame(width: layout.width * s, height: layout.height * s)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    let s = min(geo.size.width / layout.width, geo.size.height / layout.height)
                    plate(layout, mode: mode, s: s)
                        .frame(width: layout.width * s, height: layout.height * s)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            } else {
                Text("The faceplate artwork is missing from the app.")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .bbMenuHost()
        .background(Color.black.ignoresSafeArea())
        .background(spaceBar)
        .sheet(item: $editor) { target in
            if target.loop {
                LoopEditorView(controller: controller, loop: target.pad)
            } else {
                PadEditorView(controller: controller, pad: target.pad)
            }
        }
        .sheet(isPresented: $showExport) { ExportView(controller: controller) }
        .sheet(isPresented: $showMenu) { MenuView(controller: controller) }
        .fullScreenCover(item: $patternEditor) { target in DrumRollView(controller: controller, loop: target.loop) }
        .fullScreenCover(item: $browser) { kind in BrowserView(controller: controller, kind: kind) }
        .alert(namePrompt == .kit ? "Save Kit" : "Save Preset", isPresented: Binding(
            get: { namePrompt != nil }, set: { if !$0 { namePrompt = nil } })) {
            TextField("Name", text: $nameText)
            Button("Save") {
                if namePrompt == .kit { controller.saveKit(as: nameText) } else { controller.savePreset(as: nameText) }
                namePrompt = nil
            }
            Button("Cancel", role: .cancel) { namePrompt = nil }
        } message: {
            Text(namePrompt == .kit ? "Saves the 12 pads (your samples and pad settings) as a kit."
                                    : "Saves the whole faceplate: mode, knobs, kit and loops.")
        }
    }

    /// Space bar (hardware keyboard) = PLAY / STOP in the standalone app. In a DAW the space
    /// bar belongs to the DAW, so the plug-in leaves it alone.
    @ViewBuilder private var spaceBar: some View {
        if !controller.isPlugin && patternEditor == nil {
            Button("") { controller.playPressed() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func plate(_ L: FaceplateLayout, mode: SoundMode, s: CGFloat) -> some View {
        let sfx = controller.faceKey
        ZStack(alignment: .topLeading) {
            Image(L.plateImageName(face: sfx))
                .resizable()
                .interpolation(.high)
                .frame(width: L.width * s, height: L.height * s)
            topLeft(L, sfx: sfx, s: s)
            knobs(L, sfx: sfx, s: s)
            transport(L, sfx: sfx, s: s)
            windows(L, s: s)
            pads(L, s: s)
        }
    }

    /// Screen, ONE-SHOT / LOOP and the three mode buttons (each mode is its own faceplate).
    @ViewBuilder
    private func topLeft(_ L: FaceplateLayout, sfx: String, s: CGFloat) -> some View {
        ScopeView(controller: controller, scale: L.isPhone ? s * 1.3 : s)
            .place(L.scope, s)
        if controller.playMode == .oneShot {
            Image(L.overlayName("oneshot_on", sfx)).resizable().place(L.oneShotButton, s)
            Image(L.overlayName("loop_off", sfx)).resizable().place(L.loopButton, s)
        }
        hit(L.oneShotButton, s) { controller.selectPlayMode(.oneShot) }
        hit(L.loopButton, s) { controller.selectPlayMode(.loop) }
        ForEach(SoundMode.allCases, id: \.rawValue) { m in
            if let r = L.modeButtons[m.assetSuffix] { hit(r, s) { controller.selectMode(m) } }
        }
    }

    /// The 14 knobs and the CLIPPER button.
    @ViewBuilder
    private func knobs(_ L: FaceplateLayout, sfx: String, s: CGFloat) -> some View {
        ForEach(KnobControl.order, id: \.rawValue) { p in
            if let k = L.knobs[p.id] {
                KnobControl(controller: controller, param: p, knob: k, scale: s)
            }
        }
        if controller.value(.clipper) < 0.5 {
            Image(L.overlayName("clipper_off", sfx)).resizable().place(L.clipperRect, s)
        }
        hit(L.clipperRect, s) { controller.toggle(.clipper) }
        hit(L.exportRect, s) { showExport = true }
        if let r = L.editorRect {
            hit(r, s) {
                // Opens on the loop that's playing, otherwise loop 1.
                let current = Int(controller.meters.status[1])
                patternEditor = PatternTarget(loop: (0..<Pad.count).contains(current) ? current : 0)
            }
        }
        hit(L.menuRect, s) { showMenu = true }
    }

    /// PLAY, BPM, TEMPO SYNC, FOLLOW DAW, dice.
    @ViewBuilder
    private func transport(_ L: FaceplateLayout, sfx: String, s: CGFloat) -> some View {
        PlayButtonView(controller: controller, image: L.overlayName("play_on", sfx), rect: L.playRect, scale: s)
        BPMDisplay(controller: controller, layout: L, scale: s)
        if controller.value(.tempoSync) < 0.5 { Image(L.overlayName("led_off", sfx)).resizable().place(L.leds.tempoSyncRect, s) }
        if controller.value(.followDAW) < 0.5 { Image(L.overlayName("led_off", sfx)).resizable().place(L.leds.followDAWRect, s) }
        hit(ledHitRect(L, L.leds.tempoSyncRect), s) { controller.toggle(.tempoSync) }
        hit(ledHitRect(L, L.leds.followDAWRect), s) { controller.toggle(.followDAW) }
        hit(L.diceRect, s) { controller.dice() }
    }

    /// KITS and PRESETS windows, and SAVE.
    @ViewBuilder
    private func windows(_ L: FaceplateLayout, s: CGFloat) -> some View {
        NameWindow(text: controller.loadingKit ? "LOADING..." : controller.kitDisplayName,
                   textRect: L.kitText, color: L.textColor, scale: s)
        if !FaceplateView.snapshotMode { kitsMenu.place(L.kitBox, s) }
        NameWindow(text: controller.state.presetName,
                   textRect: L.presetText,
                   color: L.textColor, scale: s)
        if !FaceplateView.snapshotMode { presetsMenu.place(L.presetBox, s) }
        hit(L.saveRect, s) {
            nameText = controller.state.presetName == "INIT" ? "" : controller.state.presetName.capitalized
            namePrompt = .preset
        }
    }

    /// The 12 pads.
    private func pads(_ L: FaceplateLayout, s: CGFloat) -> some View {
        ForEach(0..<L.pads.count, id: \.self) { i in
            PadView(controller: controller, pad: L.padIndex(forLayoutPosition: i), rect: L.pads[i], scale: s) { loopEditor in
                editor = EditorTarget(pad: L.padIndex(forLayoutPosition: i), loop: loopEditor)
            }
        }
    }

    private func width(_ r: [Double], _ s: CGFloat) -> CGFloat { (r[2] - r[0]) * s }
    private func height(_ r: [Double], _ s: CGFloat) -> CGFloat { (r[3] - r[1]) * s }

    /// LED plus its printed label (the overlay rect plus label is about 5 overlay-widths).
    private func ledHitRect(_ L: FaceplateLayout, _ r: [Double]) -> [Double] {
        let w = r[2] - r[0]
        return [r[0], r[1], r[0] + w * 5, r[3]]
    }

    private func hit(_ r: [Double], _ s: CGFloat, action: @escaping () -> Void) -> some View {
        PressableArea(action: action)
            .frame(width: width(r, s), height: height(r, s))
            .place(r, s)
    }

    // MARK: Menus

    /// KITS: the drum sounds, grouped by mode, plus your own kits. (BreakBoss menu, not Apple's.)
    func kitMenuItems() -> [BBMenuItem] {
        var items: [BBMenuItem] = []
        for mode in SoundMode.allCases {
            items.append(.submenu("\(mode.title) kits", icon: "square.grid.3x3",
                KitLibrary.kits(for: mode).map { def in
                    BBMenuItem.item(def.name, detail: "\(Int(def.tempo)) BPM", checked: def.id == controller.state.kitID && controller.state.userKit == nil) {
                        controller.selectKit(def)
                    }
                }))
        }
        if !controller.userKits.isEmpty {
            items.append(.submenu("My kits", icon: "person.crop.square", controller.userKits.map { name in
                BBMenuItem.item(name, checked: controller.state.userKit == name) { controller.selectUserKit(name) }
            }))
        }
        items.append(.item("Save Kit As…", icon: "square.and.arrow.down") {
            nameText = controller.state.userKit ?? ""; namePrompt = .kit
        })
        if !controller.userKits.isEmpty {
            items.append(.submenu("Delete a Kit", icon: "trash", controller.userKits.map { name in
                BBMenuItem.item(name, destructive: true) { controller.deleteUserKit(name) }
            }))
        }
        return items
    }

    /// PRESETS: patterns, grouped by style (Danger Patterns first), plus your own presets.
    func presetMenuItems() -> [BBMenuItem] {
        var items: [BBMenuItem] = [.item("INIT", checked: controller.state.presetName == "INIT") { controller.loadInit() }]
        for style in PatternBank.styles {
            items.append(.submenu(style, icon: style == "Danger Patterns" ? "bolt.fill" : "music.note.list",
                PatternBank.presets(in: style).map { p in
                    BBMenuItem.item(p.name, detail: "\(Int(p.bpm)) BPM\(p.swing > 50.5 ? " · \(Int(p.swing))% SWING" : "")",
                          checked: controller.state.presetName == p.name) { controller.loadPatternPreset(p) }
                }))
        }
        if !controller.userPresets.isEmpty {
            items.append(.submenu("My presets", icon: "person.crop.square", controller.userPresets.map { name in
                BBMenuItem.item(name) { controller.loadUserPreset(name) }
            }))
            items.append(.submenu("Delete a Preset", icon: "trash", controller.userPresets.map { name in
                BBMenuItem.item(name, destructive: true) { controller.deleteUserPreset(name) }
            }))
        }
        return items
    }

    private var kitsMenu: some View {
        Color.white.opacity(0.001).contentShape(Rectangle()).onTapGesture { browser = .kits }
    }

    private var presetsMenu: some View {
        Color.white.opacity(0.001).contentShape(Rectangle()).onTapGesture { browser = .presets }
    }
}

// MARK: - Placement helpers

extension View {
    /// Sizes and places a view over a rectangle given in faceplate pixels.
    func place(_ r: [Double], _ s: CGFloat) -> some View {
        let rect = FaceplateLayout.rect(r)
        return self
            .frame(width: rect.width * s, height: rect.height * s)
            .position(x: rect.midX * s, y: rect.midY * s)
    }
}

/// An invisible button that darkens a little while pressed (like a real button going in).
struct PressableArea: View {
    let action: () -> Void
    @State private var down = false

    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(down ? 0.22 : 0.001))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !down { down = true } }
                    .onEnded { g in
                        down = false
                        if abs(g.translation.width) < 40 && abs(g.translation.height) < 40 { action() }
                    }
            )
    }
}

// MARK: - Knobs

struct KnobControl: View {
    @ObservedObject var controller: KnockController
    let param: KParam
    let knob: FaceplateLayout.Knob
    let scale: CGFloat
    @State private var start: Float?

    static let order: [KParam] = [.pitch, .tune, .bounce, .velocity, .filter, .clipDrive, .output,
                                  .boost, .punch, .analogEQ, .grit, .shine, .tighten, .noise]

    /// Pointer travel: 135° either side of straight up, like the printed scale.
    static func angle(_ v: Float) -> Double { -135 + 270 * Double(v) }

    var body: some View {
        let r = knob.r * scale
        let v = controller.value(param)
        ZStack {
            Circle().fill(Color.white.opacity(0.001))
            KnobPointer(angle: KnobControl.angle(v), inner: knob.pointerInner, outer: knob.pointerOuter, width: 0.13)
                .fill(Color(white: 0.04))
                .frame(width: r * 2, height: r * 2)
            KnobPointer(angle: KnobControl.angle(v), inner: knob.pointerInner, outer: knob.pointerOuter, width: 0.13)
                .stroke(Color.white.opacity(0.18), lineWidth: max(0.5, 0.7 * scale))
                .frame(width: r * 2, height: r * 2)
        }
        .frame(width: r * 2.7, height: r * 2.7)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { g in
                    if start == nil { start = v }
                    // Full travel in about 260 points of drag, up or right turns it up.
                    let delta = Float((-g.translation.height + g.translation.width * 0.6) / 260)
                    controller.set(param, (start ?? v) + delta)
                }
                .onEnded { _ in start = nil }
        )
        .onTapGesture(count: 2) { controller.resetKnob(param) }
        .position(x: knob.x * scale, y: knob.y * scale)
        .accessibilityLabel(param.name)
        .accessibilityValue(param.text(v))
    }
}

/// The black notch on the knob cap.
struct KnobPointer: Shape {
    let angle: Double
    let inner: Double
    let outer: Double
    let width: Double

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let notch = CGRect(x: -r * width / 2, y: -r * outer, width: r * width, height: r * (outer - inner))
        var p = Path(roundedRect: notch, cornerRadius: r * width * 0.2)
        let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle * .pi / 180)
        p = p.applying(t)
        return p
    }
}

// MARK: - Name windows (KITS / PRESETS)

struct NameWindow: View {
    let text: String
    let textRect: [Double]
    let color: [Double]
    let scale: CGFloat

    var body: some View {
        let h = (textRect[3] - textRect[1])
        Text(text.uppercased())
            .font(.system(size: h * 1.32 * scale, weight: .regular, design: .monospaced))
            .tracking(0.6 * scale)
            .foregroundColor(Color(red: color[0] / 255, green: color[1] / 255, blue: color[2] / 255))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: (textRect[2] - textRect[0]) * scale, height: h * 1.8 * scale, alignment: .leading)
            .position(x: (textRect[0] + textRect[2]) / 2 * scale, y: (textRect[1] + textRect[3]) / 2 * scale)
            .allowsHitTesting(false)
    }
}

// MARK: - BPM (seven-segment digits next to the printed "BPM")

struct BPMDisplay: View {
    @ObservedObject var controller: KnockController
    let layout: FaceplateLayout
    let scale: CGFloat
    @State private var startBPM: Double?

    var body: some View {
        let d = layout.bpmDigits
        let box = layout.bpmBox
        let color = Color(red: layout.textColor[0] / 255, green: layout.textColor[1] / 255, blue: layout.textColor[2] / 255)
        ZStack(alignment: .topLeading) {
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                let bpm = Int(controller.liveTempo.rounded())
                // Right-aligned up to just before the printed "BPM".
                let right = layout.bpmLabelX - 7
                let left = box[0] + 12
                SevenSegment(number: bpm, digits: 3, color: color)
                    .frame(width: (right - left) * scale, height: (d[3] - d[1]) * scale)
                    .position(x: (left + right) / 2 * scale, y: (d[1] + d[3]) / 2 * scale)
            }
            .allowsHitTesting(false)
            Rectangle()
                .fill(Color.white.opacity(0.001))
                .contentShape(Rectangle())
                .place(box, scale)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            guard !controller.tempoIsExternal else { return }
                            if startBPM == nil { startBPM = controller.state.bpm }
                            controller.setBPM((startBPM ?? 120) - Double(g.translation.height) / 5)
                            controller.readout = Readout(title: "TEMPO", value: "\(Int(controller.state.bpm.rounded())) BPM", time: Date())
                        }
                        .onEnded { _ in startBPM = nil }
                )
                .onTapGesture(count: 2) {
                    guard !controller.tempoIsExternal else { return }
                    controller.setBPM(controller.kitDefinition.tempo)
                    controller.readout = Readout(title: "TEMPO", value: "KIT TEMPO \(Int(controller.kitDefinition.tempo)) BPM", time: Date())
                }
        }
    }
}

/// Thin seven-segment digits, right-aligned, blank leading zeros.
struct SevenSegment: View {
    let number: Int
    let digits: Int
    let color: Color

    // Segments a b c d e f g for 0-9
    static let map: [[Bool]] = [
        [true, true, true, true, true, true, false], [false, true, true, false, false, false, false],
        [true, true, false, true, true, false, true], [true, true, true, true, false, false, true],
        [false, true, true, false, false, true, true], [true, false, true, true, false, true, true],
        [true, false, true, true, true, true, true], [true, true, true, false, false, false, false],
        [true, true, true, true, true, true, true], [true, true, true, true, false, true, true]
    ]

    var body: some View {
        Canvas { ctx, size in
            let n = max(0, min(number, Int(pow(10, Double(digits))) - 1))
            let chars = Array(String(n))
            let h = size.height
            let cell = min(size.width / CGFloat(digits), h * 0.58)
            let w = cell * 0.78
            let t = max(1.2, h * 0.11)
            let origin = size.width - cell * CGFloat(digits)
            for (i, ch) in chars.enumerated() {
                guard let value = ch.wholeNumberValue else { continue }
                let x0 = origin + CGFloat(digits - chars.count + i) * cell + (cell - w) / 2
                let segs = SevenSegment.map[value]
                func bar(_ rect: CGRect) { ctx.fill(Path(roundedRect: rect, cornerRadius: t / 2), with: .color(color)) }
                let mid = h / 2
                if segs[0] { bar(CGRect(x: x0 + t * 0.6, y: 0, width: w - t * 1.2, height: t)) }
                if segs[1] { bar(CGRect(x: x0 + w - t, y: t * 0.6, width: t, height: mid - t * 0.9)) }
                if segs[2] { bar(CGRect(x: x0 + w - t, y: mid + t * 0.3, width: t, height: mid - t * 0.9)) }
                if segs[3] { bar(CGRect(x: x0 + t * 0.6, y: h - t, width: w - t * 1.2, height: t)) }
                if segs[4] { bar(CGRect(x: x0, y: mid + t * 0.3, width: t, height: mid - t * 0.9)) }
                if segs[5] { bar(CGRect(x: x0, y: t * 0.6, width: t, height: mid - t * 0.9)) }
                if segs[6] { bar(CGRect(x: x0 + t * 0.6, y: mid - t / 2, width: w - t * 1.2, height: t)) }
            }
        }
    }
}

// MARK: - Play button

struct PlayButtonView: View {
    @ObservedObject var controller: KnockController
    let image: String
    let rect: [Double]
    let scale: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                if controller.isPlaying {
                    Image(image).resizable().place(rect, scale)
                }
            }
            .allowsHitTesting(false)
            PressableArea { controller.playPressed() }.place(rect, scale)
        }
    }
}
