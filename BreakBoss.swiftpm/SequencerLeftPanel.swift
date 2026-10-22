// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Face 2: the left panel (the sound library, GENERATE, MIDI) and the track settings strip.
extension SequencerView {
    // MARK: Left panel: GENERAL (the sound library) · GENERATE · MIDI, on the picture's panel

    var sounds: [LibrarySound] { userSounds + Self.factorySounds }
    var shownSounds: [LibrarySound] {
        var list = sounds
        if let libraryType { list = list.filter { $0.type == libraryType } }
        if !search.isEmpty {
            let q = search.uppercased()
            list = list.filter { $0.name.uppercased().contains(q) || $0.pack.uppercased().contains(q) }
        }
        return list
    }

    /// A section header: the render's own header plate (SeqHeader_<face> for SOUNDS, SeqHeaderGen_<face>
    /// for GENERATE, cut from the picture where each one sits) the full width of the panel, flush
    /// against the well under it. Tap it to slide the panels over.
    func sectionHeader(_ title: String, open: Bool, _ s: CGFloat) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) { section = section == .sounds ? .generate : .sounds }
        } label: {
            ZStack {
                Image(headerPlate(title)).resizable()
                HStack {
                    Text(title).font(.system(size: 19 * s, weight: .semibold)).foregroundColor(inkColor)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 17 * s, weight: .semibold)).foregroundColor(inkColor)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.leading, 19 * s).padding(.trailing, 18 * s)
            }
            .frame(height: A.headerH * s)
        }
        .buttonStyle(PlatePress())
        .accessibilityIdentifier(title == "SOUNDS" ? "soundsHeader" : "generateHeader")
    }

    /// GENERATE at the panel's foot is the picture's own plate there (rounded bottom corners); slid up
    /// over the open GENERATE well it wears the same plate with square bottom corners.
    func headerPlate(_ title: String) -> String {
        title == "SOUNDS" ? "SeqHeader_\(finish)" : section == .generate ? "SeqHeaderGenMid_\(finish)" : "SeqHeaderGen_\(finish)"
    }

    /// The left panel: SOUNDS and GENERATE, each a platinum plate over its dark well. Opening one
    /// slides the GENERATE plate up or down like a piece of metal, closing the other well under it.
    /// Its edges are the picture's: the clip follows the picture's own corner (the plate under it is
    /// the same picture), and no outline is drawn on top (Tyrone, Oct 21: flush, no second edge).
    @ViewBuilder func leftPanel(_ s: CGFloat) -> some View {
        let r = A.leftPanel
        let headerH = A.headerH * s
        let wellH = CGFloat(r[3] - r[1]) * s - 2 * headerH
        VStack(spacing: 0) {
            sectionHeader("SOUNDS", open: section == .sounds, s)
            well(soundsPanel(s).erased(), height: wellH, open: section == .sounds, s)
            sectionHeader("GENERATE", open: section == .generate, s)
            well(generatePanel(s).erased(), height: wellH, open: section == .generate, s)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14 * s))
        .place(r, s)
    }

    /// A dark well under a plate: the content keeps its size and the plate below slides over it.
    func well<Content: View>(_ content: Content, height: CGFloat, open: Bool, _ s: CGFloat) -> some View {
        content
            .frame(height: height, alignment: .top)
            .background(Color(white: 0.035))
            .overlay(alignment: .top) {
                // the plate above throws its shadow into the well
                LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom).frame(height: 6 * s).allowsHitTesting(false)
            }
            .frame(height: open ? height : 0, alignment: .top)
            .clipped()
    }

    /// GENERATE: GENRE, UPDATE SOUNDS, UPDATE TEMPO, Generate, Clear.
    func generatePanel(_ s: CGFloat) -> some View {
        let line = Rectangle().fill(Color(white: 0.2)).frame(height: 1)
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3 * s) {
                Text("GENRE").font(.system(size: 12 * s, weight: .medium)).foregroundColor(S.dim)
                HStack {
                    Text(generateStyle ?? PatternRandomizer.style(for: controller.state.presetName))
                        .font(.system(size: 17 * s)).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.6)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12 * s, weight: .semibold)).foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16 * s).frame(maxWidth: .infinity, minHeight: 70 * s, alignment: .leading)
            .bbMenu(title: "Genre", width: 280) {
                [BBMenuItem.item("This preset's style", checked: generateStyle == nil) { generateStyle = nil }]
                + PatternBank.styles.map { st in BBMenuItem.item(st, checked: generateStyle == st) { generateStyle = st } }
            }
            line
            HStack(spacing: 0) {
                generateSwitch("UPDATE SOUNDS", on: updateSounds, s) { updateSounds.toggle() }
                Rectangle().fill(Color(white: 0.2)).frame(width: 1)
                generateSwitch("UPDATE TEMPO", on: updateTempo, s) { updateTempo.toggle() }
            }
            .frame(height: 70 * s)
            line
            Spacer(minLength: 0)
            HStack(spacing: 8 * s) {
                SeqButton("SeqBtnGenerate", corner: 8, scale: s) { generate() }.frame(width: 125 * s, height: 46 * s)
                Button { clear() } label: {
                    HStack(spacing: 6 * s) {
                        Image(systemName: "xmark").font(.system(size: 15 * s, weight: .medium))
                        Text("Clear").font(.system(size: 15 * s, weight: .medium))
                    }
                    .foregroundColor(.white).frame(width: 84 * s, height: 46 * s)
                    .background(RoundedRectangle(cornerRadius: 8 * s).fill(Color(white: 0.11)).overlay(RoundedRectangle(cornerRadius: 8 * s).stroke(Color(white: 0.3), lineWidth: 1)))
                }
                .buttonStyle(SeqPress())
            }
            .padding(.bottom, 20 * s)
        }
    }

    func generateSwitch(_ title: String, on: Bool, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(title).font(.system(size: 11 * s, weight: .medium)).foregroundColor(S.dim).lineLimit(1).minimumScaleFactor(0.7)
                Text(on ? "On" : "Off").font(.system(size: 16 * s)).foregroundColor(on ? .white : Color(white: 0.5))
            }
            .padding(.horizontal, 12 * s).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SeqPress())
    }

    /// The sound library (SOUNDS open): type chips, search, the list, import. Drag a sound to the rack.
    func soundsPanel(_ s: CGFloat) -> some View {
        VStack(spacing: 7 * s) {
            // the chips run the well's full width and sink into its edges as they scroll, instead of
            // being cut off short of the panel's edge (Tyrone, Oct 21); at rest they sit where they did
            // and the next chip's sliver past RIMS is under the right edge, not showing
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4 * s) {
                    typeChip("ALL", on: libraryType == nil, s) { libraryType = nil }
                    ForEach(SoundType.allCases) { t in typeChip(t.rawValue, on: libraryType == t, s) { libraryType = t } }
                }
                .padding(.horizontal, 8 * s)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.027),
                                         .init(color: .black, location: 0.963), .init(color: .clear, location: 0.969)],
                                 startPoint: .leading, endPoint: .trailing))
            .padding(.horizontal, -8 * s)
            HStack(spacing: 5 * s) {
                Image(systemName: "magnifyingglass").font(.system(size: 16 * s)).foregroundColor(Color(white: 0.78))
                TextField("Search", text: $search).font(.system(size: 16 * s)).foregroundColor(.white).autocorrectionDisabled().focused($searchFocused)
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 14 * s)).foregroundColor(S.dim) } }
            }
            .padding(.horizontal, 10 * s).frame(height: 33 * s).background(RoundedRectangle(cornerRadius: 6 * s).fill(Color(white: 0.11)))
            ScrollView {
                LazyVStack(spacing: 2 * s) {
                    ForEach(shownSounds) { sound in soundRow(sound, s) }
                    if shownSounds.isEmpty { Text("Nothing here yet.").font(.system(size: 12 * s)).foregroundColor(S.dim).padding(16 * s) }
                }
            }
            HStack(spacing: 8 * s) {
                Button { importKind = .sounds } label: { smallLabel("square.and.arrow.down", "SOUNDS", s) }
                Button { importKind = .pack } label: { smallLabel("folder.badge.plus", "PACK", s) }
                if let pad = selectedPad, !controller.isPlugin { Button { recordPad = pad } label: { smallLabel("record.circle", "REC", s) } }
            }
            // how loud picked sounds are heard; let go to hear the selected track at that level
            PreviewFader(value: previewVolume, scale: s, color: accent,
                         change: { previewVolume = $0 },
                         done: { controller.previewAgain(orPad: selectedPad) })
                .frame(height: 24 * s)
            Text(libraryNote.isEmpty ? "DRAG A SOUND ONTO THE RACK" : libraryNote).font(.system(size: 8 * s, weight: .semibold)).foregroundColor(S.dim).lineLimit(1)
        }
        .padding(.horizontal, 8 * s).padding(.top, 9 * s).padding(.bottom, 6 * s)
    }

    func soundRow(_ sound: LibrarySound, _ s: CGFloat) -> some View {
        let onSelected = selected?.soundID == sound.id
        let picked = libraryPick == sound.id
        return HStack(spacing: 6 * s) {
            Image(systemName: "waveform").font(.system(size: 16 * s)).foregroundColor(onSelected ? accent : Color(white: 0.8)).frame(width: 26 * s)
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(sound.name).font(.system(size: 15 * s, weight: .medium)).foregroundColor(onSelected ? accent : .white).lineLimit(1).minimumScaleFactor(0.7)
                Text(sound.pack).font(.system(size: 11 * s)).foregroundColor(Color(white: 0.72)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if sound.user { Text("YOURS").font(.system(size: 8 * s, weight: .bold)).foregroundColor(S.orange) }
            Image(systemName: "line.3.horizontal").font(.system(size: 14 * s)).foregroundColor(Color(white: 0.75))
        }
        .padding(.horizontal, 6 * s).frame(height: 49 * s)
        .background(RoundedRectangle(cornerRadius: 5 * s).fill(onSelected || picked ? accent.opacity(0.12) : Color.clear))
        .overlay { if picked { RoundedRectangle(cornerRadius: 5 * s).stroke(accent.opacity(0.8), lineWidth: 1.5 * s).allowsHitTesting(false) } }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.16)).frame(height: 1).allowsHitTesting(false) }
        .contentShape(Rectangle())
        // the first tap picks the sound and plays it, every tap on it after that plays it again at the
        // preview volume; no track changes (drag it onto the rack for that, Tyrone, Oct 20)
        .onTapGesture {
            libraryPick = sound.id
            controller.previewSound(sound); libraryPreviews += 1
        }
        .accessibilityIdentifier("librarySound_" + sound.name)
        .accessibilityValue(picked ? "picked, played \(libraryPreviews)" : "")
        .onDrag {
            NSItemProvider(object: (soundDragPrefix + sound.id) as NSString)
        } preview: {
            Text(sound.name).font(.system(size: 12, weight: .semibold)).foregroundColor(.black)
                .padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(accent))
        }
    }

    func typeChip(_ title: String, on: Bool, _ s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11 * s, weight: .semibold))
                .foregroundColor(on ? .black : .white).padding(.horizontal, 8 * s).frame(height: 26 * s)
                .background(RoundedRectangle(cornerRadius: 4 * s).fill(on ? accent : Color(white: 0.14)))
                .overlay(RoundedRectangle(cornerRadius: 4 * s).stroke(on ? accent : Color(white: 0.34), lineWidth: 1))
                .shadow(color: on ? accent.opacity(0.7) : .clear, radius: 4 * s)
        }
    }

    func smallLabel(_ icon: String, _ title: String, _ s: CGFloat) -> some View {
        HStack(spacing: 3 * s) {
            Image(systemName: icon).font(.system(size: 14 * s, weight: .medium))
            Text(title).font(.system(size: 13 * s, weight: .medium))
        }
        .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 40 * s)
        .background(RoundedRectangle(cornerRadius: 6 * s).fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6 * s).stroke(Color(white: 0.4), lineWidth: 1)))
    }

    /// Generate: new steps in the chosen genre; UPDATE SOUNDS rolls new sounds on every channel too;
    /// UPDATE TEMPO sets the genre's tempo.
    func generate() {
        let style = generateStyle ?? PatternRandomizer.style(for: controller.state.presetName)
        remember()
        controller.randomizePattern(style: style)
        if updateSounds { controller.dice() }
        if updateTempo, !controller.tempoIsExternal {
            let bpms = PatternBank.presets(in: style).map(\.bpm)
            if !bpms.isEmpty { controller.setBPM((bpms.reduce(0, +) / Double(bpms.count)).rounded()) }
        }
        selection = []
    }

    // MARK: Track settings (sound, tune, decay, filter, reverse, solo, MIDI): from the channel's menu

    func channelStrip(_ ch: WorkspaceChannel) -> some View {
        let pad = ch.pad
        let ps = controller.state.pads[pad]
        func set(_ change: (inout PadSettings) -> Void) { var v = controller.state.pads[pad]; change(&v); controller.setPadSettings(pad, v) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ch.name).font(.system(size: 13, weight: .semibold)).foregroundColor(lit).lineLimit(1)
                    Text(controller.padName(pad).uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(S.dim).lineLimit(1)
                }
                .frame(width: 150, alignment: .leading)
                labelBox("waveform", "SOUND").bbMenu(title: ch.name, width: 320) { channelSampleItems(ch) }
                    .accessibilityIdentifier("trackSound\(pad)")
                labelBox("cable.connector", midiOutLabel(pad), lit: controller.midiOutOn && controller.midiOutChannels[pad] >= 0)
                    .bbMenu(title: "MIDI out · \(ch.name)", width: 240) { midiOutChannelItems(pad) }
                divider
                stripKnob("TUNE", ps.tune, -24...24, String(format: "%+.1f", ps.tune)) { v in set { $0.tune = (v * 2).rounded() / 2 } }
                stripKnob("DECAY", ps.decay, 0.05...1, ps.decay >= 0.999 ? "FULL" : String(format: "%.0f%%", ps.decay * 100)) { v in set { $0.decay = v } }
                stripKnob("FILTER", ps.filter, 0...1, ps.filter >= 0.999 ? "OPEN" : String(format: "%.0f Hz", 40 * powf(450, ps.filter))) { v in set { $0.filter = v } }
                Button { set { $0.reverse.toggle() } } label: { labelBox("arrow.left.arrow.right", "REV", lit: ps.reverse) }
                Button { controller.toggleSolo(pad) } label: { labelBox("s.square", "SOLO", lit: controller.soloPads[pad]) }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 64)
        .background(S.channel)
    }

    func channelSampleItems(_ ch: WorkspaceChannel) -> [BBMenuItem] {
        let pad = ch.pad
        var items: [BBMenuItem] = [.item("Load a sample from Files…", icon: "folder") { importPad = pad }]
        if !controller.isPlugin { items.append(.item("Record to this channel…", icon: "record.circle") { recordPad = pad }) }
        if controller.state.pads[pad].sampleFile != nil {
            items.append(.item("Back to the kit's sound", icon: "arrow.uturn.backward", destructive: true) { controller.revertPad(pad) })
        }
        return items
    }

    func stripKnob(_ title: String, _ value: Float, _ range: ClosedRange<Float>, _ text: String,
                           set: @escaping (Float) -> Void) -> some View {
        let norm = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return HStack(spacing: 6) {
            DrumRollKnob(value: norm) { v, _ in set(range.lowerBound + v * (range.upperBound - range.lowerBound)) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(S.dim)
                Text(text).font(.system(size: 12, design: .monospaced)).foregroundColor(S.text)
            }
            .frame(width: 58, alignment: .leading)
        }
    }
}
