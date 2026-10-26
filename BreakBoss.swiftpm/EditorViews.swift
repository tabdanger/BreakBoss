// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// Sheets that open over the faceplate: the pad editor (your own samples and pad settings), the
// loop editor (make or change a groove step by step) and export.

private let panel = Color(white: 0.11)
private let accent = Color(red: 1, green: 0.30, blue: 0.20)

// MARK: - Pad sound menu (ONE-SHOT: hold a pad)

/// The pad sound menu (Tyrone's mockup, Oct 24): one floating hardware window with SOUND / SAMPLES /
/// PAD tabs in the menu's and SAMPLER's hardware (BKMenuPalette, PadSoundPanel.swift). SOUND shows the
/// loaded sound and the ways to put yours on the pad, SAMPLES is the Samples folder, PAD is level,
/// pan, tune, decay, filter, reverse and NOTE REPEAT. Every action is the one the old pad editor ran.
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
        let palette = BKMenuPalette.of(controller.faceKey)
        let settings = controller.state.pads[pad]
        VStack(spacing: 0) {
            header(palette)
            tabStrip(palette)
            ScrollView {
                tabBody(settings, palette)
                    .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 16)
            }
            footer(palette)
        }
        .background(PadSoundBody(palette: palette))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .environment(\.seqFinish, palette.finish)
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

    /// PAD 07, what the window's for, and DONE.
    private func header(_ palette: BKMenuPalette) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(String(format: "PAD %02d", pad + 1)).font(.system(size: 19, weight: .bold, design: .monospaced))
                    .foregroundColor(palette.text)
                    .accessibilityIdentifier("padSound.title")
                Text("SOUND / IMPORT / CONTROL").font(.system(size: 9, weight: .semibold, design: .monospaced)).kerning(0.6)
                    .foregroundColor(palette.secondary)
            }
            Spacer(minLength: 8)
            Button { dismiss() } label: { PadSoundKeyFace(title: "DONE", palette: palette, height: 40).frame(width: 84) }
                .buttonStyle(BKPanelKeyStyle(palette: palette))
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Done")
                .accessibilityIdentifier("padSound.done")
        }
        .padding(.leading, 26).padding(.trailing, 22).padding(.top, 18).padding(.bottom, 12)
    }

    private func tabStrip(_ palette: BKMenuPalette) -> some View {
        HStack(spacing: 8) {
            ForEach(PadSoundTab.allCases, id: \.self) { t in
                Button { tab = t } label: { PadSoundKeyFace(title: t.rawValue, palette: palette, lamp: tab == t) }
                    .buttonStyle(BKPanelKeyStyle(palette: palette))
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
                    .accessibilityIdentifier("padSound.tab.\(t.rawValue.lowercased())")
            }
        }
        .padding(.horizontal, 18).padding(.bottom, 14)
    }

    /// How many sounds are in the Samples folder, and the mode the window is wearing.
    private func footer(_ palette: BKMenuPalette) -> some View {
        HStack(spacing: 12) {
            Text("\(files.count) SOUND\(files.count == 1 ? "" : "S")").font(.system(size: 10, weight: .semibold, design: .monospaced)).kerning(0.6)
                .foregroundColor(palette.secondary)
                .accessibilityIdentifier("padSound.count")
            Spacer()
            Text(palette.modeName).font(.system(size: 10, weight: .semibold, design: .monospaced)).kerning(0.6)
                .foregroundColor(palette.secondary)
        }
        .padding(.horizontal, 30).frame(height: 38)
        .overlay(Rectangle().fill(Color.black.opacity(0.3)).frame(height: 1)
                    .overlay(Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1).offset(y: 1)), alignment: .top)
    }

    @ViewBuilder private func tabBody(_ settings: PadSettings, _ palette: BKMenuPalette) -> some View {
        switch tab {
        case .sound: soundTab(settings, palette)
        case .samples: samplesTab(settings, palette)
        case .pad: padTab(settings, palette)
        }
    }

    // MARK: SOUND

    /// The loaded sound, then Files, the mic and the Samples folder, and back to the kit.
    private func soundTab(_ settings: PadSettings, _ palette: BKMenuPalette) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            loadedCard(settings, palette)
            PadSoundCaption(text: "ADD YOUR SOUND", color: palette.secondary).padding(.top, 8).padding(.leading, 2)
            PadSoundRow(icon: "folder", title: "IMPORT FROM FILES", detail: "Choose an audio file for this pad", palette: palette,
                        enabled: !recorder.isRecording, id: "padSound.import") { importing = true }
            if !controller.isPlugin { recordRow(palette) }
            if let message = recorder.message {
                Text(message).font(.system(size: 12, design: .monospaced)).foregroundColor(palette.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BKRecessedPanel(palette: palette))
            }
            PadSoundRow(icon: "waveform", title: "BROWSE SAMPLES", detail: "Load a sound from your sample library", palette: palette,
                        id: "padSound.browse") { tab = .samples }
            if settings.sampleFile != nil {
                PadSoundRow(icon: "arrow.uturn.backward", title: "BACK TO THE KIT'S SOUND", detail: "Put the kit's sound back on this pad",
                            palette: palette, id: "padSound.revert") { controller.revertPad(pad) }
            }
            Text("Import replaces the sound on this pad.\nYour other pads keep their sounds. You can also drag an audio file "
                 + "from Files straight onto a pad; imported sounds are copied to "
                 + (controller.isPlugin ? "the plug-in's Samples folder." : "Files › BreaKing › Samples on this device."))
                .font(.system(size: 12)).foregroundColor(palette.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }

    private func loadedCard(_ settings: PadSettings, _ palette: BKMenuPalette) -> some View {
        let sample = pad < controller.kitSamples.count ? controller.kitSamples[pad] : nil
        let seconds = sample.map { Double($0.length) / max($0.sampleRate, 1) } ?? 0
        return PadLoadedSoundCard(name: controller.padName(pad), points: sample?.overview ?? [], reverse: settings.reverse,
                                  seconds: seconds, palette: palette, playedAt: playedAt) {
            controller.padDown(pad, velocity: 1)
            playedAt = Date()
        }
    }

    /// Record from the mic straight onto this pad (standalone app; a plug-in can't use the mic).
    @ViewBuilder private func recordRow(_ palette: BKMenuPalette) -> some View {
        if recorder.isRecording {
            HStack(spacing: 12) {
                Button {
                    if let url = recorder.stop() {
                        controller.importSample(url, toPad: pad)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { files = KnockFolders.sampleFiles() }
                    }
                } label: {
                    HStack(spacing: 8) {
                        BKMenuLED(isOn: true, accent: palette.accent, width: 10, height: 10)
                        Image(systemName: "stop.fill").font(.system(size: 14, weight: .bold))
                    }
                    .frame(width: 64, height: 42)
                }
                .buttonStyle(BKPanelKeyStyle(palette: palette))
                .accessibilityLabel("Stop recording")
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        BKMenuWell()
                        RoundedRectangle(cornerRadius: 2).fill(palette.accent)
                            .frame(width: max(0, (g.size.width - 8) * CGFloat(recorder.level)), height: 4).padding(.leading, 4)
                    }
                }
                .frame(height: 12)
                PadReadout(text: String(format: "%.1f s", recorder.seconds), palette: palette, width: 70)
                Button { recorder.cancel() } label: {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 42, height: 42)
                }
                .buttonStyle(BKPanelKeyStyle(palette: palette))
                .accessibilityLabel("Cancel recording")
            }
            .padding(.horizontal, 12).frame(minHeight: 66)
            .background(BKRecessedPanel(palette: palette))
        } else {
            PadSoundRow(icon: "record.circle", title: "RECORD TO THIS PAD", detail: "Capture audio using the app recorder", palette: palette,
                        id: "padSound.record") { recorder.start() }
        }
    }

    // MARK: SAMPLES

    /// The Samples folder's sounds (its subfolders too), one tap loads one.
    private func samplesTab(_ settings: PadSettings, _ palette: BKMenuPalette) -> some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            PadSoundCaption(text: "SAMPLES FOLDER", color: palette.secondary).padding(.leading, 2)
            if files.isEmpty {
                Text("No sounds in the Samples folder yet. Import or record one on the SOUND tab and it lands here.")
                    .font(.system(size: 13, design: .monospaced)).foregroundColor(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BKRecessedPanel(palette: palette))
            } else {
                ForEach(files, id: \.self) { url in
                    PadSoundRow(icon: "waveform", title: KnockFolders.untagged(url.deletingPathExtension().lastPathComponent), detail: "", palette: palette,
                                checked: settings.sampleFile == url.lastPathComponent) {
                        controller.importSample(url, toPad: pad)
                    }
                }
            }
        }
    }

    // MARK: PAD

    /// Level, pan, tune, decay, filter, reverse, then NOTE REPEAT and its division.
    private func padTab(_ settings: PadSettings, _ palette: BKMenuPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PadSoundCaption(text: "PAD", color: palette.secondary).padding(.leading, 2)
            PadSoundSlider(title: "Level", value: settings.level, range: PadSettings.minLevel...PadSettings.maxLevel,
                           text: PadSettings.levelText(settings.level), palette: palette) { v in
                var s = controller.state.pads[pad]; s.level = v; controller.setPadSettings(pad, s)
            }
            PadSoundSlider(title: "Pan", value: settings.pan, range: -1...1, text: panText(settings.pan), palette: palette) { v in
                var s = controller.state.pads[pad]; s.pan = abs(v) < 0.03 ? 0 : v; controller.setPadSettings(pad, s)
            }
            PadSoundSlider(title: "Tune", value: settings.tune, range: -24...24, text: String(format: "%+.1f st", settings.tune),
                           palette: palette) { v in
                var s = controller.state.pads[pad]; s.tune = (v * 2).rounded() / 2; controller.setPadSettings(pad, s)
            }
            PadSoundSlider(title: "Decay", value: settings.decay, range: 0.05...1,
                           text: settings.decay >= 0.999 ? "FULL" : String(format: "%.0f%%", settings.decay * 100), palette: palette) { v in
                var s = controller.state.pads[pad]; s.decay = v; controller.setPadSettings(pad, s)
            }
            PadSoundSlider(title: "Filter", value: settings.filter, range: 0...1, text: filterText(settings.filter), palette: palette) { v in
                var s = controller.state.pads[pad]; s.filter = v; controller.setPadSettings(pad, s)
            }
            PadControlRow(title: "Reverse", palette: palette) {
                Spacer(minLength: 0)
                PadSwitchKey(isOn: settings.reverse, palette: palette) {
                    var s = controller.state.pads[pad]; s.reverse.toggle(); controller.setPadSettings(pad, s)
                }
                .accessibilityLabel("Reverse")
                .accessibilityValue(settings.reverse ? "On" : "Off")
                .accessibilityIdentifier("padSound.reverse")
            }
            noteRepeatRow(settings, palette)
            Text(controller.padRepeats(pad)
                 ? "NOTE REPEAT is on: holding this pad plays it every \(NoteRepeat.name(settings.repeatDivision)) on the beat. While it's on, open this window from MENU › KITS / FILES › EDIT."
                 : "Save these pads as your own kit from the KITS window (Save Kit As…).")
                .font(.system(size: 12)).foregroundColor(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    /// NOTE REPEAT on / off with its lamp, and the stepped REPEAT DIVISION knob with its readout.
    private func noteRepeatRow(_ settings: PadSettings, _ palette: BKMenuPalette) -> some View {
        let toggle: () -> Void = {
            var s = controller.state.pads[pad]; s.noteRepeat.toggle(); controller.setPadSettings(pad, s)
        }
        let division = NoteRepeat.clamped(settings.repeatDivision)
        return HStack(spacing: 12) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    Text("NOTE REPEAT").font(.system(size: 12, weight: .bold, design: .monospaced)).kerning(0.6)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 14).frame(height: 44)
                }
                .buttonStyle(BKPanelKeyStyle(palette: palette))
                .accessibilityHidden(true)
                PadSwitchKey(isOn: settings.noteRepeat, palette: palette, toggle: toggle)
                    .accessibilityLabel("Note repeat")
                    .accessibilityValue(settings.noteRepeat ? "On" : "Off")
                    .accessibilityIdentifier("padSound.noteRepeat")
            }
            Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1, height: 46)
                .overlay(Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1).offset(x: 1))
            Spacer(minLength: 0)
            Text("REPEAT\nDIVISION").font(.system(size: 11, weight: .semibold, design: .monospaced)).kerning(0.5)
                .foregroundColor(palette.text).multilineTextAlignment(.leading)
                .lineLimit(2).fixedSize()
            PadSteppedKnob(index: division, count: NoteRepeat.count, palette: palette) { i in
                var s = controller.state.pads[pad]; s.repeatDivision = NoteRepeat.clamped(i); controller.setPadSettings(pad, s)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Repeat division")
            .accessibilityValue(NoteRepeat.name(division))
            .accessibilityIdentifier("padSound.repeatDivision")
            .accessibilityAdjustableAction { direction in
                var s = controller.state.pads[pad]
                s.repeatDivision = NoteRepeat.clamped(division + (direction == .increment ? 1 : -1))
                controller.setPadSettings(pad, s)
            }
            PadReadout(text: NoteRepeat.name(division), palette: palette, width: 70)
                .accessibilityIdentifier("padSound.repeatDivision.value")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(BKRecessedPanel(palette: palette))
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
