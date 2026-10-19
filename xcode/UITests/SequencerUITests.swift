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

        // hold the note and pull down: the step repeats (more hits the further down)
        let step = grid.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 20, dy: 14))
        step.press(forDuration: 0.15, thenDragTo: step.withOffset(CGVector(dx: 0, dy: 50)))
        sleep(1)
        let count = { (text: String) in Int(text.components(separatedBy: " ").first ?? "") ?? 0 }
        XCTAssertGreaterThan(count(notes()), count(drawn), "pulling a step down repeats it (\(drawn) -> \(notes()))")
        snap("note-repeat")
        app.buttons["undoButton"].tap()
        sleep(1)
        XCTAssertEqual(notes(), drawn, "UNDO takes the repeats away")

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

        // tempo: slide the BPM chip down (the chip sits near the top edge, so a slide up can run off the screen)
        let bpmBefore = label("tempoChip")
        let chip = any("tempoChip")
        print("UITREE FRAME tempoChip \(chip.frame)")
        chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: chip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 90)))
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

    /// The piano roll reaches C1 to C8 (Tyrone, Oct 18): ⊕ / ⊖ beside the keys move them an octave,
    /// and a two-finger tap on a note shows ⊕ over it and ⊖ under it to move the note an octave.
    func testPianoRollOctaves() {
        let arrow = app.buttons["trackArrow0"]
        XCTAssertTrue(arrow.waitForExistence(timeout: 20), "the sequencer opens with the first track's arrow")
        sleep(1)
        arrow.tap()
        XCTAssertTrue(app.buttons["lanePitch"].waitForExistence(timeout: 3), "the arrow opens the lanes")
        app.buttons["lanePitch"].tap()
        let keysUp = app.buttons["rollOctaveUp"], keysDown = app.buttons["rollOctaveDown"]
        XCTAssertTrue(keysUp.waitForExistence(timeout: 3), "the piano roll has a plus beside its keys")
        XCTAssertTrue(keysDown.exists, "and a minus")
        let keys = { keysUp.value as? String ?? "" }
        print("UITREE piano roll opens on \(keys())")
        let opened = keys()
        XCTAssertTrue(opened.range(of: "^C[0-9] to C[0-9]$", options: .regularExpression) != nil, "the keys run C to C (\(opened))")
        snap("roll-open")

        for _ in 0..<8 where keysDown.isEnabled { keysDown.tap() }
        XCTAssertEqual(keys(), "C1 to C3", "minus takes the keys down to C1")
        XCTAssertFalse(keysDown.isEnabled, "and no lower")
        snap("roll-C1")
        for _ in 0..<8 where keysUp.isEnabled { keysUp.tap() }
        XCTAssertEqual(keys(), "C6 to C8", "plus takes the keys up to C8")
        XCTAssertFalse(keysUp.isEnabled, "and no higher")
        snap("roll-C8")
        while keysDown.isEnabled && keys() != opened { keysDown.tap() }
        XCTAssertEqual(keys(), opened, "back where it opened")

        // draw a note where a two-finger tap on the grid lands (the middle of the grid on screen)
        let grid = any("grid")
        let notes = { grid.value as? String ?? "" }
        let count = { Int(notes().components(separatedBy: " ").first ?? "") ?? -1 }
        let blank = count()
        let s = grid.frame.width / 950
        grid.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 475 * s + 20, dy: 212 * s)).tap()
        sleep(1)
        XCTAssertEqual(count(), blank + 1, "a tap in the piano roll draws a note")
        snap("roll-note")

        // a two-finger tap (right-click) on the note opens the grid's menu (Tyrone, Oct 19); its Octave up
        // moves the note and leaves ⊕ over it and ⊖ under it for more moves
        grid.twoFingerTap()
        let octaveUp = app.staticTexts["Octave up"]
        if !octaveUp.waitForExistence(timeout: 3) { dumpTree("after the two-finger tap (grid \(grid.frame))") }
        XCTAssertTrue(octaveUp.exists, "a two-finger tap on the note opens the menu")
        for row in ["Select all", "Copy", "Paste", "Octave down"] { XCTAssertTrue(app.staticTexts[row].exists, "the menu has \(row)") }
        XCTAssertEqual(count(), blank + 1, "the two-finger tap doesn't draw or erase a note")
        snap("grid-menu")
        octaveUp.tap()
        sleep(1)
        let noteUp = app.buttons["noteOctaveUp"], noteDown = app.buttons["noteOctaveDown"]
        XCTAssertTrue(noteUp.waitForExistence(timeout: 3), "after Octave up the note shows a plus over it")
        XCTAssertTrue(noteDown.exists, "and a minus under it")
        let name = { noteUp.exists ? (noteUp.value as? String ?? "") : "gone" }
        print("UITREE glyph up \(noteUp.frame) down \(noteDown.frame) grid \(grid.frame) hittable \(noteUp.isHittable)")
        let raised = name()
        print("UITREE note after Octave up \(raised), keys \(keys())")
        // the note's glyphs are pictures over the grid (the grid takes the touch): tap where they are
        func press(_ e: XCUIElement) { e.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        func octave(_ n: String, _ by: Int) -> String {
            let letters = n.prefix { !$0.isNumber && $0 != "-" }
            return "\(letters)\((Int(n.dropFirst(letters.count)) ?? 0) + by)"
        }
        snap("note-up")
        press(noteDown)
        sleep(1)
        XCTAssertEqual(name(), octave(raised, -1), "minus moves it back down an octave")
        XCTAssertEqual(count(), blank + 1, "moving octaves keeps one note")
        snap("note-down")

        // UNDO takes the two octave moves and the note away
        for _ in 0..<3 { app.buttons["undoButton"].tap() }
        sleep(1)
        XCTAssertEqual(count(), blank, "UNDO takes the octave moves and the note away")

        // DRAW mode: a quick drag from an empty spot draws a selection box, not notes (Tyrone, Oct 19)
        let spot = grid.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 475 * s + 20, dy: 212 * s))
        spot.tap()
        sleep(1)
        XCTAssertEqual(count(), blank + 1, "a tap draws the note again")
        spot.withOffset(CGVector(dx: -70 * s, dy: -14 * s)).press(forDuration: 0.05, thenDragTo: spot.withOffset(CGVector(dx: 70 * s, dy: 14 * s)))
        sleep(1)
        print("UITREE after the draw-mode box: \(notes())")
        XCTAssertEqual(count(), blank + 1, "the box draws no notes")
        XCTAssertFalse(notes().hasSuffix(" 0 selected"), "the box selects the note (\(notes()))")
        snap("draw-box-selected")
        app.buttons["undoButton"].tap()
        sleep(1)
        XCTAssertEqual(count(), blank, "UNDO takes the note away")
        arrow.tap()
    }

}
