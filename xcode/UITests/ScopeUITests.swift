import XCTest
import UIKit

/// The Face 1 scope on an iPad simulator (build.yml, "taps" job), in all four faces: plays the 808
/// pad and the HAT pad in ONE-SHOT and reads the scope (BREAKBOSS_UI_PROBE gives it its loudness
/// and its bass / top share as its value), so the trace is shown to move for every sound and to
/// follow the sound's frequencies. Small JPEGs of the scope go into the log as UITREE IMG lines.
/// Puts ONE-SHOT back to LOOP.
final class ScopeUITests: XCTestCase {
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

    /// The scope's probe: "level L bass B top T".
    private func reading(_ scope: XCUIElement) -> (level: Double, bass: Double, top: Double)? {
        guard let v = scope.value as? String else { return nil }
        let p = v.components(separatedBy: " ")
        guard p.count >= 6, let l = Double(p[1]), let b = Double(p[3]), let t = Double(p[5]) else { return nil }
        return (l, b, t)
    }

    /// The scope, upright, as a small JPEG printed in pieces (UITREE IMG <name> <part>/<parts> <base64>).
    private func picture(_ name: String, of element: XCUIElement, width: CGFloat = 700) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "scope-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        let scale = image.scale
        let f = element.frame.insetBy(dx: -12, dy: -12)
        guard f.width > 10, let cg = image.cgImage?.cropping(to: CGRect(x: f.minX * scale, y: f.minY * scale,
                                                                       width: f.width * scale, height: f.height * scale)) else { return }
        let size = CGSize(width: width, height: width * f.height / f.width)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size)) }
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

    /// Plays a pad over and over, keeping the loudest reading; a picture of the scope on the way.
    private func play(_ pad: (CGFloat, CGFloat), _ name: String, scope: XCUIElement) -> (level: Double, bass: Double, top: Double) {
        var best = (level: 0.0, bass: 0.0, top: 0.0)
        for k in 0..<6 {
            at(pad.0, pad.1).tap()
            if k == 2 { picture(name, of: scope) }     // straight away: a hat is over in a moment
            usleep(120_000)
            if let r = reading(scope), r.level >= best.level { best = r }
        }
        print("UITREE scope \(name): level \(best.level) bass \(best.bass) top \(best.top)")
        return best
    }

    private func checkFace(_ face: String) {
        let scope = app.descendants(matching: .any)["scope"].firstMatch
        XCTAssertTrue(scope.waitForExistence(timeout: 5), "\(face): the scope is on Face 1")
        tap(191, 108)           // ONE-SHOT
        sleep(2)
        picture(face + "-idle", of: scope)
        // pad 7, 808 (top row, MPC order); a mode switch reloads the kit, which can take a few
        // seconds on the simulator, so play again while it is still silent
        var bass = play((217, 760), face + "-808", scope: scope)
        for _ in 0..<3 where bass.level < 0.01 {
            sleep(3)
            bass = play((217, 760), face + "-808", scope: scope)
        }
        sleep(2)
        let hat = play((1038, 935), face + "-hat", scope: scope)     // pad 5, HAT (bottom row)
        XCTAssertGreaterThan(bass.level, 0.01, "\(face): the 808 moves the scope")
        XCTAssertGreaterThan(hat.level, 0.01, "\(face): the hat moves the scope")
        XCTAssertGreaterThan(bass.bass, hat.bass, "\(face): the 808 reads more bass than the hat")
        XCTAssertGreaterThan(hat.top, bass.top, "\(face): the hat reads more top than the 808")
        tap(378, 108)           // LOOP
    }

    func testScopeFollowsEverySound() {
        launch(platinum: false)
        for (name, y) in [("modern", 86.0), ("texture", 287.0), ("vintage", 186.0)] {
            tap(562, y)
            sleep(1)
            checkFace(name)
        }
        tap(562, 86)
        app.terminate()

        launch(platinum: true)
        tap(562, 86)
        sleep(1)
        checkFace("platinum")
        app.terminate()
    }
}
