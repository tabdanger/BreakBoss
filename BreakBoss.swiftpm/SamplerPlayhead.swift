// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UIKit
import AVFoundation

// MARK: - The SAMPLER's live waveform (Tyrone's reference, Oct 18)
//
// The waveform is drawn once from the sound's own audio (peaks worked out off the main and audio
// threads and kept per sound) and stays still. Over it a thin cursor follows the track's newest
// voice from the engine (KnockEngine.playheads): it restarts at the voice's real start on every
// hit and moves at the voice's real speed, backwards when the voice plays backwards, round the
// loop when it loops. The part already played is gently brighter. Only the cursor and that
// brighter part move while it plays; when nothing plays the display link drops to a slow check
// and nothing is redrawn, and it stops when the window is closed, minimized or on another page.

/// A sound's peaks (low and high, the two channels mixed) in blocks of 32 and 1024 frames, so
/// any zoom draws from at most a few dozen numbers per pixel column.
final class SamplerPeaks {
    static let fine = 32, coarse = 1_024
    let length: Int
    private let fineLo: [Float], fineHi: [Float], coarseLo: [Float], coarseHi: [Float]

    init(_ sample: SampleBuffer) {
        let n = sample.length
        length = n
        let fineCount = (n + Self.fine - 1) / Self.fine
        var flo = [Float](repeating: 0, count: fineCount), fhi = [Float](repeating: 0, count: fineCount)
        for b in 0..<fineCount {
            var lo: Float = 0, hi: Float = 0
            for i in (b * Self.fine)..<min(n, (b + 1) * Self.fine) {
                let v = (sample.left[i] + sample.right[i]) * 0.5
                lo = min(lo, v); hi = max(hi, v)
            }
            flo[b] = lo; fhi[b] = hi
        }
        let per = Self.coarse / Self.fine
        let coarseCount = (fineCount + per - 1) / per
        var clo = [Float](repeating: 0, count: coarseCount), chi = [Float](repeating: 0, count: coarseCount)
        for c in 0..<coarseCount {
            var lo: Float = 0, hi: Float = 0
            for b in (c * per)..<min(fineCount, (c + 1) * per) { lo = min(lo, flo[b]); hi = max(hi, fhi[b]) }
            clo[c] = lo; chi[c] = hi
        }
        fineLo = flo; fineHi = fhi; coarseLo = clo; coarseHi = chi
    }

    /// Low and high of frames a..<b (a few frames are read from the sound itself).
    func range(_ sample: SampleBuffer, _ from: Int, _ to: Int) -> (Float, Float) {
        let a = max(0, from), b = min(length, sample.length, max(a + 1, to))
        guard b > a else { return (0, 0) }
        var lo: Float = 0, hi: Float = 0
        if b - a <= 2 * Self.fine {
            for i in a..<b { let v = (sample.left[i] + sample.right[i]) * 0.5; lo = min(lo, v); hi = max(hi, v) }
        } else if b - a <= 2 * Self.coarse {
            for k in (a / Self.fine)..<min(fineLo.count, (b + Self.fine - 1) / Self.fine) { lo = min(lo, fineLo[k]); hi = max(hi, fineHi[k]) }
        } else {
            for k in (a / Self.coarse)..<min(coarseLo.count, (b + Self.coarse - 1) / Self.coarse) { lo = min(lo, coarseLo[k]); hi = max(hi, coarseHi[k]) }
        }
        return (lo, hi)
    }

    /// One low / high per pixel column for the part of the sound on screen (`zoom`, `scroll` as the waveform's).
    func columns(_ sample: SampleBuffer, count: Int, zoom: Double, scroll: Double) -> [(Float, Float)] {
        let n = Double(sample.length)
        let span = n / max(1, zoom), first = scroll * n
        var out: [(Float, Float)] = []
        out.reserveCapacity(count)
        for c in 0..<count {
            let a = Int(first + span * Double(c) / Double(count))
            guard a < sample.length else { break }
            out.append(range(sample, a, Int(first + span * Double(c + 1) / Double(count))))
        }
        return out
    }

