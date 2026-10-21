import XCTest
import UIKit

/// Touches stay with the top window (Tyrone, Oct 20): with the SAMPLER floating over the sequencer,
/// taps on bare parts of the window (its bezel and the gaps between its panels) must not reach the
/// grid, the rack or the library behind it. The grid's lanes (its probe value) and the rack's names
/// must be the same afterwards, and the window must still be open.
final class LayersUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchEnvironment["BREAKBOSS_OPEN_SEQUENCER"] = "1"
        app.launchEnvironment["BREAKBOSS_UI_PROBE"] = "1"
        app.launch()
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func menuRow(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", prefix)).firstMatch
    }

    /// The grid's lanes as its probe lists them ("; rows pad:notes@y ...").
    private func lanes() -> String {
        let value = any("grid").value as? String ?? ""
        guard let r = value.range(of: "; rows ") else { return value }
        return value[r.upperBound...].components(separatedBy: "; grab").first.map { String($0) } ?? ""
    }

    private func rackNames() -> [String] {
        (0..<12).map { app.buttons["trackArrow\($0)"].exists ? app.buttons["trackArrow\($0)"].label : "-" }
    }

    func testSamplerWindowKeepsItsTouches() {
        let header = any("trackHeader0")
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the rack shows its first track")
        sleep(1)
        header.twoFingerTap()
        if !menuRow("Open Sample Editor").waitForExistence(timeout: 2) { header.press(forDuration: 1.2) }
        let open = menuRow("Open Sample Editor")
        XCTAssertTrue(open.waitForExistence(timeout: 3), "the track menu has Open Sample Editor")
        open.tap()
        let window = any("samplerWindow")
        XCTAssertTrue(window.waitForExistence(timeout: 5), "the sampler opens")
        sleep(2)
        let grid = lanes(), rack = rackNames()
        print("UITREE LAYERS window \(window.frame) lanes before: \(grid)")

        // the bezel all round, and the gaps between the SAMPLE page's panels
        let spots: [(CGFloat, CGFloat)] = [(0.004, 0.3), (0.004, 0.7), (0.996, 0.3), (0.996, 0.7), (0.3, 0.997), (0.7, 0.997),
                                           (0.5, 0.004), (0.501, 0.35), (0.501, 0.5), (0.501, 0.65)]
        for (x, y) in spots {
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            usleep(300_000)
        }
        sleep(1)
        let after = lanes()
        print("UITREE LAYERS lanes after: \(after)")
        XCTAssertEqual(after, grid, "no tap on the window reaches the grid behind it")
        XCTAssertEqual(rackNames(), rack, "no tap on the window reaches the rack behind it")
        XCTAssertTrue(any("samplerWindow").exists, "the window is still open")

        // the app's CPU with the window open, resting and while the sound plays (from the cursor's
        // probe; the test's own reads of the screen add some, so these are upper bounds)
        let playhead = any("samplerPlayhead")
        func cpu() -> String {
            (playhead.value as? String ?? "").components(separatedBy: " ").filter { $0.hasPrefix("cpu=") || $0.hasPrefix("frame=") }.joined(separator: " ")
        }
        sleep(4)
        print("UITREE CPU sampler open, resting (whole app, % of one core): \(cpu())")
        let wave = any("samplerWaveform").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // spaced like a player's taps (each one plays)
        for _ in 0..<6 { wave.tap(); usleep(600_000) }
        print("UITREE CPU sampler playing (whole app incl. the test's taps; frame = the animation's main-thread time per frame): \(cpu())")
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
    }
}
