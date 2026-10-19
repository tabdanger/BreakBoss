// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The SAMPLER window (Tyrone's two renders, Oct 18)
//
// One window per track, opened from the track's menu (two-finger tap / right-click > Open sample
// editor). Page 1 SAMPLE, page 2 ENVELOPE, page 3 MISC (the wrench); the tabs flip between them. Drawn at the renders' size
// (1408 × 1000 with the waveform's edit bar) and scaled to fit: it floats over the sequencer, drag
// its title bar to move it and its corner to resize it. Each mode wears its own metal and light: Platinum silver with
// platinum knobs and red light, Modern Black with red, Vintage cream with yellow, Texture blue
// with blue. See Sampler.swift for what every control does to the sound.

/// The window's metal, printing and light in each finish.
struct SamplerSkin {
    let finish: String
    /// The bezel round the window (Modern Black wears a silver one, as in the render).
    let bezel: MetalTone
    /// The title bar, tab strip and panels.
    let surface: MetalTone
    let ink: Color
    let glow: Color

    var dim: Color { ink.opacity(0.62) }
    var well: Color { Color(white: finish == "modern" ? 0.07 : 0.09) }
    var wellInk: Color { Color(white: 0.9) }
    /// A knob's cap: platinum silver, black, cream or blue.
    var cap: MetalTone { finish == "modern" ? MetalTone(bright: Color(white: 0.34), light: Color(white: 0.2), mid: Color(white: 0.12), dark: Color(white: 0.04), ink: .white, pebbled: false) : surface }

    static func of(_ finish: String) -> SamplerSkin {
        let tone = MetalTone.of(finish)
        let glow: Color
        // Platinum and Modern Black light red (Tyrone, Oct 18: no lime green on Platinum), Vintage yellow, Texture blue
        switch finish {
        case "vintage": glow = Color(red: 1, green: 0.78, blue: 0.18)
        case "texture": glow = Color(red: 0.3, green: 0.66, blue: 1)
        default: glow = Color(red: 1, green: 0.2, blue: 0.16)
        }
        return SamplerSkin(finish: finish, bezel: finish == "modern" ? MetalTone.of("platinum") : tone, surface: tone, ink: tone.ink, glow: glow)
    }
}

/// Brushed metal in the skin's tone: the band of light, the grain (and Face 1's pebble on cream
/// and blue), a lit top lip and a shadowed lower edge.
struct SamplerMetal: View {
    let tone: MetalTone
    var corner: CGFloat = 6
    var sunk = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner)
        ZStack {
            LinearGradient(stops: [.init(color: tone.light, location: 0), .init(color: tone.mid, location: 0.45),
                                   .init(color: tone.light, location: 0.7), .init(color: tone.dark, location: 1)],
                           startPoint: sunk ? .bottom : .top, endPoint: sunk ? .top : .bottom)
            if tone.pebbled { PebbleGrain(amount: 0.4) }
            BrushedFinish(corner: corner)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: sunk ? [.black.opacity(0.55), tone.bright.opacity(0.5)] : [tone.bright.opacity(0.85), .black.opacity(0.5)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .allowsHitTesting(false)
    }
}

/// A dark inset (menus, the readouts, the graphs, the waveform).
struct SamplerWell: View {
    let skin: SamplerSkin
    var corner: CGFloat = 5
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner)
        shape.fill(LinearGradient(colors: [Color(white: 0.03), skin.well], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.black.opacity(0.8), skin.surface.bright.opacity(0.45)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .allowsHitTesting(false)
    }
}

/// A knob of the sampler: the cap in the skin's metal, a lit pointer, and an arc of light showing
/// its value (from the middle for the two-way knobs). Drag up or right to turn it; double tap to
/// reset. While it turns, its value shows above it.
struct SamplerKnob: View {
    let value: Float
    let skin: SamplerSkin
    var bipolar = false
    var reset: Float? = nil
    var display: ((Float) -> String)? = nil
    let change: (Float, Bool) -> Void
    @State private var start: Float?
    @State private var live: Float?
    @State private var lastTap = Date.distantPast

    var body: some View {
        let v = live ?? value
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            ZStack {
                // the scale: dots round the knob
                ForEach(0..<11, id: \.self) { i in
                    Circle().fill(skin.dim.opacity(0.7)).frame(width: d * 0.035, height: d * 0.035)
                        .offset(y: -d * 0.5).rotationEffect(.degrees(-135 + Double(i) * 27))
                }
                // the value: an arc of the mode's light
                let lo = bipolar ? min(0.375, Double(v) * 0.75) : 0
                let hi = bipolar ? max(0.375, Double(v) * 0.75) : Double(v) * 0.75
                Circle().trim(from: lo, to: max(lo, hi)).stroke(skin.glow, style: StrokeStyle(lineWidth: d * 0.055, lineCap: .round))
                    .rotationEffect(.degrees(135)).frame(width: d * 0.88, height: d * 0.88)
                    .shadow(color: skin.glow.opacity(0.8), radius: d * 0.05)
                // the cap
                ZStack {
                    Circle().fill(skin.finish == "platinum"
                                  ? AngularGradient(colors: [Color(white: 0.96), Color(white: 0.6), Color(white: 0.9), Color(white: 0.52), Color(white: 0.96)], center: .center)
                                  : skin.cap.spun)
                    if skin.cap.pebbled { PebbleGrain(amount: 0.3).clipShape(Circle()) }
                    Circle().fill(RadialGradient(colors: [Color.white.opacity(0.35), .clear], center: .init(x: 0.35, y: 0.25), startRadius: 0, endRadius: d * 0.4))
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom), lineWidth: max(1, d * 0.03))
                    Capsule().fill(skin.glow).frame(width: max(2, d * 0.05), height: d * 0.22).offset(y: -d * 0.2)
                        .shadow(color: skin.glow, radius: d * 0.03)
                        .rotationEffect(.degrees(-135 + 270 * Double(v)))
                }
                .frame(width: d * 0.7, height: d * 0.7)
                .shadow(color: .black.opacity(0.7), radius: d * 0.06, y: d * 0.05)
                if live != nil, let display {
                    Text(display(v)).font(.system(size: max(10, d * 0.2), weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.black.opacity(0.85)).overlay(Capsule().stroke(skin.glow, lineWidth: 1)))
                        .fixedSize().offset(y: -d * 0.72).allowsHitTesting(false)
                }
            }
            .frame(width: d, height: d)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .contentShape(Rectangle())
        .accessibilityValue(display?(value) ?? String(format: "%.3f", value))
        // a short travel before it turns, so a two-finger tap (its tempo menu) isn't taken for a turn
        .highPriorityGesture(DragGesture(minimumDistance: 2)
            .onChanged { g in
                if start == nil { start = value }
                let n = ((start ?? value) + Float((-g.translation.height + g.translation.width * 0.6) / 180)).clamped(0, 1)
                live = n
                change(n, false)
            }
            .onEnded { g in
                let n = ((start ?? value) + Float((-g.translation.height + g.translation.width * 0.6) / 180)).clamped(0, 1)
                change(n, true)
                start = nil; live = nil
            })
        // double tap: back to its default (two single taps timed here: a count-2 tap gesture next to the
        // knob's two-finger menu recognizer never fired in the simulator)
        .simultaneousGesture(TapGesture().onEnded {
            let now = Date()
            if now.timeIntervalSince(lastTap) < 0.4, let reset { change(reset, true); lastTap = .distantPast } else { lastTap = now }
        })
    }
}

/// A round switch: a dark socket that lights in the mode's colour when it's on.
struct SamplerSwitch: View {
    let on: Bool
    let skin: SamplerSkin
    var lamp: Color? = nil
    var body: some View {
        let light = lamp ?? skin.glow
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(white: 0.02), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(LinearGradient(colors: [.black.opacity(0.8), skin.surface.bright.opacity(0.7)], startPoint: .top, endPoint: .bottom), lineWidth: max(1, d * 0.06))
                if on {
                    Circle().fill(RadialGradient(colors: [.white, light, light.opacity(0.6)], center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: d * 0.4))
                        .padding(d * 0.16).shadow(color: light, radius: d * 0.25)
                } else {
                    Circle().fill(Color(white: 0.12)).padding(d * 0.18)
                }
            }
            .frame(width: d, height: d)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
        .animation(.easeOut(duration: 0.12), value: on)
    }
}

