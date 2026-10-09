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
    @State private var editPad: Int?
    @State private var savingKit = false
    @State private var kitName = ""

    private let accent = Color(red: 1, green: 0.30, blue: 0.20)

    var body: some View {
        NavigationView {
            Form {
                Section {
                    ForEach(0..<Pad.count, id: \.self) { pad in padRow(pad) }
                } header: {
                    Text("Your samples on the pads")
                } footer: {
                    Text("Tap Import to put an audio file (WAV, AIFF, MP3, M4A, FLAC) on a pad. You can also drag a file from Files straight onto a pad, or hold a pad for its editor. Imported files are copied to "
                         + (controller.isPlugin ? "the plug-in's Samples folder." : "Files › On My iPad › BreakBoss › Samples."))
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
                    mapRow("C1 – B1  (36 – 47)", "Pads 1 – 12. In LOOP mode they start loops 1 – 12.")
                    mapRow("C2 – C5  (48 – 84)", "The 808, chromatic. C3 (60) is the kit's tuning.")
                    mapRow("MIDI clock", "TEMPO SYNC follows its tempo, FOLLOW DAW its start / stop.")
                } header: { Text("MIDI") }

                Section("How it works") {
                    guide("ONE-SHOT / LOOP", "ONE-SHOT: the pads play drums. LOOP: the pads play grooves made from the kit; a new pick starts on the next bar, tap the same pad again to stop at the end of the bar.")
                    guide("MODERN / VINTAGE / TEXTURE", "Each mode is its own faceplate and sound. Vintage adds drive and boost. Texture adds a downsampled, unstable sound with a synced delay and gated reverb.")
                    guide("DICE", "LOOP: new grooves in the kit's style. ONE-SHOT: new variations of the kit's sounds.")
                    guide("KNOBS", "Drag up or right to turn up. Double-tap to reset.")
                    guide("BPM", "Drag up or down on the display. Double-tap for the kit's tempo. With TEMPO SYNC on, the DAW or MIDI clock sets it.")
                    guide("HOLD A PAD", "ONE-SHOT: pad editor (level, pan, tune, decay, reverse, your sample). LOOP: step editor for that loop, or drop in a MIDI file.")
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
        .fileImporter(isPresented: Binding(get: { importPad != nil }, set: { if !$0 { importPad = nil } }),
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
        return HStack(spacing: 12) {
            Text("\(pad + 1)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 26)
                .foregroundColor(own ? accent : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.padName(pad).uppercased()).font(.system(.body, design: .monospaced)).lineLimit(1)
                Text(own ? "YOUR SAMPLE" : Pad(rawValue: pad)?.label ?? "")
                    .font(.caption).foregroundColor(own ? accent : .secondary)
            }
            Spacer()
            Button { controller.padDown(pad, velocity: 1) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless)
            Button("Edit") { editPad = pad }.buttonStyle(.borderless)
            Button("Import") { importPad = pad }.buttonStyle(.borderless).foregroundColor(accent)
            if own {
                Button(role: .destructive) { controller.revertPad(pad) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
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
