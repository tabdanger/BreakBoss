import XCTest
import UIKit

/// The hardware menus (Tyrone, Oct 21): the track menu opens from a rack track (two-finger tap, else a
/// hold), runs in Tyrone's order with no Remove, Solo shows its state, the fills and Clear Steps change
/// only that track and undo in one step, a tap outside closes the menu without touching the grid, and
/// Open Sample Editor opens the SAMPLER. KITS and PATTERNS open from their chips. Prints a picture of each.
final class HardwareMenuUITests: XCTestCase {
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

    private func dumpTree(_ why: String) {
        print("UITREE ---- \(why)")
        for line in app.debugDescription.components(separatedBy: "\n") { print("UITREE \(line)") }
    }

    /// How many notes the grid draws in pad 0's lane ("; rows pad:notes@y ...").
    private func notes(_ pad: Int) -> Int {
        let value = any("grid").value as? String ?? ""
        guard let r = value.range(of: "; rows ") else { return -1 }
        let rows = value[r.upperBound...].components(separatedBy: "; grab").first ?? ""
        for item in rows.split(separator: " ") {
            let parts = item.split(separator: ":")
            if parts.count == 2, Int(parts[0]) == pad { return Int(parts[1].split(separator: "@").first ?? "") ?? -1 }
        }
        return -1
    }

