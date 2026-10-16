// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

/// Additional performance surface; the approved faceplate artwork and hit regions stay fixed.
struct PerformanceView: View {
    @ObservedObject var controller: KnockController
    @Environment(\.dismiss) private var dismiss
    @State private var editor: FaceplateView.EditorTarget?
    @State private var pattern = 0
    @State private var export = false

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let compact = geo.size.width < 600
                if geo.size.width > geo.size.height && geo.size.height < 500 {
                    let controlWidth = min(260, max(200, geo.size.width * 0.3))
                    HStack(spacing: 12) {
                        ScrollView(.vertical) {
                            VStack(spacing: 12) {
                                performanceHeader(compact: true)
                                patternControls(compact: true)
                                performanceGuide(compact: true)
                            }
                        }.frame(width: controlWidth)
                        padGrid(width: geo.size.width - controlWidth - 44,
                                height: geo.size.height - 32, compact: true)
                    }.padding()
                } else {
                    VStack(spacing: 10) {
                        performanceHeader(compact: compact)
                        GeometryReader { grid in
                            padGrid(width: grid.size.width, height: grid.size.height, compact: compact)
                        }
                        .frame(minHeight: 206)
                        patternControls(compact: compact)
                        performanceGuide(compact: compact)
                    }
                    .padding()
                }
            }
            .font(.system(.body, design: .monospaced))
            .background(Color(white: 0.07))
            .navigationTitle("BreakBoss · 12 Pads").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack).preferredColorScheme(.dark)
        .bbMenuHost()
        .sheet(item: $editor) { target in
            if target.loop { LoopEditorView(controller: controller, loop: target.pad) }
            else { PadEditorView(controller: controller, pad: target.pad) }
        }
        .sheet(isPresented: $export) { ExportView(controller: controller) }
        .onDisappear { controller.panic() }
    }

    private func performanceGuide(compact: Bool) -> some View {
        Text(compact ? "Hold for the editor. Drop audio to replace a sound. Release loops to stop."
             : "Hold a pad for its editor. Drop audio onto a pad to replace its sound. In LOOP mode, release to stop.")
            .font(.footnote).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playModePicker: some View {
        Picker("Play mode", selection: Binding(get: { controller.playMode.rawValue }, set: {
            controller.selectPlayMode(PlayMode(rawValue: $0) ?? .oneShot)
        })) {
            Text("ONE-SHOT").tag(0)
            Text("HOLD TO LOOP").tag(1)
        }.pickerStyle(.segmented).frame(maxWidth: 380)
    }

    private var kitActions: some View {
        HStack {
            Text(controller.state.kitName).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Button { controller.dice() } label: {
                Image(systemName: "dice").accessibilityLabel("Randomize")
            }
            .frame(minWidth: 44, minHeight: 44)
            Button("STOP") { controller.panic() }.tint(.red)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    @ViewBuilder private func performanceHeader(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 4) { playModePicker; kitActions }
        } else {
            HStack { playModePicker; Spacer(); kitActions }
        }
    }

    private func padGrid(width: CGFloat, height: CGFloat, compact: Bool) -> some View {
        let w = max(44, (width - 30) / 4)
        let h = max(44, (height - 30) / 4)
        return VStack(spacing: 10) {
            ForEach((0..<4).reversed(), id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { col in
                        let pad = row * 4 + col
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.4), lineWidth: 1))
                            VStack(alignment: .leading, spacing: 4) {
                                if compact {
                                    HStack(spacing: 2) {
                                        Text(String(format: "%02d", pad + 1)).foregroundColor(ScopeView.red)
                                        Spacer(minLength: 0)
                                        Text("M\(Pad(rawValue: pad)?.midiNote ?? 36)").foregroundColor(.secondary)
                                    }.font(.system(size: 9, design: .monospaced))
                                    Text(padTitle(pad)).lineLimit(h < 70 ? 1 : 2).minimumScaleFactor(0.6)
                                    Spacer(minLength: 0)
                                } else {
                                    Text(String(format: "%02d", pad + 1)).foregroundColor(ScopeView.red)
                                    Text(padTitle(pad)).lineLimit(2).minimumScaleFactor(0.6)
                                    Spacer(minLength: 0)
                                    Text("MIDI \(Pad(rawValue: pad)?.midiNote ?? 36)")
                                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                }
                            }
                            .font(.system(compact ? .caption : .body, design: .monospaced))
                            .padding(compact ? 6 : 12).allowsHitTesting(false)
                            PadView(controller: controller, pad: pad, rect: [0, 0, Double(w), Double(h)], scale: 1,
                                    holdToPlay: true) { isLoop in
                                editor = FaceplateView.EditorTarget(pad: pad, loop: isLoop)
                            }
                        }.frame(width: w, height: h).clipped()
                    }
                }
            }
        }
    }

    private var patternPicker: some View {
        HStack {
            Text(controller.loops.indices.contains(pattern) ? controller.loops[pattern].name : "PATTERN")
                .font(.system(.body, design: .monospaced))
            Image(systemName: "chevron.down")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.16)))
        .bbMenu(title: "Pattern") {
            controller.loops.indices.map { i in BBMenuItem.item("\(i + 1)  \(controller.loops[i].name)", checked: i == pattern) { pattern = i } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func patternControls(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 8) {
                HStack { patternPicker; Button("Export") { export = true } }
                HStack {
                    Button("Program pattern") { editor = FaceplateView.EditorTarget(pad: pattern, loop: true) }
                        .frame(maxWidth: .infinity)
                    Button("Play / Stop") { controller.previewLoop(pattern) }
                        .frame(maxWidth: .infinity)
                }
            }.buttonStyle(.bordered)
        } else {
            HStack {
                patternPicker
                Button("Program pattern") { editor = FaceplateView.EditorTarget(pad: pattern, loop: true) }
                Button("Play / Stop pattern") { controller.previewLoop(pattern) }
                Spacer()
                Button("Export") { export = true }
            }.buttonStyle(.bordered)
        }
    }

    private func padTitle(_ pad: Int) -> String {
        if controller.playMode == .loop, controller.loops.indices.contains(pad) { return controller.loops[pad].name }
        return controller.padName(pad).uppercased()
    }
}
