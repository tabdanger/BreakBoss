import XCTest
import UIKit

/// Opens the SAMPLER from every rack track's menu ("Open sample editor") and closes it again
/// (Tyrone, Oct 21: build 113 crashed on Open sample editor). The app must still be running after each.
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
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", prefix)).firstMatch
    }

    func testOpenSampleEditorOnEveryTrack() {
        XCTAssertTrue(any("trackHeader0").waitForExistence(timeout: 20), "the rack shows its first track")
        sleep(1)
        for i in 0..<12 {
            let header = any("trackHeader\(i)")
            guard header.exists, header.isHittable else { print("UITREE OPEN track \(i): not on screen"); continue }
            header.twoFingerTap()
            if !menuRow("Open sample editor").waitForExistence(timeout: 2) { header.press(forDuration: 1.2) }
            let open = menuRow("Open sample editor")
            guard open.waitForExistence(timeout: 3) else { print("UITREE OPEN track \(i): no menu"); continue }
            open.tap()
            let opened = any("samplerWindow").waitForExistence(timeout: 5)
            sleep(2)
            let running = app.state == .runningForeground
            print("UITREE OPEN track \(i): opened=\(opened) running=\(running) info=\(any("samplerFileInfo").exists ? any("samplerFileInfo").label : "-")")
            XCTAssertTrue(running, "the app is still running after Open sample editor on track \(i)")
            guard running else { return }
            XCTAssertTrue(opened, "the sampler opens for track \(i)")
            // every page
            for tab in ["ENVELOPE", "MISC", "SAMPLE"] {
                let t = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", tab)).firstMatch
                if t.exists { t.tap(); sleep(1) }
                XCTAssertEqual(app.state, .runningForeground, "the app is still running on \(tab), track \(i)")
            }
            if any("samplerClose").exists { any("samplerClose").tap() }
            sleep(1)
        }
    }
}