struct SamplerWindow: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    let finish: String
    let close: () -> Void
    let minimize: () -> Void
    let switchTo: (Int) -> Void
    let importFile: () -> Void
    let drop: ([NSItemProvider]) -> Bool
    /// The track's own SWING (below 0: it follows the SWING knob) and push / pull (ticks) in the
    /// pattern, and how MISC's SHIFT / SWING knobs set them (nil leaves one as it is; `final` at let go).
    var swing: Float = -1
    var shift: Float = 0
    var setFeel: ((_ swing: Float?, _ shift: Float?, _ final: Bool) -> Void)? = nil
    /// Dragging the title bar moves the window (translation, finished).
    var move: ((CGSize, Bool) -> Void)? = nil

    @State private var page = 0                  // 0 SAMPLE, 1 ENVELOPE, 2 MISC
    @State private var trackingTab = 1           // MISC's tracking: 0 Vol (velocity), 1 Key
    @State private var target: SamplerTarget = .volume
    @State private var keyboardStart = 36        // the keyboard's first key (C3)
    @State private var zoom: CGFloat = 1
    @State private var scrollPos: CGFloat = 0
    @State private var pinchFrom: CGFloat?
    @State private var dropping = false
    /// Turning a SAMPLE-page knob: the knob shows this until it's let go (the sound is computed then).
    @State private var pending: SamplerSettings?
    /// The waveform's selection (parts of the sound, 0…1) and the edits UNDO can take back.
    @State private var selection: ClosedRange<Double>?
    @State private var selectFrom: Double?
    /// A region marker being dragged along the top of the waveform: which one, and where it is now.
    @State private var markerDrag: (Int, Float)?
    @State private var handleFrom: (Double, Double)?
    /// Every change made in the window (knobs, switches, menus, waveform edits), as what the track was
    /// before it: UNDO takes the last one back, REDO puts it back again (Tyrone, Oct 19).
    @State private var undo: [PadSettings] = []
    @State private var redo: [PadSettings] = []
    /// When a change was last kept for UNDO: a knob turning sends many changes, kept as one step.
    @State private var lastKept = Date.distantPast
    /// Dragging a loop flag: the loop points shown until it's let go.
    @State private var loopDrag: (Float, Float)?
    @State private var loopFrom: (Float, Float)?
    /// Dragging the Start flag.
    @State private var startDrag: Float?
    @State private var startFrom: Float?
    /// Saving the envelope as a preset: its kind, and the name being typed.
    @State private var savingKind: String?
    @State private var presetName = ""
    @State private var presetsChanged = 0
    /// Dragging a point or curve on the envelope graph: which one, and the envelope when it started.
    @State private var envDrag: (handle: Int, from: SamplerEnvelope)?
    /// The envelope point tapped last and when (a second tap on it soon after deletes it).
    @State private var envPointTap: (index: Int, time: Date) = (-1, .distantPast)

    static let artW: CGFloat = 1408, artH: CGFloat = 1000
    static let probing = ProcessInfo.processInfo.environment["BREAKBOSS_UI_PROBE"] != nil
    @State private var probe = ""

    private var skin: SamplerSkin { SamplerSkin.of(finish) }
    private var sm: SamplerSettings { pending ?? controller.sampler(pad) }
    private var trackNumber: Int { (controller.rackOrder.firstIndex(of: pad) ?? pad) + 1 }

    private func edit(_ change: (inout SamplerSettings) -> Void) {
        var s = controller.sampler(pad); change(&s)
        guard s != controller.sampler(pad) else { return }
        keep(controller.state.pads[pad], merging: true)
        controller.setSampler(pad, s)
    }
    /// A SAMPLE-page knob: shown while it turns, computed into the sound when it's let go.
    private func editComputed(_ final: Bool, _ change: (inout SamplerSettings) -> Void) {
        var s = sm; change(&s)
        if final {
            pending = nil
            if s != controller.sampler(pad) { keep(controller.state.pads[pad]); controller.setSampler(pad, s) }
        } else { pending = s }
    }
    /// The track's own settings (PAN, its file) changed from the window.
    private func setPad(_ ps: PadSettings, merging: Bool = false) {
        guard ps != controller.state.pads[pad] else { return }
        keep(controller.state.pads[pad], merging: merging)
        controller.setPadSettings(pad, ps)
    }
    /// Keeps what the track was for UNDO (a new change clears REDO). `merging`: a change coming less
    /// than half a second after the last one (a knob still turning) joins that step.
    private func keep(_ before: PadSettings, merging: Bool = false) {
        let now = Date()
        defer { lastKept = now }
        if merging && now.timeIntervalSince(lastKept) < 0.5 && !undo.isEmpty { return }
        undo.append(before)
        if undo.count > 50 { undo.removeFirst() }
        redo = []
    }
    private func undoStep() {
        guard let last = undo.popLast() else { return }
        redo.append(controller.state.pads[pad])
        pending = nil; lastKept = .distantPast
        controller.restorePad(pad, last)
        selection = nil
    }
    private func redoStep() {
        guard let next = redo.popLast() else { return }
        undo.append(controller.state.pads[pad])
        pending = nil; lastKept = .distantPast
        controller.restorePad(pad, next)
        selection = nil
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Self.artW, geo.size.height / Self.artH)
            ZStack(alignment: .topLeading) {
                // the window's own id sits on its bezel: on the whole window it would replace every control's id
                bezel(s).accessibilityElement().accessibilityIdentifier("samplerWindow")
                titleBar(s)
                tabStrip(s)
                switch page {
                case 0: samplePage(s)
                case 1: envelopePage(s)
                default: miscPage(s)
                }
                if Self.probing {
                    // UI tests only: renders a hit of the track as it is now and shows its numbers
                    Button { probe = controller.probeTrack(pad) } label: {
                        Text(probe.isEmpty ? "probe" : probe).font(.system(size: 9)).foregroundColor(.white.opacity(0.3))
                    }
                    .accessibilityIdentifier("samplerProbe").accessibilityValue(probe)
                    .spot(560, 974, 560, 22, s)
                }
            }
            .frame(width: Self.artW * s, height: Self.artH * s, alignment: .topLeading)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(Self.artW / Self.artH, contentMode: .fit)
        // the window's menus check their items in the mode's own colour, not lime
        .environment(\.bbMenuAccent, skin.glow)
        .alert("Save the envelope", isPresented: Binding(get: { savingKind != nil }, set: { if !$0 { savingKind = nil } })) {
            TextField("Name", text: $presetName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) { savingKind = nil }
        } message: {
            Text("Saved with your \(savingKind ?? "") presets on this device.")
        }
    }

    // MARK: Frame, title, tabs

    private func bezel(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SamplerMetal(tone: skin.bezel, corner: 14 * s)
                .shadow(color: .black.opacity(0.7), radius: 18 * s, y: 8 * s)
            // the body inside the bezel
            SamplerMetal(tone: skin.surface, corner: 8 * s, sunk: true).spot(22, 6, 1364, 982, s)
            ForEach([CGPoint(x: 10, y: 500), CGPoint(x: 1398, y: 500)], id: \.x) { p in
                Circle().fill(skin.bezel.spun).overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: 9 * s, height: 9 * s).position(x: p.x * s, y: p.y * s)
            }
        }
        .frame(width: Self.artW * s, height: Self.artH * s, alignment: .topLeading)
    }

    /// BreaKing with its K in the mode's light, as in the renders.
    private var brand: Text {
        let a: Text = Text("Brea").foregroundColor(skin.ink)
        let k: Text = Text("K").foregroundColor(skin.glow)
        let b: Text = Text("ing").foregroundColor(skin.ink)
        return a + k + b
    }

    private func titleBar(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SamplerMetal(tone: skin.surface, corner: 6 * s).spot(26, 8, 1356, 58, s)
            // the title bar moves the window
            Color.clear.contentShape(Rectangle()).spot(26, 8, 1190, 58, s)
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { v in move?(v.translation, false) }
                    .onEnded { v in move?(v.translation, true) })
                .accessibilityIdentifier("samplerTitleBar")
            brand
                .font(.system(size: 34 * s, weight: .bold).width(.expanded))
                .shadow(color: .black.opacity(0.4), radius: 0, y: 1)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 210 * s, height: 58 * s, alignment: .leading).offset(x: 58 * s, y: 8 * s)
                .allowsHitTesting(false)
            Text("SAMPLER").font(.system(size: 30 * s, weight: .medium).width(.expanded)).foregroundColor(skin.dim)
                .frame(width: 220 * s, height: 58 * s, alignment: .leading).offset(x: 272 * s, y: 8 * s)
                .allowsHitTesting(false)
            Text(String(format: "CH %02d", trackNumber)).font(.system(size: 27 * s, weight: .medium)).foregroundColor(skin.ink)
                .frame(width: 160 * s, height: 58 * s, alignment: .trailing).offset(x: 1030 * s, y: 8 * s)
                .allowsHitTesting(false)
            // UNDO / REDO: every change in the window, on every page
            titleButton("arrow.uturn.backward", s, red: false, action: undoStep).spot(880, 14, 64, 46, s)
                .disabled(undo.isEmpty || controller.sampleEditing).opacity(undo.isEmpty ? 0.45 : 1)
                .accessibilityLabel("Undo").accessibilityIdentifier("samplerUndo")
            titleButton("arrow.uturn.forward", s, red: false, action: redoStep).spot(950, 14, 64, 46, s)
                .disabled(redo.isEmpty || controller.sampleEditing).opacity(redo.isEmpty ? 0.45 : 1)
                .accessibilityLabel("Redo").accessibilityIdentifier("samplerRedo")
            titleButton("minus", s, red: false, action: minimize).spot(1232, 14, 64, 46, s)
                .accessibilityLabel("Minimize the sampler").accessibilityIdentifier("samplerMinimize")
            titleButton("xmark", s, red: true, action: close).spot(1310, 14, 66, 46, s)
                .accessibilityLabel("Close the sampler").accessibilityIdentifier("samplerClose")
        }
    }

    private func titleButton(_ symbol: String, _ s: CGFloat, red: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                SamplerMetal(tone: skin.surface, corner: 5 * s)
                Image(systemName: symbol).font(.system(size: 24 * s, weight: .semibold)).foregroundColor(red ? skin.glow : skin.ink)
            }
        }
        .buttonStyle(SeqPress())
    }

    private func tabStrip(_ s: CGFloat) -> some View {
        let muted = controller.mutedPads[pad]
        return ZStack(alignment: .topLeading) {
            SamplerMetal(tone: skin.surface, corner: 6 * s).spot(30, 68, 1352, 100, s)
            pageTab(0, "SAMPLE", s) { SampleGlyph().stroke(page == 0 ? skin.glow : skin.dim, style: StrokeStyle(lineWidth: 3 * s, lineJoin: .round)) }
                .spot(36, 76, 238, 84, s)
            pageTab(1, "ENVELOPE", s) { EnvelopeGlyph().stroke(page == 1 ? skin.glow : skin.dim, style: StrokeStyle(lineWidth: 3 * s, lineJoin: .round)) }
                .spot(278, 76, 264, 84, s)
            pageTab(2, "MISC", s) {
                Image(systemName: "wrench.adjustable").font(.system(size: 28 * s, weight: .medium)).foregroundColor(page == 2 ? skin.glow : skin.dim)
            }
                .spot(546, 76, 200, 84, s)
            // ON: the track plays (a mute on the rack turns it off)
            Button { controller.toggleMute(pad) } label: {
                VStack(spacing: 6 * s) {
                    SamplerSwitch(on: !muted, skin: skin, lamp: nil).frame(width: 34 * s, height: 34 * s)
                    label("ON", s)
                }
            }
            .buttonStyle(SeqPress()).spot(770, 84, 60, 80, s).accessibilityIdentifier("samplerOn")
            headerKnob("PAN", value: (controller.state.pads[pad].pan + 1) / 2, bipolar: true, reset: 0.5, x: 906, s,
                       display: { v in let p = Int(((v * 2 - 1) * 100).rounded()); return p == 0 ? "C" : (p < 0 ? "L\(-p)" : "R\(p)") }) { v, _ in
                var ps = controller.state.pads[pad]; let p = v * 2 - 1; ps.pan = abs(p) < 0.03 ? 0 : p; setPad(ps, merging: true)
            }
            // VOL: the sampler's own pre-amp before the mode's effects, −12 dB … +12 dB (Tyrone, Oct 19), bigger
            headerKnob("VOL", value: sm.volume, bipolar: false, reset: 0.5, x: 1002, s, size: 80,
                       display: SamplerSettings.volumeText) { v, _ in
                edit { $0.volume = abs(v - 0.5) < 0.01 ? 0.5 : v }
            }
            headerKnob("PITCH", value: (sm.pitch + 1) / 2, bipolar: true, reset: 0.5, x: 1101, s,
                       display: { v in String(format: "%+.2f st", Double(v * 2 - 1) * Double(sm.range)) }) { v, _ in
                edit { $0.pitch = abs(v * 2 - 1) < 0.02 ? 0 : v * 2 - 1 }
            }
            led("\(sm.range)", "RANGE", x: 1178, s)
                .bbMenu(title: "Pitch range (semitones)", width: 220) {
                    [1, 2, 3, 4, 5, 6, 7, 12, 24, 48].map { r in BBMenuItem.item("± \(r)", checked: sm.range == r) { edit { $0.range = r } } }
                }
                .offset(x: 1164 * s, y: 90 * s)
            led(String(format: "%02d", trackNumber), "TRACK", x: 1285, s)
                .bbMenu(title: "Track", width: 260) {
                    controller.rackChannels.enumerated().map { i, ch in
                        BBMenuItem.item(String(format: "%02d  %@", i + 1, ch.name), checked: ch.pad == pad) { switchTo(ch.pad) }
                    }
                }
                .offset(x: 1271 * s, y: 90 * s)
        }
    }

    /// A page tab is a physical button (Tyrone's MISC render, Oct 18): a raised metal cap with a
    /// bevelled edge in its own dark bay; the page that's showing is pressed in, its icon lit and
    /// a line of light under it.
    private func pageTab<G: View>(_ i: Int, _ title: String, _ s: CGFloat, @ViewBuilder glyph: () -> G) -> some View {
        let on = page == i
        let cap = RoundedRectangle(cornerRadius: 5 * s)
        return Button { withAnimation(.easeOut(duration: 0.15)) { page = i } } label: {
            ZStack {
                // the bay the button sits in
                SamplerWell(skin: skin, corner: 7 * s)
                ZStack(alignment: .bottom) {
                    SamplerMetal(tone: skin.surface, corner: 5 * s, sunk: on)
                    // the bevel: a lit top lip and a dark lower edge (inverted when it's pressed in)
                    cap.strokeBorder(LinearGradient(colors: on ? [.black.opacity(0.7), skin.surface.bright.opacity(0.35)]
                                                              : [skin.surface.bright.opacity(0.9), .clear, .black.opacity(0.75)],
                                                    startPoint: .top, endPoint: .bottom), lineWidth: 2 * s)
                    if on { cap.fill(skin.glow.opacity(0.08)) }
                    HStack(spacing: 20 * s) {
                        glyph().frame(width: 50 * s, height: 36 * s)
                            .shadow(color: on ? skin.glow.opacity(0.8) : .clear, radius: 4 * s)
                        Text(title).font(.system(size: 24 * s, weight: .medium)).foregroundColor(on ? skin.ink : skin.dim)
                            .shadow(color: .black.opacity(on ? 0.35 : 0.25), radius: 0, y: 1 * s)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: on ? 1 * s : 0)
                    if on {
                        Capsule().fill(skin.glow).frame(height: 4 * s).padding(.horizontal, 8 * s).padding(.bottom, 2 * s)
                            .shadow(color: skin.glow, radius: 5 * s)
                    }
                }
                .clipShape(cap)
                .shadow(color: .black.opacity(on ? 0.25 : 0.6), radius: on ? 1 * s : 3 * s, y: on ? 0 : 2 * s)
                .padding(4 * s)
            }
        }
        .buttonStyle(SeqPress())
        .accessibilityIdentifier(["samplerSamplePage", "samplerEnvelopePage", "samplerMiscPage"][min(i, 2)])
    }

    private func headerKnob(_ title: String, value: Float, bipolar: Bool, reset: Float, x: CGFloat, _ s: CGFloat, size: CGFloat = 66,
                            display: @escaping (Float) -> String, change: @escaping (Float, Bool) -> Void) -> some View {
        VStack(spacing: 4 * s) {
            SamplerKnob(value: value, skin: skin, bipolar: bipolar, reset: reset, display: display, change: change).frame(width: size * s, height: size * s)
                .accessibilityLabel(title).accessibilityIdentifier("samplerKnob" + title)
            label(title, s)
        }
        // a bigger knob sits higher, so its label stays on the others' line
        .frame(width: 96 * s).offset(x: (x - 48) * s, y: (74 - (size - 66)) * s)
    }

    private func led(_ text: String, _ title: String, x: CGFloat, _ s: CGFloat) -> some View {
        VStack(spacing: 8 * s) {
            ZStack {
                SamplerWell(skin: skin, corner: 3 * s)
                Text(text).font(.system(size: 29 * s, weight: .medium, design: .monospaced)).foregroundColor(skin.glow)
                    .shadow(color: skin.glow.opacity(0.8), radius: 4 * s)
            }
            .frame(width: 72 * s, height: 46 * s)
            label(title, s)
        }
        .frame(width: 100 * s)
    }

    private func label(_ text: String, _ s: CGFloat, size: CGFloat = 17) -> some View {
        Text(text).font(.system(size: size * s, weight: .medium)).foregroundColor(skin.ink).lineLimit(1).minimumScaleFactor(0.6)
    }

    // MARK: Page 1: SAMPLE

    private func samplePage(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            filePanel(s).spot(36, 182, 664, 86, s)
            contentPanel(s).spot(36, 274, 664, 234, s)
            playbackPanel(s).spot(36, 514, 664, 170, s)
            stretchPanel(s).spot(710, 182, 664, 166, s)
            effectsPanel(s).spot(710, 354, 664, 330, s)
            editBar(s).spot(38, 694, 1334, 52, s)
            waveform(s).spot(38, 754, 1334, 216, s)
        }
    }

    private func panel<C: View>(_ title: String?, _ s: CGFloat, @ViewBuilder content: () -> C) -> some View {
        ZStack(alignment: .topLeading) {
            SamplerMetal(tone: skin.surface, corner: 6 * s)
            if let title { Text(title).font(.system(size: 22 * s, weight: .medium)).foregroundColor(skin.ink).offset(x: 20 * s, y: 12 * s) }
            content()
        }
    }

    private var fileName: String {
        controller.state.pads[pad].sampleFile.map { ($0 as NSString).lastPathComponent } ?? controller.padName(pad)
    }

    private func filePanel(_ s: CGFloat) -> some View {
        panel(nil, s) {
            label("File", s, size: 22).frame(height: 86 * s).offset(x: 22 * s)
            ZStack(alignment: .leading) {
                SamplerWell(skin: skin)
                Text(controller.state.pads[pad].sampleFile == nil ? "\(fileName) (kit)" : fileName)
                    .font(.system(size: 21 * s)).foregroundColor(skin.wellInk.opacity(0.85)).lineLimit(1).padding(.leading, 14 * s)
            }
            .spot(84, 18, 440, 52, s)
            Button(action: importFile) {
                ZStack { SamplerMetal(tone: skin.surface, corner: 4 * s); Image(systemName: "folder").font(.system(size: 24 * s)).foregroundColor(skin.ink) }
            }
            .buttonStyle(SeqPress()).spot(526, 18, 80, 52, s).accessibilityIdentifier("samplerOpenFile")
            ZStack { SamplerMetal(tone: skin.surface, corner: 4 * s); Image(systemName: "chevron.down").font(.system(size: 18 * s, weight: .semibold)).foregroundColor(skin.ink) }
                .bbMenu(title: "Sample", width: 320) { fileMenu() }
                .spot(608, 18, 42, 52, s)
        }
    }

    private func fileMenu() -> [BBMenuItem] {
        var items: [BBMenuItem] = [.item("Load a sample from Files…", icon: "folder") { importFile() }]
        let folder = KnockFolders.samples.standardizedFileURL.path + "/"
        let files = KnockFolders.sampleFiles().prefix(60).map { $0.standardizedFileURL.path.replacingOccurrences(of: folder, with: "") }
        if !files.isEmpty {
            items.append(.submenu("Your samples", icon: "waveform", files.map { name in
                BBMenuItem.item((name as NSString).deletingPathExtension, checked: controller.state.pads[pad].sampleFile == name) {
                    var ps = controller.state.pads[pad]; ps.sampleFile = name; setPad(ps)
                }
            }))
        }
        if controller.state.pads[pad].sampleFile != nil {
            items.append(.item("Back to the kit's sound", icon: "arrow.uturn.backward") {
                var ps = controller.state.pads[pad]; ps.sampleFile = nil; setPad(ps)
            })
        }
        items.append(.item("Reset the sampler", icon: "arrow.counterclockwise", destructive: true) {
            var ps = controller.state.pads[pad]; ps.sampler = nil; setPad(ps)
        })
        return items
    }

    private func toggleRow(_ title: String, _ on: Bool, x: CGFloat, y: CGFloat, w: CGFloat = 290, _ s: CGFloat, id: String, _ flip: @escaping () -> Void) -> some View {
        Button(action: flip) {
            HStack(spacing: 14 * s) {
                SamplerSwitch(on: on, skin: skin).frame(width: 34 * s, height: 34 * s)
                Text(title).font(.system(size: 21 * s)).foregroundColor(on ? skin.ink : skin.dim).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SeqPress())
        .accessibilityIdentifier(id)
        .accessibilityValue(on ? "on" : "off")
        .spot(x, y, w, 40, s)
    }

    private func menuChip(_ text: String, _ s: CGFloat, size: CGFloat = 22) -> some View {
        ZStack {
            SamplerWell(skin: skin)
            HStack {
                Text(text).font(.system(size: size * s)).foregroundColor(skin.wellInk).lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 4 * s)
                Image(systemName: "triangle.fill").rotationEffect(.degrees(180)).font(.system(size: 11 * s)).foregroundColor(skin.wellInk.opacity(0.8))
            }
            .padding(.horizontal, 16 * s)
        }
        .contentShape(Rectangle())
    }

    private func contentPanel(_ s: CGFloat) -> some View {
        panel("Content", s) {
            // Keep on disk (Tyrone, Oct 18): lit while the channel holds its own loaded sample; off goes
            // back to the kit's sound, on opens Files to load one
            toggleRow("Keep on disk", controller.state.pads[pad].sampleFile != nil, x: 22, y: 56, s, id: "samplerKeepOnDisk") {
                if controller.state.pads[pad].sampleFile != nil {
                    var ps = controller.state.pads[pad]; ps.sampleFile = nil; setPad(ps)
                } else {
                    importFile()
                }
            }
            toggleRow("Resample", sm.resample, x: 22, y: 102, s, id: "samplerResample") { edit { $0.resample.toggle() } }
            toggleRow("Load regions", sm.loadRegions, x: 314, y: 56, s, id: "samplerLoadRegions") { edit { $0.loadRegions.toggle() } }
            toggleRow("Load slice markers", sm.loadSliceMarkers, x: 314, y: 102, w: 340, s, id: "samplerSliceMarkers") { edit { $0.loadSliceMarkers.toggle() } }
            label("Declicking mode", s, size: 21).frame(height: 52 * s).offset(x: 34 * s, y: 156 * s)
            menuChip(sm.declick.title, s)
                .bbMenu(title: "Declicking mode", width: 330) {
                    SamplerDeclick.allCases.map { d in BBMenuItem.item(d.title, checked: sm.declick == d) { edit { $0.declick = d } } }
                }
                .spot(250, 156, 392, 52, s)
                .accessibilityIdentifier("samplerDeclick")
        }
    }

    private func playbackPanel(_ s: CGFloat) -> some View {
        let cues = sm.loadSliceMarkers ? (controller.playedSample(pad)?.cues ?? []) : []
        let length = max(1, controller.playedSample(pad)?.length ?? 1)
        let marks = cues.map { Float($0) / Float(length) } + sm.markers
        return panel("Playback", s) {
            knob("START OFFSET", sm.startOffset, x: 113, y: 92, d: 72, s, labelY: 146, reset: 0,
                 display: { v in "\(Int((v * 100).rounded()))%" }) { v, _ in
                // with slice or region markers, START OFFSET jumps from marker to marker
                var o = v
                if !marks.isEmpty {
                    let points = [0] + marks
                    o = points.min { abs($0 - v) < abs($1 - v) } ?? v
                }
                edit { $0.startOffset = o }
            }
            toggleRow("Use loop points", sm.useLoop, x: 314, y: 56, s, id: "samplerUseLoop") { edit { $0.useLoop.toggle() } }
            toggleRow("Ping pong loop", sm.pingPong, x: 314, y: 102, s, id: "samplerPingPong") { edit { $0.pingPong.toggle(); if $0.pingPong { $0.useLoop = true } } }
        }
    }

    private func knob(_ title: String, _ value: Float, x: CGFloat, y: CGFloat, d: CGFloat, _ s: CGFloat, labelY: CGFloat,
                      bipolar: Bool = false, reset: Float? = nil, labelSize: CGFloat = 17, id: String? = nil,
                      menu: (() -> [BBMenuItem])? = nil,
                      display: ((Float) -> String)? = nil, change: @escaping (Float, Bool) -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            SamplerKnob(value: value, skin: skin, bipolar: bipolar, reset: reset, display: display, change: change)
                .bbContextMenu(title: title, width: 220) { menu?() ?? [] }
                .frame(width: d * s, height: d * s).offset(x: (x - d / 2) * s, y: (y - d / 2) * s)
                .accessibilityLabel(title)
                .accessibilityIdentifier("samplerKnob" + (id ?? title.replacingOccurrences(of: " ", with: "")))
            label(title, s, size: labelSize).frame(width: 140 * s, height: 24 * s).offset(x: (x - 70) * s, y: (labelY - 12) * s)
        }
    }

    private func stretchPanel(_ s: CGFloat) -> some View {
        let sourceSeconds = controller.playedSample(pad)?.seconds ?? 1
        return panel("Time stretching", s) {
            knob("PITCH", (sm.stretchPitch / 12 + 1) / 2, x: 67, y: 86, d: 72, s, labelY: 142, bipolar: true, reset: 0.5,
                 display: { v in String(format: "%+.2f st", Double(v * 2 - 1) * 12) }) { v, final in
                // like FL: turning PITCH while on Resample switches to a stretch that keeps the length
                editComputed(final) { $0.stretchPitch = abs(v * 2 - 1) < 0.01 ? 0 : (v * 2 - 1) * 12; if $0.stretch == .resample { $0.stretch = .stretch } }
            }
            knob("MUL", sm.multiplier, x: 166, y: 86, d: 72, s, labelY: 142, bipolar: true, reset: 0.5,
                 display: { v in String(format: "× %.2f", pow(4, Double(v - 0.5) * 2)) }) { v, final in
                editComputed(final) { $0.multiplier = abs(v - 0.5) < 0.01 ? 0.5 : v }
            }
            knob("TIME", timeKnob(sourceSeconds), x: 266, y: 86, d: 72, s, labelY: 142, reset: 0,
                 display: { v in v < 0.01 ? "(none)" : SamplerTime.seconds(Self.seconds(v)).title }) { v, final in
                editComputed(final) { $0.time = v < 0.01 ? .none : .seconds(Self.seconds(v)) }
            }
            // TIME's options (FL's right-click): tap the name
            Color.clear.contentShape(Rectangle()).frame(width: 100 * s, height: 30 * s)
                .bbMenu(title: "TIME: \(sm.time.title)", width: 260) { timeMenu() }
                .offset(x: 216 * s, y: 127 * s)
                .accessibilityIdentifier("samplerTimeMenu")
            label("Mode", s, size: 22).frame(height: 52 * s).offset(x: 348 * s, y: 60 * s)
            menuChip(sm.stretch.title, s)
                .bbMenu(title: "Mode", width: 260) {
                    SamplerStretch.allCases.map { m in BBMenuItem.item(m.title, checked: sm.stretch == m) { edit { $0.stretch = m } } }
                }
                .spot(424, 60, 222, 52, s)
                .accessibilityIdentifier("samplerStretchMode")
        }
    }

    private static func seconds(_ v: Float) -> Double { 0.05 * pow(400, Double(v)) }

    private func timeKnob(_ source: Double) -> Float {
        let d: Double
        switch sm.time {
        case .none: return 0
        case .seconds(let x): d = x
        default: d = source * sm.time.factor(sourceSeconds: source, bpm: controller.state.bpm)
        }
        return Float(log(max(d, 0.05) / 0.05) / log(400)).clamped(0.01, 1)
    }

    private func timeMenu() -> [BBMenuItem] {
        func set(_ t: SamplerTime) { edit { $0.time = t } }
        let beats: [Double] = [1, 2, 4, 8, 16]
        return [.item("(none)", checked: sm.time == .none) { set(.none) },
                .item("Autodetect", checked: sm.time == .autodetect) { set(.autodetect) },
                .item("Project tempo", detail: "\(Int(controller.state.bpm.rounded())) BPM", checked: { if case .projectTempo = sm.time { return true }; return false }()) {
                    set(.projectTempo(controller.state.bpm))
                }]
            + beats.map { b in BBMenuItem.item(SamplerTime.beats(b).title, checked: sm.time == .beats(b)) { set(.beats(b)) } }
    }

    /// Precomputed effects (FL's set, Tyrone, Oct 19): the six switches, then two rows of knobs, each
    /// computed into the track's sound when it's let go (the file on disk is never changed).
    private func effectsPanel(_ s: CGFloat) -> some View {
        let pct: (Float) -> String = { v in "\(Int((v * 100).rounded()))%" }
        let xs: [CGFloat] = [50, 144, 238, 332, 426, 520, 614]
        let xs2: [CGFloat] = [46, 128, 210, 292, 374, 456, 538]
        let row1: CGFloat = 172, row2: CGFloat = 262, d: CGFloat = 52
        return panel("Precomputed effects", s) {
            Group {
            toggleRow("Remove DC offset", sm.removeDC, x: 22, y: 46, w: 210, s, id: "samplerRemoveDC") { edit { $0.removeDC.toggle() } }
            toggleRow("Normalize", sm.normalize, x: 236, y: 46, w: 210, s, id: "samplerNormalize") { edit { $0.normalize.toggle() } }
            toggleRow("Reverse", sm.reverse, x: 450, y: 46, w: 200, s, id: "samplerReverse") { edit { $0.reverse.toggle() } }
            toggleRow("Reverse polarity", sm.reversePolarity, x: 22, y: 88, w: 210, s, id: "samplerPolarity") { edit { $0.reversePolarity.toggle() } }
            toggleRow("Fade stereo", sm.fadeStereo, x: 236, y: 88, w: 210, s, id: "samplerFadeStereo") { edit { $0.fadeStereo.toggle() } }
            toggleRow("Swap stereo", sm.swapStereo, x: 450, y: 88, w: 200, s, id: "samplerSwapStereo") { edit { $0.swapStereo.toggle() } }
            }
            Rectangle().fill(LinearGradient(colors: [.black.opacity(0.5), skin.surface.bright.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                .frame(width: 632 * s, height: 2 * s).offset(x: 16 * s, y: 134 * s)
            Group {
            knob("SMP START", sm.start, x: xs[0], y: row1, d: d, s, labelY: 210, reset: 0, labelSize: 14, display: pct) { v, f in editComputed(f) { $0.start = v } }
            knob("LENGTH", sm.length, x: xs[1], y: row1, d: d, s, labelY: 210, reset: 1, labelSize: 14, display: pct) { v, f in editComputed(f) { $0.length = max(0.005, v) } }
            knob("IN", sm.fadeIn, x: xs[2], y: row1, d: d, s, labelY: 210, reset: 0, labelSize: 14, display: { v in v < 0.005 ? "0%" : pct(v * v) }) { v, f in editComputed(f) { $0.fadeIn = v } }
            knob("OUT", sm.fadeOut, x: xs[3], y: row1, d: d, s, labelY: 210, reset: 0, labelSize: 14, display: { v in v < 0.005 ? "0%" : pct(v * v) }) { v, f in editComputed(f) { $0.fadeOut = v } }
            knob("POGO", (sm.pogo + 1) / 2, x: xs[4], y: row1, d: d, s, labelY: 210, bipolar: true, reset: 0.5, labelSize: 14,
                 display: { v in abs(v * 2 - 1) < 0.01 ? "off" : String(format: "%+.1f st", Double(v * 2 - 1) * 24) }) { v, f in
                editComputed(f) { $0.pogo = abs(v * 2 - 1) < 0.01 ? 0 : v * 2 - 1 }
            }
            // CROSSFADE (FL's CRF): turned up from off, the loop points come on too, so the blended
            // loop keeps going for as long as the note is held (Tyrone, Oct 19)
            knob("CROSSFADE", sm.crossfade, x: xs[5], y: row1, d: d, s, labelY: 210, reset: 0, labelSize: 14, display: { v in v < 0.005 ? "off" : pct(v / 2) }) { v, f in
                let was = controller.sampler(pad).crossfade
                editComputed(f) { $0.crossfade = v; if f && was < 0.005 && v >= 0.005 { $0.useLoop = true } }
            }
            knob("TRIM", sm.trim, x: xs[6], y: row1, d: d, s, labelY: 210, reset: 0, labelSize: 14,
                 display: { v in v < 0.0001 ? "silence" : String(format: "%.0f dB", -90 + 70 * Double(v)) }) { v, f in editComputed(f) { $0.trim = v } }
            }
            Group {
            knob("EQ", (sm.eq + 1) / 2, x: xs2[0], y: row2, d: d, s, labelY: 300, bipolar: true, reset: 0.5, labelSize: 14,
                 display: { v in abs(v * 2 - 1) < 0.01 ? "flat" : (v > 0.5 ? "bright " : "dark ") + pct(abs(v * 2 - 1)) }) { v, f in
                editComputed(f) { $0.eq = abs(v * 2 - 1) < 0.01 ? 0 : v * 2 - 1 }
            }
            knob("BOOST", sm.boost, x: xs2[1], y: row2, d: d, s, labelY: 300, reset: 0, labelSize: 14,
                 display: { v in v < 0.005 ? "0 dB" : String(format: "+%.1f dB", Double(SamplerSettings.boostDB(v))) }) { v, f in
                editComputed(f) { $0.boost = v < 0.005 ? 0 : v }
            }
            knob("RM MIX", sm.rmMix, x: xs2[2], y: row2, d: d, s, labelY: 300, reset: 0, labelSize: 14, display: { v in v < 0.005 ? "off" : pct(v) }) { v, f in
                editComputed(f) { $0.rmMix = v < 0.005 ? 0 : v }
            }
            knob("RM FREQ", sm.rmFreq, x: xs2[3], y: row2, d: d, s, labelY: 300, reset: 0.5, labelSize: 14, display: { v in
                let hz = SamplerSettings.ringHertz(v)
                return hz < 1000 ? "\(Int(hz.rounded())) Hz" : String(format: "%.1f kHz", hz / 1000)
            }) { v, f in editComputed(f) { $0.rmFreq = v } }
            knob("DELAY", sm.delayMix, x: xs2[4], y: row2, d: d, s, labelY: 300, reset: 0, labelSize: 14, display: { v in v < 0.005 ? "off" : pct(v) }) { v, f in
                editComputed(f) { $0.delayMix = v < 0.005 ? 0 : v }
            }
            knob("DLY TIME", sm.delayTime, x: xs2[5], y: row2, d: d, s, labelY: 300, reset: 0.5, labelSize: 14,
                 display: { v in SamplerSettings.step(v).0 }) { v, f in editComputed(f) { $0.delayTime = v } }
            knob("REVERB", sm.reverbMix, x: xs2[6], y: row2, d: d, s, labelY: 300, reset: 0, labelSize: 14, display: { v in v < 0.005 ? "off" : pct(v) }) { v, f in
                editComputed(f) { $0.reverbMix = v < 0.005 ? 0 : v }
            }
            }
            // the reverb's type: A (room) or B (hall), two keys beside REVERB
            VStack(spacing: 4 * s) {
                reverbKey("A", on: !sm.reverbB, s) { edit { $0.reverbB = false } }
                reverbKey("B", on: sm.reverbB, s) { edit { $0.reverbB = true } }
            }
            .frame(width: 44 * s, height: 56 * s).offset(x: 588 * s, y: 234 * s)
            label("TYPE", s, size: 14).frame(width: 60 * s, height: 24 * s).offset(x: 580 * s, y: 288 * s)
        }
    }

    private func reverbKey(_ title: String, on: Bool, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                SamplerMetal(tone: skin.surface, corner: 3 * s)
                Text(title).font(.system(size: 13 * s, weight: .semibold)).foregroundColor(on ? skin.glow : skin.dim)
                    .shadow(color: on ? skin.glow.opacity(0.8) : .clear, radius: 3 * s)
            }
        }
        .buttonStyle(SeqPress())
        .accessibilityIdentifier("samplerReverb" + title)
        .accessibilityValue(on ? "on" : "off")
    }

    // MARK: The sample view

    /// The loop points shown (while a flag is dragged, where it is).
    private var loopPoints: (Float, Float) { loopDrag ?? (sm.loopStart, sm.loopEnd) }

    /// A point on the waveform (0…width) as a part of the sound.
    private func part(_ x: CGFloat, width: CGFloat) -> Double {
        (Double(scrollPos) + Double(x / max(1, width)) / Double(zoom)).clamped(0, 1)
    }
    /// A part of the sound as a point on the waveform.
    private func point(_ f: Double, width: CGFloat) -> CGFloat { CGFloat((f - Double(scrollPos)) * Double(zoom)) * width }

    private func waveform(_ s: CGFloat) -> some View {
        let sample = controller.playedSample(pad)
        let marks = sm.loadSliceMarkers ? (sample?.cues ?? []) : []
        let w = 1334 * s, h = 182 * s
        return ZStack(alignment: .topLeading) {
            SamplerWell(skin: skin, corner: 6 * s).spot(0, 0, 1334, 182, s)
            if let sample {
                SamplerWaveCanvas(sample: sample, zoom: zoom, scroll: scrollPos, color: skin.glow, startOffset: startDrag ?? sm.startOffset,
                                  loop: sm.useLoop, loopPoints: loopPoints, region: sm.loadRegions ? sample.region : nil, cues: marks,
                                  markers: markerDrag.map { d in var m = sm.markers; if m.indices.contains(d.0) { m[d.0] = d.1 }; return m } ?? sm.markers,
                                  regions: sm.regions, selection: selection, bpm: controller.state.bpm)
                    .equatable()
                    .clipShape(RoundedRectangle(cornerRadius: 6 * s)).spot(2, 2, 1330, 178, s)
                // the playback cursor and the played part, following the track's newest voice
                SamplerPlayhead(playheads: controller.engine.playheads, pad: pad, sample: sample, zoom: zoom, scroll: scrollPos,
                                color: UIColor(skin.glow),
                                rest: controller.state.pads[pad].reverse ? 1 - Double(startDrag ?? sm.startOffset) : Double(startDrag ?? sm.startOffset))
                    .clipShape(RoundedRectangle(cornerRadius: 6 * s)).spot(2, 2, 1330, 178, s)
                    .allowsHitTesting(false)
                // bit depth and channels, lower right (FL's readout)
                HStack(spacing: 8 * s) {
                    Text(String(format: "%.3f BPM", controller.state.bpm)).font(.system(size: 16 * s, weight: .medium, design: .monospaced))
                    Text("\(sample.bitDepth)-Bit").font(.system(size: 16 * s, weight: .medium, design: .monospaced))
                    ZStack {
                        Circle().stroke(lineWidth: 1.5 * s).frame(width: 14 * s, height: 14 * s).offset(x: sample.stereo ? -4 * s : 0)
                        if sample.stereo { Circle().stroke(lineWidth: 1.5 * s).frame(width: 14 * s, height: 14 * s).offset(x: 4 * s) }
                    }
                    Text(sample.stereo ? "stereo" : "mono").font(.system(size: 14 * s, weight: .medium))
                }
                .foregroundColor(skin.wellInk.opacity(0.7))
                .frame(width: 1310 * s, height: 170 * s, alignment: .bottomTrailing)
                .allowsHitTesting(false)
                Text(String(format: "%@  ·  %.3f s", fileName, sample.seconds)).font(.system(size: 14 * s, weight: .medium))
                    .foregroundColor(skin.wellInk.opacity(0.55)).padding(10 * s)
                    .frame(width: 900 * s, height: 182 * s, alignment: .bottomLeading).allowsHitTesting(false)
            }
            if sample == nil || dropping {
                Text("DROP SAMPLE HERE").font(.system(size: 36 * s, weight: .medium)).kerning(2 * s)
                    .foregroundColor(dropping ? skin.glow : skin.wellInk.opacity(0.3))
                    .frame(width: 1334 * s, height: 182 * s).allowsHitTesting(false)
            }
            // tap: play it; drag: select; pinch: zoom; tap twice: load another sample from Files
            Color.clear.contentShape(Rectangle()).frame(width: w, height: h)
                .onTapGesture(count: 2) { importFile() }
                .onTapGesture { controller.auditionPad(pad) }
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { v in
                        // a drag that starts on a marker's flag (along the top) moves that marker
                        if selectFrom == nil && markerDrag == nil && v.startLocation.y < 28 * s,
                           let k = sm.markers.indices.min(by: { abs(point(Double(sm.markers[$0]), width: w) - v.startLocation.x) < abs(point(Double(sm.markers[$1]), width: w) - v.startLocation.x) }),
                           abs(point(Double(sm.markers[k]), width: w) - v.startLocation.x) < 22 * s {
                            markerDrag = (k, sm.markers[k])
                        }
                        if let d = markerDrag {
                            markerDrag = (d.0, Float(part(v.location.x, width: w)))
                            return
                        }
                        if selectFrom == nil { selectFrom = part(v.startLocation.x, width: w) }
                        let a = selectFrom ?? 0, b = part(v.location.x, width: w)
                        selection = min(a, b)...max(a, b)
                    }
                    .onEnded { _ in
                        if let d = markerDrag {
                            markerDrag = nil
                            edit { if $0.markers.indices.contains(d.0) { $0.markers[d.0] = d.1; $0.markers.sort() } }
                            return
                        }
                        selectFrom = nil
                        if let sel = selection, sel.upperBound - sel.lowerBound < 0.000_5 { selection = nil }
                    })
                .simultaneousGesture(MagnificationGesture()
                    .onChanged { m in
                        if pinchFrom == nil { pinchFrom = zoom }
                        zoom = ((pinchFrom ?? 1) * m).clamped(1, 64)
                        scrollPos = scrollPos.clamped(0, 1 - 1 / zoom)
                    }
                    .onEnded { _ in pinchFrom = nil })
                .onDrop(of: [.plainText, .fileURL, .audio], isTargeted: $dropping) { providers in drop(providers) }
                // two-finger tap (or right-click): the sample's options
                .bbContextMenu(title: "Sample", width: 320) { waveformMenu() }
                .accessibilityIdentifier("samplerWaveform")
            if sample != nil {
                selectionHandles(w: w, h: h, s)
                if sm.useLoop { loopFlags(w: w, h: h, s) }
                startFlag(w: w, s)
            }
            scrollBar(s).spot(0, 186, 1334, 30, s)
        }
    }

    /// The selection's red handles: drag either edge.
    @ViewBuilder private func selectionHandles(w: CGFloat, h: CGFloat, _ s: CGFloat) -> some View {
        if let sel = selection {
            ForEach(0..<2, id: \.self) { edge in
                let f = edge == 0 ? sel.lowerBound : sel.upperBound
                let x = point(f, width: w)
                if x >= -10 * s && x <= w + 10 * s {
                    SelectionHandle(scale: s, leading: edge == 0)
                        .frame(width: 44 * s, height: h)
                        .contentShape(Rectangle())
                        .position(x: x, y: h / 2)
                        .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { v in
                                if handleFrom == nil { handleFrom = (sel.lowerBound, sel.upperBound) }
                                guard let from = handleFrom else { return }
                                let moved = (edge == 0 ? from.0 : from.1) + Double(v.translation.width / w) / Double(zoom)
                                let other = edge == 0 ? from.1 : from.0
                                let m = moved.clamped(0, 1)
                                selection = min(m, other)...max(m, other)
                            }
                            .onEnded { _ in handleFrom = nil })
                        .accessibilityIdentifier(edge == 0 ? "samplerSelectionStart" : "samplerSelectionEnd")
                }
            }
        }
    }

    /// START OFFSET's flag along the top of the waveform: drag it to start the sound later in.
    private func startFlag(w: CGFloat, _ s: CGFloat) -> some View {
        let f = Double(startDrag ?? sm.startOffset)
        let x = point(f, width: w)
        return HStack(spacing: 3 * s) {
            Rectangle().fill(skin.glow).frame(width: 4 * s, height: 22 * s)
            Text("Start").font(.system(size: 14 * s, weight: .semibold)).foregroundColor(skin.glow)
        }
        .padding(.trailing, 6 * s)
        .frame(height: 30 * s)
        .background(Color.black.opacity(0.35))
        .contentShape(Rectangle())
        .fixedSize()
        .position(x: x + 26 * s, y: 15 * s)
        .opacity(x >= -10 * s && x <= w ? 1 : 0)
        .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                if startFrom == nil { startFrom = sm.startOffset }
                startDrag = ((startFrom ?? 0) + Float(v.translation.width / w) / Float(zoom)).clamped(0, 0.99)
            }
            .onEnded { _ in
                if let d = startDrag { edit { $0.startOffset = d < 0.002 ? 0 : d } }
                startDrag = nil; startFrom = nil
            })
        .accessibilityIdentifier("samplerStartFlag")
    }

    /// The waveform's own menu: play, loop, markers, zoom.
    private func waveformMenu() -> [BBMenuItem] {
        var items: [BBMenuItem] = [
            .item("Play", icon: "play.fill") { controller.auditionPad(pad) },
            .item("Start from the beginning", icon: "backward.end", enabled: sm.startOffset > 0) { edit { $0.startOffset = 0 } },
            .item(sm.useLoop ? "Loop off" : "Loop on", icon: "repeat", checked: sm.useLoop) { edit { $0.useLoop.toggle() } },
            .item("Zoom out", icon: "minus.magnifyingglass", enabled: zoom > 1) { zoom = 1; scrollPos = 0 },
            .item("Load another sample…", icon: "folder") { importFile() }
        ]
        items += propertiesMenu()
        return items
    }

    /// The loop's start and end flags under the waveform: drag them to set the loop points.
    private func loopFlags(w: CGFloat, h: CGFloat, _ s: CGFloat) -> some View {
        let (ls, le) = loopPoints
        return ForEach(0..<2, id: \.self) { edge in
            let f = Double(edge == 0 ? ls : le)
            let x = point(f, width: w)
            LoopFlag(color: skin.glow, leading: edge == 0)
                .frame(width: 30 * s, height: 26 * s)
                .contentShape(Rectangle())
                .position(x: x, y: h - 13 * s)
                .opacity(x >= -15 * s && x <= w + 15 * s ? 1 : 0)
                .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { v in
                        if loopFrom == nil { loopFrom = (sm.loopStart, sm.loopEnd) }
                        guard let from = loopFrom else { return }
                        let d = Float(v.translation.width / w) / Float(zoom)
                        if edge == 0 { loopDrag = ((from.0 + d).clamped(0, from.1 - 0.002), from.1) }
                        else { loopDrag = (from.0, (from.1 + d).clamped(from.0 + 0.002, 1)) }
                    }
                    .onEnded { _ in
                        if let l = loopDrag { edit { $0.loopStart = l.0; $0.loopEnd = l.1 } }
                        loopDrag = nil; loopFrom = nil
                    })
                .accessibilityIdentifier(edge == 0 ? "samplerLoopStart" : "samplerLoopEnd")
        }
    }

    // MARK: The edit bar: select, cut, copy, paste, delete, trim silence, fades, undo, properties

    /// The selection in frames of the sound that plays now.
    private func frames(_ sample: SampleBuffer) -> Range<Int>? {
        guard let sel = selection else { return nil }
        let a = Int(sel.lowerBound * Double(sample.length)), b = Int(sel.upperBound * Double(sample.length))
        return b > a ? a..<min(b, sample.length) : nil
    }

    /// Runs an edit, keeping what the track was for UNDO.
    private func run(_ e: SampleEdit, keepSelection: Bool = false, select: ((Int) -> ClosedRange<Double>?)? = nil) {
        let before = controller.state.pads[pad]
        let oldLength = controller.playedSample(pad)?.length ?? 0
        controller.editSample(pad, e) { name in
            guard name != nil else { return }
            keep(before)
            if let select { selection = select(oldLength) } else if !keepSelection { selection = nil }
        }
    }

    private func editBar(_ s: CGFloat) -> some View {
        let sample = controller.playedSample(pad)
        let range = sample.flatMap { frames($0) }
        let clip = controller.sampleClipboard
        let busy = controller.sampleEditing
        return ZStack(alignment: .topLeading) {
            Group {
                editButton("ALL", "selection.pin.in.out", s, enabled: sample != nil) { selection = 0...1 }
                    .spot(0, 0, 96, 50, s)
                editButton("CUT", "scissors", s, enabled: range != nil && !busy) {
                    guard let sample, let r = range else { return }
                    controller.sampleClipboard = SampleEditor.clip(sample, r)
                    run(.delete(r))
                }
                .spot(102, 0, 96, 50, s)
                editButton("COPY", "doc.on.doc", s, enabled: range != nil) {
                    guard let sample, let r = range else { return }
                    controller.sampleClipboard = SampleEditor.clip(sample, r)
                }
                .spot(204, 0, 96, 50, s)
                editButton("PASTE", "doc.on.clipboard", s, enabled: clip != nil && !busy, menu: true)
                    .bbMenu(title: clip.map { String(format: "Paste %.3f s", Double($0.count) / max(1, $0.sampleRate)) } ?? "Paste", width: 300) { pasteMenu() }
                    .spot(306, 0, 110, 50, s)
                    .accessibilityIdentifier("samplerPaste")
                editButton("DELETE", "delete.left", s, enabled: range != nil && !busy) {
                    guard let r = range else { return }
                    run(.delete(r))
                }
                .spot(422, 0, 110, 50, s)
                editButton("TRIM", "arrow.right.and.line.vertical.and.arrow.left", s, enabled: sample != nil && !busy) { run(.trimSilence) }
                    .spot(538, 0, 96, 50, s)
                editButton("FADE IN", "chart.line.uptrend.xyaxis", s, enabled: range != nil && !busy) {
                    guard let r = range else { return }
                    run(.fadeIn(r), keepSelection: true)
                }
                .spot(640, 0, 120, 50, s)
                editButton("FADE OUT", "chart.line.downtrend.xyaxis", s, enabled: range != nil && !busy) {
                    guard let r = range else { return }
                    run(.fadeOut(r), keepSelection: true)
                }
                .spot(766, 0, 132, 50, s)
                editButton("UNDO", "arrow.uturn.backward", s, enabled: !undo.isEmpty && !busy) { undoStep() }
                .spot(904, 0, 104, 50, s)
            }
            // the selection's length
            Text(selectionText(sample)).font(.system(size: 15 * s, weight: .medium, design: .monospaced))
                .foregroundColor(skin.ink).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 126 * s, height: 50 * s).offset(x: 1012 * s)
                .allowsHitTesting(false)
            editButton("PROPERTIES", "slider.horizontal.3", s, enabled: sample != nil, menu: true)
                .bbMenu(title: "Sample properties", width: 320) { propertiesMenu() }
                .spot(1142, 0, 192, 50, s)
                .accessibilityIdentifier("samplerProperties")
        }
        // pinned to its own top left: without this the bar (only as wide as its widest button) sat centred
        // in its spot, shoved ~570 px right and off the window (Tyrone, Oct 19)
        .frame(width: 1334 * s, height: 50 * s, alignment: .topLeading)
    }

    private func selectionText(_ sample: SampleBuffer?) -> String {
        guard let sample, let sel = selection else { return controller.sampleEditing ? "saving…" : "" }
        return String(format: "%.3f s", (sel.upperBound - sel.lowerBound) * sample.seconds)
    }

    private func editButton(_ title: String, _ icon: String, _ s: CGFloat, enabled: Bool, menu: Bool = false,
                            action: (() -> Void)? = nil) -> some View {
        let face = ZStack {
            SamplerMetal(tone: skin.surface, corner: 5 * s)
            HStack(spacing: 6 * s) {
                Image(systemName: icon).font(.system(size: 15 * s, weight: .semibold))
                Text(title).font(.system(size: 14 * s, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                if menu { Image(systemName: "triangle.fill").rotationEffect(.degrees(180)).font(.system(size: 8 * s)) }
            }
            .foregroundColor(enabled ? skin.ink : skin.dim.opacity(0.5))
            .padding(.horizontal, 6 * s)
        }
        .opacity(enabled ? 1 : 0.75)
        return Group {
            if let action {
                Button(action: action) { face }.buttonStyle(SeqPress()).disabled(!enabled)
                    .accessibilityIdentifier("samplerEdit\(title.replacingOccurrences(of: " ", with: ""))")
            } else {
                face.contentShape(Rectangle()).allowsHitTesting(enabled)
            }
        }
    }

    private func pasteMenu() -> [BBMenuItem] {
        guard let clip = controller.sampleClipboard, let sample = controller.playedSample(pad) else { return [] }
        let range = frames(sample)
        let added = SampleEditor.converted(clip, to: sample.sampleRate).count
        // the pasted audio is selected afterwards
        func selected(at: Int) -> (Int) -> ClosedRange<Double>? {
            { old in
                let total = Double(max(1, old - (range.map { $0.count } ?? 0) + added))
                return Double(at) / total...min(1, Double(at + added) / total)
            }
        }
        var items: [BBMenuItem] = []
        if let r = range {
            items.append(.item("Replace the selection", icon: "rectangle.2.swap") {
                run(.replace(clip, over: r), select: selected(at: r.lowerBound))
            })
            items.append(.item("Insert at the selection's start", icon: "arrow.right.to.line") {
                let before = controller.state.pads[pad]
                let old = sample.length
                controller.editSample(pad, .insert(clip, at: r.lowerBound)) { name in
                    guard name != nil else { return }
                    keep(before)
                    let total = Double(max(1, old + added))
                    selection = Double(r.lowerBound) / total...min(1, Double(r.lowerBound + added) / total)
                }
            })
        }
        items.append(.item("Insert at the start", icon: "backward.end") {
            let before = controller.state.pads[pad]
            let old = sample.length
            controller.editSample(pad, .insert(clip, at: 0)) { name in
                guard name != nil else { return }
                keep(before)
                selection = 0...min(1, Double(added) / Double(max(1, old + added)))
            }
        })
        items.append(.item("Insert at the end", icon: "forward.end") {
            let before = controller.state.pads[pad]
            let old = sample.length
            controller.editSample(pad, .insert(clip, at: old)) { name in
                guard name != nil else { return }
                keep(before)
                selection = Double(old) / Double(max(1, old + added))...1
            }
        })
        return items
    }

    /// Loop points, region markers and beat length (FL's sample properties).
    private func propertiesMenu() -> [BBMenuItem] {
        let sel = selection
        let inSelection = sel.map { r in sm.markers.filter { r.contains(Double($0)) } } ?? []
        var items: [BBMenuItem] = [.header("Loop")]
        items.append(.item("Loop the selection", icon: "repeat", enabled: sel != nil) {
            guard let r = sel else { return }
            edit { $0.loopStart = Float(r.lowerBound); $0.loopEnd = Float(r.upperBound); $0.useLoop = true }
        })
        items.append(.item("Use loop points", checked: sm.useLoop) { edit { $0.useLoop.toggle() } })
        items.append(.item("Ping pong loop", checked: sm.pingPong) { edit { $0.pingPong.toggle(); if $0.pingPong { $0.useLoop = true } } })
        let fades: [(String, Float)] = [("Off", 0), ("5%", 0.1), ("10%", 0.2), ("25%", 0.5), ("50%", 1)]
        let fadeRows: [BBMenuItem] = fades.map { f in
            BBMenuItem.item(f.0, checked: abs(sm.crossfade - f.1) < 0.01) { edit { $0.crossfade = f.1 } }
        }
        items.append(BBMenuItem.submenu("Loop crossfade", icon: "point.topleft.down.curvedto.point.bottomright.up", fadeRows))
        items.append(.item("Loop the whole sound", icon: "arrow.left.and.right", enabled: sm.customLoop) {
            edit { $0.loopStart = 0; $0.loopEnd = 1 }
        })
        items.append(.header("Region markers"))
        items.append(.item(sel == nil ? "Add a marker (select a spot first)" : "Add a marker at the selection", icon: "flag", enabled: sel != nil) {
            guard let r = sel else { return }
            edit { $0.markers = ($0.markers + [Float(r.lowerBound)]).sorted() }
        })
        items.append(.item("Start from the selection", icon: "play", enabled: sel != nil) {
            guard let r = sel else { return }
            edit { $0.startOffset = Float(r.lowerBound).clamped(0, 0.99) }
        })
        items.append(.item("Remove the markers in the selection", icon: "flag.slash", destructive: true, enabled: !inSelection.isEmpty) {
            guard let r = sel else { return }
            edit { $0.markers.removeAll { r.contains(Double($0)) } }
        })
        items.append(.item("Clear all markers", icon: "trash", destructive: true, enabled: !sm.markers.isEmpty) { edit { $0.markers = [] } })
        items.append(.header("Regions"))
        let wide = sel.map { $0.upperBound - $0.lowerBound > 0.001 } ?? false
        items.append(.item(wide ? "Add a region from the selection" : "Add a region (select a part first)", icon: "rectangle.dashed", enabled: wide) {
            guard let r = sel else { return }
            edit { $0.regions.append(SamplerRegion(start: Float(r.lowerBound), end: Float(r.upperBound))); $0.regions.sort { $0.start < $1.start } }
        })
        items.append(.item("Play only the first region", detail: "Load regions", checked: sm.loadRegions, enabled: !sm.regions.isEmpty) { edit { $0.loadRegions.toggle() } })
        let regionsHere = sel.map { r in sm.regions.filter { r.overlaps(Double($0.start)...Double(max($0.start, $0.end))) } } ?? []
        items.append(.item("Remove the regions in the selection", icon: "rectangle.slash", destructive: true, enabled: !regionsHere.isEmpty) {
            guard let r = sel else { return }
            edit { $0.regions.removeAll { r.overlaps(Double($0.start)...Double(max($0.start, $0.end))) } }
        })
        items.append(.item("Clear all regions", icon: "trash", destructive: true, enabled: !sm.regions.isEmpty) { edit { $0.regions = [] } })
        items.append(.header("Beat length"))
        let beats: [Double] = [1, 2, 4, 8, 16, 32]
        var beatRows: [BBMenuItem] = [
            BBMenuItem.item("(none)", checked: sm.time == .none) { edit { $0.time = SamplerTime.none } },
            BBMenuItem.item("Autodetect", checked: sm.time == .autodetect) { edit { $0.time = .autodetect } }
        ]
        beatRows += beats.map { b in BBMenuItem.item(SamplerTime.beats(b).title, checked: sm.time == .beats(b)) { edit { $0.time = .beats(b) } } }
        items.append(BBMenuItem.submenu("Length in beats: \(sm.time.title)", icon: "metronome", beatRows))
        items.append(.item("Lock to the project tempo", detail: "\(Int(controller.state.bpm.rounded())) BPM",
                           checked: { if case .projectTempo = sm.time { return true }; return false }()) {
            edit { $0.time = .projectTempo(controller.state.bpm) }
        })
        return items
    }

    private func scrollBar(_ s: CGFloat) -> some View {
        let step = 0.25 / zoom
        let maxPos = max(0, 1 - 1 / zoom)
        return GeometryReader { g in
            let track = g.size.width - 72 * s
            let thumbW = max(40 * s, track / zoom)
            ZStack(alignment: .leading) {
                SamplerWell(skin: skin, corner: 4 * s)
                // the whole sound, small, under the thumb (the zoom-scroll bar)
                if let sample = controller.playedSample(pad) {
                    SamplerWaveCanvas(sample: sample, zoom: 1, scroll: 0, color: skin.glow, startOffset: 0, loop: false, region: nil, cues: [])
                        .opacity(0.55).padding(.horizontal, 36 * s).padding(.vertical, 2 * s)
                }
                Capsule().fill(LinearGradient(colors: [skin.surface.bright, skin.surface.dark], startPoint: .top, endPoint: .bottom))
                    .frame(width: thumbW, height: 10 * s)
                    .offset(x: 36 * s + (maxPos > 0 ? (track - thumbW) * scrollPos / maxPos : (track - thumbW) / 2))
                    .gesture(DragGesture().onChanged { v in
                        guard maxPos > 0 else { return }
                        scrollPos = (scrollPos + v.translation.width / max(1, track - thumbW) * maxPos / 8).clamped(0, maxPos)
                    })
                HStack {
                    Button { scrollPos = (scrollPos - step).clamped(0, maxPos) } label: { Image(systemName: "chevron.left").frame(width: 36 * s, height: 30 * s) }
                    Spacer()
                    Button { scrollPos = (scrollPos + step).clamped(0, maxPos) } label: { Image(systemName: "chevron.right").frame(width: 36 * s, height: 30 * s) }
                }
                .font(.system(size: 16 * s, weight: .semibold)).foregroundColor(skin.wellInk.opacity(0.7))
                .buttonStyle(SeqPress())
            }
        }
    }

    // MARK: Page 2: ENVELOPE

    private var env: SamplerEnvelope { soundEnvelope ?? sm.envelope(target) }
    private var lfo: SamplerLFO { sm.lfo(target) }
    /// The Volume envelope before it's ever been touched: its knobs and graph show the sound's own shape
    /// (HOLD = how long the sound lasts), and the first edit starts from that, so switching it on changes
    /// nothing and every knob shapes the sound from what it already is (Tyrone, Oct 19). Nil otherwise.
    private var soundEnvelope: SamplerEnvelope? {
        guard target == .volume, sm.envelope(.volume) == SamplerSettings.defaultEnvelopes[SamplerTarget.volume.rawValue],
              let sample = controller.playedSample(pad) else { return nil }
        return Self.measuredEnvelope(sample, reversed: controller.state.pads[pad].reverse, pitchedNotes: pad == Pad.bass808.rawValue)
    }
    /// The last sound measured (the window asks many times a frame).
    private static var measuredCache: (ObjectIdentifier, Bool, Bool, SamplerEnvelope)?
    private static func measuredEnvelope(_ sample: SampleBuffer, reversed: Bool, pitchedNotes: Bool) -> SamplerEnvelope {
        let id = ObjectIdentifier(sample)
        if let c = measuredCache, c.0 == id, c.1 == reversed, c.2 == pitchedNotes { return c.3 }
        let e = SamplerEnvelope.measured(sample, reversed: reversed, pitchedNotes: pitchedNotes)
        measuredCache = (id, reversed, pitchedNotes, e)
        return e
    }
    /// `on`: turning one of its knobs or points switches the envelope on, so you hear it straight away.
    /// `knobs`: a knob (or its Set menu) shapes the envelope, so graph points you added give way to the knobs' shape.
    private func editEnv(on: Bool = false, knobs: Bool = false, _ change: @escaping (inout SamplerEnvelope) -> Void) {
        let t = target
        let seed = soundEnvelope
        edit { $0.setEnvelope(t) { e in if let seed { e = seed }; change(&e); if on { e.on = true }; if knobs { e.points = []; e.sustainPoint = -1 } } }
    }
    /// `bringIn`: an LFO with AMT in the middle does nothing, so picking its shape, speed, delay or
    /// attack brings it in at +50% (turn AMT back to the middle to take it out again).
    private func editLFO(bringIn: Bool = false, _ change: @escaping (inout SamplerLFO) -> Void) {
        let t = target
        edit { $0.setLFO(t) { l in change(&l); if bringIn && abs(l.amount) < 0.001 { l.amount = 0.5 } } }
    }

    private func envelopePage(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            targetTabs(s).spot(36, 168, 1348, 54, s)
            envelopePanel(s).spot(36, 226, 696, 460, s)
            lfoPanel(s).spot(742, 226, 384, 460, s)
            filterPanel(s).spot(1136, 226, 238, 460, s)
            rootBar(s).spot(36, 696, 1348, 66, s)
            keyboard(s).spot(36, 770, 1348, 200, s)
        }
    }

    private func targetTabs(_ s: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(SamplerTarget.allCases, id: \.rawValue) { t in
                let on = target == t
                let lit = sm.envelope(t).on || abs(sm.lfo(t).amount) > 0.001
                Button { target = t } label: {
                    VStack(spacing: 6 * s) {
                        HStack(spacing: 6 * s) {
                            Text(t.title).font(.system(size: 22 * s, weight: on ? .semibold : .regular)).foregroundColor(on ? skin.ink : skin.dim)
                            if lit { Circle().fill(skin.glow).frame(width: 7 * s, height: 7 * s).shadow(color: skin.glow, radius: 3 * s) }
                        }
                        Capsule().fill(on ? skin.glow : .clear).frame(height: 4 * s).shadow(color: on ? skin.glow : .clear, radius: 4 * s)
                    }
                    .padding(.horizontal, 22 * s).frame(height: 54 * s).contentShape(Rectangle())
                }
                .buttonStyle(SeqPress())
                .accessibilityIdentifier("samplerTarget\(t.title.replacingOccurrences(of: " ", with: ""))")
            }
            Spacer()
        }
        .padding(.leading, 34 * s)
    }

    private func envelopePanel(_ s: CGFloat) -> some View {
        let e = env
        let time: (Float) -> String = { v in
            let u = SamplerEnvelope.units(v, tempo: e.tempo)
            return e.tempo ? String(format: "%.2f beats", u) : (u < 1 ? "\(Int((u * 1000).rounded())) ms" : String(format: "%.2f s", u))
        }
        let tension: (Float) -> String = { v in "\(Int(((v * 2 - 1) * 100).rounded()))%" }
        // a time knob's own menu (two-finger tap or right-click): tempo lengths, which turn Tempo on
        func set(_ title: String, _ path: WritableKeyPath<SamplerEnvelope, Float>) -> () -> [BBMenuItem] {
            { [BBMenuItem.header("Set \(title) (tempo)")] + SamplerEnvelope.tempoLengths.map { name, beats in
                BBMenuItem.item(name, checked: e.tempo && abs(SamplerEnvelope.units(e[keyPath: path], tempo: true) - beats) < 0.001) {
                    editEnv(on: true, knobs: true) { $0.tempo = true; $0[keyPath: path] = SamplerEnvelope.knob(beats: beats) }
                }
            } }
        }
        return panel(nil, s) {
            Button { editEnv { $0.on.toggle() } } label: {
                HStack(spacing: 14 * s) {
                    SamplerSwitch(on: e.on, skin: skin).frame(width: 30 * s, height: 30 * s)
                    Text("Envelope").font(.system(size: 22 * s, weight: .medium)).foregroundColor(skin.ink)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SeqPress()).offset(x: 14 * s, y: 12 * s)
            .accessibilityIdentifier("samplerEnvelopeOn").accessibilityValue(e.on ? "on" : "off")
            ZStack {
                SamplerWell(skin: skin)
                EnvelopeGraph(env: e, color: skin.glow).opacity(e.on ? 1 : 0.35).padding(10 * s)
                envelopeEditor(e).padding(10 * s)
            }
            .spot(18, 52, 660, 178, s)
            // AHDSR presets: 808s, kicks, snares, the box method and your own
            menuChip(presetTitle, s, size: 19)
                .bbMenu(title: "Envelope presets", width: 300) { presetMenu() }
                .spot(410, 8, 268, 38, s)
                .accessibilityIdentifier("samplerEnvPresets")
            Group {
            knob("DELAY", e.delay, x: 56, y: 282, d: 64, s, labelY: 327, reset: 0, menu: set("DELAY", \.delay), display: time) { v, _ in editEnv(on: true, knobs: true) { $0.delay = v } }
            knob("ATT", e.attack, x: 154, y: 282, d: 64, s, labelY: 327, reset: 0, menu: set("ATT", \.attack), display: time) { v, _ in editEnv(on: true, knobs: true) { $0.attack = v } }
            knob("HOLD", e.hold, x: 254, y: 282, d: 64, s, labelY: 327, reset: 0, menu: set("HOLD", \.hold), display: time) { v, _ in editEnv(on: true, knobs: true) { $0.hold = v } }
            knob("DEC", e.decay, x: 353, y: 282, d: 64, s, labelY: 327, reset: 0, menu: set("DEC", \.decay), display: time) { v, _ in editEnv(on: true, knobs: true) { $0.decay = v } }
            knob("SUS", e.sustain, x: 451, y: 282, d: 64, s, labelY: 327, reset: 1, display: { v in "\(Int((v * 100).rounded()))%" }) { v, _ in editEnv(on: true, knobs: true) { $0.sustain = v } }
            knob("REL", e.release, x: 548, y: 282, d: 64, s, labelY: 327, reset: 0, menu: set("REL", \.release), display: time) { v, _ in editEnv(on: true, knobs: true) { $0.release = v } }
            }
            if target != .volume {
                knob("AMT", (e.amount + 1) / 2, x: 640, y: 282, d: 54, s, labelY: 327, bipolar: true, reset: 0.5,
                     display: { v in "\(Int(((v * 2 - 1) * 100).rounded()))%" }) { v, _ in editEnv(on: true) { $0.amount = abs(v * 2 - 1) < 0.02 ? 0 : v * 2 - 1 } }
            }
            Group {
            knob("TENSION", (e.attackTension + 1) / 2, x: 154, y: 370, d: 46, s, labelY: 407, bipolar: true, reset: 0.5, labelSize: 15, id: "AttTension", display: tension) { v, _ in editEnv(on: true, knobs: true) { $0.attackTension = v * 2 - 1 } }
            knob("TENSION", (e.decayTension + 1) / 2, x: 353, y: 370, d: 46, s, labelY: 407, bipolar: true, reset: 0.5, labelSize: 15, id: "DecTension", display: tension) { v, _ in editEnv(on: true, knobs: true) { $0.decayTension = v * 2 - 1 } }
            knob("TENSION", (e.releaseTension + 1) / 2, x: 548, y: 370, d: 46, s, labelY: 407, bipolar: true, reset: 0.5, labelSize: 15, id: "RelTension", display: tension) { v, _ in editEnv(on: true, knobs: true) { $0.releaseTension = v * 2 - 1 } }
            }
            smallToggle("Tempo", e.tempo, x: 690, y: 394, s, id: "samplerEnvTempo") { editEnv { $0.tempo.toggle() } }
        }
    }

    /// The envelope graph's touch layer: drag a point to move it, drag a diamond up or down to bend its
    /// curve; tap empty space to add a point there and double tap a point to delete it (FL style:
    /// the knobs' shape turns into free points the first time); a two-finger tap (or a right-click)
    /// opens the points menu (sustain point, straighten, back to the knobs' shape).
    private func envelopeEditor(_ e: SamplerEnvelope) -> some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if envDrag == nil {
                            let handles = EnvelopeGraph.handles(e, width: w, height: h)
                            let near = handles.enumerated().min { hypot($0.1.x - v.startLocation.x, $0.1.y - v.startLocation.y) < hypot($1.1.x - v.startLocation.x, $1.1.y - v.startLocation.y) }
                            guard let near, hypot(near.1.x - v.startLocation.x, near.1.y - v.startLocation.y) < 34 else { return }
                            envDrag = (near.0, e)
                        }
                        guard let drag = envDrag else { return }
                        let dy = Float(-v.translation.height / max(h * 0.9, 1))
                        let moved = drag.from.usesPoints
                            ? Self.draggedPoint(drag.from, handle: drag.handle, dt: Float(v.translation.width / EnvelopeGraph.pixelsPerUnit(drag.from, width: w)), dy: dy)
                            : Self.dragged(drag.from, handle: drag.handle, dx: Float(v.translation.width / max(w, 1)), dy: dy)
                        editEnv { $0 = moved }
                    }
                    .onEnded { _ in envDrag = nil })
                .simultaneousGesture(SpatialTapGesture().onEnded { v in
                    // one tap on empty space adds a point (Tyrone, Oct 18); a double tap on a point deletes it
                    let handles = EnvelopeGraph.handles(e, width: w, height: h)
                    let pts = e.usesPoints ? EnvelopeGraph.pointXY(e, width: w, height: h) : []
                    if let hit = pts.indices.first(where: { hypot(pts[$0].x - v.location.x, pts[$0].y - v.location.y) < 26 }) {
                        let now = Date()
                        if envPointTap.index == hit && now.timeIntervalSince(envPointTap.time) < 0.4 {
                            envPointTap = (-1, .distantPast)
                            editEnv(on: true) { $0 = Self.removingPoint(hit, from: $0) }
                        } else {
                            envPointTap = (hit, now)
                        }
                    } else if handles.contains(where: { hypot($0.x - v.location.x, $0.y - v.location.y) < 26 }) {
                        // a tap on one of the knob shape's points or a curve handle adds nothing
                    } else {
                        let p = e.withPoints()
                        let time = Float(v.location.x / EnvelopeGraph.pixelsPerUnit(p, width: w))
                        let level = Float((h - 2 - v.location.y) / max(h * 0.9, 1)).clamped(0, 1)
                        editEnv(on: true) { $0 = Self.addingPoint(time: time, level: level, to: $0) }
                    }
                })
                .bbContextMenu(title: "Envelope points", width: 300) { envelopePointItems(e) }
        }
        .accessibilityIdentifier("samplerEnvGraph")
        .accessibilityValue(e.usesPoints ? "\(e.points.count) points" : "knobs")
    }

    /// Adds a point `time` from the start (seconds, or beats with Tempo) at `level`; the points after it stay where they are.
    static func addingPoint(time: Float, level: Float, to from: SamplerEnvelope) -> SamplerEnvelope {
        var e = from.withPoints()
        guard e.points.count < SamplerEnvPoints.capacity else { return e }
        var start: Float = 0
        var at = e.points.count
        for (i, p) in e.points.enumerated() {
            if start + p.time > time { at = i; break }
            start += p.time
        }
        let gap = max(0, time - start)
        if at < e.points.count { e.points[at].time = max(0, e.points[at].time - gap) }
        e.points.insert(SamplerEnvPoint(time: gap, level: level), at: at)
        if e.sustainPoint >= at { e.sustainPoint += 1 }
        return e
    }

    /// Deletes point `i`; the points after it stay where they are. The last one gone = the knobs' shape again.
    static func removingPoint(_ i: Int, from: SamplerEnvelope) -> SamplerEnvelope {
        var e = from
        guard e.points.indices.contains(i) else { return e }
        let gap = e.points[i].time
        e.points.remove(at: i)
        if i < e.points.count { e.points[i].time += gap }
        if e.sustainPoint == i { e.sustainPoint = -1 } else if e.sustainPoint > i { e.sustainPoint -= 1 }
        if e.points.isEmpty { e.sustainPoint = -1 }
        return e
    }

    /// A graph point (handle < count) moved by `dt` (seconds, or beats) and `dy` of the height, or the
    /// curve into point handle − count bent by `dy`.
    static func draggedPoint(_ from: SamplerEnvelope, handle: Int, dt: Float, dy: Float) -> SamplerEnvelope {
        var e = from
        e.on = true
        let n = e.points.count
        if handle < n {
            e.points[handle].time = (from.points[handle].time + dt).clamped(0, from.maxPointTime)
            e.points[handle].level = (from.points[handle].level + dy).clamped(0, 1)
        } else if handle - n < n {
            let i = handle - n
            let before: Float = i == 0 ? 0 : from.points[i - 1].level
            let rising = from.points[i].level >= before
            e.points[i].tension = (from.points[i].tension + (rising ? -dy : dy) * 2).clamped(-1, 1)
        }
        return e
    }

    /// A point (0 attack start … 5 release end) or a curve (6 attack, 7 decay, 8 release) dragged by
    /// `dx` of the graph's width and `dy` of its height (up is positive).
    static func dragged(_ from: SamplerEnvelope, handle: Int, dx: Float, dy: Float) -> SamplerEnvelope {
        var e = from
        e.on = true
        let fx = dx * 1.5
        switch handle {
        case 0: e.delay = (from.delay + fx).clamped(0, 1)
        case 1: e.attack = (from.attack + fx).clamped(0, 1)
        case 2: e.hold = (from.hold + fx).clamped(0, 1)
        case 3: e.decay = (from.decay + fx).clamped(0, 1); e.sustain = (from.sustain + dy).clamped(0, 1)
        case 4: e.sustain = (from.sustain + dy).clamped(0, 1)
        case 5: e.release = (from.release + fx).clamped(0, 1)
        // up bulges a rising curve (less tension) and a falling one (more)
        case 6: e.attackTension = (from.attackTension - dy * 2).clamped(-1, 1)
        case 7: e.decayTension = (from.decayTension + dy * 2).clamped(-1, 1)
        case 8: e.releaseTension = (from.releaseTension + dy * 2).clamped(-1, 1)
        default: break
        }
        return e
    }

    private func envelopePointItems(_ e: SamplerEnvelope) -> [BBMenuItem] {
        if e.usesPoints {
            let sustainRows: [BBMenuItem] = [.item("None (runs straight through)", checked: e.sustainPoint < 0) { editEnv(on: true) { $0.sustainPoint = -1 } }]
                + e.points.indices.map { i in
                    BBMenuItem.item("Point \(i + 1)", detail: "\(Int((e.points[i].level * 100).rounded()))%", checked: e.sustainPoint == i) { editEnv(on: true) { $0.sustainPoint = i } }
                }
            return [
                .header("Tap the graph to add a point, double tap a point to delete it"),
                .submenu("Sustain point", icon: "pause", sustainRows),
                .item("Delete the last point", icon: "minus.circle", destructive: true) { editEnv(on: true) { $0 = Self.removingPoint($0.points.count - 1, from: $0) } },
                .item("Straighten the curves", icon: "line.diagonal") { editEnv(on: true) { for i in $0.points.indices { $0.points[i].tension = 0 } } },
                .item("Back to the knobs' shape", icon: "dial.medium") { editEnv(on: true) { $0.points = []; $0.sustainPoint = -1 } },
                .item(e.on ? "Turn the envelope off" : "Turn the envelope on", icon: "power", checked: e.on) { editEnv { $0.on.toggle() } },
            ]
        }
        let d = SamplerEnvelope.shaped
        let stages: [(String, WritableKeyPath<SamplerEnvelope, Float>, Float)] = [("delay", \.delay, 0.2), ("attack", \.attack, d.attack), ("hold", \.hold, d.hold),
                                                                               ("decay", \.decay, d.decay), ("release", \.release, d.release)]
        var items: [BBMenuItem] = stages.map { name, path, back in
            e[keyPath: path] > 0.001
                ? BBMenuItem.item("Remove the \(name) point", icon: "minus.circle", destructive: true) { editEnv(on: true) { $0[keyPath: path] = 0 } }
                : BBMenuItem.item("Add a \(name) point", icon: "plus.circle") { editEnv(on: true) { $0[keyPath: path] = back } }
        }
        items.append(e.sustain > 0.001
                     ? .item("Remove the sustain (level to 0)", icon: "minus.circle", destructive: true) { editEnv(on: true) { $0.sustain = 0 } }
                     : .item("Add a sustain level", icon: "plus.circle") { editEnv(on: true) { $0.sustain = 0.5 } })
        items.append(.item("Straighten the curves", icon: "line.diagonal") { editEnv(on: true) { $0.attackTension = 0; $0.decayTension = 0; $0.releaseTension = 0 } })
        items.append(.item(e.on ? "Turn the envelope off" : "Turn the envelope on", icon: "power", checked: e.on) { editEnv { $0.on.toggle() } })
        return items
    }

    // MARK: Envelope presets

    /// The preset whose envelopes the track has now, if any.
    private var presetTitle: String {
        _ = presetsChanged
        let all = [SamplerEnvelopePreset.boxMethod] + SamplerEnvelopePreset.factory + SamplerEnvelopePreset.saved
        return all.first { $0.envelopes == sm.envelopes }?.name ?? "Presets"
    }

    private func presetMenu() -> [BBMenuItem] {
        let saved = SamplerEnvelopePreset.saved
        func row(_ p: SamplerEnvelopePreset) -> BBMenuItem {
            .item(p.name, checked: p.envelopes == sm.envelopes) {
                edit { $0.envelopes = p.envelopes }
                target = .volume
            }
        }
        let box = SamplerEnvelopePreset.boxMethod
        var items: [BBMenuItem] = [
            .item(box.name, detail: "Full level while held, stops when you let go", icon: "square", checked: box.envelopes == sm.envelopes) {
                edit { $0.envelopes = box.envelopes }
                target = .volume
            }
        ]
        for kind in SamplerEnvelopePreset.kinds {
            var rows: [BBMenuItem] = SamplerEnvelopePreset.factory.filter { $0.kind == kind }.map(row)
            let mine = saved.filter { $0.kind == kind }
            if !mine.isEmpty { rows.append(BBMenuItem.header("Yours")); rows += mine.map(row) }
            items.append(BBMenuItem.submenu(kind == "808" ? "808s" : kind + "s", icon: "waveform.path", rows))
        }
        let saveRows: [BBMenuItem] = SamplerEnvelopePreset.kinds.map { kind in
            let word = kind == "808" ? "808" : kind.lowercased()
            return BBMenuItem.item("As a\(kind == "808" ? "n" : "") \(word) preset…") {
                presetName = "My \(word) \(saved.filter { $0.kind == kind }.count + 1)"
                savingKind = kind
            }
        }
        items.append(BBMenuItem.submenu("Save this envelope", icon: "square.and.arrow.down", saveRows))
        if !saved.isEmpty {
            let deleteRows: [BBMenuItem] = saved.map { p in
                BBMenuItem.item("\(p.name) (\(p.kind))", destructive: true) { SamplerEnvelopePreset.delete(p); presetsChanged += 1 }
            }
            items.append(BBMenuItem.submenu("Delete one of yours", icon: "trash", deleteRows))
        }
        items.append(.item("Reset the envelopes", icon: "arrow.counterclockwise") { edit { $0.envelopes = SamplerSettings.defaultEnvelopes } })
        return items
    }

    private func savePreset() {
        guard let kind = savingKind else { return }
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        savingKind = nil
        guard !name.isEmpty else { return }
        SamplerEnvelopePreset.save(SamplerEnvelopePreset(name: name, kind: kind, envelopes: sm.envelopes))
        presetsChanged += 1
    }

    /// A label and a small switch, right-aligned on `x`.
    private func smallToggle(_ title: String, _ on: Bool, x: CGFloat, y: CGFloat, _ s: CGFloat, id: String, _ flip: @escaping () -> Void) -> some View {
        Button(action: flip) {
            HStack(spacing: 10 * s) {
                Text(title).font(.system(size: 19 * s)).foregroundColor(skin.ink)
                SamplerSwitch(on: on, skin: skin).frame(width: 28 * s, height: 28 * s)
            }
            .frame(width: 150 * s, height: 40 * s, alignment: .trailing).contentShape(Rectangle())
        }
        .buttonStyle(SeqPress())
        .accessibilityIdentifier(id)
        .accessibilityValue(on ? "on" : "off")
        .offset(x: (x - 150) * s, y: (y - 20) * s)
    }

    private func lfoPanel(_ s: CGFloat) -> some View {
        let l = lfo
        let shapes = ["Sine", "Triangle", "Square"]
        // a knob's own menu: tempo lengths (the LFO's DELAY and ATT go up to 2 bars), which turn Tempo on
        func set(_ title: String, _ path: WritableKeyPath<SamplerLFO, Float>) -> () -> [BBMenuItem] {
            { [BBMenuItem.header("Set \(title) (tempo)")] + SamplerEnvelope.tempoLengths.filter { $0.1 <= 8 }.map { name, beats in
                BBMenuItem.item(name, checked: l.tempo && abs(SamplerEnvelope.units(l[keyPath: path], tempo: true) * 0.5 - beats) < 0.001) {
                    editLFO(bringIn: true) { $0.tempo = true; $0[keyPath: path] = SamplerEnvelope.knob(beats: beats, scale: 0.5) }
                }
            } }
        }
        let speeds: () -> [BBMenuItem] = {
            [BBMenuItem.header("Set SPEED (tempo)")] + SamplerLFO.divisions.enumerated().map { i, d in
                BBMenuItem.item("One cycle every \(d.0)", checked: l.tempo && l.division.0 == d.0) {
                    editLFO(bringIn: true) { $0.tempo = true; $0.speed = (Float(i) + 0.5) / Float(SamplerLFO.divisions.count) }
                }
            }
        }
        return panel(nil, s) {
            HStack(spacing: 6 * s) {
                ForEach(0..<3, id: \.self) { i in
                    Button { editLFO(bringIn: true) { $0.shape = i } } label: {
                        ZStack {
                            if l.shape == i { SamplerWell(skin: skin, corner: 4 * s) }
                            LFOShapeGlyph(shape: i).stroke(l.shape == i ? skin.glow : skin.ink, style: StrokeStyle(lineWidth: 2.5 * s, lineJoin: .round))
                                .frame(width: 32 * s, height: 24 * s)
                        }
                        .frame(width: 62 * s, height: 46 * s).contentShape(Rectangle())
                    }
                    .buttonStyle(SeqPress())
                    .accessibilityLabel(shapes[i]).accessibilityValue(l.shape == i ? "on" : "off")
                    .accessibilityIdentifier("samplerLFOShape\(i)")
                }
                Text("LFO").font(.system(size: 22 * s, weight: .medium)).foregroundColor(skin.ink).padding(.leading, 8 * s)
            }
            .offset(x: 12 * s, y: 8 * s)
            ZStack {
                SamplerWell(skin: skin)
                LFOGraph(lfo: l, color: skin.glow).padding(8 * s)
            }
            .spot(12, 58, 356, 172, s)
            let time: (Float) -> String = { v in
                let u = SamplerEnvelope.units(v, tempo: l.tempo) * 0.5
                return l.tempo ? String(format: "%.2f beats", u) : (u < 1 ? "\(Int((u * 1000).rounded())) ms" : String(format: "%.2f s", u))
            }
            knob("DELAY", l.delay, x: 49, y: 282, d: 62, s, labelY: 327, reset: 0, id: "LFODELAY", menu: set("DELAY", \.delay), display: time) { v, _ in editLFO(bringIn: true) { $0.delay = v } }
            knob("ATT", l.attack, x: 141, y: 282, d: 62, s, labelY: 327, reset: 0, id: "LFOATT", menu: set("ATT", \.attack), display: time) { v, _ in editLFO(bringIn: true) { $0.attack = v } }
            knob("AMT", (l.amount + 1) / 2, x: 234, y: 282, d: 62, s, labelY: 327, bipolar: true, reset: 0.5, id: "LFOAMT",
                 display: { v in "\(Int(((v * 2 - 1) * 100).rounded()))%" }) { v, _ in editLFO { $0.amount = abs(v * 2 - 1) < 0.02 ? 0 : v * 2 - 1 } }
            knob("SPEED", l.speed, x: 327, y: 282, d: 62, s, labelY: 327, reset: 0.5, id: "LFOSPEED", menu: speeds,
                 display: { v in var c = l; c.speed = v; return c.speedLabel }) { v, _ in editLFO(bringIn: true) { $0.speed = v } }
            smallToggle("Tempo", l.tempo, x: 160, y: 394, s, id: "samplerLFOTempo") { editLFO(bringIn: true) { $0.tempo.toggle() } }
            smallToggle("Global", l.global, x: 330, y: 394, s, id: "samplerLFOGlobal") { editLFO(bringIn: true) { $0.global.toggle() } }
        }
    }

    private func filterPanel(_ s: CGFloat) -> some View {
        panel(nil, s) {
            ZStack(alignment: .leading) {
                SamplerMetal(tone: skin.surface, corner: 4 * s)
                Text("Filter").font(.system(size: 22 * s, weight: .medium)).foregroundColor(skin.ink).padding(.leading, 12 * s)
            }
            .spot(10, 8, 218, 44, s)
            knob("MOD X", sm.cutoff, x: 118, y: 136, d: 92, s, labelY: 66, reset: 1,
                 display: { v in let hz = 20 * pow(1000, Double(v)); return hz < 1000 ? "\(Int(hz)) Hz" : String(format: "%.1f kHz", hz / 1000) }) { v, _ in edit { $0.cutoff = v } }
            knob("MOD Y", sm.resonance, x: 118, y: 290, d: 92, s, labelY: 220, reset: 0,
                 display: { v in "\(Int((v * 100).rounded()))%" }) { v, _ in edit { $0.resonance = v } }
            menuChip(sm.filterType.title, s)
                .bbMenu(title: "Filter type", width: 220) {
                    SamplerFilterType.allCases.map { t in BBMenuItem.item(t.title, checked: sm.filterType == t) { edit { $0.filterType = t } } }
                }
                .spot(20, 362, 198, 52, s)
                .accessibilityIdentifier("samplerFilterType")
        }
    }

    // MARK: Page 3: MISC (Tyrone's third render, Oct 18). What each control does: SamplerSettings / KnockEngine.trigger

    private func miscPage(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            levelsPanel(s).spot(36, 176, 372, 244, s)
            polyphonyPanel(s).spot(414, 176, 300, 244, s)
            timePanel(s).spot(720, 176, 320, 244, s)
            trackingPanel(s).spot(1046, 176, 338, 244, s)
            groupPanel(s).spot(36, 426, 250, 260, s)
            arpPanel(s).spot(292, 426, 560, 260, s)
            echoPanel(s).spot(858, 426, 526, 260, s)
            rootBar(s).spot(36, 696, 1348, 66, s)
            keyboard(s).spot(36, 770, 1348, 200, s)
        }
    }

    /// A count with − and + either side (Max, Cut, By, Range, Repeat, Echoes), its name underneath.
    private func stepper(_ title: String, _ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 120, _ s: CGFloat, id: String,
                         down: @escaping () -> Void, up: @escaping () -> Void) -> some View {
        VStack(spacing: 6 * s) {
            HStack(spacing: 0) {
                Button(action: down) { Image(systemName: "minus").frame(width: 30 * s, height: 44 * s).contentShape(Rectangle()) }
                    .accessibilityIdentifier(id + "Down")
                ZStack {
                    SamplerWell(skin: skin, corner: 3 * s)
                    Text(text).font(.system(size: 24 * s, weight: .medium, design: .monospaced)).foregroundColor(skin.glow)
                        .shadow(color: skin.glow.opacity(0.8), radius: 4 * s).lineLimit(1).minimumScaleFactor(0.5)
                }
                .accessibilityElement().accessibilityIdentifier(id).accessibilityValue(text)
                Button(action: up) { Image(systemName: "plus").frame(width: 30 * s, height: 44 * s).contentShape(Rectangle()) }
                    .accessibilityIdentifier(id + "Up")
            }
            .font(.system(size: 16 * s, weight: .bold)).foregroundColor(skin.ink)
            .buttonStyle(SeqPress())
            .frame(height: 44 * s)
            label(title, s)
        }
        .frame(width: w * s)
        .offset(x: x * s, y: y * s)
    }

    private static func percent(_ v: Float) -> String { "\(Int((v * 100).rounded()))%" }
    private static func bipolarPercent(_ v: Float) -> String { "\(Int(((v * 2 - 1) * 100).rounded()))%" }
    private static func cutoffText(_ v: Float) -> String {
        let hz = 20 * pow(1000, Double(v)); return hz < 1000 ? "\(Int(hz)) Hz" : String(format: "%.1f kHz", hz / 1000)
    }
    private static func bipolar(_ v: Float) -> Float { abs(v * 2 - 1) < 0.02 ? 0 : v * 2 - 1 }

    /// Levels adjustment (FL's MISC offsets): PAN, VOL, MOD X and MOD Y on top of the main ones, on every note.
    private func levelsPanel(_ s: CGFloat) -> some View {
        panel("Levels adjustment", s) {
            knob("PAN", (sm.levelPan + 1) / 2, x: 55, y: 120, d: 62, s, labelY: 166, bipolar: true, reset: 0.5, id: "LevelsPAN",
                 display: { v in let p = Int(((v * 2 - 1) * 100).rounded()); return p == 0 ? "C" : (p < 0 ? "L\(-p)" : "R\(p)") }) { v, _ in
                edit { $0.levelPan = Self.bipolar(v) }
            }
            knob("VOL", sm.levelVol, x: 142, y: 120, d: 76, s, labelY: 173, reset: 0.5, id: "LevelsVOL",
                 display: SamplerSettings.volumeText) { v, _ in edit { $0.levelVol = abs(v - 0.5) < 0.01 ? 0.5 : v } }
            knob("MOD X", (sm.levelX + 1) / 2, x: 229, y: 120, d: 62, s, labelY: 166, bipolar: true, reset: 0.5, id: "LevelsMODX",
                 display: Self.bipolarPercent) { v, _ in edit { $0.levelX = Self.bipolar(v) } }
            knob("MOD Y", (sm.levelY + 1) / 2, x: 316, y: 120, d: 62, s, labelY: 166, bipolar: true, reset: 0.5, id: "LevelsMODY",
                 display: Self.bipolarPercent) { v, _ in edit { $0.levelY = Self.bipolar(v) } }
        }
    }

    /// Polyphony: Max notes at once (∞ = no limit), SLIDE (the glide's time), Porta, Mono.
    private func polyphonyPanel(_ s: CGFloat) -> some View {
        panel("Polyphony", s) {
            stepper("MAX", sm.polyMax == 0 ? "∞" : "\(sm.polyMax)", x: 18, y: 64, w: 130, s, id: "samplerPolyMax",
                    down: { edit { $0.polyMax = max(0, $0.polyMax - 1) } }, up: { edit { $0.polyMax = min(16, $0.polyMax + 1) } })
            knob("SLIDE", sm.slide, x: 226, y: 96, d: 62, s, labelY: 142, reset: 0.3, id: "SLIDE",
                 display: { v in let t = SamplerSettings.slideSeconds(v); return t < 1 ? "\(Int((t * 1000).rounded())) ms" : String(format: "%.2f s", t) }) { v, _ in edit { $0.slide = v } }
            smallToggle("Porta", sm.porta, x: 160, y: 206, s, id: "samplerPorta") { edit { $0.porta.toggle() } }
            smallToggle("Mono", sm.mono, x: 290, y: 206, s, id: "samplerMono") { edit { $0.mono.toggle() } }
        }
    }

    /// Time: GATE (every note's length; all the way down = off), SHIFT (push / pull) and SWING (the
    /// track's own swing in the pattern), Full porta.
    private func timePanel(_ s: CGFloat) -> some View {
        panel("Time", s) {
            knob("GATE", sm.gate, x: 55, y: 110, d: 62, s, labelY: 156, reset: 0, id: "GATE",
                 display: { v in let t = SamplerSettings.gateSeconds(v); return t == 0 ? "Off" : (t < 1 ? "\(Int((t * 1000).rounded())) ms" : String(format: "%.2f s", t)) }) { v, _ in
                edit { $0.gate = v < 0.01 ? 0 : v }
            }
            knob("SHIFT", (shift / PatternData.maxShift + 1) / 2, x: 160, y: 110, d: 62, s, labelY: 156, bipolar: true, reset: 0.5, id: "SHIFT",
                 display: { v in
                     let t = ((v * 2 - 1) * PatternData.maxShift).rounded()
                     return t == 0 ? "On the grid" : "\(Int(abs(t))) ticks \(t < 0 ? "early" : "late")"
                 }) { v, final in setFeel?(nil, ((v * 2 - 1) * PatternData.maxShift).rounded(), final) }
            knob("SWING", max(0, swing), x: 265, y: 110, d: 62, s, labelY: 156, reset: 0, id: "SWING",
                 menu: { [BBMenuItem.item("Follow the SWING knob", checked: swing < 0) { setFeel?(-1, nil, true) }] },
                 display: { v in swing < 0 && v == 0 ? "SWING knob" : "\(Int((50 + v * 22).rounded()))%" }) { v, final in setFeel?(v, nil, final) }
            smallToggle("Full porta", sm.fullPorta, x: 300, y: 214, s, id: "samplerFullPorta") { edit { $0.fullPorta.toggle() } }
        }
    }

    /// Tracking: how far velocity (Vol) or the note's distance from Mid (Key) moves PAN, MOD X and MOD Y.
    private func trackingPanel(_ s: CGFloat) -> some View {
        let tab = trackingTab
        let values = tab == 0 ? sm.velTrack : sm.keyTrack
        func value(_ i: Int) -> Float { i < values.count ? values[i] : 0 }
        func set(_ i: Int, _ v: Float) {
            edit { st in
                if tab == 0 { while st.velTrack.count < 3 { st.velTrack.append(0) }; st.velTrack[i] = v }
                else { while st.keyTrack.count < 3 { st.keyTrack.append(0) }; st.keyTrack[i] = v }
            }
        }
        return panel(nil, s) {
            HStack(spacing: 4 * s) {
                ForEach(0..<2, id: \.self) { i in
                    Button { trackingTab = i } label: {
                        VStack(spacing: 4 * s) {
                            Text(i == 0 ? "Vol" : "Key").font(.system(size: 21 * s, weight: tab == i ? .semibold : .regular))
                                .foregroundColor(tab == i ? skin.ink : skin.dim)
                            Capsule().fill(tab == i ? skin.glow : .clear).frame(height: 4 * s).shadow(color: tab == i ? skin.glow : .clear, radius: 4 * s)
                        }
                        .frame(width: 64 * s, height: 44 * s).contentShape(Rectangle())
                    }
                    .buttonStyle(SeqPress())
                    .accessibilityIdentifier(i == 0 ? "samplerTrackVol" : "samplerTrackKey")
                    .accessibilityValue(tab == i ? "on" : "off")
                }
                Text("Tracking").font(.system(size: 22 * s, weight: .medium)).foregroundColor(skin.ink).padding(.leading, 8 * s)
            }
            .offset(x: 12 * s, y: 6 * s)
            knob("PAN", (value(0) + 1) / 2, x: 62, y: 106, d: 58, s, labelY: 150, bipolar: true, reset: 0.5, id: "TrackPAN",
                 display: Self.bipolarPercent) { v, _ in set(0, Self.bipolar(v)) }
            knob("MOD X", (value(1) + 1) / 2, x: 169, y: 106, d: 58, s, labelY: 150, bipolar: true, reset: 0.5, id: "TrackMODX",
                 display: Self.bipolarPercent) { v, _ in set(1, Self.bipolar(v)) }
            knob("MOD Y", (value(2) + 1) / 2, x: 276, y: 106, d: 58, s, labelY: 150, bipolar: true, reset: 0.5, id: "TrackMODY",
                 display: Self.bipolarPercent) { v, _ in set(2, Self.bipolar(v)) }
            // Mid: the note that Key tracking leaves alone
            label("Mid: \(Self.noteName(sm.keyMid))", s).frame(width: 110 * s, height: 30 * s, alignment: .leading).offset(x: 16 * s, y: 196 * s)
            midSlider(s).spot(124, 190, 196, 42, s).opacity(tab == 1 ? 1 : 0.45)
        }
    }

    private func midSlider(_ s: CGFloat) -> some View {
        GeometryReader { g in
            let w = g.size.width
            let lo = 24, hi = 108
            let x = CGFloat(sm.keyMid.clamped(lo, hi) - lo) / CGFloat(hi - lo) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.05)).overlay(Capsule().stroke(skin.surface.bright.opacity(0.5), lineWidth: 1)).frame(height: 10 * s)
                ZStack {
                    Circle().fill(skin.cap.spun)
                    Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
                    Capsule().fill(skin.glow).frame(width: 3 * s, height: 14 * s)
                }
                .frame(width: 30 * s, height: 30 * s).offset(x: x - 15 * s)
                .shadow(color: .black.opacity(0.6), radius: 3 * s, y: 2 * s)
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let n = lo + Int((Float(v.location.x / max(w, 1)) * Float(hi - lo)).rounded())
                edit { $0.keyMid = n.clamped(lo, hi) }
            })
            .onTapGesture(count: 2) { edit { $0.keyMid = 60 } }
        }
        .accessibilityElement().accessibilityIdentifier("samplerKeyMid").accessibilityValue(Self.noteName(sm.keyMid))
    }

    /// Group: a note on this track stops the tracks whose By is this track's Cut; Cut self stops its own.
    private func groupPanel(_ s: CGFloat) -> some View {
        panel("Group", s) {
            stepper("CUT", sm.cutGroup == 0 ? "–" : "\(sm.cutGroup)", x: 14, y: 62, w: 106, s, id: "samplerCut",
                    down: { edit { $0.cutGroup = max(0, $0.cutGroup - 1) } }, up: { edit { $0.cutGroup = min(16, $0.cutGroup + 1) } })
            stepper("BY", sm.cutBy == 0 ? "–" : "\(sm.cutBy)", x: 128, y: 62, w: 106, s, id: "samplerCutBy",
                    down: { edit { $0.cutBy = max(0, $0.cutBy - 1) } }, up: { edit { $0.cutBy = min(16, $0.cutBy + 1) } })
            smallToggle("Cut self", sm.cutSelf, x: 230, y: 200, s, id: "samplerCutSelf") { edit { $0.cutSelf.toggle() } }
        }
    }

    /// Arpeggiator: off, up, down, up and down, sticky (the ends twice), random; TIME a step, GATE its length,
    /// Range octaves, Repeat each note, Slide between notes, Chord the notes it runs over.
    private func arpPanel(_ s: CGFloat) -> some View {
        let modes = ["Off", "Up", "Down", "Up/Dn", "Sticky", "Random"]
        let icons = ["xmark", "arrow.up.right", "arrow.down.right", "arrow.up.arrow.down", "arrow.up.and.down.righttriangle.up.righttriangle.down", "shuffle"]
        return panel("Arpeggiator", s) {
            HStack(spacing: 4 * s) {
                ForEach(0..<6, id: \.self) { i in
                    let on = sm.arpMode == i
                    Button { edit { $0.arpMode = i } } label: {
                        ZStack {
                            if on { SamplerWell(skin: skin, corner: 4 * s) }
                            VStack(spacing: 2 * s) {
                                Image(systemName: icons[i]).font(.system(size: 16 * s, weight: .semibold))
                                Text(modes[i]).font(.system(size: 13 * s, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .foregroundColor(on ? skin.glow : skin.ink)
                        }
                        .frame(width: 62 * s, height: 50 * s).contentShape(Rectangle())
                    }
                    .buttonStyle(SeqPress())
                    .accessibilityLabel(modes[i]).accessibilityValue(on ? "on" : "off")
                    .accessibilityIdentifier("samplerArp\(i)")
                }
            }
            .offset(x: 160 * s, y: 6 * s)
            knob("TIME", sm.arpTime, x: 52, y: 120, d: 60, s, labelY: 165, reset: 0.45, id: "ArpTIME",
                 display: { v in SamplerSettings.step(v).0 }) { v, _ in edit { $0.arpTime = v } }
            knob("GATE", sm.arpGate, x: 142, y: 120, d: 60, s, labelY: 165, reset: 0.5, id: "ArpGATE",
                 display: { v in "\(Int(((0.05 + 0.95 * v) * 100).rounded()))%" }) { v, _ in edit { $0.arpGate = v } }
            stepper("RANGE", "\(sm.arpRange)", x: 200, y: 92, w: 112, s, id: "samplerArpRange",
                    down: { edit { $0.arpRange = max(1, $0.arpRange - 1) } }, up: { edit { $0.arpRange = min(4, $0.arpRange + 1) } })
            stepper("REPEAT", "\(sm.arpRepeat)", x: 318, y: 92, w: 112, s, id: "samplerArpRepeat",
                    down: { edit { $0.arpRepeat = max(1, $0.arpRepeat - 1) } }, up: { edit { $0.arpRepeat = min(8, $0.arpRepeat + 1) } })
            smallToggle("Slide", sm.arpSlide, x: 548, y: 120, s, id: "samplerArpSlide") { edit { $0.arpSlide.toggle() } }
            label("Chord", s, size: 20).frame(height: 46 * s).offset(x: 22 * s, y: 196 * s)
            menuChip(SamplerSettings.chords[sm.arpChord.clamped(0, SamplerSettings.chords.count - 1)].0, s, size: 20)
                .bbMenu(title: "Chord", width: 240) {
                    SamplerSettings.chords.enumerated().map { i, c in BBMenuItem.item(c.0, checked: sm.arpChord == i) { edit { $0.arpChord = i } } }
                }
                .spot(96, 196, 300, 46, s)
                .accessibilityIdentifier("samplerArpChord")
        }
    }

    /// Echo delay / fat mode: FEED (0 = off) each echo quieter, PAN / MOD X / MOD Y / PITCH move each one
    /// further, TIME apart, Echoes how many; Ping pong swaps sides, Fat mode packs them a few ms apart.
    private func echoPanel(_ s: CGFloat) -> some View {
        panel("Echo delay / fat mode", s) {
            knob("FEED", sm.echoFeed, x: 50, y: 112, d: 58, s, labelY: 156, reset: 0, id: "EchoFEED",
                 display: { v in v <= 0.001 ? "Off" : Self.percent(v) }) { v, _ in edit { $0.echoFeed = v < 0.01 ? 0 : v } }
            knob("PAN", (sm.echoPan + 1) / 2, x: 135, y: 112, d: 58, s, labelY: 156, bipolar: true, reset: 0.5, id: "EchoPAN",
                 display: Self.bipolarPercent) { v, _ in edit { $0.echoPan = Self.bipolar(v) } }
            knob("MOD X", (sm.echoX + 1) / 2, x: 220, y: 112, d: 58, s, labelY: 156, bipolar: true, reset: 0.5, id: "EchoMODX",
                 display: Self.bipolarPercent) { v, _ in edit { $0.echoX = Self.bipolar(v) } }
            knob("MOD Y", (sm.echoY + 1) / 2, x: 305, y: 112, d: 58, s, labelY: 156, bipolar: true, reset: 0.5, id: "EchoMODY",
                 display: Self.bipolarPercent) { v, _ in edit { $0.echoY = Self.bipolar(v) } }
            knob("PITCH", (sm.echoPitch + 1) / 2, x: 390, y: 112, d: 58, s, labelY: 156, bipolar: true, reset: 0.5, id: "EchoPITCH",
                 display: { v in String(format: "%+.1f st", Double(Self.bipolar(v)) * 12) }) { v, _ in edit { $0.echoPitch = Self.bipolar(v) } }
            knob("TIME", sm.echoTime, x: 475, y: 112, d: 58, s, labelY: 156, reset: 0.5, id: "EchoTIME",
                 display: { v in SamplerSettings.step(v).0 }) { v, _ in edit { $0.echoTime = v } }
            stepper("ECHOES", "\(sm.echoes)", x: 20, y: 182, w: 130, s, id: "samplerEchoes",
                    down: { edit { $0.echoes = max(1, $0.echoes - 1) } }, up: { edit { $0.echoes = min(16, $0.echoes + 1) } })
            smallToggle("Ping pong", sm.echoPingPong, x: 340, y: 210, s, id: "samplerPingPongEcho") { edit { $0.echoPingPong.toggle() } }
            smallToggle("Fat mode", sm.fatMode, x: 506, y: 210, s, id: "samplerFatMode") { edit { $0.fatMode.toggle() } }
        }
    }

    /// FL names notes with C5 = MIDI 60.
    static func noteName(_ n: Int) -> String { "\(MusicScale.noteNames[((n % 12) + 12) % 12])\(n / 12)" }

    private func rootBar(_ s: CGFloat) -> some View {
        panel(nil, s) {
            label("Root note: \(Self.noteName(sm.rootNote))", s, size: 22).frame(height: 66 * s).offset(x: 18 * s)
            Button { edit { $0.rootNote = 60 } } label: {
                ZStack { SamplerMetal(tone: skin.surface, corner: 4 * s); Text("Reset").font(.system(size: 20 * s)).foregroundColor(skin.ink) }
            }
            .buttonStyle(SeqPress()).spot(214, 12, 136, 42, s).accessibilityIdentifier("samplerRootReset")
            toggleRow("Enable main pitch", sm.mainPitch, x: 392, y: 13, w: 250, s, id: "samplerMainPitch") { edit { $0.mainPitch.toggle() } }
            toggleRow("Add to key", sm.addToKey, x: 646, y: 13, w: 200, s, id: "samplerAddToKey") { edit { $0.addToKey.toggle() } }
            label("Fine tune", s, size: 20).frame(width: 120 * s, height: 66 * s, alignment: .trailing).offset(x: 846 * s)
            fineTune(s).spot(982, 8, 330, 50, s)
        }
    }

    private func fineTune(_ s: CGFloat) -> some View {
        GeometryReader { g in
            let w = g.size.width
            let x = CGFloat((sm.fineTune + 100) / 200) * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.05)).overlay(Capsule().stroke(skin.surface.bright.opacity(0.5), lineWidth: 1)).frame(height: 10 * s)
                ForEach(0..<11, id: \.self) { i in
                    Rectangle().fill(skin.dim).frame(width: 1, height: (i == 5 ? 12 : 7) * s).offset(x: w * CGFloat(i) / 10, y: 14 * s)
                }
                ZStack {
                    Circle().fill(skin.cap.spun)
                    Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1)
                    Capsule().fill(skin.glow).frame(width: 3 * s, height: 16 * s)
                }
                .frame(width: 34 * s, height: 34 * s).offset(x: x - 17 * s)
                .shadow(color: .black.opacity(0.6), radius: 3 * s, y: 2 * s)
                if sm.fineTune != 0 {
                    Text("\(Int(sm.fineTune.rounded())) ct").font(.system(size: 13 * s, weight: .semibold)).foregroundColor(skin.ink)
                        .offset(x: min(max(0, x - 20 * s), w - 50 * s), y: -24 * s)
                }
            }
            .frame(height: g.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let c = (Float(v.location.x / max(w, 1)) * 200 - 100).clamped(-100, 100)
                edit { $0.fineTune = abs(c) < 3 ? 0 : c.rounded() }
            })
            .onTapGesture(count: 2) { edit { $0.fineTune = 0 } }
            .accessibilityIdentifier("samplerFineTune")
        }
    }

    // MARK: The keyboard: tap a key to play the track at that note; two-finger tap sets the root note

    private func keyboard(_ s: CGFloat) -> some View {
        let whites = 29                // C3 to C7 (Tyrone's render), four octaves and the top C
        let whiteNotes = Self.whiteKeys(from: keyboardStart, count: whites)
        return ZStack(alignment: .topLeading) {
            GeometryReader { g in
                let kw = g.size.width / CGFloat(whites)
                let h = 148 * s
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.75)], startPoint: .top, endPoint: .bottom)).frame(height: 26 * s)
                    ForEach(Array(whiteNotes.enumerated()), id: \.offset) { i, n in
                        if n % 12 == 0 {
                            Text(Self.noteName(n)).font(.system(size: 18 * s, weight: .medium)).foregroundColor(Color(white: 0.15))
                                .offset(x: CGFloat(i) * kw + 6 * s, y: 3 * s)
                        }
                        key(n, white: true, s).frame(width: kw - 1.5 * s, height: h - 30 * s).offset(x: CGFloat(i) * kw, y: 28 * s)
                    }
                    ForEach(Array(whiteNotes.enumerated()), id: \.offset) { i, n in
                        if [0, 2, 5, 7, 9].contains(n % 12), i < whites - 1 {
                            key(n + 1, white: false, s).frame(width: kw * 0.58, height: (h - 30 * s) * 0.6).offset(x: CGFloat(i + 1) * kw - kw * 0.29, y: 28 * s)
                        }
                    }
                }
            }
            .frame(height: 148 * s)
            .clipShape(RoundedRectangle(cornerRadius: 4 * s))
            HStack {
                Button { keyboardStart = max(0, keyboardStart - 12) } label: { Image(systemName: "chevron.left").frame(width: 40 * s, height: 30 * s) }
                Spacer()
                Button { keyboardStart = min(72, keyboardStart + 12) } label: { Image(systemName: "chevron.right").frame(width: 40 * s, height: 30 * s) }
            }
            .font(.system(size: 16 * s, weight: .semibold)).foregroundColor(skin.ink)
            .buttonStyle(SeqPress())
            .background(SamplerWell(skin: skin, corner: 4 * s))
            .frame(height: 30 * s).offset(y: 152 * s)
        }
    }

    private func key(_ n: Int, white: Bool, _ s: CGFloat) -> some View {
        let root = n == sm.rootNote
        return Rectangle()
            .fill(root ? AnyShapeStyle(LinearGradient(colors: [skin.glow.opacity(0.75), skin.glow], startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(LinearGradient(colors: white ? [Color(white: 0.98), Color(white: 0.86)] : [Color(white: 0.25), Color(white: 0.02)], startPoint: .top, endPoint: .bottom)))
            .overlay(Rectangle().stroke(Color.black.opacity(0.6), lineWidth: 0.5))
            .shadow(color: root ? skin.glow.opacity(0.7) : .clear, radius: 5 * s)
            .contentShape(Rectangle())
            .bbTwoFingerMenu(title: Self.noteName(n), width: 240, tap: { controller.auditionPitched(pad, semis: n - 60) }) {
                [BBMenuItem.item("Set as root note", icon: "music.note", checked: root) { edit { $0.rootNote = n } }]
            }
            .accessibilityIdentifier("samplerKey\(n)")
    }

    static func whiteKeys(from start: Int, count: Int) -> [Int] {
        var out: [Int] = []
        var n = start
        while out.count < count {
            if [0, 2, 4, 5, 7, 9, 11].contains(n % 12) { out.append(n) }
            n += 1
        }
        return out
    }
}

// MARK: - Drawings

/// The waveform: the sound's peaks in the mode's light (with a soft glow, over a faint grid), with
/// START OFFSET, the loop and the fade / slice markers. Drawn only when what it shows changes (the
/// peaks are kept per sound, see SamplerPeaks); the cursor moves over it in SamplerPlayhead.
struct SamplerWaveCanvas: View, Equatable {
    let sample: SampleBuffer
    let zoom: CGFloat
    let scroll: CGFloat
    let color: Color
    let startOffset: Float
    let loop: Bool
    /// The track's loop points (parts of the sound).
    var loopPoints: (Float, Float) = (0, 1)
    let region: ClosedRange<Int>?
    let cues: [Int]
    var markers: [Float] = []
    /// Regions drawn from a selection (shaded, numbered R1, R2…).
    var regions: [SamplerRegion] = []
    var selection: ClosedRange<Double>? = nil
    /// The project's tempo: a line every beat, the bar numbers along the top.
    var bpm: Double = 0

    static let selectionRed = Color(red: 1, green: 0.16, blue: 0.14)

    /// Counts the sounds whose peaks have come in (draws again then).
    @State private var peaksLoaded = 0

    static func == (a: Self, b: Self) -> Bool {
        a.sample === b.sample && a.zoom == b.zoom && a.scroll == b.scroll && a.color == b.color && a.startOffset == b.startOffset
            && a.loop == b.loop && a.loopPoints == b.loopPoints && a.region == b.region && a.cues == b.cues
            && a.markers == b.markers && a.regions == b.regions && a.selection == b.selection && a.bpm == b.bpm
    }

    var body: some View {
        let loaded = peaksLoaded
        return Canvas { ctx, size in
            let n = sample.length
            // the faint grid: 32 across, 6 down
            var grid = Path()
            for k in 1..<32 { grid.addRect(CGRect(x: (size.width * CGFloat(k) / 32).rounded(), y: 0, width: 0.5, height: size.height)) }
            for k in 1..<6 { grid.addRect(CGRect(x: 0, y: (size.height * CGFloat(k) / 6).rounded(), width: size.width, height: 0.5)) }
            ctx.fill(grid, with: .color(.white.opacity(0.05)))
            guard n > 1 else { return }
            let span = Double(n) / Double(zoom)
            let first = Double(scroll) * Double(n)
            func x(_ i: Int) -> CGFloat { CGFloat((Double(i) - first) / span) * size.width }
            let mid = size.height / 2
            // the selection: tinted red behind the wave
            if let sel = selection {
                let a = x(Int(sel.lowerBound * Double(n))), b = x(Int(sel.upperBound * Double(n)))
                ctx.fill(Path(CGRect(x: a, y: 0, width: max(1, b - a), height: size.height)), with: .color(Self.selectionRed.opacity(0.22)))
            }
            // the beat grid: a line every beat, brighter on the bar, the bar's number at the top
            if bpm > 0 {
                let beat = sample.sampleRate * 60 / bpm
                let perBeat = CGFloat(beat / span) * size.width
                if perBeat > 4 {
                    var b = Int(first / beat)
                    while Double(b) * beat < first + span {
                        let bx = x(Int(Double(b) * beat))
                        let bar = b % 4 == 0
                        ctx.fill(Path(CGRect(x: bx, y: 0, width: bar ? 1 : 0.5, height: size.height)), with: .color(.white.opacity(bar ? 0.16 : 0.07)))
                        if bar && bx > 2 {
                            ctx.draw(Text("\(b / 4 + 1)").font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.45)),
                                     at: CGPoint(x: bx + 4, y: 9), anchor: .leading)
                        }
                        b += 1
                    }
                }
            }
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(color.opacity(0.25)))
            var top = Path()
            if loaded >= 0, let peaks = SamplerPeaks.cached(sample) {
                for (c, (lo, hi)) in peaks.columns(sample, count: max(1, Int(size.width)), zoom: Double(zoom), scroll: Double(scroll)).enumerated() {
                    top.addRect(CGRect(x: CGFloat(c), y: mid - CGFloat(hi) * mid * 0.92, width: 1, height: max(1, CGFloat(hi - lo) * mid * 0.92)))
                }
            }
            // a soft glow under the crisp wave
            ctx.drawLayer { glow in
                glow.addFilter(.blur(radius: 4))
                glow.fill(top, with: .color(color.opacity(0.55)))
            }
            ctx.fill(top, with: .color(color.opacity(0.9)))
            // START OFFSET: before it is dimmed
            let so = x(Int(Double(startOffset) * Double(n - 1)))
            if startOffset > 0 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: max(0, so), height: size.height)), with: .color(.black.opacity(0.45)))
                ctx.fill(Path(CGRect(x: so - 1, y: 0, width: 2, height: size.height)), with: .color(.white.opacity(0.8)))
            }
            // the loop: a CROSSFADE's own loop, the file's region, or the loop points
            if loop {
                let last = n - 1
                var a = Int(Double(loopPoints.0) * Double(last)), b = Int(Double(loopPoints.1) * Double(last))
                if sample.loopEnd > 0 { a = sample.loopStart; b = sample.loopEnd } else { a = max(a, sample.loopStart) }
                if let region { a = region.lowerBound; b = region.upperBound }
                ctx.fill(Path(CGRect(x: x(a), y: 0, width: max(1, x(b) - x(a)), height: size.height)), with: .color(color.opacity(0.14)))
                ctx.fill(Path(CGRect(x: x(a), y: 0, width: max(1, x(b) - x(a)), height: 8)), with: .color(color.opacity(0.6)))
                for p in [a, b] { ctx.fill(Path(CGRect(x: x(p) - 1, y: 0, width: 2, height: size.height)), with: .color(color.opacity(0.7))) }
            }
            // the regions you drew
            for (k, rg) in regions.enumerated() {
                let a = x(Int(Double(rg.start) * Double(n - 1))), b = x(Int(Double(rg.end) * Double(n - 1)))
                ctx.fill(Path(CGRect(x: a, y: 0, width: max(1, b - a), height: size.height)), with: .color(color.opacity(0.1)))
                ctx.fill(Path(CGRect(x: a, y: size.height - 16, width: max(1, b - a), height: 16)), with: .color(color.opacity(0.35)))
                for p in [a, b] { ctx.fill(Path(CGRect(x: p - 0.5, y: 0, width: 1, height: size.height)), with: .color(color.opacity(0.55))) }
                ctx.draw(Text("R\(k + 1)").font(.system(size: 10, weight: .bold)).foregroundColor(.white),
                         at: CGPoint(x: a + 12, y: size.height - 8))
            }
            // a bleeding declick's fade markers
            let (fi, fo) = sample.fadeMarks
            for p in [fi, fo] where p > 0 && p < n {
                var tri = Path()
                tri.move(to: CGPoint(x: x(p) - 7, y: size.height)); tri.addLine(to: CGPoint(x: x(p) + 7, y: size.height)); tri.addLine(to: CGPoint(x: x(p), y: size.height - 12))
                ctx.fill(tri, with: .color(.white.opacity(0.8)))
            }
            // slice markers (the file's) and region markers (yours, numbered)
            let regionMarks = markers.map { Int(Double($0) * Double(n - 1)) }
            for (k, p) in (cues + regionMarks).enumerated() {
                let mine = k >= cues.count
                ctx.fill(Path(CGRect(x: x(p), y: 0, width: 1, height: size.height)), with: .color(.white.opacity(mine ? 0.7 : 0.5)))
                var flag = Path()
                flag.move(to: CGPoint(x: x(p), y: 0)); flag.addLine(to: CGPoint(x: x(p) + (mine ? 16 : 8), y: mine ? 7 : 5)); flag.addLine(to: CGPoint(x: x(p), y: mine ? 14 : 10))
                ctx.fill(flag, with: .color(.white.opacity(0.85)))
                if mine {
                    ctx.draw(Text("\(k - cues.count + 1)").font(.system(size: 9, weight: .bold)).foregroundColor(.black),
                             at: CGPoint(x: x(p) + 5, y: 7))
                }
            }
            // the selection's edges
            if let sel = selection {
                for f in [sel.lowerBound, sel.upperBound] {
                    ctx.fill(Path(CGRect(x: x(Int(f * Double(n))) - 1, y: 0, width: 2, height: size.height)), with: .color(Self.selectionRed))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
        .onAppear { load() }
        .onChange(of: ObjectIdentifier(sample)) { _ in load() }
    }

    private func load() {
        SamplerPeaks.load(sample) { _ in peaksLoaded += 1 }
    }
}

