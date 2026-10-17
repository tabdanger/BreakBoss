// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UIKit

// MARK: - BreakBoss's own drop-down menus (no Apple pop-up menus anywhere)
//
// A button marked .bbMenu(...) opens a BreakBoss-styled panel just under itself. The panel
// lives in a host layer added with .bbMenuHost() at the top of each screen (faceplate, drum
// roll, piano roll, sheets), so it's drawn over everything and closes when you tap outside.
// Items can open a sub-list in the same panel (with a back row), and a panel can hold custom
// content such as the tempo slider.

struct BBMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var detail: String? = nil
    var icon: String? = nil
    var checked = false
    var destructive = false
    var isHeader = false
    var enabled = true
    var children: [BBMenuItem]? = nil
    var action: (() -> Void)? = nil

    static func header(_ title: String) -> BBMenuItem { BBMenuItem(title: title, isHeader: true) }
    static func item(_ title: String, detail: String? = nil, icon: String? = nil, checked: Bool = false,
                     destructive: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) -> BBMenuItem {
        BBMenuItem(title: title, detail: detail, icon: icon, checked: checked, destructive: destructive, enabled: enabled, action: action)
    }
    static func submenu(_ title: String, icon: String? = nil, _ children: [BBMenuItem]) -> BBMenuItem {
        BBMenuItem(title: title, icon: icon, children: children)
    }
}

struct BBMenuSpec: Identifiable {
    let id = UUID()
    var anchor: CGRect
    var width: CGFloat
    var title: String?
    var items: [BBMenuItem]
    var custom: AnyView? = nil
}

final class BBMenuCenter: ObservableObject {
    @Published var open: BBMenuSpec?
    @Published var path: [BBMenuItem] = []     // sub-lists opened inside the panel
    func show(_ spec: BBMenuSpec) { withAnimation(.easeOut(duration: 0.16)) { path = []; open = spec } }
    func close() { withAnimation(.easeIn(duration: 0.12)) { open = nil; path = [] } }
}

enum BBMenuStyle {
    static let panel = Color(red: 0.11, green: 0.115, blue: 0.125)
    static let row = Color(red: 0.15, green: 0.155, blue: 0.17)
    static let line = Color(red: 0.26, green: 0.27, blue: 0.29)
    static let text = Color(red: 0.87, green: 0.88, blue: 0.87)
    static let dim = Color(red: 0.58, green: 0.6, blue: 0.61)
    static let accent = Color(red: 181 / 255, green: 232 / 255, blue: 124 / 255)
    static let danger = Color(red: 0.95, green: 0.33, blue: 0.28)
}

private let bbSpace = "bbMenuHost"

extension View {
    /// Adds the layer the BreakBoss menus draw in. Put it on the outermost view of a screen.
    func bbMenuHost() -> some View { modifier(BBMenuHost()) }

    /// Makes this view open a BreakBoss menu when tapped.
    func bbMenu(title: String? = nil, width: CGFloat = 280, items: @escaping () -> [BBMenuItem]) -> some View {
        modifier(BBMenuTrigger(title: title, width: width, items: items, custom: nil))
    }

    /// Opens a BreakBoss menu on a long press (or a right-click with a trackpad or mouse);
    /// a normal tap still runs `tap`.
    func bbLongPressMenu(title: String? = nil, width: CGFloat = 280, tap: @escaping () -> Void,
                         items: @escaping () -> [BBMenuItem]) -> some View {
        modifier(BBMenuTrigger(title: title, width: width, items: items, custom: nil, tap: tap, longPress: true))
    }

    /// A menu trigger placed over a painted button (faceplate pixels): the menu goes on BEFORE the
    /// placement so its touch area and anchor are the button, not the whole screen.
    func bbMenuPlaced(_ r: [Double], _ s: CGFloat, title: String? = nil, width: CGFloat = 280,
                      items: @escaping () -> [BBMenuItem]) -> some View {
        bbMenu(title: title, width: width, items: items).place(r, s)
    }
    func bbPanelPlaced<Content: View>(_ r: [Double], _ s: CGFloat, title: String? = nil, width: CGFloat = 320,
                                      @ViewBuilder content: @escaping () -> Content) -> some View {
        bbPanel(title: title, width: width, content: content).place(r, s)
    }

    /// Makes this view open a BreakBoss panel with custom content (e.g. a slider).
    func bbPanel<Content: View>(title: String? = nil, width: CGFloat = 320, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(BBMenuTrigger(title: title, width: width, items: { [] }, custom: { AnyView(content()) }))
    }
}

private struct BBMenuTrigger: ViewModifier {
    @EnvironmentObject var center: BBMenuCenter
    let title: String?
    let width: CGFloat
    let items: () -> [BBMenuItem]
    let custom: (() -> AnyView)?
    var tap: (() -> Void)? = nil
    var longPress = false
    @State private var frame: CGRect = .zero

    private func open() {
        center.show(BBMenuSpec(anchor: frame, width: width, title: title, items: items(), custom: custom?()))
    }

    func body(content: Content) -> some View {
        let measured = content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .named(bbSpace)) }
                    .onChange(of: g.frame(in: .named(bbSpace))) { frame = $0 }
            })
            .contentShape(Rectangle())
        if longPress {
            // A real button: tap runs `tap`, holding opens the menu (works inside a scrolling rack too).
            Button(action: { tap?() }) { measured }
                .buttonStyle(SeqPress())
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in open() })
                .background(SecondaryClickCatcher { open() })
        } else {
            // A real button: a press-and-hold DragGesture next to onTapGesture swallowed the taps on
            // newer iPadOS, so none of these menus opened. The button goes in while your finger is on it.
            Button(action: open) { measured }
                .buttonStyle(MenuPress())
        }
    }
}

