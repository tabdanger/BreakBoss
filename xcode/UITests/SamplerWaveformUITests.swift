import XCTest
import UIKit

/// The SAMPLER's live waveform and its page buttons, on an iPad simulator (build.yml, "taps" job).
/// Taps the waveform (the track sounds) and reads the cursor (BREAKBOSS_UI_PROBE gives it the
/// cursor's place as its value) while the hit plays and after it ends. Small JPEGs of the window
/// go into the log as UITREE IMG lines so they can be looked at without the artifacts.
final class SamplerWaveformUITests: XCTestCase {
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

    private func dumpTree(_ why: String) {
        print("UITREE ---- \(why)")
        for line in app.debugDescription.components(separatedBy: "\n") { print("UITREE \(line)") }
    }

    /// The window as a small JPEG, printed in pieces (UITREE IMG <name> <part>/<parts> <base64>).
    private func picture(_ name: String, of element: XCUIElement, width: CGFloat = 1000) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "waveform-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = shot.image
        let scale = image.scale
        let f = element.frame
        guard f.width > 10, let cg = image.cgImage?.cropping(to: CGRect(x: f.minX * scale, y: f.minY * scale,
                                                                       width: f.width * scale, height: f.height * scale)) else { return }
        let size = CGSize(width: width, height: width * f.height / f.width)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = small.jpegData(compressionQuality: 0.55) else { return }
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

    /// The cursor's value: its place in the sound and "playing" or "rest".
    private func cursor(_ el: XCUIElement) -> (Double, Bool)? {
        guard let v = el.value as? String else { return nil }
        let parts = v.components(separatedBy: " ")
        guard parts.count == 2, let f = Double(parts[0]) else { return nil }
        return (f, parts[1] == "playing")
    }

    func testLiveWaveformAndPageButtons() {
        let header = any("trackHeader0")
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the rack shows its first track")
        sleep(1)
        header.twoFingerTap()
        if !menuRow("Open sample editor").waitForExistence(timeout: 2) { header.press(forDuration: 1.2) }
        let open = menuRow("Open sample editor")
        XCTAssertTrue(open.waitForExistence(timeout: 3), "the track menu has Open sample editor")
        open.tap()
        let window = any("samplerWindow")
        XCTAssertTrue(window.waitForExistence(timeout: 5), "the sampler opens")
        sleep(2)

        // the three page buttons sit where they did
        for id in ["samplerSamplePage", "samplerEnvelopePage", "samplerMiscPage"] {
            let b = any(id)
            XCTAssertTrue(b.exists, "\(id) is there")
            print("UITREE TAB \(id) frame=\(b.frame) window=\(window.frame)")
        }

        let wave = any("samplerWaveform")
        let playhead = any("samplerPlayhead")
        XCTAssertTrue(wave.exists, "the waveform is there")
        XCTAssertTrue(playhead.waitForExistence(timeout: 3), "the cursor is over the waveform")
        guard let rest = cursor(playhead) else { dumpTree("no cursor value"); XCTFail("the cursor reports its place"); return }
        print("UITREE CURSOR rest \(rest)")
        XCTAssertFalse(rest.1, "nothing plays before a hit")
        picture("sample-page-rest", of: window)

        // a hit: the cursor starts at the sound's start, moves on, then rests at the start again
        var seen: [(Double, Bool, Double)] = []
        let t0 = Date()
        wave.tap()
        var tookPicture = false
        while Date().timeIntervalSince(t0) < 4 {
            if let c = cursor(playhead) {
                seen.append((c.0, c.1, Date().timeIntervalSince(t0)))
                if c.1 && !tookPicture && c.0 > rest.0 + 0.05 { picture("sample-page-playing", of: window); tookPicture = true }
                if !c.1 && seen.contains(where: { $0.1 }) { break }
            }
        }
        print("UITREE CURSOR seen " + seen.map { String(format: "%.3f%@@%.2f", $0.0, $0.1 ? "p" : "r", $0.2) }.joined(separator: " "))
        let playing = seen.filter { $0.1 }.map { $0.0 }
        XCTAssertGreaterThan(playing.count, 1, "the cursor moves while the hit plays")
        if playing.count > 1 {
            XCTAssertGreaterThan(playing.last!, playing.first!, "the cursor moves forward through the sound")
            XCTAssertEqual(zip(playing, playing.dropFirst()).filter { $1 < $0 - 0.001 }.count, 0, "the cursor never jumps back during one hit")
        }
        if let last = seen.last {
            XCTAssertFalse(last.1, "the cursor rests once the hit has ended")
            XCTAssertEqual(last.0, rest.0, accuracy: 0.002, "it rests at the sound's start again")
        }

        // the page buttons on every page
        any("samplerEnvelopePage").tap(); sleep(1)
        XCTAssertFalse(playhead.exists, "the cursor stops with the SAMPLE page hidden")
        picture("envelope-page", of: window)
        any("samplerMiscPage").tap(); sleep(1)
        picture("misc-page", of: window)
        any("samplerSamplePage").tap(); sleep(1)
        XCTAssertTrue(any("samplerPlayhead").waitForExistence(timeout: 3), "the cursor is back with the SAMPLE page")
        XCTAssertEqual(app.state, .runningForeground, "the app is still running")
    }
}