/// The window's resize corner: three ridges of the window's metal.
struct SamplerResizeGrip: View {
    let tone: MetalTone
    var body: some View {
        Canvas { ctx, size in
            for k in 1...3 {
                let d = CGFloat(k) * size.width / 4
                var p = Path()
                p.move(to: CGPoint(x: size.width - d, y: size.height - 3)); p.addLine(to: CGPoint(x: size.width - 3, y: size.height - d))
                ctx.stroke(p, with: .color(.black.opacity(0.6)), lineWidth: 2.5)
                ctx.stroke(p.offsetBy(dx: -1, dy: -1), with: .color(tone.bright), lineWidth: 1.2)
            }
        }
    }
}

/// A red selection handle: a tab at the top and bottom of the edge (the line is drawn on the waveform).
struct SelectionHandle: View {
    let scale: CGFloat
    let leading: Bool
    var body: some View {
        VStack {
            tab
            Spacer()
            tab
        }
    }
    private var tab: some View {
        RoundedRectangle(cornerRadius: 3 * scale)
            .fill(SamplerWaveCanvas.selectionRed)
            .overlay(RoundedRectangle(cornerRadius: 3 * scale).stroke(Color.white.opacity(0.7), lineWidth: 1))
            .frame(width: 16 * scale, height: 22 * scale)
            .offset(x: (leading ? -7 : 7) * scale)
            .shadow(color: SamplerWaveCanvas.selectionRed.opacity(0.8), radius: 4 * scale)
    }
}

