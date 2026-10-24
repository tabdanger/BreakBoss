// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - The pad sound menu's look (Tyrone's mockup, Oct 24)
//
// Holding a pad opens one floating panel: PAD 07 with SOUND / SAMPLES / PAD tabs, the loaded sound
// with PLAY and its waveform, then the ways to put your own sound on the pad. Its colours follow
// the mode: Modern charcoal with red, Vintage cream with gold, Texture slate with ice blue (the
// mockup's "Classic"). Platinum wears Modern's charcoal and red. These are the panel's parts; the
// panel itself is PadEditorView (EditorViews.swift), which keeps the pad editor's actions.

/// The three tabs across the top of the panel.
enum PadSoundTab: String, CaseIterable {
    case sound = "SOUND", samples = "SAMPLES", pad = "PAD"
}

/// One palette of the pad sound menu.
struct PadSoundPalette {
    /// Footer readout: MODERN MODE, PLATINUM MODE, VINTAGE MODE, TEXTURE MODE.
    let modeName: String
    /// The finish the brushed grain and machined edge take (SeqControls' finishes).
    let finish: String
    /// The panel body, top to bottom.
    let top: Color, bottom: Color
    let ink: Color, dim: Color
    /// The lit tab and PLAY, and what's printed on them.
    let accent: Color, onAccent: Color
    /// Idle tabs, the ADD YOUR SOUND rows and DONE.
    let well: Color, wellEdge: Color
    /// The LOADED SOUND card and what's printed on it.
    let card: Color, cardEdge: Color, cardInk: Color, cardDim: Color
    /// The waveform's screen and the waveform.
    let scope: Color, wave: Color

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    /// The palette for a face key ("modern", "platinum", "vintage", "texture").
    static func of(_ face: String) -> PadSoundPalette {
        switch face {
        case "vintage":
            return PadSoundPalette(modeName: "VINTAGE MODE", finish: "vintage",
                                   top: rgb(230, 218, 187), bottom: rgb(200, 182, 140),
                                   ink: rgb(42, 36, 24), dim: rgb(104, 92, 68),
                                   accent: rgb(122, 90, 28), onAccent: rgb(243, 231, 200),
                                   well: rgb(236, 223, 192), wellEdge: rgb(203, 182, 138),
                                   card: rgb(163, 146, 116), cardEdge: rgb(107, 92, 64), cardInk: rgb(42, 36, 24), cardDim: rgb(78, 68, 48),
                                   scope: rgb(7, 8, 10), wave: rgb(243, 212, 124))
        case "texture":
            return PadSoundPalette(modeName: "TEXTURE MODE", finish: "texture",
                                   top: rgb(59, 86, 114), bottom: rgb(30, 51, 73),
                                   ink: rgb(233, 241, 248), dim: rgb(166, 184, 201),
                                   accent: rgb(143, 212, 245), onAccent: rgb(13, 42, 61),
                                   well: rgb(52, 80, 108), wellEdge: rgb(90, 119, 149),
                                   card: rgb(15, 28, 41), cardEdge: rgb(6, 14, 22), cardInk: rgb(233, 241, 248), cardDim: rgb(166, 184, 201),
                                   scope: rgb(8, 17, 26), wave: rgb(143, 212, 245))
        default:
            return PadSoundPalette(modeName: face == "platinum" ? "PLATINUM MODE" : "MODERN MODE", finish: "modern",
                                   top: rgb(43, 46, 52), bottom: rgb(28, 30, 34),
                                   ink: rgb(240, 240, 240), dim: rgb(154, 160, 168),
                                   accent: rgb(242, 86, 75), onAccent: rgb(42, 11, 8),
                                   well: rgb(46, 49, 55), wellEdge: rgb(74, 78, 86),
                                   card: rgb(18, 20, 24), cardEdge: rgb(6, 7, 9), cardInk: rgb(240, 240, 240), cardDim: rgb(154, 160, 168),
                                   scope: rgb(8, 9, 11), wave: rgb(242, 86, 75))
        }
    }
}

