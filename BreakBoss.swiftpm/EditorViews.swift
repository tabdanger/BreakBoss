// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// Sheets that open over the faceplate: the pad editor (your own samples and pad settings), the
// loop editor (make or change a groove step by step) and export.

private let panel = Color(white: 0.11)
private let accent = Color(red: 1, green: 0.30, blue: 0.20)

// MARK: - Pad editor (ONE-SHOT: hold a pad)

struct PadEditorView: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var files: [URL] = []

    var body: some View {
        let settings = controller.state.pads[pad]
        NavigationView {
            Form {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PAD \(pad + 1) · \(Pad(rawValue: pad)?.label ?? "")")
                                .font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                            Text(controller.padName(pad).uppercased())
                                .font(.system(.title3, design: .monospaced))
                        }
                        Spacer()
                        Button { controller.padDown(pad, velocity: 1) } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    }
                    if pad < controller.kitSamples.count {
                        Waveform(points: controller.kitSamples[pad].overview, reverse: settings.reverse)
                            .frame(height: 70)
                    }
                }

                Section("Your sound") {
                    Button { importing = true } label: { Label("Import an audio file…", systemImage: "square.and.arrow.down") }
                    if settings.sampleFile != nil {
                        Button(role: .destructive) { controller.revertPad(pad) } label: {
                            Label("Back to the kit's sound", systemImage: "arrow.uturn.backward")
                        }
                    }
                    Text("You can also drag an audio file from Files straight onto a pad. Imported sounds are copied to "
                         + (controller.isPlugin ? "the plug-in's Samples folder." : "Files › On My iPad › BreakBoss › Samples."))
                        .font(.footnote).foregroundColor(.secondary)
                }

                if !files.isEmpty {
                    Section("Samples folder") {
                        ForEach(files, id: \.self) { url in
                            Button {
                                controller.importSample(url, toPad: pad)
                            } label: {
                                HStack {
                                    Image(systemName: "waveform")
                                    Text(url.deletingPathExtension().lastPathComponent)
                                    Spacer()
                                    if settings.sampleFile == url.lastPathComponent { Image(systemName: "checkmark").foregroundColor(accent) }
                                }
                            }
                        }
                    }
                }

                Section("Pad") {
                    slider("Level", settings.level, 0...1, text: String(format: "%.0f%%", settings.level / 0.8 * 100)) { v in
                        var s = settings; s.level = v; controller.setPadSettings(pad, s)
                    }
                    slider("Pan", settings.pan, -1...1, text: settings.pan == 0 ? "C" : String(format: "%@%.0f", settings.pan < 0 ? "L" : "R", abs(settings.pan) * 100)) { v in
                        var s = settings; s.pan = abs(v) < 0.03 ? 0 : v; controller.setPadSettings(pad, s)
                    }
                    slider("Tune", settings.tune, -24...24, text: String(format: "%+.1f st", settings.tune)) { v in
                        var s = settings; s.tune = (v * 2).rounded() / 2; controller.setPadSettings(pad, s)
                    }
                    slider("Decay", settings.decay, 0.05...1, text: settings.decay >= 0.999 ? "FULL" : String(format: "%.0f%%", settings.decay * 100)) { v in
                        var s = settings; s.decay = v; controller.setPadSettings(pad, s)
                    }
                    Toggle("Reverse", isOn: Binding(get: { settings.reverse }, set: { v in
                        var s = settings; s.reverse = v; controller.setPadSettings(pad, s)
                    }))
                    .tint(accent)
                }

                Section {
                    Text("Save these pads as your own kit from the KITS window (Save Kit As…).")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Pad \(pad + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .onAppear { files = KnockFolders.sampleFiles() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                controller.importSample(url, toPad: pad)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { files = KnockFolders.sampleFiles() }
            }
        }
    }

    private func slider(_ title: String, _ value: Float, _ range: ClosedRange<Float>, text: String,
                        set: @escaping (Float) -> Void) -> some View {
        HStack {
            Text(title).frame(width: 70, alignment: .leading)
            Slider(value: Binding(get: { value }, set: set), in: range).tint(accent)
            Text(text).font(.system(.body, design: .monospaced)).frame(width: 80, alignment: .trailing)
        }
    }
}

struct Waveform: View {
    let points: [Float]
    let reverse: Bool