/// A loop point's flag under the waveform, in the mode's light.
struct LoopFlag: View {
    let color: Color
    let leading: Bool
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            let x = size.width / 2
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
            p.addLine(to: CGPoint(x: leading ? size.width : 0, y: size.height * 0.62)); p.addLine(to: CGPoint(x: x, y: size.height * 0.25))
            p.closeSubpath()
            ctx.fill(p, with: .color(color))
            ctx.stroke(p, with: .color(.white.opacity(0.6)), lineWidth: 1)
        }
        .shadow(color: color, radius: 3)
    }
}

/// The envelope's shape: delay, attack (curved by its tension), hold, decay, a stretch of sustain,
/// release, with a handle at each corner.
struct EnvelopeGraph: View {
    let env: SamplerEnvelope
    let color: Color

    /// Where the stages meet across `w`: delay start, attack start, peak, hold end, decay end,
    /// sustain end, release end.
    static func xs(_ env: SamplerEnvelope, width w: CGFloat) -> [CGFloat] {
        let u = { (v: Float) in max(0.02, Double(v) * 0.5 + SamplerEnvelope.units(v, tempo: false) / 16) }
        let parts = [u(env.delay) - 0.02, u(env.attack), u(env.hold), u(env.decay), 0.35, u(env.release)]
        let total = parts.reduce(0, +)
        var t = 0.0
        var xs: [CGFloat] = []
        for p in parts { xs.append(CGFloat(t / total) * w); t += p }
        xs.append(w)
        return xs
    }
    static func y(_ v: CGFloat, height h: CGFloat) -> CGFloat { h - v * h * 0.9 - 2 }

