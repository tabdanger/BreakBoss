// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The screen

/// The trace of what's coming out, plus a line of text for whatever you just touched
/// (knob values, pad names, loop names, kit and preset changes) and the loop that's playing.
/// The trace follows the sound's frequencies like a real scope: bass swings slow and wide with a
/// deep, wide glow; hats and cymbals fill a dense band of fizz and burn brighter and thinner.
struct ScopeView: View {
    @ObservedObject var controller: KnockController
    let scale: CGFloat

    static let red = Color(red: 1, green: 0.30, blue: 0.20)
    static let probing = ProcessInfo.processInfo.environment["BREAKBOSS_UI_PROBE"] != nil

    @State private var tracer = ScopeTracer()

    var body: some View {
        // Redraw every display frame straight from the audio ring, which the engine fills every
        // audio block, so the trace moves as smoothly as the screen can show it.
        let light = FaceLight.of(controller.faceKey)
        TimelineView(.animation(paused: !controller.scopeActive)) { context in
            let now = context.date
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let frame = tracer.advance(meters: controller.engine.meters, now: now)
                    let mid = size.height / 2
                    let count = frame.line.count
                    func y(_ v: Float) -> CGFloat { mid - CGFloat(max(-1, min(1, v))) * mid * 0.85 }
                    func x(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(count - 1) * size.width }
                    // Smooth curve through the midpoints, so there are no sharp corners.
                    func curve(_ values: [Float], into path: inout Path, from first: Bool) {
                        let p0 = CGPoint(x: x(0), y: y(values[0]))
                        if first { path.move(to: p0) } else { path.addLine(to: p0) }
                        for i in 1..<count - 1 {
                            let p = CGPoint(x: x(i), y: y(values[i]))
                            let q = CGPoint(x: x(i + 1), y: y(values[i + 1]))
                            path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
                        }
                        path.addLine(to: CGPoint(x: x(count - 1), y: y(values[count - 1])))
                    }
                    let top = Double(frame.top), bass = Double(frame.bass)
                    // The fizz band: everything the points' highs and lows reach, glowing faintly,
                    // brighter the more top end there is (a hat fills it, an 808 leaves only the line).
                    if frame.spread > 0.004 {
                        var band = Path()
                        curve(frame.high, into: &band, from: true)
                        var low = Path()
                        curve(frame.low, into: &low, from: true)
                        // back along the lows, right to left
                        for i in stride(from: count - 1, through: 0, by: -1) {
                            band.addLine(to: CGPoint(x: x(i), y: y(frame.low[i])))
                        }
                        band.closeSubpath()
                        ctx.fill(band, with: .color(light.blend(0.35 + 0.5 * top).opacity(0.10 + 0.22 * top)))
                        ctx.stroke(low, with: .color(light.glow.opacity(0.12 + 0.2 * top)), lineWidth: 0.8 * scale)
                    }
                    var path = Path()
                    curve(frame.line, into: &path, from: true)
                    // Glow from two soft wide strokes; a blur filter every frame costs far more.
                    // Bass widens and deepens the glow; top end tightens it and burns the core brighter.
                    let wide = 7 * scale * CGFloat(1 + 0.9 * bass - 0.25 * top)
                    let round = StrokeStyle(lineWidth: wide, lineCap: .round, lineJoin: .round)
                    // In the face's own light, like the trace in its picture.
                    ctx.stroke(path, with: .color(light.glow.opacity(0.14 + 0.08 * bass)), style: round)
                    ctx.stroke(path, with: .color(light.glow.opacity(0.32)),
                               style: StrokeStyle(lineWidth: 3.5 * scale * CGFloat(1 + 0.4 * bass), lineCap: .round, lineJoin: .round))
                    ctx.stroke(path, with: .color(light.blend(0.6 + 0.4 * top - 0.25 * bass)),
                               style: StrokeStyle(lineWidth: 1.6 * scale * CGFloat(1 + 0.3 * bass - 0.2 * top), lineCap: .round, lineJoin: .round))
                }
                VStack(alignment: .leading, spacing: 2 * scale) {
                    if let r = controller.readout, now.timeIntervalSince(r.time) < 1.8 {
                        Text(r.title).font(.system(size: 13 * scale, weight: .medium, design: .monospaced))
                            .foregroundColor(light.glow.opacity(0.85))
                        Text(r.value).font(.system(size: 22 * scale, weight: .regular, design: .monospaced))
                            .foregroundColor(.white.opacity(0.92))
                            .lineLimit(1).minimumScaleFactor(0.5)
                    } else if let notice = controller.notice {
                        Text(notice).font(.system(size: 13 * scale, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(3).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    statusLine(light.glow)
                }
                .padding(10 * scale)
            }
        }
        .allowsHitTesting(false)
        .modifier(ScopeProbe(tracer: tracer, active: controller.scopeActive))
        .onChange(of: controller.notice) { value in
            guard value != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { controller.notice = nil }
        }
    }

    private func statusLine(_ color: Color) -> some View {
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
            .foregroundColor(color.opacity(0.75))
    }
}

/// UI tests only (BREAKBOSS_UI_PROBE): the scope's loudness and its bass / top share, read about
/// once a second by XCUITest, so a test can tell a kick from a hat on the screen.
private struct ScopeProbe: ViewModifier {
    let tracer: ScopeTracer
    let active: Bool

