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
    /// The check marks' colour; nil = the usual lime (the sampler on Platinum lights them red).
    var accent: Color? = nil
    /// KITS, PATTERNS and the track menu: a hardware panel (HardwareMenu.swift) instead of the list.
    var hardware: BBHardwareSpec? = nil
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

let bbSpace = "bbMenuHost"

/// The menu layer a trigger opens its menu in. Optional, so a menu button in a view with no
/// .bbMenuHost() above it (a sheet, a new window) does nothing instead of crashing the app
/// (build 82: Track settings in a sheet hit SwiftUI's "No ObservableObject of type BBMenuCenter").
private struct BBMenuCenterKey: EnvironmentKey { static let defaultValue: BBMenuCenter? = nil }
extension EnvironmentValues {
    var bbMenuCenter: BBMenuCenter? {
        get { self[BBMenuCenterKey.self] }
        set { self[BBMenuCenterKey.self] = newValue }
    }
    /// The colour the menus opened from inside this view check their items in (nil = lime).
    var bbMenuAccent: Color? {
        get { self[BBMenuAccentKey.self] }
        set { self[BBMenuAccentKey.self] = newValue }
    }
}
private struct BBMenuAccentKey: EnvironmentKey { static let defaultValue: Color? = nil }

extension View {
    /// Adds the layer the BreakBoss menus draw in. Put it on the outermost view of a screen.
    func bbMenuHost() -> some View { modifier(BBMenuHost()) }

    /// Makes this view open a BreakBoss menu when tapped.
    func bbMenu(title: String? = nil, width: CGFloat = 280, items: @escaping () -> [BBMenuItem]) -> some View {
        modifier(BBMenuTrigger(title: title, width: width, items: items, custom: nil))
    }

    /// Opens a BreakBoss menu on a two-finger tap (or a right-click with a trackpad or mouse);
    /// a normal tap still runs `tap`. Holding does nothing (Tyrone, Oct 17: no hold menus).
    func bbTwoFingerMenu(title: String? = nil, width: CGFloat = 280, tap: @escaping () -> Void,
                         items: @escaping () -> [BBMenuItem]) -> some View {
        modifier(BBMenuTrigger(title: title, width: width, items: items, custom: nil, tap: tap, twoFinger: true))
    }

    /// Opens a BreakBoss menu on a two-finger tap (or right-click) on a control that keeps its own
    /// touches, such as a knob or the sampler's waveform: one finger still turns or drags it.
    func bbContextMenu(title: String? = nil, width: CGFloat = 280, items: @escaping () -> [BBMenuItem]) -> some View {
        modifier(BBContextTrigger(title: title, width: width, items: items))
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

    /// Opens one of the hardware panels (KITS, PATTERNS) when tapped: up from the control, or down
    /// when there's no room above.
    func bbHardwareMenu<Content: View>(title: String, finish: String, placement: BBPanelPlacement = .above, id: String? = nil,
                                       @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(BBHardwareTrigger(title: title, finish: finish, placement: placement, panel: { AnyView(content()) }, id: id))
    }

    /// A hardware panel's trigger placed over a painted button (see bbMenuPlaced).
    func bbHardwarePlaced<Content: View>(_ r: [Double], _ s: CGFloat, title: String, finish: String, id: String? = nil,
                                         @ViewBuilder content: @escaping () -> Content) -> some View {
        bbHardwareMenu(title: title, finish: finish, id: id, content: content).place(r, s)
    }

    /// The track menu (Tyrone, Oct 21): a trackpad / mouse right-click opens it beside the track; a
    /// normal tap still runs `tap`. No two-finger tap and no hold (Tyrone, Oct 21 08:44). `extraWidth` stretches the anchor over the rest
    /// of the track's row so the panel opens clear of its knobs.
    func bbTrackMenu<Content: View>(title: String, finish: String, extraWidth: CGFloat = 0, tap: @escaping () -> Void,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(BBHardwareTrigger(title: title, finish: finish, placement: .beside, extraWidth: extraWidth,
                                   panel: { AnyView(content()) }, tap: tap))
    }

    /// Makes this view open a BreakBoss panel with custom content (e.g. a slider).
    func bbPanel<Content: View>(title: String? = nil, width: CGFloat = 320, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(BBMenuTrigger(title: title, width: width, items: { [] }, custom: { AnyView(content()) }))
    }
}

private struct BBMenuTrigger: ViewModifier {
    @Environment(\.bbMenuCenter) private var center
    @Environment(\.bbMenuAccent) private var accent
    let title: String?
    let width: CGFloat
    let items: () -> [BBMenuItem]
    let custom: (() -> AnyView)?
    var tap: (() -> Void)? = nil
    var twoFinger = false
    @State private var frame: CGRect = .zero

