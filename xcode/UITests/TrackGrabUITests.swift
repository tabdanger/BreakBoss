import XCTest
import UIKit

/// The channel rack's grab studs (Tyrone, Oct 19): grab the two studs left of a track's arrow, pull
/// the track from row 1 to row 4, and the rack's order changes with the track's steps going along
/// (the grid's lanes, read from its probe value), then UNDO and REDO put the move back and forth.
/// The rack is pictured (UITREE IMG) before, after and after the undo.
final class TrackGrabUITests: XCTestCase {
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

    /// The grid's lanes top to bottom: (pad, notes in that lane).
    private func rows() -> [(pad: Int, notes: Int)] {
        let value = any("grid").value as? String ?? ""
        guard let r = value.range(of: "; rows ") else { return [] }
        return value[r.upperBound...].split(separator: " ").compactMap { item in
            let parts = item.split(whereSeparator: { $0 == ":" || $0 == "@" })
            guard parts.count == 3, let pad = Int(parts[0]), let notes = Int(parts[1]) else { return nil }
            return (pad, notes)
        }
    }

    /// The left part of the screen (the rack and the start of the grid), upright, as a small JPEG
    /// printed in pieces (UITREE IMG <name> <k>/<n> <base64>).
    private func picture(_ name: String, part: CGFloat = 0.42, width: CGFloat = 640) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "grab-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
        let raw = shot.image
        let rotate = (raw.size.width < raw.size.height) != (app.frame.width < app.frame.height)
        let upright = rotate ? CGSize(width: raw.size.height, height: raw.size.width) : raw.size
        let k = width / (upright.width * part)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let size = CGSize(width: width, height: (upright.height * k).rounded())
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { r in
            r.cgContext.scaleBy(x: k, y: k)
            if rotate {
                r.cgContext.translateBy(x: 0, y: raw.size.width)
                r.cgContext.rotate(by: -.pi / 2)
            }
            raw.draw(at: .zero)
        }
        guard let data = small.jpegData(compressionQuality: 0.5) else { return }
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

    func testGrabTrackFromRow1ToRow4() {
        XCTAssertTrue(any("grid").waitForExistence(timeout: 20), "the sequencer opens")
        sleep(1)
        var before = rows()
        XCTAssertGreaterThanOrEqual(before.count, 4, "the rack has at least four tracks (\(before))")
        guard before.count >= 4 else { return }
        let pad = before[0].pad
        // the top track gets steps from its dice, so there is a pattern to follow it
        if before[0].notes == 0 {
            any("trackDice\(pad)").tap()
            sleep(1)
            before = rows()
        }
        let notes = before[0].notes
        print("UITREE grab before \(before)")
        XCTAssertGreaterThan(notes, 0, "the top track has steps to carry")
        picture("before")

        let grip = any("trackGrip\(pad)")
        XCTAssertTrue(grip.exists, "the top track has its grab studs")
        let row4 = any("trackGrip\(before[3].pad)")
        let rowH = any("trackGrip\(before[1].pad)").frame.midY - grip.frame.midY
        let from = grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = from.withOffset(CGVector(dx: 0, dy: row4.frame.midY - grip.frame.midY + rowH * 0.3))
        from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        sleep(1)

        let after = rows()
        print("UITREE grab after \(after)")
        var expected = before.map(\.pad)
        expected.removeFirst()
        expected.insert(pad, at: 3)
        XCTAssertEqual(after.map(\.pad), expected, "the track went from row 1 to row 4 and the others moved up")
        XCTAssertEqual(after.count > 3 ? after[3].notes : -1, notes, "its steps went with it (lane 4 has its \(notes) notes)")
        for r in before where r.pad != pad {
            XCTAssertEqual(after.first { $0.pad == r.pad }?.notes, r.notes, "track \(r.pad) kept its own steps")
        }
        XCTAssertEqual(any("trackGrip\(pad)").frame.midY, any("trackGrip\(expected[3])").frame.midY, accuracy: 0.5, "the studs drew in row 4")
        XCTAssertGreaterThan(any("trackGrip\(pad)").frame.midY, any("trackGrip\(expected[2])").frame.midY + rowH * 0.5, "row 4 sits under row 3")
        picture("after")

        // UNDO puts the old order back, REDO the move again; undo once more to leave the rack as found
        app.buttons["undoButton"].tap()
        sleep(1)
        XCTAssertEqual(rows().map(\.pad), before.map(\.pad), "UNDO puts the track back on row 1")
        picture("undone")
        app.buttons["redoButton"].tap()
        sleep(1)
        XCTAssertEqual(rows().map(\.pad), expected, "REDO moves it to row 4 again")
        app.buttons["undoButton"].tap()
        sleep(1)
        XCTAssertEqual(rows().map(\.pad), before.map(\.pad), "and back")
    }
}