    // Kept per sound (the newest few); worked out on a background queue.
    private struct Entry { weak var sample: SampleBuffer?; let peaks: SamplerPeaks }
    private static var cache: [ObjectIdentifier: Entry] = [:]
    private static var order: [ObjectIdentifier] = []
    private static let lock = NSLock()
    private static let queue = DispatchQueue(label: "BreakBoss.samplerPeaks", qos: .userInitiated)

    static func cached(_ sample: SampleBuffer) -> SamplerPeaks? {
        lock.lock(); defer { lock.unlock() }
        guard let e = cache[ObjectIdentifier(sample)], e.sample === sample else { return nil }
        return e.peaks
    }

    /// The sound's peaks, on the main queue (at once when they're kept already).
    static func load(_ sample: SampleBuffer, _ done: @escaping (SamplerPeaks) -> Void) {
        if let p = cached(sample) { done(p); return }
        queue.async {
            let p = cached(sample) ?? SamplerPeaks(sample)
            lock.lock()
            let id = ObjectIdentifier(sample)
            cache[id] = Entry(sample: sample, peaks: p)
            order.removeAll { $0 == id }
            order.append(id)
            while order.count > 24 { cache[order.removeFirst()] = nil }
            lock.unlock()
            DispatchQueue.main.async { done(p) }
        }
    }
}

/// The cursor and the brighter played part over the waveform.
struct SamplerPlayhead: UIViewRepresentable {
    let playheads: SharedPlayheads
    let pad: Int
    let sample: SampleBuffer
    let zoom: CGFloat
    let scroll: CGFloat
    let color: UIColor
    /// Where a hit starts (START OFFSET; the end when the track plays backwards): the cursor waits there.
    let rest: Double

    func makeUIView(context: Context) -> CursorView {
        let view = CursorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = CursorView.probing
        view.accessibilityIdentifier = "samplerPlayhead"
        view.cursor = self
        return view
    }

    func updateUIView(_ view: CursorView, context: Context) { view.cursor = self }

    final class CursorView: UIView {
        var cursor: SamplerPlayhead? { didSet { changed(from: oldValue) } }
        private let wash = CALayer()
        private let played = CALayer()
        private let playedMask = CALayer()
        private let line = CALayer()
        private let head = CAShapeLayer()
        private var link: CADisplayLink?
        private var fast = false
        private var peaks: SamplerPeaks?
        private var imageToken = 0
        private var imageKey: [Double] = []

        // What's on screen: the voice it follows, where the cursor is, what's been played.
        private var voice: UInt32 = 0
        private var position: Double = 0
        private var playedLo: Double = 0, playedHi: Double = 0
        private var last: SharedPlayheads.Row?
        private var resetAt: Double?
        private var shownValue = ""
        /// For the UI tests (BREAKBOSS_UI_PROBE): hits followed, resets to rest, steps against the
        /// voice's direction, and how far the longest hit got.
        private var probeHits = 0, probeResets = 0, probeBacksteps = 0
        private var probeFurthest: Double = 0
        /// From the engine writing a sound to hearing it: the output's latency and one buffer.
        private let latency: Double = {
            #if os(iOS)
            let s = AVAudioSession.sharedInstance()
            return min(0.1, max(0, s.outputLatency + s.ioBufferDuration))
            #else
            return 0.01
            #endif
        }()

        override init(frame: CGRect) {
            super.init(frame: frame)
            for l in [wash, played, playedMask, line, head] as [CALayer] {
                l.actions = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "hidden": NSNull(),
                             "contents": NSNull(), "opacity": NSNull()]
            }
            playedMask.backgroundColor = UIColor.white.cgColor
            played.mask = playedMask
            played.contentsGravity = .resize
            wash.isHidden = true
            played.isHidden = true
            line.shadowOpacity = 0.9
            line.shadowRadius = 3
            line.shadowOffset = .zero
            head.shadowOpacity = 0.9
            head.shadowRadius = 3
            head.shadowOffset = .zero
            layer.addSublayer(wash)
            layer.addSublayer(played)
            layer.addSublayer(line)
            layer.addSublayer(head)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            guard window != nil else { return }
            let link = CADisplayLink(target: Proxy(self), selector: #selector(Proxy.tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
            setFast(false, force: true)
        }

        deinit { link?.invalidate() }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            played.frame = bounds
            CATransaction.commit()
            redrawPlayedImage()
            place()
        }

