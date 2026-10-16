// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

/// Static brushed aluminium. No texture decoding or animation runs on the audio thread.
struct RackMetal: View {
    var dark = false
    var body: some View {
        LinearGradient(colors: dark
                       ? [Color(white: 0.56), Color(white: 0.72), Color(white: 0.49)]
                       : [Color(white: 0.91), Color(white: 0.71), Color(white: 0.88), Color(white: 0.66)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay {
            Canvas { context, size in
                var lines = Path()
                var y: CGFloat = 0
                while y < size.height {
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: size.width, y: y))
                    y += 2
                }
                context.stroke(lines, with: .color(.black.opacity(0.035)), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
        }
        .accessibilityHidden(true)
    }
}

struct RackChromeKnob: View {
    let title: String
    let value: Float
    let change: (Float) -> Void
    @State private var start: Float?
    var body: some View {
        ZStack {
            Circle().fill(Color.black).padding(-2)
            Circle().fill(AngularGradient(colors: [.white, Color(white: 0.42), .white,
                                                  Color(white: 0.55), .white], center: .center))
            Circle().stroke(.white.opacity(0.65), lineWidth: 0.7)
            Capsule().fill(Color(white: 0.1)).frame(width: 2, height: 7).offset(y: -7)
                .rotationEffect(.degrees(KnobControl.angle(value)))
        }
        .frame(width: 23, height: 23)
        .frame(width: 38, height: 44)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 1).onChanged { gesture in
            if start == nil { start = value }
            let delta = Float((-gesture.translation.height + gesture.translation.width * 0.5) / 160)
            change(((start ?? value) + delta).clamped(0, 1))
        }.onEnded { _ in start = nil })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            change((value + (direction == .increment ? 0.05 : -0.05)).clamped(0, 1))
        }
    }
}

/// This local spring only changes a newly inserted channel's header. Grid and transport
/// updates never attach an implicit animation to the rack.
struct RackBubbleHeader<Content: View>: View {
    let animateInsertion: Bool
    let selected: Bool
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = true
    init(animateInsertion: Bool, selected: Bool, @ViewBuilder content: () -> Content) {
        self.animateInsertion = animateInsertion
        self.selected = selected
        self.content = content()
    }
    var body: some View {
        GeometryReader { geometry in
            let width = expanded ? geometry.size.width : min(42, geometry.size.width)
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Color(white: 0.06), Color(white: 0.14), Color(white: 0.055)], startPoint: .top, endPoint: .bottom))
                    .frame(width: width, height: 42)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 2)
                content
                    .padding(.leading, 12).padding(.trailing, 5)
                    .frame(width: geometry.size.width, height: 42)
                    .opacity(expanded ? 1 : 0)
                    .mask(alignment: .leading) { Capsule().frame(width: width, height: 42) }
                Capsule().stroke(selected ? DrumRollStyle.green : .white.opacity(0.16), lineWidth: selected ? 1.5 : 0.8)
                    .frame(width: width, height: 42)
            }
            .frame(width: geometry.size.width, height: 42, alignment: .leading)
        }
        .frame(height: 42)
        .onAppear { if animateInsertion { bloom() } }
        .onChange(of: animateInsertion) { if $0 { bloom() } }
    }
    private func bloom() {
        guard !reduceMotion else { expanded = true; return }
        expanded = false
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.69)) { expanded = true }
        }
    }
}
