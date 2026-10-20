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
// loop when it loops. As on Face 1's screen (Tyrone, Oct 20) the sound lights the wave up like
// phosphor: a bloom at the cursor that swells with how loud the sound is right there, a lit trail
// behind it that fades, and the played part left gently brighter. All of that is layers moved by
// the display link (no redrawing while it plays); when nothing plays the link drops to a slow
// check (10 a second) and nothing is redrawn, and it stops when the window is closed, minimized
// or on another page.

/// A sound's peaks (low and high, the two channels mixed) in blocks of 32 and 1024 frames, so
/// any zoom draws from at most a few dozen numbers per pixel column.
final class SamplerPeaks {
    static let fine = 32, coarse = 1_024
    let length: Int
    /// The loudest the sound gets (for the cursor's bloom: a soft sound lights up as clearly as a loud one).
    let loudest: Float
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
        loudest = max(clo.map { -$0 }.max() ?? 0, chi.max() ?? 0)
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


/// The SAMPLE page's waveform in Face 1's light (Tyrone, Oct 20): the sound's highs and lows as a
/// faint phosphor band edged by glowing traces, and once zoomed in far enough the wave itself as
/// one glowing line, like the trace on Face 1's screen. Glow comes from wide soft strokes under a
/// bright core, as on Face 1 (no blur), so a redraw stays cheap. Built once per sound, zoom and size.
struct SamplerPhosphor {
    var band = Path(), high = Path(), low = Path(), line = Path()
    /// Zoomed in far enough to see the wave itself (a few frames per point).
    var showsLine = false

    init(_ sample: SampleBuffer, peaks: SamplerPeaks?, size: CGSize, zoom: Double, scroll: Double, pointsPerColumn: CGFloat = 2) {
        let n = sample.length
        guard n > 1, size.width > 1 else { return }
        let mid = size.height / 2, k = mid * 0.92
        func y(_ v: Float) -> CGFloat { mid - CGFloat(max(-1, min(1, v))) * k }
        let span = Double(n) / max(1, zoom), first = scroll * Double(n)
        if span / Double(size.width) <= 3 {
            // a few frames per point: the wave itself, through every frame
            showsLine = true
            let a = max(0, Int(first) - 1), b = min(n - 1, Int(first + span) + 1)
            for i in a...b {
                let p = CGPoint(x: CGFloat((Double(i) - first) / span) * size.width, y: y((sample.left[i] + sample.right[i]) * 0.5))
                if i == a { line.move(to: p) } else { line.addLine(to: p) }
            }
            return
        }
        guard let peaks else { return }
        let count = max(2, Int(size.width / pointsPerColumn))
        let cols = peaks.columns(sample, count: count, zoom: zoom, scroll: scroll)
        guard cols.count > 1 else { return }
        let step = size.width / CGFloat(count)
        // smooth curves through the midpoints, so the edges have no sharp corners (Face 1's curve)
        func curve(_ values: [Float], into path: inout Path) {
            path.move(to: CGPoint(x: 0, y: y(values[0])))
            for i in 1..<values.count - 1 {
                let p = CGPoint(x: CGFloat(i) * step, y: y(values[i])), q = CGPoint(x: CGFloat(i + 1) * step, y: y(values[i + 1]))
                path.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
            }
            path.addLine(to: CGPoint(x: CGFloat(values.count - 1) * step, y: y(values[values.count - 1])))
        }
        let hi = cols.map { $0.1 }, lo = cols.map { $0.0 }
        curve(hi, into: &high)
        curve(lo, into: &low)
        band = high
        for i in stride(from: lo.count - 1, through: 0, by: -1) { band.addLine(to: CGPoint(x: CGFloat(i) * step, y: y(lo[i]))) }
        band.closeSubpath()
    }

