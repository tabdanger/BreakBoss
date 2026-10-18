import SwiftUI
import UIKit

/// A Canvas that only redraws when `key` changes (SwiftUI otherwise repaints a Canvas every time
/// its parent's body runs). `key` must cover everything `draw` reads.
struct EquatableCanvas: View, Equatable {
    let key: Int
    let draw: (inout GraphicsContext, CGSize) -> Void
    init(key: Int, draw: @escaping (inout GraphicsContext, CGSize) -> Void) { self.key = key; self.draw = draw }
    static func == (a: EquatableCanvas, b: EquatableCanvas) -> Bool { a.key == b.key }
    var body: some View { Canvas { ctx, size in draw(&ctx, size) } }
}

/// Two fingers on the sequencer's grid slide it: sideways along a long pattern and up and down
/// through the rack. One finger keeps drawing. A two-finger swipe on a trackpad does the same (the
/// rack's own scrolling takes the up and down). Sits behind the grid inside the rack's ScrollView,
/// finds that UIScrollView and adds the pans to it.
struct GridScrollHook: UIViewRepresentable {
    /// `trackpad`: a trackpad swipe, so no finger is drawing on the grid.
    var began: (_ trackpad: Bool) -> Void
    /// Sideways travel since the two fingers went down, in points.
    var sideways: (CGFloat) -> Void
    var ended: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> HookView {
        let view = HookView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: HookView, context: Context) {
        context.coordinator.hook = self
        view.coordinator = context.coordinator
    }

    final class HookView: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                var v = self.superview
                while let current = v, !(current is UIScrollView) { v = current.superview }
                if let scrollView = v as? UIScrollView { self.coordinator?.attach(to: scrollView, area: self) }
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var hook: GridScrollHook?
        private weak var scrollView: UIScrollView?
        private weak var area: UIView?
        private var pan: UIPanGestureRecognizer?
        private var swipe: UIPanGestureRecognizer?
        private var touch: UILongPressGestureRecognizer?
        private var startY: CGFloat = 0
        /// After the fingers lift the grid keeps gliding and slows down, like any iOS scroll view.
        private var link: CADisplayLink?
        private var velocity = CGPoint.zero
        private var glideX: CGFloat = 0
        private var glidesY = false

        func attach(to scrollView: UIScrollView, area: UIView) {
            self.area = area
            guard self.scrollView !== scrollView else { return }
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            if let swipe { swipe.view?.removeGestureRecognizer(swipe) }
            if let touch { touch.view?.removeGestureRecognizer(touch) }
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.cancelsTouchesInView = false
            pan.delegate = self
            scrollView.addGestureRecognizer(pan)
            // the rack's own scrolling stays one finger, so the two never fight
            scrollView.panGestureRecognizer.maximumNumberOfTouches = 1
            self.pan = pan
            // a trackpad's two-finger swipe: scroll events only, fingers on the glass stay with the pan
            let swipe = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
            swipe.allowedScrollTypesMask = .continuous
            swipe.allowedTouchTypes = []
            swipe.delegate = self
            scrollView.addGestureRecognizer(swipe)
            self.swipe = swipe
            // a finger landing anywhere on the rack stops a glide, like a scroll view
            let touch = UILongPressGestureRecognizer(target: self, action: #selector(touched(_:)))
            touch.minimumPressDuration = 0
            touch.cancelsTouchesInView = false
            touch.delaysTouchesBegan = false
            touch.delegate = self
            scrollView.addGestureRecognizer(touch)
            self.touch = touch
            self.scrollView = scrollView
        }

        @objc private func panned(_ g: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            let moved = g.translation(in: scrollView.superview)
            switch g.state {
            case .began:
                stopGlide(notify: true)
                startY = scrollView.contentOffset.y
                hook?.began(false)
            case .changed:
                let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                scrollView.contentOffset.y = min(maxY, max(0, startY - moved.y))
                hook?.sideways(moved.x)
            case .ended:
                glide(from: moved.x, velocity: g.velocity(in: scrollView.superview), vertical: true)
            default:
                hook?.ended()
            }
        }

        @objc private func swiped(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                stopGlide(notify: true)
                hook?.began(true)
            case .changed: hook?.sideways(g.translation(in: g.view?.superview).x)
            case .ended:
                let v = g.velocity(in: g.view?.superview)
                glide(from: g.translation(in: g.view?.superview).x, velocity: CGPoint(x: v.x, y: 0), vertical: false)
            default: hook?.ended()
            }
        }

