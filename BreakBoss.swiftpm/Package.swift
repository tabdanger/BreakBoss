// swift-tools-version: 5.9
// Copyright © 2026 Tyrone Dangerfield. All rights reserved.

import PackageDescription
import AppleProductTypes

// Universal standalone iPhone and iPad app for iOS 16 and later.
// The repository's Xcode targets additionally build the existing AUv3 extension.
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
            displayVersion: "0.4.0",
            bundleVersion: "10",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.red),
            supportedDeviceFamilies: [.phone, .pad],
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
