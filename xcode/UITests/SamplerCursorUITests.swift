import XCTest
import UIKit

/// The SAMPLER's live waveform and its page buttons, on an iPad simulator (build.yml, "taps" job).
/// Taps the waveform (the track sounds) and reads the cursor (BREAKBOSS_UI_PROBE gives it the
/// cursor's place as its value) while the hit plays and after it ends. Small JPEGs of the window
/// go into the log as UITREE IMG lines so they can be looked at without the artifacts.
// Named to run before SamplerUITests: the app keeps its settings between launches, and that test
// leaves track 1's MISC page changed (arpeggiator, Cut, MAX, Mono, levels down).
final class SamplerCursorUITests: XCTestCase {
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
        // the screen upright, as the app is drawn (a landscape screenshot can come out portrait)
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

    /// The cursor's value: its place in the sound, "playing" or "rest", and its counts
    /// (hits followed, resets to rest, steps backwards during a hit, how far a hit got).
    private struct Cursor: CustomStringConvertible {
        var position = 0.0, playing = false, hits = 0, resets = 0, back = 0, far = 0.0
        var description: String { String(format: "%.3f %@ hits=%d resets=%d back=%d far=%.3f", position, playing ? "playing" : "rest", hits, resets, back, far) }
    }
    private func cursor(_ el: XCUIElement) -> Cursor? {
        guard let v = el.value as? String else { return nil }
        let parts = v.components(separatedBy: " ")
        guard parts.count >= 2, let f = Double(parts[0]) else { return nil }
        var c = Cursor(position: f, playing: parts[1] == "playing")
        for part in parts.dropFirst(2) {
            let kv = part.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "hits": c.hits = Int(kv[1]) ?? 0
            case "resets": c.resets = Int(kv[1]) ?? 0
            case "back": c.back = Int(kv[1]) ?? 0
            case "far": c.far = Double(kv[1]) ?? 0
            default: break
            }
        }
        return c
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
        XCTAssertFalse(rest.playing, "nothing plays before a hit")
        picture("sample-page-rest", of: window)
        picture("waveform-rest", of: wave, width: 1200)

        // a hit: the cursor follows it (never stepping back), then rests at the start again
        wave.tap()
        var playingShot = false, tappedAgain = false
        var now = rest
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 12 {
            guard let c = cursor(playhead) else { continue }
            now = c
            print(String(format: "UITREE CURSOR %.2fs %@", Date().timeIntervalSince(t0), c.description))
            if c.playing && !playingShot && c.far > 0.05 { picture("sample-page-playing", of: window); picture("waveform-playing", of: wave, width: 1200); playingShot = true }
            if c.resets > rest.resets && !c.playing { break }
            // the first tap after the window opens can land before the audio is running: tap once more
            if c.hits == rest.hits && !tappedAgain && Date().timeIntervalSince(t0) > 3 {
                print("UITREE CURSOR no hit after 3 s, tapping again")
                tappedAgain = true
                wave.tap()
            }
        }
        // one tap can be several hits (the track's arpeggiator or chord): the cursor follows each newest one
        XCTAssertGreaterThanOrEqual(now.hits, rest.hits + 1, "the hit restarts the cursor (\(now))")
        XCTAssertEqual(now.resets, rest.resets + 1, "the cursor resets when the hit ends (\(now))")
        XCTAssertFalse(now.playing, "the cursor rests once the hit has ended")
        XCTAssertEqual(now.position, rest.position, accuracy: 0.002, "it rests at the sound's start again")
        XCTAssertEqual(now.back, 0, "the cursor never steps back during a hit (\(now))")
        XCTAssertGreaterThan(now.far, 0.5, "the cursor travels through the sound (\(now))")

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
