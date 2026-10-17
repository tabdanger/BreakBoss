// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

// MARK: - KITS and PRESETS browsers (MS26 "PATCH MEMORY" style, in the mode's colour)
//
// Banks on the left (favourites, factory banks with counts, your own), search and filter
// chips on top, numbered cards with a star, and a detail panel with SAVE / SAVE AS NEW.
// Tapping a card loads it straight away. KITS change sounds only; PRESETS change the
// pattern only. Colour follows the mode: Modern / Platinum red, Vintage cream, Texture blue.

struct BrowserView: View {
    enum Kind: String, Identifiable { case kits, presets; var id: String { rawValue } }
    @ObservedObject var controller: KnockController
    let kind: Kind
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var bank = ""
    @State private var search = ""
    @State private var chip = "ALL"
    @State private var favorites: Set<String> = []
    @State private var newName = ""
    @State private var naming = false

    // MARK: Colours

    private var accent: Color {
        switch controller.mode {
        case .modern: return Color(red: 0.91, green: 0.28, blue: 0.25)
        case .vintage: return Color(red: 0.95, green: 0.86, blue: 0.6)
        case .texture: return Color(red: 0.3, green: 0.63, blue: 1)
        }
    }
    private let bg = Color(red: 0.055, green: 0.055, blue: 0.06)
    private let panel = Color(red: 0.085, green: 0.085, blue: 0.09)
    private let card = Color(red: 0.11, green: 0.11, blue: 0.115)
    private let line = Color(red: 0.2, green: 0.2, blue: 0.21)
    private let text = Color(red: 0.93, green: 0.92, blue: 0.9)
    private let dim = Color(red: 0.6, green: 0.6, blue: 0.6)
    private func mono(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    private var compact: Bool { sizeClass == .compact }

    // MARK: Items

    struct Item: Identifiable, Hashable {
        let id: String
        let number: Int
        let category: String
        let name: String
        let detail: String
        let bank: String
        let user: Bool
        /// The genre tab a kit sits under (TRAP, WEST COAST...).
        var family = ""
    }

    private static let favoritesBank = "★ FAVORITES"
    private static let userBank = "USER"

    private var allItems: [Item] {
        switch kind {
        case .presets:
            var n = 0
            var out = PatternBank.all.map { p -> Item in
                n += 1
                return Item(id: p.name, number: n, category: p.style.uppercased(), name: p.name,
                            detail: "\(Int(p.bpm)) BPM" + (p.swing > 50.5 ? " · \(Int(p.swing))% SWING" : " · STRAIGHT"),
                            bank: p.style, user: false)
            }
            out += controller.userPresets.enumerated().map { i, name in
                Item(id: "user:" + name, number: i + 1, category: "USER", name: name.uppercased(), detail: "YOUR PRESET", bank: Self.userBank, user: true)
            }
            return out
        case .kits:
            var n = 0
            var out: [Item] = []
            for mode in SoundMode.allCases {
                for g in KitLibrary.genreGroups(for: mode) {
                    for def in g.kits {
                        n += 1
                        out.append(Item(id: def.id, number: n, category: def.genre, name: def.name,
                                        detail: "\(mode.title.uppercased()) · \(Int(def.tempo)) BPM", bank: "\(mode.title.uppercased()) KITS",
                                        user: false, family: def.family))
                    }
                }
            }
            out += controller.userKits.enumerated().map { i, name in
                Item(id: "user:" + name, number: i + 1, category: "USER", name: name.uppercased(), detail: "YOUR KIT", bank: Self.userBank, user: true)
            }
            return out
        }
    }

    struct BankInfo: Hashable { let name: String; let count: Int }

    private var banks: [BankInfo] {
        let items = allItems.filter { !$0.user }
        var order: [String] = []
        for i in items where !order.contains(i.bank) { order.append(i.bank) }
        return order.map { b in BankInfo(name: b, count: items.filter { $0.bank == b }.count) }
    }

    private var chips: [String] {
        switch kind {
        case .presets: return ["ALL", "STRAIGHT", "SWING", "< 90", "90–110", "110–130", "130+"]
        case .kits: return ["ALL"] + KitLibrary.families
        }
    }

    private var shown: [Item] {
        var items = allItems
        if bank == Self.favoritesBank { items = items.filter { favorites.contains($0.id) } }
        else if bank == Self.userBank { items = items.filter { $0.user } }
        else if !bank.isEmpty && search.isEmpty { items = items.filter { $0.bank == bank } }
        if !search.isEmpty {
            let q = search.uppercased()
            items = items.filter { $0.name.uppercased().contains(q) || $0.category.contains(q) || $0.detail.contains(q) }
        }
        if chip != "ALL" {
            items = items.filter { i in
                switch kind {
                case .kits: return i.family == chip
                case .presets:
                    guard let p = PatternBank.preset(named: i.name) else { return false }
                    switch chip {
                    case "STRAIGHT": return p.swing <= 50.5
                    case "SWING": return p.swing > 50.5
                    case "< 90": return p.bpm < 90
                    case "90–110": return p.bpm >= 90 && p.bpm < 110
                    case "110–130": return p.bpm >= 110 && p.bpm < 130
                    default: return p.bpm >= 130
                    }
                }
            }
        }
        return items
    }

    private var currentID: String {
        switch kind {
        case .presets:
            return controller.userPresets.contains(where: { $0.uppercased() == controller.state.presetName.uppercased() })
                ? "user:" + (controller.userPresets.first { $0.uppercased() == controller.state.presetName.uppercased() } ?? "")
                : controller.state.presetName
        case .kits:
            return controller.state.userKit.map { "user:" + $0 } ?? controller.state.kitID
        }
    }

    private var currentName: String {
        kind == .presets ? controller.state.presetName : controller.state.kitName
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(line).frame(height: 1)
            HStack(spacing: 0) {
                if !compact { sidebar.frame(width: 250) ; Rectangle().fill(line).frame(width: 1) }
                VStack(spacing: 12) {
                    if compact { compactBanks; if naming { namingBox }; compactActions }
                    searchBar
                    chipRow
                    grid
                }
                .padding(14)
                if !compact { Rectangle().fill(line).frame(width: 1); detail.frame(width: 300) }
            }
        }
        .background(bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            favorites = Set(UserDefaults.standard.stringArray(forKey: favKey) ?? [])
            bank = allItems.first(where: { $0.id == currentID })?.bank ?? banks.first?.name ?? ""
        }
    }

