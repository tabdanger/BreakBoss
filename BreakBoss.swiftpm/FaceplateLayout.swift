// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import CoreGraphics
import Foundation

/// Control positions in the original artwork's own pixels. Tablet and phone layouts use
/// the same controller, parameters and pad IDs; only the artwork and coordinates differ.
struct FaceplateLayout: Decodable {
    enum Device: String, Decodable { case tablet, phone }

    struct Knob: Decodable {
        let x: Double
        let y: Double
        let r: Double
        let pointerInner: Double
        let pointerOuter: Double
        let bakedAngle: Double?
    }

    struct LEDs: Decodable {
        let tempoSyncRect: [Double]
        let followDAWRect: [Double]
    }

    let size: [Double]
    let device: Device?
    let knobs: [String: Knob]
    let scope: [Double]
    let bpmDigits: [Double]
    let bpmLabelX: Double
    let bpmBox: [Double]
    let textColor: [Double]
    let kitBox: [Double]
    let kitText: [Double]
    let presetBox: [Double]
    let presetText: [Double]
    let leds: LEDs
    let oneShotButton: [Double]
    let loopButton: [Double]
    let clipperRect: [Double]
    let playRect: [Double]
    let diceRect: [Double]
    let saveRect: [Double]
    let exportRect: [Double]
    let menuRect: [Double]
    let modeButtons: [String: [Double]]
    /// Artwork positions in reading order. Pad IDs are independent of the device layout.
    let pads: [[Double]]
    let padOrder: [Int]?

    var width: Double { size[0] }
    var height: Double { size[1] }
    var isPhone: Bool { device == .phone }

    func plateImageName(for mode: SoundMode) -> String {
        "\(isPhone ? "PhonePlate" : "Plate")_\(mode.assetSuffix)"
    }

    /// State overlays cut from the same plate: "oneshot_on_modern" or "phone_oneshot_on_modern".
    func overlayName(_ kind: String, _ suffix: String) -> String {
        "\(isPhone ? "phone_" : "")\(kind)_\(suffix)"
    }

    static func rect(_ r: [Double]) -> CGRect {
        guard r.count == 4 else { return .zero }
        return CGRect(x: r[0], y: r[1], width: r[2] - r[0], height: r[3] - r[1])
    }

    /// Pad index (0 = pad 1 bottom-left) for a layout position (0 = top-left).
    static func padIndex(forLayoutPosition i: Int) -> Int { i < 6 ? i + 6 : i - 6 }

    func padIndex(forLayoutPosition i: Int) -> Int {
        if let order = padOrder, order.indices.contains(i) { return order[i] }
        return Self.padIndex(forLayoutPosition: i)
    }

    static let all: [String: FaceplateLayout] = {
        load("KnockLayout")
    }()

    static let phone: [String: FaceplateLayout] = {
        load("PhoneKnockLayout")
    }()

    private static func load(_ name: String) -> [String: FaceplateLayout] {
        guard let url = knockResourceURL(name, "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: FaceplateLayout].self, from: data) else { return [:] }
        return decoded
    }

    static func forMode(_ mode: SoundMode, device: Device = .tablet) -> FaceplateLayout? {
        (device == .phone ? phone : all)[mode.assetSuffix]
    }
}

/// Swift Playgrounds doesn't always make SwiftPM's resource accessor for app packages, and
/// may put processed resources in the app, in a Resources folder or in a .bundle: look everywhere.
func knockResourceURL(_ name: String, _ ext: String) -> URL? {
    let filename = "\(name).\(ext)"
    for bundle in [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks {
        if let url = bundle.url(forResource: name, withExtension: ext) { return url }
    }
    guard let root = Bundle.main.resourceURL else { return nil }
    for candidate in [root.appendingPathComponent(filename), root.appendingPathComponent("Resources").appendingPathComponent(filename)]
    where FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
    }
    if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
        for case let url as URL in walker where url.lastPathComponent == filename { return url }
    }
    return nil
}