        @objc private func touched(_ g: UILongPressGestureRecognizer) {
            if g.state == .began { stopGlide(notify: true) }
        }

        private func glide(from x: CGFloat, velocity v: CGPoint, vertical: Bool) {
            guard hypot(v.x, vertical ? v.y : 0) > 60 else { hook?.ended(); return }
            glideX = x
            velocity = CGPoint(x: v.x, y: vertical ? v.y : 0)
            glidesY = vertical
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        @objc private func step(_ link: CADisplayLink) {
            let dt = CGFloat(max(1.0 / 240, min(1.0 / 30, link.targetTimestamp - link.timestamp)))
            // UIScrollView's normal deceleration: 0.998 per millisecond
            let decay = pow(0.998, dt * 1000)
            velocity.x *= decay
            velocity.y *= decay
            if abs(velocity.x) > 1 {
                glideX += velocity.x * dt
                hook?.sideways(glideX)
            }
            if glidesY, let scrollView {
                let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                let y = scrollView.contentOffset.y - velocity.y * dt
                scrollView.contentOffset.y = min(maxY, max(0, y))
                if y <= 0 || y >= maxY { velocity.y = 0 }
            }
            if abs(velocity.x) < 12 && abs(velocity.y) < 12 { stopGlide(notify: true) }
        }

        private func stopGlide(notify: Bool) {
            guard let link else { return }
            link.invalidate()
            self.link = nil
            if notify { hook?.ended() }
        }

        deinit { link?.invalidate() }

        /// Only on the grid (the rack scrolls with one finger).
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            if g === touch { return link != nil }
            guard let area else { return false }
            return area.bounds.contains(g.location(in: area))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// A thin line the display link moves every frame: `position` is the playhead's place across the
/// view (0...1, nil when nothing plays here); `offScreen` is called when it leaves the view.
struct PlayheadLine: UIViewRepresentable {
    var color: UIColor
    var position: () -> CGFloat?
    var offScreen: () -> Void

    func makeUIView(context: Context) -> LineView {
        let view = LineView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.line = self
        return view
    }

    func updateUIView(_ view: LineView, context: Context) { view.line = self }

    final class LineView: UIView {
        var line: PlayheadLine? { didSet { bar.backgroundColor = line?.color.cgColor } }
        private let bar = CALayer()
        private var link: CADisplayLink?
        private var lastNudge: CFTimeInterval = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            bar.isHidden = true
            bar.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
            layer.addSublayer(bar)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            link?.invalidate()
            link = nil
            guard window != nil else { return }
            let link = CADisplayLink(target: Proxy(self), selector: #selector(Proxy.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        deinit { link?.invalidate() }

        fileprivate func tick(_ link: CADisplayLink) {
            guard let line, let f = line.position() else { bar.isHidden = true; return }
            if f < 0 || f > 1 {
                bar.isHidden = true
                // ask the window to catch up, at most every tenth of a second
                if link.timestamp - lastNudge > 0.1 { lastNudge = link.timestamp; line.offScreen() }
                return
            }
            bar.isHidden = false
            bar.frame = CGRect(x: f * bounds.width - 1, y: 0, width: 2, height: bounds.height)
        }

        /// Keeps the display link from holding the view alive.
        private final class Proxy: NSObject {
            weak var view: LineView?
            init(_ view: LineView) { self.view = view }
            @objc func tick(_ link: CADisplayLink) {
                if let view { view.tick(link) } else { link.invalidate() }
            }
        }
    }
}