    func body(content: Content) -> some View {
        if ScopeView.probing {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                content
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("scope")
                    .accessibilityValue(tracer.probeText)
            }
        } else {
            content
        }
    }
}

/// Keeps the trace steady and fluid: each frame it lines the wave up on a rising zero
/// crossing (so it doesn't jump sideways), then eases every point toward the new shape. Also
/// measures how much of the sound is bass and how much is top end, for the trace's colour and glow.
final class ScopeTracer {
    static let pointCount = 240
    /// About 45 ms of audio across the screen (the ring holds roughly 6,000 points a second).
    static let window = 272

    struct Frame {
        var line: [Float]
        var low: [Float]
        var high: [Float]
        /// 0...1: how much of what's on screen is bass (under 150 Hz) and top end (over 2.5 kHz).
        var bass: Float
        var top: Float
        /// The widest the fizz band gets, after the screen's gain.
        var spread: Float
    }

    private var rings = ScopeRings()
    private var line = [Float](repeating: 0, count: ScopeTracer.pointCount)
    private var low = [Float](repeating: 0, count: ScopeTracer.pointCount)
    private var high = [Float](repeating: 0, count: ScopeTracer.pointCount)
    private var targetLine = [Float](repeating: 0, count: ScopeTracer.pointCount)
    private var targetLow = [Float](repeating: 0, count: ScopeTracer.pointCount)
    private var targetHigh = [Float](repeating: 0, count: ScopeTracer.pointCount)
    private var bass: Float = 0
    private var top: Float = 0
    /// The screen's gain follows the loudest recent peak, so a soft hat fills the screen as
    /// clearly as a loud kick (up to 4x), and a sound pushed past full scale (OUTPUT up) still fits.
    private var peak: Float = 0
    private var last: Date?

    /// For the UI tests: the recent loudness (peak held), bass share and top share.
    private(set) var probeLevel: Float = 0
    var probeText: String { String(format: "level %.3f bass %.2f top %.2f", probeLevel, bass, top) }

    func advance(meters: SharedMeters, now: Date) -> Frame {
        let n = MasterBus.scopeSize
        let mask = n - 1
        meters.copyScope(into: &rings)
        let end = rings.write
        let dt = Float(min(0.1, max(0.001, now.timeIntervalSince(last ?? now.addingTimeInterval(-1.0 / 60)))))
        last = now

        // Look back up to one window for a rising crossing to start from.
        let latestStart = end - Self.window
        var start = latestStart
        for back in 0..<Self.window {
            let i = latestStart - back
            let a = rings.line[(i - 1 + n * 2) & mask], b = rings.line[(i + n * 2) & mask]
            if a < 0 && b >= 0 && b - a > 0.002 { start = i; break }
        }

        // How loud, and how much bass and top, across what's on screen.
        var loud: Float = 0, bassSum: Float = 0, topSum: Float = 0
        for k in 0..<Self.window {
            let i = (start + k + n * 2) & mask
            loud = max(loud, abs(rings.low[i]), abs(rings.high[i]))
            bassSum += rings.bass[i]
            topSum += rings.top[i]
        }
        // held for the tests, which read it only about once a second
        probeLevel = max(loud, probeLevel - dt * 0.4)
        // The gain's peak jumps up at once and lets go over about half a second.
        peak = loud > peak ? loud : peak + (loud - peak) * (1 - exp(-dt / 0.5))
        let gain = min(4, max(0.2, 0.8 / max(peak, 0.0001)))

        let step = Float(Self.window) / Float(Self.pointCount)
        for p in 0..<Self.pointCount {
            // Average the values each point covers for the line; the band keeps their extremes.
            let from = Float(p) * step, to = from + step
            var sum: Float = 0, c: Float = 0
            var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
            var k = Int(from)
            repeat {
                let i = (start + k + n * 2) & mask
                sum += rings.line[i]
                lo = min(lo, rings.low[i]); hi = max(hi, rings.high[i])
                c += 1
                k += 1
            } while Float(k) < to
            targetLine[p] = sum / c * gain
            targetLow[p] = lo * gain
            targetHigh[p] = hi * gain
        }
        // Ease toward the new frame, the same at 60 or 120 Hz: the line in about 25 ms; the band
        // opens at once and closes over about 60 ms, like a phosphor glow fading.
        let ease = 1 - exp(-dt / 0.025)
        let fade = 1 - exp(-dt / 0.06)
        var spread: Float = 0
        for p in 0..<Self.pointCount {
            line[p] += (targetLine[p] - line[p]) * ease
            high[p] = targetHigh[p] > high[p] ? targetHigh[p] : high[p] + (targetHigh[p] - high[p]) * fade
            low[p] = targetLow[p] < low[p] ? targetLow[p] : low[p] + (targetLow[p] - low[p]) * fade
            // the band always wraps the line
            high[p] = max(high[p], line[p]); low[p] = min(low[p], line[p])
            spread = max(spread, high[p] - low[p])
        }
        // The colour follows the sound's balance over about 80 ms (silence keeps the last colour).
        let total = bassSum + topSum + 0.000_1 * Float(Self.window)
        let blend = 1 - exp(-dt / 0.08)
        if loud > 0.001 {
            bass += (bassSum / total - bass) * blend
            top += (min(1, topSum / total * 1.6) - top) * blend
        }
        return Frame(line: line, low: low, high: high, bass: bass, top: top, spread: spread)
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
