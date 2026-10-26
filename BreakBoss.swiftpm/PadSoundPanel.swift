// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - The pad sound window's hardware (Tyrone's mockup, Oct 24; restyled Oct 26)
//
// Holding a pad opens one floating window: PAD 07 with SOUND / SAMPLES / PAD tabs, the loaded sound
// with PLAY and its waveform, then the ways to put your own sound on the pad. Since Oct 26 it wears
// the same hardware as the BreaKing menu and the SAMPLER (BKHardware.swift): one palette,
// BKMenuPalette.of(faceKey), for all three windows. Modern satin black, Platinum satin silver, both
// with red lights; Vintage cream with dark brown printing and yellow lights; Texture blue with ice
// blue lights. These are the window's parts; the window itself is PadEditorView (EditorViews.swift),
// which keeps the pad editor's actions.

/// The three tabs across the top of the window.
enum PadSoundTab: String, CaseIterable {
    case sound = "SOUND", samples = "SAMPLES", pad = "PAD"
}

/// The window's plate: the palette's satin metal, the stepped lip and a screw in each corner.
struct PadSoundBody: View {
    let palette: BKMenuPalette
    var body: some View {
        ZStack {
            BKMenuMetal(palette: palette, corner: 16)
            BKCornerScrews(size: 10, inset: 8)
        }
        .environment(\.seqFinish, palette.finish)
        .allowsHitTesting(false)
    }
}

/// A key's printing with its recessed lamp under it: a tab (lit while it's open) or DONE (no lamp).
struct PadSoundKeyFace: View {
    let title: String
    let palette: BKMenuPalette
    var lamp: Bool? = nil
    var height: CGFloat = 46

    var body: some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced)).kerning(0.8)
                .foregroundColor(palette.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let lamp { BKMenuLED(isOn: lamp, accent: palette.accent, width: 22, height: 4) }
        }
        .frame(maxWidth: .infinity).frame(height: height)
    }
}

/// The small spaced caption over a section (LOADED SOUND, ADD YOUR SOUND, SAMPLE PREVIEW).
struct PadSoundCaption: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced)).kerning(0.8).foregroundColor(color)
    }
}

/// An ADD YOUR SOUND row or a sound in the Samples folder: icon, title, a line under it, and a
/// chevron, on a raised key of the window's metal. `checked` lights its lamp (the pad's sound).
struct PadSoundRow: View {
    let icon: String
    let title: String
    let detail: String
    let palette: BKMenuPalette
    var enabled = true
    var checked = false
    var id: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .regular))
                    .foregroundColor(palette.text).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold, design: .monospaced)).kerning(0.6)
                        .foregroundColor(palette.text).lineLimit(1).minimumScaleFactor(0.7)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 12, design: .monospaced)).foregroundColor(palette.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 6)
                if checked { BKMenuLED(isOn: true, accent: palette.accent, width: 8, height: 8) }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(palette.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 66)
        }
        .buttonStyle(BKPanelKeyStyle(palette: palette, corner: 7))
        .disabled(!enabled)
        .accessibilityLabel(title.capitalized)
        .accessibilityHint(detail)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .modifier(PadSoundID(id: id))
    }
}

struct PadSoundID: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}