    /// The points you can drag: attack start, peak, hold end, decay end, sustain end, release end.
    static func points(_ env: SamplerEnvelope, width w: CGFloat, height h: CGFloat) -> [CGPoint] {
        let xs = xs(env, width: w), sus = CGFloat(env.sustain)
        return [CGPoint(x: xs[1], y: y(0, height: h)), CGPoint(x: xs[2], y: y(1, height: h)), CGPoint(x: xs[3], y: y(1, height: h)),
                CGPoint(x: xs[4], y: y(sus, height: h)), CGPoint(x: xs[5], y: y(sus, height: h)), CGPoint(x: xs[6], y: y(0, height: h))]
    }

    // MARK: the graph's own points

    /// Pixels per second (or beat): the whole envelope fills 92% of the width.
    static func pixelsPerUnit(_ env: SamplerEnvelope, width w: CGFloat) -> CGFloat {
        let total = CGFloat(env.points.reduce(0) { $0 + $1.time })
        return w * 0.92 / max(total, 0.05)
    }

    /// Where each point sits.
    static func pointXY(_ env: SamplerEnvelope, width w: CGFloat, height h: CGFloat) -> [CGPoint] {
        let k = pixelsPerUnit(env, width: w)
        var t: CGFloat = 0
        return env.points.map { p in t += CGFloat(p.time); return CGPoint(x: t * k, y: y(CGFloat(p.level), height: h)) }
    }