    /// A small JPEG of the whole screen in the log (UITREE IMG lines), upright.
    private func picture(_ name: String, width: CGFloat = 1100) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "menus-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
        let raw = shot.image
        let rotate = (raw.size.width < raw.size.height) != (app.frame.width < app.frame.height)
        let upright = rotate ? CGSize(width: raw.size.height, height: raw.size.width) : raw.size
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let size = CGSize(width: width, height: width * upright.height / upright.width)
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { r in
            let k = width / upright.width
            r.cgContext.scaleBy(x: k, y: k)
            if rotate {
                r.cgContext.translateBy(x: 0, y: raw.size.width)
                r.cgContext.rotate(by: -.pi / 2)
            }
            raw.draw(at: .zero)
        }
        guard let data = small.jpegData(compressionQuality: 0.6) else { return }
        let text = data.base64EncodedString()
        let piece = 6_000
        let parts = (text.count + piece - 1) / piece
        var i = text.startIndex, k = 1
        while i < text.endIndex {
            let j = text.index(i, offsetBy: piece, limitedBy: text.endIndex) ?? text.endIndex
            print("UITREE IMG \(name) \(k)/\(parts) \(text[i..<j])")
            i = j; k += 1
        }
    }

    /// Opens a track's menu: a two-finger tap first (it's what right-click shares), then a hold.
    private func openTrackMenu(_ header: XCUIElement, _ label: String) -> Bool {
        print("UITREE HW \(label): header hittable=\(header.isHittable) frame=\(header.frame)")
        if header.isHittable {
            header.twoFingerTap()
            if any("trackMenu.settings").waitForExistence(timeout: 2) { print("UITREE HW \(label): two-finger tap opened it"); return true }
            print("UITREE HW \(label): two-finger tap missed; holding")
        }
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.9)
        let ok = any("trackMenu.settings").waitForExistence(timeout: 3)
        print("UITREE HW \(label): hold opened it = \(ok)")
        return ok
    }

    func testHardwareMenus() {
        let header = any("trackHeader0")
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the rack shows its first track")
        sleep(1)
        XCTAssertTrue(header.isHittable, "the first track's header takes touches (build 116 lost them)")

        // the track menu, its order, no Remove
        guard openTrackMenu(header, "first") else { dumpTree("no track menu"); XCTFail("the track menu opens"); return }
        sleep(1)
        picture("track-menu")
        let order = ["trackMenu.settings", "trackMenu.editor", "trackMenu.solo", "trackMenu.load", "trackMenu.clearSample",
                     "trackMenu.fill1", "trackMenu.fill2", "trackMenu.fill4", "trackMenu.fill8", "trackMenu.clearSteps"]
        let ys = order.map { any($0).exists ? any($0).frame.minY : -1 }
        print("UITREE HW ORDER \(zip(order, ys).map { "\($0.0)@\(Int($0.1))" }.joined(separator: " "))")
        XCTAssertFalse(ys.contains(-1), "every track-menu row is there")
        XCTAssertEqual(ys, ys.sorted(), "the track menu runs in Tyrone's order")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Remove")).firstMatch.exists, "no Remove in the track menu")
        let title = any("hwMenuTitle")
        print("UITREE HW title=\(title.exists ? title.label : "-") at=\(title.frame) settings=\(any("trackMenu.settings").frame) app=\(app.frame)")

        // Solo shows its state and keeps the menu open
        let solo = any("trackMenu.solo")
        let before = solo.value as? String ?? "?"
        solo.tap(); sleep(1)
        let after = any("trackMenu.solo").value as? String ?? "?"
        print("UITREE HW solo \(before) -> \(after)")
        XCTAssertNotEqual(before, after, "Solo switches and the menu shows it")
        any("trackMenu.solo").tap(); sleep(1)

        // Fill Every Step / Every 4 / Clear Steps, each one undo
        any("trackMenu.fill1").tap(); sleep(1)
        XCTAssertFalse(any("trackMenu.settings").exists, "a fill closes the menu")
        let n1 = notes(0)
        _ = openTrackMenu(header, "fill4")
        any("trackMenu.fill4").tap(); sleep(1)
        let n4 = notes(0)
        print("UITREE HW fills every1=\(n1) every4=\(n4)")
        XCTAssertTrue(n4 > 0 && n1 == n4 * 4, "Fill Every 4 puts a hit on one step in four across the whole pattern")
        any("undoButton").tap(); sleep(1)
        XCTAssertEqual(notes(0), n1, "UNDO takes the fill back in one step")
        _ = openTrackMenu(header, "clear")
        any("trackMenu.clearSteps").tap(); sleep(1)
        XCTAssertEqual(notes(0), 0, "Clear Steps empties the track")
        any("undoButton").tap(); sleep(1)

        // a tap outside closes the menu and doesn't reach the grid
        _ = openTrackMenu(header, "outside")
        let gridBefore = any("grid").value as? String ?? ""
        any("grid").coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.1)).tap(); sleep(1)
        XCTAssertFalse(any("trackMenu.settings").exists, "a tap outside closes the menu")
        XCTAssertEqual(any("grid").value as? String ?? "", gridBefore, "the outside tap didn't toggle a step")

        // Open Sample Editor opens the SAMPLER
        _ = openTrackMenu(header, "editor")
        any("trackMenu.editor").tap()
        XCTAssertTrue(any("samplerWindow").waitForExistence(timeout: 5), "Open Sample Editor opens the SAMPLER")
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
        sleep(1)
        if any("samplerClose").exists { any("samplerClose").tap(); sleep(1) }

        // KITS and PATTERNS from their chips
        for (chip, panel) in [("kitChip", "KITS"), ("patternChip", "PATTERNS")] {
            let c = any(chip)
            guard c.waitForExistence(timeout: 3) else { dumpTree("no \(chip)"); XCTFail("there is a \(chip)"); continue }
            c.tap()
            let title = any("hwMenuTitle")
            XCTAssertTrue(title.waitForExistence(timeout: 3) && title.label == panel, "\(chip) opens \(panel)")
            XCTAssertTrue(any("hwMenuSearch").exists, "\(panel) has its search field")
            sleep(1)
            print("UITREE HW \(panel) title=\(title.exists ? title.label : "-") at=\(title.frame) chip=\(c.frame) app=\(app.frame)")
            picture(panel)
            any("hwMenuClose").tap(); sleep(1)
            XCTAssertFalse(any("hwMenuTitle").exists, "the close button closes \(panel)")
        }
    }
}
