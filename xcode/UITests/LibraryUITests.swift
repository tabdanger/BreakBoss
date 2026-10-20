import XCTest
import UIKit

/// The sound library's taps (Tyrone, Oct 20): the first tap on a sound picks it, every tap on it
/// after that plays it again (the row's value counts the plays), and no tap changes a track's sound
/// (the rack's names, read from its arrows, stay the same). Only drag and drop changes a track.
final class LibraryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app = XCUIApplication()
        app.launchEnvironment["BREAKBOSS_OPEN_SEQUENCER"] = "1"
        app.launch()
    }

    private func any(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func rackNames() -> [String] {
        (0..<12).map { app.buttons["trackArrow\($0)"].exists ? app.buttons["trackArrow\($0)"].label : "-" }
    }

    func testTapPicksTapAgainPlays() {
        XCTAssertTrue(app.buttons["trackArrow0"].waitForExistence(timeout: 20), "Face 2 is open")
        sleep(2)
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'librarySound_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5), "the library lists sounds")
        let row = rows.element(boundBy: min(2, rows.count - 1))
        let rowID = row.identifier
        let before = rackNames()
        print("UITREE LIBRARY rack before \(before)")

        row.tap(); usleep(500_000)
        let first = any(rowID).value as? String ?? ""
        print("UITREE LIBRARY after first tap \(rowID) value='\(first)'")
        XCTAssertEqual(first, "picked, played 0", "the first tap picks the sound without playing it")

        for n in 1...3 {
            any(rowID).tap(); usleep(500_000)
            let v = any(rowID).value as? String ?? ""
            print("UITREE LIBRARY tap \(n + 1) value='\(v)'")
            XCTAssertEqual(v, "picked, played \(n)", "every tap on the picked sound plays it again")
        }
        XCTAssertEqual(rackNames(), before, "no tap in the library changes a track's sound")

        // another sound: its first tap picks it (the old one lets go)
        let other = rows.element(boundBy: min(4, rows.count - 1))
        let otherID = other.identifier
        if otherID != rowID {
            other.tap(); usleep(500_000)
            XCTAssertTrue((any(otherID).value as? String ?? "").hasPrefix("picked"), "a tap on another sound picks it")
            XCTAssertEqual(any(rowID).value as? String ?? "", "", "the first sound is no longer picked")
        }
        XCTAssertEqual(rackNames(), before, "the rack is still the same")
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
    }
}
