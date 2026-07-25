// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RailAngyerCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RailAngyerCore", targets: ["RailAngyerCore"])
    ],
    targets: [
        .target(
            name: "RailAngyerCore",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "RailAngyerCoreTests",
            dependencies: ["RailAngyerCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
