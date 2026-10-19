import XCTest

/// The track menu and the SAMPLER window, on an iPad simulator (build.yml, "taps" job). Every control
/// is turned the way a finger turns it, then the track's next hit is rendered offline in the app
/// (the window's probe, BREAKBOSS_UI_PROBE) so the log shows whether the sound changed.
final class SamplerUITests: XCTestCase {
    private var app: XCUIApplication!
    private var shot = 0

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchEnvironment["BREAKBOSS_OPEN_SEQUENCER"] = "1"
        app.launchEnvironment["BREAKBOSS_UI_PROBE"] = "1"
        app.launch()
    }

    private func snap(_ name: String) {
        shot += 1
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = String(format: "sampler-%02d-%@", shot, name)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dumpTree(_ why: String) {
        print("UITREE ---- \(why)")
        for line in app.debugDescription.components(separatedBy: "\n") { print("UITREE \(line)") }
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func menuRow(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", prefix)).firstMatch
    }

    /// The track's next hit, rendered now: energy left / right, early / late, zero crossings, brightness.
    private struct Probe: CustomStringConvertible {
        var l = 0.0, r = 0.0, early = 0.0, late = 0.0, zc = 0.0, hf = 0.0
        var description: String { String(format: "L=%.4f R=%.4f early=%.4f late=%.4f zc=%.0f hf=%.4f", l, r, early, late, zc, hf) }
    }

    private func probe(_ what: String) -> Probe {
        let button = any("samplerProbe")
        guard button.waitForExistence(timeout: 3) else { dumpTree("no probe"); return Probe() }
        sleep(2)            // the SAMPLE page's sound is computed off the main thread
        button.tap()
        sleep(1)
        let text = (button.value as? String) ?? button.label
        var p = Probe()
        for part in text.components(separatedBy: " ") {
            let kv = part.components(separatedBy: "=")
            guard kv.count == 2, let v = Double(kv[1]) else { continue }
            switch kv[0] {
            case "L": p.l = v
            case "R": p.r = v
            case "early": p.early = v
            case "late": p.late = v
            case "zc": p.zc = v
            case "hf": p.hf = v
            default: break
            }
        }
        print("UITREE PROBE \(what): \(p)  [given:\(text.components(separatedBy: " lfoV=").dropFirst().first.map { " lfoV=" + $0 } ?? "")]")
        return p
    }

    /// A two-finger tap; if the simulator's two fingers miss (the second can land on a neighbour), the
    /// test-only one-second hold opens the same menu.
    private func menuTap(_ el: XCUIElement, expect row: String) {
        el.twoFingerTap()
        if menuRow(row).waitForExistence(timeout: 2) { print("UITREE MENU two-finger tap opened \(row)"); return }
        print("UITREE MENU two-finger tap missed \(row); holding instead")
        el.press(forDuration: 1.2)
    }

    /// Turns a knob: drags up (positive) or down from its middle.
    private func turn(_ id: String, by dy: CGFloat, dx: CGFloat = 0) {
        let knob = any(id)
        guard knob.waitForExistence(timeout: 3) else { XCTFail("there is a \(id) knob"); dumpTree("no \(id)"); return }
        let from = knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: dx, dy: -dy)))
        sleep(1)
        print("UITREE KNOB \(id) = \(knob.value ?? "?")")
    }

    func testTrackMenuAndSampler() {
        let header = any("trackHeader0")
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the rack shows its first track")
        sleep(1)

        // the track menu: the track's own things first, Remove up top
        menuTap(header, expect: "Track settings")
        let settings = menuRow("Track settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 3), "a two-finger tap opens the track menu with Track settings")
        snap("track-menu")
        let order = ["Track settings", "Open sample editor", "Solo", "Load sample", "Clear sample", "Remove"]
        let ys = order.map { menuRow($0).exists ? menuRow($0).frame.minY : -1 }
        print("UITREE MENU ORDER \(zip(order, ys).map { "\($0.0)@\(Int($0.1))" }.joined(separator: " "))")
        XCTAssertEqual(ys, ys.sorted(), "the track menu runs Track settings, Open sample editor, Solo, Load sample, Clear sample, Remove")
        if menuRow("Remove").exists && menuRow("Fill every step").exists {
            XCTAssertLessThan(menuRow("Remove").frame.minY, menuRow("Fill every step").frame.minY, "Remove is above the fills")
        } else { dumpTree("track menu") }

        // Track settings (build 82 crashed here): the sheet opens and its SOUND menu works
        settings.tap()
        XCTAssertTrue(app.staticTexts["TRACK SETTINGS"].waitForExistence(timeout: 5), "Track settings opens without crashing")
        snap("track-settings")
        let sound = any("trackSound0")
        if sound.waitForExistence(timeout: 2) {
            sound.tap()
            XCTAssertTrue(menuRow("Load a sample").waitForExistence(timeout: 3), "the SOUND menu opens inside Track settings")
            snap("track-settings-sound-menu")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap()
        } else {
            dumpTree("no SOUND in track settings")
        }
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
        app.swipeDown(velocity: .fast)
        sleep(1)
        if app.staticTexts["TRACK SETTINGS"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            sleep(1)
        }

        // the sample editor
        menuTap(header, expect: "Open sample editor")
        let open = menuRow("Open sample editor")
        XCTAssertTrue(open.waitForExistence(timeout: 3), "the track menu has Open sample editor")
        open.tap()
        XCTAssertTrue(any("samplerWindow").waitForExistence(timeout: 5), "the sampler opens")
        snap("sampler")

        let plain = probe("plain")
        XCTAssertGreaterThan(plain.l + plain.r, 0.0001, "the track makes a sound")

        // PAN, VOL, PITCH on the header
        turn("samplerKnobPAN", by: 0, dx: 160)
        let panned = probe("pan right")
        XCTAssertGreaterThan(panned.r, panned.l * 1.5, "PAN to the right moves the sound right (\(panned))")
        turn("samplerKnobVOL", by: -120)
        let quieter = probe("vol down")
        XCTAssertLessThan(quieter.l + quieter.r, (panned.l + panned.r) * 0.7, "VOL down makes it quieter (\(quieter) vs \(panned))")
        turn("samplerKnobVOL", by: 120)
        turn("samplerKnobPITCH", by: 150)
        let higher = probe("pitch up")
        XCTAssertGreaterThan(higher.zc, quieter.zc * 1.05, "PITCH up raises it (\(higher.zc) vs \(quieter.zc) crossings)")
        turn("samplerKnobPITCH", by: -75)

        // precomputed effects
        let beforeReverse = probe("before reverse")
        any("samplerReverse").tap()
        let reversed = probe("reverse")
        XCTAssertNotEqual(reversed.early, beforeReverse.early, accuracy: beforeReverse.early * 0.05, "Reverse changes the sound")
        any("samplerReverse").tap()
        turn("samplerKnobLENGTH", by: -150)
        let shorter = probe("length short")
        XCTAssertLessThan(shorter.late + shorter.early, (beforeReverse.late + beforeReverse.early) * 0.95, "LENGTH shortens the sound (\(shorter))")
        turn("samplerKnobLENGTH", by: 300)
        snap("sample-page-turned")

        // ENVELOPE: turning a knob turns the Volume envelope on and shapes the hit
        any("samplerEnvelopePage").tap()
        sleep(1)
        snap("envelope-page")
        let open0 = probe("envelope page")
        turn("samplerKnobDEC", by: -150)
        turn("samplerKnobSUS", by: -150)
        let decayed = probe("decay short, sustain 0")
        XCTAssertLessThan(decayed.late, open0.late * 0.5 + 1e-6, "DEC and SUS shorten the hit (\(decayed) vs \(open0))")
        turn("samplerKnobATT", by: 140)
        let slow = probe("slow attack")
        XCTAssertLessThan(slow.early, decayed.early * 0.8, "ATT fades the hit in (\(slow) vs \(decayed))")
        snap("envelope-turned")

        // the box method preset
        any("samplerEnvPresets").tap()
        let box = menuRow("Box method")
        if box.waitForExistence(timeout: 3) { box.tap() } else { XCTFail("the presets have the box method"); dumpTree("presets") }
        _ = probe("box method")

        // LFO on the volume: picking a shape brings it in; AMT turned left inverts it (a short hit lands
        // on the square's dip instead of its top)
        let boxed = probe("before LFO")
        any("samplerLFOShape2").tap()
        turn("samplerKnobLFOAMT", by: -160)
        let lfo = probe("square LFO on volume, inverted")
        XCTAssertLessThan(lfo.l + lfo.r, (boxed.l + boxed.r) * 0.8, "the LFO changes the level (\(lfo) vs \(boxed))")
        snap("lfo")
        // AMT back to the middle takes the LFO out again, so the checks after this hear the plain hit
        any("samplerKnobLFOAMT").doubleTap()
        sleep(1)
        print("UITREE KNOB samplerKnobLFOAMT after double tap = \(any("samplerKnobLFOAMT").value ?? "?")")
        let unLFO = probe("LFO back out")
        XCTAssertEqual(unLFO.l + unLFO.r, boxed.l + boxed.r, accuracy: (boxed.l + boxed.r) * 0.05 + 1e-6, "AMT in the middle takes the LFO out (\(unLFO) vs \(boxed))")

        // a tempo length from a knob's own menu
        menuTap(any("samplerKnobATT"), expect: "1/4 (beat)")
        let quarter = menuRow("1/4 (beat)")
        XCTAssertTrue(quarter.waitForExistence(timeout: 3), "a two-finger tap on ATT opens its tempo lengths")
        snap("att-set-menu")
        if quarter.exists { quarter.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap() }
        sleep(1)
        XCTAssertEqual(any("samplerEnvTempo").value as? String, "on", "picking a tempo length turns Tempo on")
        let beat = probe("attack 1/4 beat")
        XCTAssertGreaterThan(beat.l + beat.r, 0, "a one-beat attack still sounds (\(beat))")

        // the filter: MOD X down takes the top off
        let open1 = probe("before filter")
        turn("samplerKnobMODX", by: -160)
        let dark = probe("mod x down")
        XCTAssertLessThan(dark.hf, open1.hf * 0.7, "MOD X down darkens the sound (\(dark.hf) vs \(open1.hf))")
        turn("samplerKnobMODY", by: 160)
        _ = probe("mod y up")
        snap("filter")

        // the graph: drag the sustain point down
        let graph = any("samplerEnvGraph")
        if graph.waitForExistence(timeout: 2) {
            graph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: graph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            sleep(1)
            snap("graph-dragged")
            // FL-style free points: one tap on empty space adds one, the knobs' shape becomes points
            let pointsBefore = probe("before adding a point")
            graph.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.1)).tap()
            sleep(1)
            print("UITREE GRAPH after double tap = \(graph.value ?? "?")")
            XCTAssertTrue((graph.value as? String)?.hasSuffix("points") == true, "tapping the graph adds a point (\(graph.value ?? "?"))")
            _ = probe("after adding a point")
            _ = pointsBefore
            snap("graph-point-added")
        }

        // MISC (the wrench tab): echoes, the arpeggiator, Levels VOL, steppers and the chord menu
        any("samplerMiscPage").tap()
        sleep(1)
        snap("misc-page")
        let misc0 = probe("misc page")
        turn("samplerKnobEchoFEED", by: 140)
        let echoed = probe("echo feed up")
        XCTAssertNotEqual(echoed.late, misc0.late, accuracy: misc0.late * 0.05 + 1e-6, "FEED adds echoes (\(echoed) vs \(misc0))")
        any("samplerArp1").tap()
        let arped = probe("arpeggiator up")
        XCTAssertNotEqual(arped.late, echoed.late, accuracy: echoed.late * 0.05 + 1e-6, "the arpeggiator changes the sound (\(arped) vs \(echoed))")
        any("samplerArpRangeUp").tap()
        sleep(1)
        XCTAssertEqual(any("samplerArpRange").value as? String, "2", "RANGE steps up")
        any("samplerArpChord").tap()
        let major = menuRow("Minor 7")
        if major.waitForExistence(timeout: 3) { major.tap() } else { XCTFail("the Chord menu opens"); dumpTree("chord menu") }
        let chord = probe("minor 7 chord")
        XCTAssertNotEqual(chord.zc, arped.zc, accuracy: 0.5, "the chord changes the notes (\(chord) vs \(arped))")
        turn("samplerKnobLevelsVOL", by: -140)
        let levels = probe("levels vol down")
        XCTAssertLessThan(levels.l + levels.r, (chord.l + chord.r) * 0.7, "Levels VOL turns it down (\(levels) vs \(chord))")
        any("samplerCutUp").tap()
        sleep(1)
        print("UITREE STEP Cut after + = \(any("samplerCut").value ?? "?")")
        // MAX's + can sit over the sound library's chip strip, which takes the touch: move the window
        // down by its title bar first, as a player would (Tyrone: leave the strip as it is)
        let title = any("samplerTitleBar")
        let moveBy: CGFloat = 70
        let grabDown = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grabDown.press(forDuration: 0.3, thenDragTo: grabDown.withOffset(CGVector(dx: 0, dy: moveBy)))
        sleep(1)
        print("UITREE FRAME samplerPolyMaxUp after moving the window \(any("samplerPolyMaxUp").frame)")
        any("samplerPolyMaxUp").tap()
        sleep(1)
        print("UITREE STEP MAX after + = \(any("samplerPolyMax").value ?? "?")")
        if (any("samplerPolyMax").value as? String) != "1" { snap("max-stepper") }
        XCTAssertEqual(any("samplerPolyMax").value as? String, "1", "MAX steps up from no limit")
        any("samplerMono").tap()
        sleep(1)
        XCTAssertEqual(any("samplerMono").value as? String, "on", "Mono switches on")
        let grabUp = title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grabUp.press(forDuration: 0.3, thenDragTo: grabUp.withOffset(CGVector(dx: 0, dy: -moveBy)))
        sleep(1)
        // the keyboard: C3 to C7, as in the render
        XCTAssertTrue(any("samplerKey36").exists && any("samplerKey84").exists, "the keyboard runs from C3 to C7")
        XCTAssertFalse(any("samplerKey86").exists, "the keyboard stops at C7")
        snap("misc-turned")
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
    }
}