    private var favKey: String { kind == .presets ? "breakboss.favPresets" : "breakboss.favKits" }

    private var header: some View {
        HStack(spacing: 14) {
            Text(kind == .presets ? "PRESETS" : "KITS").font(mono(compact ? 20 : 26, .heavy)).foregroundColor(accent)
            Text(kind == .presets ? "PATTERNS" : "DRUM SOUNDS").font(mono(13, .semibold)).foregroundColor(dim)
            Spacer()
            Button { dismiss() } label: {
                HStack(spacing: 8) { Image(systemName: "xmark"); Text("CLOSE") }
                    .font(mono(15, .heavy)).foregroundColor(text)
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(Rectangle().fill(card)).overlay(Rectangle().stroke(line))
            }
        }
        .padding(.horizontal, 18).frame(height: 64)
        .background(Color.black)
    }

    // MARK: Banks

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FACTORY").font(mono(13, .heavy)).foregroundColor(dim).padding(.top, 14)
            ScrollView {
                VStack(spacing: 8) {
                    bankRow(Self.favoritesBank, favorites.count, icon: "star.fill")
                    ForEach(banks, id: \.self) { b in bankRow(b.name, b.count, icon: "lock.fill") }
                    Text("YOUR BANKS").font(mono(13, .heavy)).foregroundColor(dim).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    bankRow(Self.userBank, allItems.filter { $0.user }.count, icon: "folder.fill")
                }
            }
            Spacer(minLength: 8)
            if kind == .presets {
                bigButton("INIT PATTERN", icon: "circle.dashed") { controller.loadInit() }
            }
            bigButton(kind == .presets ? "SAVE AS NEW" : "SAVE KIT AS NEW", icon: "plus") { naming = true; newName = "" }
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
        .background(panel)
    }

    private var compactBanks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton("★", selected: bank == Self.favoritesBank) { bank = Self.favoritesBank }
                ForEach(banks, id: \.self) { b in chipButton(b.name, selected: bank == b.name) { bank = b.name; search = "" } }
                chipButton(Self.userBank, selected: bank == Self.userBank) { bank = Self.userBank }
            }
        }
    }

    private func bankRow(_ name: String, _ count: Int, icon: String) -> some View {
        let sel = bank == name
        return Button { bank = name; search = "" } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13))
                Text(name.uppercased()).font(mono(15, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text("\(count)").font(mono(14, .bold))
            }
            .foregroundColor(sel ? .black : text)
            .padding(.horizontal, 12).frame(height: 50)
            .background(Rectangle().fill(sel ? accent : card))
            .overlay(Rectangle().stroke(sel ? accent : line))
        }
    }

    private func bigButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) { Image(systemName: icon); Text(title) }
                .font(mono(15, .heavy)).foregroundColor(text)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Rectangle().fill(card)).overlay(Rectangle().stroke(line))
        }
    }

    // MARK: Search, chips, cards

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundColor(dim)
            TextField("", text: $search, prompt: Text(kind == .presets ? "SEARCH ALL PRESETS" : "SEARCH ALL KITS").foregroundColor(dim))
                .font(mono(16, .medium)).foregroundColor(text)
                .textInputAutocapitalization(.characters).disableAutocorrection(true)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(dim) }
            }
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(Rectangle().fill(panel)).overlay(Rectangle().stroke(line))
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(chips, id: \.self) { c in chipButton(c, selected: chip == c) { chip = c } } }
        }
    }

    private func chipButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased()).font(mono(14, .heavy)).lineLimit(1)
                .foregroundColor(selected ? .black : text)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Rectangle().fill(selected ? Color(white: 0.94) : card)).overlay(Rectangle().stroke(line))
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: compact ? 2 : 4), spacing: 10) {
                ForEach(shown) { item in cardView(item) }
            }
            if shown.isEmpty {
                Text(bank == Self.favoritesBank ? "Tap a star to add favourites." : "Nothing here yet.")
                    .font(mono(14, .medium)).foregroundColor(dim).padding(.top, 40)
            }
        }
    }

    private func cardView(_ item: Item) -> some View {
        let sel = item.id == currentID
        let fav = favorites.contains(item.id)
        return Button { load(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(String(format: "%03d", item.number)).font(mono(13, .heavy)).foregroundColor(accent)
                        .padding(.horizontal, 5).padding(.vertical, 2).background(Rectangle().fill(Color.black.opacity(0.5)))
                    Text(item.category).font(mono(11, .bold)).foregroundColor(dim).lineLimit(1)
                    Spacer(minLength: 2)
                    Button { toggleFavorite(item) } label: {
                        Image(systemName: fav ? "star.fill" : "star").font(.system(size: 18)).foregroundColor(fav ? accent : dim)
                    }
                    .buttonStyle(.plain)
                }
                Text(item.name).font(mono(compact ? 14 : 17, .heavy)).foregroundColor(text).lineLimit(1).minimumScaleFactor(0.6)
                Text(item.detail).font(mono(11, .semibold)).foregroundColor(Color(red: 0.6, green: 0.68, blue: 0.66)).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(Rectangle().fill(sel ? accent.opacity(0.14) : card))
            .overlay(Rectangle().stroke(sel ? accent : line, lineWidth: sel ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(currentName.uppercased()).font(mono(30, .heavy)).foregroundColor(accent).lineLimit(2).minimumScaleFactor(0.5)
            Text(kind == .presets
                 ? "Patterns only: the drum sounds and knobs stay as they are. Tap a card to load it."
                 : "Sounds only: your pattern keeps playing. Tap a card to hear its drums.")
                .font(.system(size: 15)).foregroundColor(dim)
            if naming { namingBox }
            Spacer()
            if let user = userItemSelected {
                bigButton("DELETE", icon: "trash") {
                    if kind == .presets { controller.deleteUserPreset(user) } else { controller.deleteUserKit(user) }
                }
            }
            HStack(spacing: 10) {
                bigButton("SAVE", icon: "square.and.arrow.down") { saveOver() }
                    .disabled(userItemSelected == nil).opacity(userItemSelected == nil ? 0.4 : 1)
                bigButton("SAVE AS NEW", icon: "plus") { naming = true; newName = "" }
            }
        }
        .padding(18)
        .background(panel)
    }

    private var namingBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME").font(mono(12, .heavy)).foregroundColor(dim)
            TextField("", text: $newName).font(mono(16, .bold)).foregroundColor(text)
                .padding(10).background(Rectangle().fill(card)).overlay(Rectangle().stroke(accent))
                .textInputAutocapitalization(.characters).disableAutocorrection(true)
                .onSubmit { saveNew() }
            HStack {
                bigButton("CANCEL", icon: "xmark") { naming = false }
                bigButton("SAVE", icon: "checkmark") { saveNew() }
            }
        }
    }

    /// iPhone: the detail panel's buttons in one row under the banks.
    private var compactActions: some View {
        HStack(spacing: 8) {
            if kind == .presets { bigButton("INIT", icon: "circle.dashed") { controller.loadInit() } }
            bigButton("SAVE", icon: "square.and.arrow.down") { saveOver() }
                .disabled(userItemSelected == nil).opacity(userItemSelected == nil ? 0.4 : 1)
            bigButton("NEW", icon: "plus") { naming = true; newName = "" }
            if let user = userItemSelected {
                bigButton("DEL", icon: "trash") {
                    if kind == .presets { controller.deleteUserPreset(user) } else { controller.deleteUserKit(user) }
                }
            }
        }
    }

    private var userItemSelected: String? {
        currentID.hasPrefix("user:") ? String(currentID.dropFirst(5)) : nil
    }

    // MARK: Actions

    private func load(_ item: Item) {
        switch kind {
        case .presets:
            if item.user { controller.loadUserPreset(String(item.id.dropFirst(5))) }
            else if let p = PatternBank.preset(named: item.id) { controller.loadPatternPreset(p) }
        case .kits:
            if item.user { controller.selectUserKit(String(item.id.dropFirst(5))) }
            else { controller.selectKit(KitLibrary.kit(id: item.id)) }
            controller.auditionPad(Pad.kick.rawValue, velocity: 0.9)
        }
    }

    private func toggleFavorite(_ item: Item) {
        if favorites.contains(item.id) { favorites.remove(item.id) } else { favorites.insert(item.id) }
        UserDefaults.standard.set(Array(favorites), forKey: favKey)
    }

    private func saveNew() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if kind == .presets { controller.savePreset(as: name) } else { controller.saveKit(as: name) }
        naming = false
        bank = Self.userBank
    }

    private func saveOver() {
        guard let name = userItemSelected else { return }
        if kind == .presets { controller.savePreset(as: name) } else { controller.saveKit(as: name) }
    }
}
