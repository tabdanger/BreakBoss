// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - The hardware menus (Tyrone's mockups, Oct 21)
//
// KITS, PATTERNS and the track menu are compact vertical panels: satin black metal with a slim
// machined edge, a brushed header in the face's own metal, recessed dark rows and one lit
// selection in the face's light (Modern Black and Platinum red, Vintage yellow, Texture blue).
// They open in the same menu layer as the other BreakBoss menus (.bbMenuHost()), so only one menu
// is ever open. Each sits next to the control that opened it, stays inside the app's (or the
// plug-in's) own view, and a tap outside closes it without reaching the step or pad under it.
// Nothing here touches the audio: a row calls the same controller action the old menus did.

/// Where a hardware panel opens from its control.
enum BBPanelPlacement {
    /// Up from a control on the bottom rail (down when there's no room above).
    case above
    /// Beside a track header: to its right, else its left, else under or over it.
    case beside
}

/// A hardware panel waiting in the menu layer: its header, the face it wears and what's in it.
struct BBHardwareSpec {
    let title: String
    let finish: String
    let placement: BBPanelPlacement
    let content: AnyView
}

enum BBPanelMetrics {
    /// The panel's width before it's fitted to the view (the mockups' 300-360 points).
    static let width: CGFloat = 340
    /// Gap kept between the panel and the edges of the app / plug-in view.
    static let inset: CGFloat = 12
    /// The share of the view's height a panel may take; its list scrolls past that.
    static let heightShare: CGFloat = 0.68
    static let headerH: CGFloat = 56
    static let searchH: CGFloat = 52
    static let rowH: CGFloat = 50

    /// The panel's top-left corner for a panel of `size` opened from `anchor`, inside `bounds`.
    static func origin(anchor a: CGRect, size p: CGSize, bounds b: CGSize, placement: BBPanelPlacement) -> CGPoint {
        let i = inset
        func clampX(_ x: CGFloat) -> CGFloat { min(max(i, x), max(i, b.width - p.width - i)) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(i, y), max(i, b.height - p.height - i)) }
        switch placement {
        case .above:
            let x = clampX(a.midX - p.width / 2)
            if a.minY - 8 - p.height >= i { return CGPoint(x: x, y: a.minY - 8 - p.height) }
            if a.maxY + 8 + p.height <= b.height - i { return CGPoint(x: x, y: a.maxY + 8) }
            return CGPoint(x: x, y: clampY(a.minY - 8 - p.height))
        case .beside:
            let y = clampY(a.minY)
            if a.maxX + 8 + p.width <= b.width - i { return CGPoint(x: a.maxX + 8, y: y) }
            if a.minX - 8 - p.width >= i { return CGPoint(x: a.minX - 8 - p.width, y: y) }
            let x = clampX(a.minX)
            if a.maxY + 6 + p.height <= b.height - i { return CGPoint(x: x, y: a.maxY + 6) }
            if a.minY - 6 - p.height >= i { return CGPoint(x: x, y: a.minY - 6 - p.height) }
            return CGPoint(x: x, y: clampY(a.maxY + 6))
        }
    }

    /// The panel's width and tallest height in a view of this size.
    static func fit(_ bounds: CGSize) -> (width: CGFloat, maxHeight: CGFloat) {
        let w = max(200, min(width, bounds.width - inset * 2))
        let h = max(180, min(bounds.height * heightShare, bounds.height - inset * 2))
        return (w, h)
    }
}

/// How tall the panel's body (under the header) may grow; its lists scroll inside that.
private struct BBPanelBodyKey: EnvironmentKey { static let defaultValue: CGFloat = 400 }
extension EnvironmentValues {
    var bbPanelBody: CGFloat {
        get { self[BBPanelBodyKey.self] }
        set { self[BBPanelBodyKey.self] = newValue }
    }
}

// MARK: The layer

