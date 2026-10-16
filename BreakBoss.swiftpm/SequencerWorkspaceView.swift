// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Same controls and layout across Modern, Platinum, Vintage and Texture.
// Active steps follow the matching instrument pads: red, light yellow, or blue.
private struct RackSkin {
    let background: Color
    let panel: Color
    let alternate: Color
    let unlit: Color
    let stroke: Color
    let ink: Color
    let muted: Color
    let active: Color
    let activeInk: Color

    static func forFace(_ face: String) -> RackSkin {
        switch face {
        case "platinum":
            return RackSkin(background: Color(red: 0.70, green: 0.72, blue: 0.74),
                            panel: Color(red: 0.81, green: 0.83, blue: 0.84),
                            alternate: Color(red: 0.75, green: 0.77, blue: 0.79),
                            unlit: Color(red: 0.59, green: 0.61, blue: 0.63),
                            stroke: Color(white: 0.47), ink: Color(white: 0.13),
                            muted: Color(white: 0.36),
                            active: Color(red: 0.93, green: 0.12, blue: 0.15),
                            activeInk: .white)
        case "vintage":
            return RackSkin(background: Color(red: 0.78, green: 0.75, blue: 0.66),
                            panel: Color(red: 0.94, green: 0.91, blue: 0.82),
                            alternate: Color(red: 0.87, green: 0.84, blue: 0.75),
                            unlit: Color(red: 0.65, green: 0.63, blue: 0.58),
                            stroke: Color(red: 0.54, green: 0.49, blue: 0.41),
                            ink: Color(red: 0.18, green: 0.16, blue: 0.13),
                            muted: Color(red: 0.43, green: 0.39, blue: 0.31),
                            active: Color(red: 1.0, green: 0.92, blue: 0.56),
                            activeInk: Color(red: 0.19, green: 0.15, blue: 0.08))
        case "texture":
            return RackSkin(background: Color(red: 0.045, green: 0.12, blue: 0.23),
                            panel: Color(red: 0.08, green: 0.21, blue: 0.34),
                            alternate: Color(red: 0.10, green: 0.25, blue: 0.39),
                            unlit: Color(red: 0.13, green: 0.31, blue: 0.43),
                            stroke: Color(red: 0.21, green: 0.43, blue: 0.58),
                            ink: Color(red: 0.91, green: 0.96, blue: 1),
                            muted: Color(red: 0.62, green: 0.76, blue: 0.86),
                            active: Color(red: 0.19, green: 0.67, blue: 1),
                            activeInk: Color(white: 0.08))
        default:
            return RackSkin(background: Color(white: 0.075),
                            panel: Color(white: 0.15),
                            alternate: Color(white: 0.19),
                            unlit: Color(white: 0.28),
                            stroke: Color(white: 0.32),
                            ink: Color(white: 0.92), muted: Color(white: 0.62),
                            active: Color(red: 0.94, green: 0.13, blue: 0.14),
                            activeInk: .white)
        }
    }
}

/// Opens from the original faceplate's existing step-sequencer button.
/// The right browser, center rack and left MIDI/generation controls are one workspace.
/// The piano roll is an inline expansion of a rack track, never another screen.
struct SequencerWorkspaceView: View {
    @ObservedObject var controller: KnockController
    let loop: Int
    @Environment(\.dismiss) private var dismiss

    @State private var category: SoundType = .kick
    @State private var search = ""
    @State private var userSounds: [LibrarySound] = UserSoundLibrary.sounds()
    @State private var highlightedDrop = false
    @State private var newborn = Set<UUID>()
    @State private var expanded: UUID?
    @State private var selected: UUID?
    @State private var bar = 0
    @State private var importKind: ImportKind?
    @State private var status = ""

    private enum ImportKind: Identifiable {
        case sounds, pack
        var id: Int { self == .sounds ? 0 : 1 }
    }

