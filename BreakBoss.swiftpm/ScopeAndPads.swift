// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The screen

/// The red trace of what's coming out, plus a line of text for whatever you just touched
/// (knob values, pad names, loop names, kit and preset changes) and the loop that's playing.
struct ScopeView: View {
    @ObservedObject var controller: KnockController
    let scale: CGFloat

    static let red = Color(red: 1, green: 0.30, blue: 0.20)

    @State private var tracer = ScopeTracer()

    var body: some View {
        // Redraw at 60 Hz straight from the audio ring (not the 30 Hz meter copy), so the trace
        // moves smoothly without spending ProMotion's 120 Hz on it.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !controller.scopeActive)) { context in
            let now = context.date
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let points = tracer.advance(meters: controller.engine.meters, now: now)
                    let mid = size.height / 2
                    let count = points.count
                    func pt(_ i: Int) -> CGPoint {
                        CGPoint(x: CGFloat(i) / CGFloat(count - 1) * size.width,
                                y: mid - CGFloat(max(-1, min(1, points[i]))) * mid * 0.85)
                    }
                    // Smooth curve through the midpoints, so there are no sharp corners.
                    var path = Path()
                    path.move(to: pt(0))
                    for i in 1..<count - 1 {
                        let p = pt(i), q = pt(i + 1)
                        path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
                    }
                    path.addLine(to: pt(count - 1))
                    // Glow from two soft wide strokes; a blur filter every frame costs far more.
                    let round = StrokeStyle(lineWidth: 7 * scale, lineCap: .round, lineJoin: .round)
                    ctx.stroke(path, with: .color(ScopeView.red.opacity(0.14)), style: round)
                    ctx.stroke(path, with: .color(ScopeView.red.opacity(0.32)),
                               style: StrokeStyle(lineWidth: 3.5 * scale, lineCap: .round, lineJoin: .round))
                    ctx.stroke(path, with: .color(Color(red: 1, green: 0.55, blue: 0.42)),
                               style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round))
                }
                VStack(alignment: .leading, spacing: 2 * scale) {
                    if let r = controller.readout, now.timeIntervalSince(r.time) < 1.8 {
                        Text(r.title).font(.system(size: 13 * scale, weight: .medium, design: .monospaced))
                            .foregroundColor(ScopeView.red.opacity(0.85))
                        Text(r.value).font(.system(size: 22 * scale, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1).minimumScaleFactor(0.5)
                    } else if let notice = controller.notice {
                        Text(notice).font(.system(size: 13 * scale, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(3).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    statusLine
                }
                .padding(10 * scale)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: controller.notice) { value in
            guard value != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { controller.notice = nil }
        }
    }

    private var statusLine: some View {
        let e = controller.meters
        let playing = e.status[0] > 0.5
        let loop = Int(e.status[1])
        let queued = Int(e.status[2])
        let beat = e.status[3]
        var text = ""
        if playing && loop >= 0 && loop < controller.loops.count {
            let bars = max(1, controller.loops[loop].bars)
            let bar = Int((beat / 4).rounded(.down)) % bars + 1
            let b = Int(beat.rounded(.down)) % 4 + 1
            text = "\(loop + 1) \(controller.loops[loop].name)   \(bar).\(b)"
            if queued >= 0 { text += "   NEXT \(queued + 1)" } else if queued == -1 { text += "   STOPPING" }
        } else if controller.loadingKit {
            text = "LOADING KIT"
        }
        return Text(text)
            .font(.system(size: 12 * scale, design: .monospaced))
            .foregroundColor(ScopeView.red.opacity(0.75))
    }
}

/// Keeps the trace steady and fluid: each frame it lines the wave up on a rising zero
/// crossing (so it doesn't jump sideways), then eases every point toward the new shape.
final class ScopeTracer {
    static let pointCount = 160
    /// About 45 ms of audio across the screen (the ring holds roughly 6,000 values a second).
    static let window = 272
    private var ring = [Float](repeating: 0, count: MasterBus.scopeSize)
    private var shown = [Float](repeating: 0, count: ScopeTracer.pointCount)
    private var target = [Float](repeating: 0, count: ScopeTracer.pointCount)
    private var last: Date?

    func advance(meters: SharedMeters, now: Date) -> [Float] {
        let n = MasterBus.scopeSize
        let end = meters.copyScope(into: &ring)
        let dt = min(0.1, max(0.001, now.timeIntervalSince(last ?? now.addingTimeInterval(-1.0 / 60))))
        last = now

        // Look back up to one window for a rising crossing to start from.
        let latestStart = end - Self.window
        var start = latestStart
        for back in 0..<Self.window {
            let i = latestStart - back
            let a = ring[(i - 1 + n * 2) & (n - 1)], b = ring[(i + n * 2) & (n - 1)]
            if a < 0 && b >= 0 && b - a > 0.002 { start = i; break }
        }
        let step = Float(Self.window) / Float(Self.pointCount)
        for p in 0..<Self.pointCount {
            // Average the values each point covers, which also takes out fizz.
            let from = Float(p) * step, to = from + step
            var sum: Float = 0
            var c: Float = 0
            var k = Int(from)
            while Float(k) < to {
                sum += ring[(start + k + n * 2) & (n - 1)]
                c += 1
                k += 1
            }
            target[p] = c > 0 ? sum / c : 0
        }
        // Ease toward the new frame (about 30 ms), the same at 60 or 120 Hz.
        let ease = Float(1 - exp(-dt / 0.03))
        for p in 0..<Self.pointCount { shown[p] += (target[p] - shown[p]) * ease }
        return shown
    }
}

// MARK: - Pads

/// One pad. Touch plays it straight away (higher on the pad = softer, lower = harder).
/// Hold it for a second to open its editor. Drop an audio file on it to load your own sound;
/// in LOOP mode, drop a MIDI file to load your own groove.
struct PadView: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    let rect: [Double]
    let scale: CGFloat
    var holdToPlay = false
    let openEditor: (Bool) -> Void

    @State private var pressed = false
    @State private var dropping = false
    @State private var memory = FlashMemory()
    @State private var hold: DispatchWorkItem?

    final class FlashMemory {
        var count: UInt32 = 0
        var time = Date.distantPast
    }

    var body: some View {
        let r = FaceplateLayout.rect(rect)
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let hits = controller.meters.padHits[pad]
            let now = context.date
            let flash = flashAmount(hits: hits, now: now)
            let loopMode = controller.playMode == .loop
            let current = Int(controller.meters.status[1]) == pad && controller.meters.status[0] > 0.5
            let queued = Int(controller.meters.status[2]) == pad
            let blink = queued && Int(now.timeIntervalSinceReferenceDate * 4) % 2 == 0
            let light = PadView.lightColor(controller.mode)
            let lit = loopMode && current
            ZStack {
                Rectangle().fill(Color.black.opacity(pressed ? 0.12 : 0))
                // Each mode lights its pads in its own colour: hits flash, the playing loop's pad glows.
                Rectangle().fill(light.opacity(max(Double(flash) * 0.5, lit ? 0.2 : 0)))
                if lit || blink || flash > 0.01 {
                    Rectangle()
                        .strokeBorder(light.opacity(lit ? 0.9 : blink ? 0.6 : Double(flash) * 0.8), lineWidth: 3 * scale)
                        .shadow(color: light.opacity(0.7), radius: 6 * scale)
                }
                if dropping {
                    Rectangle().strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3 * scale, dash: [8 * scale, 5 * scale]))
                }
            }
        }
        .frame(width: r.width * scale, height: r.height * scale)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in
                    guard !pressed else { return }
                    pressed = true
                    let y = Float(g.startLocation.y / max(1, r.height * scale))
                    let velocity = 0.55 + 0.45 * y.clamped(0, 1)
                    if holdToPlay { controller.gateDown(pad, velocity: velocity) }
                    else { controller.padDown(pad, velocity: velocity) }
                    let work = DispatchWorkItem {
                        if pressed {
                            if holdToPlay { controller.gateUp(pad) }
                            openEditor(controller.playMode == .loop)
                        }
                    }
                    hold = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
                }
                .onEnded { _ in
                    pressed = false
                    if holdToPlay { controller.gateUp(pad) }
                    hold?.cancel()
                    hold = nil
                }
        )
        .onDrop(of: [UTType.fileURL, UTType.audio, UTType.midi], isTargeted: $dropping) { providers in
            handleDrop(providers)
        }
        .position(x: r.midX * scale, y: r.midY * scale)
        .accessibilityLabel("Pad \(pad + 1)")
        .onDisappear {
            hold?.cancel()
            if pressed && holdToPlay { controller.gateUp(pad) }
            pressed = false
        }
    }

    /// Modern red, Vintage light yellow, Texture blue.
    static func lightColor(_ mode: SoundMode) -> Color {
        switch mode {
        case .modern: return Color(red: 1, green: 0.20, blue: 0.14)
        case .vintage: return Color(red: 1, green: 0.93, blue: 0.62)
        case .texture: return Color(red: 0.25, green: 0.62, blue: 1)
        }
    }

    private func flashAmount(hits: UInt32, now: Date) -> Float {
        if hits != memory.count {
            memory.count = hits
            memory.time = now
        }
        let dt = Float(now.timeIntervalSince(memory.time))
        return max(0, 1 - dt / 0.22)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let pad = self.pad
        let controller = self.controller
        func use(_ url: URL) {
            let ext = url.pathExtension.lowercased()
            DispatchQueue.main.async {
                if ext == "mid" || ext == "midi" {
                    controller.importMIDI(url, toLoop: pad)
                } else {
                    controller.importSample(url, toPad: pad)
                }
            }
        }
        // Files and the Files app hand over a file URL.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in if let url { use(url) } }
            return true
        }
        // Other apps hand over the audio itself: copy it before the temporary file goes away.
        for type in [UTType.midi, UTType.audio] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { return }
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try? FileManager.default.removeItem(at: copy)
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil { use(copy) }
            }
            return true
        }
        return false
    }
}