/// The open hardware panel over the whole view: a clear catcher that closes it on a tap outside,
/// the panel where it fits, and Escape to close.
struct BBHardwareLayer: View {
    let spec: BBHardwareSpec
    let anchor: CGRect
    let bounds: CGSize
    let close: () -> Void
    @State private var size: CGSize = .zero
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fit = BBPanelMetrics.fit(bounds)
        // until the panel has measured itself, place it as if it were as tall as it may grow
        let known = size.height > 0 ? size : CGSize(width: fit.width, height: fit.maxHeight)
        let spot = BBPanelMetrics.origin(anchor: anchor, size: known, bounds: bounds, placement: spec.placement)
        let opensUp = spec.placement == .above && spot.y < anchor.minY
        ZStack(alignment: .topLeading) {
            // a touch anywhere else closes the menu and goes no further: it doesn't toggle a step or play a pad
            Color.white.opacity(0.001)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { _ in close() })
                .accessibilityElement()
                .accessibilityLabel("Close \(spec.title.lowercased())")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { close() }
                .accessibilityIdentifier("hwMenuOutside")
            BBHardwarePanel(spec: spec, maxHeight: fit.maxHeight, close: close)
                .frame(width: fit.width)
                // measured the way the menu triggers measure their buttons (a preference here never
                // reported on the iPad, so the panel stayed invisible)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { size = g.size }
                        .onChange(of: g.size) { size = $0 }
                })
                .scaleEffect(shown || reduceMotion ? 1 : 0.97, anchor: opensUp ? .bottom : .top)
                .opacity(shown ? 1 : 0)
                .offset(x: spot.x, y: spot.y)
            // Escape on a hardware keyboard
            Button("", action: close)
                .keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .environment(\.seqFinish, spec.finish)
        .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.14)) { shown = true } }
    }
}

// MARK: The panel

/// The shell every hardware menu wears: header with the crown, its title and a close button, then
/// the menu's own body.
struct BBHardwarePanel: View {
    let spec: BBHardwareSpec
    let maxHeight: CGFloat
    let close: () -> Void

    var body: some View {
        let skin = SamplerSkin.of(spec.finish)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 0) {
            header(skin)
            spec.content
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 10)
                .environment(\.bbPanelBody, maxHeight - BBPanelMetrics.headerH - 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(BBSatinBody(skin: skin, shape: shape))
        .overlay(BBMachinedEdge(skin: skin, shape: shape))
        .clipShape(shape)
        .background(shape.fill(Color.black)
            .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
            .shadow(color: .black.opacity(0.5), radius: 20, y: 12))
    }