    /// The middle of the curve into each point.
    static func pointTensionHandles(_ env: SamplerEnvelope, width w: CGFloat, height h: CGFloat) -> [CGPoint] {
        let xy = pointXY(env, width: w, height: h)
        return env.points.indices.map { i in
            let x0 = i == 0 ? 0 : xy[i - 1].x
            let v0 = CGFloat(i == 0 ? 0 : env.points[i - 1].level), v1 = CGFloat(env.points[i].level)
            return CGPoint(x: (x0 + xy[i].x) / 2, y: y(v0 + (v1 - v0) * CGFloat(pow(0.5, Double(powf(4, env.points[i].tension)))), height: h))
        }
    }

    /// Everything a finger can drag, in the order the editor numbers it.
    static func handles(_ env: SamplerEnvelope, width w: CGFloat, height h: CGFloat) -> [CGPoint] {
        env.usesPoints ? pointXY(env, width: w, height: h) + pointTensionHandles(env, width: w, height: h)
                       : points(env, width: w, height: h) + tensionHandles(env, width: w, height: h)
    }

    /// The middles of the attack, decay and release curves.
    static func tensionHandles(_ env: SamplerEnvelope, width w: CGFloat, height h: CGFloat) -> [CGPoint] {
        let xs = xs(env, width: w), sus = CGFloat(env.sustain)
        func mid(_ x0: CGFloat, _ x1: CGFloat, _ v0: CGFloat, _ v1: CGFloat, _ t: Float) -> CGPoint {
            CGPoint(x: (x0 + x1) / 2, y: y(v0 + (v1 - v0) * CGFloat(pow(0.5, Double(powf(4, t)))), height: h))
        }
        return [mid(xs[1], xs[2], 0, 1, env.attackTension), mid(xs[3], xs[4], 1, sus, env.decayTension), mid(xs[5], xs[6], sus, 0, env.releaseTension)]
    }