    /// Draws it in a face's light. `lit` 0 = resting on the page, 1 = lit by the sound playing.
    /// `thin` < 1 narrows the glow for a small strip (the scroll bar's whole-sound view).
    func draw(in ctx: inout GraphicsContext, light: FaceLight, lit: Double = 0, thin: CGFloat = 1) {
        let soft = StrokeStyle(lineWidth: (6 + 3 * lit) * thin, lineCap: .round, lineJoin: .round)
        let mid = StrokeStyle(lineWidth: (3 + lit) * thin, lineCap: .round, lineJoin: .round)
        let core = StrokeStyle(lineWidth: max(0.8, (1.3 + 0.4 * lit) * thin), lineCap: .round, lineJoin: .round)
        if showsLine {
            ctx.stroke(line, with: .color(light.glow.opacity(0.16 + 0.14 * lit)), style: soft)
            ctx.stroke(line, with: .color(light.glow.opacity(0.34 + 0.2 * lit)), style: mid)
            ctx.stroke(line, with: .color(light.blend(0.6 + 0.4 * lit)), style: core)
            return
        }
        ctx.fill(band, with: .color(light.blend(0.3 + 0.4 * lit).opacity(0.32 + 0.3 * lit)))
        for edge in [high, low] {
            ctx.stroke(edge, with: .color(light.glow.opacity(0.16 + 0.14 * lit)), style: soft)
            ctx.stroke(edge, with: .color(light.glow.opacity(0.34 + 0.2 * lit)), style: mid)
            ctx.stroke(edge, with: .color(light.blend(0.55 + 0.45 * lit)), style: core)
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
    /// Which face's light (FaceLight) the lit wave glows in.
    var face = "modern"
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
        private let played = CALayer()
        private let playedMask = CALayer()
        /// The lit trail behind the cursor (bright at the cursor, fading back to the played part's glow).
        private let trailMask = CAGradientLayer()
        /// The played part before the trail: gently lit.
        private let doneMask = CALayer()
        /// The phosphor bloom at the cursor.
        private let bloom = CAGradientLayer()
        /// How loud the sound is at the cursor, 0...1 of its loudest (eased like Face 1's glow).
        private var level: Double = 0
        private var lastTick: Double = 0
        private var fading = false
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
            for l in [played, playedMask, trailMask, doneMask, bloom, line, head] as [CALayer] {
                l.actions = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "hidden": NSNull(),
                             "contents": NSNull(), "opacity": NSNull()]
            }
            doneMask.backgroundColor = UIColor.white.withAlphaComponent(0.3).cgColor
            trailMask.startPoint = CGPoint(x: 0, y: 0.5)
            trailMask.endPoint = CGPoint(x: 1, y: 0.5)
            trailMask.colors = [UIColor.white.withAlphaComponent(0.3).cgColor, UIColor.white.cgColor]
            playedMask.addSublayer(doneMask)
            playedMask.addSublayer(trailMask)
            played.mask = playedMask
            played.contentsGravity = .resize
            played.isHidden = true
            bloom.startPoint = CGPoint(x: 0, y: 0.5)
            bloom.endPoint = CGPoint(x: 1, y: 0.5)
            bloom.isHidden = true
            line.shadowOpacity = 0.9
            line.shadowRadius = 3
            line.shadowOffset = .zero
            head.shadowOpacity = 0.9
            head.shadowRadius = 3
            head.shadowOffset = .zero
            layer.addSublayer(played)
            layer.addSublayer(bloom)
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
            playedMask.frame = bounds
            CATransaction.commit()
            redrawPlayedImage()
            place()
        }

        /// The cursor's pale light: the mode's colour lifted toward white.
        private var paleColor: UIColor { cursor.map { Self.lifted($0.color, 0.6) } ?? .white }

        /// A face's bright core (FaceLight), for the bloom.
        static func coreColor(_ face: String) -> UIColor { FaceLight.of(face).uiColor(1) }

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
            let core = Self.coreColor(cursor.face)
            bloom.colors = [core.withAlphaComponent(0).cgColor, core.withAlphaComponent(0.55).cgColor, core.withAlphaComponent(0).cgColor]
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
                       Double(bounds.width), Double(bounds.height), Double(scale), Double(cursor.face.hashValue)]
            guard key != imageKey else { return }
            imageKey = key
            imageToken += 1
            let token = imageToken
            let size = bounds.size, sample = cursor.sample, zoom = Double(cursor.zoom), scroll = Double(cursor.scroll)
            // the lit wave: the same phosphor band and traces as the page's, in the face's light, burning bright
            let light = FaceLight.of(cursor.face)
            DispatchQueue.global(qos: .userInitiated).async {
                let wave = SamplerPhosphor(sample, peaks: peaks, size: size, zoom: zoom, scroll: scroll)
                let format = UIGraphicsImageRendererFormat()
                format.scale = scale
                let image = UIGraphicsImageRenderer(size: size, format: format).image { r in
                    let ctx = r.cgContext
                    let glow = light.uiColor(0), hot = light.uiColor(1), warm = light.uiColor(0.7)
                    let edges = wave.showsLine ? [wave.line] : [wave.high, wave.low]
                    if !wave.showsLine {
                        ctx.addPath(wave.band.cgPath)
                        ctx.setFillColor(warm.withAlphaComponent(0.6).cgColor)
                        ctx.fillPath()
                    }
                    ctx.setLineCap(.round); ctx.setLineJoin(.round)
                    for (width, color) in [(9.0, glow.withAlphaComponent(0.3)), (4.0, glow.withAlphaComponent(0.55)), (1.7, hot)] as [(CGFloat, UIColor)] {
                        for e in edges { ctx.addPath(e.cgPath) }
                        ctx.setLineWidth(width)
                        ctx.setStrokeColor(color.cgColor)
                        ctx.strokePath()
                    }
                    ctx.setFillColor(warm.withAlphaComponent(0.5).cgColor)
                    ctx.fill(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1))
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
            link.preferredFrameRateRange = on ? CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                                              : CAFrameRateRange(minimum: 8, maximum: 15, preferred: 10)
        }