    private func header(_ skin: SamplerSkin) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "crown.fill").font(.system(size: 14, weight: .semibold))
                .foregroundColor(skin.ink.opacity(0.85))
                .shadow(color: skin.ink == Color(white: 0.13) ? .white.opacity(0.5) : .black.opacity(0.7), radius: 0, y: 1)
            Text(spec.title.uppercased())
                .font(.system(size: 21, weight: .medium)).kerning(1)
                .foregroundColor(skin.ink).lineLimit(1).minimumScaleFactor(0.6)
                .shadow(color: skin.ink == Color(white: 0.13) ? .white.opacity(0.5) : .black.opacity(0.7), radius: 0, y: 1)
                .accessibilityIdentifier("hwMenuTitle")
            Spacer(minLength: 6)
            Button(action: close) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(LinearGradient(colors: [Color(white: 0.03), Color(white: 0.1)], startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(LinearGradient(colors: [.black.opacity(0.8), skin.bezel.bright.opacity(0.55)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                        .frame(width: 34, height: 34)
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundColor(Color(white: 0.9))
                }
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(SeqPress())
            .accessibilityLabel("Close")
            .accessibilityIdentifier("hwMenuClose")
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .frame(height: BBPanelMetrics.headerH)
        .background(SamplerMetal(tone: skin.surface, corner: 0))
        .overlay(Rectangle().fill(Color.black.opacity(0.7)).frame(height: 1), alignment: .bottom)
    }
}

/// The panel's body: smooth satin black metal, darkening toward the bottom, with a fine grain.
private struct BBSatinBody<S: Shape>: View {
    let skin: SamplerSkin
    let shape: S
    var body: some View {
        ZStack {
            shape.fill(LinearGradient(stops: [.init(color: Color(white: 0.12), location: 0), .init(color: Color(white: 0.065), location: 0.35),
                                              .init(color: Color(white: 0.045), location: 1)], startPoint: .top, endPoint: .bottom))
            BrushedFinish(corner: 14).opacity(0.45)
        }
        .allowsHitTesting(false)
    }
}

/// The slim machined edge in the face's bezel metal (silver on Modern Black and Platinum, cream on
/// Vintage, blue on Texture), a dark line inside it, the lit top lip and four small screws.
private struct BBMachinedEdge<S: InsettableShape>: View {
    let skin: SamplerSkin
    let shape: S
    var body: some View {
        let b = skin.bezel
        ZStack {
            shape.strokeBorder(LinearGradient(stops: [.init(color: b.bright, location: 0), .init(color: b.light, location: 0.2),
                                                      .init(color: b.dark, location: 0.55), .init(color: b.mid, location: 0.85),
                                                      .init(color: b.light, location: 1)], startPoint: .top, endPoint: .bottom), lineWidth: 2.2)
            shape.inset(by: 2.2).strokeBorder(Color.black.opacity(0.85), lineWidth: 1)
            VStack {
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1).padding(.horizontal, 18).padding(.top, 0.6)
                Spacer()
            }
            GeometryReader { g in
                ForEach(0..<4, id: \.self) { i in
                    BBScrew(tone: b)
                        .position(x: i % 2 == 0 ? 7.5 : g.size.width - 7.5, y: i < 2 ? 7.5 : g.size.height - 7.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A small screw head in the bezel's metal.
private struct BBScrew: View {
    let tone: MetalTone
    var body: some View {
        ZStack {
            Circle().fill(tone.spun)
            Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 0.6)
            Rectangle().fill(Color.black.opacity(0.55)).frame(width: 4.4, height: 0.9).rotationEffect(.degrees(35))
        }
        .frame(width: 6, height: 6)
    }
}

// MARK: Rows

/// A recessed dark row; the selected one is tinted in the face's light with a lit bar on its left.
struct BBRowWell: View {
    var selected = false
    var accent: Color
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        ZStack(alignment: .leading) {
            shape.fill(LinearGradient(colors: [Color(white: 0.045), Color(white: 0.085)], startPoint: .top, endPoint: .bottom))
            if selected {
                shape.fill(LinearGradient(colors: [accent.opacity(0.2), accent.opacity(0.09)], startPoint: .leading, endPoint: .trailing))
                Capsule().fill(accent).frame(width: 3).padding(.vertical, 8).padding(.leading, 3)
                    .shadow(color: accent.opacity(0.9), radius: 3)
            }
            shape.strokeBorder(LinearGradient(colors: [.black.opacity(0.9), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// A section's name over its rows (DRUM KITS, NEO SOUL, STEPS).
struct BBSectionHeading: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased()).font(.system(size: 12, weight: .semibold)).kerning(0.8)
                .foregroundColor(Color(white: 0.62)).lineLimit(1).minimumScaleFactor(0.7)
            Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1)
        }
        .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The small lamp on a browser row: a dark ring, lit in the face's light on the selected row.
struct BBRowLamp: View {
    let on: Bool
    let accent: Color
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.04))
            Circle().strokeBorder(Color(white: on ? 0.75 : 0.45), lineWidth: 1.4)
            if on {
                Circle().fill(accent).padding(4).shadow(color: accent, radius: 3)
            }
        }
        .frame(width: 17, height: 17)
    }
}

/// A KITS / PATTERNS row: lamp, name and its details, a check when it's the one loaded.
struct BBBrowserRow: View {
    let title: String
    let detail: String?
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                BBRowLamp(on: selected, accent: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundColor(Color(white: selected ? 0.98 : 0.9))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let detail {
                        Text(detail).font(.system(size: 11.5, weight: .medium, design: .monospaced)).foregroundColor(Color(white: 0.58)).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(accent)
                        .shadow(color: accent.opacity(0.7), radius: 2)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: BBPanelMetrics.rowH)
            .background(BBRowWell(selected: selected, accent: accent))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlatePress())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The search field at the top of KITS and PATTERNS.
struct BBPanelSearch: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundColor(Color(white: 0.6))
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Color(white: 0.5)))
                .font(.system(size: 15)).foregroundColor(Color(white: 0.92))
                .textInputAutocapitalization(.characters).disableAutocorrection(true)
                .accessibilityIdentifier("hwMenuSearch")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Color(white: 0.55)).frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(BBRowWell(accent: .clear))
        .padding(.bottom, BBPanelMetrics.searchH - 44)
    }
}

/// What's left of a browser after a search: the headings that still have rows under them.
struct BBBrowserEntry: Identifiable {
    enum Kind { case heading, row }
    let id: String
    let kind: Kind
    let title: String
    var detail: String? = nil
    /// Words the search looks through besides the title (the heading, the tempo).
    var keywords = ""
}

