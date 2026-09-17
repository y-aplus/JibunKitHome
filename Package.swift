// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JibunKit",
    platforms: [
        .iOS("26.0"),
        // Foundation-only tests run on the macOS CI host (Date.now: macOS 12).
        // App and Widget entry points remain iOS-only.
        .macOS(.v12),
    ],
    products: [
        .library(name: "JibunKitBackup", targets: ["JibunKitBackup"]),
        .library(name: "CounterIntegration", targets: ["CounterIntegration"]),
        .library(name: "ReminderIntegration", targets: ["ReminderIntegration"]),
        .library(name: "ZaikoIntegration", targets: ["ZaikoIntegration"]),
        .library(name: "JibunKitCore", targets: ["JibunKitCore"]),
        .library(name: "CounterFeature", targets: ["CounterFeature"]),
        .library(name: "ReminderFeature", targets: ["ReminderFeature"]),
    ],
    dependencies: [
        .package(path: "Modules/Records"),
        .package(path: "Modules/Zaiko"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .executableTarget(name: "SharedStateProcessProbe", dependencies: ["JibunKitCore"],
                          path: "Tests/SharedStateProcessProbe"),
        .executableTarget(name: "IncomingProcessProbe", dependencies: ["JibunKitCore"],
                          path: "Tests/IncomingProcessProbe"),
        .target(name: "JibunKitBackup", dependencies: ["JibunKitCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")], resources: [.copy("Resources/ZIPFoundation-LICENSE.txt")]),
        .testTarget(name: "JibunKitBackupTests", dependencies: ["JibunKitBackup", "JibunKitCore", "RecordsBackupIntegration", .product(name: "RecordsFeature", package: "Records"), .product(name: "ZIPFoundation", package: "ZIPFoundation")]),
        .target(
            name: "RecordsBackupIntegration",
            dependencies: ["JibunKitCore", .product(name: "RecordsFeature", package: "Records")],
            path: "Modules/Records/Integration",
            exclude: ["RecordsMiniApp.swift"],
            sources: ["RecordsBackup.swift", "RecordsNotifications.swift"]
        ),
        .testTarget(
            name: "RecordsBackupIntegrationTests",
            dependencies: ["RecordsBackupIntegration", "JibunKitCore", .product(name: "RecordsFeature", package: "Records")]
        ),
        .target(name: "CounterIntegration", dependencies: ["CounterFeature", "JibunKitCore"],
                exclude: ["AppShortcuts.swift.fragment"]),
        .target(name: "ReminderIntegration", dependencies: ["ReminderFeature", "JibunKitCore"]),
        .target(
            name: "ZaikoIntegration",
            dependencies: ["JibunKitCore", .product(name: "ZaikoFeature", package: "Zaiko")],
            path: "Modules/Zaiko/Integration"
        ),
        .target(
            name: "JibunKitCore"
        ),
        .target(
            name: "CounterFeature",
            dependencies: ["JibunKitCore"]
        ),
        .target(
            name: "ReminderFeature",
            dependencies: ["JibunKitCore"]
        ),
        .testTarget(
            name: "CounterFeatureTests",
            dependencies: ["CounterFeature"]
        ),
        .testTarget(
            name: "JibunKitCoreTests",
            dependencies: ["JibunKitCore"]
        ),
        .testTarget(
            name: "MiniAppIntegrationTests",
            dependencies: ["JibunKitCore", "CounterFeature", "ReminderFeature"]
        ),
    ]
)
