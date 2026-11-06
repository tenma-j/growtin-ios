// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrowtinCore",
    defaultLocalization: "fr",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "GrowtinCore", targets: ["GrowtinCore"])
    ],
    targets: [
        .target(
            name: "GrowtinCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GrowtinCoreTests",
            dependencies: ["GrowtinCore"]
        )
    ]
)
