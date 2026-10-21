import XCTest
import UIKit

/// The track menu's Open Sample Editor (Tyrone, Oct 21: on 113 it crashed, on 116 it didn't open):
/// a hold on track 1's name opens the menu, Open Sample Editor opens the SAMPLER, and the app keeps running.
/// Also Face 1's power button beside the slider, as a picture (UITREE IMG lines), on and off.
final class SamplerOpenUITests: XCTestCase {
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
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", prefix)).firstMatch
    }

    /// Every element whose frame holds `p` (what sits over a control that isn't hittable).
    private func dumpAt(_ p: CGPoint, _ what: String) {
        for e in app.descendants(matching: .any).allElementsBoundByIndex where e.frame.contains(p) && e.frame.width < 900 {
            print("UITREE AT \(what) \(e.elementType.rawValue) id=\(e.identifier) label=\(e.label) frame=\(e.frame) hittable=\(e.isHittable)")
        }
    }

    func testOpenSampleEditorFromTrackMenu() {
        let header = any("trackHeader0")
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the rack shows its first track")
        sleep(1)
        print("UITREE HEADER frame=\(header.frame) hittable=\(header.isHittable)")
        if !header.isHittable { dumpAt(CGPoint(x: header.frame.midX, y: header.frame.midY), "header") }
        // a hold opens the menu (the same panel a right-click or a two-finger tap opens)
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1.0)
        let open = menuRow("Open Sample Editor")
        let shown = open.waitForExistence(timeout: 3)
        print("UITREE MENU shown=\(shown) hittable=\(shown && open.isHittable) frame=\(shown ? open.frame : .zero)")
        XCTAssertTrue(shown, "a hold on the track opens its menu with Open Sample Editor")
        guard shown else { return }
        if !open.isHittable { dumpAt(CGPoint(x: open.frame.midX, y: open.frame.midY), "row") }
        open.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let opened = any("samplerWindow").waitForExistence(timeout: 5)
        sleep(1)
        print("UITREE SAMPLER opened=\(opened) running=\(app.state == .runningForeground) menuStill=\(menuRow("Open Sample Editor").exists)")
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
        XCTAssertTrue(opened, "Open Sample Editor opens the sampler")
    }

    func testFace1PowerButton() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments += ["-breakboss.tutorialSeen", "YES"]
        app.launch()
        sleep(3)
        let power = any("powerButton1")
        XCTAssertTrue(power.waitForExistence(timeout: 10), "Face 1 has its power button")
        print("UITREE POWER frame=\(power.frame) slider=\(any("faceSlider1").frame)")
        picture("power-on", around: power)
        power.tap()
        sleep(1)
        picture("power-off", around: power)
        power.tap()
        sleep(1)
    }

    /// The screen near `element`, upright, as a JPEG printed in pieces (UITREE IMG <name> <part>/<parts> <base64>).
    private func picture(_ name: String, around element: XCUIElement) {
        let raw = XCUIScreen.main.screenshot().image
        let rotate = (raw.size.width < raw.size.height) != (app.frame.width < app.frame.height)
        let upright = rotate ? CGSize(width: raw.size.height, height: raw.size.width) : raw.size
        let k = upright.width / app.frame.width
        let f = element.frame
        let crop = CGRect(x: (f.minX - 160) * k, y: (f.minY - 70) * k, width: (f.width + 320) * k, height: (f.height + 120) * k)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let image = UIGraphicsImageRenderer(size: crop.size, format: fmt).image { r in
            r.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            if rotate {
                r.cgContext.translateBy(x: 0, y: raw.size.width)
                r.cgContext.rotate(by: -.pi / 2)
            }
            raw.draw(at: .zero)
        }
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let text = data.base64EncodedString()
        let piece = 6_000
        let parts = (text.count + piece - 1) / piece
        var i = text.startIndex, n = 1
        while i < text.endIndex {
            let j = text.index(i, offsetBy: piece, limitedBy: text.endIndex) ?? text.endIndex
            print("UITREE IMG \(name) \(n)/\(parts) \(text[i..<j])")
            i = j; n += 1
        }
    }
}
