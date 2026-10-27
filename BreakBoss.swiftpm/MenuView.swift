// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - The menu button (top right, next to export)
//
// The BreaKing CONTROL PANEL (Tyrone's "both popup windows" kit, Oct 26): a hardware window drawn
// over the faceplate or the sequencer (never a sheet, so the instrument keeps playing underneath),
// six section keys down the left (GENERAL, RECORD, MIDI / SYNC, KITS / FILES, PERFORMANCE, HELP),
// ENGINE CONTROLS, COMPLETE PRESET and BUG REPORT opening inside it with a BACK key, and ALL NOTES
// & LOOPS OFF always in the bottom rail. The look is BKHardware.swift's, shared with the SAMPLER.

struct MenuView: View {
    @ObservedObject var controller: KnockController
    let close: () -> Void

    private enum MenuSection: String, CaseIterable, Identifiable {
        case general, record, midi, files, performance, help
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "GENERAL"
            case .record: return "RECORD"
            case .midi: return "MIDI / SYNC"
            case .files: return "KITS / FILES"
            case .performance: return "PERFORMANCE"
            case .help: return "HELP"
            }
        }
        var symbol: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .record: return "record.circle"
            case .midi: return "pianokeys"
            case .files: return "folder"
            case .performance: return "square.grid.3x3"
            case .help: return "questionmark.circle"
            }
        }
    }

    private enum Subpage { case engine, transfer, report, materials }
    private enum ImportKind { case sample(Int), preset }
    private struct PadID: Identifiable { let id: Int }
    private struct SharedFile: Identifiable { let id = UUID(); let url: URL }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section: MenuSection = .general
    @State private var subpage: Subpage?
    @State private var importKind: ImportKind?
    @State private var showingImporter = false
    @State private var editPad: Int?
    @State private var kitName = ""
    @State private var performance = false
    @State private var sharing: SharedFile?
    @State private var expandedGuide: String?
    @State private var learningPad: Int?
    @State private var learnBase: Int32 = 0
    /// LEARN ALL 12: after each pad learns its note, the next pad starts learning (pad 1 to 12).
    @State private var learnAll = false
    // COMPLETE PRESET (the .bbpack file)
    @State private var presetWorking = false
    @State private var presetURL: URL?
    @State private var presetError: String?
    // BUG REPORT
    @State private var what = ""
    @State private var preview = ""
    @State private var copied = false
    private let learnTicker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var finish: String { controller.faceKey }
    private var palette: BKMenuPalette { BKMenuPalette.of(finish) }

    var body: some View {
        GeometryReader { geo in
            // maximums, not a screen size: the app's or the host's space wins
            let width = max(0, min(1000, geo.size.width - 24))
            let height = max(0, min(744, geo.size.height - 24))
            let compact = width < 720 || dynamicTypeSize.isAccessibilitySize
            ZStack {
                Color.black.opacity(0.38)
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)
                window(compact: compact).frame(width: width, height: height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.seqFinish, finish)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismiss() }
        .accessibilityIdentifier("bkControlPanel")
        .onReceive(learnTicker) { _ in pollLearn() }
        .fullScreenCover(isPresented: $performance) { PerformanceView(controller: controller) }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: importTypes, allowsMultipleSelection: false) { result in
            imported(result)
        }
        .sheet(item: Binding(get: { editPad.map { PadID(id: $0) } }, set: { editPad = $0?.id })) { p in
            PadEditorView(controller: controller, pad: p.id)
        }
        .sheet(item: $sharing) { shared in ShareSheet(items: [shared.url]) }
    }

    // MARK: The window

    private func window(compact: Bool) -> some View {
        VStack(spacing: 0) {
            header
            divider
            if compact {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MenuSection.allCases) { item in sectionKey(item, compact: true) }
                    }
                    .padding(12)
                }
                .fixedSize(horizontal: false, vertical: true)
                divider
                detail(compact: true)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 9) {
                            ForEach(MenuSection.allCases) { item in sectionKey(item, compact: false) }
                        }
                        .padding(14)
                    }
                    .frame(width: 200)
                    Rectangle().fill(palette.edge).frame(width: 1)
                    detail(compact: false)
                }
            }
            divider
            footer(compact: compact)
        }
        .background(BKMenuMetal(palette: palette))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(BKCornerScrews())
        .shadow(color: .black.opacity(0.72), radius: 22, x: 0, y: 16)
    }

    /// BreaKing with its K in the mode's light, as on the SAMPLER.
    private var brand: Text {
        let a: Text = Text("Brea").foregroundColor(palette.text)
        let k: Text = Text("K").foregroundColor(palette.accent)
        let b: Text = Text("ing").foregroundColor(palette.text)
        return a + k + b
    }

    private var header: some View {
        HStack(spacing: 12) {
            brand.font(.system(size: 24, weight: .bold).width(.expanded))
                .shadow(color: .black.opacity(0.4), radius: 0, y: 1)
            Text("CONTROL PANEL")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .tracking(1.1)
                .foregroundColor(palette.secondary)
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.headline).foregroundColor(palette.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(BKHardwareButtonStyle(accent: palette.accent))
            .accessibilityLabel("Close the BreaKing menu")
            .accessibilityIdentifier("menuClose")
            .keyboardShortcut(.cancelAction)
        }
        .foregroundColor(palette.text)
        .padding(.horizontal, 22).padding(.vertical, 12)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var divider: some View {
        Rectangle().fill(palette.edge).frame(height: 1)
            .overlay(Rectangle().fill(Color.black.opacity(0.8)).frame(height: 1).offset(y: 1), alignment: .bottom)
            .accessibilityHidden(true)
    }

    private func sectionKey(_ item: MenuSection, compact: Bool) -> some View {
        let selected = section == item
        return Button {
            section = item
            subpage = nil
        } label: {
            HStack(spacing: 9) {
                BKMenuLED(isOn: selected, accent: palette.accent)
                if !compact { Image(systemName: item.symbol).frame(width: 18).accessibilityHidden(true) }
                Text(item.title).font(.system(.caption, design: .monospaced).weight(.bold)).tracking(0.6)
                if !compact { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 12).frame(minHeight: 48)
        }
        .buttonStyle(BKHardwareButtonStyle(accent: palette.accent, selected: selected))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("menuSection_" + item.rawValue)
    }

    private var pageTitle: String {
        switch subpage {
        case .some(.engine): return "ENGINE CONTROLS"
        case .some(.transfer): return "COMPLETE PRESET"
        case .some(.report): return "BUG REPORT"
        case .some(.materials): return "MATERIAL TEST"
        case .none: return section.title
        }
    }

    @ViewBuilder
    private func detail(compact: Bool) -> some View {
        // MATERIAL TEST sits outside the scroll view: a scroll view holds touches back to see if they
        // scroll, and the pad there has to play the instant a finger lands, like Face 1's
        if subpage == .materials {
            detailContent(compact: compact).frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { detailContent(compact: compact) }
        }
    }

    private func detailContent(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if subpage != nil {
                Button { subpage = nil } label: {
                    Label("BACK TO \(section.title)", systemImage: "chevron.left")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .padding(.horizontal, 12).frame(minHeight: 44)
                }
                .buttonStyle(BKHardwareButtonStyle(accent: palette.accent))
            }
            Text(pageTitle)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .tracking(1.1)
                .foregroundColor(palette.text)
                .accessibilityAddTraits(.isHeader)
            page
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 14 : 20)
        .id(section.rawValue + ":" + pageTitle)
    }

    private var page: AnyView {
        if let subpage {
            switch subpage {
            case .engine: return enginePage.erased()
            case .transfer: return transferPage.erased()
            case .report: return reportPage.erased()
            case .materials: return MaterialTestView(controller: controller, palette: palette).erased()
            }
        }
        switch section {
        case .general: return generalPage.erased()
        case .record: return recordPage.erased()
        case .midi: return midiPage.erased()
        case .files: return filesPage.erased()
        case .performance: return performancePage.erased()
        case .help: return helpPage.erased()
        }
    }

    private func footer(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Button { controller.panic() } label: {
                HStack(spacing: 9) {
                    BKMenuLED(isOn: false, accent: palette.accent)
                    Text("ALL NOTES & LOOPS OFF").font(.system(.caption, design: .monospaced).weight(.bold))
                }
                .padding(.horizontal, 12).frame(minHeight: 44)
            }
            .buttonStyle(BKHardwareButtonStyle(accent: palette.accent))
            .accessibilityHint("Stops every sounding note and loop")
            .accessibilityIdentifier("menuPanic")
            Spacer(minLength: 0)
            if !compact {
                Text("BreaKing " + versionText)
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(1.2).foregroundColor(palette.secondary)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: GENERAL

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("MODERN FACEPLATE") {
                LazyVGrid(columns: optionColumns, spacing: 8) {
                    ForEach([false, true], id: \.self) { plat in
                        option(plat ? "PLATINUM" : "MODERN (BLACK)", selected: controller.platinumFace == plat) {
                            controller.setPlatinumFace(plat)
                            if controller.mode != .modern { controller.selectMode(.modern) }
                        }
                    }
                }
                caption("Platinum is Modern's alternate face: same sound and controls, brushed-silver plate. Free while we test.")
            }
            group("TUTORIAL") {
                action("PLAY THE TUTORIAL", subtitle: "Every feature, step by step: the modes, the pads, recording live into your DAW, the sequencer, the dice and the FX. SKIP ends it at any step.",
                       symbol: "graduationcap", id: "menuTutorial", perform: playTutorial)
            }
            group("QUICK ACCESS") {
                action("12 PERFORMANCE PADS", symbol: "square.grid.3x3") { performance = true }
                action("ENGINE CONTROLS", symbol: "slider.horizontal.3") { subpage = .engine }
            }
        }
    }

    // MARK: RECORD

    private var recordPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("COUNT-IN") {
                LazyVGrid(columns: optionColumns, spacing: 8) {
                    ForEach([1, 2], id: \.self) { bars in
                        option(bars == 1 ? "1 BAR" : "\(bars) BARS", selected: controller.countInBars == bars) {
                            controller.setCountInBars(bars)
                        }
                    }
                }
            }
            group("METRONOME") {
                BKMenuSwitch(title: "METRONOME WHILE PLAYING", isOn: controller.metronome, accent: palette.accent) {
                    controller.setMetronome(!controller.metronome)
                }
            }
            caption("The RECORD button (top right) counts in with the metronome, then the pattern plays and every pad you hit lands in it on that pad's own channel. Open the sequencer to see and edit the notes in each pad's piano roll.")
        }
    }

    // MARK: MIDI / SYNC

    private var midiPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("MIDI CONTROLLER (MPC AND OTHER PAD CONTROLLERS)") {
                ForEach(MIDIPadMap.allCases, id: \.self) { map in
                    option(map.title.uppercased(), selected: controller.midiMap == map) { controller.setMIDIMap(map) }
                }
                action(learnAll ? "CANCEL LEARNING" : "LEARN ALL 12 PADS", symbol: learnAll ? "xmark" : "pianokeys", id: "menuLearnAll") {
                    if learnAll {
                        learnAll = false; learningPad = nil
                    } else {
                        learnBase = controller.lastMIDINoteOn.count
                        learnAll = true
                        learningPad = 0
                    }
                }
                if learnAll, let pad = learningPad {
                    HStack(spacing: 10) {
                        BKMenuLED(isOn: true, accent: palette.accent)
                        Text(pad < 8 ? "Hit the controller pad for pad \(pad + 1). On an 8-pad controller, bank A pads 1–8 are pads 1–8."
                                     : "Hit the controller pad for pad \(pad + 1). On an 8-pad controller, switch to bank B: its pads 1–4 are pads 9–12.")
                            .font(.footnote).foregroundColor(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(0..<Pad.count, id: \.self) { pad in learnRow(pad) }
                caption("On an MPC, pick the same pad note setting on the MPC (Classic MPC or Chromatic C1), or tap Learn next to a pad here and hit the MPC pad you want for it. MPC pads A01–A12 line up with pads 1–12, bottom-left first. This only changes live playing; MIDI files and MIDI export keep notes 36–47.")
            }
            group("MIDI") {
                noteRow("36 – 47", "Pads 1 – 12, in order (with the standard pad notes above). ONE-SHOT plays a full strike regardless of note length. LOOP plays a rhythm while the key is held; release stops it. Last-held note takes priority.")
                noteRow("48 – 84", "The 808, chromatic. Note 60 is the kit's tuning. Note numbers stay the same when a DAW uses different octave names.")
                noteRow("MIDI clock", "TEMPO SYNC follows its tempo, FOLLOW DAW its start / stop.")
            }
            group("SYNC") {
                BKMenuSwitch(title: "TEMPO SYNC", subtitle: "The DAW or MIDI clock sets the tempo.",
                             isOn: controller.value(.tempoSync) > 0.5, accent: palette.accent) { controller.toggle(.tempoSync) }
                BKMenuSwitch(title: "FOLLOW DAW", subtitle: "The DAW or MIDI clock starts and stops the pattern.",
                             isOn: controller.value(.followDAW) > 0.5, accent: palette.accent) { controller.toggle(.followDAW) }
            }
            group("MIDI OUT") {
                BKMenuSwitch(title: "MIDI OUT TO YOUR DAW",
                             subtitle: controller.isPlugin ? "Sent from the plug-in's MIDI output" : "Sent on the \"BreaKing Out\" MIDI port",
                             isOn: controller.midiOutOn, accent: palette.accent) { controller.setMIDIOut(!controller.midiOutOn) }
                option("ONE TRACK · EVERY PAD ON MIDI CHANNEL 1, PADS 1–12 ON NOTES 36–47", selected: outLayout == 3) {
                    controller.setMIDIOutOneTrack()
                }
                option("MULTI-OUT · EACH PAD ON ITS OWN MIDI CHANNEL (1–12), NOTES C1 UP", selected: outLayout == 1) {
                    controller.setMIDIOutLayout(multi: true)
                }
                option("ONE CHANNEL · EVERY PAD ON MIDI CHANNEL 10 (GENERAL MIDI DRUMS)", selected: outLayout == 2) {
                    controller.setMIDIOutLayout(multi: false)
                }
                caption("Everything you play on the pads and every note the patterns and drum roll play goes out as MIDI. In your DAW, record BreaKing's MIDI output onto a track and the notes land in its piano roll, ready to edit. The 808 sends the note it plays. Pick each channel's MIDI channel and note in the drum roll (tap a channel name). ONE TRACK puts the whole kit on one track: a note drawn on row 36–47 plays that pad. When the DAW track plays the notes back, turn FOLLOW DAW off so the pattern doesn't play on top of them.")
            }
        }
    }

    /// Which quick MIDI-out setup is in use: 1 multi-out, 2 one channel, 3 one track, 0 your own per-channel picks.
    private var outLayout: Int {
        let ch = controller.midiOutChannels
        if ch == KnockController.oneTrackMIDIOutChannels && controller.midiOutNotes == KnockController.defaultMIDIOutNotes { return 3 }
        if ch == KnockController.defaultMIDIOutChannels && controller.midiOutNotes == KnockController.defaultMIDIOutNotes { return 1 }
        let drums = ch.enumerated().allSatisfy { i, c in i == Pad.bass808.rawValue || c == 9 }
        return drums ? 2 : 0
    }

    private func learnRow(_ pad: Int) -> some View {
        let note = controller.midiPadNotes[pad]
        let learning = learningPad == pad
        return HStack(spacing: 10) {
            Text("PAD \(pad + 1)").font(.system(.caption, design: .monospaced).weight(.bold)).frame(width: 58, alignment: .leading)
            Text(controller.padName(pad).uppercased()).font(.caption).lineLimit(1)
                .foregroundColor(BKMenuPalette.wellText.opacity(0.8))
            Spacer(minLength: 6)
            Text(learning ? "HIT A PAD…" : note >= 0 ? "NOTE \(note)" : "—")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(learning ? palette.accent : BKMenuPalette.wellText)
            Button {
                learnAll = false
                if learning { learningPad = nil } else {
                    learnBase = controller.lastMIDINoteOn.count
                    learningPad = pad
                }
            } label: {
                HStack(spacing: 7) {
                    BKMenuLED(isOn: learning, accent: palette.accent)
                    Text(learning ? "CANCEL" : "LEARN").font(.system(.caption, design: .monospaced).weight(.bold))
                }
                .padding(.horizontal, 10).frame(minHeight: 44)
            }
            .buttonStyle(BKHardwareButtonStyle(accent: palette.accent, selected: learning))
            .accessibilityLabel(learning ? "Cancel learning pad \(pad + 1)" : "Learn the MIDI note for pad \(pad + 1)")
        }
        .foregroundColor(BKMenuPalette.wellText)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(BKMenuWell())
    }

    /// MIDI learn: the next note-on the engine hears goes to the pad that's listening.
    private func pollLearn() {
        guard let pad = learningPad else { return }
        let last = controller.lastMIDINoteOn
        guard last.count != learnBase else { return }
        controller.learnMIDINote(pad: pad, note: last.note)
        if learnAll && pad + 1 < Pad.count {
            learnBase = last.count
            learningPad = pad + 1
        } else {
            learnAll = false
            learningPad = nil
        }
    }

    private func noteRow(_ left: String, _ right: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(left.uppercased()).font(.system(.subheadline, design: .monospaced).weight(.semibold)).foregroundColor(palette.text)
            Text(right).font(.footnote).foregroundColor(palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: KITS / FILES

    private var filesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("YOUR SAMPLES ON THE PADS") {
                ForEach(0..<Pad.count, id: \.self) { pad in padRow(pad) }
                caption("Tap Import to put an audio file (WAV, AIFF, MP3, M4A, FLAC) on a pad. You can also drag a file from Files straight onto a pad, or hold a pad for its editor. Imported files are copied to "
                        + (controller.isPlugin ? "the plug-in's Samples folder." : "Files › BreaKing › Samples on this device."))
            }
            group("KITS") {
                HStack(spacing: 10) {
                    TextField("Kit name", text: $kitName)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(BKMenuPalette.wellText)
                        .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(BKMenuWell())
                        .accessibilityLabel("Kit name")
                    Button {
                        controller.saveKit(as: kitName)
                    } label: {
                        Label("SAVE KIT", systemImage: "square.and.arrow.down")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .padding(.horizontal, 12).frame(minHeight: 44)
                    }
                    .buttonStyle(BKHardwareButtonStyle(accent: palette.accent))
                    .disabled(kitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                caption("Saves the 12 pads (your samples and pad settings) as a kit. A kit changes the drum sounds only; the pattern keeps playing.")
                ForEach(controller.userKits, id: \.self) { name in userKitRow(name) }
            }
            group("COMPLETE PRESET") {
                action("SHARE / IMPORT A COMPLETE PRESET", symbol: "arrow.up.arrow.down") { subpage = .transfer }
            }
        }
        .onAppear { if kitName.isEmpty { kitName = controller.state.userKit ?? "" } }
    }

    private func padRow(_ pad: Int) -> some View {
        let own = controller.state.pads[pad].sampleFile != nil
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                padDescription(pad, own: own).frame(minWidth: 140, alignment: .leading)
                Spacer(minLength: 8)
                padActions(pad, own: own).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 6) {
                padDescription(pad, own: own)
                padActions(pad, own: own).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(BKMenuWell())
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
                .foregroundColor(own ? palette.accent : BKMenuPalette.wellText.opacity(0.6))
            VStack(alignment: .leading, spacing: 1) {
                Text(controller.padName(pad).uppercased()).font(.system(.body, design: .monospaced)).lineLimit(1)
                    .foregroundColor(BKMenuPalette.wellText)
                Text(own ? "YOUR SAMPLE" : Pad(rawValue: pad)?.label ?? "")
                    .font(.caption).foregroundColor(own ? palette.accent : BKMenuPalette.wellText.opacity(0.6))
            }
        }
    }

    private func padActions(_ pad: Int, own: Bool) -> some View {
        HStack(spacing: 8) {
            smallKey(symbol: "play.fill", label: "Play pad \(pad + 1)") { controller.padDown(pad, velocity: 1) }
            smallKey(title: "EDIT", label: "Edit pad \(pad + 1)") { editPad = pad }
            smallKey(title: "IMPORT", label: "Import a sample onto pad \(pad + 1)", lit: true) {
                importKind = .sample(pad); showingImporter = true
            }
            if own {
                smallKey(symbol: "arrow.uturn.backward", label: "Restore kit sound on pad \(pad + 1)") { controller.revertPad(pad) }
            }
        }
    }

    private func userKitRow(_ name: String) -> some View {
        HStack(spacing: 10) {
            BKMenuLED(isOn: controller.state.userKit == name, accent: palette.accent)
            Text(name.uppercased()).font(.system(.body, design: .monospaced)).lineLimit(1)
                .foregroundColor(BKMenuPalette.wellText)
            Spacer(minLength: 6)
            smallKey(title: "LOAD", label: "Load the kit \(name)") { controller.selectUserKit(name); dismiss() }
            smallKey(symbol: "trash", label: "Delete the kit \(name)") { controller.deleteUserKit(name) }
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(BKMenuWell())
    }

    // MARK: PERFORMANCE

    private var performancePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("PERFORMANCE") {
                action("OPEN THE 12 PERFORMANCE PADS", symbol: "square.grid.3x3") { performance = true }
                action("ENGINE CONTROLS", symbol: "slider.horizontal.3") { subpage = .engine }
                action("SHARE / IMPORT A COMPLETE PRESET", symbol: "arrow.up.arrow.down") { subpage = .transfer }
                action("ALL NOTES AND LOOPS OFF", symbol: "stop.fill") { controller.panic() }
            }
            caption("ALL NOTES & LOOPS OFF is also always in the bottom rail.")
        }
    }

    // MARK: ENGINE CONTROLS (inside the window)

    private var engineControls: [KParam] {
        switch controller.mode {
        case .modern: return [.boost, .punch, .analogEQ, .tighten, .grit, .shine, .noise]
        case .vintage: return [.drive, .bounce, .velocity, .grit, .shine, .tighten, .noise]
        case .texture: return [.resample, .instability, .textureDelay, .gatedReverb, .drive, .shine, .noise]
        }
    }

    private var enginePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            group("WORLD") {
                LazyVGrid(columns: optionColumns, spacing: 8) {
                    ForEach(SoundMode.allCases, id: \.rawValue) { m in
                        option(m.title, selected: controller.mode == m) { controller.selectMode(m) }
                    }
                }
            }
            group(controller.mode.title) {
                ForEach(engineControls, id: \.rawValue) { parameter in
                    BKMenuFader(title: parameter == .bounce ? "Swing" : parameter.name,
                                value: controller.value(parameter),
                                text: parameter.text(controller.value(parameter)),
                                accent: palette.accent,
                                reset: parameter.defaultValue) { controller.set(parameter, $0) }
                        .foregroundColor(palette.text)
                }
            }
            group("MASTER") {
                BKMenuSwitch(title: "CLIPPER", isOn: controller.value(.clipper) > 0.5, accent: palette.accent) {
                    controller.set(.clipper, controller.value(.clipper) > 0.5 ? 0 : 1)
                }
            }
        }
    }

    // MARK: COMPLETE PRESET (inside the window)

    private var transferPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            caption("Share your current kit, all 12 pad settings, imported audio, patterns, and processing controls in one .bbpack file.")
            action(presetWorking ? "PREPARING…" : "PREPARE COMPLETE PRESET", symbol: "shippingbox") { makePackage() }
                .disabled(presetWorking)
            if let url = presetURL {
                action("SHARE / SAVE PRESET", symbol: "square.and.arrow.up") { sharing = SharedFile(url: url) }
            }
            action("IMPORT .BBPACK PRESET", symbol: "square.and.arrow.down") {
                importKind = .preset; showingImporter = true
            }
            .disabled(presetWorking)
            caption("After import, use SAVE on the faceplate to keep a named preset.")
            if let presetError {
                Text(presetError).font(.callout).foregroundColor(palette.accent)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(BKMenuWell())
            }
        }
    }

    private func makePackage() {
        presetWorking = true; presetError = nil; presetURL = nil
        let state = controller.state
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PortablePreset.write(state) }
            DispatchQueue.main.async {
                presetWorking = false
                switch result {
                case .success(let file): presetURL = file
                case .failure(let failure): presetError = failure.localizedDescription
                }
            }
        }
    }

    private func importPackage(_ file: URL) {
        presetWorking = true; presetError = nil; presetURL = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try PortablePreset.read(file) }
            DispatchQueue.main.async {
                presetWorking = false
                switch result {
                case .success(var state):
                    state.midiMap = controller.state.midiMap
                    state.midiCustomNotes = controller.state.midiCustomNotes
                    controller.restore(state)
                    controller.notice = "Portable preset loaded."
                case .failure(let failure): presetError = failure.localizedDescription
                }
            }
        }
    }

    // MARK: Files in (a pad's sample, a .bbpack)

    private var importTypes: [UTType] {
        if case .some(.preset) = importKind { return [.data] }
        return AudioFormats.pickerTypes
    }

    private func imported(_ result: Result<[URL], Error>) {
        defer { importKind = nil }
        switch result {
        case .success(let urls):
            guard let url = urls.first, let kind = importKind else { return }
            switch kind {
            case .sample(let pad): controller.importSample(url, toPad: pad)
            case .preset: importPackage(url)
            }
        case .failure(let failure):
            if case .some(.preset) = importKind { presetError = failure.localizedDescription }
        }
    }

    // MARK: HELP

    private struct Guide: Identifiable { let title: String; let text: String; var id: String { title } }

    private var guides: [Guide] {
        [
            Guide(title: "ONE-SHOT / LOOP", text: "ONE-SHOT: the pads play drums. LOOP: the pads play grooves made from the kit; a new pick starts on the next bar, tap the same pad again to stop at the end of the bar."),
            Guide(title: "MODERN / VINTAGE / TEXTURE", text: "Modern is clean and punchy. Vintage is home to soul, boom bap and break grooves, with tape drive, low-end warmth and a rolled-off top. Texture adds resampling, instability, synced delay and gated reverb. You can play any kit or imported acoustic sample in every mode."),
            Guide(title: "KITS / PRESETS", text: "KITS change the drum sounds only; the pattern keeps playing. PRESETS change the pattern only (groove, variation and tempo); the sounds and knobs stay. Mix any pattern with any kit. SAVE stores everything as your own preset."),
            Guide(title: "DICE", text: "The dice randomizes. LOOP: a new pattern in the preset's style. ONE-SHOT: new variations of the kit's sounds. In the drum roll, each channel has its own dice that changes only that channel."),
            Guide(title: "KNOBS", text: "Drag up or right to turn up. Double-tap to reset."),
            Guide(title: "BPM", text: "Drag up or down on the display. Double-tap for the kit's tempo. With TEMPO SYNC on, the DAW or MIDI clock sets it."),
            Guide(title: "HOLD A PAD", text: "ONE-SHOT: pad editor (level, pan, tune, decay, filter, reverse, your sample). LOOP: step editor for that loop, or drop in a MIDI file."),
            Guide(title: "DRUM ROLL", text: "The piano-keys button opens the drum roll for the pattern that's playing. DRAW: tap to add, tap a note to delete, drag a note to move, drag along a row to paint, drag on the 808 row for a long note. SELECT: box notes, then move, DUPLICATE or CLEAR. ERASE: wipe over notes. The lane underneath sets velocity or pitch. Tap a channel name to load or record a sample onto it, or open its piano roll. M / S mute and solo. RECORD writes what you play on the ▶ buttons or a MIDI controller into the pattern. Space bar plays and stops."),
            Guide(title: "EXPORT", text: "The arrow button renders MIDI, a stereo mix and stems you can drag into a DAW or share."),
        ]
    }

    private var helpPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            action("PLAY THE TUTORIAL", symbol: "graduationcap", perform: playTutorial)
            group("HOW IT WORKS") {
                ForEach(guides) { g in guideRow(g.title, g.text) }
            }
            group("TESTING") {
                action("BUG REPORT", subtitle: "BreakBoss keeps a log while you play. If something goes wrong, open this, write what happened, and Copy or Share the report.",
                       symbol: "ladybug") { subpage = .report }
                // realistic materials, stage 1 (Tyrone, Oct 27): one knob and one pad to try before Face 1 gets them
                action("MATERIAL TEST", subtitle: "The new realistic knob and pad: turn, drum, tilt the iPad, and read how smoothly the screen runs.",
                       symbol: "cube.transparent") { subpage = .materials }
            }
            group("VERSION") {
                HStack {
                    Text("BreaKing").font(.system(.body, design: .monospaced)).foregroundColor(palette.text)
                    Spacer()
                    Text(versionText).font(.system(.body, design: .monospaced)).foregroundColor(palette.secondary)
                }
            }
        }
    }

    private func guideRow(_ title: String, _ text: String) -> some View {
        let open = expandedGuide == title
        return VStack(alignment: .leading, spacing: 10) {
            Button { expandedGuide = open ? nil : title } label: {
                HStack {
                    Text(title).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: open ? "minus" : "plus")
                }
                .padding(.horizontal, 12).frame(minHeight: 48)
            }
            .buttonStyle(BKHardwareButtonStyle(accent: palette.accent, selected: open))
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open { caption(text).padding(.horizontal, 4) }
        }
    }

    // MARK: BUG REPORT (inside the window)

    private var reportPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let crash = BugLog.shared.lastCrash {
                group("BREAKING CRASHED LAST TIME") {
                    Text(crash.split(separator: "\n").prefix(4).joined(separator: "\n"))
                        .font(.system(size: 12, design: .monospaced)).foregroundColor(BKMenuPalette.wellText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(BKMenuWell())
                    caption("The whole crash report is in the report below. Write what you were doing, then Copy or Share.")
                }
            } else if BugLog.shared.lastRunEndedOnScreen {
                group("LAST RUN") {
                    caption("BreaKing closed while it was on screen without a crash report: a freeze, running out of memory, or Stop in Swift Playgrounds.")
                }
            }
            group("WHAT HAPPENED?") {
                TextEditor(text: $what)
                    .font(.body)
                    .foregroundColor(BKMenuPalette.wellText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)
                    .background(BKMenuWell())
                    .accessibilityLabel("What happened")
                caption("What you tapped, what you expected, and what you heard or saw. It goes at the top of the report.")
            }
            action(copied ? "COPIED: PASTE IT IN THE PROJECT CHAT" : "COPY REPORT", symbol: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = BugLog.shared.report(whatHappened: what)
                copied = true
            }
            action("SHARE REPORT AS A FILE…", symbol: "square.and.arrow.up") {
                if let url = BugLog.shared.reportFile(whatHappened: what) { sharing = SharedFile(url: url) }
            }
            action("REFRESH", symbol: "arrow.clockwise") { refreshReport() }
            action("CLEAR OLD REPORTS", symbol: "trash") {
                BugLog.shared.clearOldReports()
                refreshReport()
            }
            caption("The log keeps running while you play. Reports are also saved in Files › BreaKing › Bug Reports.")
            group("REPORT") {
                Text(preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(BKMenuPalette.wellText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(BKMenuWell())
            }
        }
        .onAppear(perform: refreshReport)
        .onChange(of: what) { _ in copied = false }
    }

    /// The on-screen copy shows the last 300 lines; Copy and Share send everything.
    private func refreshReport() {
        let lines = BugLog.shared.report(whatHappened: what).split(separator: "\n", omittingEmptySubsequences: false)
        let shown: [Substring] = lines.count > 300 ? ["…"] + lines.suffix(300) : Array(lines)
        preview = shown.joined(separator: "\n")
    }

    // MARK: Parts

    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }

    private var optionColumns: [GridItem] { [GridItem(.adaptive(minimum: 170), spacing: 8)] }

    private func option(_ title: String, selected: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 9) {
                BKMenuLED(isOn: selected, accent: palette.accent)
                Text(title).font(.system(.caption, design: .monospaced).weight(.bold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 6).frame(minHeight: 48)
        }
        .buttonStyle(BKHardwareButtonStyle(accent: palette.accent, selected: selected))
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func action(_ title: String, subtitle: String? = nil, symbol: String, id: String? = nil,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 22).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundColor(BKMenuPalette.wellText.opacity(0.75))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
            }
            .padding(12).frame(minHeight: 52)
        }
        .buttonStyle(BKHardwareButtonStyle(accent: palette.accent))
        .accessibilityIdentifier(id ?? "")
    }

    private func smallKey(title: String? = nil, symbol: String? = nil, label: String, lit: Bool = false,
                          perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                } else {
                    Text(title ?? "").font(.system(.caption, design: .monospaced).weight(.bold))
                }
            }
            .foregroundColor(lit ? palette.accent : BKMenuPalette.wellText)
            .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(BKHardwareButtonStyle(accent: palette.accent))
        .accessibilityLabel(label)
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(.caption, design: .monospaced).weight(.bold))
                .tracking(1).foregroundColor(palette.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(palette.inset)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.edge, lineWidth: 1))
                .overlay(Rectangle().fill(Color.black.opacity(0.55)).frame(height: 2).padding(.horizontal, 6), alignment: .top)
        )
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.callout).foregroundColor(palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func playTutorial() {
        dismiss()
        // after the menu has gone, so the tour starts on the faceplate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { TutorialGuide.shared.start() }
    }

    /// Closing stops a MIDI learn that's still listening.
    private func dismiss() {
        learnAll = false
        learningPad = nil
        close()
    }
}
