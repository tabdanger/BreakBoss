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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let now = context.date
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let scope = controller.engine.master.scope
                    let n = MasterBus.scopeSize
                    let count = 300
                    let end = controller.engine.master.scopeWrite
                    var path = Path()
                    let mid = size.height / 2
                    for i in 0..<count {
                        let idx = (end - count + i + n) & (n - 1)
                        let v = CGFloat(max(-1, min(1, scope[idx])))
                        let x = CGFloat(i) / CGFloat(count - 1) * size.width
                        let y = mid - v * mid * 0.85
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    var glow = ctx
                    glow.addFilter(.blur(radius: 3 * scale))
                    glow.stroke(path, with: .color(ScopeView.red.opacity(0.55)), lineWidth: 4 * scale)
                    ctx.stroke(path, with: .color(Color(red: 1, green: 0.55, blue: 0.42)), lineWidth: 1.6 * scale)
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
        let e = controller.engine
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

// MARK: - Pads

/// One pad. Touch plays it straight away (higher on the pad = softer, lower = harder).
/// Hold it for a second to open its editor. Drop an audio file on it to load your own sound;
/// in LOOP mode, drop a MIDI file to load your own groove.
struct PadView: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    let rect: [Double]
    let scale: CGFloat
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
            let hits = controller.engine.padHits[pad]
            let now = context.date
            let flash = flashAmount(hits: hits, now: now)
            let loopMode = controller.playMode == .loop
            let current = Int(controller.engine.status[1]) == pad && controller.engine.status[0] > 0.5
            let queued = Int(controller.engine.status[2]) == pad
            let blink = queued && Int(now.timeIntervalSinceReferenceDate * 4) % 2 == 0
            ZStack {
                Rectangle().fill(Color.black.opacity(pressed ? 0.12 : 0))
                Rectangle().fill(Color.white.opacity(Double(flash) * 0.32))
                if loopMode && (current || blink) {
                    Rectangle()
                        .strokeBorder(ScopeView.red.opacity(current ? 0.9 : 0.6), lineWidth: 3 * scale)
                        .shadow(color: ScopeView.red.opacity(0.7), radius: 6 * scale)
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
                    controller.padDown(pad, velocity: 0.55 + 0.45 * y.clamped(0, 1))
                    let work = DispatchWorkItem { if pressed { openEditor(controller.playMode == .loop) } }
                    hold = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
                }
                .onEnded { _ in
                    pressed = false
                    hold?.cancel()
                    hold = nil
                }
        )
        .onDrop(of: [UTType.fileURL, UTType.audio, UTType.midi], isTargeted: $dropping) { providers in
            handleDrop(providers)
        }
        .position(x: r.midX * scale, y: r.midY * scale)
        .accessibilityLabel("Pad \(pad + 1)")
    }

    private func flashAmount(hits: UInt32, now: Date) -> Float {
        if hits != memory.count {
            memory.count = hits
            memory.time = now
        }
        let dt = Float(now.timeIntervalSince(memory.time))
        return max(0, 1 - dt / 0.16)
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
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: copy)
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil { use(copy) }
            }
            return true
        }
        return false
    }
}
