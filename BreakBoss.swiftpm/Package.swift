// swift-tools-version: 5.9
// Copyright © 2026 Tyrone Dangerfield. All rights reserved.

import PackageDescription
import AppleProductTypes

// BreakBoss runs on iPad, iPadOS 16.0 and later. The same code is also built as an AUv3
// instrument on GitHub (see xcode/ and AUv3/ at the top of the repository).
let package = Package(
    name: "BreakBoss",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "BreakBoss",
            targets: ["AppModule"],
            bundleIdentifier: "com.tabdanger.BreakBoss",
            displayVersion: "0.1.0",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.red),
            supportedDeviceFamilies: [.pad],
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft,
                .portrait,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            appCategory: .music,
            additionalInfoPlistContentFilePath: "Info.plist"
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            exclude: [
                "README.md",
                "Info.plist"
            ],
            resources: [.process("Resources")]
        )
    ]
)
