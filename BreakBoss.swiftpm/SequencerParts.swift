// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// The tempo slider panel (header BPM). Follows the DAW / MIDI clock when TEMPO SYNC has one.
struct TempoPanel: View {
    @Environment(\.bbMenuAccent) private var accent
    @ObservedObject var controller: KnockController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if controller.tempoIsExternal {
                Text("Tempo follows the DAW / MIDI clock: \(Int(controller.liveTempo.rounded())) BPM")
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(BBMenuStyle.dim)
            } else {
                BBSlider(value: controller.state.bpm, range: 40...280, step: 1, label: { "\(Int($0)) BPM" }) { controller.setBPM($0) }
                HStack(spacing: 6) {
                    ForEach([80, 90, 100, 120, 140, 150, 160, 170], id: \.self) { b in
                        Button { controller.setBPM(Double(b)) } label: {
                            Text("\(b)").font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(Int(controller.state.bpm) == b ? .black : BBMenuStyle.text)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Int(controller.state.bpm) == b ? (accent ?? BBMenuStyle.accent) : BBMenuStyle.row))
                        }
                    }
                }
            }
        }
    }
}

/// The picture's knob, turned to its value: drag up or right to turn it up.
struct ArtKnob: View {
    let value: Float
    /// Extra touchable margin round the knob (it's small in the picture).
    var grip: CGFloat = 0
    /// A double tap puts the knob back here (pan: centre).
    var reset: Float? = nil
    /// Or a double tap does this instead (DELAY: tempo lock on / off).
    var doubleTap: (() -> Void)? = nil
    /// The value readout shown over the knob while it turns (Tyrone, Oct 19).
    var hud: KnobHUD? = nil
    let change: (Float, Bool) -> Void
    @State private var start: Float?
    @State private var lastTap: Date?
    @State private var showHUD = false
    @State private var hudRelease = 0

    var body: some View {
        MetalKnob().aspectRatio(1, contentMode: .fit)
            .rotationEffect(.degrees(KnobControl.angle(value)))
            // follows the finger exactly while it turns (an ease on every move made it lag and step);
            // a double tap's reset still swings there
            .animation(start == nil ? .easeOut(duration: 0.15) : nil, value: value)
            .anchorPreference(key: KnobHUDKey.self, value: .bounds) { a in
                guard showHUD, let hud else { return [] }
                return [KnobHUDEntry(hud: hud, anchor: a)]
            }
            .padding(grip)
            .contentShape(Rectangle())
            // high priority: the rack's knobs turn instead of scrolling the rack. That drag takes every
            // touch, so an onTapGesture(count: 2) beside it never saw a tap: the double tap is counted here.
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if start == nil { start = value }
                    if hud != nil && !showHUD { showHUD = true }
                    hudRelease += 1
                    let d = KnobFeel.delta(g.translation, travel: KnobFeel.small)
                    change(((start ?? value) + d).clamped(0, 1), false)
                }
                .onEnded { g in
                    let isTap = abs(g.translation.width) < 6 && abs(g.translation.height) < 6
                    if isTap, reset != nil || doubleTap != nil, let t = lastTap, Date().timeIntervalSince(t) < 0.35 {
                        if let doubleTap { doubleTap(); change(start ?? value, true) } else if let reset { change(reset, true) }
                        lastTap = nil
                    } else {
                        let d = KnobFeel.delta(g.translation, travel: KnobFeel.small)
                        change(((start ?? value) + d).clamped(0, 1), true)
                        lastTap = isTap ? Date() : nil
                    }
                    start = nil
                    // the readout stays a moment after the finger lifts, then goes
                    releaseHUD()
                })
            // mouse wheel / trackpad scroll turns it too (over the rack it turns the knob, not the rack)
            .scrollTurn { t, ended in
                if start == nil { start = value }
                if hud != nil && !showHUD { showHUD = true }
                hudRelease += 1
                let d = KnobFeel.delta(t, travel: KnobFeel.small)
                change(((start ?? value) + d).clamped(0, 1), ended)
                if ended {
                    start = nil
                    releaseHUD()
                }
            }
    }

    private func releaseHUD() {
        hudRelease += 1
        let token = hudRelease
        DispatchQueue.main.asyncAfter(deadline: .now() + KnobHUD.linger) {
            if hudRelease == token { withAnimation(.easeOut(duration: 0.2)) { showHUD = false } }
        }
    }
}

/// A small knob (the track settings): drag up or right to turn it up.
struct DrumRollKnob: View {
    let value: Float
    var size: CGFloat = 36
    let change: (Float, Bool) -> Void
    @State private var start: Float?

    var body: some View {
        ZStack {
            MetalKnob(pointer: false)
            Capsule().fill(Color(white: 0.12)).frame(width: 2.5, height: size * 0.22)
                .offset(y: -size * 0.2)
                .rotationEffect(.degrees(KnobControl.angle(value)))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 1)
            .onChanged { g in
                if start == nil { start = value }
                let d = KnobFeel.delta(g.translation, travel: KnobFeel.small)
                change(((start ?? value) + d).clamped(0, 1), false)
            }
            .onEnded { g in
                let d = KnobFeel.delta(g.translation, travel: KnobFeel.small)
                change(((start ?? value) + d).clamped(0, 1), true)
                start = nil
            })
    }
}

/// Record from the mic straight onto one channel (standalone app).
struct ChannelRecordSheet: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = PadRecorder()

    var body: some View {
        NavigationView {
            VStack(spacing: 22) {
                Text(controller.rackChannels.first(where: { $0.pad == pad })?.name ?? Pad(rawValue: pad)?.channelTitle ?? "PAD").font(.system(.title2, design: .monospaced))
                if recorder.isRecording {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(white: 0.2))
                            Capsule().fill(DrumRollStyle.red).frame(width: g.size.width * CGFloat(recorder.level))
                        }
                    }
                    .frame(height: 10)
                    Text(String(format: "%.1f s", recorder.seconds)).font(.system(.title3, design: .monospaced))
                    Button {
                        if let url = recorder.stop() {
                            controller.importSample(url, toPad: pad)
                            dismiss()
                        }
                    } label: { Label("Stop and use it", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DrumRollStyle.red)
                } else {
                    Button { recorder.start() } label: { Label("Record", systemImage: "record.circle").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(DrumRollStyle.red)
                    Text("Make your sound when you're ready. The silence before it is trimmed, so the channel hits right away.")
                        .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                if let m = recorder.message { Text(m).font(.footnote).foregroundColor(DrumRollStyle.red) }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Record to channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { recorder.cancel(); dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .onDisappear { if recorder.isRecording { recorder.cancel() } }
    }
}
