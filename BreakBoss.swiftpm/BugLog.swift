// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import AVFoundation
import Foundation
import SwiftUI
import UIKit

// MARK: - Bug reports
//
// A running log of what the app did (launch, audio route and interruptions, notices on screen, memory
// warnings, screen freezes, anything printed to the console) kept in Files › BreakBoss › Bug Reports, so a
// test on the iPad (Swift Playgrounds or TestFlight) leaves something to send back. MENU › Bug report shows
// it with the device details and the crash from the last run, if there was one; Copy or Share sends it.
// Catching crashes and console output (BugCatcher.swift) is standalone-app only; the plug-in keeps the log
// in memory.

final class BugLog {
    static let shared = BugLog()

    let folder: URL
    var logURL: URL { folder.appendingPathComponent("log.txt") }
    var previousLogURL: URL { folder.appendingPathComponent("previous-run.txt") }
    /// Written by the crash catcher as the app dies; renamed to last-crash.txt at the next launch.
    var crashURL: URL { folder.appendingPathComponent("crash.txt") }
    var lastCrashURL: URL { folder.appendingPathComponent("last-crash.txt") }
    /// Present while the app is on screen; left behind when a run ends without going to the background.
    private var onScreenURL: URL { folder.appendingPathComponent("on-screen") }

    /// The crash report from the previous run, if it crashed (read at launch).
    private(set) var lastCrash: String?
    /// The previous run ended while on screen without a crash report (a freeze, out of memory, or Stop in
    /// Swift Playgrounds).
    private(set) var lastRunEndedOnScreen = false

    private let queue = DispatchQueue(label: "com.tabdanger.BreakBoss.buglog")
    private var recent: [String] = []
    private var handle: FileHandle?
    private let stamp: DateFormatter
    private static let keep = 3_000

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = docs.appendingPathComponent("Bug Reports", isDirectory: true)
        stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "HH:mm:ss.SSS"
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Standalone app launch: keeps the last run's log and crash, starts a fresh log file.
    func beginRun() {
        let fm = FileManager.default
        if fm.fileExists(atPath: crashURL.path) {
            try? fm.removeItem(at: lastCrashURL)
            try? fm.moveItem(at: crashURL, to: lastCrashURL)
            lastCrash = (try? String(contentsOf: lastCrashURL, encoding: .utf8)) ?? "(the crash report could not be read)"
        } else {
            try? fm.removeItem(at: lastCrashURL)
            lastRunEndedOnScreen = fm.fileExists(atPath: onScreenURL.path)
        }
        if fm.fileExists(atPath: logURL.path) {
            try? fm.removeItem(at: previousLogURL)
            try? fm.moveItem(at: logURL, to: previousLogURL)
        }
        fm.createFile(atPath: logURL.path, contents: nil)
        let h = try? FileHandle(forWritingTo: logURL)
        queue.sync {
            handle = h
            if let data = recent.map({ $0 + "\n" }).joined().data(using: .utf8) { try? h?.write(contentsOf: data) }
        }
        setOnScreen(true)
        note("BreakBoss started · " + Self.versionLine)
        if lastCrash != nil { note("The last run crashed (report in last-crash.txt)") }
        if lastRunEndedOnScreen { note("The last run ended while on screen without a crash report") }
    }

    /// Adds a time-stamped line. Safe from any thread except the audio render thread.
    func note(_ text: String) {
        let now = Date()
        queue.async { [self] in
            let line = stamp.string(from: now) + "  " + text
            recent.append(line)
            if recent.count > Self.keep { recent.removeFirst(recent.count - Self.keep) }
            if let data = (line + "\n").data(using: .utf8) { try? handle?.write(contentsOf: data) }
        }
    }

    func setOnScreen(_ on: Bool) {
        if on { FileManager.default.createFile(atPath: onScreenURL.path, contents: nil) }
        else { try? FileManager.default.removeItem(at: onScreenURL) }
    }