enum BBBrowserFilter {
    /// The entries whose title or keywords hold `query`, each heading kept only with rows under it.
    static func apply(_ entries: [BBBrowserEntry], _ query: String) -> [BBBrowserEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty else { return entries }
        var out: [BBBrowserEntry] = []
        var heading: BBBrowserEntry?
        for e in entries {
            if e.kind == .heading { heading = e; continue }
            guard e.title.uppercased().contains(q) || e.keywords.uppercased().contains(q) else { continue }
            if let h = heading { out.append(h); heading = nil }
            out.append(e)
        }
        return out
    }
}

// MARK: KITS

/// The KITS browser: every factory kit under its genre and mode, then your own. Picking a kit loads
/// its sounds only (the pattern keeps playing) and the browser stays open so you can try the next.
struct KitBrowserPanel: View {
    @ObservedObject var controller: KnockController
    /// Face 1 plays the kick of a kit you pick, as its KITS browser always has.
    var audition = false
    /// Face 1's "Save Kit As…" (nil: not on this face).
    var saveAs: (() -> Void)? = nil
    /// Face 1 deletes your own kits from here.
    var allowDelete = false
    @State private var query = ""
    @Environment(\.bbPanelBody) private var bodyH
    @Environment(\.seqFinish) private var finish

    /// Every factory kit, in browser order, under "GENRE · MODE" (built once: the catalog is fixed).
    static let factoryEntries: [BBBrowserEntry] = {
        var out: [BBBrowserEntry] = []
        for mode in SoundMode.allCases {
            for g in KitLibrary.genreGroups(for: mode) {
                let heading = "\(g.genre) · \(mode.title)"
                out.append(BBBrowserEntry(id: "h:" + heading, kind: .heading, title: heading))
                for def in g.kits {
                    out.append(BBBrowserEntry(id: def.id, kind: .row, title: def.name, detail: "\(Int(def.tempo)) BPM",
                                              keywords: "\(heading) \(def.genre) \(Int(def.tempo)) BPM"))
                }
            }
        }
        return out
    }()

    private var entries: [BBBrowserEntry] {
        var all = Self.factoryEntries
        if !controller.userKits.isEmpty {
            all.append(BBBrowserEntry(id: "h:my", kind: .heading, title: "My kits"))
            all += controller.userKits.map { BBBrowserEntry(id: "user:" + $0, kind: .row, title: $0.uppercased(), detail: "YOUR KIT", keywords: "MY KITS") }
        }
        return BBBrowserFilter.apply(all, query)
    }

    private var currentID: String { controller.state.userKit.map { "user:" + $0 } ?? controller.state.kitID }

    var body: some View {
        let accent = SamplerSkin.of(finish).glow
        VStack(spacing: 0) {
            BBPanelSearch(text: $query, prompt: "Search kits")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { e in
                            if e.kind == .heading {
                                BBSectionHeading(title: e.title)
                            } else {
                                HStack(spacing: 4) {
                                    BBBrowserRow(title: e.title, detail: e.detail, selected: e.id == currentID, accent: accent) { pick(e.id) }
                                    if allowDelete && e.id.hasPrefix("user:") {
                                        BBTrashButton(label: "Delete \(e.title)") { controller.deleteUserKit(String(e.id.dropFirst(5))) }
                                    }
                                }
                                .id(e.id)
                            }
                        }
                        if entries.isEmpty { BBEmptyNote(text: "No kits match \u{201C}\(query)\u{201D}") }
                        if let saveAs, query.isEmpty {
                            BBSectionHeading(title: "Your kits")
                            BBActionRow(icon: { Image(systemName: "square.and.arrow.down") }, title: "Save Kit As…", accent: accent, action: saveAs)
                        }
                    }
                    .padding(.horizontal, 1).padding(.bottom, 2)
                }
                .frame(maxHeight: max(BBPanelMetrics.rowH * 2, bodyH - BBPanelMetrics.searchH))
                .onAppear { scrollToCurrent(proxy) }
            }
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        let id = currentID
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
    }

    private func pick(_ id: String) {
        if id.hasPrefix("user:") { controller.selectUserKit(String(id.dropFirst(5))) }
        else { controller.selectKit(KitLibrary.kit(id: id)) }
        if audition { controller.auditionPad(Pad.kick.rawValue, velocity: 0.9) }
    }
}

// MARK: PATTERNS

