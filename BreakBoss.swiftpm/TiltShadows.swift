// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import CoreMotion
import SwiftUI
import UIKit

// MARK: - Shadow tilt (Tyrone, Oct 31: MS26's shadow tilt on Face 1's knobs and pads, stronger)
//
// Tilt the iPad and the knob and pad shadows slide toward the low side, the way a real machine's
// would under a ceiling light. Stand the screen up and they throw long; lean it back on the hinge
// and they pull in. At the usual playing angle (on a stand) the extra shadow is empty, so Face 1
// looks exactly like its picture until you tilt.
//
// Made more real than MS26's: each knob throws a cylinder's shadow (its round foot swept along
// the light, a dark core with a soft edge that widens the further it falls, plus a contact shadow
// hugging the base) and each pad throws its own rubber block's shadow into the well. Nothing is
// ever drawn on a knob or a pad: the layer is cut away over them.
//
// Speed: one motion reader, on its own queue (never the main thread, never the audio thread),
// 30 a second (15 in Low Power Mode), smoothed there and passed on only when the change is
// visible, so an iPad lying still costs nothing. The shadows are Core Animation layers made once;
// a change only moves them (GPU work, no redraw). The reader runs only while Face 1 is on screen
// and the app (or the plug-in's host) is in front; MOTION LIGHT off or Reduce Motion stops it.
// No permission is needed: device motion isn't one of the sensors iOS asks about.

/// The shadow maths, kept apart so the self-test can check it without a sensor.
enum TiltShadowMath {
    /// Gravity's downward part (screen y) at the usual playing angle: the shadows are the plate's own here.
    static let restingDown: Double = 0.55
    static let hingeRange: Double = 0.45

    /// Where the shadows lean, -1...1 each way (x right, y down), from gravity on the screen's axes.
    /// Leaning the screen back only pulls them in a little: a ceiling light can't throw a shadow up the plate.
    static func lean(gravityX gx: Double, gravityY gy: Double) -> CGVector {
        let x = min(max(gx * 1.4, -1), 1)
        let y = min(max((gy - restingDown) / hingeRange, -1), 1)
        return CGVector(dx: x, dy: y > 0 ? y : y * 0.3)
    }

    /// How strongly the extra shadow shows: none at rest, full a little way into a tilt.
    static func strength(_ lean: CGVector) -> CGFloat { min(1, hypot(lean.dx, lean.dy) * 2) }

    /// Gravity in device axes (portrait: x right edge, y top edge) turned to the screen's axes.
    static func screen(_ x: Double, _ y: Double, _ o: UIInterfaceOrientation) -> (Double, Double) {
        switch o {
        case .portrait: return (x, -y)
        case .portraitUpsideDown: return (-x, y)
        case .landscapeLeft: return (y, x)
        default: return (-y, -x)                   // landscapeRight
        }
    }

    // Shapes, in the plate's own pixels.
    /// A Face 1 knob's round body (black skirt) is about 1.32x the layout's cap radius (measured on the plates).
    static let knobBody: CGFloat = 1.32
    /// Full tilt throws a knob's shadow about this many body radii past its foot (MS26: half a radius).
    static let knobReach: CGFloat = 1.25
    /// Full tilt throws a pad's shadow this far across the well (the pads stand lower than the knobs).
    static let padReach: CGFloat = 16
    static let padCorner: CGFloat = 6
}

/// The one motion reader for Face 1's shadows.
final class TiltShadowMotion {
    static let shared = TiltShadowMotion()

    /// The latest lean, main thread.
    private(set) var lean = CGVector.zero

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "BreaKing shadow tilt"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()
    private let listeners = NSHashTable<TiltShadowUIView>.weakObjects()
    private var background = false
    private var running = false
    private var orientation: UIInterfaceOrientation = .landscapeRight
    private var observers: [NSObjectProtocol] = []

    // sensor queue only
    private var smooth = (x: 0.0, y: TiltShadowMath.restingDown)
    private var sent = CGVector.zero
    private var primed = false

