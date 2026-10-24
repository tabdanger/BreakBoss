// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// Sheets that open over the faceplate: the pad editor (your own samples and pad settings), the
// loop editor (make or change a groove step by step) and export.

private let panel = Color(white: 0.11)
private let accent = Color(red: 1, green: 0.30, blue: 0.20)

// MARK: - Pad sound menu (ONE-SHOT: hold a pad)

/// The pad sound menu (Tyrone's mockup, Oct 24): one floating hardware panel with SOUND / SAMPLES /
/// PAD tabs in the mode's colours (PadSoundPanel.swift). SOUND shows the loaded sound and the ways
/// to put yours on the pad, SAMPLES is the Samples folder, PAD is level, pan, tune, decay, filter
/// and reverse. Every action is the one the old pad editor ran.
struct PadEditorView: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var files: [URL] = []
    @State private var tab: PadSoundTab = .sound
    @State private var playedAt: Date?
    @StateObject private var recorder = PadRecorder()

    var body: some View {
        let look = PadSoundPalette.of(controller.faceKey)
        let settings = controller.state.pads[pad]
        VStack(spacing: 0) {
            header(look)
            tabStrip(look)
            ScrollView {
                tabBody(settings, look)
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            }
            footer(look)
        }
        .background(PadSoundBody(look: look))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padSoundSheetClear()
        .preferredColorScheme(.dark)
        .onAppear { files = KnockFolders.sampleFiles() }
        .onDisappear { if recorder.isRecording { recorder.cancel() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                controller.importSample(url, toPad: pad)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { files = KnockFolders.sampleFiles() }
            }
        }
    }

    // MARK: Header, tabs, footer

    /// PAD 07, what the panel's for, and DONE.
    private func header(_ look: PadSoundPalette) -> some View {
        HStack(spacing: 12) {
            PadSoundScrew(finish: look.finish)
            VStack(alignment: .leading, spacing: 5) {
                Text(String(format: "PAD %02d", pad + 1)).font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundColor(look.ink)
                    .accessibilityIdentifier("padSound.title")
                Text("SOUND / IMPORT / CONTROL").font(.system(size: 9, weight: .semibold, design: .monospaced)).kerning(0.6)
                    .foregroundColor(look.dim)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: { PadSoundKey(title: "DONE", look: look).frame(width: 76) }
                .buttonStyle(SeqPress())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Done")
                .accessibilityIdentifier("padSound.done")
        }
        .padding(.leading, 18).padding(.trailing, 16).padding(.top, 14).padding(.bottom, 12)
    }

    private func tabStrip(_ look: PadSoundPalette) -> some View {
        HStack(spacing: 6) {
            ForEach(PadSoundTab.allCases, id: \.self) { t in
                Button { tab = t } label: { PadSoundKey(title: t.rawValue, look: look, lit: tab == t) }
                    .buttonStyle(SeqPress())
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
                    .accessibilityIdentifier("padSound.tab.\(t.rawValue.lowercased())")
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    /// How many sounds are in the Samples folder, and the mode the panel is wearing.
    private func footer(_ look: PadSoundPalette) -> some View {
        HStack(spacing: 12) {
            PadSoundScrew(finish: look.finish, size: 11)
            Text("\(files.count) SOUND\(files.count == 1 ? "" : "S")").font(.system(size: 10, weight: .semibold, design: .monospaced)).kerning(0.6)
                .foregroundColor(look.dim)
                .accessibilityIdentifier("padSound.count")
            Spacer()
            Text(look.modeName).font(.system(size: 10, weight: .semibold, design: .monospaced)).kerning(0.6)
                .foregroundColor(look.dim)
            PadSoundScrew(finish: look.finish, size: 11)
        }
        .padding(.horizontal, 16).frame(height: 36)
        .overlay(Rectangle().fill(Color.black.opacity(0.25)).frame(height: 1), alignment: .top)
    }

    @ViewBuilder private func tabBody(_ settings: PadSettings, _ look: PadSoundPalette) -> some View {
        switch tab {
        case .sound: soundTab(settings, look)
        case .samples: samplesTab(settings, look)
        case .pad: padTab(settings, look)
        }
    }

    // MARK: SOUND

    /// The loaded sound, then Files, the mic and the Samples folder, and back to the kit.
    private func soundTab(_ settings: PadSettings, _ look: PadSoundPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            loadedCard(settings, look)
            PadSoundCaption(text: "ADD YOUR SOUND", color: look.dim).padding(.top, 10).padding(.leading, 2)
            PadSoundRow(icon: "folder", title: "IMPORT FROM FILES", detail: "Choose an audio file for this pad", look: look,
                        enabled: !recorder.isRecording, id: "padSound.import") { importing = true }
            if !controller.isPlugin { recordRow(look) }
            if let message = recorder.message {
                Text(message).font(.footnote).foregroundColor(look.accent)
            }
            PadSoundRow(icon: "waveform", title: "BROWSE SAMPLES", detail: "Load a sound from your sample library", look: look,
                        id: "padSound.browse") { tab = .samples }
            if settings.sampleFile != nil {
                PadSoundRow(icon: "arrow.uturn.backward", title: "BACK TO THE KIT'S SOUND", detail: "Put the kit's sound back on this pad",
                            look: look, id: "padSound.revert") { controller.revertPad(pad) }
            }
            Text("Import replaces the sound on this pad.\nYour other pads keep their sounds. You can also drag an audio file "
                 + "from Files straight onto a pad; imported sounds are copied to "
                 + (controller.isPlugin ? "the plug-in's Samples folder." : "Files › BreaKing › Samples on this device."))
                .font(.system(size: 12)).foregroundColor(look.dim).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func loadedCard(_ settings: PadSettings, _ look: PadSoundPalette) -> some View {
        let sample = pad < controller.kitSamples.count ? controller.kitSamples[pad] : nil
        let seconds = sample.map { Double($0.length) / max($0.sampleRate, 1) } ?? 0
        return PadLoadedSoundCard(name: controller.padName(pad), points: sample?.overview ?? [], reverse: settings.reverse,
                                  seconds: seconds, look: look, playedAt: playedAt) {
            controller.padDown(pad, velocity: 1)
            playedAt = Date()
        }
    }

    /// Record from the mic straight onto this pad (standalone app; a plug-in can't use the mic).
    @ViewBuilder private func recordRow(_ look: PadSoundPalette) -> some View {
        if recorder.isRecording {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            HStack(spacing: 12) {
                Button {
                    if let url = recorder.stop() {
                        controller.importSample(url, toPad: pad)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { files = KnockFolders.sampleFiles() }
                    }
                } label: {
                    Image(systemName: "stop.fill").font(.system(size: 16, weight: .bold)).foregroundColor(look.onAccent)
                        .frame(width: 48, height: 40).background(RoundedRectangle(cornerRadius: 7).fill(look.accent))
                }
                .buttonStyle(SeqPress())
                .accessibilityLabel("Stop recording")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.35))
                        Capsule().fill(look.accent).frame(width: g.size.width * CGFloat(recorder.level))
                    }
                }
                .frame(height: 8)
                Text(String(format: "%.1f s", recorder.seconds)).font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(look.ink)
                Button { recorder.cancel() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundColor(look.ink).frame(width: 40, height: 40)
                }
                .buttonStyle(SeqPress())
                .accessibilityLabel("Cancel recording")
            }
            .padding(.horizontal, 12).frame(minHeight: 64)
            .background(shape.fill(look.well))
            .overlay(shape.strokeBorder(look.accent, lineWidth: 1.5))
        } else {
            PadSoundRow(icon: "record.circle", title: "RECORD TO THIS PAD", detail: "Capture audio using the app recorder", look: look,
                        id: "padSound.record") { recorder.start() }
        }
    }

    // MARK: SAMPLES

    /// The Samples folder's sounds, one tap loads one.
    private func samplesTab(_ settings: PadSettings, _ look: PadSoundPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PadSoundCaption(text: "SAMPLES FOLDER", color: look.dim).padding(.leading, 2)
            if files.isEmpty {
                Text("No sounds in the Samples folder yet. Import or record one on the SOUND tab and it lands here.")
                    .font(.system(size: 13)).foregroundColor(look.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
            } else {
                ForEach(files, id: \.self) { url in
                    PadSoundRow(icon: "waveform", title: url.deletingPathExtension().lastPathComponent, detail: "", look: look,
                                checked: settings.sampleFile == url.lastPathComponent) {
                        controller.importSample(url, toPad: pad)
                    }
                }
            }
        }
    }

    // MARK: PAD

    /// Level, pan, tune, decay, filter, reverse.
    private func padTab(_ settings: PadSettings, _ look: PadSoundPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PadSoundCaption(text: "PAD", color: look.dim).padding(.leading, 2)
            PadSoundSlider(title: "Level", value: settings.level, range: PadSettings.minLevel...PadSettings.maxLevel,
                           text: PadSettings.levelText(settings.level), look: look) { v in
                var s = settings; s.level = v; controller.setPadSettings(pad, s)
            }
            PadSoundSlider(title: "Pan", value: settings.pan, range: -1...1, text: panText(settings.pan), look: look) { v in
                var s = settings; s.pan = abs(v) < 0.03 ? 0 : v; controller.setPadSettings(pad, s)
            }
            PadSoundSlider(title: "Tune", value: settings.tune, range: -24...24, text: String(format: "%+.1f st", settings.tune), look: look) { v in
                var s = settings; s.tune = (v * 2).rounded() / 2; controller.setPadSettings(pad, s)
            }
            PadSoundSlider(title: "Decay", value: settings.decay, range: 0.05...1,
                           text: settings.decay >= 0.999 ? "FULL" : String(format: "%.0f%%", settings.decay * 100), look: look) { v in
                var s = settings; s.decay = v; controller.setPadSettings(pad, s)
            }
            PadSoundSlider(title: "Filter", value: settings.filter, range: 0...1, text: filterText(settings.filter), look: look) { v in
                var s = settings; s.filter = v; controller.setPadSettings(pad, s)
            }
            reverseRow(settings, look)
            Text("Save these pads as your own kit from the KITS window (Save Kit As…).")
                .font(.system(size: 12)).foregroundColor(look.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private func reverseRow(_ settings: PadSettings, _ look: PadSoundPalette) -> some View {
        Button {
            var s = settings; s.reverse.toggle(); controller.setPadSettings(pad, s)
        } label: {
            HStack {
                Text("REVERSE").font(.system(size: 12, weight: .semibold, design: .monospaced)).kerning(0.6).foregroundColor(look.ink)
                Spacer()
                BBSwitchPill(on: settings.reverse, accent: look.accent)
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(look.well))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(look.wellEdge, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlatePress())
        .accessibilityLabel("Reverse")
        .accessibilityValue(settings.reverse ? "On" : "Off")
        .accessibilityIdentifier("padSound.reverse")
    }

    private func panText(_ pan: Float) -> String {
        pan == 0 ? "C" : String(format: "%@%.0f", pan < 0 ? "L" : "R", abs(pan) * 100)
    }

    private func filterText(_ filter: Float) -> String {
        filter >= 0.999_999 ? "OPEN" : String(format: "%.0f Hz", 40 * powf(450, filter))
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
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            loopHeading(p, edited: edited)
                            Spacer()
                            previewButton
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) {
                            loopHeading(p, edited: edited)
                            previewButton
                        }
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
                Text("Tap a square to add or remove a hit. Micro-timing and velocity from the generated groove are kept on hits you don't touch. Drop a MIDI file on the pad (or import one below) to use your own groove: notes 36–47 play pads 1–12 and 48–84 play the 808.")
                    .font(.footnote).foregroundColor(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { loopActions(edited: edited) }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) { loopActions(edited: edited) }
                    }
                .buttonStyle(.bordered)
                }.padding()
            }
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

    private func loopHeading(_ pattern: PatternData, edited: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("LOOP \(loop + 1) · \(pattern.name)").font(.system(.title3, design: .monospaced))
            if edited { Text("EDITED").font(.system(.caption, design: .monospaced)).foregroundColor(accent) }
        }
    }

    private var previewButton: some View {
        Button { controller.previewLoop(loop) } label: { Label("Play / Stop", systemImage: "playpause.fill") }
            .buttonStyle(.borderedProminent).tint(accent)
    }

    @ViewBuilder private func loopActions(edited: Bool) -> some View {
        Button { controller.regenerateLoop(loop) } label: { Label("New groove", systemImage: "dice") }
        Button { importingMIDI = true } label: { Label("Import MIDI…", systemImage: "pianokeys") }
        Button(role: .destructive) { controller.clearLoop(loop) } label: { Label("Clear", systemImage: "trash") }
        if edited {
            Button { controller.useGeneratedLoop(loop) } label: { Label("Back to generated", systemImage: "arrow.uturn.backward") }
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
                whatSection
                resultSections
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

    /// Loop, length, tempo and RENDER.
    private var whatSection: some View {
        Section("What to export") {
            Picker("Loop", selection: $loop) {
                ForEach(0..<controller.loops.count, id: \.self) { i in
                    Text("\(i + 1)  \(controller.loops[i].name)").tag(i)
                }
            }
            .pickerStyle(.inline)
            Picker("Length", selection: $bars) {
                ForEach([1, 2, 4, 8, 16], id: \.self) { Text("\($0) bars").tag($0) }
            }
            .pickerStyle(.segmented)
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
    }

    /// What went wrong, or the files: MIDI, the mix, the stems, SHARE.
    @ViewBuilder private var resultSections: some View {
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
                    Text("Each stem includes processing independently. Nonlinear saturation and clipping mean these stems may not sum exactly to the stereo mix.")
                        .font(.footnote).foregroundColor(.secondary)
                    ForEach(out.stems, id: \.url) { stem in
                        DragTile(title: stem.name, subtitle: stem.url.lastPathComponent, icon: "waveform.path", url: stem.url)
                    }
                }
            }
            Section {
                ShareLink(items: allURLs(out)) { Label("Share or save everything…", systemImage: "square.and.arrow.up") }
                if !controller.isPlugin {
                    Text("Also in Files › BreaKing › Exports on this device.").font(.footnote).foregroundColor(.secondary)
                }
            }
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