/// The PATTERNS browser (the Pattern control's presets): every preset under its style, then your
/// own. Loading one goes through the same load the old menus used, so UPDATE SOUNDS, UPDATE TEMPO
/// and FOLLOW DAW keep their meaning.
struct PatternBrowserPanel: View {
    @ObservedObject var controller: KnockController
    /// Face 1 keeps INIT at the top, as its PRESETS browser had.
    var showInit = false
    /// Face 1 deletes your own presets from here.
    var allowDelete = false
    /// After a preset loads (Face 2 goes back to its first pattern and drops its selection).
    var loaded: () -> Void = {}
    @State private var query = ""
    @Environment(\.bbPanelBody) private var bodyH
    @Environment(\.seqFinish) private var finish

    static let factoryEntries: [BBBrowserEntry] = {
        var out: [BBBrowserEntry] = []
        for style in PatternBank.styles {
            out.append(BBBrowserEntry(id: "h:" + style, kind: .heading, title: style))
            for p in PatternBank.presets(in: style) {
                let detail = "\(Int(p.bpm)) BPM" + (p.swing > 50.5 ? " · \(Int(p.swing))% SWING" : "")
                out.append(BBBrowserEntry(id: p.name, kind: .row, title: p.name, detail: detail, keywords: "\(style) \(detail)"))
            }
        }
        return out
    }()

    private var entries: [BBBrowserEntry] {
        var all: [BBBrowserEntry] = []
        if showInit { all.append(BBBrowserEntry(id: "init:", kind: .row, title: "INIT", detail: "EMPTY PATTERN", keywords: "INIT")) }
        all += Self.factoryEntries
        if !controller.userPresets.isEmpty {
            all.append(BBBrowserEntry(id: "h:my", kind: .heading, title: "My presets"))
            all += controller.userPresets.map { BBBrowserEntry(id: "user:" + $0, kind: .row, title: $0.uppercased(), detail: "YOUR PRESET", keywords: "MY PRESETS") }
        }
        return BBBrowserFilter.apply(all, query)
    }

    private var currentID: String {
        let name = controller.state.presetName
        if showInit && name == "INIT" { return "init:" }
        if let user = controller.userPresets.first(where: { $0.uppercased() == name.uppercased() }), PatternBank.preset(named: name) == nil {
            return "user:" + user
        }
        return name
    }

    var body: some View {
        let accent = SamplerSkin.of(finish).glow
        VStack(spacing: 0) {
            BBPanelSearch(text: $query, prompt: "Search patterns")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(entries) { e in
                            if e.kind == .heading {
                                BBSectionHeading(title: e.title)
                            } else {
                                HStack(spacing: 4) {
                                    BBBrowserRow(title: e.title, detail: e.detail, selected: e.id == currentID, accent: accent) { pick(e.id) }
                                    if allowDelete && e.id.hasPrefix("user:") {
                                        BBTrashButton(label: "Delete \(e.title)") { controller.deleteUserPreset(String(e.id.dropFirst(5))) }
                                    }
                                }
                                .id(e.id)
                            }
                        }
                        if entries.isEmpty { BBEmptyNote(text: "No patterns match \u{201C}\(query)\u{201D}") }
                    }
                    .padding(.horizontal, 1).padding(.bottom, 2)
                }
                .frame(maxHeight: max(BBPanelMetrics.rowH * 2, bodyH - BBPanelMetrics.searchH))
                .onAppear {
                    let id = currentID
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func pick(_ id: String) {
        if id == "init:" { controller.loadInit() }
        else if id.hasPrefix("user:") { controller.loadUserPreset(String(id.dropFirst(5))) }
        else if let p = PatternBank.preset(named: id) { controller.loadPatternPreset(p) }
        else { return }
        loaded()
    }
}

// MARK: The track menu

/// A track's menu (a right-click on its name; nothing else opens it). The order is Tyrone's:
/// Track Settings, Open Sample Editor, Solo, Load Sample, Clear Sample. There's no Remove here
/// (Tyrone, Oct 21); the STEPS fills moved to the grid's right-click menu (Oct 23).
struct TrackMenuPanel: View {
    @ObservedObject var controller: KnockController
    let pad: Int
    let settings: () -> Void
    let openEditor: () -> Void
    let loadSample: () -> Void
    let clearSample: () -> Void
    @Environment(\.bbMenuCenter) private var center
    @Environment(\.bbPanelBody) private var bodyH
    @Environment(\.seqFinish) private var finish