/// The panel's body: the palette's metal with a brushed grain, a machined edge in the face's metal
/// and a screw in each corner of the header and footer.
struct PadSoundBody: View {
    let look: PadSoundPalette
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let tone = MetalTone.of(look.finish)
        ZStack {
            shape.fill(LinearGradient(colors: [look.top, look.bottom], startPoint: .top, endPoint: .bottom))
            BrushedFinish(corner: 16).opacity(0.5)
            shape.strokeBorder(LinearGradient(stops: [.init(color: tone.bright, location: 0), .init(color: tone.light, location: 0.25),
                                                      .init(color: tone.dark, location: 0.6), .init(color: tone.light, location: 1)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 2)
            shape.inset(by: 2).strokeBorder(Color.black.opacity(0.45), lineWidth: 1)
        }
        .environment(\.seqFinish, look.finish)
        .allowsHitTesting(false)
    }
}

/// A slotted screw head in the face's metal (the panel's header and footer corners).
struct PadSoundScrew: View {
    let finish: String
    var size: CGFloat = 12
    var body: some View {
        ZStack {
            Circle().fill(MetalTone.of(finish == "modern" ? "platinum" : finish).spun)
            Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 0.8)
            Rectangle().fill(Color.black.opacity(0.6)).frame(width: size * 0.7, height: 1.4).rotationEffect(.degrees(35))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A raised key: DONE, an idle tab, or (lit) the tab that's open.
struct PadSoundKey: View {
    let title: String
    let look: PadSoundPalette
    var lit = false
    var height: CGFloat = 44
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Text(title)
            .font(.system(size: 12, weight: .bold, design: .monospaced)).kerning(0.6)
            .foregroundColor(lit ? look.onAccent : look.ink)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(shape.fill(lit ? look.accent : look.well))
            .overlay(shape.strokeBorder(lit ? Color.black.opacity(0.25) : look.wellEdge, lineWidth: 1))
            .overlay(shape.inset(by: 1).strokeBorder(LinearGradient(colors: [.white.opacity(lit ? 0.35 : 0.12), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
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

/// An ADD YOUR SOUND row: icon, title, a line under it, and a chevron. A real button that presses.
struct PadSoundRow: View {
    let icon: String
    let title: String
    let detail: String
    let look: PadSoundPalette
    var enabled = true
    var checked = false
    var id: String? = nil
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .regular))
                    .foregroundColor(look.ink).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold, design: .monospaced)).kerning(0.6)
                        .foregroundColor(look.ink).lineLimit(1).minimumScaleFactor(0.7)
                    if !detail.isEmpty {
                        Text(detail).font(.system(size: 12)).foregroundColor(look.dim).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: checked ? "checkmark" : "chevron.right")
                    .font(.system(size: checked ? 14 : 12, weight: .bold))
                    .foregroundColor(checked ? look.accent : look.dim)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 64)
            .background(shape.fill(look.well))
            .overlay(shape.strokeBorder(checked ? look.accent : look.wellEdge, lineWidth: checked ? 1.5 : 1))
            .overlay(shape.inset(by: 1).strokeBorder(LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlatePress())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(title.capitalized)
        .accessibilityHint(detail)
        .modifier(PadSoundID(id: id))
    }
}

private struct PadSoundID: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}

/// The LOADED SOUND card: the sound's name, PLAY, and its waveform on a dark screen with the
/// sound's length under it. While it plays a line runs across, lit behind it.
struct PadLoadedSoundCard: View {
    let name: String
    let points: [Float]
    let reverse: Bool
    let seconds: Double
    let look: PadSoundPalette
    /// When PLAY was last pressed (the line runs across for the sound's length).
    let playedAt: Date?
    let play: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    PadSoundCaption(text: "LOADED SOUND", color: look.cardDim)
                    Text(name.uppercased()).font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundColor(look.cardInk).lineLimit(1).minimumScaleFactor(0.6)
                        .accessibilityIdentifier("padSound.name")
                }
                Spacer(minLength: 8)
                Button(action: play) {
                    Image(systemName: "play.fill").font(.system(size: 18, weight: .bold)).foregroundColor(look.onAccent)
                        .frame(width: 48, height: 44)
                        .background(RoundedRectangle(cornerRadius: 7).fill(look.accent))
                        .overlay(RoundedRectangle(cornerRadius: 7).inset(by: 1).strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                }
                .buttonStyle(SeqPress())
                .accessibilityLabel("Play")
                .accessibilityIdentifier("padSound.play")
            }
            scope
            HStack {
                PadSoundCaption(text: "SAMPLE PREVIEW", color: look.cardDim)
                Spacer()
                Text(String(format: "%.2f s", seconds)).font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(look.cardDim)
                    .accessibilityIdentifier("padSound.length")
            }
            .padding(.trailing, 20)
        }
        .padding(14)
        .background(shape.fill(look.card))
        .overlay(shape.strokeBorder(look.cardEdge, lineWidth: 1))
        .overlay(shape.inset(by: 1).strokeBorder(LinearGradient(colors: [.black.opacity(0.35), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private var scope: some View {
        let running = playedAt.map { Date().timeIntervalSince($0) < seconds } ?? false
        return TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { context in
            let at = playedAt.map { context.date.timeIntervalSince($0) / max(seconds, 0.01) } ?? 1
            PadWaveformScreen(points: points, reverse: reverse, look: look, progress: at < 1 ? at : nil)
        }
        .frame(height: 104)
    }
}

/// The waveform on its dark screen with faint grid lines. `progress` (0-1) draws the moving line,
/// the waveform lit behind it and dimmer ahead of it.
struct PadWaveformScreen: View {
    let points: [Float]
    let reverse: Bool
    let look: PadSoundPalette
    let progress: Double?

    var body: some View {
        Canvas { ctx, size in
            var grid = Path()
            for i in 1..<6 {
                let x = size.width * CGFloat(i) / 6
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            ctx.stroke(grid, with: .color(Color.white.opacity(0.06)), lineWidth: 1)
            guard points.count > 1 else { return }
            let peak = max(points.max() ?? 1, 0.0001)
            let n = points.count
            let split = progress.map { CGFloat($0) * size.width } ?? size.width
            var lit = Path(), ahead = Path()
            for i in 0..<n {
                let v = CGFloat(points[reverse ? n - 1 - i : i] / peak) * size.height * 0.46
                let x = CGFloat(i) / CGFloat(n - 1) * size.width
                let mid = size.height / 2
                if x <= split {
                    lit.move(to: CGPoint(x: x, y: mid - v)); lit.addLine(to: CGPoint(x: x, y: mid + v))
                } else {
                    ahead.move(to: CGPoint(x: x, y: mid - v)); ahead.addLine(to: CGPoint(x: x, y: mid + v))
                }
            }
            let w = max(1, size.width / CGFloat(n) * 0.8)
            ctx.stroke(lit, with: .color(look.wave), lineWidth: w)
            ctx.stroke(ahead, with: .color(look.wave.opacity(0.45)), lineWidth: w)
            var centre = Path()
            centre.move(to: CGPoint(x: 0, y: size.height / 2)); centre.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            ctx.stroke(centre, with: .color(look.wave.opacity(0.5)), lineWidth: 0.6)
            if progress != nil {
                var line = Path()
                line.move(to: CGPoint(x: split, y: 0)); line.addLine(to: CGPoint(x: split, y: size.height))
                ctx.stroke(line, with: .color(Color.white.opacity(0.9)), lineWidth: 1.2)
            }
        }
        .background(look.scope)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.8), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// A PAD-tab control: name, a slider in the face's light and its readout, on a recessed row.
struct PadSoundSlider: View {
    let title: String
    let value: Float
    let range: ClosedRange<Float>
    let text: String
    let look: PadSoundPalette
    let set: (Float) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title.uppercased()).font(.system(size: 12, weight: .semibold, design: .monospaced)).kerning(0.6)
                .foregroundColor(look.ink).frame(width: 64, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range).tint(look.accent)
                .accessibilityLabel(title)
                .accessibilityValue(text)
            Text(text).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(look.ink)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.horizontal, 14).frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.well))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(look.wellEdge, lineWidth: 1))
    }
}

extension View {
    /// The sheet behind the pad sound menu goes clear so the panel's own edge and corners show
    /// (iPadOS 16.4 and later; before that the panel just fills the sheet).
    @ViewBuilder func padSoundSheetClear() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(.clear)
        } else {
            self
        }
    }
}
