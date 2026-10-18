// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The SAMPLER window (Tyrone's two renders, Oct 18)
//
// One window per track, opened from the track's menu (two-finger tap / right-click > Open sample
// editor). Page 1 SAMPLE, page 2 ENVELOPE; the tabs flip between them. Drawn at the renders' size
// (1408 × 940) and scaled to fit. Each mode wears its own metal and light: Platinum silver with
// platinum knobs and green light, Modern Black with red, Vintage cream with yellow, Texture blue
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
        switch finish {
        case "modern": glow = Color(red: 1, green: 0.2, blue: 0.16)
        case "vintage": glow = Color(red: 1, green: 0.78, blue: 0.18)
        case "texture": glow = Color(red: 0.3, green: 0.66, blue: 1)
        default: glow = DrumRollStyle.green
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
    @State private var lastTap: Date?

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
        .highPriorityGesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                if start == nil { start = value }
                let n = ((start ?? value) + Float((-g.translation.height + g.translation.width * 0.6) / 180)).clamped(0, 1)
                live = n
                change(n, false)
            }
            .onEnded { g in
                let isTap = abs(g.translation.width) < 6 && abs(g.translation.height) < 6
                if isTap, let reset, let t = lastTap, Date().timeIntervalSince(t) < 0.35 {
                    change(reset, true); lastTap = nil
                } else {
                    let n = ((start ?? value) + Float((-g.translation.height + g.translation.width * 0.6) / 180)).clamped(0, 1)
                    change(n, true)
                    lastTap = isTap ? Date() : nil
                }
                start = nil; live = nil
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

    @State private var page = 0                  // 0 SAMPLE, 1 ENVELOPE
    @State private var target: SamplerTarget = .volume
    @State private var keyboardStart = 36        // the keyboard's first key (C3)
    @State private var zoom: CGFloat = 1
    @State private var scrollPos: CGFloat = 0
    @State private var pinchFrom: CGFloat?
    @State private var dropping = false
    /// Turning a SAMPLE-page knob: the knob shows this until it's let go (the sound is computed then).
    @State private var pending: SamplerSettings?

    static let artW: CGFloat = 1408, artH: CGFloat = 940

    private var skin: SamplerSkin { SamplerSkin.of(finish) }
    private var sm: SamplerSettings { pending ?? controller.sampler(pad) }
    private var trackNumber: Int { (controller.rackOrder.firstIndex(of: pad) ?? pad) + 1 }

    private func edit(_ change: (inout SamplerSettings) -> Void) {
        var s = controller.sampler(pad); change(&s); controller.setSampler(pad, s)
    }
    /// A SAMPLE-page knob: shown while it turns, computed into the sound when it's let go.
    private func editComputed(_ final: Bool, _ change: (inout SamplerSettings) -> Void) {
        var s = sm; change(&s)
        if final { pending = nil; controller.setSampler(pad, s) } else { pending = s }
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Self.artW, geo.size.height / Self.artH)
            ZStack(alignment: .topLeading) {
                bezel(s)
                titleBar(s)
                tabStrip(s)
                if page == 0 { samplePage(s) } else { envelopePage(s) }
            }
            .frame(width: Self.artW * s, height: Self.artH * s, alignment: .topLeading)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(Self.artW / Self.artH, contentMode: .fit)
        .accessibilityIdentifier("samplerWindow")
    }

    // MARK: Frame, title, tabs

    private func bezel(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SamplerMetal(tone: skin.bezel, corner: 14 * s)
                .shadow(color: .black.opacity(0.7), radius: 18 * s, y: 8 * s)
            // the body inside the bezel
            SamplerMetal(tone: skin.surface, corner: 8 * s, sunk: true).spot(22, 6, 1364, 922, s)
            ForEach([CGPoint(x: 10, y: 470), CGPoint(x: 1398, y: 470)], id: \.x) { p in
                Circle().fill(skin.bezel.spun).overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: 9 * s, height: 9 * s).position(x: p.x * s, y: p.y * s)
            }
        }
        .frame(width: Self.artW * s, height: Self.artH * s, alignment: .topLeading)
    }

    private func titleBar(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            SamplerMetal(tone: skin.surface, corner: 6 * s).spot(26, 8, 1356, 58, s)
            (Text("Brea").foregroundColor(skin.ink) + Text("K").foregroundColor(skin.glow) + Text("ing").foregroundColor(skin.ink))
                .font(.system(size: 34 * s, weight: .bold).width(.expanded))
                .shadow(color: .black.opacity(0.4), radius: 0, y: 1)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 210 * s, height: 58 * s, alignment: .leading).offset(x: 58 * s, y: 8 * s)
            Text("SAMPLER").font(.system(size: 30 * s, weight: .medium).width(.expanded)).foregroundColor(skin.dim)
                .frame(width: 220 * s, height: 58 * s, alignment: .leading).offset(x: 272 * s, y: 8 * s)
            Text(String(format: "CH %02d", trackNumber)).font(.system(size: 27 * s, weight: .medium)).foregroundColor(skin.ink)
                .frame(width: 160 * s, height: 58 * s, alignment: .trailing).offset(x: 1030 * s, y: 8 * s)
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
            // ON: the track plays (a mute on the rack turns it off)
            Button { controller.toggleMute(pad) } label: {
                VStack(spacing: 6 * s) {
                    SamplerSwitch(on: !muted, skin: skin, lamp: Color(red: 0.4, green: 0.95, blue: 0.3)).frame(width: 34 * s, height: 34 * s)
                    label("ON", s)
                }
            }
            .buttonStyle(SeqPress()).spot(770, 84, 60, 80, s).accessibilityIdentifier("samplerOn")
            headerKnob("PAN", value: (controller.state.pads[pad].pan + 1) / 2, bipolar: true, reset: 0.5, x: 906, s,
                       display: { v in let p = Int(((v * 2 - 1) * 100).rounded()); return p == 0 ? "C" : (p < 0 ? "L\(-p)" : "R\(p)") }) { v, _ in
                var ps = controller.state.pads[pad]; let p = v * 2 - 1; ps.pan = abs(p) < 0.03 ? 0 : p; controller.setPadSettings(pad, ps)
            }
            headerKnob("VOL", value: controller.state.pads[pad].level, bipolar: false, reset: 0.8, x: 1002, s,
                       display: { v in v <= 0.001 ? "-∞" : String(format: "%.1f dB", 40 * log10(Double(v) / 0.8)) }) { v, _ in
                var ps = controller.state.pads[pad]; ps.level = v; controller.setPadSettings(pad, ps)
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

    private func pageTab<G: View>(_ i: Int, _ title: String, _ s: CGFloat, @ViewBuilder glyph: () -> G) -> some View {
        let on = page == i
        return Button { withAnimation(.easeOut(duration: 0.15)) { page = i } } label: {
            ZStack(alignment: .bottom) {
                SamplerMetal(tone: skin.surface, corner: 5 * s, sunk: on)
                if on { RoundedRectangle(cornerRadius: 5 * s).fill(skin.glow.opacity(0.12)) }
                HStack(spacing: 20 * s) {
                    glyph().frame(width: 50 * s, height: 36 * s)
                    Text(title).font(.system(size: 24 * s, weight: .medium)).foregroundColor(on ? skin.glow : skin.dim)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if on {
                    Capsule().fill(skin.glow).frame(height: 4 * s).padding(.horizontal, 6 * s)
                        .shadow(color: skin.glow, radius: 5 * s)
                }
            }
        }
        .buttonStyle(SeqPress())
        .accessibilityIdentifier(i == 0 ? "samplerSamplePage" : "samplerEnvelopePage")
    }

    private func headerKnob(_ title: String, value: Float, bipolar: Bool, reset: Float, x: CGFloat, _ s: CGFloat,
                            display: @escaping (Float) -> String, change: @escaping (Float, Bool) -> Void) -> some View {
        VStack(spacing: 4 * s) {
            SamplerKnob(value: value, skin: skin, bipolar: bipolar, reset: reset, display: display, change: change).frame(width: 66 * s, height: 66 * s)
            label(title, s)
        }
        .frame(width: 96 * s).offset(x: (x - 48) * s, y: 74 * s)
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
            waveform(s).spot(38, 698, 1334, 216, s)
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
                    var ps = controller.state.pads[pad]; ps.sampleFile = name; controller.setPadSettings(pad, ps)
                }
            }))
        }
        if controller.state.pads[pad].sampleFile != nil {
            items.append(.item("Back to the kit's sound", icon: "arrow.uturn.backward") {
                var ps = controller.state.pads[pad]; ps.sampleFile = nil; controller.setPadSettings(pad, ps)
            })
        }
        items.append(.item("Reset the sampler", icon: "arrow.counterclockwise", destructive: true) {
            var ps = controller.state.pads[pad]; ps.sampler = nil; controller.setPadSettings(pad, ps)
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
            toggleRow("Keep on disk", sm.keepOnDisk, x: 22, y: 56, s, id: "samplerKeepOnDisk") { edit { $0.keepOnDisk.toggle() } }
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
        return panel("Playback", s) {
            knob("START OFFSET", sm.startOffset, x: 113, y: 92, d: 72, s, labelY: 146, reset: 0,
                 display: { v in "\(Int((v * 100).rounded()))%" }) { v, _ in
                // with slice markers, START OFFSET jumps from marker to marker
                var o = v
                if !cues.isEmpty {
                    let points = [0] + cues.map { Float($0) / Float(length) }
                    o = points.min { abs($0 - v) < abs($1 - v) } ?? v
                }
                edit { $0.startOffset = o }
            }
            toggleRow("Use loop points", sm.useLoop, x: 314, y: 56, s, id: "samplerUseLoop") { edit { $0.useLoop.toggle() } }
            toggleRow("Ping pong loop", sm.pingPong, x: 314, y: 102, s, id: "samplerPingPong") { edit { $0.pingPong.toggle(); if $0.pingPong { $0.useLoop = true } } }
        }
    }

    private func knob(_ title: String, _ value: Float, x: CGFloat, y: CGFloat, d: CGFloat, _ s: CGFloat, labelY: CGFloat,
                      bipolar: Bool = false, reset: Float? = nil, labelSize: CGFloat = 17,
                      display: ((Float) -> String)? = nil, change: @escaping (Float, Bool) -> Void) -> some View {
        ZStack(alignment: .topLeading) {
            SamplerKnob(value: value, skin: skin, bipolar: bipolar, reset: reset, display: display, change: change)
                .frame(width: d * s, height: d * s).offset(x: (x - d / 2) * s, y: (y - d / 2) * s)
                .accessibilityLabel(title)
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

    private func effectsPanel(_ s: CGFloat) -> some View {
        panel("Precomputed effects", s) {
            Group {
            toggleRow("Remove DC offset", sm.removeDC, x: 32, y: 52, s, id: "samplerRemoveDC") { edit { $0.removeDC.toggle() } }
            toggleRow("Normalize", sm.normalize, x: 32, y: 96, s, id: "samplerNormalize") { edit { $0.normalize.toggle() } }
            toggleRow("Reverse", sm.reverse, x: 32, y: 141, s, id: "samplerReverse") { edit { $0.reverse.toggle() } }
            toggleRow("Reverse polarity", sm.reversePolarity, x: 338, y: 52, s, id: "samplerPolarity") { edit { $0.reversePolarity.toggle() } }
            toggleRow("Fade stereo", sm.fadeStereo, x: 338, y: 96, s, id: "samplerFadeStereo") { edit { $0.fadeStereo.toggle() } }
            toggleRow("Swap stereo", sm.swapStereo, x: 338, y: 141, s, id: "samplerSwapStereo") { edit { $0.swapStereo.toggle() } }
            }
            Rectangle().fill(LinearGradient(colors: [.black.opacity(0.5), skin.surface.bright.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                .frame(width: 632 * s, height: 2 * s).offset(x: 16 * s, y: 192 * s)
            let pct: (Float) -> String = { v in "\(Int((v * 100).rounded()))%" }
            Group {
            knob("SMP START", sm.start, x: 60, y: 248, d: 64, s, labelY: 300, reset: 0, labelSize: 16, display: pct) { v, f in editComputed(f) { $0.start = v } }
            knob("LENGTH", sm.length, x: 168, y: 248, d: 64, s, labelY: 300, reset: 1, labelSize: 16, display: pct) { v, f in editComputed(f) { $0.length = max(0.005, v) } }
            knob("IN", sm.fadeIn, x: 274, y: 248, d: 64, s, labelY: 300, reset: 0, labelSize: 16, display: { v in v < 0.005 ? "off" : pct(v * v) }) { v, f in editComputed(f) { $0.fadeIn = v } }
            knob("OUT", sm.fadeOut, x: 380, y: 248, d: 64, s, labelY: 300, reset: 0, labelSize: 16, display: { v in v < 0.005 ? "off" : pct(v * v) }) { v, f in editComputed(f) { $0.fadeOut = v } }
            knob("CROSSFADE", sm.crossfade, x: 488, y: 248, d: 64, s, labelY: 300, reset: 0, labelSize: 16, display: { v in v < 0.005 ? "off" : pct(v / 2) }) { v, f in editComputed(f) { $0.crossfade = v } }
            knob("TRIM", sm.trim, x: 598, y: 248, d: 64, s, labelY: 300, reset: 0, labelSize: 16,
                 display: { v in v < 0.0001 ? "silence" : String(format: "%.0f dB", -90 + 70 * Double(v)) }) { v, f in editComputed(f) { $0.trim = v } }
            }
        }
    }

    // MARK: The sample view

    private func waveform(_ s: CGFloat) -> some View {
        let sample = controller.playedSample(pad)
        let marks = sm.loadSliceMarkers ? (sample?.cues ?? []) : []
        return ZStack(alignment: .topLeading) {
            SamplerWell(skin: skin, corner: 6 * s).spot(0, 0, 1334, 182, s)
            if let sample {
                SamplerWaveCanvas(sample: sample, zoom: zoom, scroll: scrollPos, color: skin.glow, startOffset: sm.startOffset,
                                  loop: sm.useLoop, region: sm.loadRegions ? sample.region : nil, cues: marks)
                    .clipShape(RoundedRectangle(cornerRadius: 6 * s)).spot(2, 2, 1330, 178, s)
                // bit depth and channels, lower right (FL's readout)
                HStack(spacing: 8 * s) {
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
                    .foregroundColor(skin.wellInk.opacity(0.55)).padding(10 * s).allowsHitTesting(false)
            }
            if sample == nil || dropping {
                Text("DROP SAMPLE HERE").font(.system(size: 36 * s, weight: .medium)).kerning(2 * s)
                    .foregroundColor(dropping ? skin.glow : skin.wellInk.opacity(0.3))
                    .frame(width: 1334 * s, height: 182 * s).allowsHitTesting(false)
            }
            // tap: play it; pinch: zoom; tap twice: load another sample from Files
            Color.clear.contentShape(Rectangle()).frame(width: 1334 * s, height: 182 * s)
                .onTapGesture(count: 2) { importFile() }
                .onTapGesture { controller.auditionPad(pad) }
                .gesture(MagnificationGesture()
                    .onChanged { m in
                        if pinchFrom == nil { pinchFrom = zoom }
                        zoom = ((pinchFrom ?? 1) * m).clamped(1, 64)
                        scrollPos = scrollPos.clamped(0, 1 - 1 / zoom)
                    }
                    .onEnded { _ in pinchFrom = nil })
                .onDrop(of: [.plainText, .fileURL, .audio], isTargeted: $dropping) { providers in drop(providers) }
                .accessibilityIdentifier("samplerWaveform")
            scrollBar(s).spot(0, 186, 1334, 30, s)
        }
    }

    private func scrollBar(_ s: CGFloat) -> some View {
        let step = 0.25 / zoom
        let maxPos = max(0, 1 - 1 / zoom)
        return GeometryReader { g in
            let track = g.size.width - 72 * s
            let thumbW = max(40 * s, track / zoom)
            ZStack(alignment: .leading) {
                SamplerWell(skin: skin, corner: 4 * s)
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

    private var env: SamplerEnvelope { sm.envelope(target) }
    private var lfo: SamplerLFO { sm.lfo(target) }
    private func editEnv(_ change: @escaping (inout SamplerEnvelope) -> Void) { let t = target; edit { $0.setEnvelope(t, change) } }
    private func editLFO(_ change: @escaping (inout SamplerLFO) -> Void) { let t = target; edit { $0.setLFO(t, change) } }

    private func envelopePage(_ s: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            targetTabs(s).spot(36, 168, 1348, 54, s)
            envelopePanel(s).spot(36, 226, 696, 430, s)
            lfoPanel(s).spot(742, 226, 384, 430, s)
            filterPanel(s).spot(1136, 226, 238, 430, s)
            rootBar(s).spot(36, 666, 1348, 66, s)
            keyboard(s).spot(36, 736, 1348, 182, s)
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
        return panel(nil, s) {
            Button { editEnv { $0.on.toggle() } } label: {
                HStack(spacing: 14 * s) {
                    SamplerSwitch(on: e.on, skin: skin).frame(width: 30 * s, height: 30 * s)
                    Text("Envelope").font(.system(size: 22 * s, weight: .medium)).foregroundColor(skin.ink)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SeqPress()).offset(x: 14 * s, y: 12 * s).accessibilityIdentifier("samplerEnvelopeOn")
            ZStack {
                SamplerWell(skin: skin)
                EnvelopeGraph(env: e, color: skin.glow).opacity(e.on ? 1 : 0.35).padding(10 * s)
            }
            .spot(18, 52, 660, 178, s)
            Group {
            knob("DELAY", e.delay, x: 56, y: 282, d: 64, s, labelY: 327, reset: 0, display: time) { v, _ in editEnv { $0.delay = v } }
            knob("ATT", e.attack, x: 154, y: 282, d: 64, s, labelY: 327, reset: 0.12, display: time) { v, _ in editEnv { $0.attack = v } }
            knob("HOLD", e.hold, x: 254, y: 282, d: 64, s, labelY: 327, reset: 0.18, display: time) { v, _ in editEnv { $0.hold = v } }
            knob("DEC", e.decay, x: 353, y: 282, d: 64, s, labelY: 327, reset: 0.45, display: time) { v, _ in editEnv { $0.decay = v } }
            knob("SUS", e.sustain, x: 451, y: 282, d: 64, s, labelY: 327, reset: 0.5, display: { v in "\(Int((v * 100).rounded()))%" }) { v, _ in editEnv { $0.sustain = v } }
            knob("REL", e.release, x: 548, y: 282, d: 64, s, labelY: 327, reset: 0.3, display: time) { v, _ in editEnv { $0.release = v } }
            }
            if target != .volume {
                knob("AMT", (e.amount + 1) / 2, x: 640, y: 282, d: 54, s, labelY: 327, bipolar: true, reset: 0.75,
                     display: { v in "\(Int(((v * 2 - 1) * 100).rounded()))%" }) { v, _ in editEnv { $0.amount = v * 2 - 1 } }
            }
            knob("TENSION", (e.attackTension + 1) / 2, x: 154, y: 370, d: 46, s, labelY: 407, bipolar: true, reset: 0.5, labelSize: 15, display: tension) { v, _ in editEnv { $0.attackTension = v * 2 - 1 } }
            knob("TENSION", (e.decayTension + 1) / 2, x: 353, y: 370, d: 46, s, labelY: 407, bipolar: true, reset: 0.5, labelSize: 15, display: tension) { v, _ in editEnv { $0.decayTension = v * 2 - 1 } }
            knob("TENSION", (e.releaseTension + 1) / 2, x: 548, y: 370, d: 46, s, labelY: 407, bipolar: true, reset: 0.5, labelSize: 15, display: tension) { v, _ in editEnv { $0.releaseTension = v * 2 - 1 } }
            smallToggle("Tempo", e.tempo, x: 690, y: 394, s, id: "samplerEnvTempo") { editEnv { $0.tempo.toggle() } }
        }
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
        .offset(x: (x - 150) * s, y: (y - 20) * s)
    }

    private func lfoPanel(_ s: CGFloat) -> some View {
        let l = lfo
        return panel(nil, s) {
            HStack(spacing: 6 * s) {
                ForEach(0..<3, id: \.self) { i in
                    Button { editLFO { $0.shape = i } } label: {
                        ZStack {
                            if l.shape == i { SamplerWell(skin: skin, corner: 4 * s) }
                            LFOShapeGlyph(shape: i).stroke(l.shape == i ? skin.glow : skin.ink, style: StrokeStyle(lineWidth: 2.5 * s, lineJoin: .round))
                                .frame(width: 32 * s, height: 24 * s)
                        }
                        .frame(width: 62 * s, height: 46 * s).contentShape(Rectangle())
                    }
                    .buttonStyle(SeqPress())
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
            knob("DELAY", l.delay, x: 49, y: 282, d: 62, s, labelY: 327, reset: 0, display: time) { v, _ in editLFO { $0.delay = v } }
            knob("ATT", l.attack, x: 141, y: 282, d: 62, s, labelY: 327, reset: 0, display: time) { v, _ in editLFO { $0.attack = v } }
            knob("AMT", (l.amount + 1) / 2, x: 234, y: 282, d: 62, s, labelY: 327, bipolar: true, reset: 0.5,
                 display: { v in "\(Int(((v * 2 - 1) * 100).rounded()))%" }) { v, _ in editLFO { $0.amount = abs(v * 2 - 1) < 0.02 ? 0 : v * 2 - 1 } }
            knob("SPEED", l.speed, x: 327, y: 282, d: 62, s, labelY: 327, reset: 0.5,
                 display: { v in var c = l; c.speed = v; return c.speedLabel }) { v, _ in editLFO { $0.speed = v } }
            smallToggle("Tempo", l.tempo, x: 160, y: 394, s, id: "samplerLFOTempo") { editLFO { $0.tempo.toggle() } }
            smallToggle("Global", l.global, x: 330, y: 394, s, id: "samplerLFOGlobal") { editLFO { $0.global.toggle() } }
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
        let whites = 33
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

/// The waveform: the sound's peaks in the mode's light, with START OFFSET, the loop and the
/// fade / slice markers.
struct SamplerWaveCanvas: View {
    let sample: SampleBuffer
    let zoom: CGFloat
    let scroll: CGFloat
    let color: Color
    let startOffset: Float
    let loop: Bool
    let region: ClosedRange<Int>?
    let cues: [Int]

    var body: some View {
        Canvas { ctx, size in
            let n = sample.length
            guard n > 1 else { return }
            let span = Double(n) / Double(zoom)
            let first = Double(scroll) * Double(n)
            func x(_ i: Int) -> CGFloat { CGFloat((Double(i) - first) / span) * size.width }
            let mid = size.height / 2
            ctx.fill(Path(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1)), with: .color(color.opacity(0.25)))
            var top = Path()
            let cols = max(1, Int(size.width))
            let per = max(1, Int(span / Double(cols)))
            let stride = max(1, per / 64)
            for c in 0..<cols {
                let a = Int(first + span * Double(c) / Double(cols))
                guard a < n else { break }
                var lo: Float = 0, hi: Float = 0
                var i = a
                while i < min(n, a + per) { let v = (sample.left[i] + sample.right[i]) * 0.5; lo = min(lo, v); hi = max(hi, v); i += stride }
                let px = CGFloat(c)
                top.addRect(CGRect(x: px, y: mid - CGFloat(hi) * mid * 0.92, width: 1, height: max(1, CGFloat(hi - lo) * mid * 0.92)))
            }
            ctx.fill(top, with: .color(color.opacity(0.9)))
            // START OFFSET: before it is dimmed
            let so = x(Int(Double(startOffset) * Double(n - 1)))
            if startOffset > 0 {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: max(0, so), height: size.height)), with: .color(.black.opacity(0.45)))
                ctx.fill(Path(CGRect(x: so - 1, y: 0, width: 2, height: size.height)), with: .color(.white.opacity(0.8)))
            }
            // the loop: crossfade start (or the file's region) to the end
            if loop {
                let a = region?.lowerBound ?? sample.loopStart, b = region?.upperBound ?? n - 1
                ctx.fill(Path(CGRect(x: x(a), y: 0, width: max(1, x(b) - x(a)), height: 8)), with: .color(color.opacity(0.6)))
                for p in [a, b] { ctx.fill(Path(CGRect(x: x(p) - 1, y: 0, width: 2, height: size.height)), with: .color(color.opacity(0.7))) }
            }
            // a bleeding declick's fade markers
            let (fi, fo) = sample.fadeMarks
            for p in [fi, fo] where p > 0 && p < n {
                var tri = Path()
                tri.move(to: CGPoint(x: x(p) - 7, y: size.height)); tri.addLine(to: CGPoint(x: x(p) + 7, y: size.height)); tri.addLine(to: CGPoint(x: x(p), y: size.height - 12))
                ctx.fill(tri, with: .color(.white.opacity(0.8)))
            }
            // slice markers
            for p in cues {
                ctx.fill(Path(CGRect(x: x(p), y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.5)))
                var flag = Path()
                flag.move(to: CGPoint(x: x(p), y: 0)); flag.addLine(to: CGPoint(x: x(p) + 8, y: 5)); flag.addLine(to: CGPoint(x: x(p), y: 10))
                ctx.fill(flag, with: .color(.white.opacity(0.8)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The envelope's shape: delay, attack (curved by its tension), hold, decay, a stretch of sustain,
/// release, with a handle at each corner.
struct EnvelopeGraph: View {
    let env: SamplerEnvelope
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let u = { (v: Float) in max(0.02, Double(v) * 0.5 + SamplerEnvelope.units(v, tempo: false) / 16) }
            let parts = [u(env.delay) - 0.02, u(env.attack), u(env.hold), u(env.decay), 0.35, u(env.release)]
            let total = parts.reduce(0, +)
            var t = 0.0
            var xs: [CGFloat] = []
            for p in parts { xs.append(CGFloat(t / total) * w); t += p }
            xs.append(w)
            let sus = CGFloat(env.sustain)
            func y(_ v: CGFloat) -> CGFloat { h - v * h * 0.9 - 2 }
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