    var body: some View {
        if env.usesPoints { pointsBody } else { knobsBody }
    }

    /// The graph's own points: the line through them, the sustain point marked with a dashed line.
    private var pointsBody: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func y(_ v: CGFloat) -> CGFloat { Self.y(v, height: h) }
            let xy = Self.pointXY(env, width: w, height: h)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y(0)))
            var x0: CGFloat = 0, v0: CGFloat = 0
            for (i, p) in env.points.enumerated() {
                let v1 = CGFloat(p.level), k = Double(powf(4, p.tension))
                for j in 1...24 {
                    let f = Double(j) / 24
                    path.addLine(to: CGPoint(x: x0 + (xy[i].x - x0) * CGFloat(f), y: y(v0 + (v1 - v0) * CGFloat(pow(f, k)))))
                }
                x0 = xy[i].x; v0 = v1
            }
            var fill = path
            fill.addLine(to: CGPoint(x: x0, y: h)); fill.addLine(to: CGPoint(x: 0, y: h)); fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0.05)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            for i in 1..<8 { ctx.fill(Path(CGRect(x: w * CGFloat(i) / 8, y: 0, width: 0.5, height: h)), with: .color(.white.opacity(0.06))) }
            for i in 1..<4 { ctx.fill(Path(CGRect(x: 0, y: h * CGFloat(i) / 4, width: w, height: 0.5)), with: .color(.white.opacity(0.06))) }
            if xy.indices.contains(env.sustainPoint) {
                var line = Path()
                line.move(to: CGPoint(x: xy[env.sustainPoint].x, y: 0)); line.addLine(to: CGPoint(x: xy[env.sustainPoint].x, y: h))
                ctx.stroke(line, with: .color(color.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            for (i, p) in xy.enumerated() {
                let r = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
                ctx.fill(Path(ellipseIn: r), with: .color(i == env.sustainPoint ? color : Color(white: 0.1)))
                ctx.stroke(Path(ellipseIn: r), with: .color(color), lineWidth: 2.5)
            }
            for p in Self.pointTensionHandles(env, width: w, height: h) {
                var d = Path()
                d.move(to: CGPoint(x: p.x, y: p.y - 6)); d.addLine(to: CGPoint(x: p.x + 6, y: p.y))
                d.addLine(to: CGPoint(x: p.x, y: p.y + 6)); d.addLine(to: CGPoint(x: p.x - 6, y: p.y)); d.closeSubpath()
                ctx.fill(d, with: .color(color.opacity(0.85)))
            }
        }
        .shadow(color: color.opacity(0.5), radius: 4)
        .allowsHitTesting(false)
    }

    private var knobsBody: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let xs = Self.xs(env, width: w)
            let sus = CGFloat(env.sustain)
            func y(_ v: CGFloat) -> CGFloat { Self.y(v, height: h) }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y(0)))
            path.addLine(to: CGPoint(x: xs[1], y: y(0)))
            func curve(_ x0: CGFloat, _ x1: CGFloat, _ v0: CGFloat, _ v1: CGFloat, _ tension: Float) {
                let k = Double(powf(4, tension))
                for i in 1...24 {
                    let p = Double(i) / 24
                    let c = CGFloat(pow(p, k))
                    path.addLine(to: CGPoint(x: x0 + (x1 - x0) * CGFloat(p), y: y(v0 + (v1 - v0) * c)))
                }
            }
            curve(xs[1], xs[2], 0, 1, env.attackTension)
            path.addLine(to: CGPoint(x: xs[3], y: y(1)))
            curve(xs[3], xs[4], 1, sus, env.decayTension)
            path.addLine(to: CGPoint(x: xs[5], y: y(sus)))
            curve(xs[5], xs[6], sus, 0, env.releaseTension)
            var fill = path
            fill.addLine(to: CGPoint(x: w, y: h)); fill.addLine(to: CGPoint(x: 0, y: h)); fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0.05)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            // grid
            for i in 1..<8 { ctx.fill(Path(CGRect(x: w * CGFloat(i) / 8, y: 0, width: 0.5, height: h)), with: .color(.white.opacity(0.06))) }
            for i in 1..<4 { ctx.fill(Path(CGRect(x: 0, y: h * CGFloat(i) / 4, width: w, height: 0.5)), with: .color(.white.opacity(0.06))) }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            for p in [CGPoint(x: xs[1], y: y(0)), CGPoint(x: xs[2], y: y(1)), CGPoint(x: xs[3], y: y(1)), CGPoint(x: xs[4], y: y(sus)),
                      CGPoint(x: xs[5], y: y(sus)), CGPoint(x: xs[6], y: y(0))] {
                let r = CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)
                ctx.fill(Path(ellipseIn: r), with: .color(Color(white: 0.1)))
                ctx.stroke(Path(ellipseIn: r), with: .color(color), lineWidth: 2.5)
            }
            // the tension handles: drag one up or down to bend its curve
            for p in Self.tensionHandles(env, width: w, height: h) {
                var d = Path()
                d.move(to: CGPoint(x: p.x, y: p.y - 6)); d.addLine(to: CGPoint(x: p.x + 6, y: p.y))
                d.addLine(to: CGPoint(x: p.x, y: p.y + 6)); d.addLine(to: CGPoint(x: p.x - 6, y: p.y)); d.closeSubpath()
                ctx.fill(d, with: .color(color.opacity(0.85)))
            }
        }
        .shadow(color: color.opacity(0.5), radius: 4)
        .allowsHitTesting(false)
    }
}

