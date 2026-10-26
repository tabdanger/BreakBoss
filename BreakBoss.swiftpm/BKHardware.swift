// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - The popups' hardware (Tyrone's "both popup windows" kit, Oct 26)
//
// One look for the BreaKing menu (MenuView) and the SAMPLER window's shell and drop-downs: satin
// black metal with a fine brush, a stepped bevelled lip, small corner screws, engraved silver
// printing, recessed dark wells, rectangular black keys and dark lenses that only light when the
// thing they show is on. Modern black / Platinum silver with red, Vintage cream with yellow,
// Texture blue: the light is the SAMPLER's own (SamplerSkin.glow), so both windows match.

struct BKMenuPalette {
    let top: Color
    let bottom: Color
    let inset: Color
    let edge: Color
    let text: Color
    let secondary: Color
    let accent: Color
    /// Printing on the black keys and inside the wells (every finish).
    static let wellText = Color(bkHex: 0xEEEDE7)

    /// `finish`: the face showing (KnockController.faceKey: modern, platinum, vintage, texture).
    static func of(_ finish: String) -> BKMenuPalette {
        let accent = SamplerSkin.of(finish).glow
        switch finish {
        case "platinum":
            return BKMenuPalette(top: Color(bkHex: 0xC9CDD0), bottom: Color(bkHex: 0x949A9E), inset: Color(bkHex: 0xA6ACAF),
                                 edge: Color(bkHex: 0x73797C), text: Color(bkHex: 0x171B1E), secondary: Color(bkHex: 0x262C30), accent: accent)
        case "vintage":
            return BKMenuPalette(top: Color(bkHex: 0xE1D6BB), bottom: Color(bkHex: 0xB9AA8B), inset: Color(bkHex: 0xCDC0A1),
                                 edge: Color(bkHex: 0x85775D), text: Color(bkHex: 0x242016), secondary: Color(bkHex: 0x453B29), accent: accent)
        case "texture":
            return BKMenuPalette(top: Color(bkHex: 0x263F50), bottom: Color(bkHex: 0x0E1C27), inset: Color(bkHex: 0x142A39),
                                 edge: Color(bkHex: 0x496577), text: Color(bkHex: 0xE2EDF2), secondary: Color(bkHex: 0xB0C9D6), accent: accent)
        default:
            return BKMenuPalette(top: Color(bkHex: 0x2B2D2E), bottom: Color(bkHex: 0x101112), inset: Color(bkHex: 0x17191A),
                                 edge: Color(bkHex: 0x424546), text: wellText, secondary: Color(bkHex: 0xB8BAB6), accent: accent)
        }
    }
}

extension Color {
    init(bkHex: UInt32) {
        let r = Double((bkHex >> 16) & 0xFF) / 255
        let g = Double((bkHex >> 8) & 0xFF) / 255
        let b = Double(bkHex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// A black key: raised with a lit top lip, pressed in (and down a point) while your finger is on it.
/// `selected` rims it in the mode's light.
struct BKHardwareButtonStyle: ButtonStyle {
    let accent: Color
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        BKHardwareKey(label: configuration.label, pressed: configuration.isPressed, selected: selected, accent: accent)
    }
}

private struct BKHardwareKey<Content: View>: View {
    let label: Content
    let pressed: Bool
    let selected: Bool
    let accent: Color
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let colors: [Color] = pressed ? [Color(bkHex: 0x0B0C0D), Color(bkHex: 0x202223)] : [Color(bkHex: 0x303233), Color(bkHex: 0x101112)]
        let lip: [Color] = [Color.white.opacity(pressed ? 0.05 : 0.25), Color.black.opacity(0.8)]
        return label
            .foregroundColor(BKMenuPalette.wellText)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black, lineWidth: 2)
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(LinearGradient(colors: lip, startPoint: .top, endPoint: .bottom), lineWidth: 1)
                        .padding(2)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(selected ? accent.opacity(0.48) : Color.clear, lineWidth: 1)
                        .padding(1)
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 5))
            .offset(y: pressed ? 1 : 0)
            .shadow(color: .black.opacity(0.6), radius: pressed ? 1 : 3, x: 0, y: pressed ? 1 : 3)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// A recessed lens: dark with an inset shadow when off, the mode's light when on.
struct BKMenuLED: View {
    let isOn: Bool
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(isOn ? accent : Color(bkHex: 0x171717))
            .frame(width: 6, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(Color.black.opacity(0.95), lineWidth: 1))
            .overlay(Rectangle().fill(Color.black.opacity(0.65)).frame(height: 2), alignment: .top)
            .shadow(color: isOn ? accent.opacity(0.35) : .clear, radius: 3)
            .accessibilityHidden(true)
    }
}

