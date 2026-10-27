// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import CoreMotion
import simd
import SwiftUI
import UIKit

// MARK: - The light on the hardware (realistic materials, stage 1, Tyrone Oct 27)
//
// One light for every material part. Fixed by default where the renders have it (above, a little
// left). With MOTION LIGHT on, tilting the iPad swings it gently, like turning a real machine under
// a lamp. The sensor runs on its own queue at 30 a second, is smoothed there, and only reaches the
// main thread when the light has really moved; it never touches the audio thread. It stops when no
// part is on screen, when the app or plug-in window goes to the background, and when Reduce
// Motion is on (then the light stays fixed).

final class MaterialLight: ObservableObject {
    static let shared = MaterialLight()

    /// Where the light has swung from its fixed place, -1...1 each way (x right, y toward you).
    @Published private(set) var tilt = CGVector.zero
    @Published private(set) var state: LightState = .off
    /// Sensor readings handled in the last second (for the MATERIAL TEST readout).
    @Published private(set) var readsPerSecond = 0

    enum LightState: Equatable { case moving, off, reduceMotion, noSensor }

    static let settingKey = "bk.motionLight"
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.settingKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.settingKey); refresh() }
    }
    /// The interface orientation, so tilting right always swings the light the same way on screen.
    var orientation: UIInterfaceOrientation = .landscapeRight {
        didSet {
            // the sensor queue reads it when updates start: restart them on the new axes
            guard orientation != oldValue, running else { return }
            manager.stopDeviceMotionUpdates()
            running = false
            start()
        }
    }

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "BreaKing material light"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()
    private var users = 0
    private var background = false
    private var running = false
    private var observers: [NSObjectProtocol] = []

    // sensor queue only
    private var rest: SIMD2<Double>?
    private var smooth = SIMD2<Double>(0, 0)
    private var sent = SIMD2<Double>(0, 0)
    private var reads = 0
    private var readsMark = CACurrentMediaTime()

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.background = true; self?.refresh() })
        observers.append(center.addObserver(forName: UIScene.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.background = false; self?.refresh() })
    }

    /// A material part came on screen / went away.
    func attach() { users += 1; refresh() }
    func detach() { users = max(0, users - 1); refresh() }

    private func refresh() {
        let state: LightState
        if !enabled { state = .off }
        else if UIAccessibility.isReduceMotionEnabled { state = .reduceMotion }
        else if !manager.isDeviceMotionAvailable { state = .noSensor }
        else { state = .moving }
        if self.state != state { self.state = state }
        let want = state == .moving && users > 0 && !background
        if want && !running { start() } else if !want && running { stop() }
    }

    private func start() {
        running = true
        let orientation = self.orientation
        queue.addOperation { [weak self] in self?.rest = nil }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            self.read(g, orientation)
        }
    }

    private func stop() {
        running = false
        manager.stopDeviceMotionUpdates()
        // back to the fixed light, gently
        withAnimation(.easeOut(duration: 0.45)) { tilt = .zero }
        readsPerSecond = 0
    }

    /// Sensor queue: gravity on the screen's axes, measured from how you're holding the iPad (that
    /// slowly becomes the new rest), smoothed, and sent on only when it moved enough to see.
    private func read(_ g: CMAcceleration, _ orientation: UIInterfaceOrientation) {
        let s: SIMD2<Double>
        switch orientation {
        case .portrait: s = [g.x, -g.y]
        case .portraitUpsideDown: s = [-g.x, g.y]
        case .landscapeLeft: s = [g.y, g.x]
        default: s = [-g.y, -g.x]
        }
        let dt = 1.0 / 30
        guard let r = rest else { rest = s; smooth = .zero; return }
        rest = r + (s - r) * (dt / 4.0)                  // the rest pose follows over ~4 s
        // the light stays put in the room: tip the right side down and it moves left on the plate
        let target = simd_clamp(-(s - r) / 0.3, SIMD2(-1, -1), SIMD2(1, 1))
        smooth += (target - smooth) * (dt / 0.18)        // ~0.18 s smoothing
        reads += 1
        let now = CACurrentMediaTime()
        var perSecond: Int?
        if now - readsMark >= 1 { perSecond = reads; reads = 0; readsMark = now }
        let moved = simd_length(smooth - sent) > 0.006
        if moved { sent = smooth }
        guard moved || perSecond != nil else { return }
        let value = sent
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            if moved { self.tilt = CGVector(dx: value.x, dy: value.y) }
            if let perSecond { self.readsPerSecond = perSecond }
        }
    }
}

/// Tells MaterialLight which way up the screen is (works in the app and in the plug-in window).
struct MaterialOrientationProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {}

    final class Probe: UIView {
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        private func report() {
            if let o = window?.windowScene?.interfaceOrientation, o != .unknown { MaterialLight.shared.orientation = o }
        }
    }
}

// MARK: - Screen readout for the MATERIAL TEST page

/// Frames the screen drew in the last second, the slowest one, frames that came late, and the
/// app's CPU, measured on the main thread with a display link (only while the page is open).
final class FrameMeter: ObservableObject {
    @Published private(set) var text = "measuring…"
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0, late = 0
    private var slowest: CFTimeInterval = 0
    private var mark: CFTimeInterval = 0
    private var cpuMark: (wall: Double, cpu: Double)?

    func start() {
        guard link == nil else { return }
        let link = CADisplayLink(target: Proxy(self), selector: #selector(Proxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        mark = CACurrentMediaTime(); last = 0
    }

    func stop() { link?.invalidate(); link = nil }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if last > 0 {
            let dt = now - last
            slowest = max(slowest, dt)
            let expected = link.targetTimestamp - link.timestamp
            if expected > 0 && dt > expected * 1.5 { late += 1 }
        }
        last = now
        frames += 1
        if now - mark >= 1 {
            text = String(format: "SCREEN %d fps · slowest frame %.1f ms · %d late · light %d/s · app CPU %.0f%%",
                          frames, slowest * 1000, late, MaterialLight.shared.readsPerSecond, cpu())
            frames = 0; late = 0; slowest = 0; mark = now
        }
    }

    private func cpu() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        let cpu = Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
        let wall = CACurrentMediaTime()
        defer { cpuMark = (wall, cpu) }
        guard let m = cpuMark, wall > m.wall else { return 0 }
        return (cpu - m.cpu) / (wall - m.wall) * 100
    }

    /// Keeps the display link from holding the meter alive.
    private final class Proxy: NSObject {
        weak var meter: FrameMeter?
        init(_ meter: FrameMeter) { self.meter = meter }
        @objc func tick(_ link: CADisplayLink) {
            if let meter { meter.tick(link) } else { link.invalidate() }
        }
    }
}