    static var enabled: Bool {
        (UserDefaults.standard.object(forKey: MaterialLight.settingKey) as? Bool ?? true) && !UIAccessibility.isReduceMotionEnabled
    }

    private init() {
        let center = NotificationCenter.default
        // the app's own and, in the plug-in, the host's going away and coming back
        let away: [Notification.Name] = [UIScene.didEnterBackgroundNotification, .NSExtensionHostDidEnterBackground]
        let back: [Notification.Name] = [UIScene.willEnterForegroundNotification, .NSExtensionHostWillEnterForeground]
        for name in away {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.background = true; self?.refresh() })
        }
        for name in back {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.background = false; self?.refresh() })
        }
        for name in [UIAccessibility.reduceMotionStatusDidChangeNotification, .NSProcessInfoPowerStateDidChange, UserDefaults.didChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
    }

    fileprivate func attach(_ view: TiltShadowUIView) { listeners.add(view); refresh() }
    fileprivate func detach(_ view: TiltShadowUIView) { listeners.remove(view); refresh() }

    /// Which way up the screen is (told by the shadow view from its window).
    fileprivate func setOrientation(_ o: UIInterfaceOrientation) {
        guard o != .unknown, o != orientation else { return }
        orientation = o
        if running { stop(settle: false); refresh() }   // restart on the new axes
    }

    /// Main thread: start or stop the reader to match the screen, the app and the settings.
    func refresh() {
        let want = Self.enabled && !background && listeners.allObjects.contains { $0.wantsMotion }
        if want && !running { start() } else if !want && running { stop(settle: true) }
    }

    private func start() {
        guard manager.isDeviceMotionAvailable else { return }   // the simulator: shadows stay at rest
        running = true
        let o = orientation
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        queue.addOperation { [weak self] in self?.primed = false }
        manager.deviceMotionUpdateInterval = low ? 1.0 / 15 : 1.0 / 30
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            self.read(g, o)
        }
    }

    private func stop(settle: Bool) {
        running = false
        manager.stopDeviceMotionUpdates()
        guard settle else { return }
        // back to the plate's own shadows, gently
        publish(.zero, animated: 0.35)
        queue.addOperation { [weak self] in self?.sent = .zero }
    }

    /// Sensor queue: smoothed (about a tenth of a second: no shiver from a hand, no lag behind the
    /// iPad), and sent on only when the shadows would visibly move.
    private func read(_ g: CMAcceleration, _ o: UIInterfaceOrientation) {
        let (x, y) = TiltShadowMath.screen(g.x, g.y, o)
        if !primed { smooth = (x, y); primed = true }
        smooth.x += (x - smooth.x) * 0.3
        smooth.y += (y - smooth.y) * 0.3
        let next = TiltShadowMath.lean(gravityX: smooth.x, gravityY: smooth.y)
        guard abs(next.dx - sent.dx) + abs(next.dy - sent.dy) > 0.006 else { return }
        sent = next
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.publish(next, animated: 1.0 / 30)
        }
    }

    private func publish(_ next: CGVector, animated: CFTimeInterval) {
        lean = next
        for view in listeners.allObjects { view.apply(next, duration: animated) }
    }
}

// MARK: - The shadow layer

/// Face 1's tilt shadows: sits on the plate, under the knob pointers and the pads' lights, never takes a touch.
struct TiltShadows: UIViewRepresentable {
    struct Knob: Equatable { let center: CGPoint; let r: CGFloat }
    /// Knob caps (layout centre and cap radius) and pad rects, in the plate's own pixels.
    let knobs: [Knob]
    let pads: [CGRect]
    let art: CGSize
    let scale: CGFloat
    /// Off while Face 2 covers Face 1 (the reader stops).
    let active: Bool

