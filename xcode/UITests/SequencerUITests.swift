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

    /// What's on screen, in the build log (lines start with UITREE) when a step fails.
    private func dumpTree(_ why: String) {
        print("UITREE ---- \(why)")
        for line in app.debugDescription.components(separatedBy: "\n") { print("UITREE \(line)") }
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// The text shown on a control (its StaticText, not its picture's name).
    private func label(_ id: String) -> String {
        app.staticTexts.matching(identifier: id).firstMatch.label
    }

    func testSequencerControls() {
        let arrow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'trackArrow'")).firstMatch
        XCTAssertTrue(arrow.waitForExistence(timeout: 20), "the sequencer opens with a track arrow")
        sleep(1)
        snap("sequencer")
        XCTAssertEqual(any("brandLogo").label, "BreaKing", "the sequencer wears the BreaKing logo")

        // GENERATE slides up over the sound library and back down
        any("generateHeader").tap()
        sleep(1)
        snap("generate-open")
        any("soundsHeader").tap()
        sleep(1)
        snap("sounds-open")

        // the power button turns the sequencer and pads off, then back on
        let power = app.buttons["powerButton"]
        XCTAssertTrue(power.exists, "there is a power button")
        power.tap()
        sleep(1)
        XCTAssertTrue(power.label.hasPrefix("Power off"), "one tap turns everything off")
        snap("power-off")
        power.tap()
        sleep(1)
        XCTAssertTrue(power.label.hasPrefix("Power on"), "a second tap turns it back on")

        // draw a note, then UNDO takes it away and REDO brings it back
        let grid = any("grid")
        let notes = { grid.value as? String ?? "" }
        let blank = notes()
        grid.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 14)).tap()
        sleep(1)
        let drawn = notes()
        XCTAssertNotEqual(drawn, blank, "a tap on the grid draws a note (still \(blank))")
        snap("note-drawn")
        app.buttons["undoButton"].tap()
        sleep(1)
        XCTAssertEqual(notes(), blank, "UNDO takes the note away")
        app.buttons["redoButton"].tap()
        sleep(1)
        XCTAssertEqual(notes(), drawn, "REDO puts it back")
        snap("undo-redo")

        // the arrow opens the track's VELOCITY graph
        arrow.tap()
        XCTAssertTrue(app.buttons["laneVelocity"].waitForExistence(timeout: 3), "the arrow opens the velocity graph")
        XCTAssertTrue(app.staticTexts["DRAG A BAR UP OR DOWN"].exists, "the velocity graph shows")
        snap("arrow-opens-velocity")

        // PITCH shows the notes on a piano roll with KEY / SCALE / SNAP
        app.buttons["lanePitch"].tap()
        XCTAssertTrue(app.buttons["SNAP"].waitForExistence(timeout: 3), "PITCH opens the piano roll with SNAP")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'KEY'")).firstMatch.exists, "the piano roll has KEY")
        snap("pitch-piano-roll")
        app.buttons["laneVelocity"].tap()
        XCTAssertTrue(app.staticTexts["DRAG A BAR UP OR DOWN"].waitForExistence(timeout: 3), "VELOCITY goes back to the graph")

        // the arrow closes it again
        arrow.tap()
        sleep(1)
        XCTAssertFalse(app.buttons["laneVelocity"].exists, "the arrow closes the graph")
        snap("arrow-closes")

        // pattern length 2 / 4 / 8 / 16
        let barsChip = any("barsChip")
        XCTAssertTrue(barsChip.exists, "there is a BARS chip")
        barsChip.tap()
        let four = app.buttons.matching(NSPredicate(format: "label CONTAINS '4 BARS'")).firstMatch
        let opened = four.waitForExistence(timeout: 3)
        XCTAssertTrue(opened, "the BARS chip opens the length menu")
        snap("bars-menu")
        if opened { four.tap() } else { dumpTree("after tapping BARS") }
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

        // a tap on the BPM chip still opens the tempo panel
        chip.tap()
        XCTAssertTrue(app.staticTexts["TEMPO"].waitForExistence(timeout: 3), "a tap on the BPM chip opens the tempo panel")
        snap("tempo-panel")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()   // close the panel
        sleep(1)

        // drag the silver tab of the first track down two places: it moves straight away, no hold
        let kickY = app.buttons["trackArrow0"].frame.midY
        let grip = app.buttons["trackArrow0"]
        XCTAssertTrue(grip.exists, "every track has its tab on the left")
        let rowH = app.buttons["trackArrow1"].frame.midY - kickY
        grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: rowH * 2.2)))
        sleep(1)
        XCTAssertGreaterThan(app.buttons["trackArrow0"].frame.midY, kickY + rowH, "the dragged track moved down the rack")
        snap("track-moved")

        // slide the platinum knob to the right: back to Face 1
        let slider = any("faceSlider")
        XCTAssertTrue(slider.exists, "there is the Face 1 slider")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5)))
        sleep(2)
        XCTAssertFalse(arrow.exists, "sliding right goes back to Face 1")
        XCTAssertTrue(any("brandLogo").exists, "Face 1 wears the BreaKing logo")
        snap("back-to-face-1")
    }
}