/// The LFO's wave over three cycles, growing in after its delay and attack.
struct LFOGraph: View {
    let lfo: SamplerLFO
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, mid = h / 2
            for i in 1..<4 { ctx.fill(Path(CGRect(x: w * CGFloat(i) / 4, y: 0, width: 0.5, height: h)), with: .color(.white.opacity(0.06))) }
            ctx.fill(Path(CGRect(x: 0, y: h / 4, width: w, height: 0.5)), with: .color(.white.opacity(0.06)))
            ctx.fill(Path(CGRect(x: 0, y: h * 3 / 4, width: w, height: 0.5)), with: .color(.white.opacity(0.06)))
            var path = Path()
            let d = Double(lfo.delay) * 0.3, a = Double(lfo.attack) * 0.3
            for i in 0...240 {
                let t = Double(i) / 240
                let ramp = t < d ? 0 : (a <= 0 ? 1 : min(1, (t - d) / a))
                let p = (t * 3).truncatingRemainder(dividingBy: 1)
                let v: Double
                switch lfo.shape {
                case 1: v = 1 - 4 * abs(p - 0.5)
                case 2: v = p < 0.5 ? 1 : -1
                default: v = sin(2 * .pi * p)
                }
                let pt = CGPoint(x: w * CGFloat(t), y: mid - CGFloat(v * ramp * Double(lfo.amount)) * mid * 0.85)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
        }
        .shadow(color: color.opacity(0.6), radius: 4)
        .allowsHitTesting(false)
    }
}

/// SAMPLE's icon: a burst of waveform.
struct SampleGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let hs: [CGFloat] = [0.15, 0.35, 0.2, 0.7, 1, 0.55, 0.85, 0.3, 0.5, 0.2, 0.1]
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        for (i, v) in hs.enumerated() {
            let x = r.minX + r.width * CGFloat(i + 1) / CGFloat(hs.count + 1)
            p.addLine(to: CGPoint(x: x, y: r.midY + (i % 2 == 0 ? -1 : 1) * v * r.height / 2))
        }
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}

/// ENVELOPE's icon: a rise and a fall with its handles.
struct EnvelopeGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let a = CGPoint(x: r.minX + 2, y: r.maxY - 3), b = CGPoint(x: r.minX + r.width * 0.32, y: r.minY + 3)
        let c = CGPoint(x: r.minX + r.width * 0.62, y: r.maxY - 6), d = CGPoint(x: r.maxX - 4, y: r.maxY - 6)
        p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.addLine(to: d)
        for q in [a, b, d] { p.addEllipse(in: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)) }
        return p
    }
}

/// The LFO's shape buttons: sine, triangle, square.
struct LFOShapeGlyph: Shape {
    let shape: Int
    func path(in r: CGRect) -> Path {
        var p = Path()
        switch shape {
        case 1:
            p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        case 2:
            p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.closeSubpath()
        default:
            p.move(to: CGPoint(x: r.minX, y: r.midY))
            for i in 1...24 {
                let t = CGFloat(i) / 24
                p.addLine(to: CGPoint(x: r.minX + r.width * t, y: r.midY - sin(t * 2 * .pi) * r.height / 2))
            }
        }
        return p
    }
}

extension View {
    /// Places a view at (x, y) with size (w, h) in the sampler's design units.
    func spot(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ s: CGFloat) -> some View {
        frame(width: w * s, height: h * s).offset(x: x * s, y: y * s)
    }
}