    private func open() {
        center?.show(BBMenuSpec(anchor: frame, width: width, title: title, items: items(), custom: custom?(), accent: accent))
    }

    func body(content: Content) -> some View {
        let measured = content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .named(bbSpace)) }
                    .onChange(of: g.frame(in: .named(bbSpace))) { frame = $0 }
            })
            .contentShape(Rectangle())
        if twoFinger {
            // A real button: one finger runs `tap`, two fingers (or a right-click) open the menu.
            Button(action: { tap?() }) { measured }
                .buttonStyle(SeqPress())
                .twoFingerTap { open() }
                .uiTestHold { open() }
        } else {
            // A real button: a press-and-hold DragGesture next to onTapGesture swallowed the taps on
            // newer iPadOS, so none of these menus opened. The button goes in while your finger is on it.
            Button(action: open) { measured }
                .buttonStyle(MenuPress())
        }
    }
}

/// Opens a hardware panel. As a track menu (`tap` set) it's a real button: a tap runs `tap`, a
/// right-click opens the panel.
private struct BBHardwareTrigger: ViewModifier {
    @Environment(\.bbMenuCenter) private var center
    let title: String
    let finish: String
    let placement: BBPanelPlacement
    var extraWidth: CGFloat = 0
    let panel: () -> AnyView
    var tap: (() -> Void)? = nil
    /// The button's id for the UI tests (KITS and PATTERNS chips).
    var id: String? = nil
    @State private var frame: CGRect = .zero

    /// UI tests: how often this trigger opened its panel, and whether it had a menu layer to open it in.
    @State private var opens = 0

    private func open() {
        opens += 1
        var anchor = frame
        anchor.size.width += extraWidth
        center?.show(BBMenuSpec(anchor: anchor, width: BBPanelMetrics.width, title: title, items: [],
                                hardware: BBHardwareSpec(title: title, finish: finish, placement: placement, content: panel())))
    }

    func body(content: Content) -> some View {
        let measured = content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .named(bbSpace)) }
                    .onChange(of: g.frame(in: .named(bbSpace))) { frame = $0 }
            })
            .contentShape(Rectangle())
        if tap != nil {
            // a tap selects / auditions; only a right-click opens the menu (Tyrone, Oct 21). UI tests can't
            // right-click on the iPad simulator, so they get the one-second hold (BREAKBOSS_UI_PROBE only).
            Button(action: { tap?() }) { measured }
                .buttonStyle(SeqPress())
                .rightClick { open() }
                .uiTestPress { open() }
                .accessibilityAction(named: "Track menu") { open() }
                .accessibilityValue(SamplerWindow.probing ? "menu opens \(opens) layer \(center == nil ? "none" : "ok")" : "")
        } else {
            Button(action: open) { measured }
                .buttonStyle(MenuPress())
                .modifier(TriggerID(id: id))
        }
    }
}

private struct TriggerID: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}

/// Opens a menu from code at a point inside the view it's attached to (the grid's right-click menu,
/// where the grid's own gesture code knows what was clicked). Attach it with .bbMenuOpener(_:).
final class BBMenuOpener {
    fileprivate var center: BBMenuCenter?
    fileprivate var accent: Color?
    fileprivate var frame: CGRect = .zero

    /// `point` is in the attached view's own space.
    func show(at point: CGPoint, title: String? = nil, width: CGFloat = 260, items: [BBMenuItem]) {
        guard let center, !items.isEmpty else { return }
        let anchor = CGRect(x: frame.minX + point.x, y: frame.minY + point.y, width: 1, height: 1)
        center.show(BBMenuSpec(anchor: anchor, width: width, title: title, items: items, accent: accent))
    }
}

private struct BBMenuOpenerHook: ViewModifier {
    @Environment(\.bbMenuCenter) private var center
    @Environment(\.bbMenuAccent) private var accent
    let opener: BBMenuOpener

    func body(content: Content) -> some View {
        content.background(GeometryReader { g in
            Color.clear
                .onAppear { opener.center = center; opener.accent = accent; opener.frame = g.frame(in: .named(bbSpace)) }
                .onChange(of: g.frame(in: .named(bbSpace))) { opener.frame = $0; opener.center = center; opener.accent = accent }
        })
    }
}

extension View {
    func bbMenuOpener(_ opener: BBMenuOpener) -> some View { modifier(BBMenuOpenerHook(opener: opener)) }
}

