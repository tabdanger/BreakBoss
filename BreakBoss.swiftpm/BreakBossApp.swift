// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UIKit

@main
struct BreakBossApp: App {
    init() {
        BugCatcher.install()
        if ProcessInfo.processInfo.environment["BREAKBOSS_SELFTEST"] == "1" {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) { KnockSelfTest.run() }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @ObservedObject private var controller = AppAudioHost.shared.controller
    @Environment(\.scenePhase) private var scenePhase
    @State private var crashReport = false

    var body: some View {
        FaceplateView(controller: controller)
            .ignoresSafeArea(.container, edges: .all)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .preferredColorScheme(.dark)
            .onAppear {
                AppAudioHost.shared.start()
                // After a crash, the report opens by itself so the details get sent back.
                if BugLog.shared.lastCrash != nil { crashReport = true }
                if ProcessInfo.processInfo.environment["BREAKBOSS_SNAPSHOTS"] == "1" {
                    let c = controller
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        LayoutSnapshots.write(c)
                    }
                }
            }
            .sheet(isPresented: $crashReport) { BugReportView() }
            .onChange(of: scenePhase) { phase in
                BugLog.shared.note("App \(phase == .active ? "on screen" : phase == .background ? "in the background" : "inactive")")
                if phase != .inactive { BugLog.shared.setOnScreen(phase == .active) }
            }
            .onReceive(controller.$notice) { notice in
                if let notice { BugLog.shared.note("Notice on screen: " + notice) }
            }
            .onChange(of: controller.state.presetName) { BugLog.shared.note("Preset: " + $0) }
            .onChange(of: controller.state.kitID) { BugLog.shared.note("Kit: " + $0) }
            .onChange(of: controller.mode) { BugLog.shared.note("Mode: \($0.title)") }
    }
}

/// Build-machine only (BREAKBOSS_SNAPSHOTS=1): renders both approved device layouts.
enum LayoutSnapshots {
    @MainActor
    static func write(_ controller: KnockController) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let start = controller.mode
        FaceplateView.snapshotMode = true
        defer { FaceplateView.snapshotMode = false }
        for device in [FaceplateLayout.Device.tablet] {
            let size = CGSize(width: 1450, height: 1085)
            for mode in SoundMode.allCases {
                controller.selectMode(mode)
                for play in [PlayMode.loop, .oneShot] {
                    controller.selectPlayMode(play)
                    controller.readout = nil
                    let view = FaceplateView(controller: controller, deviceOverride: device)
                        .frame(width: size.width, height: size.height)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    if let image = renderer.uiImage, let data = image.pngData() {
                        let name = "layout-\(device.rawValue)-\(mode.assetSuffix)-\(play == .loop ? "loop" : "oneshot").png"
                        try? data.write(to: caches.appendingPathComponent(name))
                    }
                }
            }
        }
        controller.selectPlayMode(.loop)
        controller.selectMode(start)
        print("BreakBoss layout snapshots written")
    }
}
