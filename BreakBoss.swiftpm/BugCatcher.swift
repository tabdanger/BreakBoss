// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import AVFoundation
import Darwin
import Foundation
import UIKit
import os

// MARK: - Crash and freeze catching (standalone app only)
//
// Feeds BugLog: a crash (Swift error, exception or bad memory access) writes crash.txt with the console's
// last words (Swift prints "Fatal error: …" with the file and line just before it stops) and the call stack;
// the console (print and system warnings) is copied into the log while still reaching Swift Playgrounds'
// console; a watchdog notes when the screen stops responding; audio interruptions, route changes, audio
// resets and memory warnings are noted as they happen. The plug-in never runs this (its host owns crashes).

enum BugCatcher {
    private static var installed = false
    private static var observers: [NSObjectProtocol] = []

    static func install() {
        guard !installed else { return }
        installed = true
        BugLog.shared.beginRun()
        crashPath = strdup(BugLog.shared.crashURL.path)
        consoleTail = UnsafeMutablePointer<UInt8>.allocate(capacity: tailSize)
        consoleTail?.initialize(repeating: 0, count: tailSize)
        _ = tailLock
        copyConsole(fd: STDERR_FILENO)
        copyConsole(fd: STDOUT_FILENO)
        setvbuf(stdout, nil, _IOLBF, 0)
        NSSetUncaughtExceptionHandler { exception in
            BugCatcher.writeCrash(title: "Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")",
                                  stack: exception.callStackSymbols)
        }
        // The handler runs on a stack of its own: a crash from running out of stack (calls that never end)
        // leaves no room on the main thread's stack, so without this nothing would be written down.
        var alt = stack_t()
        alt.ss_size = 256 * 1_024
        alt.ss_sp = UnsafeMutableRawPointer.allocate(byteCount: alt.ss_size, alignment: 16)
        alt.ss_flags = 0
        sigaltstack(&alt, nil)
        for sig in caught {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = bugSignalHandler
            action.sa_flags = SA_ONSTACK
            var previous = sigaction()
            if sigaction(sig, &action, &previous) == 0 { previousHandlers[sig] = previous.__sigaction_u.__sa_handler }
        }
        watchScreen()
        observeSystem()
    }

    // MARK: Crashes

    private static let caught: [Int32] = [SIGABRT, SIGTRAP, SIGSEGV, SIGBUS, SIGILL, SIGFPE]
    private static var previousHandlers: [Int32: sig_t] = [:]
    private static var crashPath: UnsafeMutablePointer<CChar>?

    private static func name(of sig: Int32) -> String {
        switch sig {
        case SIGABRT: return "SIGABRT (abort)"
        case SIGTRAP: return "SIGTRAP (Swift runtime error: see the console lines above)"
        case SIGSEGV: return "SIGSEGV (bad memory access)"
        case SIGBUS: return "SIGBUS (bad memory access)"
        case SIGILL: return "SIGILL (illegal instruction)"
        case SIGFPE: return "SIGFPE (arithmetic error)"
        default: return "signal \(sig)"
        }
    }

    fileprivate static func crashed(signal sig: Int32) {
        // The process is going down: this isn't strictly signal-safe (it allocates), which is the usual
        // trade for a readable report. The default handler runs right after.
        writeCrash(title: "Crashed: " + name(of: sig), stack: Thread.callStackSymbols)
        for s in caught { signal(s, previousHandlers[s] ?? SIG_DFL) }
        raise(sig)
    }

    static func writeCrash(title: String, stack: [String]) {
        guard let path = crashPath else { return }
        usleep(150_000)    // lets the console reader pick up the last line Swift printed
        let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else { return }
        var text = title + "\nThread: " + (Thread.isMainThread ? "main" : (Thread.current.name ?? "background")) + "\n"
        text += "\nLast console output:\n" + lastConsoleOutput() + "\n"
        text += "\nCall stack:\n" + stack.joined(separator: "\n") + "\n"
        text.withCString { p in _ = Darwin.write(fd, p, strlen(p)) }
        close(fd)
    }

    // MARK: Console

    private static let tailSize = 4_096
    private static var consoleTail: UnsafeMutablePointer<UInt8>?
    private static var tailEnd = 0
    private static let tailLock: os_unfair_lock_t = {
        let lock = os_unfair_lock_t.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        return lock
    }()

    /// Puts a pipe in front of stdout / stderr: everything still goes to the original console, and each
    /// line also goes to the log and the crash report's tail.
    private static func copyConsole(fd target: Int32) {
        var ends: [Int32] = [0, 0]
        guard pipe(&ends) == 0 else { return }
        let original = dup(target)
        guard original >= 0, dup2(ends[1], target) >= 0 else { return }
        close(ends[1])
        let reader = ends[0]
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 4_096)
            var pending = ""
            while true {
                let n = buffer.withUnsafeMutableBytes { read(reader, $0.baseAddress, 4_096) }
                if n <= 0 { if n < 0 && errno == EINTR { continue }; break }
                buffer.withUnsafeBytes { _ = Darwin.write(original, $0.baseAddress, n) }
                remember(buffer, count: n)
                pending += String(decoding: buffer[0..<n], as: UTF8.self)
                while let newline = pending.firstIndex(of: "\n") {
                    let line = pending[..<newline].trimmingCharacters(in: .whitespaces)
                    pending = String(pending[pending.index(after: newline)...])
                    if !line.isEmpty { BugLog.shared.note("console: " + line) }
                }
            }
        }
        thread.name = "BreakBoss console copy"
        thread.qualityOfService = .utility
        thread.start()
    }

    private static func remember(_ bytes: [UInt8], count: Int) {
        guard let tail = consoleTail else { return }
        os_unfair_lock_lock(tailLock)
        for i in 0..<count {
            tail[tailEnd % tailSize] = bytes[i]
            tailEnd += 1
        }
        os_unfair_lock_unlock(tailLock)
    }

    private static func lastConsoleOutput() -> String {
        guard let tail = consoleTail, os_unfair_lock_trylock(tailLock) else { return "(busy)" }
        defer { os_unfair_lock_unlock(tailLock) }
        let count = min(tailEnd, tailSize)
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for i in (tailEnd - count)..<tailEnd { bytes.append(tail[i % tailSize]) }
        return count == 0 ? "(none)" : String(decoding: bytes, as: UTF8.self)
    }

    // MARK: Freezes

    /// Pings the main thread every second; one that takes over 2 seconds to answer is a freeze.
    private static func watchScreen() {
        let thread = Thread {
            while true {
                let answered = DispatchSemaphore(value: 0)
                let start = Date()
                DispatchQueue.main.async { answered.signal() }
                if answered.wait(timeout: .now() + 2) == .timedOut {
                    BugLog.shared.note("FREEZE: the screen stopped responding (over 2 s)")
                    answered.wait()
                    BugLog.shared.note(String(format: "FREEZE over: the screen was stuck for %.1f s", Date().timeIntervalSince(start)))
                }
                Thread.sleep(forTimeInterval: 1)
            }
        }
        thread.name = "BreakBoss watchdog"
        thread.qualityOfService = .utility
        thread.start()
    }

    // MARK: Audio and system events

    private static func observeSystem() {
        let center = NotificationCenter.default
        let log = BugLog.shared
        func watch(_ name: Notification.Name, _ describe: @escaping (Notification) -> String) {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { log.note(describe($0)) })
        }
        watch(AVAudioSession.interruptionNotification) { note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            return raw == AVAudioSession.InterruptionType.began.rawValue
                ? "Audio interrupted (call, Siri, another app took the audio)" : "Audio interruption ended"
        }
        watch(AVAudioSession.routeChangeNotification) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).map(String.init) ?? "?"
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portName).joined(separator: ", ")
            return "Audio route changed (reason \(reason)) · now out: \(outputs.isEmpty ? "none" : outputs)"
        }
        watch(AVAudioSession.mediaServicesWereLostNotification) { _ in "iOS audio services were lost" }
        watch(AVAudioSession.mediaServicesWereResetNotification) { _ in "iOS audio services were reset" }
        watch(.AVAudioEngineConfigurationChange) { _ in "Audio engine configuration changed (engine restarts)" }
        watch(UIApplication.didReceiveMemoryWarningNotification) { _ in "MEMORY WARNING from iOS" }
        watch(ProcessInfo.thermalStateDidChangeNotification) { _ in
            "Thermal state now \(ProcessInfo.processInfo.thermalState.rawValue) (0 normal … 3 critical)"
        }
    }
}

private func bugSignalHandler(_ sig: Int32) {
    BugCatcher.crashed(signal: sig)
}
