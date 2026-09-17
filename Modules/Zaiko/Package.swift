// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Zaiko",
    platforms: [.iOS("26.0"), .macOS(.v12)],
    products: [.library(name: "ZaikoFeature", targets: ["ZaikoFeature"])],
    targets: [.target(name: "ZaikoFeature"),
              .testTarget(name: "ZaikoFeatureTests", dependencies: ["ZaikoFeature"])]
)
