import XCTest
import UIKit

/// Face 1 on an iPad simulator (build.yml, "taps" job): each of Tyrone's four faces (Modern black,
/// Texture, Vintage, Platinum) as the app draws it, with its buttons as drawn, then with every lit
/// part switched over (ONE-SHOT, CLIPPER off, TEMPO SYNC / FOLLOW DAW, PLAY, knobs turned). Small
/// JPEGs of the screen go into the log as UITREE IMG lines so they can be compared with the renders
/// without the artifacts. Puts every switch back as it found it.
final class Face1UITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(platinum: Bool) {
        app = XCUIApplication()
        app.launchArguments += ["-breakboss.platinumFace", platinum ? "YES" : "NO"]
        app.launch()
        sleep(3)
    }

    /// A point on the faceplate, in the picture's own pixels (1450 x 1085, centred and fitted).
    private func at(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
        let f = app.windows.firstMatch.frame
        let s = min(f.width / 1450, f.height / 1085)
        let ox = (f.width - 1450 * s) / 2, oy = (f.height - 1085 * s) / 2
        return app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: ox + x * s, dy: oy + y * s))
    }

    private func tap(_ x: CGFloat, _ y: CGFloat) {
        at(x, y).tap()
        usleep(400_000)
    }

    /// The screen, upright, as a small JPEG printed in pieces (UITREE IMG <name> <part>/<parts> <base64>).
    private func picture(_ name: String, width: CGFloat = 1100) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "face1-" + name
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

    /// Everything a face lights, switched over: ONE-SHOT, CLIPPER, the two lamps, PLAY, a knob turned.
    private func switchAll() {
        tap(210, 83)            // ONE-SHOT
        tap(1259, 244)          // CLIPPER
        tap(365, 379)           // TEMPO SYNC
        tap(365, 413)           // FOLLOW DAW
        at(1095, 234).press(forDuration: 0.1, thenDragTo: at(1095, 150))   // OUTPUT up
        at(240, 510).press(forDuration: 0.1, thenDragTo: at(240, 430))     // BOOST up
        tap(146, 398)           // PLAY
        sleep(1)
    }

    private func switchBack() {
        tap(146, 398)           // STOP
        tap(377, 83)            // LOOP
        tap(1259, 244)
        tap(365, 379)
        tap(365, 413)
        at(1095, 234).doubleTap()                                          // knobs back to their defaults
        at(240, 510).doubleTap()
        usleep(400_000)
    }

    func testFourFaces() {
        launch(platinum: false)
        for (name, y) in [("modern", 86.0), ("texture", 287.0), ("vintage", 186.0)] {
            tap(562, y)
            sleep(1)
            picture(name)
            switchAll()
            picture(name + "-switched")
            switchBack()
        }
        tap(562, 86)
        app.terminate()

        launch(platinum: true)
        tap(562, 86)
        sleep(1)
        picture("platinum")
        switchAll()
        picture("platinum-switched")
        switchBack()
        app.terminate()
    }

    /// Face 2's key on Face 1 (Tyrone, Oct 20): sliding it opens Face 2; Face 2's key brings Face 1
    /// back with its key home again.
    func testFaceKeyOpensFace2() {
        launch(platinum: false)
        let key = app.descendants(matching: .any)["faceSlider1"].firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 10), "Face 1 has the Face 1 / Face 2 key")
        key.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: key.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5)))
        XCTAssertTrue(app.buttons["trackArrow0"].waitForExistence(timeout: 10), "sliding Face 1's key opens Face 2")
        let back = app.descendants(matching: .any)["faceSlider"].firstMatch
        back.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: back.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5)))
        sleep(2)
        XCTAssertTrue(key.waitForExistence(timeout: 10), "Face 2's key brings Face 1 back")
        picture("face-key-home")
        // a tap on the slot's right end works too
        key.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["trackArrow0"].waitForExistence(timeout: 10), "tapping the key's right end opens Face 2")
        app.terminate()
    }
}