    init(layout L: FaceplateLayout, scale: CGFloat, active: Bool) {
        var knobs: [Knob] = []
        for key in L.knobs.keys.sorted() {
            guard let k = L.knobs[key] else { continue }
            knobs.append(Knob(center: CGPoint(x: k.x, y: k.y), r: CGFloat(k.r)))
        }
        self.knobs = knobs
        self.pads = L.pads.map { FaceplateLayout.rect($0) }
        self.art = CGSize(width: L.width, height: L.height)
        self.scale = scale
        self.active = active
    }

    func makeUIView(context: Context) -> TiltShadowUIView {
        let view = TiltShadowUIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: TiltShadowUIView, context: Context) {
        view.configure(knobs: knobs, pads: pads, art: art, scale: scale, active: active)
    }
}

final class TiltShadowUIView: UIView {
    private let content = CALayer()
    private let cutout = CAShapeLayer()
    private var knobs: [TiltShadows.Knob] = []
    private var pads: [CGRect] = []
    private var art = CGSize.zero
    private var scale: CGFloat = 1
    private var active = true
    private var attached = false
    /// Per knob: core, soft edge, contact. Per pad: core, soft edge.
    private var knobLayers: [(core: CALayer, soft: CALayer, contact: CALayer)] = []
    private var padLayers: [(core: CALayer, soft: CALayer)] = []

    var wantsMotion: Bool { window != nil && active && !knobs.isEmpty }