        /// The cursor's pale light: the mode's colour lifted toward white.
        private var paleColor: UIColor { cursor.map { Self.lifted($0.color, 0.6) } ?? .white }

        private static func lifted(_ c: UIColor, _ amount: CGFloat) -> UIColor {
            var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: 1)
        }

        private func changed(from old: SamplerPlayhead?) {
            guard let cursor else { return }
            let pale = paleColor.cgColor
            line.backgroundColor = pale
            line.shadowColor = cursor.color.cgColor
            head.fillColor = pale
            head.shadowColor = cursor.color.cgColor
            wash.backgroundColor = cursor.color.withAlphaComponent(0.07).cgColor
            if old?.sample !== cursor.sample || old?.pad != cursor.pad {
                voice = 0; last = nil; resetAt = nil
                peaks = nil
                SamplerPeaks.load(cursor.sample) { [weak self] p in
                    guard let self, self.cursor?.sample === cursor.sample else { return }
                    self.peaks = p
                    self.redrawPlayedImage()
                }
            }
            if voice == 0 { position = cursor.rest }
            redrawPlayedImage()
            place()
        }

        /// The brighter copy of the waveform that shows through over the played part. Drawn on a
        /// background queue whenever the sound, the zoom or the size changes, never while it plays.
        private func redrawPlayedImage() {
            guard let cursor, let peaks, bounds.width > 1, bounds.height > 1 else { return }
            let scale = window?.screen.scale ?? 2
            let key = [Double(ObjectIdentifier(cursor.sample).hashValue), Double(cursor.zoom), Double(cursor.scroll),
                       Double(bounds.width), Double(bounds.height), Double(scale), Double(paleColor.hashValue)]
            guard key != imageKey else { return }
            imageKey = key
            imageToken += 1
            let token = imageToken
            let size = bounds.size, sample = cursor.sample, zoom = Double(cursor.zoom), scroll = Double(cursor.scroll)
            // the played part: the mode's light lifted a little toward white, not the cursor's pale
            let bright = cursor.color, lift = Self.lifted(cursor.color, 0.3)
            DispatchQueue.global(qos: .userInitiated).async {
                let cols = peaks.columns(sample, count: max(1, Int(size.width * scale)), zoom: zoom, scroll: scroll)
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                let image = UIGraphicsImageRenderer(size: size, format: format).image { r in
                    let ctx = r.cgContext
                    let mid = size.height / 2, w = 1 / scale
                    ctx.setFillColor(lift.withAlphaComponent(0.5).cgColor)
                    for (c, (lo, hi)) in cols.enumerated() {
                        ctx.fill(CGRect(x: CGFloat(c) * w, y: mid - CGFloat(hi) * mid * 0.92, width: w,
                                        height: max(w, CGFloat(hi - lo) * mid * 0.92)))
                    }
                    ctx.setFillColor(bright.withAlphaComponent(0.5).cgColor)
                    ctx.fill(CGRect(x: 0, y: mid - 0.5, width: size.width, height: 1))
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.imageToken == token else { return }
                    self.played.contents = image.cgImage
                    self.played.contentsScale = scale
                }
            }
        }

        private func setFast(_ on: Bool, force: Bool = false) {
            guard let link, on != fast || force else { return }
            fast = on
            link.preferredFrameRateRange = on ? CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
                                              : CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        }

        fileprivate func tick(_ link: CADisplayLink) {
            guard let cursor else { return }
            let now = link.targetTimestamp
            let row = cursor.playheads.row(cursor.pad)
            if row.id != 0 {
                resetAt = nil
                // the audio thread has stopped (paused): the cursor stays where it is
                if now - row.time > max(0.25, row.block * 4) { setFast(false); return }
                setFast(true)
                if row.id != voice {
                    // a new hit: the cursor starts again where the voice started
                    voice = row.id
                    playedLo = row.start; playedHi = row.start
                    position = row.start
                    probeHits += 1
                }
                last = row
                let before = position
                position = heard(row, now)
                if Self.probing && row.loopEnd < 0 {
                    if (row.speed > 0 && position < before - 0.001) || (row.speed < 0 && position > before + 0.001) { probeBacksteps += 1 }
                    probeFurthest = max(probeFurthest, abs(position - row.start))
                }
                playedLo = min(playedLo, position); playedHi = max(playedHi, position)
                place()
                return
            }
            guard voice != 0 else { setFast(false); return }
            // the voice has ended (or STOP): it's still heard for the output's latency, then the cursor resets
            if resetAt == nil { resetAt = now + latency }
            if let last, let r = resetAt, now < r {
                let before = position
                position = heard(last, now, allowAhead: latency)
                // a short hit can end in the engine before most of it is heard (a big output buffer):
                // the cursor still travels here, so the test counts this part too
                if Self.probing && last.loopEnd < 0 {
                    if (last.speed > 0 && position < before - 0.001) || (last.speed < 0 && position > before + 0.001) { probeBacksteps += 1 }
                    probeFurthest = max(probeFurthest, abs(position - last.start))
                }
                playedLo = min(playedLo, position); playedHi = max(playedHi, position)
                place()
                return
            }
            voice = 0; last = nil; resetAt = nil
            position = cursor.rest
            probeResets += 1
            setFast(false)
            place()
        }

        /// Where the voice is heard at `now`: its last place, moved on by its speed for the time
        /// since then, less the time the sound takes to reach the speaker.
        private func heard(_ row: SharedPlayheads.Row, _ now: Double, allowAhead extra: Double = 0) -> Double {
            let elapsed = min(now - row.time - latency, row.block + extra)
            var p = row.position + row.speed * elapsed
            if row.loopEnd > row.loopStart && row.loopStart >= 0 {
                let len = row.loopEnd - row.loopStart
                if row.speed > 0 && p > row.loopEnd { p = row.loopStart + (p - row.loopStart).truncatingRemainder(dividingBy: len) }
                if row.speed < 0 && p < row.loopStart { p = row.loopStart }
            }
            // just after a hit the voice has moved on in the engine but isn't heard yet: hold it at the start
            if elapsed < 0 {
                if row.speed > 0 && row.position >= row.start && p < row.start { p = row.start }
                if row.speed < 0 && row.position <= row.start && p > row.start { p = row.start }
            }
            return min(1, max(0, p))
        }

        private func place() {
            guard let cursor, bounds.width > 0 else { return }
            let w = bounds.width, h = bounds.height
            func x(_ f: Double) -> CGFloat { CGFloat((f - Double(cursor.scroll)) * Double(cursor.zoom)) * w }
            let cx = x(position)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let playing = voice != 0
            line.frame = CGRect(x: cx - 0.75, y: 0, width: 1.5, height: h)
            line.opacity = playing ? 1 : 0.55
            line.isHidden = cx < -4 || cx > w + 4
            let hw: CGFloat = 6
            if head.path == nil {
                let tri = UIBezierPath()
                tri.move(to: .zero); tri.addLine(to: CGPoint(x: 2 * hw, y: 0)); tri.addLine(to: CGPoint(x: hw, y: 9)); tri.close()
                head.path = tri.cgPath
            }
            head.frame = CGRect(x: cx - hw, y: 0, width: 2 * hw, height: 9)
            head.opacity = line.opacity
            head.isHidden = line.isHidden
            let a = x(playedLo), b = x(playedHi)
            let showPlayed = playing && b - a > 0.5
            played.isHidden = !showPlayed
            wash.isHidden = !showPlayed
            if showPlayed {
                playedMask.frame = CGRect(x: a, y: 0, width: b - a, height: h)
                wash.frame = CGRect(x: a, y: 0, width: b - a, height: h)
            }
            CATransaction.commit()
            // for the UI tests: where the cursor is (part of the sound), whether a hit is playing, and the counts above
            guard Self.probing else { return }
            let value = String(format: "%.3f %@ hits=%d resets=%d back=%d far=%.3f", position, playing ? "playing" : "rest",
                               probeHits, probeResets, probeBacksteps, probeFurthest)
            if value != shownValue { shownValue = value; accessibilityValue = value }
        }

        static let probing = ProcessInfo.processInfo.environment["BREAKBOSS_UI_PROBE"] == "1"

        /// Keeps the display link from holding the view alive.
        private final class Proxy: NSObject {
            weak var view: CursorView?
            init(_ view: CursorView) { self.view = view }
            @objc func tick(_ link: CADisplayLink) {
                if let view { view.tick(link) } else { link.invalidate() }
            }
        }
    }
}
