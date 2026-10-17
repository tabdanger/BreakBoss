import SwiftUI
import UIKit

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
        private var startY: CGFloat = 0

        func attach(to scrollView: UIScrollView, area: UIView) {
            self.area = area
            guard self.scrollView !== scrollView else { return }
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            if let swipe { swipe.view?.removeGestureRecognizer(swipe) }
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
            self.scrollView = scrollView
        }

        @objc private func panned(_ g: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            let moved = g.translation(in: scrollView.superview)
            switch g.state {
            case .began:
                startY = scrollView.contentOffset.y
                hook?.began(false)
            case .changed:
                let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                scrollView.contentOffset.y = min(maxY, max(0, startY - moved.y))
                hook?.sideways(moved.x)
            default:
                hook?.ended()
            }
        }

        @objc private func swiped(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began: hook?.began(true)
            case .changed: hook?.sideways(g.translation(in: g.view?.superview).x)
            default: hook?.ended()
            }
        }

        /// Only on the grid (the rack scrolls with one finger).
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let area else { return false }
            return area.bounds.contains(g.location(in: area))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