    override init(frame: CGRect) {
        super.init(frame: frame)
        content.anchorPoint = .zero
        cutout.fillRule = .evenOdd
        content.mask = cutout
        layer.addSublayer(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let o = window?.windowScene?.interfaceOrientation { TiltShadowMotion.shared.setOrientation(o) }
        if window != nil && !attached {
            attached = true
            TiltShadowMotion.shared.attach(self)
        } else if window == nil && attached {
            attached = false
            TiltShadowMotion.shared.detach(self)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let o = window?.windowScene?.interfaceOrientation { TiltShadowMotion.shared.setOrientation(o) }
    }

    func configure(knobs: [TiltShadows.Knob], pads: [CGRect], art: CGSize, scale: CGFloat, active: Bool) {
        let shapeChanged = knobs != self.knobs || pads != self.pads || art != self.art
        let activeChanged = active != self.active
        self.knobs = knobs; self.pads = pads; self.art = art; self.active = active
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if scale != self.scale || shapeChanged {
            self.scale = scale
            content.bounds = CGRect(origin: .zero, size: art)
            content.position = .zero
            content.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
        if shapeChanged { build() }
        CATransaction.commit()
        if shapeChanged { apply(TiltShadowMotion.shared.lean, duration: 0) }
        if activeChanged || shapeChanged { TiltShadowMotion.shared.refresh() }
    }

    /// The layers, made once per layout: nothing is drawn again while tilting.
    private func build() {
        content.sublayers?.forEach { $0.removeFromSuperlayer() }
        knobLayers = []
        padLayers = []
        // cut away every knob body and pad top: shadows land only on the plate and in the well
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: art))
        for k in knobs {
            let b = k.r * TiltShadowMath.knobBody
            path.addEllipse(in: CGRect(x: k.center.x - b, y: k.center.y - b, width: b * 2, height: b * 2))
        }
        for p in pads {
            path.addRoundedRect(in: p, cornerWidth: TiltShadowMath.padCorner, cornerHeight: TiltShadowMath.padCorner)
        }
        cutout.frame = CGRect(origin: .zero, size: art)
        cutout.path = path

        let body = (knobs.map(\.r).max() ?? 34) * TiltShadowMath.knobBody
        let core = TiltShadowSprites.disc(radius: body, blur: body * 0.14)
        let soft = TiltShadowSprites.disc(radius: body, blur: body * 0.42)
        let contact = TiltShadowSprites.disc(radius: body, blur: body * 0.10)
        for _ in knobs {
            let set = (core: stretchLayer(core), soft: stretchLayer(soft), contact: stretchLayer(contact))
            content.addSublayer(set.soft)
            content.addSublayer(set.core)
            content.addSublayer(set.contact)
            knobLayers.append(set)
        }
        let padCore = TiltShadowSprites.roundRect(corner: TiltShadowMath.padCorner, blur: 3)
        let padSoft = TiltShadowSprites.roundRect(corner: TiltShadowMath.padCorner, blur: 9)
        for _ in pads {
            let set = (core: sliceLayer(padCore), soft: sliceLayer(padSoft))
            content.addSublayer(set.soft)
            content.addSublayer(set.core)
            padLayers.append(set)
        }
    }

    private func stretchLayer(_ s: TiltShadowSprites.Sprite) -> CALayer {
        let l = CALayer()
        l.contents = s.image
        l.contentsScale = s.scale
        // only the middle column stretches: a disc pulled out into a capsule, a cylinder's shadow
        l.contentsCenter = CGRect(x: 0.5 - 0.5 / s.pixels.width, y: 0, width: 1 / s.pixels.width, height: 1)
        l.bounds = CGRect(origin: .zero, size: s.size)
        l.opacity = 0
        return l
    }

    private func sliceLayer(_ s: TiltShadowSprites.Sprite) -> CALayer {
        let l = CALayer()
        l.contents = s.image
        l.contentsScale = s.scale
        // nine-slice: the blurred corners keep their shape, the middle stretches to the pad
        let c = s.pad + TiltShadowMath.padCorner
        l.contentsCenter = CGRect(x: c / s.size.width, y: c / s.size.height,
                                  width: max(0.001, 1 - 2 * c / s.size.width), height: max(0.001, 1 - 2 * c / s.size.height))
        l.opacity = 0
        l.anchorPoint = .zero
        l.setValue(s.pad, forKey: "bkPad")
        return l
    }

    /// Moves the shadows for a lean (main thread; a few property sets, the GPU does the rest).
    func apply(_ lean: CGVector, duration: CFTimeInterval) {
        guard !knobLayers.isEmpty || !padLayers.isEmpty else { return }
        let strength = TiltShadowMath.strength(lean)
        let length = hypot(lean.dx, lean.dy)
        let angle = atan2(lean.dy, lean.dx)
        let dir = length > 0.0001 ? CGVector(dx: lean.dx / length, dy: lean.dy / length) : .zero
        CATransaction.begin()
        if duration > 0 {
            CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: duration > 0.1 ? .easeOut : .linear))
        } else {
            CATransaction.setDisableActions(true)
        }
        for (i, k) in knobs.enumerated() where i < knobLayers.count {
            let body = k.r * TiltShadowMath.knobBody
            let throwLen = length * body * TiltShadowMath.knobReach
            let set = knobLayers[i]
            // the core: the knob's foot swept along the light, darkest close in
            place(set.core, at: k.center, angle: angle, length: throwLen)
            set.core.opacity = Float(0.62 * strength)
            // the soft edge: falls further and spreads wider (a real shadow blurs with distance)
            place(set.soft, at: k.center, angle: angle, length: throwLen * 1.35, wide: 1.08 + 0.10 * strength)
            set.soft.opacity = Float(0.34 * strength)
            // contact shadow: hugs the base, barely moves
            place(set.contact, at: CGPoint(x: k.center.x + dir.dx * throwLen * 0.08, y: k.center.y + dir.dy * throwLen * 0.08),
                  angle: angle, length: 0, wide: 1.07, long: 1.07)
            set.contact.opacity = Float(0.5 * strength)
        }
        let padThrow = CGVector(dx: lean.dx * TiltShadowMath.padReach, dy: lean.dy * TiltShadowMath.padReach)
        for (i, p) in pads.enumerated() where i < padLayers.count {
            let set = padLayers[i]
            slide(set.core, pad: p, by: padThrow)
            set.core.opacity = Float(0.66 * strength)
            slide(set.soft, pad: p, by: CGVector(dx: padThrow.dx * 1.4, dy: padThrow.dy * 1.4))
            set.soft.opacity = Float(0.38 * strength)
        }
        CATransaction.commit()
    }

    /// A capsule from the knob's foot, `length` toward `angle`; `wide` spreads it across the throw,
    /// `long` along it.
    private func place(_ l: CALayer, at center: CGPoint, angle: CGFloat, length: CGFloat, wide: CGFloat = 1, long: CGFloat = 1) {
        let h = l.bounds.height            // the sprite is square: with no throw it is h wide
        let w = h + length
        l.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        l.anchorPoint = CGPoint(x: (h / 2) / w, y: 0.5)   // the foot circle's centre
        l.position = center
        l.setAffineTransform(CGAffineTransform(rotationAngle: angle).scaledBy(x: long, y: wide))
    }

    /// A pad's block shadow: the pad's own shape and its slid copy, joined.
    private func slide(_ l: CALayer, pad p: CGRect, by v: CGVector) {
        let pad = (l.value(forKey: "bkPad") as? CGFloat) ?? 0
        let moved = p.offsetBy(dx: v.dx, dy: v.dy)
        l.frame = p.union(moved).insetBy(dx: -pad, dy: -pad)
    }
}

