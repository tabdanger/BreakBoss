// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import UIKit

// MARK: - SELF-TEST from the menu (MENU › HELP › TESTING › SELF-TEST)
//
// Tyrone, Nov 1: the self-test has to run on the iPad itself, where BREAKBOSS_SELFTEST=1 can't be
// set. KnockSelfTest is app-only (xcode/generate.py APP_ONLY), so the standalone app hands its suite
// in at launch and the AUv3 has none: there the menu row doesn't show. The suite runs on its own
// background queue with its own engines and controllers. The playing engine, the kit, the pattern,
// presets and saved files are never touched, and the audio callback is not involved.

struct SelfTestReport {
    struct Phase: Identifiable {
        let name: String
        let checks: Int
        let failures: [String]
        let seconds: Double
        /// Why the menu's run left this phase (or part of it) out; nil when it ran in full.
        let skipped: String?
        /// The whole phase was left out (nothing ran).
        let skippedWhole: Bool
        var id: String { name }
        var title: String { SelfTestReport.title(name) }
        var passed: Bool { failures.isEmpty }
    }

    var phases: [Phase]
    var seconds: Double

    var passed: Bool { phases.allSatisfy(\.passed) }
    var checks: Int { phases.reduce(0) { $0 + $1.checks } }
    var failureCount: Int { phases.reduce(0) { $0 + $1.failures.count } }
    var ranPhases: Int { phases.filter { !$0.skippedWhole }.count }

    /// "checkHostMIDIAndAutomation" -> "Host MIDI and automation"
    static func title(_ name: String) -> String {
        let chars = Array(name.hasPrefix("check") ? String(name.dropFirst(5)) : name)
        var words: [String] = []
        var word = ""
        for (i, c) in chars.enumerated() {
            if c.isUppercase, !word.isEmpty, i > 0 {
                let prev = chars[i - 1]
                let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextLower) {
                    words.append(word)
                    word = ""
                }
            }
            word.append(c)
        }
        if !word.isEmpty { words.append(word) }
        var shaped: [String] = []
        for (i, w) in words.enumerated() {
            if w.count > 1 && w == w.uppercased() { shaped.append(w) }   // MIDI, CPU, FX
            else { shaped.append(i == 0 ? w : w.lowercased()) }
        }
        return shaped.joined(separator: " ")
    }

    /// The text COPY RESULTS puts on the clipboard: short enough to paste into a chat, with every failure
    /// (up to 200) in full and one line per phase.
    func text(header: String) -> String {
        var out: [String] = []
        let count = NumberFormatter.localizedString(from: NSNumber(value: checks), number: .decimal)
        out.append(passed ? "BreaKing SELF-TEST: PASSED"
                          : "BreaKing SELF-TEST: FAILED (\(failureCount) of \(count) checks)")
        out.append(header)
        out.append(String(format: "%@ checks in %ld phases, %.1f s", count, ranPhases, seconds))
        let skipped = phases.filter { $0.skipped != nil }
        if !skipped.isEmpty {
            out.append("")
            out.append("LEFT OUT IN THE APP (they would change your files)")
            for p in skipped { out.append("- \(p.title) (\(p.name)): \(p.skipped ?? "")") }
        }
        if !passed {
            out.append("")
            out.append("WHAT FAILED")
            let all = phases.flatMap { p in p.failures.map { "- [\(p.title)] \($0)" } }
            out.append(contentsOf: all.prefix(200))
            if all.count > 200 { out.append("… and \(all.count - 200) more") }
        }
        out.append("")
        out.append("PHASES")
        for p in phases {
            let mark = p.skippedWhole ? "SKIP" : (p.passed ? "PASS" : "FAIL")
            var line = "\(mark)  \(p.title) (\(p.name))"
            if !p.skippedWhole {
                line += String(format: ": %ld checks, %.2f s", p.checks, p.seconds)
                if !p.passed { line += ", \(p.failures.count) failed" }
            }
            if p.skipped != nil && !p.skippedWhole { line += " (part left out)" }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }
}

final class SelfTestRunner: ObservableObject {
    static let shared = SelfTestRunner()

    /// (phase number from 1, how many phases, the phase's name). Called on the test's queue.
    typealias Progress = (_ index: Int, _ total: Int, _ phase: String) -> Void

    /// The suite: set once by the standalone app at launch (BreakBossApp), nil in the AUv3.
    static var suite: ((@escaping Progress) -> SelfTestReport)?

    enum Status {
        case idle
        case running(index: Int, total: Int, phase: String)
        case finished(SelfTestReport, copyText: String)
    }

    @Published private(set) var status: Status = .idle
    private let queue = DispatchQueue(label: "breakboss.selftest", qos: .userInitiated)

    var available: Bool { Self.suite != nil }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    /// Starts a run unless one is going. Main thread only (the menu's button).
    func start() {
        guard let suite = Self.suite, !isRunning else { return }
        status = .running(index: 0, total: 0, phase: "")
        queue.async { [weak self] in
            let report = suite { index, total, phase in
                DispatchQueue.main.async { self?.status = .running(index: index, total: total, phase: phase) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.status = .finished(report, copyText: report.text(header: self.header()))
            }
        }
    }

    private func header() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current
        let date = ISO8601DateFormatter().string(from: Date())
        return "Version \(version) (\(build)) · \(device.model) · \(device.systemName) \(device.systemVersion) · \(date) · run from MENU › HELP › SELF-TEST"
    }
}
