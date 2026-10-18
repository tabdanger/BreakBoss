// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - The sequencer's real controls, each cut out of Tyrone's picture
//
// Every button, chip and switch on the DRUM SEQUENCER is its own view (a sprite from the picture,
// `tools/sequencer_art/build_controls.py`), not a press area over a painting: it goes in while
// your finger is on it, springs back when you let go, and lights up when it's on.

// MARK: - The finish (Oct 17, Tyrone: headers, slider and control edges in the faceplate's metal)

private struct SeqFinishKey: EnvironmentKey { static let defaultValue = "platinum" }

extension EnvironmentValues {
    /// Face 2's finish: "platinum", "modern" (black), "vintage" (cream) or "texture" (blue), the same as Face 1.
    var seqFinish: String {
        get { self[SeqFinishKey.self] }
        set { self[SeqFinishKey.self] = newValue }
    }
}

/// The faceplate's metal in each finish, matched to Face 1's plate: its bright, light, mid and dark
/// tones (light caught in bands, as on the slider knob), the printing on it, and whether it wears
/// Face 1's pebble grain.
struct MetalTone {
    let bright: Color, light: Color, mid: Color, dark: Color
    let ink: Color
    let pebbled: Bool

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    static func of(_ finish: String) -> MetalTone {
        switch finish {
        case "modern":
            return MetalTone(bright: rgb(98, 98, 102), light: rgb(58, 58, 61), mid: rgb(40, 40, 42), dark: rgb(20, 20, 21),
                             ink: Color(white: 0.9), pebbled: false)
        case "vintage":
            return MetalTone(bright: rgb(252, 247, 232), light: rgb(238, 227, 199), mid: rgb(222, 208, 174), dark: rgb(184, 166, 128),
                             ink: Color(white: 0.13), pebbled: true)
        case "texture":
            return MetalTone(bright: rgb(118, 182, 244), light: rgb(28, 110, 196), mid: rgb(12, 86, 162), dark: rgb(6, 50, 104),
                             ink: Color(white: 0.95), pebbled: true)
        default:
            return MetalTone(bright: Color(white: 0.96), light: Color(white: 0.88), mid: Color(white: 0.80), dark: Color(white: 0.62),
                             ink: Color(white: 0.13), pebbled: false)
        }
    }

    /// The spun metal of a knob cap or the slider knob: bright facets turning round it.
    var spun: AngularGradient {
        AngularGradient(colors: [bright, dark, light, dark, bright], center: .center)
    }
}

/// Face 1's pebble grain (the `PlateGrain` tile from build_finishes.py) over a cream or blue plate.
struct PebbleGrain: View {
    var amount = 0.55

    var body: some View {
        Image("PlateGrain").resizable(resizingMode: .tile)
            .blendMode(.overlay).opacity(amount)
            .allowsHitTesting(false)
    }
}

