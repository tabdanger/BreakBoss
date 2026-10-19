import SwiftUI
import UIKit

/// The channel rack's grab handle (Tyrone, Oct 19): a thin UIKit strip over the two studs on the left
/// of every track's tab. A touch on a track's studs grabs that track at once (a press with no hold,
/// so the rack's scroll never takes the finger); moving reports the finger's y in the rack, and near
/// the top or bottom of the visible rack the rack scrolls on its own so a track can go anywhere.
/// One strip for the whole rack, laid over the rows, so the grab survives the rows moving under it.
struct TrackGrabStrip: UIViewRepresentable {
    /// The track (pad) whose studs are at this y in the rack, if any.
    let grip: (CGFloat) -> Int?
    let began: (Int, CGFloat) -> Void
    let moved: (CGFloat) -> Void
    let ended: () -> Void

    func makeCoordinator() -> Grab { Grab() }

    func makeUIView(context: Context) -> StripView {
        let v = StripView()
        v.backgroundColor = .clear
        v.grab = context.coordinator
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Grab.pressed(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.delegate = context.coordinator
        v.addGestureRecognizer(press)
        context.coordinator.view = v
        return v
    }

    func updateUIView(_ v: StripView, context: Context) {
        let c = context.coordinator
        c.grip = grip; c.began = began; c.moved = moved; c.ended = ended
    }

    static func dismantleUIView(_ v: StripView, coordinator: Grab) { coordinator.stopScrolling() }

    /// Takes touches only on a track's studs; anywhere else in the strip falls through.
    final class StripView: UIView {
        weak var grab: Grab?
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard bounds.contains(point) else { return false }
            return grab?.grip(point.y) != nil
        }
    }

    final class Grab: NSObject, UIGestureRecognizerDelegate {
        weak var view: UIView?
        var grip: (CGFloat) -> Int? = { _ in nil }
        var began: (Int, CGFloat) -> Void = { _, _ in }
        var moved: (CGFloat) -> Void = { _ in }
        var ended: () -> Void = {}
        private weak var press: UILongPressGestureRecognizer?
        private var link: CADisplayLink?
        private var grabbing = false

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let v = view else { return false }
            return grip(g.location(in: v).y) != nil
        }

        /// The rack's scroll waits for the grab to fail (a touch off the studs), so a fast drag on the
        /// studs can never be taken over by the scroll halfway.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }

        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            guard let v = view else { return }
            let y = g.location(in: v).y
            switch g.state {
            case .began:
                guard let pad = grip(y) else { return }
                press = g
                grabbing = true
                began(pad, y)
                startScrolling()
            case .changed:
                if grabbing { moved(y) }
            default:
                if grabbing {
                    grabbing = false
                    stopScrolling()
                    moved(y)     // a quick flick's last move only comes with the lift
                    ended()
                }
            }
        }

        /// The scroll view the rack scrolls in (SwiftUI's ScrollView is a UIScrollView underneath).
        private var scroller: UIScrollView? {
            var v = view?.superview
            while let s = v, !(s is UIScrollView) { v = s.superview }
            return v as? UIScrollView
        }

        private func startScrolling() {
            stopScrolling()
            let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }

        func stopScrolling() { link?.invalidate(); link = nil }

        /// Within 44 points of the visible rack's top or bottom edge, the rack scrolls that way,
        /// faster the closer the finger is, and the track keeps riding under the finger.
        @objc private func tick(_ l: CADisplayLink) {
            guard grabbing, let g = press, let v = view, let sv = scroller else { return }
            let inView = g.location(in: sv).y - sv.contentOffset.y        // the finger in the visible rack
            let edge: CGFloat = 44
            let h = sv.bounds.height
            var speed: CGFloat = 0
            if inView < edge { speed = -(edge - inView) / edge }
            else if inView > h - edge { speed = (inView - (h - edge)) / edge }
            guard speed != 0 else { return }
            let maxY = max(0, sv.contentSize.height + sv.adjustedContentInset.bottom - h)
            let minY = -sv.adjustedContentInset.top
            let step = max(-1, min(1, speed)) * 900 * CGFloat(l.targetTimestamp - l.timestamp)
            let next = min(maxY, max(minY, sv.contentOffset.y + step))
            guard next != sv.contentOffset.y else { return }
            sv.contentOffset.y = next
            moved(g.location(in: v).y)
        }
    }
}