    private static let factorySounds = StockSampleLibrary.bundled.librarySounds()
    private var sounds: [LibrarySound] { userSounds + Self.factorySounds }
    private var matched: [LibrarySound] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return sounds.filter { item in
            (item.type == category || !q.isEmpty) &&
            (q.isEmpty || item.name.localizedCaseInsensitiveContains(q) ||
                            item.pack.localizedCaseInsensitiveContains(q) ||
                            item.type.rawValue.localizedCaseInsensitiveContains(q))
        }
    }
    private var skin: RackSkin { RackSkin.forFace(controller.faceKey) }
    private var rows: [WorkspaceChannel] { controller.workspaceChannels }
    private var pattern: PatternData {
        controller.loops.indices.contains(loop)
            ? controller.loops[loop]
            : PatternData(name: "MAIN A", lengthTicks: PatternEdit.barTicks * 2, events: [])
    }
    private var barCount: Int { max(1, pattern.bars) }
    private var currentBar: Int { min(bar, barCount - 1) }
    private var selectedTrack: WorkspaceChannel? {
        if let selected, let track = rows.first(where: { $0.id == selected }) { return track }
        return rows.first
    }

    var body: some View {
        GeometryReader { geo in
            // On iPhone the panels scroll horizontally instead of shrinking the 16 steps
            // into untappable pixels. iPad gets the true simultaneous three-panel layout.
            let narrow = geo.size.width < 920
            let leftWidth: CGFloat = narrow ? 174 : 192
            let rightWidth: CGFloat = narrow ? 254 : 268
            let centerWidth: CGFloat = narrow ? 615 : max(450, geo.size.width - leftWidth - rightWidth - 2)
            ScrollView(.horizontal, showsIndicators: narrow) {
                HStack(spacing: 1) {
                    generationAndMIDI.frame(width: leftWidth)
                    channelRack.frame(width: centerWidth)
                    soundBrowser.frame(width: rightWidth)
                }
                .frame(height: geo.size.height)
                .background(skin.stroke)
            }
            .scrollDisabled(!narrow)
        }
        .background(skin.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            controller.ensureWorkspace(loop: loop)
            controller.setWorkspaceOpen(true)
        }
        .onDisappear { controller.setWorkspaceOpen(false) }
        .fileImporter(
            isPresented: Binding(get: { importKind != nil }, set: { if !$0 { importKind = nil } }),
            allowedContentTypes: importKind == .pack ? [.folder] : [.audio],
            allowsMultipleSelection: importKind == .sounds
        ) { result in
            guard case .success(let urls) = result else { importKind = nil; return }
            let count = importKind == .pack
                ? urls.reduce(0) { $0 + UserSoundLibrary.importPack($1) }
                : UserSoundLibrary.importSounds(urls)
            userSounds = UserSoundLibrary.sounds()
            status = count > 0 ? "Imported \(count) sounds" : "No new audio files"
            importKind = nil
        }
    }

    private var generationAndMIDI: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionHeader("WORKSPACE")
            Button { dismiss() } label: {
                Label("FACEPLATE", systemImage: "arrow.left")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundColor(skin.ink)

            sectionHeader("GENERATION")
            commandButton("GENERATE", icon: "dice.fill") {
                controller.generateWorkspace(loop: loop)
                status = "Generated \(rows.count) channels"
            }
            .disabled(rows.isEmpty)
            commandButton("CLEAR STEPS", icon: "square.dashed") {
                let active = Set(rows.map(\.pad))
                var p = pattern
                p.events.removeAll { active.contains(Int($0.pad)) }
                controller.setLoop(loop, p)
            }
            .disabled(rows.isEmpty)

            sectionHeader("TRANSPORT")
            HStack(spacing: 8) {
                commandButton("PLAY", icon: "play.fill") { controller.playPattern(loop) }
                commandButton("STOP", icon: "stop.fill") { controller.stopPlayback() }
            }
            HStack(spacing: 6) {
                commandButton("−", icon: "minus") { controller.setBPM(controller.liveTempo - 1) }
                Text("\(Int(controller.liveTempo.rounded()))")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(skin.ink)
                    .frame(maxWidth: .infinity)
                commandButton("+", icon: "plus") { controller.setBPM(controller.liveTempo + 1) }
            }
            Text("BPM").font(.system(size: 10, design: .monospaced)).foregroundColor(skin.muted)

            sectionHeader("MIDI / HOST")
            toggleButton("MIDI OUT", on: controller.midiOutOn) {
                controller.setMIDIOut(!controller.midiOutOn)
            }
            toggleButton("MULTI-CHANNEL", on: controller.midiOutChannels == KnockController.defaultMIDIOutChannels) {
                let isMulti = controller.midiOutChannels == KnockController.defaultMIDIOutChannels
                controller.setMIDIOutLayout(multi: !isMulti)
            }
            toggleButton("FOLLOW DAW", on: controller.value(.followDAW) > 0.5) {
                controller.toggle(.followDAW)
            }
            toggleButton("TEMPO SYNC", on: controller.value(.tempoSync) > 0.5) {
                controller.toggle(.tempoSync)
            }
            Spacer(minLength: 0)
            Text("12-CHANNEL ENGINE · AUv3")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(skin.muted)
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(skin.panel)
    }

    private var channelRack: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("CHANNEL RACK")
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundColor(skin.ink)
                Text("\(rows.count)/12")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(skin.muted)
                Spacer(minLength: 4)
                Button { bar = max(0, currentBar - 1) } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentBar == 0)
                Text("BAR \(currentBar + 1)/\(barCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .frame(minWidth: 75)
                Button { bar = min(barCount - 1, currentBar + 1) } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentBar >= barCount - 1)
                Menu {
                    ForEach([2, 4, 8, 16], id: \.self) { length in
                        Button("\(length) BARS") {
                            controller.setLoop(loop, PatternEdit.setLength(pattern, bars: length))
                            bar = min(bar, length - 1)
                        }
                    }
                } label: {
                    Text("\(barCount) BARS").font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 7)
                        .background(skin.alternate, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .foregroundColor(skin.ink)
            .padding(.horizontal, 12).frame(height: 54)
            .background(skin.panel)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    if rows.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up")
                                .font(.system(size: 34, weight: .ultraLight))
                            Text("DROP A SOUND TO CREATE A TRACK")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                            Text("Choose KICKS, CLAPS, SNARES and more from the library on the right. Drag a sound here or tap its + button.")
                                .font(.system(size: 11, design: .monospaced))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(skin.muted)
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }
                    ForEach(rows) { row in
                        rackRow(row)
                    }
                    if rows.count < Pad.count {
                        Text("＋ DROP OR TAP A SOUND TO ADD A TRACK")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(skin.muted)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(skin.alternate.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: .infinity)
            .background(highlightedDrop ? skin.active.opacity(0.10) : skin.background)
            .onDrop(of: [UTType.plainText], isTargeted: $highlightedDrop) { providers in
                guard rows.count < Pad.count, let item = providers.first else { return false }
                _ = item.loadObject(ofClass: NSString.self) { object, _ in
                    guard let id = object as? String else { return }
                    DispatchQueue.main.async {
                        if let sound = sounds.first(where: { $0.id == id }) { add(sound) }
                    }
                }
                return true
            }

            velocityEditor
        }
    }

    private func rackRow(_ row: WorkspaceChannel) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Button {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        expanded = expanded == row.id ? nil : row.id
                        selected = row.id
                    }
                } label: {
                    Image(systemName: expanded == row.id ? "chevron.down" : "chevron.right")
                        .frame(width: 21, height: 34)
                }
                Button {
                    selected = row.id
                    controller.auditionPad(row.pad)
                } label: {
                    ZStack {
                        Capsule()
                            .fill(selected == row.id ? skin.active.opacity(0.28) : skin.alternate)
                            .overlay(Capsule().stroke(skin.stroke, lineWidth: 1))
                        if !newborn.contains(row.id) {
                            VStack(spacing: 1) {
                                Text(row.name)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .lineLimit(1)
                                Text(row.category)
                                    .font(.system(size: 8, design: .monospaced))
                                    .lineLimit(1)
                                    .foregroundColor(skin.muted)
                            }.padding(.horizontal, 5)
                        }
                    }
                    .frame(width: newborn.contains(row.id) ? 34 : 150, height: 34)
                    .frame(width: 150, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.name), audition channel")

                ForEach(0..<16, id: \.self) { step in
                    let isOn = hasNote(row.pad, step: step)
                    Button {
                        selected = row.id
                        controller.toggleWorkspaceStep(loop: loop, pad: row.pad, step: step, bar: currentBar)
                        if !isOn { controller.auditionPad(row.pad) }
                    } label: {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isOn ? skin.active : (step / 4) % 2 == 0 ? skin.unlit : skin.alternate)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(isOn ? skin.active.opacity(0.55) : skin.stroke.opacity(0.8), lineWidth: 0.8))
                            .shadow(color: isOn ? skin.active.opacity(0.30) : .black.opacity(0.13),
                                    radius: isOn ? 3 : 1, y: 2)
                            .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(row.name), step \(step + 1), \(isOn ? "on" : "off")")
                }
                Button { controller.toggleMute(row.pad) } label: {
                    Text("M").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(controller.mutedPads[row.pad] ? skin.active : skin.muted)
                        .frame(width: 21, height: 30)
                }
                Button { controller.toggleSolo(row.pad) } label: {
                    Text("S").font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(controller.soloPads[row.pad] ? skin.active : skin.muted)
                        .frame(width: 21, height: 30)
                }
                Button {
                    controller.removeWorkspaceChannel(row.id, loop: loop)
                    if expanded == row.id { expanded = nil }
                    if selected == row.id { selected = nil }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundColor(skin.muted).frame(width: 20, height: 30)
                }
            }
            .foregroundColor(skin.ink)
            .padding(5)
            .frame(height: 46)
            .background(skin.panel, in: RoundedRectangle(cornerRadius: 8))

            if expanded == row.id {
                channelControls(row)
                pianoRoll(row)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// Each channel has its own sample settings, independent of its sound category.
    private func channelControls(_ row: WorkspaceChannel) -> some View {
        let settings = controller.state.pads[row.pad]
        return VStack(spacing: 7) {
            HStack(spacing: 10) {
                Text("LEVEL").frame(width: 48, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(controller.state.pads[row.pad].level) },
                    set: { value in updatePad(row.pad) { $0.level = Float(value) } }
                ), in: 0...1)
                Text("\(Int(settings.level * 100))%").frame(width: 34)
                Text("PAN").frame(width: 26)
                Slider(value: Binding(
                    get: { Double(controller.state.pads[row.pad].pan) },
                    set: { value in updatePad(row.pad) { $0.pan = Float(value) } }
                ), in: -1...1)
            }
            HStack(spacing: 10) {
                Text("TUNE").frame(width: 48, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(controller.state.pads[row.pad].tune) },
                    set: { value in updatePad(row.pad) { $0.tune = Float(value) } }
                ), in: -24...24, step: 1)
                Text("\(Int(settings.tune)) ST").frame(width: 55)
                Text("DECAY").frame(width: 42)
                Slider(value: Binding(
                    get: { Double(controller.state.pads[row.pad].decay) },
                    set: { value in updatePad(row.pad) { $0.decay = Float(value) } }
                ), in: 0.05...1)
            }
        }
        .tint(skin.active)
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(skin.ink)
        .padding(9)
        .background(skin.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private func updatePad(_ pad: Int, _ edit: (inout PadSettings) -> Void) {
        var settings = controller.state.pads[pad]
        edit(&settings)
        controller.setPadSettings(pad, settings)
    }

    /// One octave inline, with individual pitched events on the same pattern timeline.
    /// All 12 drum slots can be tuned; 808 slots retain the engine's chromatic behavior.
    private func pianoRoll(_ row: WorkspaceChannel) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("PIANO ROLL · \(row.name)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
                Text("C4 – B4 · 1/16 SNAP")
                    .font(.system(size: 9, design: .monospaced))
            }
            ForEach((0..<12).reversed(), id: \.self) { pitch in
                HStack(spacing: 4) {
                    Text(MusicScale.noteNames[pitch])
                        .font(.system(size: 9, design: .monospaced))
                        .frame(width: 41, alignment: .trailing)
                    ForEach(0..<16, id: \.self) { step in
                        let on = hasNote(row.pad, step: step, pitch: pitch)
                        Button {
                            selected = row.id
                            controller.toggleWorkspacePianoNote(loop: loop, pad: row.pad,
                                                               step: step, bar: currentBar, semitones: pitch)
                            if !on { controller.auditionPad(row.pad, semis: Float(pitch)) }
                        } label: {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(on ? skin.active : (step / 4) % 2 == 0 ? skin.unlit : skin.alternate)
                                .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .foregroundColor(skin.ink)
        .padding(8)
        .background(skin.panel, in: RoundedRectangle(cornerRadius: 8))
    }

    private var velocityEditor: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("VELOCITY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(selectedTrack?.name ?? "SELECT A CHANNEL")
                    .font(.system(size: 9, design: .monospaced)).lineLimit(1)
                Spacer()
            }
            HStack(spacing: 5) {
                Text("VEL").font(.system(size: 9, design: .monospaced)).frame(width: 150, alignment: .trailing)
                ForEach(0..<16, id: \.self) { step in
                    let events = selectedTrack.map { notesFor($0.pad, step: step) } ?? []
                    let vel = events.first?.velocity ?? 0
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2).fill(skin.unlit.opacity(0.50))
                            if vel > 0 {
                                RoundedRectangle(cornerRadius: 2).fill(skin.active)
                                    .frame(height: max(3, geo.size.height * CGFloat(vel)))
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { touch in
                                guard let selectedTrack else { return }
                                setVelocity(pad: selectedTrack.pad, step: step,
                                            value: Float(1 - touch.location.y / max(1, geo.size.height)).clamped(0.05, 1))
                            })
                    }
                    .frame(maxWidth: .infinity)
                }
                Color.clear.frame(width: 65)
            }
            .frame(height: 55)
        }
        .foregroundColor(skin.ink)
        .padding(12)
        .background(skin.panel)
    }

    private var soundBrowser: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SOUND LIBRARY")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                Spacer()
                Text("\(sounds.count)")
                    .font(.system(size: 10, design: .monospaced)).foregroundColor(skin.muted)
            }
            .foregroundColor(skin.ink)
            .padding(12).background(skin.alternate)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(skin.muted)
                TextField("Search sounds / packs", text: $search)
                    .font(.system(size: 12))
                    .tint(skin.active)
                    .foregroundColor(skin.ink)
                    .autocorrectionDisabled()
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundColor(skin.muted)
                }
            }
            .padding(9)
            .background(skin.alternate, in: RoundedRectangle(cornerRadius: 6))
            .padding(9)

            HStack(spacing: 8) {
                Button { moveCategory(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(category.rawValue)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                Spacer()
                Button { moveCategory(1) } label: { Image(systemName: "chevron.right") }
            }
            .foregroundColor(skin.ink)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(skin.alternate)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if abs(value.translation.width) > abs(value.translation.height) {
                    moveCategory(value.translation.width < 0 ? 1 : -1)
                }
            })

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SoundType.allCases) { item in
                        Button { category = item; search = "" } label: {
                            Text(item.rawValue)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(category == item ? skin.activeInk : skin.ink)
                                .padding(.horizontal, 8).padding(.vertical, 8)
                                .background(category == item ? skin.active : skin.alternate,
                                            in: Capsule())
                        }
                    }
                }.padding(8)
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(matched) { sound in
                        soundRow(sound)
                    }
                    if matched.isEmpty {
                        Text("No sounds found")
                            .foregroundColor(skin.muted).padding(20)
                    }
                }
                .padding(.horizontal, 7)
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                commandButton("IMPORT", icon: "plus") { importKind = .sounds }
                commandButton("PACK", icon: "folder") { importKind = .pack }
            }.padding(8)
            if !status.isEmpty {
                Text(status).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(skin.muted).lineLimit(1).padding(.bottom, 6)
            }
        }
        .background(skin.panel)
    }

    private func soundRow(_ sound: LibrarySound) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.system(size: 12))
                .foregroundColor(skin.muted)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(sound.name).font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(sound.pack).font(.system(size: 9, design: .monospaced))
                    .foregroundColor(skin.muted).lineLimit(1)
            }
            Spacer(minLength: 2)
            Button { add(sound) } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 20))
                    .foregroundColor(skin.active)
            }
            .disabled(rows.count >= Pad.count)
        }
        .foregroundColor(skin.ink)
        .padding(.horizontal, 7).frame(height: 47)
        .background(skin.alternate, in: RoundedRectangle(cornerRadius: 6))
        .onDrag { NSItemProvider(object: sound.id as NSString) }
    }

    private func add(_ sound: LibrarySound) {
        guard let row = controller.addWorkspaceChannel(sound, loop: loop) else {
            status = "Maximum of 12 tracks"
            return
        }
        selected = row.id
        newborn.insert(row.id)
        // A dropped track header physically grows from a circle to an oval.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) {
                newborn.remove(row.id)
            }
        }
        status = "Loaded \(sound.name)"
    }

    private func moveCategory(_ offset: Int) {
        let types = SoundType.allCases
        guard let index = types.firstIndex(of: category) else { return }
        category = types[(index + offset + types.count) % types.count]
        search = ""
    }

    private func hasNote(_ pad: Int, step: Int, pitch: Int? = nil) -> Bool {
        !notesFor(pad, step: step).filter { event in
            pitch == nil || Int(event.semis.rounded()) == pitch
        }.isEmpty
    }

    private func notesFor(_ pad: Int, step: Int) -> [GrooveEvent] {
        let tick = (Int32(currentBar) * 16 + Int32(step)) * PatternData.stepTicks
        return pattern.events.filter { Int($0.pad) == pad && $0.tick == tick }
    }

    private func setVelocity(pad: Int, step: Int, value: Float) {
        let tick = (Int32(currentBar) * 16 + Int32(step)) * PatternData.stepTicks
        var data = pattern
        var changed = false
        for i in data.events.indices where Int(data.events[i].pad) == pad && data.events[i].tick == tick {
            data.events[i].velocity = value
            changed = true
        }
        if changed { controller.setLoop(loop, data) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundColor(skin.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 3)
            .overlay(Rectangle().fill(skin.stroke).frame(height: 1), alignment: .bottom)
    }

    private func commandButton(_ label: String, icon: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(skin.ink)
            .frame(maxWidth: .infinity, minHeight: 35)
            .background(skin.alternate, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(skin.stroke, lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func toggleButton(_ label: String, on: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                Spacer()
                Circle()
                    .fill(on ? skin.active : skin.unlit)
                    .frame(width: 9, height: 9)
            }
            .foregroundColor(skin.ink)
            .padding(8)
            .background(skin.alternate, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