/// A recessed dark well (readouts, text, the lists).
struct BKMenuWell: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(bkHex: 0x08090A), Color(bkHex: 0x17191A)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black, lineWidth: 2)
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color.white.opacity(0.13), lineWidth: 1).padding(2)
        }
        .overlay(Rectangle().fill(Color.black.opacity(0.7)).frame(height: 3).padding(.horizontal, 4), alignment: .top)
        .allowsHitTesting(false)
    }
}

/// The window's plate: satin metal in the palette's tone, a fine brush, and the stepped lip.
struct BKMenuMetal: View {
    let palette: BKMenuPalette
    var corner: CGFloat = 12

    var body: some View {
        let lip: [Color] = [Color.white.opacity(0.30), Color.black.opacity(0.9)]
        return ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            BrushedFinish(corner: corner)
            RoundedRectangle(cornerRadius: corner).strokeBorder(Color.black, lineWidth: 2)
            RoundedRectangle(cornerRadius: max(1, corner - 2))
                .strokeBorder(LinearGradient(colors: lip, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                .padding(2)
            RoundedRectangle(cornerRadius: max(1, corner - 4)).strokeBorder(Color.black.opacity(0.7), lineWidth: 1).padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .allowsHitTesting(false)
    }
}

/// A small slotted screw.
struct BKMenuScrew: View {
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(bkHex: 0x5A5B5B), Color(bkHex: 0x151616)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(Color.black, lineWidth: 1))
            .overlay(Rectangle().fill(Color.black.opacity(0.9)).frame(width: size * 0.62, height: max(1, size * 0.12)).rotationEffect(.degrees(-28)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The four corner screws over a window.
struct BKCornerScrews: View {
    var size: CGFloat = 8
    var inset: CGFloat = 6

    var body: some View {
        VStack {
            HStack { BKMenuScrew(size: size); Spacer(); BKMenuScrew(size: size) }
            Spacer()
            HStack { BKMenuScrew(size: size); Spacer(); BKMenuScrew(size: size) }
        }
        .padding(inset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An ON / OFF key: its name, and a lens with ON or OFF in a well.
struct BKMenuSwitch: View {
    let title: String
    var subtitle: String? = nil
    let isOn: Bool
    let accent: Color
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundColor(BKMenuPalette.wellText.opacity(0.7))
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    BKMenuLED(isOn: isOn, accent: accent)
                    Text(isOn ? "ON" : "OFF").font(.system(.caption, design: .monospaced).weight(.bold))
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(BKMenuWell())
            }
            .padding(12).frame(minHeight: 52)
        }
        .buttonStyle(BKHardwareButtonStyle(accent: accent, selected: isOn))
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A fader in a recessed slot: drag anywhere along it (from where your finger went down, so the
/// value never jumps), double tap to reset. `value` 0…1 is the parameter's own normalized value.
struct BKMenuFader: View {
    let title: String
    let value: Float
    let text: String
    let accent: Color
    var reset: Float? = nil
    let change: (Float) -> Void
    @State private var start: Float?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased()).font(.system(.caption, design: .monospaced).weight(.bold))
                Spacer(minLength: 8)
                Text(text).font(.system(.caption, design: .monospaced).weight(.semibold)).foregroundColor(accent)
                    .padding(.horizontal, 8).frame(minWidth: 64, minHeight: 26)
                    .background(BKMenuWell())
            }
            GeometryReader { g in
                let w = max(1, g.size.width)
                let f = CGFloat(min(1, max(0, value)))
                ZStack(alignment: .leading) {
                    BKMenuWell().frame(height: 12)
                    RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.85))
                        .frame(width: max(4, (w - 8) * f), height: 4).padding(.leading, 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(colors: [Color(bkHex: 0x58595A), Color(bkHex: 0x1A1B1C)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.black, lineWidth: 1))
                        .overlay(Rectangle().fill(accent).frame(width: 2, height: 16))
                        .frame(width: 22, height: 30)
                        .shadow(color: .black.opacity(0.7), radius: 2, y: 2)
                        .offset(x: (w - 22) * f)
                }
                .frame(height: 34)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { d in
                        if start == nil { start = value }
                        let moved = Float(d.translation.width / w)
                        change(min(1, max(0, (start ?? value) + moved)))
                    }
                    .onEnded { _ in start = nil })
                .simultaneousGesture(TapGesture(count: 2).onEnded { if let reset { change(reset) } })
            }
            .frame(height: 34)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue(text)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(min(1, value + 0.02))
            case .decrement: change(max(0, value - 0.02))
            @unknown default: break
            }
        }
    }
}
