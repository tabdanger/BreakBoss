import XCTest

/// Taps the sequencer the way Tyrone does, on an iPad simulator on GitHub's Mac (build.yml, "taps" job).
/// Every step leaves a screenshot, so a broken control shows up as a picture, not a guess.
final class SequencerUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shot = 0

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchEnvironment["BREAKBOSS_OPEN_SEQUENCER"] = "1"
        app.launch()
    }

    private func snap(_ name: String) {
        shot += 1
        let image = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = String(format: "%02d-%@", shot, name)
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["SHOTS"] {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? image.pngRepresentation.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(attachment.name ?? name).png"))
        }
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func label(_ id: String) -> String {
        let e = any(id)
        if !e.label.isEmpty { return e.label }
        return e.staticTexts.firstMatch.label
    }

    func testSequencerControls() {
        let arrow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trackArrow'")).firstMatch
        XCTAssertTrue(arrow.waitForExistence(timeout: 20), "the sequencer opens with a track arrow")
        sleep(1)
        snap("sequencer")

        // the arrow opens the track's VELOCITY graph
        arrow.tap()
        XCTAssertTrue(app.buttons["laneVelocity"].waitForExistence(timeout: 3), "the arrow opens the velocity graph")
        XCTAssertTrue(app.staticTexts["DRAG A BAR UP OR DOWN"].exists, "the velocity graph shows")
        snap("arrow-opens-velocity")

        // PITCH shows the notes on a piano roll with KEY / SCALE / SNAP
        app.buttons["lanePitch"].tap()
        XCTAssertTrue(app.buttons["SNAP"].waitForExistence(timeout: 3), "PITCH opens the piano roll with SNAP")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'KEY'")).firstMatch.exists, "the piano roll has KEY")
        snap("pitch-piano-roll")
        app.buttons["laneVelocity"].tap()
        XCTAssertTrue(app.staticTexts["DRAG A BAR UP OR DOWN"].waitForExistence(timeout: 3), "VELOCITY goes back to the graph")

        // the arrow closes it again
        arrow.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["laneVelocity"].exists, "the arrow closes the graph")
        snap("arrow-closes")

        // pattern length 2 / 4 / 8 / 16
        any("barsChip").tap()
        let four = app.buttons["4 BARS"]
        XCTAssertTrue(four.waitForExistence(timeout: 3), "the BARS chip opens the length menu")
        snap("bars-menu")
        four.tap()
        sleep(1)
        XCTAssertTrue(label("barsChip").contains("4"), "the chip says 4 BARS (it says \(label("barsChip")))")
        snap("four-bars")

        // slide along the longer pattern: drag the beat numbers
        let before = label("pageLabel")
        let ruler = any("ruler")
        let from = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        sleep(1)
        XCTAssertNotEqual(label("pageLabel"), before, "dragging the beat numbers slides the grid (still \(before))")
        snap("slid-sideways")

        // tempo: slide the BPM chip up
        let bpmBefore = label("tempoChip")
        let chip = any("tempoChip")
        chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -3)))
        sleep(1)
        XCTAssertNotEqual(label("tempoChip"), bpmBefore, "sliding the BPM chip changes the tempo (still \(bpmBefore))")
        snap("tempo-slid")
    }
}