private struct BBContextTrigger: ViewModifier {
    @Environment(\.bbMenuCenter) private var center
    @Environment(\.bbMenuAccent) private var accent
    let title: String?
    let width: CGFloat
    let items: () -> [BBMenuItem]
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { frame = g.frame(in: .named(bbSpace)) }
                    .onChange(of: g.frame(in: .named(bbSpace))) { frame = $0 }
            })
            .twoFingerTap { show() }
            .uiTestHold { show() }
    }

    private func show() {
        let list = items()
        guard !list.isEmpty else { return }
        center?.show(BBMenuSpec(anchor: frame, width: width, title: title, items: list, accent: accent))
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

private extension View {
    /// A two-finger tap or a trackpad / mouse right-click on this view. SwiftUI's own taps can't count
    /// fingers, so these are UIKit recognizers handed to SwiftUI (iPadOS 18 and later; the app's
    /// iPads run 26), which keeps them in SwiftUI's gesture system next to the button's own tap.
    /// UI tests only (BREAKBOSS_UI_PROBE): a one-second hold opens the same menu, since the simulator's
    /// synthesized two-finger tap can land its second finger on a neighbouring control.
    @ViewBuilder func uiTestHold(_ action: @escaping () -> Void) -> some View {
        if ProcessInfo.processInfo.environment["BREAKBOSS_UI_PROBE"] != nil {
            simultaneousGesture(LongPressGesture(minimumDuration: 1).onEnded { _ in action() })
        } else {
            self
        }
    }

    @ViewBuilder func twoFingerTap(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            gesture(TapRecognizer(touches: 2, action: action))
                .gesture(TapRecognizer(secondaryClick: true, action: action))
        } else {
            self
        }
    }
}

private extension View {
    /// UI tests only (BREAKBOSS_UI_PROBE): a one-second hold through a UIKit recognizer, the same kind
    /// as the right-click's, standing in for it (the simulator can't right-click). Neither a SwiftUI long
    /// press nor a normal-priority one reached the rack's header buttons.
    @ViewBuilder func uiTestPress(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            if ProcessInfo.processInfo.environment["BREAKBOSS_UI_PROBE"] != nil {
                // high priority: the button's own press otherwise keeps a one-finger hold to itself
                highPriorityGesture(HoldRecognizer(action: action))
            } else {
                self
            }
        } else {
            self
        }
    }

    /// A trackpad / mouse right-click on this view only (the track menu, Tyrone Oct 21: no two-finger
    /// tap, no hold).
    @ViewBuilder func rightClick(_ action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            gesture(TapRecognizer(secondaryClick: true, action: action))
        } else {
            self
        }
    }
}

@available(iOS 18.0, *)
private struct HoldRecognizer: UIGestureRecognizerRepresentable {
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let g = UILongPressGestureRecognizer()
        g.minimumPressDuration = 1
        return g
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began { action() }
    }
}

@available(iOS 18.0, *)
private struct TapRecognizer: UIGestureRecognizerRepresentable {
    var touches = 1
    var secondaryClick = false
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let g = UITapGestureRecognizer()
        if secondaryClick { g.buttonMaskRequired = .secondary } else { g.numberOfTouchesRequired = touches }
        return g
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }
}

private struct BBMenuHost: ViewModifier {
    @StateObject private var center = BBMenuCenter()

    func body(content: Content) -> some View {
        content
            .environmentObject(center)
            .environment(\.bbMenuCenter, center)
            .overlay(
                GeometryReader { geo in
                    if let spec = center.open, let hardware = spec.hardware {
                        // sized and placed by the view it's in (the app or the plug-in), never the screen
                        BBHardwareLayer(spec: hardware, anchor: spec.anchor, bounds: geo.size, close: { center.close() })
                            .environment(\.bbMenuCenter, center)
                            .id(spec.id)
                            .transition(.opacity)
                    } else if let spec = center.open {
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
                    .foregroundColor(spec.accent ?? M.accent)
                    .padding(.horizontal, 14).frame(height: 42)
                }
                Rectangle().fill(M.line).frame(height: 1)
            } else if let title = spec.title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(M.dim)
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
            }
            if let custom = spec.custom, center.path.isEmpty {
                custom.padding(14).environment(\.bbMenuAccent, spec.accent)
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
                    if item.checked { Image(systemName: "checkmark").foregroundColor(spec.accent ?? M.accent) }
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
    @Environment(\.bbMenuAccent) var accent

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
                    Capsule().fill(accent ?? BBMenuStyle.accent).frame(width: max(8, g.size.width * f), height: 8)
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
