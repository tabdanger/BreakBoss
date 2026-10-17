// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - The sequencer's real controls, each cut out of Tyrone's picture
//
// Every button, chip and switch on the DRUM SEQUENCER is its own view (a sprite from the picture,
// `tools/sequencer_art/build_controls.py`), not a press area over a painting: it goes in while
// your finger is on it, springs back when you let go, and lights up when it's on.

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

    var body: some View {
        ZStack {
            Image(sprite).resizable()
            BrushedFinish(corner: corner * scale)
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

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height, w = geo.size.width
            let knob = h - 8 * scale
            let maxTravel = max(1, w - knob - 8 * scale)
            ZStack(alignment: .leading) {
                // the slot
                Capsule().fill(LinearGradient(colors: [Color(white: 0.05), Color(white: 0.16)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().stroke(Color(white: 0.6), lineWidth: 1))
                    .overlay(Capsule().fill(color.opacity(0.25 * Double(travel / maxTravel))).padding(2))
                // where it goes: Face 1's pads
                Image(systemName: "square.fill").font(.system(size: 13 * scale, weight: .bold))
                    .foregroundColor(Color(white: travel > maxTravel * 0.5 ? 0.95 : 0.55))
                    .frame(width: knob, height: knob).offset(x: w - knob - 4 * scale)
                Image(systemName: "chevron.right.2").font(.system(size: 9 * scale, weight: .bold)).foregroundColor(Color(white: 0.45))
                    .offset(x: knob + 6 * scale).opacity(1 - Double(travel / maxTravel))
                // the platinum knob
                ZStack {
                    Circle().fill(AngularGradient(colors: [Color(white: 0.96), Color(white: 0.62), Color(white: 0.9), Color(white: 0.58), Color(white: 0.96)], center: .center))
                    Circle().fill(RadialGradient(colors: [Color.white.opacity(0.55), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: knob * 0.6))
                    Circle().stroke(Color(white: 0.35), lineWidth: 1)
                    Image(systemName: "square.grid.3x3.fill").font(.system(size: knob * 0.42, weight: .bold)).foregroundColor(Color(white: 0.15))
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
struct PlatinumPlate: View {
    var corner: CGFloat = 0

    var body: some View {
        let w = { (v: Double) in Color(white: v) }
        ZStack {
            LinearGradient(stops: [.init(color: w(0.95), location: 0), .init(color: w(0.80), location: 0.38),
                                   .init(color: w(0.88), location: 0.62), .init(color: w(0.68), location: 1)],
                           startPoint: .top, endPoint: .bottom)
            // light caught across it, like the facets of the knob
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.1), .init(color: .white.opacity(0.4), location: 0.27),
                                   .init(color: .white.opacity(0), location: 0.44), .init(color: .black.opacity(0.06), location: 0.6),
                                   .init(color: .white.opacity(0.22), location: 0.8), .init(color: .white.opacity(0), location: 0.95)],
                           startPoint: .leading, endPoint: .trailing)
            BrushedFinish(corner: corner)
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

    var body: some View {
        Button(action: action) {
            GeometryReader { g in
                let d = min(g.size.width, g.size.height)
                ZStack {
                    // the slot it sits in
                    Circle().fill(LinearGradient(colors: [Color(white: 0.05), Color(white: 0.18)], startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().stroke(Color(white: 0.6), lineWidth: 1))
                    Circle().stroke(on ? color : Color(white: 0.25), lineWidth: 2 * scale)
                        .shadow(color: on ? color.opacity(0.8) : .clear, radius: 4 * scale)
                        .padding(2.5 * scale)
                    // the platinum knob
                    ZStack {
                        Circle().fill(AngularGradient(colors: [Color(white: 0.96), Color(white: 0.62), Color(white: 0.9), Color(white: 0.58), Color(white: 0.96)], center: .center))
                        Circle().fill(RadialGradient(colors: [Color.white.opacity(0.55), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.45))
                        Circle().stroke(Color(white: 0.35), lineWidth: 1)
                        Image(systemName: "power").font(.system(size: d * 0.3, weight: .bold))
                            .foregroundColor(on ? color : Color(white: 0.2))
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

    var body: some View {
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
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .allowsHitTesting(false)
    }
}

/// A machined knob: a spun-metal cap (concentric grain, light caught in its facets) sitting in a dark
/// well, with a groove on the cap and a white tick on the rim to read it by.
struct MetalKnob: View {
    var pointer = true

    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            let w = { (v: Double) in Color(white: v) }
            ZStack {
                Circle().fill(RadialGradient(colors: [w(0.02), w(0.18)], center: .center, startRadius: d * 0.32, endRadius: d * 0.5))
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