/// Pressed look for any Button on the sequencer: shrinks a little and darkens, then springs back.
struct SeqPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .compositingGroup()
            .brightness(configuration.isPressed ? -0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Pressed look for a metal plate that sits flush in a panel: it darkens but keeps its size, so no
/// gap opens at its edges.
struct PlatePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A button from the picture. `lit` draws the on-state (a coloured ring and tint) over the sprite.
struct SeqButton<Label: View>: View {
    let sprite: String
    var lit: Color? = nil
    var corner: CGFloat = 7
    var scale: CGFloat = 1
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    init(_ sprite: String, lit: Color? = nil, corner: CGFloat = 7, scale: CGFloat = 1,
         action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.sprite = sprite; self.lit = lit; self.corner = corner; self.scale = scale; self.action = action; self.label = label
    }

    var body: some View {
        Button(action: action) {
            SeqArt(sprite: sprite, lit: lit, corner: corner, scale: scale) { label() }
        }
        .buttonStyle(SeqPress())
    }
}

extension SeqButton where Label == EmptyView {
    init(_ sprite: String, lit: Color? = nil, corner: CGFloat = 7, scale: CGFloat = 1, action: @escaping () -> Void) {
        self.init(sprite, lit: lit, corner: corner, scale: scale, action: action) { EmptyView() }
    }
}

/// The sprite with its on-state and label: what a SeqButton draws, also used for the chips that
/// open a menu (the menu trigger supplies their pressed look).
struct SeqArt<Label: View>: View {
    let sprite: String
    var lit: Color? = nil
    var corner: CGFloat = 7
    var scale: CGFloat = 1
    @ViewBuilder var label: () -> Label
    @Environment(\.seqFinish) private var finish

    /// The sprite in the finish: Face 2's buttons are cut out of each face's own render
    /// (tools/sequencer_art/face2/build_face2.py); older sprites fall back to the bare one.
    private var art: String {
        let name = "\(sprite)_\(finish)"
        return UIImage(named: name) != nil ? name : sprite
    }
    /// Sprites from the renders already carry their metal; the older ones get the brushed overlay.
    private var fromRender: Bool { SeqArtSprites.fromRenders.contains(sprite) }

    var body: some View {
        ZStack {
            Image(art).resizable()
            if !fromRender { BrushedFinish(corner: corner * scale) }
            if let lit {
                RoundedRectangle(cornerRadius: corner * scale).fill(lit.opacity(0.16))
                RoundedRectangle(cornerRadius: corner * scale).stroke(lit, lineWidth: 1.5 * scale)
                    .shadow(color: lit.opacity(0.7), radius: 4 * scale)
            }
            label()
        }
        .animation(.easeOut(duration: 0.12), value: lit != nil)
    }
}

/// The buttons and chips build_face2.py cuts out of Tyrone's Face 2 renders (Oct 17), one per finish.
enum SeqArtSprites {
    static let fromRenders: Set<String> = ["SeqBtnTool", "SeqBtnTransport", "SeqBtnHost", "SeqChipBpm", "SeqChipBars", "SeqBtnGear",
                                           "SeqBtnCloud", "SeqChipSnap", "SeqChipSwing", "SeqChipHumanize", "SeqArrowBack", "SeqArrowFwd",
                                           "SeqChipPattern", "SeqChipKit", "SeqRowBtn"]
}

/// A chip from the picture (BPM, BARS, PATTERN…) with its live text; attach `.bbMenu` for its menu.
struct SeqChip: View {
    let sprite: String
    let text: String
    var size: CGFloat = 15
    var leading: CGFloat = 10
    var trailing: CGFloat = 26
    var scale: CGFloat = 1
    var color: Color = .white

    var body: some View {
        SeqArt(sprite: sprite, scale: scale) {
            HStack {
                Text(text).font(.system(size: size * scale, weight: .medium)).foregroundColor(color)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            .padding(.leading, leading * scale).padding(.trailing, trailing * scale)
        }
    }
}

/// A bare glyph button on the metal (the bars pager's arrows): no body, just the symbol pressing in.
struct SeqGlyph: View {
    let symbol: String
    var size: CGFloat = 17
    var scale: CGFloat = 1
    var enabled = true
    var color: Color = Color(white: 0.1)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size * scale, weight: .semibold))
                .foregroundColor(color.opacity(enabled ? 1 : 0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(SeqPress())
    }
}

/// The system share sheet (a MIDI file to another app, Files, AirDrop…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Face 2 → Face 1: a platinum knob wearing the sequencer's 9 squares in a dark slot. Slide it to
/// the right (past halfway) to go back to the faceplate; let go sooner and it springs back. A tap
/// on the slot's right end (the pads square) does the same slide.
struct FaceSlider: View {
    var scale: CGFloat = 1
    var color: Color = .green
    let back: () -> Void
    @State private var travel: CGFloat = 0
    @State private var leaving = false
    @Environment(\.seqFinish) private var finish

    var body: some View {
        let tone = MetalTone.of(finish)
        GeometryReader { geo in
            let h = geo.size.height, w = geo.size.width
            let knob = h - 8 * scale
            let maxTravel = max(1, w - knob - 8 * scale)
            ZStack(alignment: .leading) {
                // the slot
                Capsule().fill(LinearGradient(colors: [Color(white: 0.05), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [tone.dark, tone.bright], startPoint: .top, endPoint: .bottom), lineWidth: 1.5 * scale))
                    .overlay(Capsule().fill(color.opacity(0.25 * Double(travel / maxTravel))).padding(2))
                // where it goes: Face 1's pads
                Image(systemName: "forward.end.fill").font(.system(size: 14 * scale, weight: .bold))
                    .foregroundColor(Color(white: travel > maxTravel * 0.5 ? 0.95 : 0.6))
                    .frame(width: knob, height: knob).offset(x: w - knob - 4 * scale)
                Image(systemName: "chevron.right").font(.system(size: 12 * scale, weight: .semibold)).foregroundColor(Color(white: 0.35))
                    .offset(x: knob + 6 * scale).opacity(1 - Double(travel / maxTravel))
                // the key: a silver square with the pads' four squares (Tyrone's Face 2 render)
                ZStack {
                    RoundedRectangle(cornerRadius: knob * 0.22).fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.78), Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: knob * 0.22).strokeBorder(LinearGradient(colors: [.white, Color(white: 0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    Image(systemName: "square.grid.2x2.fill").font(.system(size: knob * 0.46, weight: .bold)).foregroundColor(Color(white: 0.1))
                }
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.55), radius: 3 * scale, y: 2 * scale)
                .offset(x: 4 * scale + travel)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard !leaving else { return }
                    travel = min(maxTravel, max(0, g.translation.width))
                }
                .onEnded { g in
                    guard !leaving else { return }
                    // a tap on the right half also slides it across
                    let tapRight = abs(g.translation.width) < 4 && g.location.x > w / 2
                    if travel > maxTravel * 0.5 || tapRight {
                        leaving = true
                        withAnimation(.easeOut(duration: 0.15)) { travel = maxTravel }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) { back() }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { travel = 0 }
                    }
                })
        }
        .accessibilityElement()
        .accessibilityIdentifier("faceSlider")
        .accessibilityLabel("Slide right to go back to Face 1")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { back() }
    }
}

