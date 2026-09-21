// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpotAlias",
    platforms: [.iOS("26.0"), .macOS(.v12)],
    products: [
        .library(name: "SpotAliasFeature", targets: ["SpotAliasFeature"]),
    ],
    targets: [
        .target(
            name: "SpotAliasFeature"
        ),
        .testTarget(
            name: "SpotAliasFeatureTests",
            dependencies: ["SpotAliasFeature"]
        ),
    ]
)
