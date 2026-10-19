import XCTest
import UIKit

/// Face 2's FX knobs per track and the knob readout (Tyrone, Oct 19), on an iPad simulator, in each
/// of the four faces: the first FX knob turned with track A (the kick) selected moves A's value only
/// (track B shows its own, untouched), and turning a knob shows its value in a readout over it.
/// Small JPEGs of the bottom rail and the rack with the readout up go into the log as UITREE IMG lines.
final class TrackFXUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(platinum: Bool) {
        app = XCUIApplication()
        app.launchArguments += ["-breakboss.platinumFace", platinum ? "YES" : "NO"]
        app.launchEnvironment["BREAKBOSS_UI_PROBE"] = "1"
        app.launch()
        sleep(3)
    }

    /// A point on Face 1, in the picture's own pixels (1450 x 1085, centred and fitted).
    private func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        let f = app.windows.firstMatch.frame
        let s = min(f.width / 1450, f.height / 1085)
        let ox = (f.width - 1450 * s) / 2, oy = (f.height - 1085 * s) / 2
        return app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: ox + x * s, dy: oy + y * s))
    }

    /// Part of the screen (`region` in 0...1 of the upright screen), as a small JPEG printed in pieces.
    private func picture(_ name: String, region: CGRect, width: CGFloat = 640) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "trackfx-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
        let raw = shot.image
        let rotate = (raw.size.width < raw.size.height) != (app.frame.width < app.frame.height)
        let upright = rotate ? CGSize(width: raw.size.height, height: raw.size.width) : raw.size
        let k = width / (upright.width * region.width)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let size = CGSize(width: width, height: (upright.height * region.height * k).rounded())
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { r in
            r.cgContext.scaleBy(x: k, y: k)
            r.cgContext.translateBy(x: -upright.width * region.minX, y: -upright.height * region.minY)
            if rotate {
                r.cgContext.translateBy(x: 0, y: raw.size.width)
                r.cgContext.rotate(by: -.pi / 2)
            }
            raw.draw(at: .zero)
        }
        guard let data = small.jpegData(compressionQuality: 0.55) else { return }
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

    private func value(_ e: XCUIElement) -> String { (e.value as? String) ?? "" }

    /// Turns a knob by dragging up from its centre by `points`, and keeps the finger there a moment.
    private func turn(_ knob: XCUIElement, up points: CGFloat) {
        let c = knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        c.press(forDuration: 0.05, thenDragTo: c.withOffset(CGVector(dx: 0, dy: -points)), withVelocity: 300, thenHoldForDuration: 0.3)
    }

    private func face(_ name: String, modeY: CGFloat, first: String) {
        at(562, modeY).tap()
        sleep(1)
        at(1288, 29).tap()                         // the piano-roll button: Face 2
        let kick = app.descendants(matching: .any)["trackHeader0"].firstMatch
        let snare = app.descendants(matching: .any)["trackHeader1"].firstMatch
        XCTAssertTrue(kick.waitForExistence(timeout: 10), "Face 2 opens (\(name))")
        sleep(1)
        let knob = app.descendants(matching: .any)["fx_\(first)"].firstMatch
        XCTAssertTrue(knob.exists, "the first FX knob is there (\(name))")

        // select the snare first (a tap on an unselected track only selects it), then the kick
        snare.tap(); sleep(1)
        let snareBefore = value(knob)
        kick.tap(); sleep(1)
        let kickBefore = value(knob)
        turn(knob, up: 120)
        let hud = app.descendants(matching: .any)["knobHUD"].firstMatch
        let hudShown = hud.waitForExistence(timeout: 2)
        print("UITREE \(name) FX readout: shown \(hudShown) '\(hudShown ? (hud.value as? String ?? hud.label) : "")'")
        XCTAssertTrue(hudShown, "turning an FX knob shows its readout (\(name))")
        picture("\(name)-fx", region: CGRect(x: 0.5, y: 0.6, width: 0.5, height: 0.4))
        let kickAfter = value(knob)
        snare.tap(); sleep(1)
        let snareAfter = value(knob)
        kick.tap(); sleep(1)
        let kickAgain = value(knob)
        print("UITREE \(name) FX \(first): kick \(kickBefore) -> \(kickAfter) (back on kick \(kickAgain)); snare \(snareBefore) -> \(snareAfter)")
        XCTAssertNotEqual(kickBefore, kickAfter, "the knob turns the kick's own value (\(name))")
        XCTAssertEqual(snareBefore, snareAfter, "the snare keeps its own value (\(name))")
        XCTAssertEqual(kickAfter, kickAgain, "selecting the kick again shows its value (\(name))")
        // put the kick back as it was
        turn(knob, up: -400)
        sleep(1)

        // the rack's VOLUME and PAN readouts
        let volume = app.descendants(matching: .any)["trackVolume0"].firstMatch
        let pan = app.descendants(matching: .any)["trackPan0"].firstMatch
        XCTAssertTrue(volume.exists && pan.exists, "the kick's VOLUME and PAN knobs are there (\(name))")
        let volumeBefore = value(volume)
        turn(volume, up: 200)                      // already at the top (100%): it stays there
        let volumeTop = value(volume)
        turn(volume, up: -40)
        print("UITREE \(name) VOLUME top: \(volumeBefore) -> up \(volumeTop)")
        XCTAssertTrue(volumeTop.contains("100%"), "the rack's VOLUME stops at 100% (\(name): \(volumeTop))")
        let volShown = hud.waitForExistence(timeout: 2)
        print("UITREE \(name) VOLUME readout: shown \(volShown) '\(volShown ? (hud.value as? String ?? hud.label) : "")' knob \(value(volume))")
        XCTAssertTrue(volShown, "turning VOLUME shows its readout (\(name))")
        picture("\(name)-volume", region: CGRect(x: 0.15, y: 0.25, width: 0.4, height: 0.4))
        volume.doubleTap()                         // back to 100% (the top)
        sleep(6)
        turn(pan, up: -40)
        let panShown = hud.waitForExistence(timeout: 2)
        print("UITREE \(name) PAN readout: shown \(panShown) '\(panShown ? (hud.value as? String ?? hud.label) : "")' knob \(value(pan))")
        XCTAssertTrue(panShown, "turning PAN shows its readout (\(name))")
        picture("\(name)-pan", region: CGRect(x: 0.15, y: 0.25, width: 0.4, height: 0.4))
        pan.doubleTap()                            // back to the centre
        sleep(6)

        let slider = app.descendants(matching: .any)["faceSlider"].firstMatch
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5)))
        sleep(2)
    }

    func testTrackFXAndReadouts() {
        launch(platinum: false)
        for (name, y, first) in [("modern", 86.0, "boost"), ("texture", 287.0, "resample"), ("vintage", 186.0, "drive")] {
            face(name, modeY: y, first: first)
        }
        at(562, 86).tap()
        app.terminate()

        launch(platinum: true)
        face("platinum", modeY: 86, first: "boost")
        app.terminate()
    }
}
