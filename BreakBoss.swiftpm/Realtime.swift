// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import os

// MARK: - Handing things to the audio thread without making it wait
//
// The audio thread never blocks and never frees memory. New kits and loops are built on the
// main thread and passed over through a Handoff: the audio thread picks them up with a try-lock
// (if the main thread happens to hold the lock it just tries again on the next block), and
// passes the old one back the same way, so it is released on the main thread.

final class Handoff<T: AnyObject> {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private var pending: T?
    private var retired: T?

    init() {
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    /// Main thread: offer a new value. Anything the audio thread handed back is released here.
    func publish(_ value: T) {
        os_unfair_lock_lock(lock)
        let old = retired
        retired = nil
        let replaced = pending
        pending = value
        os_unfair_lock_unlock(lock)
        _ = old
        _ = replaced
    }

    /// Main thread: release whatever the audio thread handed back.
    func collect() {
        os_unfair_lock_lock(lock)
        let old = retired
        retired = nil
        os_unfair_lock_unlock(lock)
        _ = old
    }

    /// Audio thread: the new value, if there is one and the lock is free.
    func take() -> T? {
        guard os_unfair_lock_trylock(lock) else { return nil }
        let value = pending
        pending = nil
        os_unfair_lock_unlock(lock)
        return value
    }

    /// Audio thread: hand an old value back for the main thread to release. False = try later.
    func retire(_ value: T) -> Bool {
        guard os_unfair_lock_trylock(lock) else { return false }
        defer { os_unfair_lock_unlock(lock) }
        if retired != nil { return false }
        retired = value
        return true
    }
}

/// Something for the engine to do, sent from the faceplate, a MIDI port or the host.
struct KEvent {
    enum Kind: UInt8 {
        case midiNoteOn   // a: channel * 128 + note
        case loopGateOn, loopGateOff // a: channel/note token, or 2048 + touch pad
        case pad          // a: pad 0...11, value: velocity 0...1
        case bass         // a: semitones from the 808 tuning, value: velocity
        case noteOff      // a: MIDI note (808 notes release)
        case loopPad      // a: loop 0...11 (-1 = stop loops)
        case play         // start the internal transport
        case stop
        case midiStart, midiStop, midiContinue
        case midiClock    // value: time in seconds
        case songPosition // a: MIDI beats (16ths)
        case allOff
        case mapNote      // a: MIDI note (-1 = clear the whole map), value: pad 0...11 or -1
        case padMask      // a: bit per pad that may sound (drum roll mute / solo)
        case recordArm    // a: 1 = record pad / MIDI hits into the playing pattern, 0 = off
        case metronome    // a: 1 = click on every beat while playing, 0 = off
        case midiOut      // a: pad 0...11, value: channel (0...15) * 128 + note, or -1 = channel off;
                          // a: -1 = MIDI out on (value 1) / off (value 0)
        case countIn      // a: beats of metronome count-in, then the pattern (value: loop 0...11, or -1 = the current one)
        case padPitched   // a: pad + 128 * (semitones + 64), value: velocity (a drum played at a pitch)
        case cue          // a: the pattern on the sequencer (0...11); while stopped it's what PLAY or the DAW starts
    }
    var kind: Kind
    var a: Int32 = 0
    var value: Double = 0
}

/// Many producers (main thread, MIDI thread), one consumer (the audio thread).
final class EventQueue {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    private let buffer: UnsafeMutablePointer<KEvent>
    private let capacity: Int
    private var head = 0
    private var tail = 0
    private var overflowed = false

    init(capacity: Int = 1024) {
        self.capacity = capacity
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        buffer = .allocate(capacity: capacity)
        buffer.initialize(repeating: KEvent(kind: .allOff), count: capacity)
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
        buffer.deallocate()
    }

    func push(_ e: KEvent) {
        os_unfair_lock_lock(lock)
        let next = (tail + 1) % capacity
        if next != head {
            buffer[tail] = e
            tail = next
        } else { overflowed = true }
        os_unfair_lock_unlock(lock)
    }