    var body: some View {
        let accent = SamplerSkin.of(finish).glow
        let solo = controller.soloPads[pad]
        let loaded = controller.state.pads[pad].sampleFile != nil
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                BBActionRow(icon: { Image(systemName: "slider.horizontal.3") }, title: "Track Settings…", caption: "Tune, decay, filter, MIDI",
                            accent: accent, id: "trackMenu.settings") { run(settings) }
                BBActionRow(icon: { Image(systemName: "waveform") }, title: "Open Sample Editor", accent: accent, id: "trackMenu.editor") { run(openEditor) }
                // Solo is a switch: the menu stays open and shows its state
                BBActionRow(icon: { Image(systemName: "s.square") }, title: "Solo", accent: accent, trailing: .toggle(solo), id: "trackMenu.solo") {
                    controller.toggleSolo(pad)
                }
                BBActionRow(icon: { Image(systemName: "folder") }, title: "Load Sample…", accent: accent, id: "trackMenu.load") { run(loadSample) }
                BBActionRow(icon: { Image(systemName: "xmark") }, title: "Clear Sample", accent: accent, enabled: loaded, id: "trackMenu.clearSample") { run(clearSample) }
            }
            .padding(.horizontal, 1).padding(.bottom, 2)
        }
        .frame(maxHeight: max(BBPanelMetrics.rowH * 2, bodyH))
    }

    private func run(_ action: @escaping () -> Void) {
        center?.close()
        action()
    }
}

/// A row of the track menu: icon, title (and a small caption), then a chevron or a switch.
struct BBActionRow<Icon: View>: View {
    enum Trailing { case chevron, toggle(Bool), plain }
    @ViewBuilder let icon: () -> Icon
    let title: String
    var caption: String? = nil
    let accent: Color
    var enabled = true
    var trailing: Trailing = .chevron
    var id: String? = nil
    let action: () -> Void

    init(@ViewBuilder icon: @escaping () -> Icon, title: String, caption: String? = nil, accent: Color, enabled: Bool = true,
         trailing: Trailing = .chevron, id: String? = nil, action: @escaping () -> Void) {
        self.icon = icon; self.title = title; self.caption = caption; self.accent = accent
        self.enabled = enabled; self.trailing = trailing; self.id = id; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon().font(.system(size: 17, weight: .regular)).foregroundColor(Color(white: enabled ? 0.88 : 0.4))
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 16, weight: .medium)).foregroundColor(Color(white: enabled ? 0.93 : 0.45)).lineLimit(1)
                    if let caption {
                        Text(caption).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(Color(white: 0.55)).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                switch trailing {
                case .chevron:
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(white: enabled ? 0.6 : 0.3))
                case .toggle(let on):
                    BBSwitchPill(on: on, accent: accent)
                case .plain:
                    EmptyView()
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: caption == nil ? 46 : BBPanelMetrics.rowH)
            .background(BBRowWell(accent: accent))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlatePress())
        .disabled(!enabled)
        .accessibilityValue(trailingValue)
        .modifier(OptionalID(id: id))
    }

    private var trailingValue: String {
        if case .toggle(let on) = trailing { return on ? "On" : "Off" }
        return ""
    }
}

private struct OptionalID: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}

/// Solo's switch: a dark pill with a lamp, lit in the face's light when it's on.
struct BBSwitchPill: View {
    let on: Bool
    let accent: Color
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(on ? accent : Color(white: 0.35)).frame(width: 9, height: 9)
                .shadow(color: on ? accent : .clear, radius: 3)
            Text(on ? "ON" : "OFF").font(.system(size: 13, weight: .semibold)).foregroundColor(on ? Color(white: 0.95) : Color(white: 0.6))
        }
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(Color(white: 0.03)).overlay(Capsule().strokeBorder(Color(white: on ? 0.5 : 0.3), lineWidth: 1)))
    }
}

/// Delete for one of your own kits or presets.
struct BBTrashButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "trash").font(.system(size: 15)).foregroundColor(Color(white: 0.7))
                .frame(width: 44, height: BBPanelMetrics.rowH)
                .background(BBRowWell(accent: .clear))
        }
        .buttonStyle(PlatePress())
        .accessibilityLabel(label)
    }
}

private struct BBEmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13)).foregroundColor(Color(white: 0.55))
            .frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}
