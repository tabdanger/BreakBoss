// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import Foundation
import AVFoundation
import UIKit

// MARK: - Self-test
//
// Optional test suite: BREAKBOSS_SELFTEST=1 on the build machine, or MENU › HELP › SELF-TEST on the
// iPad (SelfTestRunner; that run leaves out what would change the user's files). No CI target is bundled.
// It checks the sound, not the screen: every kit renders, every style makes grooves, loops stay
// in time at different tempos and with the host's transport, the clipper holds its ceiling in
// all three modes, idle stays silent, and files round-trip.

enum KnockSelfTest {
    // One run at a time (runLock), so the env-var run at launch and the menu's SELF-TEST can't
    // share these; every run starts them empty and empties them again when it ends.
    private static var failures: [String] = []
    private static var lines: [String] = []
    private static var results: [SelfTestReport.Phase] = []
    /// The menu's run (MENU › HELP › SELF-TEST) on the iPad: leaves the user's files alone.
    private(set) static var inApp = false
    /// What the running phase left out in the menu's run (skipNote).
    private static var partSkipped: String?
    private static let runLock = NSLock()

    /// Phases that change the user's files, left out of the menu's run (Tyrone, Nov 1: the button must
    /// not touch anything he has). The BREAKBOSS_SELFTEST=1 run on the build machine still runs them.
    private static let skippedInApp: [String: String] = [
        "checkSoundSwap": "it writes a test file into your Samples folder (MY SOUNDS) and copies stock sounds there through a test controller",
    ]

    /// BREAKBOSS_SELFTEST=1 (build machine): everything, as before.
    @discardableResult
    static func run() -> Bool {
        run(inApp: false, progress: nil).passed
    }

    /// `inApp`: the menu's SELF-TEST, on a background queue while BreaKing plays. Only its own
    /// engines, controllers and temporary files; phases that would change the user's files are
    /// left out and named in the report.
    static func run(inApp app: Bool, progress: SelfTestRunner.Progress?) -> SelfTestReport {
        runLock.lock()
        defer { runLock.unlock() }
        failures = []
        lines = []
        results = []
        inApp = app
        defer {
            failures = []
            lines = []
            results = []
            inApp = false
            partSkipped = nil
        }
        let started = Date()
        let phases: [(String, () -> Void)] = [
            ("checkKits", checkKits),
            ("checkStockSamples", checkStockSamples),
            ("checkSoundSwap", checkSoundSwap),
            ("checkFreshSounds", checkFreshSounds),
            ("checkGrooves", checkGrooves),
            ("checkSmallBuffersAndVoiceStealing", checkSmallBuffersAndVoiceStealing),
            ("checkHostMIDIAndAutomation", checkHostMIDIAndAutomation),
            ("checkOneShotMIDIAndPadFilters", checkOneShotMIDIAndPadFilters),
            ("checkVelocityLayers", checkVelocityLayers),
            ("checkModesAndClipper", checkModesAndClipper),
            ("checkTempoSync", checkTempoSync),
            ("checkHostTransport", checkHostTransport),
            ("checkSilence", checkSilence),
            ("checkFiles", checkFiles),
            ("checkHeldLoops", checkHeldLoops),
            ("checkMigration", checkMigration),
            ("checkFactoryPresetsAndKitIndependence", checkFactoryPresetsAndKitIndependence),
            ("checkEveryPatternAudible", checkEveryPatternAudible),
            ("checkTextureControls", checkTextureControls),
            ("checkTexturePlate", checkTexturePlate),
            ("checkFXSections", checkFXSections),
            ("checkLevelPanGlide", checkLevelPanGlide),
            ("checkPatternEditor", checkPatternEditor),
            ("checkMIDIPadMap", checkMIDIPadMap),
            ("checkRecordingTrim", checkRecordingTrim),
            ("checkAudioFormats", checkAudioFormats),
            ("checkDrumRoll", checkDrumRoll),
            ("checkPlayheadGlide", checkPlayheadGlide),
            ("checkPianoRollOctaves", checkPianoRollOctaves),
            ("checkWorkspaceChannels", checkWorkspaceChannels),
            ("checkSampler", checkSampler),
            ("checkUntouchedEnvelopes", checkUntouchedEnvelopes),
            ("checkNoteLengthOneShots", checkNoteLengthOneShots),
            ("checkSamplerPlayhead", checkSamplerPlayhead),
            ("checkScope", checkScope),
            ("checkTrackFX", checkTrackFX),
            ("checkPrecomputedEffects", checkPrecomputedEffects),
            ("checkAudioCPU", checkAudioCPU),
            ("checkSampleEdits", checkSampleEdits),
            ("checkNoteRepeat", checkNoteRepeat),
        ]
        for (i, (name, work)) in phases.enumerated() {
            progress?(i + 1, phases.count, name)
            if app, let reason = skippedInApp[name] {
                log("BreakBoss self-test phase SKIPPED in the app: \(name) (\(reason))")
                results.append(SelfTestReport.Phase(name: name, checks: 0, failures: [], seconds: 0, skipped: reason, skippedWhole: true))
                continue
            }
            phase(name, work)
        }
        let seconds = Date().timeIntervalSince(started)
        if failures.isEmpty {
            log("BreakBoss self-test passed (\(lines.count) checks, \(String(format: "%.1f", seconds)) s)")
        } else {
            for f in failures { log("BreakBoss SELF-TEST FAILED: \(f)") }
        }
        return SelfTestReport(phases: results, seconds: seconds)
    }

    /// Persist progress before entering each phase so simulator timeouts distinguish a slow
    /// stage from a crash.
    static func phase(_ name: String, _ work: () -> Void) {
        log("BreakBoss self-test phase START: \(name)")
        let started = Date()
        let previousChecks = lines.count
        let previousFailures = failures.count
        partSkipped = nil
        work()
        let seconds = Date().timeIntervalSince(started)
        log("BreakBoss self-test phase END: \(name) (\(lines.count - previousChecks) checks, \(String(format: "%.2f", seconds)) s)")
        results.append(SelfTestReport.Phase(name: name, checks: lines.count - previousChecks,
                                            failures: Array(failures[previousFailures...]), seconds: seconds,
                                            skipped: partSkipped, skippedWhole: false))
        partSkipped = nil
    }

    /// A phase that stops early in the menu's run says what it left out.
    static func skipNote(_ what: String) {
        partSkipped = what
        log("BreakBoss self-test: left out in the app: \(what)")
    }

    static func check(_ ok: Bool, _ what: String) {
        lines.append(what)
        if !ok { failures.append(what) }
    }

    static func log(_ s: String) {
        print(s)
        NSLog("%@", s)
        if let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let url = caches.appendingPathComponent("BreakBoss-selftest.log")
            let old = (try? String(contentsOf: url)) ?? ""
            try? (old + s + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func kitBuffers(_ def: KitDefinition, rate: Double = 48_000) -> KitBuffers {
        let samples = def.pads.enumerated().map { DrumSynth.render($0.element, sampleRate: rate, seed: UInt32($0.offset + 1)) }
        return KitBuffers(name: def.name, samples: samples, settings: Array(repeating: PadSettings(), count: Pad.count), bassHz: def.bassHz,
                          renderSampleRate: rate)
    }
}