/// The LOADED SOUND card, sunk into the window: the sound's name on a dark readout, PLAY, and its
/// waveform on dark glass with the sound's length under it. While it plays a line runs across, lit
/// behind it.
struct PadLoadedSoundCard: View {
    let name: String
    let points: [Float]
    let reverse: Bool
    let seconds: Double
    let palette: BKMenuPalette
    /// When PLAY was last pressed (the line runs across for the sound's length).
    let playedAt: Date?
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PadSoundCaption(text: "LOADED SOUND", color: palette.secondary).padding(.leading, 4)
            HStack(spacing: 10) {
                Text(name.uppercased()).font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundColor(BKMenuPalette.wellText).lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                    .background(BKMenuWell())
                    .accessibilityIdentifier("padSound.name")
                Button(action: play) {
                    Image(systemName: "play.fill").font(.system(size: 18, weight: .bold)).foregroundColor(palette.text)
                        .frame(width: 64, height: 46)
                }
                .buttonStyle(BKPanelKeyStyle(palette: palette))
                .accessibilityLabel("Play")
                .accessibilityIdentifier("padSound.play")
            }
            scope
            HStack {
                PadSoundCaption(text: "SAMPLE PREVIEW", color: palette.secondary)
                Spacer()
                Text(String(format: "%.2f s", seconds)).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.secondary)
                    .accessibilityIdentifier("padSound.length")
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(BKRecessedPanel(palette: palette, corner: 10))
        .overlay(BKCornerScrews(size: 7, inset: 4))
    }

    private var scope: some View {
        let running = playedAt.map { Date().timeIntervalSince($0) < seconds } ?? false
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
            let at = playedAt.map { context.date.timeIntervalSince($0) / max(seconds, 0.01) } ?? 1
            PadWaveformScreen(points: points, reverse: reverse, accent: palette.accent, progress: at < 1 ? at : nil)
        }
        .frame(height: 104)
    }
}

/// The waveform on dark glass with faint grid lines and a reflection across its top. `progress`
/// (0-1) draws the moving line, the waveform lit behind it and dimmer ahead of it.
struct PadWaveformScreen: View {
    let points: [Float]
    let reverse: Bool
    let accent: Color
    let progress: Double?

    var body: some View {
        Canvas { ctx, size in
            var grid = Path()
            for i in 1..<6 {
                let x = size.width * CGFloat(i) / 6
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            ctx.stroke(grid, with: .color(Color.white.opacity(0.05)), lineWidth: 1)
            guard points.count > 1 else { return }
            let peak = max(points.max() ?? 1, 0.0001)
            let n = points.count
            let split = progress.map { CGFloat($0) * size.width } ?? size.width
            var lit = Path(), ahead = Path()
            for i in 0..<n {
                let v = CGFloat(points[reverse ? n - 1 - i : i] / peak) * size.height * 0.44
                let x = CGFloat(i) / CGFloat(n - 1) * size.width
                let mid = size.height / 2
                if x <= split {
                    lit.move(to: CGPoint(x: x, y: mid - v)); lit.addLine(to: CGPoint(x: x, y: mid + v))
                } else {
                    ahead.move(to: CGPoint(x: x, y: mid - v)); ahead.addLine(to: CGPoint(x: x, y: mid + v))
                }
            }
            let w = max(1, size.width / CGFloat(n) * 0.8)
            ctx.stroke(lit, with: .color(accent), lineWidth: w)
            ctx.stroke(ahead, with: .color(accent.opacity(0.45)), lineWidth: w)
            var centre = Path()
            centre.move(to: CGPoint(x: 0, y: size.height / 2)); centre.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(centre, with: .color(accent.opacity(0.5)), lineWidth: 0.6)
            if progress != nil {
                var line = Path()
                line.move(to: CGPoint(x: split, y: 0)); line.addLine(to: CGPoint(x: split, y: size.height))
                ctx.stroke(line, with: .color(Color.white.opacity(0.9)), lineWidth: 1.2)
            }
        }
        .background(LinearGradient(colors: [Color(bkHex: 0x050607), Color(bkHex: 0x111315)], startPoint: .top, endPoint: .bottom))
        .overlay(LinearGradient(stops: [.init(color: .white.opacity(0.09), location: 0), .init(color: .white.opacity(0), location: 0.4)],
                                startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        // sunk into the card: a black rim, a faint lit inner edge, the card's shadow across its top
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.black, lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(0.13), lineWidth: 1).padding(2))
        .overlay(Rectangle().fill(Color.black.opacity(0.6)).frame(height: 3).padding(.horizontal, 4), alignment: .top)
        .accessibilityHidden(true)
    }
}

/// One PAD-tab row sunk into the window: its name, then the control.
struct PadControlRow<Control: View>: View {
    let title: String
    let palette: BKMenuPalette
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(spacing: 14) {
            Text(title.uppercased()).font(.system(size: 12, weight: .semibold, design: .monospaced)).kerning(0.6)
                .foregroundColor(palette.text).frame(width: 70, alignment: .leading)
            control()
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .background(BKRecessedPanel(palette: palette))
    }
}

/// A recessed readout: the value lit in the mode's light on dark glass.
struct PadReadout: View {
    let text: String
    let palette: BKMenuPalette
    var width: CGFloat = 78

    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(BKMenuPalette.wellText)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: width, height: 34)
            .background(BKMenuWell())
    }
}

