// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
import SwiftUI
import UIKit

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

/// Build-machine only: retain the instrument snapshots and exercise the new rack in both
/// orientations. The rack uses a loaded inventory so a snapshot never captures a loading row.
enum LayoutSnapshots {
    @MainActor
    static func write(_ controller: KnockController) {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let start = controller.mode
        FaceplateView.snapshotMode = true
        defer { FaceplateView.snapshotMode = false }
        for device in [FaceplateLayout.Device.tablet, .phone] {
            let size = device == .phone ? CGSize(width: 941, height: 1672) : CGSize(width: 1448, height: 1086)
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
        let library = RackSoundLibrary(preloadedSounds: StockSampleLibrary.bundled.librarySounds())
        let layouts: [(String, CGSize)] = [
            ("phone-portrait", CGSize(width: 590, height: 1280)),
            ("phone-landscape", CGSize(width: 1280, height: 590)),
            ("tablet-portrait", CGSize(width: 1086, height: 1448)),
            ("tablet-landscape", CGSize(width: 1448, height: 1086))
        ]
        for (name, size) in layouts {
            let view = DrumRollView(controller: controller, loop: 0, library: library)
                .frame(width: size.width, height: size.height)
                .environment(\.horizontalSizeClass, size.width < 700 ? .compact : .regular)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            if let image = renderer.uiImage, let data = image.pngData() {
                try? data.write(to: caches.appendingPathComponent("rack-\(name).png"))
            }
        }
        print("BreakBoss layout snapshots written")
    }
}
