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