    var body: some View {
        Canvas { ctx, size in
            guard !points.isEmpty else { return }
            let peak = max(points.max() ?? 1, 0.0001)
            var path = Path()
            let n = points.count
            for i in 0..<n {
                let v = CGFloat(points[reverse ? n - 1 - i : i] / peak)
                let x = CGFloat(i) / CGFloat(n - 1) * size.width
                path.move(to: CGPoint(x: x, y: size.height / 2 - v * size.height / 2))
                path.addLine(to: CGPoint(x: x, y: size.height / 2 + v * size.height / 2))
            }
            ctx.stroke(path, with: .color(accent), lineWidth: max(1, size.width / CGFloat(n) * 0.7))
        }
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Loop editor (LOOP: hold a pad)

struct LoopEditorView: View {
    @ObservedObject var controller: KnockController
    let loop: Int
    @Environment(\.dismiss) private var dismiss
    @State private var importingMIDI = false

    var body: some View {
        let p = loop < controller.loops.count ? controller.loops[loop] : PatternData(name: "", lengthTicks: 768, events: [])
        let steps = max(16, Int(p.lengthTicks / PatternData.stepTicks))
        let edited = loop < controller.state.editedLoops.count && controller.state.editedLoops[loop] != nil
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("LOOP \(loop + 1) · \(p.name)").font(.system(.title3, design: .monospaced))
                    if edited { Text("EDITED").font(.system(.caption, design: .monospaced)).foregroundColor(accent) }
                    Spacer()
                    Button { controller.padDown(loop, velocity: 1) } label: { Label("Play / Stop", systemImage: "playpause.fill") }
                        .buttonStyle(.borderedProminent).tint(accent)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach((0..<Pad.count).reversed(), id: \.self) { row in
                            HStack(spacing: 3) {
                                Text(controller.padName(row).uppercased())
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(width: 92, alignment: .leading)
                                ForEach(0..<steps, id: \.self) { step in
                                    let on = hasHit(p, pad: row, step: step)
                                    Rectangle()
                                        .fill(on ? accent : Color(white: step % 4 == 0 ? 0.26 : 0.18))
                                        .frame(width: 22, height: 22)
                                        .overlay(Rectangle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                                        .padding(.leading, step > 0 && step % 16 == 0 ? 6 : 0)
                                        .onTapGesture { controller.toggleStep(loop: loop, pad: row, step: step) }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Text("Tap a square to add or remove a hit. Micro-timing and velocity from the generated groove are kept on hits you don't touch. Drop a MIDI file on the pad (or import one below) to use your own groove: notes C1-B1 play pads 1-12, C2 and up play the 808.")
                    .font(.footnote).foregroundColor(.secondary)
                HStack {
                    Button { controller.regenerateLoop(loop) } label: { Label("New groove", systemImage: "dice") }
                    Button { importingMIDI = true } label: { Label("Import MIDI…", systemImage: "pianokeys") }
                    Button(role: .destructive) { controller.clearLoop(loop) } label: { Label("Clear", systemImage: "trash") }
                    if edited {
                        Button { controller.useGeneratedLoop(loop) } label: { Label("Back to generated", systemImage: "arrow.uturn.backward") }
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding()
            .navigationTitle("Loop \(loop + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $importingMIDI, allowedContentTypes: [.midi], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { controller.importMIDI(url, toLoop: loop) }
        }
    }

    private func hasHit(_ p: PatternData, pad: Int, step: Int) -> Bool {
        let lo = Int32(step) * PatternData.stepTicks - 6
        let hi = Int32(step) * PatternData.stepTicks + 18
        return p.events.contains { Int($0.pad) == pad && $0.tick >= lo && $0.tick < hi }
    }
}

// MARK: - Export (the arrow button, top right)

struct ExportView: View {
    @ObservedObject var controller: KnockController
    @Environment(\.dismiss) private var dismiss
    @State private var loop = 0
    @State private var bars = 4
    @State private var working = false
    @State private var output: Exporter.Output?
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                Section("What to export") {
                    Picker("Loop", selection: $loop) {
                        ForEach(0..<controller.loops.count, id: \.self) { i in
                            Text("\(i + 1)  \(controller.loops[i].name)").tag(i)
                        }
                    }
                    Picker("Length", selection: $bars) {
                        ForEach([1, 2, 4, 8, 16], id: \.self) { Text("\($0) bars").tag($0) }
                    }
                    HStack {
                        Text("Tempo")
                        Spacer()
                        Text("\(Int(controller.liveTempo.rounded())) BPM").font(.system(.body, design: .monospaced))
                    }
                    Button {
                        render()
                    } label: {
                        HStack {
                            Label(working ? "Rendering…" : "Render MIDI, mix and stems", systemImage: "waveform.badge.plus")
                            if working { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(working)
                }

                if let error {
                    Section { Text(error).foregroundColor(.red) }
                }

                if let out = output {
                    Section {
                        Text("Drag any of these into your DAW's timeline, or share them.")
                            .font(.footnote).foregroundColor(.secondary)
                        if let midi = out.midi { DragTile(title: "MIDI", subtitle: midi.lastPathComponent, icon: "pianokeys", url: midi) }
                        if let mix = out.mix { DragTile(title: "STEREO MIX", subtitle: mix.lastPathComponent, icon: "waveform", url: mix) }
                    } header: { Text("Exported") }
                    if !out.stems.isEmpty {
                        Section("Stems") {
                            ForEach(out.stems, id: \.url) { stem in
                                DragTile(title: stem.name, subtitle: stem.url.lastPathComponent, icon: "waveform.path", url: stem.url)
                            }
                        }
                    }
                    Section {
                        ShareLink(items: allURLs(out)) { Label("Share or save everything…", systemImage: "square.and.arrow.up") }
                        if !controller.isPlugin {
                            Text("Also in Files › On My iPad › BreakBoss › Exports.").font(.footnote).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .onAppear {
            loop = controller.exportLoopIndex
            bars = max(2, controller.loops.indices.contains(loop) ? controller.loops[loop].bars : 2) * 2
        }
    }

    private func allURLs(_ out: Exporter.Output) -> [URL] {
        var urls: [URL] = []
        if let m = out.midi { urls.append(m) }
        if let m = out.mix { urls.append(m) }
        urls += out.stems.map { $0.url }
        return urls
    }

    private func render() {
        working = true
        error = nil
        controller.export(loop: loop, bars: bars, midi: true, mix: true, stems: true) { result in
            working = false
            switch result {
            case .success(let out): output = out
            case .failure(let e): error = e.localizedDescription
            }
        }
    }
}

/// A file you can drag out (into a DAW timeline, Files, another app).
struct DragTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundColor(accent).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.body, design: .monospaced))
                Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "hand.draw").foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag {
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            provider.suggestedName = url.deletingPathExtension().lastPathComponent
            return provider
        }
    }
}
