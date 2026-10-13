// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The menu button (top right, next to export)
//
// Your samples on all 12 pads in one place, saving kits, the MIDI note map and a short guide.

struct MenuView: View {
    @ObservedObject var controller: KnockController
    @Environment(\.dismiss) private var dismiss
    @State private var importPad: Int?
    @State private var showingSampleImporter = false
    @State private var editPad: Int?
    @State private var savingKit = false
    @State private var kitName = ""
    @State private var performance = false
    @State private var portable = false
    @State private var engineControls = false
    @State private var learningPad: Int?
    @State private var learnBase: Int32 = 0
    private let learnTicker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private let accent = Color(red: 1, green: 0.30, blue: 0.20)

    var body: some View {
        NavigationView {
            Form {
                Section("Performance") {
                    Button("Open the 12 performance pads") { performance = true }
                    Button("Engine controls") { engineControls = true }
                    Button("Share / import a complete preset") { portable = true }
                    Button("All notes and loops off") { controller.panic() }
                }
                Section {
                    ForEach(0..<Pad.count, id: \.self) { pad in padRow(pad) }
                } header: {
                    Text("Your samples on the pads")
                } footer: {
                    Text("Tap Import to put an audio file (WAV, AIFF, MP3, M4A, FLAC) on a pad. You can also drag a file from Files straight onto a pad, or hold a pad for its editor. Imported files are copied to "
                         + (controller.isPlugin ? "the plug-in's Samples folder." : "Files › BreakBoss › Samples on this device."))
                }

                Section("Kits") {
                    Button { kitName = controller.state.userKit ?? ""; savingKit = true } label: {
                        Label("Save these pads as a kit…", systemImage: "square.and.arrow.down")
                    }
                    if !controller.userKits.isEmpty {
                        ForEach(controller.userKits, id: \.self) { name in
                            HStack {
                                Button(name) { controller.selectUserKit(name); dismiss() }
                                Spacer()
                                Button(role: .destructive) { controller.deleteUserKit(name) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section {
                    Picker("Pad notes", selection: Binding(get: { controller.midiMap }, set: { controller.setMIDIMap($0) })) {
                        ForEach(MIDIPadMap.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    ForEach(0..<Pad.count, id: \.self) { pad in learnRow(pad) }
                } header: {
                    Text("MIDI controller (MPC and other pad controllers)")
                } footer: {
                    Text("On an MPC, pick the same pad note setting on the MPC (Classic MPC or Chromatic C1), or tap Learn next to a pad here and hit the MPC pad you want for it. MPC pads A01–A12 line up with pads 1–12, bottom-left first. This only changes live playing; MIDI files and MIDI export keep notes 36–47.")
                }

                Section {
                    mapRow("36 – 47", "Pads 1 – 12, in order (with the standard pad notes above). ONE-SHOT plays a full strike regardless of note length. LOOP plays a rhythm while the key is held; release stops it. Last-held note takes priority.")
                    mapRow("48 – 84", "The 808, chromatic. Note 60 is the kit's tuning. Note numbers stay the same when a DAW uses different octave names.")
                    mapRow("MIDI clock", "TEMPO SYNC follows its tempo, FOLLOW DAW its start / stop.")
                } header: { Text("MIDI") }

                Section("How it works") {
                    guide("ONE-SHOT / LOOP", "ONE-SHOT: the pads play drums. LOOP: the pads play grooves made from the kit; a new pick starts on the next bar, tap the same pad again to stop at the end of the bar.")
                    guide("MODERN / VINTAGE / TEXTURE", "Modern is clean and punchy. Vintage is home to soul, boom bap and break grooves, with tape drive, low-end warmth and a rolled-off top. Texture adds resampling, instability, synced delay and gated reverb. You can play any kit or imported acoustic sample in every mode.")
                    guide("KITS / PRESETS", "KITS change the drum sounds only; the pattern keeps playing. PRESETS change the pattern only (groove, variation and tempo); the sounds and knobs stay. Mix any pattern with any kit. SAVE stores everything as your own preset.")
                    guide("DICE", "LOOP: new grooves in the kit's style. ONE-SHOT: new variations of the kit's sounds.")
                    guide("KNOBS", "Drag up or right to turn up. Double-tap to reset.")
                    guide("BPM", "Drag up or down on the display. Double-tap for the kit's tempo. With TEMPO SYNC on, the DAW or MIDI clock sets it.")
                    guide("HOLD A PAD", "ONE-SHOT: pad editor (level, pan, tune, decay, filter, reverse, your sample). LOOP: step editor for that loop, or drop in a MIDI file.")
                    guide("DRUM ROLL", "The piano-keys button opens the drum roll for the pattern that's playing. DRAW: tap to add, tap a note to delete, drag a note to move, drag along a row to paint, drag on the 808 row for a long note. SELECT: box notes, then move, DUPLICATE or CLEAR. ERASE: wipe over notes. The lane underneath sets velocity or pitch. Tap a channel name to load or record a sample onto it, or open its piano roll. M / S mute and solo. RECORD writes what you play on the ▶ buttons or a MIDI controller into the pattern. Space bar plays and stops.")
                    guide("EXPORT", "The arrow button renders MIDI, a stereo mix and stems you can drag into a DAW or share.")
                }

                Section {
                    HStack {
                        Text("BreakBoss")
                        Spacer()
                        Text(versionText).foregroundColor(.secondary).font(.system(.body, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $performance) { PerformanceView(controller: controller) }
        .sheet(isPresented: $portable) { PortablePresetView(controller: controller) }
        .sheet(isPresented: $engineControls) { EngineControlsView(controller: controller) }
        .fileImporter(isPresented: $showingSampleImporter,
                      allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first, let pad = importPad {
                controller.importSample(url, toPad: pad)
            }
            importPad = nil
        }
        .sheet(item: Binding(get: { editPad.map { PadID(id: $0) } }, set: { editPad = $0?.id })) { p in
            PadEditorView(controller: controller, pad: p.id)
        }
        .alert("Save Kit", isPresented: $savingKit) {
            TextField("Name", text: $kitName)
            Button("Save") { controller.saveKit(as: kitName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the 12 pads (your samples and pad settings) as a kit.")
        }
    }

    private struct PadID: Identifiable { let id: Int }

    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    private func padRow(_ pad: Int) -> some View {
        let own = controller.state.pads[pad].sampleFile != nil
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                padDescription(pad, own: own).frame(minWidth: 140)
                Spacer(minLength: 8)
                padActions(pad, own: own).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 4) {
                padDescription(pad, own: own)
                padActions(pad, own: own).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { controller.importSample(url, toPad: pad) } }
            }
            return true
        }
    }

    private func padDescription(_ pad: Int, own: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(pad + 1)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 26)
                .foregroundColor(own ? accent : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.padName(pad).uppercased()).font(.system(.body, design: .monospaced)).lineLimit(1)
                Text(own ? "YOUR SAMPLE" : Pad(rawValue: pad)?.label ?? "")
                    .font(.caption).foregroundColor(own ? accent : .secondary)
            }
        }
    }

    private func padActions(_ pad: Int, own: Bool) -> some View {
        HStack(spacing: 12) {
            Button { controller.padDown(pad, velocity: 1) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Play pad \(pad + 1)")
                .frame(minWidth: 44, minHeight: 44)
            Button("Edit") { editPad = pad }.buttonStyle(.borderless)
                .frame(minHeight: 44)
            Button("Import") { importPad = pad; showingSampleImporter = true }.buttonStyle(.borderless).foregroundColor(accent)
                .frame(minHeight: 44)
            if own {
                Button(role: .destructive) { controller.revertPad(pad) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Restore kit sound on pad \(pad + 1)")
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
    }

    private func learnRow(_ pad: Int) -> some View {
        let note = controller.midiPadNotes[pad]
        let learning = learningPad == pad
        return HStack {
            Text("Pad \(pad + 1)").font(.system(.body, design: .monospaced)).frame(width: 64, alignment: .leading)
            Text(controller.padName(pad).uppercased()).font(.caption).foregroundColor(.secondary).lineLimit(1)
            Spacer()
            Text(learning ? "HIT A PAD…" : note >= 0 ? "NOTE \(note)" : "—")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(learning ? accent : .primary)
            Button(learning ? "Cancel" : "Learn") {
                if learning { learningPad = nil } else {
                    learnBase = controller.lastMIDINoteOn.count
                    learningPad = pad
                }
            }
            .buttonStyle(.bordered)
        }
        .onReceive(learnTicker) { _ in
            guard learningPad == pad else { return }
            let last = controller.lastMIDINoteOn
            if last.count != learnBase {
                controller.learnMIDINote(pad: pad, note: last.note)
                learningPad = nil
            }
        }
    }

    private func mapRow(_ left: String, _ right: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(left).font(.system(.body, design: .monospaced))
            Text(right).font(.footnote).foregroundColor(.secondary)
        }
    }

    private func guide(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(.subheadline, design: .monospaced)).foregroundColor(accent)
            Text(text).font(.footnote)
        }
        .padding(.vertical, 2)
    }
}
