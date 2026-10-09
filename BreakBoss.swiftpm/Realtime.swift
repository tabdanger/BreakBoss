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
        }
        os_unfair_lock_unlock(lock)
    }

    /// Audio thread: calls `handle` for every waiting event (skipped this block if busy).
    @inline(__always)
    func drain(_ handle: (KEvent) -> Void) {
        guard os_unfair_lock_trylock(lock) else { return }
        while head != tail {
            let e = buffer[head]
            head = (head + 1) % capacity
            handle(e)
        }
        os_unfair_lock_unlock(lock)
    }
}