/// A PAD-tab fader: name, a lit bar in a recessed slot with a cap in the face's metal, and its
/// readout. `value` is in the setting's own range.
struct PadSoundSlider: View {
    let title: String
    let value: Float
    let range: ClosedRange<Float>
    let text: String
    let palette: BKMenuPalette
    var reset: Float? = nil
    let set: (Float) -> Void

    var body: some View {
        let span = max(range.upperBound - range.lowerBound, 0.000_1)
        PadControlRow(title: title, palette: palette) {
            BKFaderTrack(value: (value - range.lowerBound) / span, accent: palette.accent,
                         cap: MetalTone.of(palette.finish == "modern" ? "platinum" : palette.finish),
                         reset: reset.map { ($0 - range.lowerBound) / span }) { f in
                set(range.lowerBound + f * span)
            }
            PadReadout(text: text, palette: palette)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title).accessibilityValue(text)
        .accessibilityAdjustableAction { direction in
            let stepped = direction == .increment ? value + span * 0.02 : value - span * 0.02
            set(min(range.upperBound, max(range.lowerBound, stepped)))
        }
    }
}

/// An ON / OFF switch on a key of the window's metal: a round recessed lamp and ON or OFF.
struct PadSwitchKey: View {
    let isOn: Bool
    let palette: BKMenuPalette
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                BKMenuLED(isOn: isOn, accent: palette.accent, width: 12, height: 12)
                Text(isOn ? "ON" : "OFF").font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(width: 32, alignment: .leading)
            }
            .padding(.horizontal, 14).frame(height: 40)
        }
        .buttonStyle(BKPanelKeyStyle(palette: palette))
    }
}

/// A stepped knob (REPEAT DIVISION): a machined cap with a detent dot for every step round it.
/// Drag up or right to step up, down or left to step down; a tap steps on (and wraps round).
struct PadSteppedKnob: View {
    let index: Int
    let count: Int
    let palette: BKMenuPalette
    let set: (Int) -> Void
    @State private var start: Int?

    /// The knob turns 270°, from 7:30 to 4:30.
    private func angle(_ i: Int) -> Double { -135 + 270 * Double(i) / Double(max(1, count - 1)) }

    var body: some View {
        let size: CGFloat = 50
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                Circle().fill(i == index ? palette.accent : palette.text.opacity(0.55))
                    .frame(width: 4, height: 4)
                    .offset(y: -size / 2 - 5)
                    .rotationEffect(.degrees(angle(i)))
            }
            MetalKnob()
                .frame(width: size, height: size)
                .rotationEffect(.degrees(angle(index)))
                .animation(.easeOut(duration: 0.12), value: index)
        }
        .frame(width: size + 18, height: size + 18)
        .environment(\.seqFinish, palette.finish)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { d in
                if start == nil { start = index }
                let moved = Int(((d.translation.width - d.translation.height) / 24).rounded())
                let next = min(count - 1, max(0, (start ?? index) + moved))
                if next != index { set(next) }
            }
            .onEnded { _ in start = nil })
        .simultaneousGesture(TapGesture().onEnded { set((index + 1) % max(1, count)) })
    }
}

extension View {
    /// The sheet behind the pad sound window goes clear so the window's own edge and corners show
    /// (iPadOS 16.4 and later; before that the window just fills the sheet).
    @ViewBuilder func padSoundSheetClear() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(.clear)
        } else {
            self
        }
    }
}
