// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - The faceplate
//
// Tyrone's four Face 1 renders are the design (MODERN black, PLATINUM, VINTAGE, TEXTURE), each face
// with its own buttons, knobs and pads; pressing a mode button swaps the whole plate. The plates carry
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
            let device = deviceOverride ?? .tablet          // iPad only for now
            if let layout = FaceplateLayout.forFace(controller.faceKey, device: device) ?? FaceplateLayout.forMode(mode, device: device) {
                let s = min(geo.size.width / layout.width, geo.size.height / layout.height)
                plate(layout, mode: mode, s: s)
                    .frame(width: layout.width * s, height: layout.height * s)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
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
        .fullScreenCover(item: $patternEditor) { target in SequencerView(controller: controller, loop: target.loop) }
        .onAppear {
            // Build-machine UI check only: open straight on the sequencer.
            if ProcessInfo.processInfo.environment["BREAKBOSS_OPEN_SEQUENCER"] == "1" && patternEditor == nil {
                patternEditor = PatternTarget(loop: 0)
            }
        }
        // the tutorial walks across both faces: its Face 2 steps open the sequencer, its Face 1 steps close it
        .onReceive(TutorialGuide.shared.$index) { i in
            guard let i, TutorialStep.all.indices.contains(i) else { return }
            if TutorialStep.all[i].surface == .face2 {
                if patternEditor == nil { openFace2() }
            } else if patternEditor != nil {
                patternEditor = nil
            }
        }
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

    /// Face 2 opens on the loop that's playing, otherwise the one PLAY starts.
    private func openFace2() {
        let current = Int(controller.meters.status[1])
        patternEditor = PatternTarget(loop: (0..<Pad.count).contains(current) ? current : controller.screenPattern)
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
            // The BreaKing logo is in the picture; this only names it for VoiceOver and the UI tests.
            Color.white.opacity(0.001)
                .allowsHitTesting(false)
                .accessibilityElement()
                .accessibilityLabel(BrandLogo.name)
                .accessibilityIdentifier("brandLogo")
                .place([600, 1004, 850, 1042], s)
            // each part erased to a plain view so Face 1's type can't nest deep enough to overflow the
            // stack in the TestFlight app (the SAMPLER window's b120 crash)
            ZStack(alignment: .topLeading) { topLeft(L, sfx: sfx, s: s) }.erased()
            ZStack(alignment: .topLeading) { knobs(L, sfx: sfx, s: s) }.erased()
            ZStack(alignment: .topLeading) { transport(L, sfx: sfx, s: s) }.erased()
            ZStack(alignment: .topLeading) { windows(L, s: s) }.erased()
            ZStack(alignment: .topLeading) { pads(L, s: s) }.erased()
            // the tutorial's lit part and card, over the face's own art (Tyrone, Oct 20)
            TutorialOverlay(surface: .face1, art: CGSize(width: L.width, height: L.height), scale: s, finish: sfx) { $0.face1(L) }
        }
    }

    /// Screen, ONE-SHOT / LOOP and the three mode buttons (each mode is its own faceplate).
    @ViewBuilder
    private func topLeft(_ L: FaceplateLayout, sfx: String, s: CGFloat) -> some View {
        ScopeView(controller: controller, scale: s)
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
        // the bottom row is the mode's FX section: Vintage and Texture print their own knobs there
        let mode = controller.mode
        ForEach(KnobControl.order, id: \.rawValue) { p in
            if let k = L.knobs[p.id] {
                KnobControl(controller: controller, param: TrackFX.face1(p, mode), knob: k, scale: s)
                    .id("\(p.id).\(mode.rawValue)")
            }
        }
        if controller.value(.clipper) < 0.5 {
            Image(L.overlayName("clipper_off", sfx)).resizable().place(L.clipperRect, s)
        }
        hit(L.clipperRect, s) { controller.toggle(.clipper) }
        hit(L.exportRect, s) { showExport = true }
        if let r = L.editorRect {
            hit(r, s) { openFace2() }
        }
        hit(L.menuRect, s) { showMenu = true }
        // Face 2's key on Face 1 too (Tyrone, Oct 20): the round spun-silver button with the pads'
        // squares in its slot, on the plate's bottom strip under pad 1; slide it (or tap its right
        // end) to open Face 2, like the piano-roll button
        if !FaceplateView.snapshotMode {
            FaceSlider(scale: s, color: FaceLight.of(sfx).glow, id: "faceSlider1", label: "Slide right to open Face 2") { openFace2() }
            .environment(\.seqFinish, sfx)
            .place([125, 1004, 235, 1040], s)
            // Face 2's power button on Face 1 too (Tyrone, Oct 21): right beside the slider, set flush
            // into the plate, the same job (the sequencer and pads all the way on or off), in this
            // face's metal and light
            PowerButton(on: controller.powerOn, scale: s, color: FaceLight.of(sfx).glow, id: "powerButton1", flush: true) { controller.togglePower() }
                .environment(\.seqFinish, sfx)
                .place([245, 1004, 281, 1040], s)
        }
        // RECORD (left of the piano-roll button): a 1- or 2-bar count-in, then the pads record
        if let r = L.recordRect {
            RecordButtonView(controller: controller, face: sfx, scale: s).place(r, s)
        }
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
        if !FaceplateView.snapshotMode { kitsMenu(L, s: s) }
        NameWindow(text: controller.state.presetName,
                   textRect: L.presetText,
                   color: L.textColor, scale: s)
        if !FaceplateView.snapshotMode { presetsMenu(L, s: s) }
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
            // (a sound or MIDI file dropped on a pad loads there: PadView's own drop target)
        }
    }

    /// LED plus its printed label (the overlay rect plus label is about 5 overlay-widths).
    private func ledHitRect(_ L: FaceplateLayout, _ r: [Double]) -> [Double] {
        let w = r[2] - r[0]
        return [r[0], r[1], r[0] + w * 5, r[3]]
    }

    private func hit(_ r: [Double], _ s: CGFloat, action: @escaping () -> Void) -> some View {
        PressableArea(action: action).place(r, s)
    }

    // MARK: Menus

    /// KITS and PATTERNS (Tyrone, Oct 21): the hardware panels, the same as Face 2's, opening from the
    /// name windows in this face's metal and light. Face 1 keeps what its browsers had: picking a kit
    /// plays its kick, INIT tops the patterns, and your own kits and presets can be saved and deleted.
    private func kitsMenu(_ L: FaceplateLayout, s: CGFloat) -> some View {
        PressGlow().bbHardwarePlaced(L.kitBox, s, title: "Kits", finish: controller.faceKey) {
            KitBrowserPanel(controller: controller, audition: true,
                            saveAs: { nameText = controller.state.userKit ?? ""; namePrompt = .kit }, allowDelete: true)
        }
    }

    private func presetsMenu(_ L: FaceplateLayout, s: CGFloat) -> some View {
        PressGlow().bbHardwarePlaced(L.presetBox, s, title: "Patterns", finish: controller.faceKey) {
            PatternBrowserPanel(controller: controller, showInit: true, allowDelete: true)
        }
    }
}