/// Platinum laid flat: the Face 1 / Face 2 slider knob's metal (bright silver catching the light in
/// bands) on a brushed plate with a bevelled edge, lit on top and shadowed underneath. The SOUNDS and
/// GENERATE headers are plates of it; inside a panel they sit square and flush against each other.
///
/// Oct 17: in the faceplate's finish (Tyrone: Vintage cream, Texture blue, Modern black, with the
/// plate's own texture), so it's the same metal as the plate around it.
struct PlatinumPlate: View {
    var corner: CGFloat = 0
    @Environment(\.seqFinish) private var finish

    var body: some View {
        let tone = MetalTone.of(finish)
        ZStack {
            LinearGradient(stops: [.init(color: tone.bright, location: 0), .init(color: tone.mid, location: 0.38),
                                   .init(color: tone.light, location: 0.62), .init(color: tone.dark, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            if tone.pebbled { PebbleGrain() }
            // light caught across it, like the facets of the knob
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.1), .init(color: .white.opacity(0.4), location: 0.27),
                                   .init(color: .white.opacity(0), location: 0.44), .init(color: .black.opacity(0.06), location: 0.6),
                                   .init(color: .white.opacity(0.22), location: 0.8), .init(color: .white.opacity(0), location: 0.95)],
                           startPoint: .leading, endPoint: .trailing)
            BrushedFinish(corner: corner)
            // depth: a lit top lip and a shadowed bottom edge, like the bevels on the plate
            VStack(spacing: 0) {
                LinearGradient(colors: [tone.bright.opacity(0.9), tone.bright.opacity(0)], startPoint: .top, endPoint: .bottom).frame(height: 3)
                Spacer(minLength: 0)
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom).frame(height: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .allowsHitTesting(false)
    }
}

/// The Face 2 power button: a platinum knob like the slider's, with the power mark. Lit (the mark
/// and a ring in green) while the sequencer and pads are on; dark when everything is off.
struct PowerButton: View {
    let on: Bool
    var scale: CGFloat = 1
    var color: Color = .green
    let action: () -> Void
    @Environment(\.seqFinish) private var finish

    var body: some View {
        let tone = MetalTone.of(finish)
        Button(action: action) {
            GeometryReader { g in
                let d = min(g.size.width, g.size.height)
                ZStack {
                    // the slot it sits in
                    Circle().fill(LinearGradient(colors: [Color(white: 0.05), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().strokeBorder(LinearGradient(colors: [tone.dark, tone.bright], startPoint: .top, endPoint: .bottom), lineWidth: 1.5 * scale))
                    Circle().stroke(on ? color : Color(white: 0.25), lineWidth: 2 * scale)
                        .shadow(color: on ? color.opacity(0.8) : .clear, radius: 4 * scale)
                        .padding(2.5 * scale)
                    // the knob, in the faceplate's metal
                    ZStack {
                        Circle().fill(tone.spun)
                        if tone.pebbled { PebbleGrain(amount: 0.35).clipShape(Circle()) }
                        Circle().fill(RadialGradient(colors: [Color.white.opacity(0.55), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.45))
                        Circle().strokeBorder(LinearGradient(colors: [tone.bright, tone.dark.opacity(0.9), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        Image(systemName: "power").font(.system(size: d * 0.3, weight: .bold))
                            .foregroundColor(on ? color : tone.ink.opacity(0.85))
                            .shadow(color: on ? color.opacity(0.9) : .clear, radius: 3 * scale)
                    }
                    .padding(6 * scale)
                    .shadow(color: .black.opacity(0.55), radius: 3 * scale, y: 2 * scale)
                }
                .frame(width: d, height: d)
                .position(x: g.size.width / 2, y: g.size.height / 2)
            }
        }
        .buttonStyle(SeqPress())
        .animation(.easeOut(duration: 0.15), value: on)
        .accessibilityIdentifier("powerButton")
        .accessibilityLabel(on ? "Power on: tap to turn the sequencer and pads off" : "Power off: tap to turn the sequencer and pads on")
    }
}

/// Brushed steel laid over a sprite: fine horizontal grain, light sweeping across it and a
/// bevelled edge (lit on top, shadowed underneath).
struct BrushedFinish: View {
    var corner: CGFloat = 7
    @Environment(\.seqFinish) private var finish

    var body: some View {
        // the lit top edge is the plate's own metal catching the light (Tyrone: edges in the plate's colour)
        let edge = finish == "platinum" ? Color.white.opacity(0.4) : MetalTone.of(finish).bright.opacity(0.75)
        let shape = RoundedRectangle(cornerRadius: corner)
        ZStack {
            Canvas { ctx, size in
                var light = Path(), dark = Path()
                var y: CGFloat = 0.5
                while y < size.height { light.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.5)); y += 1.6 }
                y = 1.3
                while y < size.height { dark.addRect(CGRect(x: 0, y: y, width: size.width, height: 0.5)); y += 2.3 }
                ctx.fill(light, with: .color(Color.white.opacity(0.05)))
                ctx.fill(dark, with: .color(Color.black.opacity(0.08)))
            }
            LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .white.opacity(0), location: 0.45),
                                   .init(color: .white.opacity(0.07), location: 0.7), .init(color: .white.opacity(0), location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [edge, edge.opacity(0), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .allowsHitTesting(false)
    }
}

/// A machined knob: a spun-metal cap (concentric grain, light caught in its facets) sitting in a dark
/// well, with a groove on the cap and a white tick on the rim to read it by.
///
/// Oct 17: the well's rim is a collar of the faceplate's metal (cream, blue, black), so the knob's edge
/// matches the plate; the cap stays silver like Face 1's knobs.
struct MetalKnob: View {
    var pointer = true
    @Environment(\.seqFinish) private var finish

    var body: some View {
        let tone = MetalTone.of(finish)
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            let w = { (v: Double) in Color(white: v) }
            ZStack {
                Circle().fill(RadialGradient(colors: [w(0.02), w(0.18)], center: .center, startRadius: d * 0.32, endRadius: d * 0.5))
                if finish != "platinum" {
                    Circle().strokeBorder(LinearGradient(colors: [tone.dark, tone.bright], startPoint: .top, endPoint: .bottom), lineWidth: max(1, d * 0.05))
                }
                ZStack {
                    Circle().fill(AngularGradient(colors: [w(0.96), w(0.6), w(0.9), w(0.52), w(0.96), w(0.58), w(0.9), w(0.55), w(0.96)], center: .center))
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        var r: CGFloat = 1.5, i = 0
                        while r < size.width / 2 {
                            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                       with: .color(i % 2 == 0 ? Color.black.opacity(0.07) : Color.white.opacity(0.06)), lineWidth: 0.5)
                            r += 1.2; i += 1
                        }
                    }
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: max(1, d * 0.03))
                    if pointer {
                        Capsule().fill(w(0.12)).frame(width: max(1.5, d * 0.06), height: d * 0.24).offset(y: -d * 0.22)
                    }
                }
                .frame(width: d * 0.8, height: d * 0.8)
                .shadow(color: .black.opacity(0.65), radius: d * 0.05, x: 0, y: d * 0.04)
                if pointer {
                    Capsule().fill(Color.white).frame(width: max(1.5, d * 0.05), height: d * 0.08).offset(y: -d * 0.455)
                }
            }
            .frame(width: d, height: d)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
    }
}