    func clearOldReports() {
        let fm = FileManager.default
        for url in [previousLogURL, lastCrashURL] { try? fm.removeItem(at: url) }
        if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for f in files where f.lastPathComponent.hasPrefix("BreakBoss bug report") { try? fm.removeItem(at: f) }
        }
        lastCrash = nil
        lastRunEndedOnScreen = false
        note("Old reports cleared")
    }

    static var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "version \(version) (\(build)) · \(Bundle.main.bundleIdentifier ?? "no bundle id")"
    }

    private static var hardware: String {
        var u = utsname()
        uname(&u)
        return withUnsafeBytes(of: &u.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    /// The whole report: what the tester wrote, the device, the last run's crash, this run and the last.
    @MainActor
    func report(whatHappened: String) -> String {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        let inputs = session.currentRoute.inputs.map(\.portName).joined(separator: ", ")
        let memory = ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
        var out = "BREAKBOSS BUG REPORT · \(Date().formatted(date: .abbreviated, time: .standard))\n\n"
        out += "WHAT HAPPENED\n" + (whatHappened.isEmpty ? "(nothing written)" : whatHappened) + "\n\n"
        out += "DEVICE\n"
        out += "BreakBoss \(Self.versionLine)\n"
        out += "\(UIDevice.current.model) \(Self.hardware) · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · \(memory) RAM\n"
        out += "Thermal state \(ProcessInfo.processInfo.thermalState.rawValue) · low power \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "on" : "off")\n"
        out += String(format: "Audio %.0f Hz · buffer %.1f ms · out: %@ · in: %@\n\n",
                      session.sampleRate, session.ioBufferDuration * 1000, outputs.isEmpty ? "none" : outputs, inputs.isEmpty ? "none" : inputs)
        if let crash = lastCrash {
            out += "LAST RUN CRASHED\n" + crash + "\n\n"
        } else if lastRunEndedOnScreen {
            out += "LAST RUN\nEnded while on screen without a crash report (a freeze, out of memory, or Stop in Swift Playgrounds).\n\n"
        }
        out += "THIS RUN\n" + queue.sync { recent.joined(separator: "\n") } + "\n"
        if let previous = try? String(contentsOf: previousLogURL, encoding: .utf8), !previous.isEmpty {
            let tail = previous.split(separator: "\n", omittingEmptySubsequences: false).suffix(400)
            out += "\nPREVIOUS RUN (last \(tail.count) lines)\n" + tail.joined(separator: "\n") + "\n"
        }
        return out
    }

    /// Writes the report to a file in Bug Reports for sharing.
    @MainActor
    func reportFile(whatHappened: String) -> URL? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = "BreakBoss bug report \(f.string(from: Date())).txt"
        let url = folder.appendingPathComponent(name)
        do { try report(whatHappened: whatHappened).write(to: url, atomically: true, encoding: .utf8) } catch { return nil }
        return url
    }
}

// MARK: - MENU › Bug report

struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var what = ""
    @State private var preview = ""
    @State private var copied = false
    @State private var sharing: SharedReport?

    private struct SharedReport: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationView {
            Form {
                if let crash = BugLog.shared.lastCrash {
                    Section {
                        Text(crash.split(separator: "\n").prefix(4).joined(separator: "\n"))
                            .font(.system(size: 12, design: .monospaced))
                    } header: {
                        Text("BreakBoss crashed last time")
                    } footer: {
                        Text("The whole crash report is in the report below. Write what you were doing, then Copy or Share.")
                    }
                } else if BugLog.shared.lastRunEndedOnScreen {
                    Section("Last run") {
                        Text("BreakBoss closed while it was on screen without a crash report: a freeze, running out of memory, or Stop in Swift Playgrounds.")
                            .font(.callout)
                    }
                }
                Section {
                    TextEditor(text: $what).frame(minHeight: 90)
                } header: {
                    Text("What happened?")
                } footer: {
                    Text("What you tapped, what you expected, and what you heard or saw. It goes at the top of the report.")
                }
                Section {
                    Button {
                        UIPasteboard.general.string = BugLog.shared.report(whatHappened: what)
                        copied = true
                    } label: {
                        Label(copied ? "Copied: paste it in the project chat" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    Button {
                        if let url = BugLog.shared.reportFile(whatHappened: what) { sharing = SharedReport(url: url) }
                    } label: {
                        Label("Share report as a file…", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        BugLog.shared.clearOldReports()
                        refresh()
                    } label: {
                        Label("Clear old reports", systemImage: "trash")
                    }
                } footer: {
                    Text("The log keeps running while you play. Reports are also saved in Files › BreakBoss › Bug Reports.")
                }
                Section("Report") {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Bug report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Refresh") { refresh() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: refresh)
        .onChange(of: what) { _ in copied = false }
        .sheet(item: $sharing) { shared in ShareSheet(items: [shared.url]) }
    }

    /// The on-screen copy shows the last 300 lines; Copy and Share send everything.
    private func refresh() {
        let lines = BugLog.shared.report(whatHappened: what).split(separator: "\n", omittingEmptySubsequences: false)
        preview = (lines.count > 300 ? ["…"] + lines.suffix(300) : Array(lines)).joined(separator: "\n")
    }
}