// MARK: - Dropping sound files on pads (faceplate pads and drum roll channels)

extension KnockController {
    /// Loads a dropped audio file onto a pad (WAV, AIFF, CAF, MP3, M4A, FLAC…).
    func importDropped(_ providers: [NSItemProvider], toPad pad: Int) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                if let url { DispatchQueue.main.async { self?.importSample(url, toPad: pad) } }
            }
            return true
        }
        guard provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) else { return false }
        provider.loadFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { [weak self] url, _ in
            guard let url else { return }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: url, to: copy)
            DispatchQueue.main.async { self?.importSample(copy, toPad: pad) }
        }
        return true
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

/// RECORD on the faceplate: the face's own button with its dot (in the plate). Tap: count-in
/// (1 or 2 bars of clicks), then the pattern plays and every pad you hit lands in it. The count-in
/// beats show on the button; it glows in the face's light while recording. Tap again to stop.
struct RecordButtonView: View {
    @ObservedObject var controller: KnockController
    let face: String
    let scale: CGFloat

    var body: some View {
        let light = FaceLight.of(face).glow
        let counting = controller.countingIn
        Button {
            controller.toggleRecordPads()
        } label: {
            ZStack {
                Color.white.opacity(0.001)
                if counting {
                    Image("rec_blank_\(face)").resizable()
                    Text("\(controller.countInBeatsLeft)").font(.system(size: 17 * scale, weight: .bold, design: .rounded)).foregroundColor(light)
                }
                if controller.recording {
                    RoundedRectangle(cornerRadius: 6 * scale).stroke(light, lineWidth: 2.5 * scale)
                        .shadow(color: light.opacity(0.8), radius: 6 * scale)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SeqPress())
        .accessibilityLabel("Record")
    }
}

/// Each face's light, taken off its picture (the scope trace and lamps): red on Modern Black and
/// Platinum, blue on Texture, amber on Vintage.
struct FaceLight {
    let core: Color
    let glow: Color
    /// The two colours as 0...1 RGB, for blending between them.
    let coreRGB: SIMD3<Double>
    let glowRGB: SIMD3<Double>

    init(core: SIMD3<Double>, glow: SIMD3<Double>) {
        coreRGB = core / 255; glowRGB = glow / 255
        self.core = Color(red: coreRGB.x, green: coreRGB.y, blue: coreRGB.z)
        self.glow = Color(red: glowRGB.x, green: glowRGB.y, blue: glowRGB.z)
    }

    static func of(_ face: String) -> FaceLight {
        switch face {
        case "texture": return FaceLight(core: [189, 236, 254], glow: [24, 100, 220])
        case "vintage": return FaceLight(core: [255, 250, 185], glow: [236, 186, 72])
        case "platinum": return FaceLight(core: [253, 159, 90], glow: [214, 50, 22])
        default: return FaceLight(core: [255, 198, 142], glow: [232, 52, 24])
        }
    }

    /// Between the face's two colours: 0 = its deep glow, 1 = its bright core.
    func blend(_ t: Double) -> Color {
        let c = glowRGB + (coreRGB - glowRGB) * min(1, max(0, t))
        return Color(red: c.x, green: c.y, blue: c.z)
    }
}

/// An invisible button that darkens a little while pressed (like a real button going in).
struct PressableArea: View {
    /// Held for half a second (optional): this instead of `action`.
    var longAction: (() -> Void)? = nil
    let action: () -> Void
    @State private var down = false
    @State private var downAt = Date()

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.black.opacity(down ? 0.3 : 0.001))
            .scaleEffect(down ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: down)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !down { down = true; downAt = Date() } }
                    .onEnded { g in
                        down = false
                        guard abs(g.translation.width) < 40 && abs(g.translation.height) < 40 else { return }
                        if let longAction, Date().timeIntervalSince(downAt) > 0.5 { longAction() } else { action() }
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
        let width = knob.pointerWidth ?? 0.13
        ZStack {
            Circle().fill(Color.white.opacity(0.001))
            KnobPointer(angle: KnobControl.angle(v), inner: knob.pointerInner, outer: knob.pointerOuter, width: width)
                .fill(Color(white: 0.04))
                .frame(width: r * 2, height: r * 2)
            KnobPointer(angle: KnobControl.angle(v), inner: knob.pointerInner, outer: knob.pointerOuter, width: width)
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
            // RECORD armed: a red ring round PLAY (hold PLAY to arm / disarm, MPC style)
            if controller.recording {
                RoundedRectangle(cornerRadius: 6 * scale).stroke(Color(red: 1, green: 0.16, blue: 0.12), lineWidth: 3 * scale)
                    .shadow(color: Color.red.opacity(0.8), radius: 6 * scale)
                    .place(rect, scale).allowsHitTesting(false)
            }
            PressableArea(longAction: { controller.toggleRecordPads() }) { controller.playPressed() }.place(rect, scale)
        }
    }
}
