// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI

@main
struct BreakBossApp: App {
    init() {
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

    var body: some View {
        FaceplateView(controller: controller)
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .preferredColorScheme(.dark)
            .onAppear {
                AppAudioHost.shared.start()
                if ProcessInfo.processInfo.environment["BREAKBOSS_SNAPSHOTS"] == "1" {
                    let c = controller
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        LayoutSnapshots.write(c)
                    }
                }
            }
    }
}

/// Build-machine only (BREAKBOSS_SNAPSHOTS=1): draws the faceplate in each mode at its full
/// landscape size into Library/Caches, so every build can be checked against the approved art.
enum LayoutSnapshots {
    @MainActor
    static func write(_ controller: KnockController) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let start = controller.mode
        FaceplateView.snapshotMode = true
        defer { FaceplateView.snapshotMode = false }
        for mode in SoundMode.allCases {
            controller.selectMode(mode)
            for play in [PlayMode.loop, .oneShot] {
                controller.selectPlayMode(play)
                controller.readout = nil
                let view = FaceplateView(controller: controller).frame(width: 1448, height: 1086)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 1
                if let image = renderer.uiImage, let data = image.pngData() {
                    let name = "layout-\(mode.assetSuffix)-\(play == .loop ? "loop" : "oneshot").png"
                    try? data.write(to: caches.appendingPathComponent(name))
                }
            }
        }
        controller.selectPlayMode(.loop)
        controller.selectMode(start)
        print("BreakBoss layout snapshots written")
    }
}