// MARK: - Shadow pictures (made once, a few KB each)

enum TiltShadowSprites {
    struct Sprite {
        let image: CGImage
        /// Size in the plate's pixels, and the blur margin around the shape.
        let size: CGSize
        let pad: CGFloat
        let scale: CGFloat
        var pixels: CGSize { CGSize(width: size.width * scale, height: size.height * scale) }
    }

    private static var cache: [String: Sprite] = [:]

    /// A blurred black disc, `radius` (plate px) with `blur` soft edge.
    static func disc(radius: CGFloat, blur: CGFloat) -> Sprite {
        let key = "d\(Int(radius * 10))_\(Int(blur * 10))"
        if let s = cache[key] { return s }
        let pad = (blur * 1.6).rounded(.up) + 2
        let side = (radius + pad) * 2
        let s = draw(CGSize(width: side, height: side), blur: blur) { ctx, off in
            ctx.fillEllipse(in: CGRect(x: pad - off, y: pad, width: radius * 2, height: radius * 2))
        }
        let sprite = Sprite(image: s.0, size: CGSize(width: side, height: side), pad: pad, scale: s.1)
        cache[key] = sprite
        return sprite
    }

    /// A blurred black rounded square to nine-slice onto a pad.
    static func roundRect(corner: CGFloat, blur: CGFloat) -> Sprite {
        let key = "r\(Int(corner * 10))_\(Int(blur * 10))"
        if let s = cache[key] { return s }
        let pad = (blur * 1.6).rounded(.up) + 2
        let core = corner * 2 + 4
        let side = core + pad * 2
        let s = draw(CGSize(width: side, height: side), blur: blur) { ctx, off in
            ctx.addPath(CGPath(roundedRect: CGRect(x: pad - off, y: pad, width: core, height: core),
                               cornerWidth: corner, cornerHeight: corner, transform: nil))
            ctx.fillPath()
        }
        let sprite = Sprite(image: s.0, size: CGSize(width: side, height: side), pad: pad, scale: s.1)
        cache[key] = sprite
        return sprite
    }

    /// Draws the shape far off the canvas and lets its Core Graphics shadow (a true soft blur) land on
    /// it: only the blurred shadow is kept. Sideways offset only, which every context reads the same way.
    private static func draw(_ size: CGSize, blur: CGFloat, shape: (CGContext, CGFloat) -> Void) -> (CGImage, CGFloat) {
        let scale: CGFloat = 2
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let off: CGFloat = 4000
        let image = UIGraphicsImageRenderer(size: size, format: format).image { r in
            let ctx = r.cgContext
            ctx.setShadow(offset: CGSize(width: off * scale, height: 0), blur: blur * scale, color: UIColor.black.cgColor)
            ctx.setFillColor(UIColor.black.cgColor)
            shape(ctx, off)
        }
        return (image.cgImage!, scale)
    }
}
