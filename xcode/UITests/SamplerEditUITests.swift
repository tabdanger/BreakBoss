import XCTest
import UIKit

/// The SAMPLER's edit bar above the waveform (Tyrone, Oct 20: every tool works): ALL selects the whole
/// sound, COPY + PASTE (mix) merges the copy into what's there (louder, same length), CUT and DELETE
/// take a selection out (shorter), FADE IN / FADE OUT change the hit's level at the start / end, TRIM
/// runs. Each edit is put back with the title bar's UNDO, so later tests find track 1 as it was.
/// Lengths come from the waveform's readout ("name · 0.127 s"), levels from the window's probe.
// Named to run before SamplerUITests (the app keeps its settings between launches).
final class SamplerEditUITests: XCTestCase {
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

    /// The sound's length in seconds and its file name, from the waveform's readout.
    private func info() -> (name: String, seconds: Double) {
        let text = any("samplerFileInfo").label
        let parts = text.components(separatedBy: "·")
        let secs = Double(parts.last?.replacingOccurrences(of: "s", with: "").trimmingCharacters(in: .whitespaces) ?? "") ?? -1
        return (parts.first?.trimmingCharacters(in: .whitespaces) ?? text, secs)
    }

    /// The track's next hit rendered now: (left + right energy, early, late).
    private func probe(_ what: String) -> (energy: Double, early: Double, late: Double) {
        let button = any("samplerProbe")
        guard button.waitForExistence(timeout: 3) else { return (0, 0, 0) }
        sleep(2)
        button.tap()
        sleep(1)
        let text = (button.value as? String) ?? button.label
        var v: [String: Double] = [:]
        for part in text.components(separatedBy: " ") {
            let kv = part.components(separatedBy: "=")
            if kv.count == 2, let x = Double(kv[1]) { v[kv[0]] = x }
        }
        let p = ((v["L"] ?? 0) + (v["R"] ?? 0), v["early"] ?? 0, v["late"] ?? 0)
        print("UITREE EDIT PROBE \(what): energy=\(p.0) early=\(p.1) late=\(p.2)  info=\(info())")
        return p
    }

    private func waitForEdit(from before: String, _ what: String) {
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 8 && info().name == before { usleep(300_000) }
        sleep(1)
        print("UITREE EDIT \(what): \(info())")
    }

    private func undo(_ what: String, back to: (name: String, seconds: Double)) {
        any("samplerUndo").tap()
        sleep(2)
        XCTAssertEqual(info().name, to.name, "UNDO puts the sound back after \(what)")
        XCTAssertEqual(info().seconds, to.seconds, accuracy: 0.0005, "UNDO puts the length back after \(what)")
    }

    /// Selects a part of the waveform by dragging across it (0…1 of its width).
    private func select(_ a: CGFloat, _ b: CGFloat) {
        let wave = any("samplerWaveform")
        wave.coordinate(withNormalizedOffset: CGVector(dx: a, dy: 0.6))
            .press(forDuration: 0.15, thenDragTo: wave.coordinate(withNormalizedOffset: CGVector(dx: b, dy: 0.6)))
        sleep(1)
    }

    func testEditBar() {
        let header = any("trackHeader0")
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the rack shows its first track")
        sleep(1)
        header.twoFingerTap()
        if !menuRow("Open sample editor").waitForExistence(timeout: 2) { header.press(forDuration: 1.2) }
        let open = menuRow("Open sample editor")
        XCTAssertTrue(open.waitForExistence(timeout: 3), "the track menu has Open sample editor")
        open.tap()
        XCTAssertTrue(any("samplerWindow").waitForExistence(timeout: 5), "the sampler opens")
        sleep(2)
        let start = info()
        XCTAssertGreaterThan(start.seconds, 0, "the waveform shows the sound's length (\(start))")
        let plain = probe("plain")

        // ALL: the whole sound
        any("samplerEditALL").tap(); sleep(1)
        let all = Double((any("samplerSelectionLength").label).replacingOccurrences(of: " s", with: "")) ?? -1
        print("UITREE EDIT ALL selects \(all) s of \(start.seconds) s")
        XCTAssertEqual(all, start.seconds, accuracy: 0.002, "ALL selects the whole sound")

        // COPY the whole sound, then PASTE it mixed in at the start: the same length, louder
        any("samplerEditCOPY").tap(); sleep(1)
        any("samplerPaste").tap()
        let mix = menuRow("Mix in")
        XCTAssertTrue(mix.waitForExistence(timeout: 3), "PASTE offers Mix in")
        mix.tap()
        waitForEdit(from: start.name, "mix")
        let mixed = probe("after mix")
        XCTAssertNotEqual(info().name, start.name, "PASTE mix saves an edit")
        XCTAssertEqual(info().seconds, start.seconds, accuracy: 0.0005, "PASTE mix of the whole sound at its start keeps the length")
        XCTAssertGreaterThan(mixed.energy, plain.energy * 2, "PASTE mix merges with what's there (the sound on itself is louder)")
        undo("the mix", back: start)

        // CUT the first half: shorter
        select(0.02, 0.5)
        any("samplerEditCUT").tap()
        waitForEdit(from: start.name, "cut")
        XCTAssertLessThan(info().seconds, start.seconds * 0.7, "CUT takes the selection out")
        undo("the cut", back: start)

        // DELETE the second half: shorter
        select(0.5, 0.98)
        any("samplerEditDELETE").tap()
        waitForEdit(from: start.name, "delete")
        XCTAssertLessThan(info().seconds, start.seconds * 0.7, "DELETE takes the selection out")
        undo("the delete", back: start)

        // FADE IN over the first half: the start of the hit is quieter
        select(0.0, 0.5)
        any("samplerEditFADEIN").tap()
        waitForEdit(from: start.name, "fade in")
        let fadedIn = probe("after fade in")
        XCTAssertLessThan(fadedIn.early, plain.early * 0.8, "FADE IN makes the start quieter")
        undo("the fade in", back: start)

        // FADE OUT over the second half: the end of the hit is quieter
        select(0.5, 1.0)
        any("samplerEditFADEOUT").tap()
        waitForEdit(from: start.name, "fade out")
        let fadedOut = probe("after fade out")
        XCTAssertLessThan(fadedOut.energy, plain.energy, "FADE OUT makes the sound quieter")
        if plain.late > 0.001 { XCTAssertLessThan(fadedOut.late, plain.late * 0.8, "FADE OUT makes the end quieter") }
        undo("the fade out", back: start)

        // TRIM: cuts any silence at the ends (a stock hit may have none: it must not break anything)
        any("samplerEditTRIM").tap()
        sleep(3)
        print("UITREE EDIT trim: \(info())")
        XCTAssertLessThanOrEqual(info().seconds, start.seconds + 0.0005, "TRIM never makes the sound longer")
        if info().name != start.name { undo("the trim", back: start) }

        let end = probe("at the end")
        XCTAssertEqual(end.energy, plain.energy, accuracy: max(1, plain.energy * 0.01), "the track sounds as it did once every edit is undone")
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
    }
}