    /// Audio thread: calls `handle` for every waiting event (skipped this block if busy).
    @inline(__always)
    func drain(_ handle: (KEvent) -> Void) {
        guard os_unfair_lock_trylock(lock) else { return }
        if overflowed {
            head = tail
            overflowed = false
            handle(KEvent(kind: .allOff))
        }
        while head != tail {
            let e = buffer[head]
            head = (head + 1) % capacity
            handle(e)
        }
        os_unfair_lock_unlock(lock)
    }
}

/// Writers may wait; the render thread only tries once and uses its previous snapshot if busy.
final class SharedControls {
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private let values = UnsafeMutablePointer<Float>.allocate(capacity: KParam.count)
    private var tempo: Double = 140
    init() {
        lock.initialize(to: os_unfair_lock())
        for p in KParam.allCases { (values + p.rawValue).initialize(to: p.defaultValue) }
    }
    deinit { values.deallocate(); lock.deinitialize(count: 1); lock.deallocate() }
    func set(_ p: KParam, _ value: Float) {
        let finite = value.isFinite ? value : p.defaultValue
        os_unfair_lock_lock(lock)
        values[p.rawValue] = p.steps.map { finite.rounded().clamped(0, Float($0 - 1)) } ?? finite.clamped(0, 1)
        os_unfair_lock_unlock(lock)
    }
    func get(_ p: KParam) -> Float {
        os_unfair_lock_lock(lock)
        let result = values[p.rawValue]
        os_unfair_lock_unlock(lock)
        return result
    }
    func setTempo(_ value: Double) {
        os_unfair_lock_lock(lock)
        tempo = value.isFinite ? value.clamped(30, 300) : 140
        os_unfair_lock_unlock(lock)
    }
    /// Audio thread: merge the host's preallocated pending values and take one snapshot.
    /// False leaves the host's dirty mask with its owner, to retry next callback. A busy UI
    /// writer never delays rendering, and automation remains audible through the local copy.
    @discardableResult
    func copy(to output: UnsafeMutablePointer<Float>, tempo outputTempo: UnsafeMutablePointer<Double>,
              hostValues: UnsafePointer<Float>? = nil, hostMask: UInt32 = 0) -> Bool {
        guard os_unfair_lock_trylock(lock) else { return false }
        if let hostValues {
            var dirty = hostMask
            while dirty != 0 {
                let index = dirty.trailingZeroBitCount
                values[index] = hostValues[index]
                dirty &= dirty - 1
            }
        }
        output.update(from: values, count: KParam.count)
        outputTempo.pointee = tempo
        os_unfair_lock_unlock(lock)
        return true
    }
}

struct MeterSnapshot {
    var status = [Double](repeating: 0, count: 8)
    var padHits = [UInt32](repeating: 0, count: Pad.count)
    var scope = [Float](repeating: 0, count: MasterBus.scopeSize)
    var scopeWrite = 0
}

/// Audio publishes into preallocated storage; UI copies it on the main thread.
final class SharedMeters {
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    private let status = UnsafeMutablePointer<Double>.allocate(capacity: 8)
    private let hits = UnsafeMutablePointer<UInt32>.allocate(capacity: Pad.count)
    private let scope = UnsafeMutablePointer<Float>.allocate(capacity: MasterBus.scopeSize)
    private var scopeWrite = 0
    init() {
        lock.initialize(to: os_unfair_lock())
        status.initialize(repeating: 0, count: 8)
        status[1] = -1; status[2] = -2
        hits.initialize(repeating: 0, count: Pad.count)
        scope.initialize(repeating: 0, count: MasterBus.scopeSize)
    }
    deinit { status.deallocate(); hits.deallocate(); scope.deallocate(); lock.deinitialize(count: 1); lock.deallocate() }
    func publish(status source: UnsafeMutablePointer<Double>, hits sourceHits: UnsafeMutablePointer<UInt32>, master: MasterBus) {
        guard os_unfair_lock_trylock(lock) else { return }
        status.update(from: source, count: 8)
        hits.update(from: sourceHits, count: Pad.count)
        scope.update(from: master.scope, count: MasterBus.scopeSize)
        scopeWrite = master.scopeWrite
        os_unfair_lock_unlock(lock)
    }
    /// The scope ring and its write position, copied into a buffer the screen reuses
    /// (no allocation, so it can run every display frame).
    func copyScope(into buffer: inout [Float]) -> Int {
        if buffer.count != MasterBus.scopeSize { buffer = [Float](repeating: 0, count: MasterBus.scopeSize) }
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        buffer.withUnsafeMutableBufferPointer { $0.baseAddress!.update(from: scope, count: MasterBus.scopeSize) }
        return scopeWrite
    }

    func snapshot() -> MeterSnapshot {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return MeterSnapshot(status: Array(UnsafeBufferPointer(start: status, count: 10)),
                             padHits: Array(UnsafeBufferPointer(start: hits, count: Pad.count)),
                             scope: Array(UnsafeBufferPointer(start: scope, count: MasterBus.scopeSize)), scopeWrite: scopeWrite)
    }
}