/// The menu buttons' press: a quick darkening, back up on release.
private struct MenuPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(configuration.isPressed ? 0.28 : 0)).allowsHitTesting(false))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// An empty touch area for a painted button (the press glow comes from the menu trigger).
struct PressGlow: View {
    var body: some View { Color.clear.contentShape(Rectangle()) }
}

/// A trackpad / mouse right-click on the view (iPadOS pointer), for the long-press menus.
private struct SecondaryClickCatcher: UIViewRepresentable {
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        let g = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.fire))
        g.buttonMaskRequired = .secondary
        v.addGestureRecognizer(g)
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.action = action }
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }
}

private struct BBMenuHost: ViewModifier {
    @StateObject private var center = BBMenuCenter()

    func body(content: Content) -> some View {
        content
            .environmentObject(center)
            .overlay(
                GeometryReader { geo in
                    if let spec = center.open {
                        ZStack(alignment: .topLeading) {
                            Color.black.opacity(0.25)
                                .contentShape(Rectangle())
                                .onTapGesture { center.close() }
                            BBMenuPanel(spec: spec)
                                .environmentObject(center)
                                .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                                .frame(width: min(spec.width, geo.size.width - 16))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxHeight: max(160, geo.size.height - panelTop(spec, geo) - 12), alignment: .top)
                                .offset(x: panelLeft(spec, geo), y: panelTop(spec, geo))
                        }
                        .transition(.opacity)
                    }
                }
            )
            .coordinateSpace(name: bbSpace)
    }

    private func panelLeft(_ spec: BBMenuSpec, _ geo: GeometryProxy) -> CGFloat {
        let w = min(spec.width, geo.size.width - 16)
        return min(max(8, spec.anchor.minX), geo.size.width - w - 8)
    }

    private func panelTop(_ spec: BBMenuSpec, _ geo: GeometryProxy) -> CGFloat {
        // Under the button, or above it when the button is low on the screen.
        let below = spec.anchor.maxY + 6
        return below > geo.size.height * 0.62 ? max(8, spec.anchor.minY - min(420, geo.size.height * 0.6) - 6) : below
    }
}

private struct BBMenuPanel: View {
    @EnvironmentObject var center: BBMenuCenter
    let spec: BBMenuSpec
    private typealias M = BBMenuStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let parent = center.path.last {
                Button { center.path.removeLast() } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text(parent.title).lineLimit(1)
                        Spacer()
                    }
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(M.accent)
                    .padding(.horizontal, 14).frame(height: 42)
                }
                Rectangle().fill(M.line).frame(height: 1)
            } else if let title = spec.title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(M.dim)
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
            }
            if let custom = spec.custom, center.path.isEmpty {
                custom.padding(14)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(center.path.last?.children ?? spec.items) { item in row(item) }
                    }
                }
                .frame(maxHeight: 460)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(M.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(M.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
    }

    @ViewBuilder private func row(_ item: BBMenuItem) -> some View {
        if item.isHeader {
            Text(item.title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(M.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
        } else {
            Button {
                if let children = item.children {
                    center.path.append(BBMenuItem(title: item.title, children: children))
                } else {
                    center.close()
                    item.action?()
                }
            } label: {
                HStack(spacing: 10) {
                    if let icon = item.icon {
                        Image(systemName: icon).frame(width: 20)
                            .foregroundColor(item.destructive ? M.danger : M.text)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                            .foregroundColor(item.destructive ? M.danger : (item.enabled ? M.text : M.dim))
                        if let d = item.detail {
                            Text(d).font(.system(size: 11, design: .monospaced)).foregroundColor(M.dim).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    if item.checked { Image(systemName: "checkmark").foregroundColor(M.accent) }
                    if item.children != nil { Image(systemName: "chevron.right").foregroundColor(M.dim) }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(!item.enabled)
            .background(item.checked ? M.row : Color.clear)
            Rectangle().fill(M.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 14)
        }
    }
}

/// A BreakBoss slider (tempo, levels): drag anywhere on the track; tap ± to nudge.
struct BBSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var label: (Double) -> String
    let set: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { set(max(range.lowerBound, value - step)) } label: { nudge("minus") }
                Spacer()
                Text(label(value)).font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundColor(BBMenuStyle.text)
                Spacer()
                Button { set(min(range.upperBound, value + step)) } label: { nudge("plus") }
            }
            GeometryReader { g in
                let f = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
                ZStack(alignment: .leading) {
                    Capsule().fill(BBMenuStyle.row).frame(height: 8)
                    Capsule().fill(BBMenuStyle.accent).frame(width: max(8, g.size.width * f), height: 8)
                    Circle().fill(Color.white).frame(width: 26, height: 26)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .offset(x: max(0, min(g.size.width - 26, g.size.width * f - 13)))
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                    let t = Double(max(0, min(1, d.location.x / max(1, g.size.width))))
                    let raw = range.lowerBound + t * (range.upperBound - range.lowerBound)
                    set((raw / step).rounded() * step)
                })
            }
            .frame(height: 30)
        }
    }

    private func nudge(_ icon: String) -> some View {
        Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundColor(BBMenuStyle.text)
            .frame(width: 44, height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(BBMenuStyle.row))
    }
}
