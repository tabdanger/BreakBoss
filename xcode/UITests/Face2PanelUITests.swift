import XCTest
import UIKit

/// Face 2's left panel (SOUNDS / GENERATE) on an iPad simulator, on all four faces (Tyrone, Oct 21:
/// every edge flush or recessed and lined up). For each face: the panel with SOUNDS open, close-ups
/// of its top corners and of GENERATE at its foot, the type chips scrolled to their end, and
/// GENERATE slid up and back. Pictures go into the log as UITREE IMG lines; the taps are checked.
final class Face2PanelUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    private func launch(platinum: Bool) {
        app = XCUIApplication()
        app.launchArguments += ["-breakboss.platinumFace", platinum ? "YES" : "NO", "-breakboss.tutorialSeen", "YES"]
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

    /// The left `part` of the screen, upright, as a small JPEG printed in pieces (UITREE IMG <name> <k>/<n> <base64>).
    private func picture(_ name: String, part: CGFloat = 0.42, width: CGFloat = 640) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "face2-" + name
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

    /// A close-up of one element (with `margin` points round it), printed like picture().
    private func closeUp(_ name: String, of element: XCUIElement, margin: CGFloat = 30, width: CGFloat = 480) {
        let shot = XCUIScreen.main.screenshot()
        let raw = shot.image
        let rotate = (raw.size.width < raw.size.height) != (app.frame.width < app.frame.height)
        let upright = rotate ? CGSize(width: raw.size.height, height: raw.size.width) : raw.size
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = raw.scale
        let image = UIGraphicsImageRenderer(size: upright, format: fmt).image { r in
            if rotate {
                r.cgContext.translateBy(x: 0, y: raw.size.width)
                r.cgContext.rotate(by: -.pi / 2)
            }
            raw.draw(at: .zero)
        }
        let f = element.frame.insetBy(dx: -margin, dy: -margin).intersection(CGRect(origin: .zero, size: upright))
        let k = image.scale
        guard f.width > 10, let cg = image.cgImage?.cropping(to: CGRect(x: f.minX * k, y: f.minY * k, width: f.width * k, height: f.height * k)) else { return }
        let size = CGSize(width: width, height: (width * f.height / f.width).rounded())
        let one = UIGraphicsImageRendererFormat(); one.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: one).image { _ in UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = small.jpegData(compressionQuality: 0.7) else { return }
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

    /// From Face 1: pick the mode, open the sequencer, picture the left panel and work its taps.
    private func panel(_ name: String, modeY: CGFloat) {
        at(562, modeY).tap()
        sleep(1)
        at(1288, 29).tap()                         // the piano-roll button: Face 2
        let sounds = app.buttons["soundsHeader"], generate = app.buttons["generateHeader"]
        XCTAssertTrue(sounds.waitForExistence(timeout: 10), "Face 2 opens (\(name))")
        sleep(1)
        picture(name + "-panel", part: 0.38, width: 900)
        closeUp(name + "-top", of: sounds, margin: 24, width: 700)
        closeUp(name + "-foot", of: generate, margin: 24, width: 700)
        // the type chips: pick one, then run the row to its end (they sink into the panel's edge)
        let snares = app.buttons["SNARES"].firstMatch
        XCTAssertTrue(snares.exists, "SNARES chip (\(name))")
        snares.tap()
        let rims = app.buttons["RIMS"].firstMatch, all = app.buttons["ALL"].firstMatch
        closeUp(name + "-chips-rest", of: rims, margin: 40, width: 500)
        rims.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: all.coordinate(withNormalizedOffset: CGVector(dx: -1.5, dy: 0.5)))
        sleep(1)
        closeUp(name + "-chips-end", of: sounds, margin: 50, width: 700)
        app.buttons["SNARES"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: sounds.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 1.6)))
        sleep(1)
        // GENERATE slides up over the sounds and back down
        let footY = generate.frame.minY
        XCTAssertTrue(generate.isHittable, "GENERATE header hittable (\(name))")
        generate.tap()
        sleep(1)
        XCTAssertLessThan(generate.frame.minY, footY - 100, "GENERATE slid up (\(name))")
        picture(name + "-generate", part: 0.38, width: 900)
        closeUp(name + "-generate-top", of: generate, margin: 24, width: 700)
        sounds.tap()
        sleep(1)
        XCTAssertEqual(generate.frame.minY, footY, accuracy: 2, "GENERATE back at the foot (\(name))")
        print("UITREE PANEL \(name) foot \(footY) ok")
        // back to Face 1 with the Face 1 / Face 2 slider
        let slider = app.descendants(matching: .any)["faceSlider"].firstMatch
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5)))
        sleep(2)
    }

    func testPanelEdges() {
        launch(platinum: false)
        for (name, y) in [("modern", 86.0), ("texture", 287.0), ("vintage", 186.0)] {
            panel(name, modeY: y)
        }
        at(562, 86).tap()
        app.terminate()

        launch(platinum: true)
        panel("platinum", modeY: 86)
        app.terminate()
    }
}