        /// For the UI tests: the main thread's time per playing frame (the animation's own cost), averaged.
        private var probeTickTime: Double = 0, probeTickCount = 0
        /// The probe's own time inside a frame (its text and the CPU reading), left out of the frame's cost.
        private var probeOwnTime: Double = 0

        fileprivate func tick(_ link: CADisplayLink) {
            guard Self.probing else { step(link); return }
            let t0 = CACurrentMediaTime()
            probeOwnTime = 0
            step(link)
            if voice != 0 { probeTickTime += CACurrentMediaTime() - t0 - probeOwnTime; probeTickCount += 1 }
        }

        private func step(_ link: CADisplayLink) {
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
            guard voice != 0 else { setFast(false); if Self.probing { place() }; return }
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
            if playing {
                // how loud the sound is at the cursor (of its loudest): up at once, letting go over
                // about 80 ms, like Face 1's glow
                let t = CACurrentMediaTime(), dt = min(0.1, max(0.001, t - lastTick))
                lastTick = t
                var loud = 0.0
                if let peaks, peaks.loudest > 0.000_1 {
                    let i = Int(position * Double(peaks.length))
                    let (lo, hi) = peaks.range(cursor.sample, i - 384, i + 384)
                    loud = Double(min(1, max(-lo, hi) / peaks.loudest))
                }
                level = loud > level ? loud : level + (loud - level) * (1 - exp(-dt / 0.08))
                if fading || played.isHidden {
                    fading = false
                    played.removeAllAnimations(); bloom.removeAllAnimations()
                    played.opacity = 1; bloom.opacity = 1
                }
                played.isHidden = false
                bloom.isHidden = cx < -40 || cx > w + 40
                // the lit trail: about a third of a second of the sound behind the cursor, fading back
                let forward = (last?.speed ?? 1) >= 0
                let trail = max(18, CGFloat(abs(last?.speed ?? 0) * 0.3 * Double(cursor.zoom)) * w)
                let t0 = forward ? max(a, cx - trail) : cx, t1 = forward ? cx : min(b, cx + trail)
                trailMask.frame = CGRect(x: t0, y: 0, width: max(0, t1 - t0), height: h)
                trailMask.startPoint = CGPoint(x: forward ? 0 : 1, y: 0.5)
                trailMask.endPoint = CGPoint(x: forward ? 1 : 0, y: 0.5)
                doneMask.frame = forward ? CGRect(x: a, y: 0, width: max(0, t0 - a), height: h)
                                         : CGRect(x: t1, y: 0, width: max(0, b - t1), height: h)
                // the bloom: wider and brighter the louder the sound is right there
                let bw = 14 + 46 * CGFloat(level)
                bloom.frame = CGRect(x: cx - bw / 2, y: 0, width: bw, height: h)
                bloom.opacity = Float(0.35 + 0.65 * level)
            } else if !played.isHidden && !fading {
                // the hit has ended: the light fades out like phosphor (the render server runs it)
                fading = true
                for l in [played, bloom] as [CALayer] {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = l.opacity
                    fade.toValue = 0
                    fade.duration = 0.35
                    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    l.opacity = 0
                    l.add(fade, forKey: "fade")
                }
                level = 0
            }
            CATransaction.commit()
            // for the UI tests: where the cursor is (part of the sound), whether a hit is playing, and the counts above
            guard Self.probing else { return }
            let p0 = CACurrentMediaTime()
            defer { probeOwnTime += CACurrentMediaTime() - p0 }
            let value = String(format: "%.3f %@ hits=%d resets=%d back=%d far=%.3f cpu=%.1f frame=%.0fus", position, playing ? "playing" : "rest",
                               probeHits, probeResets, probeBacksteps, probeFurthest, Self.processCPU(),
                               probeTickCount > 0 ? probeTickTime / Double(probeTickCount) * 1e6 : 0)
            if value != shownValue { shownValue = value; accessibilityValue = value }
        }

        static let probing = ProcessInfo.processInfo.environment["BREAKBOSS_UI_PROBE"] == "1"

        /// For the UI tests: the whole app's CPU (percent of one core) over the last second or so.
        private static var cpuMark: (wall: Double, cpu: Double)?
        private static var cpuShown: Double = 0
        static func processCPU() -> Double {
            var u = rusage()
            getrusage(RUSAGE_SELF, &u)
            let cpu = Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
            let wall = CACurrentMediaTime()
            guard let m = cpuMark else { cpuMark = (wall, cpu); return 0 }
            if wall - m.wall >= 1 { cpuShown = (cpu - m.cpu) / (wall - m.wall) * 100; cpuMark = (wall, cpu) }
            return cpuShown
        }

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

extension FaceLight {
    /// `blend` as a UIColor (safe off the main thread, for the lit wave drawn in the background).
    func uiColor(_ t: Double) -> UIColor {
        let c = glowRGB + (coreRGB - glowRGB) * min(1, max(0, t))
        return UIColor(red: c.x, green: c.y, blue: c.z, alpha: 1)
    }
}
